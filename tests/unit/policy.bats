#!/usr/bin/env bats
# host/lib/policy.sh — 재기동 판단 (PRD §23–§24, Core PRD §74)

setup() {
	# shellcheck source=../../host/lib/policy.sh
	. "$BATS_TEST_DIRNAME/../../host/lib/policy.sh"
}

@test "exit 0 is a normal stop — no restart" {
	[ "$(policy_classify_exit 0)" = stopped ]
}

@test "exit 78 is a configuration error — no restart" {
	[ "$(policy_classify_exit 78)" = config ]
}

@test "exit 69 (bind failure) is retried" {
	[ "$(policy_classify_exit 69)" = retry ]
}

@test "exit 1 and signal deaths are retried" {
	[ "$(policy_classify_exit 1)" = retry ]
	[ "$(policy_classify_exit 137)" = retry ]
	[ "$(policy_classify_exit 143)" = retry ]
}

@test "backoff is 0, 5, 15, then 60 seconds" {
	[ "$(policy_backoff 1)" = 0 ]
	[ "$(policy_backoff 2)" = 5 ]
	[ "$(policy_backoff 3)" = 15 ]
	[ "$(policy_backoff 4)" = 60 ]
	[ "$(policy_backoff 9)" = 60 ]
}

@test "prune drops restarts outside the window" {
	[ "$(policy_prune 1000 300 600 700 800 950)" = "800 950" ]
}

@test "prune keeps nothing from an empty list" {
	[ "$(policy_prune 1000 300)" = "" ]
}

@test "a restart exactly at the window edge is outside" {
	[ "$(policy_prune 1000 300 700 701)" = "701" ]
}

@test "count counts words" {
	[ "$(policy_count "")" = 0 ]
	[ "$(policy_count "800 950")" = 2 ]
}

@test "crash loop when restarts in the window reach the limit" {
	policy_crash_loop 5 5
	policy_crash_loop 6 5
	run policy_crash_loop 4 5
	[ "$status" -ne 0 ]
}

@test "restarts spread over time do not trip the crash loop" {
	restarts=""
	for now in 0 400 800 1200 1600 2000 2400; do
		restarts="$(policy_prune "$now" 300 $restarts)"
		run policy_crash_loop "$(policy_count "$restarts")" 5
		[ "$status" -ne 0 ]
		restarts="$restarts $now"
	done
}
