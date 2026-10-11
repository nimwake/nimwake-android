#!/usr/bin/env bats
# host/lib/logs.sh — 로그 순환 (PRD §20). supervisor 루프와의 연결은 supervisor.bats가 본다.

setup() {
	root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	export NIMWAKE_HOST_HOME="$BATS_TEST_TMPDIR/host"
	export NIMWAKE_LOG_MAX_KB=1
	export NIMWAKE_LOG_KEEP=2
	. "$root/host/lib/config.sh"
	. "$root/host/lib/supervisor.sh"
	. "$root/host/lib/logs.sh"
	log="$NIMWAKE_LOGS/nimwaked.log"
}

teardown() {
	[ -z "${writer:-}" ] || kill "$writer" 2>/dev/null || true
}

# fill FILE KB TAG — TAG로 시작하는 KB 크기 파일
fill() {
	{
		echo "$3"
		head -c $(($2 * 1024)) /dev/zero | tr '\0' 'x'
	} >"$1"
}

@test "a log under the limit is left alone" {
	echo small >"$log"
	run rotate_log "$log"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ "$(cat "$log")" = small ]
	[ ! -f "$log.1" ]
}

@test "a log over the limit is copied to .1 and emptied" {
	fill "$log" 3 first
	run rotate_log "$log"
	[ "$status" -eq 0 ]
	[ "$output" = 3 ]
	[ -f "$log" ]
	[ ! -s "$log" ]
	[ "$(head -n 1 "$log.1")" = first ]
}

@test "older copies shift and only KEEP of them remain" {
	for tag in a b c d; do
		fill "$log" 2 "$tag"
		rotate_log "$log" >/dev/null
	done
	[ "$(head -n 1 "$log.1")" = d ]
	[ "$(head -n 1 "$log.2")" = c ]
	[ ! -f "$log.3" ]
}

@test "KEEP=0 only empties the log" {
	NIMWAKE_LOG_KEEP=0
	fill "$log" 2 a
	rotate_log "$log" >/dev/null
	[ ! -s "$log" ]
	[ ! -f "$log.1" ]
}

# nimwaked는 `>>`로 연 채 계속 쓴다. 이름을 바꾸는 방식이면 .1이 계속 자란다
@test "a writer holding the log open keeps writing to the live file after rotation" {
	sh -c 'while :; do echo line; sleep 0.05; done' >>"$log" &
	writer=$!
	sleep 0.3
	head -c 2048 /dev/zero | tr '\0' 'x' >>"$log"
	rotate_log "$log" >/dev/null
	rotated="$(wc -c <"$log.1" | tr -d ' ')"
	sleep 0.5
	# 옮긴 파일은 더 자라지 않고, 살아 있는 파일은 처음부터 다시 자란다 (O_APPEND — 앞이 0으로 채워지지 않는다)
	[ "$(wc -c <"$log.1" | tr -d ' ')" -eq "$rotated" ]
	[ -s "$log" ]
	[ "$(head -n 1 "$log")" = line ]
	[ "$(wc -c <"$log" | tr -d ' ')" -lt 1024 ]
}

@test "rotate_logs handles every host log, logs what it did, and skips soak.csv" {
	fill "$NIMWAKE_LOGS/boot.log" 2 boot
	fill "$NIMWAKE_LOGS/soak.csv" 2 soak
	echo tiny >"$NIMWAKE_LOGS/supervisor.log"
	rotate_logs
	[ -f "$NIMWAKE_LOGS/boot.log.1" ]
	[ ! -f "$NIMWAKE_LOGS/soak.csv.1" ]
	[ ! -f "$NIMWAKE_LOGS/supervisor.log.1" ]
	grep -q "log: rotated boot.log (2KB, keep 2)" "$NIMWAKE_LOGS/supervisor.log"
}

@test "a missing log is not an error" {
	run rotate_log "$NIMWAKE_LOGS/absent.log"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}
