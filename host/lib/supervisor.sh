# shellcheck shell=sh
# nimwaked 감시 루프. (A2, PRD §8 Host Supervisor · §21 Health Model · §23–§24)
# config.sh · policy.sh 다음에 source한다.
#
#   STARTING → (health 404) → RUNNING → (exit / health 실패) → BACKOFF → STARTING …
#                                                            ↘ STOPPED   정상 종료 · stop 요청
#                                                            ↘ UNHEALTHY 설정 오류 · crash loop
#
# 판단(종료 코드 분류, backoff, crash loop)은 policy.sh에 있다. 여기는 프로세스를 다룬다.
# 상태는 run/state 한 줄 "STATE YYYY-MM-DD HH:MM:SS 이유"에 둔다. nimwake-host status가 읽는다.

host_log() {
	printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$NIMWAKE_LOGS/supervisor.log"
}

set_state() {
	printf '%s %s %s\n' "$1" "$(date '+%Y-%m-%d %H:%M:%S')" "$2" >"$NIMWAKE_RUN/state"
	host_log "state $1${2:+ — $2}"
}

# supervisor가 살아 있던 마지막 시각. 감시 주기마다 덮어쓴다 — Termux가 통째로 죽으면 아무것도 남기지 못하므로
# 다음 start가 이것으로 '언제 사라졌는가'를 안다 (10-15 기기: 로그가 종료 기록 없이 끊겼다)
heartbeat() {
	date '+%Y-%m-%d %H:%M:%S' >"$NIMWAKE_RUN/heartbeat"
}

# control socket(§85)의 디렉터리 — Core는 만들지 않는다(없으면 기동하지 않는다, 78).
# daemon이 SIGKILL로 죽으면 socket 파일이 남는다 — 기동 전(daemon이 없을 때)에 지운다
prepare_control_socket() {
	[ "$NIMWAKE_CONTROL_SOCKET" = 1 ] || return 0
	mkdir -p "$NIMWAKE_CONTROL_DIR"
	chmod 700 "$NIMWAKE_CONTROL_DIR"
	rm -f "$NIMWAKE_SOCKET"
}

# Core 상태 JSON (§86 `nimwake status --json`, contract 1). socket이 없거나 닿지 않으면 빈 값
core_status_json() {
	[ "$NIMWAKE_CONTROL_SOCKET" = 1 ] && [ -e "$NIMWAKE_SOCKET" ] && [ -x "$NIMWAKE_CORE_CLI" ] || return 1
	"$NIMWAKE_CORE_CLI" status --json --socket "$NIMWAKE_SOCKET" 2>/dev/null
}

# 이번 부팅 시각 "YYYY-MM-DD HH:MM:SS". Android는 /proc/uptime을 막는다 — `uptime -s`(sysinfo)를 쓴다
booted_at() {
	if [ -n "${NIMWAKE_BOOTED_AT:-}" ]; then
		echo "$NIMWAKE_BOOTED_AT"
	else
		uptime -s 2>/dev/null || true
	fi
}

# start 직전에 부른다 (supervisor가 없다는 것을 확인한 뒤). 이전 실행이 STOPPED · UNHEALTHY로 끝나지 않았다면
# supervisor는 종료를 기록하지 못하고 사라진 것이다. 마지막 heartbeat가 이번 부팅보다 앞이면 재부팅,
# 뒤면 폰이 켜진 채로 죽었다 — Android가 Termux를 내렸다(메모리 회수 · 배터리 · phantom process).
# supervisor.log와 run/last-unclean("시각 원인 — 설명")에 남긴다. status와 doctor가 읽는다
detect_unclean_end() {
	[ -f "$NIMWAKE_RUN/state" ] || return 0
	read -r _prev _ <"$NIMWAKE_RUN/state"
	case "$_prev" in
	STOPPED | UNHEALTHY | "") return 0 ;;
	esac
	_seen="$(cat "$NIMWAKE_RUN/heartbeat" 2>/dev/null || cut -d' ' -f2-3 "$NIMWAKE_RUN/state")"
	_boot="$(booted_at)"
	if [ -z "$_boot" ]; then
		_cause=unknown
		_why="last seen $_seen in state $_prev, boot time unknown"
	elif [ "$(printf '%s\n%s\n' "$_seen" "$_boot" | sort | head -n 1)" = "$_seen" ] && [ "$_seen" != "$_boot" ]; then
		_cause=reboot
		_why="last seen $_seen in state $_prev, phone booted at $_boot"
	else
		_cause=killed
		_why="last seen $_seen in state $_prev, phone up since $_boot — Android likely killed Termux (memory, battery, phantom process)"
	fi
	printf '%s %s — %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$_cause" "$_why" >"$NIMWAKE_RUN/last-unclean"
	host_log "previous supervisor ended without exiting ($_cause) — $_why"
	echo "nimwake-host: previous run ended without exiting ($_cause) — $_why"
}

