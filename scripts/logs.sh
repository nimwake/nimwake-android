#!/bin/sh
# 폰의 로그를 개발 머신에서. 앱을 주면 그 앱의 출력(stdout · stderr)과 Core가 남긴 그 앱의 사건만.
#
#   logs.sh            supervisor.log · nimwaked.log 끝 (nimwake-host logs)
#   logs.sh APP        APP의 줄만 — "시각  out|err|core  내용" (시각은 UTC)
#
#   LINES=100   몇 줄 (기본 100)
#   FOLLOW=1    그 뒤로 새 줄을 따라간다 (Ctrl-C로 끝)
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
#
# 앱 출력은 Core가 nimwaked.log에 `… app=NAME process=proc#N stream="stdout"`로 남긴다 — 그것을 고른다
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"
app="${1:-}"
lines="${LINES:-100}"
follow="${FOLLOW:-}"

case "$lines" in
'' | *[!0-9]*)
	echo "logs: LINES must be a number" >&2
	exit 2
	;;
esac
case "$app" in
*[!a-z0-9-]*)
	echo "logs: app names are lowercase letters, digits and '-'" >&2
	exit 2
	;;
esac

if [ -z "$app" ]; then
	exec ssh "$device" "nimwake-host logs $lines" </dev/null
fi

# 기기에서 도는 부분 (따옴표 없는 heredoc이 아니다 — $는 기기에서 푼다). 앱 이름은 위에서 [a-z0-9-]로 확인했다
ssh "$device" sh -s -- "$app" "$lines" "$follow" <<'EOF'
log="$HOME/.nimwake-host/logs/nimwaked.log"
app="$1"; lines="$2"; follow="$3"
[ -f "$log" ] || { echo "logs: no $log" >&2; exit 1; }
# 시각 · 종류 · 내용으로 — tracing의 수준 · 모듈과 줄 끝의 app= · process= · stream= 꼬리를 뗀다
pick() {
	grep --line-buffered -E "app=\"?$app\"?( |$)" | awk '
	{
		t = substr($1, 1, 10) " " substr($1, 12, 8) "Z"
		kind = "core"
		if ($0 ~ /stream="stdout"$/) kind = "out"
		else if ($0 ~ /stream="stderr"$/) kind = "err"
		msg = $0
		sub(/^[^ ]+ +[A-Z]+ +[^ ]+ /, "", msg)
		sub(/ app="?[a-z0-9-]+"? process=[^ ]+ stream="[a-z]+"$/, "", msg)
		sub(/ app="?[a-z0-9-]+"?/, "", msg)
		# SIGUSR1 상태 스냅샷(§79)의 앱 줄은 앱의 이야기가 아니다
		if (msg ~ /^ +app host=/) next
		printf "%s %-4s  %s\n", t, kind, msg
		fflush()
	}'
}
out="$(tail -n 20000 "$log" | pick | tail -n "$lines")"
if [ -n "$out" ]; then
	printf '%s\n' "$out"
else
	echo "logs: nothing for $app in the last 20000 lines of nimwaked.log — is the name right? (make apps)" >&2
fi
if [ "$follow" = 1 ]; then
	echo "-- following (Ctrl-C to stop)" >&2
	# 로그 순환은 copytruncate다 — -F가 잘린 파일을 다시 따라간다
	tail -n 0 -F "$log" 2>/dev/null | pick
fi
EOF
