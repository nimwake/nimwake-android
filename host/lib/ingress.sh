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
	# 공개 URL이 끊긴 채 다시 붙지 않는다
	if [ "$1" = UNHEALTHY ]; then
		alert ingress "ingress $NIMWAKE_INGRESS UNHEALTHY — $2"
	fi
}

# 앱의 노출 선언 — $NIMWAKE_APP_HOME/<name>/exposure. 없거나 모르는 값이면 lan (안전한 쪽, Phase 2 04)
app_exposure() {
	case "$(cat "$NIMWAKE_APP_HOME/$1/exposure" 2>/dev/null)" in
	public) echo public ;;
	*) echo lan ;;
	esac
}

# 공개할 hostname = exposure가 public인 앱들의 [server] host (공백 구분). LAN 앱은 provider에 넘기지 않는다
ingress_hosts() {
	for _m in "$NIMWAKE_MANIFESTS"/*/nimwake.toml; do
		[ -f "$_m" ] || continue
		_app="$(basename "$(dirname "$_m")")"
		[ "$(app_exposure "$_app")" = public ] || continue
		sed -n 's/^host = "\(.*\)"/\1/p' "$_m"
	done | tr '\n' ' ' | sed 's/ $//'
}

# provider 스크립트를 계약의 환경으로 부른다.
# host.conf는 셸 변수로만 읽힌다(export 아님) — provider별 설정(NIMWAKE_INGRESS_CF_MODE 등)을 별도 프로세스인
# provider가 받으려면 내보내야 한다. 빠뜨렸을 때 quick 모드가 token 모드로 돌았다 (10-14 기기)
#
# ingress_exec는 지금 셸을 provider로 **바꾼다** — 이미 갈라진 셸(`&` · `$( )`) 안에서만 부른다.
# run을 `ingress_exec run &`로 띄우면 $!가 곧 provider(cloudflared)의 pid다. 서브셸을 한 겹 더 두면 $!는
# 바깥 서브셸이 되고, 그것을 죽여도 provider는 고아로 남아 port를 붙잡는다 (10-14 기기에서 실제로)
ingress_exec() {
	for _iv in $(set | sed -n 's/^\(NIMWAKE_INGRESS_[A-Z0-9_]*\)=.*/\1/p'); do
		export "${_iv?}"
	done
	NIMWAKE_GATEWAY="$NIMWAKE_GATEWAY" \
		NIMWAKE_INGRESS_HOSTS="$(ingress_hosts)" \
		NIMWAKE_SECRETS="$NIMWAKE_SECRETS" \
		NIMWAKE_LOGS="$NIMWAKE_LOGS" \
		exec "$NIMWAKE_INGRESS_DIR/$NIMWAKE_INGRESS/$1"
}

# 끝나기를 기다리는 호출 (check · health · install)
ingress_call() {
	(ingress_exec "$1")
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
	# 인터넷이 닿기 시작한다 — 위험한 구성은 남겨 둔다 (Phase 2 04)
	if [ "$NIMWAKE_ISOLATED" != 1 ]; then
		host_log "ingress: WARNING NIMWAKE_ISOLATED=$NIMWAKE_ISOLATED — apps can read and write Termux files (SSH keys, boot scripts). Set 1 (T1)"
	fi
	if [ -z "$(ingress_hosts)" ]; then
		host_log "ingress: WARNING no app declares exposure=public — the provider gets no hosts (a token tunnel still routes whatever the Cloudflare dashboard says)"
	fi
	_irestarts=""
	while :; do
		[ -f "$NIMWAKE_RUN/ingress-stop" ] && break
		if ! _iwhy="$(ingress_call check 2>&1)"; then
			ingress_set_state UNHEALTHY "check failed: $(printf '%s' "$_iwhy" | tail -n 1)"
			return 1
		fi
		# `&`가 이미 셸을 가른다 — 그 셸이 provider로 바뀌므로 $!가 provider의 pid다
		ingress_exec run >>"$NIMWAKE_LOGS/ingress.log" 2>&1 &
		_ichild=$!
		echo "$_ichild" >"$NIMWAKE_RUN/ingress.pid"
		_ihosts="$(ingress_hosts)"
		ingress_set_state RUNNING "$NIMWAKE_INGRESS pid $_ichild → $NIMWAKE_GATEWAY for ${_ihosts:-no public app}"
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
