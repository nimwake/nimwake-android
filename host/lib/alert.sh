# shellcheck shell=sh
# 알림 — 폰 화면(NIMWAKE_NOTIFY)과 밖(NIMWAKE_ALERT_URL), 그리고 생존 신호(NIMWAKE_HEARTBEAT_URL).
# config.sh · supervisor.sh 다음에 source한다.
#
# 폰 화면 알림만으로는 폰이 꺼졌거나 Termux가 내려간 것을 알 수 없다(10-15 · 10-18 · 10-20 기기).
#   NIMWAKE_ALERT_URL      상태가 나빠지면 POST — ntfy(text) · Discord · Slack 웹훅. URL이 곧 비밀이다(host.conf, 0600)
#   NIMWAKE_HEARTBEAT_URL  RUNNING인 동안 정리 작업 주기마다 GET — healthchecks.io · Uptime Kuma push 같은 곳.
#                          신호가 끊기면 그쪽이 알린다: 폰이 통째로 꺼진 것까지 잡는 유일한 길이다
#
# 보내기는 백그라운드다 — 감시 루프를 막지 않는다. 부팅 직후처럼 네트워크가 아직 없을 수 있어 몇 번 다시 시도한다.

# JSON 문자열 안에 넣을 수 있게 — 메시지는 한 줄이다
alert_json_escape() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr -d '\n\r'
}

alert_post() {
	_akind="$1"
	_amsg="$2"
	case "$NIMWAKE_ALERT_FORMAT" in
	discord) _abody="{\"content\":\"$(alert_json_escape "$_amsg")\"}" _atype="application/json" ;;
	slack) _abody="{\"text\":\"$(alert_json_escape "$_amsg")\"}" _atype="application/json" ;;
	*) _abody="$_amsg" _atype="text/plain; charset=utf-8" ;;
	esac
	_atry=1
	while [ "$_atry" -le "$NIMWAKE_ALERT_TRIES" ]; do
		# Title · Tags는 ntfy가 읽는다 — 다른 곳은 모르는 header로 무시한다
		if curl -fsS -m 10 -o /dev/null -H "Content-Type: $_atype" -H "Title: nimwake $_akind" -H "Tags: $_akind" \
			--data-binary "$_abody" "$NIMWAKE_ALERT_URL" 2>/dev/null; then
			return 0
		fi
		[ "$_atry" -lt "$NIMWAKE_ALERT_TRIES" ] && sleep "$NIMWAKE_ALERT_RETRY_DELAY"
		_atry=$((_atry + 1))
	done
	return 1
}

# alert KIND MESSAGE — 상태가 나빠졌을 때 (부르는 쪽이 '바뀔 때만' 부른다)
alert() {
	_kind="$1"
	_msg="$2"
	if [ -n "$NIMWAKE_NOTIFY" ]; then
		sh -c "$NIMWAKE_NOTIFY" -- "$_msg" "$_kind" >/dev/null 2>&1 || host_log "$_kind: notify failed"
	fi
	if [ -n "$NIMWAKE_ALERT_URL" ]; then
		(
			alert_post "$_kind" "[$NIMWAKE_NAME] $_msg" ||
				host_log "$_kind: alert to NIMWAKE_ALERT_URL failed after $NIMWAKE_ALERT_TRIES tries"
		) &
	fi
}

# 살아 있다는 신호 — RUNNING인 동안만 (housekeeping이 부른다). 실패는 남기기만 한다
heartbeat_ping() {
	[ -n "$NIMWAKE_HEARTBEAT_URL" ] || return 0
	(
		curl -fsS -m 10 -o /dev/null "$NIMWAKE_HEARTBEAT_URL" 2>/dev/null ||
			host_log "heartbeat: ping to NIMWAKE_HEARTBEAT_URL failed"
	) &
}
