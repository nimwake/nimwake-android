#!/usr/bin/env bats
# scripts/release-check.sh — 태그 전 검사. release.yml이 같은 스크립트를 쓴다.

setup() {
	root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	check="$root/scripts/release-check.sh"
	export ROOT="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$ROOT"
	cat >"$ROOT/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

- next

## [0.2.0-rc1] — 2026-10-20

- candidate

## [0.1.0] — 2026-10-12

### Added

- supervisor

## [0.0.1] — 2026-10-01

- old
EOF
	lock tag=v0.1.0 rev=d7c55907ccc7179d0591b155b9f155845cd5c064
}

lock() {
	printf 'repo=nimwake/nimwake\n%s\n%s\n' "$1" "$2" >"$ROOT/core.lock"
}

@test "a release with a CHANGELOG section and a pinned Core tag passes" {
	run "$check" v0.1.0
	echo "$output"
	[ "$status" -eq 0 ]
	[[ "$output" == *"v0.1.0 ok (Core v0.1.0)"* ]]
}

@test "--notes prints only that version's section" {
	run "$check" v0.1.0 --notes
	echo "$output"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "### Added" ]
	[[ "$output" == *"- supervisor"* ]]
	[[ "$output" != *"old"* ]]
	[[ "$output" != *"candidate"* ]]
}

@test "a version still under [Unreleased] is refused" {
	run "$check" v0.3.0
	[ "$status" -eq 1 ]
	[[ "$output" == *"no '## [0.3.0]' section"* ]]
}

@test "a release with core.lock pinned only by rev is refused" {
	lock tag= rev=d7c55907ccc7179d0591b155b9f155845cd5c064
	run "$check" v0.1.0
	[ "$status" -eq 1 ]
	[[ "$output" == *"must pin a Core release"* ]]
}

@test "a pre-release may pin Core by rev" {
	lock tag= rev=d7c55907ccc7179d0591b155b9f155845cd5c064
	run "$check" v0.2.0-rc1
	echo "$output"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Core rev d7c5590"* ]]
}

@test "malformed tags are refused" {
	for t in 0.1.0 v0.1 v0.1.0.1 vx.y.z v0..1; do
		run "$check" "$t"
		[ "$status" -eq 1 ] || { echo "accepted $t"; return 1; }
	done
}

@test "the repository CHANGELOG has an Unreleased section and the script runs on it" {
	unset ROOT
	grep -q '^## \[Unreleased\]' "$root/CHANGELOG.md"
	# 이 레포의 다음 릴리스는 아직 [Unreleased]다 — 태그 전에 이름을 바꿔야 통과한다
	run "$check" v99.0.0
	[ "$status" -eq 1 ]
}
