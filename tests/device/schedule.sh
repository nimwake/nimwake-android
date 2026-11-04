#!/bin/sh
# Core 예정된 깨움(§89)이 제때 도는가 — 매분 일정을 걸어 두고 실제 횟수를 센다. (#95, validation/19)
#
#   schedule.sh start    시험 앱 schedprobe를 배포한다 (* * * * *, 매분 깨워 / 를 요청). 시작 시각을 남긴다
#   schedule.sh report   지금까지 경과한 분 대비 scheduled wake · 요청 성공 수, 가장 긴 공백, 전원 상태
#   schedule.sh stop     report 뒤 앱을 지운다
#
# 60분에 60줄이 아니면 그 차이가 Doze다 — 놓친 실행은 Core가 건너뛴다(§89). 충전기를 뺀 밤과 꽂은 밤을 따로 잰다.
# 다른 앱을 건드리지 않으므로 soak과 함께 돌려도 된다
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

root="$(cd "$(dirname "$0")/../.." && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"
state="$root/dist/schedule-start"
app=schedprobe

report() {
	[ -f "$state" ] || {
		echo "schedule: not started — schedule.sh start" >&2
		exit 1
	}
	ssh "$device" sh -s "$app" "$(cat "$state")" <<'EOF'
{
app="$1"
since="$2"
log="$HOME/.nimwake-host/logs/nimwaked.log"
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
minutes=$((($(date -u +%s) - $(date -u -d "$(echo "$since" | tr T ' ' | tr -d Z)" +%s)) / 60)) # portable-ok: 기기(Termux, GNU)에서 돈다
# 줄의 시각을 UTC 분으로 바꿔 공백을 잰다 — mawk에는 mktime이 없다
awk -v app="$app" -v since="$since" -v minutes="$minutes" '
function days(y, m, d) {
	if (m < 3) { y--; m += 12 }
	return int(365.25 * y) - int(y / 100) + int(y / 400) + int(30.6 * (m + 1)) + d
}
$1 < since { next }
index($0, "scheduled wake app=" app) || index($0, "scheduled wake app=\"" app "\"") {
	wakes++
	t = days(substr($1, 1, 4) + 0, substr($1, 6, 2) + 0, substr($1, 9, 2) + 0) * 1440 + substr($1, 12, 2) * 60 + substr($1, 15, 2)
	if (wakes > 1 && t - last > gap) { gap = t - last; gap_at = $1 }
	last = t
}
index($0, "scheduled wake did not start") && index($0, app) { failed++ }
index($0, "scheduled request") && index($0, app) {
	if ($0 ~ /status=200/) ok++
	else bad++
}
END {
	printf "window      %s → now, %d minutes\n", since, minutes
	printf "wakes       %d of %d expected — missed %d\n", wakes + 0, minutes, minutes - wakes
	printf "requests    %d ok, %d failed · did not start %d\n", ok + 0, bad + 0, failed + 0
	if (gap > 0)
		printf "longest gap %d minutes (before %s)\n", gap, gap_at
}' "$log"
bat="$(timeout 10 termux-battery-status 2>/dev/null | tr -d '\n ')" # portable-ok: 기기(Termux)에서 돈다
echo "power now   $(printf '%s' "$bat" | sed -n 's/.*"plugged":"\([A-Z_]*\)".*/\1/p') $(printf '%s' "$bat" | sed -n 's/.*"status":"\([A-Z_]*\)".*/\1/p') $(printf '%s' "$bat" | sed -n 's/.*"percentage":\([0-9]*\).*/\1/p')%"
echo "checked     $now — nimwaked.log only: a rotated log hides older lines"
} </dev/null
EOF
}

case "${1:-}" in
start)
	t="$(mktemp -d)"
	trap 'rm -rf "$t"' EXIT
	mkdir -p "$t/bundle" "$root/dist"
	echo "manifest-only — the binary is in /opt/nimwake/bin" >"$t/bundle/README"
	echo lan >"$t/exposure"
	cat >"$t/nimwake.toml" <<EOF
name = "$app"

[server]
host = "$app.local"
port = 3189

[runtime]
command = ["/opt/nimwake/bin/echo-server", "3189"]

[lifecycle]
idle_timeout_seconds = 20
startup_timeout_seconds = 10
shutdown_timeout_seconds = 5
max_pending_requests = 16

[schedule]
wake = "* * * * *"
path = "/"
EOF
	"$root/scripts/apps.sh" deploy "$t"
	date -u +%Y-%m-%dT%H:%M:%SZ >"$state"
	echo "schedule: started at $(cat "$state") — schedule.sh report, then schedule.sh stop"
	;;
report) report ;;
stop)
	report
	"$root/scripts/apps.sh" remove "$app"
	ssh "$device" 'r="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/home/nimwake"; rm -rf "$r/apps/'"$app"'" "$r/data/'"$app"'" "$r/secrets/'"$app"'"' </dev/null
	rm -f "$state"
	;;
*)
	echo "usage: schedule.sh start | report | stop" >&2
	exit 2
	;;
esac
