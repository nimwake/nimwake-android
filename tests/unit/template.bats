#!/usr/bin/env bats
# examples/consumer-template/Makefile — 개인 레포가 쓰는 명령의 가드. 기기 없이 돈다.

setup() {
	root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	repo="$BATS_TEST_TMPDIR/my-sites"
	cp -R "$root/examples/consumer-template" "$repo"
}

@test "upgrade needs a REV" {
	run make -s -C "$repo" upgrade
	[ "$status" -ne 0 ]
	[[ "$output" == *"upgrade: REV is empty"* ]]
}

@test "upgrade refuses a moving REV — main, master, HEAD" {
	for rev in main master HEAD; do
		run make -s -C "$repo" upgrade REV="$rev"
		[ "$status" -ne 0 ]
		[[ "$output" == *"REV=$rev moves under you"* ]]
	done
	# lock은 그대로
	grep -q '^rev=v' "$repo/nimwake-android.lock"
}

@test "upgrade writes the lock first, then setup, phone, restart and every app" {
	# -n이어도 하위 make($(MAKE) -C .nimwake-android …)는 들어간다 — 아무것도 하지 않는 자리를 둔다
	mkdir -p "$repo/.nimwake-android"
	printf 'fetch-core deploy restart deploy-app:\n\t@:\n' >"$repo/.nimwake-android/Makefile"
	run make -n -C "$repo" upgrade REV=v9.9.9
	echo "$output"
	[ "$status" -eq 0 ]
	[[ "$output" == *"s/^rev=.*/rev=v9.9.9/"* ]]
	[[ "$output" == *"setup"* ]]
	[[ "$output" == *"fetch-core deploy"* ]]
	[[ "$output" == *"restart"* ]]
	[[ "$output" == *'for d in apps/*/'* ]]
}
