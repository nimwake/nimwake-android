#!/bin/sh
# A2 — 실기기에서 supervisor가 nimwaked를 복구하는지 본다. (PRD §23–§24, MVP [3])
#
#   1. kill -9 nimwaked → supervisor가 재기동 → RUNNING · health 404 → lifecycle
#   2. 설정 오류(빈 apps 디렉터리) → nimwaked 78 → 재기동하지 않고 UNHEALTHY
#      proot-distro가 nimwaked의 종료 코드를 그대로 돌려주는지가 여기서 드러난다
#   3. nimwake-host stop → supervisor · nimwaked · application 잔존 0
#
# 끝나면 supervisor를 정상 설정으로 다시 띄워 둔다.
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

root="$(cd "$(dirname "$0")/../.." && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

on_device() {
	ssh "$device" "$@"
}

state() {
	on_device "cut -d' ' -f1 \$HOME/.nimwake-host/run/state 2>/dev/null" || true
}

# wait_state STATE SECONDS
wait_state() {
	_i=0
	while [ "$(state)" != "$1" ]; do
		[ "$_i" -ge "$2" ] && return 1
		sleep 1
		_i=$((_i + 1))
	done
}

daemon_pid() {
	on_device "pgrep -f '^/opt/nimwake/bin/nimwaked' | head -n 1" || true
}

echo "== 1. kill -9 → restart"
on_device "nimwake-host stop >/dev/null; nimwake-host start"
wait_state RUNNING 60 || fail "supervisor did not reach RUNNING"
before="$(daemon_pid)"
[ -n "$before" ] || fail "no nimwaked pid"
echo "ok  RUNNING  nimwaked pid=$before"

on_device "kill -9 $before"
killed_at="$(date +%s)"
wait_state BACKOFF 15 || true
wait_state RUNNING 60 || fail "nimwaked was not restarted"
after="$(daemon_pid)"
[ "$after" != "$before" ] || fail "pid did not change ($after)"
echo "ok  restarted  pid=$before → $after  in $(($(date +%s) - killed_at))s"
on_device "grep -E 'exit [0-9]+' \$HOME/.nimwake-host/logs/supervisor.log | tail -n 1"
"$root/tests/device/lifecycle.sh"

echo "== 2. configuration error (78) → UNHEALTHY, no restart"
on_device "nimwake-host stop >/dev/null; \
	proot-distro login ubuntu -- mkdir -p /tmp/nimwake-empty-apps; \
	NIMWAKE_APPS=/tmp/nimwake-empty-apps nimwake-host start"
if ! wait_state UNHEALTHY 60; then
	on_device "nimwake-host status; tail -n 5 \$HOME/.nimwake-host/logs/supervisor.log"
	fail "expected UNHEALTHY — does proot-distro return nimwaked's exit code?"
fi
on_device "cut -d' ' -f4- \$HOME/.nimwake-host/run/state"
on_device "grep -q 'exit 78' \$HOME/.nimwake-host/run/state" || fail "state does not mention exit 78"
echo "ok  UNHEALTHY on exit 78"

echo "== 3. stop leaves nothing behind"
on_device "nimwake-host start >/dev/null"
wait_state RUNNING 60 || fail "supervisor did not come back with the normal config"
on_device "curl -s -o /dev/null -H 'Host: echo.local' http://127.0.0.1:8080/"
on_device "nimwake-host stop"
left="$(on_device "pgrep -f '^/opt/nimwake/bin/|nimwake-host __supervise' || true")"
[ -z "$left" ] || fail "left behind: $left"
echo "ok  nothing left after stop"

on_device "nimwake-host start >/dev/null"
wait_state RUNNING 60 || fail "could not restore the supervisor"
echo "PASS recovery"
