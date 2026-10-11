#!/bin/sh
# 태그를 달아도 되는지 본다. release.yml과 개발 머신이 같은 것을 돌린다.
#
#   release-check.sh TAG           검사만 한다 (예: v0.1.0, v0.1.0-rc1)
#   release-check.sh TAG --notes   검사를 통과하면 CHANGELOG의 그 버전 절을 출력한다 (Release 본문)
#
# 검사:
#   1. TAG가 vX.Y.Z 또는 vX.Y.Z-<pre>이다
#   2. CHANGELOG.md에 `## [X.Y.Z…]` 절이 있고 비어 있지 않다 — [Unreleased]인 채로는 태그를 달지 않는다
#   3. 정식 릴리스(pre 없음)면 core.lock의 `tag=`가 비어 있지 않다 — 검증한 Core가 release로 고정돼 있어야 한다.
#      pre-release는 commit SHA(rev=)만으로도 된다
#   ROOT  레포 위치 (기본: 이 스크립트의 상위). 테스트가 바꾼다
set -eu

root="${ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"

fail() {
	echo "release-check: $*" >&2
	exit 1
}

[ $# -ge 1 ] || {
	echo "usage: release-check.sh TAG [--notes]" >&2
	exit 2
}
tag="$1"
notes="${2:-}"

version="${tag#v}"
case "$tag" in
v[0-9]*.[0-9]*.[0-9]*) ;;
*) fail "tag '$tag' is not vX.Y.Z[-pre]" ;;
esac
core="${version%%-*}"
case "$core" in
*[!0-9.]* | *.*.*.* | .* | *. | *..*) fail "tag '$tag' is not vX.Y.Z[-pre]" ;;
esac

changelog="$root/CHANGELOG.md"
[ -f "$changelog" ] || fail "CHANGELOG.md not found"

# `## [0.1.0]` 또는 `## [0.1.0] — 2026-10-12`. 다음 `## ` 전까지가 그 절이다
section="$(awk -v v="$version" '
	index($0, "## [" v "]") == 1 { on = 1; next }
	on && /^## / { exit }
	on { print }
' "$changelog")"
[ -n "$(printf '%s' "$section" | tr -d '[:space:]')" ] ||
	fail "CHANGELOG.md has no '## [$version]' section — rename [Unreleased] to [$version] — YYYY-MM-DD"

lock="$root/core.lock"
[ -f "$lock" ] || fail "core.lock not found"
core_tag="$(sed -n 's/^tag=//p' "$lock")"
core_rev="$(sed -n 's/^rev=//p' "$lock")"
case "$version" in
*-*)
	[ -n "$core_tag$core_rev" ] || fail "core.lock pins neither tag= nor rev="
	;;
*)
	[ -n "$core_tag" ] || fail "a release must pin a Core release: core.lock has tag= empty (rev=${core_rev:-none})"
	;;
esac

if [ "$notes" = --notes ]; then
	printf '%s\n' "$section" | sed '/./,$!d'
else
	echo "release-check: $tag ok (Core ${core_tag:-rev $(printf '%.7s' "$core_rev")})"
fi
