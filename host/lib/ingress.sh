# shellcheck shell=sh
# ingress provider 감시 — 계약: .docs/phases/phase-2/03-deploy-and-ingress-contract.md "2. ingress provider 계약"
# config.sh · policy.sh · supervisor.sh 다음에 source한다.
#
# provider = $NIMWAKE_INGRESS_DIR/<name>/{check,install,run,health}. host.conf NIMWAKE_INGRESS=<name>로 켠다.
# supervisor가 nimwaked와 **따로** run을 띄우고 감시한다 — ingress가 죽어도 daemon은 그대로, 반대도 그대로.
#   run이 끝나면 재기동 (backoff · crash loop — daemon과 같은 policy, PRD §23–§24)
#   run의 종료 코드 78 = 설정 오류 → 재기동하지 않는다 (Core §74와 같은 규칙)
#   check가 실패하면 시작하지 않는다 (토큰 없음 등) → UNHEALTHY
# 상태는 run/ingress 한 줄 "STATE YYYY-MM-DD HH:MM:SS 이유", 출력은 logs/ingress.log.
# 비밀은 $NIMWAKE_SECRETS(0700)에만 — provider가 읽는다. 이 파일은 비밀을 읽지도 남기지도 않는다 (PRD §40)

ingress_enabled() {
	[ -n "$NIMWAKE_INGRESS" ]
}

ingress_set_state() {
	printf '%s %s %s\n' "$1" "$(date '+%Y-%m-%d %H:%M:%S')" "$2" >"$NIMWAKE_RUN/ingress"
	host_log "ingress $1${2:+ — $2}"
}

# 공개할 hostname = manifest들의 [server] host (공백 구분)
ingress_hosts() {
	sed -n 's/^host = "\(.*\)"/\1/p' "$NIMWAKE_MANIFESTS"/*/nimwake.toml 2>/dev/null | tr '\n' ' ' | sed 's/ $//'
}

# provider 스크립트를 계약의 환경으로 부른다
ingress_call() {
	NIMWAKE_GATEWAY="$NIMWAKE_GATEWAY" \
		NIMWAKE_INGRESS_HOSTS="$(ingress_hosts)" \
		NIMWAKE_SECRETS="$NIMWAKE_SECRETS" \
		NIMWAKE_LOGS="$NIMWAKE_LOGS" \
		"$NIMWAKE_INGRESS_DIR/$NIMWAKE_INGRESS/$1"
}

ingress_pid() {
	_ipid="$(cat "$NIMWAKE_RUN/ingress.pid" 2>/dev/null || true)"
	[ -n "$_ipid" ] && kill -0 "$_ipid" 2>/dev/null && echo "$_ipid"
}

# 네트워크가 돌아왔을 때 (#31) — 지금 run을 내리면 감시 루프가 backoff 없이 다시 띄운다
ingress_restart() {
	ingress_enabled || return 0
	_ipid="$(ingress_pid)" || return 0
	: >"$NIMWAKE_RUN/ingress-restart"
	kill -TERM "$_ipid" 2>/dev/null || true
	host_log "ingress: restarting $NIMWAKE_INGRESS (network recovered)"
}

# supervisor가 끝날 때 · nimwake-host stop
ingress_stop() {
	: >"$NIMWAKE_RUN/ingress-stop"
	_ipid="$(ingress_pid)" || return 0
	kill -TERM "$_ipid" 2>/dev/null || true
}

# 감시 루프. supervisor가 백그라운드로 띄운다. 0: 멈춤 요청으로 끝 · 1: UNHEALTHY
supervise_ingress() {
	ingress_enabled || return 0
	rm -f "$NIMWAKE_RUN/ingress-stop" "$NIMWAKE_RUN/ingress-restart"
	mkdir -p "$NIMWAKE_SECRETS"
	chmod 700 "$NIMWAKE_SECRETS"
	if [ ! -x "$NIMWAKE_INGRESS_DIR/$NIMWAKE_INGRESS/run" ]; then
		ingress_set_state UNHEALTHY "provider '$NIMWAKE_INGRESS' is not installed in $NIMWAKE_INGRESS_DIR — make deploy"
		return 1
	fi
	_irestarts=""
	while :; do
		[ -f "$NIMWAKE_RUN/ingress-stop" ] && break
		if ! _iwhy="$(ingress_call check 2>&1)"; then
			ingress_set_state UNHEALTHY "check failed: $(printf '%s' "$_iwhy" | tail -n 1)"
			return 1
		fi
		ingress_call run >>"$NIMWAKE_LOGS/ingress.log" 2>&1 &
		_ichild=$!
		echo "$_ichild" >"$NIMWAKE_RUN/ingress.pid"
		ingress_set_state RUNNING "$NIMWAKE_INGRESS pid $_ichild → $NIMWAKE_GATEWAY for $(ingress_hosts)"
		_icode=0
		wait "$_ichild" || _icode=$?
		rm -f "$NIMWAKE_RUN/ingress.pid"

		[ -f "$NIMWAKE_RUN/ingress-stop" ] && break
		if [ -f "$NIMWAKE_RUN/ingress-restart" ]; then
			rm -f "$NIMWAKE_RUN/ingress-restart"
			continue
		fi
		if [ "$_icode" -eq 78 ]; then
			ingress_set_state UNHEALTHY "configuration error (exit 78) — see logs/ingress.log"
			return 1
		fi
		_inow="$(date +%s)"
		# shellcheck disable=SC2086 # 목록을 인자로 나눈다
		_irestarts="$(policy_prune "$_inow" "$NIMWAKE_RESTART_WINDOW" $_irestarts)"
		_icount="$(policy_count "$_irestarts")"
		if policy_crash_loop "$_icount" "$NIMWAKE_MAX_RESTARTS"; then
			ingress_set_state UNHEALTHY "crash loop: $_icount restarts within ${NIMWAKE_RESTART_WINDOW}s, last exit $_icode"
			return 1
		fi
		_irestarts="${_irestarts:+$_irestarts }$_inow"
		_idelay="$(policy_backoff $((_icount + 1)))"
		ingress_set_state BACKOFF "exit $_icode — restart $((_icount + 1)) in ${_idelay}s"
		_ileft="$_idelay"
		while [ "$_ileft" -gt 0 ] && [ ! -f "$NIMWAKE_RUN/ingress-stop" ]; do
			sleep 1
			_ileft=$((_ileft - 1))
		done
	done
	ingress_set_state STOPPED "stop requested"
	rm -f "$NIMWAKE_RUN/ingress-stop"
	return 0
}