health_probe() {
	if [ -n "$NIMWAKE_PROBE" ]; then
		sh -c "$NIMWAKE_PROBE"
		return
	fi
	[ "$(curl -s -o /dev/null -m 5 -w '%{http_code}' -H 'Host: nimwake-health.invalid' "$NIMWAKE_GATEWAY" 2>/dev/null)" = 404 ]
}

daemon_pid() {
	pgrep -f "$NIMWAKE_DAEMON_MATCH" 2>/dev/null | head -n 1
}

# daemon 자신에게 신호를 보낸다. 래퍼(proot)는 daemon이 끝나면 따라 끝난다.
daemon_signal() {
	pkill "-$1" -f "$NIMWAKE_DAEMON_MATCH" 2>/dev/null
}

stop_requested() {
	[ -f "$NIMWAKE_RUN/stop" ]
}

# 래퍼(proot)가 SIGKILL로 죽으면 nimwaked와 application이 고아로 남는다 (validation/06 E4).
# 고아 nimwaked는 proot의 syscall 변환을 잃어 I/O driver가 멈추고(ENOSYS) SIGTERM에도 반응하지 않는다.
# graceful을 기대하지 않고 정리한다. 그대로 두면 새 daemon이 port를 못 잡아 69 → crash loop가 된다.
# application은 각자 process group의 leader다(Core process_group(0)) — group 단위로 보내야 손자까지 간다.
reap_orphan_daemon() {
	_orphan="$(daemon_pid)"
	[ -n "$_orphan" ] || return 0
	_apps="$(pgrep -P "$_orphan" 2>/dev/null | tr '\n' ' ')"
	host_log "orphan nimwaked $_orphan (its wrapper is gone), application(s): ${_apps:-none} — killing them"
	for _app in $_apps; do
		kill -s TERM -- "-$_app" 2>/dev/null || kill -s TERM "$_app" 2>/dev/null || true
	done
	[ -n "$_apps" ] && sleep 3
	for _app in $_apps; do
		kill -s KILL -- "-$_app" 2>/dev/null || kill -s KILL "$_app" 2>/dev/null || true
	done
	kill -s KILL "$_orphan" 2>/dev/null || true
}

storage_free_mb() {
	df -Pk "$NIMWAKE_STORAGE_PATH" 2>/dev/null | awk 'NR == 2 { print int($4 / 1024) }'
}

# 남은 저장공간을 보고 상태가 바뀔 때만 남긴다 (PRD §18, §44-6).
# 부팅 때 한 번(10-nimwake)으로는 운영 중의 감소를 놓친다 — 72h soak에서 하룻밤에 1.1 GB가 빠졌다 (validation/10).
# 상태는 run/storage 한 줄 "ok|low FREE_MB YYYY-MM-DD HH:MM:SS"에 둔다.
#
# 부족하면 알리기 전에 Nimwake가 지워도 되는 것을 먼저 지운다 (NIMWAKE_STORAGE_CLEANUP=1, logs.sh drop_rotated_logs).
# 그것으로 기준 위로 돌아오면 알리지 않는다. 지울 수 있는 것은 순환된 로그뿐이다 — 최대 약 180 MB.
# 그 밖(Android 앱 · 사진 · app 데이터)은 Host Layer가 판단할 수 없다. 알림이 그 몫이다.
check_storage() {
	_free="$(storage_free_mb)"
	[ -n "$_free" ] || return 0
	_was=""
	if [ -f "$NIMWAKE_RUN/storage" ]; then
		_was="$(cut -d' ' -f1 "$NIMWAKE_RUN/storage")"
	fi
	if [ "$_free" -lt "$NIMWAKE_MIN_FREE_MB" ] && [ "$NIMWAKE_STORAGE_CLEANUP" = 1 ]; then
		_dropped="$(drop_rotated_logs)"
		if [ -n "$_dropped" ]; then
			host_log "storage: ${_free}MB free — removed ${_dropped% *} rotated log(s), ${_dropped#* }KB"
			_free="$(storage_free_mb)"
		fi
	fi
	_level=ok
	if [ "$_free" -lt "$NIMWAKE_MIN_FREE_MB" ]; then
		_level=low
	fi
	printf '%s %s %s\n' "$_level" "$_free" "$(date '+%Y-%m-%d %H:%M:%S')" >"$NIMWAKE_RUN/storage"
	[ "$_level" = "$_was" ] && return 0

	if [ "$_level" = low ]; then
		host_log "storage: LOW ${_free}MB free (< ${NIMWAKE_MIN_FREE_MB}MB)"
		if [ -n "$NIMWAKE_NOTIFY" ]; then
			sh -c "$NIMWAKE_NOTIFY" -- "storage low: ${_free}MB free (< ${NIMWAKE_MIN_FREE_MB}MB)" storage >/dev/null 2>&1 ||
				host_log "storage: notify failed"
		fi
	elif [ -n "$_was" ]; then
		host_log "storage: ok again ${_free}MB free"
	else
		host_log "storage: ok ${_free}MB free"
	fi
}

# RUNNING 동안 NIMWAKE_HOUSEKEEPING_INTERVAL마다 (logs.sh의 rotate_logs)
housekeeping() {
	check_storage
	check_battery
	rotate_logs
}

