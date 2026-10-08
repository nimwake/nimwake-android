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
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

root="$(cd "$(dirname "$0")/../.." && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

echo "== last boot (~/.nimwake-host/logs/boot.log)"
last_boot="$(ssh "$device" sh -s <<'EOF'
log="$HOME/.nimwake-host/logs/boot.log"
[ -f "$log" ] || exit 0
# 마지막 "boot: start" 이후만 출력한다. 바로 앞 줄이 같은 부팅의 sshd 줄이면 함께 보여 준다.
# 다른 실행의 줄(예: 이전 ready)이 섞이면 READY를 잘못 판정한다.
awk '/boot: start/ { buf = (prev ~ /sshd: started/) ? prev : "" }
	{ buf = buf $0 "\n"; prev = $0 "\n" }
	END { printf "%s", buf }' "$log"
EOF
)"
[ -n "$last_boot" ] || fail "boot.log is missing — 10-nimwake did not run (Termux:Boot opened once? battery restrictions?)"
printf '%s\n' "$last_boot" | sed 's/^/   /'

printf '%s\n' "$last_boot" | grep -q 'ready: health 404' ||
	fail "the last boot did not reach READY"
echo "ok  boot reached READY"

code="$(ssh "$device" "curl -s -o /dev/null -w '%{http_code}' -H 'Host: nimwake-health.invalid' http://127.0.0.1:8080/")"
[ "$code" = 404 ] || fail "health probe: expected 404, got $code"
echo "ok  health probe 404"

# 부팅 후 application은 SLEEPING이어야 한다. 이 검사는 다른 요청보다 먼저 한다.
if ssh "$device" "pgrep -f '^/opt/nimwake/bin/.*-server'" >/dev/null; then
	fail "an application is running right after boot — it should be SLEEPING"
fi
echo "ok  every application is asleep after boot"

"$root/tests/device/lifecycle.sh"
echo "PASS boot"
