#!/bin/sh
# 실제 앱 하나를 기기에서 잰다 — cold start · warm · RSS · 유휴 정지 · SIGUSR1 스냅샷 (#45)
#
#   app.sh HOST [ROUNDS]     예: app.sh blog.local 3   ·   app.sh echo.local 3
#
# 한 바퀴: 잠들어 있는 것을 확인 → cold 요청(Core의 queue · spawn · readiness 분해) → warm 5번 →
#          RSS → 유휴 정지를 기다리며 SIGTERM부터 프로세스가 사라질 때까지(Core는 정지 완료를 INFO로 남기지 않는다)
# 유휴 시간은 manifest의 idle_timeout_seconds다 — 바퀴마다 그만큼 걸린다 (blog 120초 → 3바퀴 약 8분).
# 운영 daemon을 쓴다. soak 중에는 거부한다 (요청이 soak 표본에 섞인다).
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

root="$(cd "$(dirname "$0")/../.." && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"
host="${1:?usage: app.sh HOST [ROUNDS]}"
rounds="${2:-3}"

if [ "${FORCE:-}" != 1 ] && why="$("$root/scripts/device-status.sh" --soak-running)"; then
	echo "app: a soak is running ($why) — requests would mix into it. FORCE=1 to override" >&2
	exit 1
fi

# 기기에서 돈다. 결과는 "key value" 줄로 낸다
ssh "$device" sh -s "$host" "$rounds" <<'EOF'
{
set -eu
host="$1"
rounds="$2"
log="$HOME/.nimwake-host/logs/nimwaked.log"
g=http://127.0.0.1:8080
# manifest는 proot Ubuntu 안에 있다 — Termux에서는 rootfs 경로로 읽는다 (proot-distro 5.x)
apps="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/home/nimwake/.nimwake/apps"
toml="$(grep -l "^host = \"$host\"" "$apps"/*/nimwake.toml | head -n 1)"
[ -n "$toml" ] || { echo "error no manifest with host $host"; exit 1; }
name="$(sed -n 's/^name = "\(.*\)"/\1/p' "$toml")"
port="$(sed -n 's/^port = \([0-9]*\)/\1/p' "$toml")"
idle="$(sed -n 's/^idle_timeout_seconds = \([0-9]*\)/\1/p' "$toml")"
echo "app $name port $port idle ${idle}s"

# app의 pid는 Core에게 묻는다 — control socket(§85 · §86, Core v0.1.2+), 없으면 SIGUSR1 상태 스냅샷(§79).
# 프로세스 이름으로 찾지 않는다: Next.js는 자기 이름을 `next-server (v…)`로 바꿔 명령줄 검색에 잡히지 않는다 (10-14 실제로)
daemon="$(pgrep -f '^/opt/nimwake/bin/nimwaked' | head -n 1)"
sock="$HOME/.nimwake-host/run/core/nimwake.sock"
cli="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/opt/nimwake/bin/nimwake"
socket_pid() {
	"$cli" status --json --socket "$sock" 2>/dev/null | tr '{' '\n' | grep "\"name\":\"$name\"" |
		sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p'
}
snapshot() {
	_n="$(wc -l <"$log")"
	kill -USR1 "$daemon"
	sleep 0.3
	tail -n +"$((_n + 1))" "$log" | grep "app app=\"$name\"" | tail -n 1
}
# 깨어 있으면 pid, 자고 있으면(pid="-") 빈 값
app_pid() {
	if [ -S "$sock" ] && [ -x "$cli" ]; then
		socket_pid
	else
		snapshot | sed -n 's/.* pid="\([0-9][0-9]*\)".*/\1/p'
	fi
}
now_ms() { echo $(($(date +%s%N) / 1000000)); } # portable-ok: 기기(Termux, GNU)에서 돈다

r=0
while [ "$r" -lt "$rounds" ]; do
	r=$((r + 1))
	# 잠들 때까지 (스냅샷이 로그에 남으므로 5초마다만 묻는다)
	i=0
	while [ -n "$(app_pid)" ] && [ "$i" -lt $((idle + 60)) ]; do sleep 5; i=$((i + 5)); done
	[ -z "$(app_pid)" ] || { echo "error round $r: still awake after $((idle + 60))s"; exit 1; }

	n0="$(wc -l <"$log")"
	cold="$(curl -s -o /dev/null -w '%{http_code} %{time_total}' -H "Host: $host" "$g/")"
	split="$(tail -n +"$((n0 + 1))" "$log" | grep "application started app=\"$name\"" | tail -n 1 | grep -o 'queue_us=[0-9]* spawn_us=[0-9]* readiness_us=[0-9]* total_us=[0-9]*')"
	echo "round $r cold $cold $split"

	warm=""
	for _ in 1 2 3 4 5; do warm="$warm $(curl -s -o /dev/null -w '%{time_total}' -H "Host: $host" "$g/")"; done
	echo "round $r warm$warm"

	p="$(app_pid)"
	rss="$(awk '/^VmRSS:/ { printf "%.1f", $2 / 1024 }' "/proc/$p/status" 2>/dev/null)"
	echo "round $r rss_mb ${rss:-NA} pid ${p:-NA}"

	if [ "$r" -eq 1 ]; then
		echo "round $r snapshot $(snapshot | sed 's/.*nimwaked: *//')"
		echo "round $r comm $(cat "/proc/$p/comm" 2>/dev/null) cmdline [$(tr '\0' ' ' <"/proc/$p/cmdline" 2>/dev/null)]"
	fi

	# 유휴 정지: Core가 "stopping application"을 남긴 순간부터 프로세스가 사라질 때까지
	n2="$(wc -l <"$log")"
	i=0
	until tail -n +"$((n2 + 1))" "$log" | grep -q "stopping application app=$name"; do
		sleep 0.2; i=$((i + 1)); [ "$i" -gt $(((idle + 30) * 5)) ] && break
	done
	t0="$(now_ms)"
	while kill -0 "$p" 2>/dev/null; do sleep 0.1; done
	# stop_ms는 0.1–0.2초 polling이라 거칠다. Core v0.1.4부터 정지 완료를 직접 남긴다(took_ms) — 그것이 기준이다
	took="$(tail -n +"$((n2 + 1))" "$log" | grep "stopped application app=$name" | tail -n 1 | sed -n 's/.*took_ms=\([0-9]*\).*/\1/p')"
	echo "round $r stop_ms $(($(now_ms) - t0)) core_took_ms ${took:-NA}"
done
grep MemAvailable /proc/meminfo | sed 's/^/mem /'
} </dev/null
EOF
