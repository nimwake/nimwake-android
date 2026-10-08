#!/bin/sh
# 실기기 lifecycle 시나리오 — cold → same PID → idle → sleep → new PID
# nimwaked가 기기에서 떠 있어야 한다 (scripts/run.sh). 요청은 기기 loopback으로 보낸다.
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
#   IDLE_WAIT       idle → sleep 대기 초 (기본 10, echo manifest idle_timeout 5s + 여유)
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"
idle_wait="${IDLE_WAIT:-10}"
gateway='http://127.0.0.1:8080/'

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

on_device() {
	ssh "$device" "$@"
}

# body(pid)와 소요 시간을 "pid seconds"로 받는다.
request() {
	on_device "curl -sS -H 'Host: echo.local' -w ' %{time_total}' $gateway"
}

alive() {
	on_device "[ -d /proc/$1 ]"
}

code="$(on_device "curl -s -o /dev/null -w '%{http_code}' -H 'Host: nimwake-health.invalid' $gateway")"
[ "$code" = 404 ] || fail "health probe: expected 404, got $code"
echo "ok  health probe 404"

# shellcheck disable=SC2046 # "pid seconds"를 두 인자로 나눈다
set -- $(request)
cold_pid="$1"
echo "ok  cold start   pid=$cold_pid  ${2}s"

# shellcheck disable=SC2046 # "pid seconds"를 두 인자로 나눈다
set -- $(request)
[ "$1" = "$cold_pid" ] || fail "warm request: expected pid $cold_pid, got $1"
echo "ok  warm         pid=$1  ${2}s  (same PID)"

alive "$cold_pid" || fail "pid $cold_pid is not visible in /proc from Termux (E1)"
echo "ok  /proc/$cold_pid visible from Termux"

echo "..  waiting ${idle_wait}s for idle → sleep"
sleep "$idle_wait"

if alive "$cold_pid"; then
	fail "pid $cold_pid still alive after ${idle_wait}s idle"
fi
echo "ok  sleep        pid=$cold_pid gone"

# shellcheck disable=SC2046 # "pid seconds"를 두 인자로 나눈다
set -- $(request)
[ "$1" != "$cold_pid" ] || fail "second cold start reused pid $cold_pid"
echo "ok  cold start   pid=$1  ${2}s  (new PID)"

echo "PASS lifecycle"
