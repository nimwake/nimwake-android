#!/bin/sh
# A3 — 재부팅 후 사람 손 없이 READY가 됐는지 본다. (PRD §10, §44-1, §44-5)
#
# 기기를 재부팅하고, 잠금이 있으면 잠금만 풀고 Termux는 열지 않는다.
# 개발 머신에서 ssh가 붙으면 실행한다.
#
#   1. 마지막 부팅의 boot.log가 `ready: health 404`로 끝났다
#   2. 지금 health probe가 404다
#   3. 부팅 직후 application은 하나도 떠 있지 않다 (모두 SLEEPING)
#   4. lifecycle 시나리오가 통과한다
#   NIMWAKE_DEVICE     ssh 대상 (기본 nimwake-phone)
#   NIMWAKE_BOOT_WAIT  부팅이 아직 진행 중이면 끝날 때까지 기다릴 초 (기본 100 — 10-nimwake의 READY 대기 90초보다 길게)
#   NIMWAKE_BOOT_FRESH READY 뒤 몇 초까지를 "부팅 직후"로 보는지 (기본 300) — 그 뒤엔 SLEEPING 검사를 건너뛴다
set -eu

root="$(cd "$(dirname "$0")/../.." && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"
boot_wait="${NIMWAKE_BOOT_WAIT:-100}"
boot_fresh="${NIMWAKE_BOOT_FRESH:-300}"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

read_last_boot() {
	ssh "$device" sh -s <<'EOF'
log="$HOME/.nimwake-host/logs/boot.log"
[ -f "$log" ] || exit 0
# 마지막 "boot: start" 이후만 출력한다. 바로 앞 줄이 같은 부팅의 sshd 줄이면 함께 보여 준다.
# 다른 실행의 줄(예: 이전 ready)이 섞이면 READY를 잘못 판정한다.
awk '/boot: start/ { buf = (prev ~ /sshd: started/) ? prev : "" }
	{ buf = buf $0 "\n"; prev = $0 "\n" }
	END { printf "%s", buf }' "$log"
EOF
}

# 10-nimwake가 끝났다는 줄 — READY · 이미 실행 중 · UNHEALTHY · TIMEOUT · 미설치
boot_finished() {
	printf '%s\n' "$1" | grep -qE 'ready: (health 404|TIMEOUT)|already running|UNHEALTHY|not installed'
}

echo "== last boot (~/.nimwake-host/logs/boot.log)"
# sshd(00-sshd)는 10-nimwake와 거의 같이 뜬다. ssh가 붙자마자 돌리면 READY 2초 전에 판정할 수 있다 —
# 2026-10-12 재부팅에서 실제로 그렇게 FAIL했다. 부팅이 진행 중이면 끝날 때까지 기다린다.
waited=0
last_boot="$(read_last_boot)"
while [ -n "$last_boot" ] && ! boot_finished "$last_boot" && [ "$waited" -lt "$boot_wait" ]; do
	[ "$waited" -eq 0 ] && echo "..  boot still in progress — waiting up to ${boot_wait}s"
	sleep 2
	waited=$((waited + 2))
	last_boot="$(read_last_boot)"
done
[ -n "$last_boot" ] || fail "boot.log is missing — 10-nimwake did not run (Termux:Boot opened once? battery restrictions?)"
printf '%s\n' "$last_boot" | sed 's/^/   /'

printf '%s\n' "$last_boot" | grep -q 'ready: health 404' ||
	fail "the last boot did not reach READY"
echo "ok  boot reached READY"

code="$(ssh "$device" "curl -s -o /dev/null -w '%{http_code}' -H 'Host: nimwake-health.invalid' http://127.0.0.1:8080/")"
[ "$code" = 404 ] || fail "health probe: expected 404, got $code"
echo "ok  health probe 404"

# 부팅 후 application은 SLEEPING이어야 한다. 이 검사는 다른 요청보다 먼저 한다.
# 부팅 직후에만 뜻이 있다 — soak sampler는 5분마다 app을 깨우고(깨어 있는 창 약 10초), 시간이 지나면
# 다른 요청도 깨운다. 그때 돌리면 정상인데도 FAIL한다 (10-12 실제로, validation/09). 그 경우는 건너뛰고 알린다.
since_ready="$(ssh "$device" sh -s <<'EOF'
{
ts="$(grep 'ready: health 404' "$HOME/.nimwake-host/logs/boot.log" 2>/dev/null | tail -n 1 | cut -c1-19)"
[ -n "$ts" ] && echo $(($(date +%s) - $(date -d "$ts" +%s))) # portable-ok: 기기(Termux, GNU)에서 돈다
} </dev/null
EOF
)"
if soak="$("$root/scripts/device-status.sh" --soak-running)"; then
	echo "--  skip 'asleep after boot': a soak is running ($soak) — its sampler wakes the application"
elif [ -n "$since_ready" ] && [ "$since_ready" -gt "$boot_fresh" ]; then
	echo "--  skip 'asleep after boot': READY was ${since_ready}s ago (> ${boot_fresh}s) — not right after boot"
elif ssh "$device" "pgrep -f '^/opt/nimwake/bin/.*-server'" >/dev/null; then
	fail "an application is running right after boot — it should be SLEEPING"
else
	echo "ok  every application is asleep after boot"
fi

"$root/tests/device/lifecycle.sh"
echo "PASS boot"