# 기동 직후부터 daemon이 끝날 때까지 health를 본다. 별도 subshell로 돈다.
# READY가 오지 않거나 probe가 연달아 실패하면 run/hung을 남기고 daemon을 내린다
# — 이 경우 종료 코드가 0이어도 재기동 대상이다.
monitor_daemon() {
	_waited=0
	until health_probe; do
		if [ "$_waited" -ge "$NIMWAKE_STARTUP_TIMEOUT" ]; then
			host_log "not ready after ${NIMWAKE_STARTUP_TIMEOUT}s — stopping it"
			: >"$NIMWAKE_RUN/hung"
			daemon_signal TERM
			return
		fi
		sleep 1
		_waited=$((_waited + 1))
	done
	set_state RUNNING "nimwaked pid $(daemon_pid), ready after ${_waited}s"
	heartbeat

	housekeeping
	_housekeeping_next=$(($(date +%s) + NIMWAKE_HOUSEKEEPING_INTERVAL))
	# 네트워크는 상태만 기록한다 — 끊겨도 daemon을 내리지 않는다 (PRD §13, network.sh)
	check_network
	_network_next=$(($(date +%s) + NIMWAKE_NET_INTERVAL))
	_failures=0
	while :; do
		sleep "$NIMWAKE_HEALTH_INTERVAL"
		heartbeat
		if [ "$(date +%s)" -ge "$_network_next" ]; then
			check_network
			_network_next=$(($(date +%s) + NIMWAKE_NET_INTERVAL))
		fi
		if [ "$(date +%s)" -ge "$_housekeeping_next" ]; then
			housekeeping
			_housekeeping_next=$(($(date +%s) + NIMWAKE_HOUSEKEEPING_INTERVAL))
		fi
		if health_probe; then
			_failures=0
			continue
		fi
		_failures=$((_failures + 1))
		host_log "health probe failed ($_failures/$NIMWAKE_HEALTH_FAILURES)"
		if [ "$_failures" -ge "$NIMWAKE_HEALTH_FAILURES" ]; then
			: >"$NIMWAKE_RUN/hung"
			daemon_signal TERM
			sleep "$NIMWAKE_STOP_TIMEOUT"
			daemon_signal KILL
			return
		fi
	done
}

# backoff 동안 1초마다 stop 요청을 본다. stop이면 거짓(1)을 돌려준다.
sleep_unless_stopped() {
	_left=$1
	while [ "$_left" -gt 0 ]; do
		stop_requested && return 1
		sleep 1
		_left=$((_left - 1))
	done
	! stop_requested
}

# 0: STOPPED로 끝남 · 1: UNHEALTHY로 끝남
supervise() {
	_restarts=""
	while :; do
		rm -f "$NIMWAKE_RUN/hung"
		set_state STARTING ""
		# 이전 daemon은 끝났는데 nimwaked가 남아 있다면 래퍼만 죽은 것이다
		reap_orphan_daemon
		# daemon이 없는 지금 돌리면 복사와 비우기 사이에 잃는 줄이 없다
		rotate_logs
		prepare_control_socket
		host_log "launch: $NIMWAKE_LAUNCH"
		# exec로 sh를 대체한다. wait가 받는 종료 코드는 기동 명령의 것이다.
		sh -c "exec $NIMWAKE_LAUNCH" >>"$NIMWAKE_LOGS/nimwaked.log" 2>&1 &
		_child=$!

		monitor_daemon &
		_monitor=$!

		_code=0
		wait "$_child" || _code=$?
		kill "$_monitor" 2>/dev/null
		wait "$_monitor" 2>/dev/null

		if stop_requested; then
			set_state STOPPED "stop requested (exit $_code)"
			return 0
		fi

		if [ -f "$NIMWAKE_RUN/hung" ]; then
			_decision=retry
			_why="health probe failed (exit $_code)"
		else
			_decision="$(policy_classify_exit "$_code")"
			_why="exit $_code"
		fi

		case "$_decision" in
		stopped)
			set_state STOPPED "nimwaked exited 0"
			return 0
			;;
		config)
			set_state UNHEALTHY "configuration error (exit 78) — fix it, then nimwake-host start"
			return 1
			;;
		esac

		_now="$(date +%s)"
		# shellcheck disable=SC2086 # 목록을 인자로 나눈다
		_restarts="$(policy_prune "$_now" "$NIMWAKE_RESTART_WINDOW" $_restarts)"
		_count="$(policy_count "$_restarts")"
		if policy_crash_loop "$_count" "$NIMWAKE_MAX_RESTARTS"; then
			set_state UNHEALTHY "crash loop: $_count restarts within ${NIMWAKE_RESTART_WINDOW}s, last $_why"
			return 1
		fi

		_restarts="${_restarts:+$_restarts }$_now"
		_delay="$(policy_backoff $((_count + 1)))"
		set_state BACKOFF "$_why — restart $((_count + 1)) in ${_delay}s"
		if ! sleep_unless_stopped "$_delay"; then
			set_state STOPPED "stop requested during backoff"
			return 0
		fi
	done
}
