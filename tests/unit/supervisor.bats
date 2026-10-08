#!/usr/bin/env bats
# host/bin/nimwake-host + host/lib/supervisor.sh — 가짜 daemon으로 감시 루프를 끝까지 돌린다.
# 기기 없이 개발 머신(WSL · macOS · CI)에서 돈다. 실제 proot 위의 동작은 tests/device/recovery.sh가 본다.

setup() {
	root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	host="$root/host/bin/nimwake-host"

	export FAKE_DIR="$BATS_TEST_TMPDIR/fake"
	mkdir -p "$FAKE_DIR"
	echo ok >"$FAKE_DIR/mode"

	export NIMWAKE_HOST_HOME="$BATS_TEST_TMPDIR/host"
	export NIMWAKE_HOST_LIB="$root/host/lib"
	export NIMWAKE_LAUNCH="$BATS_TEST_DIRNAME/fixtures/fake-nimwaked"
	# 테스트마다 경로가 달라 다른 테스트의 가짜 daemon을 건드리지 않는다
	export NIMWAKE_DAEMON_MATCH="fake-nimwaked"
	export NIMWAKE_PROBE="[ -f \"$FAKE_DIR/up\" ]"
	export NIMWAKE_STARTUP_TIMEOUT=5
	export NIMWAKE_HEALTH_INTERVAL=1
	export NIMWAKE_HEALTH_FAILURES=2
	export NIMWAKE_STOP_TIMEOUT=5
	export NIMWAKE_MAX_RESTARTS=5
	export NIMWAKE_RESTART_WINDOW=300
}

teardown() {
	"$host" stop >/dev/null 2>&1 || true
	pkill -f "fake-nimwaked" 2>/dev/null || true
}

state() {
	cut -d' ' -f1 "$NIMWAKE_HOST_HOME/run/state" 2>/dev/null
}

launches() {
	wc -l <"$FAKE_DIR/launches" 2>/dev/null | tr -d ' '
}

# wait_for SECONDS COMMAND... — 조건이 참이 될 때까지 기다린다
wait_for() {
	_limit=$1
	shift
	_i=0
	while ! "$@"; do
		[ "$_i" -ge $((_limit * 5)) ] && return 1
		sleep 0.2
		_i=$((_i + 1))
	done
}

state_is() { [ "$(state)" = "$1" ]; }
launched_at_least() { [ "$(launches)" -ge "$1" ]; }

@test "start → RUNNING, stop → STOPPED with nothing left" {
	run "$host" start
	[ "$status" -eq 0 ]
	wait_for 5 state_is RUNNING

	run "$host" status
	[[ "$output" == *"supervisor  running"* ]]
	[[ "$output" == *"health      OK"* ]]

	run "$host" stop
	[ "$status" -eq 0 ]
	state_is STOPPED
	! pgrep -f "fake-nimwaked"
	[ ! -f "$NIMWAKE_HOST_HOME/run/supervisor.pid" ]
}

@test "a second start does not launch a second supervisor" {
	"$host" start
	wait_for 5 state_is RUNNING
	run "$host" start
	[[ "$output" == *"already running"* ]]
	[ "$(launches)" -eq 1 ]
}

@test "exit 78 → UNHEALTHY, no restart" {
	echo config >"$FAKE_DIR/mode"
	"$host" start
	wait_for 5 state_is UNHEALTHY
	grep -q "exit 78" "$NIMWAKE_HOST_HOME/run/state"
	sleep 2
	[ "$(launches)" -eq 1 ]
}

@test "killed daemon is restarted and becomes RUNNING again" {
	"$host" start
	wait_for 5 state_is RUNNING
	pkill -KILL -f "fake-nimwaked"
	wait_for 5 launched_at_least 2
	wait_for 5 state_is RUNNING
	grep -q "exit 137" "$NIMWAKE_HOST_HOME/logs/supervisor.log"
}

@test "repeated crashes → crash loop → UNHEALTHY" {
	echo crash >"$FAKE_DIR/mode"
	export NIMWAKE_MAX_RESTARTS=2
	"$host" start
	# 기동 1 → 0s → 기동 2 → 5s → 기동 3 → crash loop
	wait_for 15 state_is UNHEALTHY
	grep -q "crash loop: 2 restarts" "$NIMWAKE_HOST_HOME/run/state"
	[ "$(launches)" -eq 3 ]
}

@test "a daemon that stops answering health probes is replaced" {
	echo hung >"$FAKE_DIR/mode"
	"$host" start
	wait_for 10 launched_at_least 2
	grep -q "health probe failed" "$NIMWAKE_HOST_HOME/logs/supervisor.log"
}

@test "exit 0 from outside (make stop) → STOPPED, no restart" {
	"$host" start
	wait_for 5 state_is RUNNING
	pkill -TERM -f "fake-nimwaked"
	wait_for 5 state_is STOPPED
	sleep 2
	[ "$(launches)" -eq 1 ]
}

@test "stop during backoff ends promptly" {
	echo crash >"$FAKE_DIR/mode"
	"$host" start
	# 두 번째 crash 뒤 5초 backoff에 들어간다
	wait_for 10 launched_at_least 2
	wait_for 5 state_is BACKOFF
	run "$host" stop
	[ "$status" -eq 0 ]
	state_is STOPPED
}
