#!/bin/sh
# docs/의 사용자 문서가 어긋나지 않게 한다. make lint가 돌린다 (CI).
#
#   1. 짝: docs/NAME.md(영문, 기본)마다 docs/NAME.ko.md(국문)가 있고, 그 반대도
#   2. 같은 뼈대: 두 판의 제목 단계(#, ##, ###)가 같은 순서로 같다 — 한쪽에만 절을 더하면 실패
#   3. 같은 명령: 두 판의 코드 블록이 글자 그대로 같다 — 명령은 번역하지 않는다(블록 안 주석도 영문)
#   4. 있는 명령: 코드 블록의 `make <대상>`이 이 레포 Makefile이나 소비처 템플릿 Makefile에 있다
#
#   ROOT  레포 위치 (기본: 이 스크립트의 상위). 테스트가 바꾼다
set -eu

root="${ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}"
docs="$root/docs"
[ -d "$docs" ] || {
	echo "check-docs: ok (no docs/)"
	exit 0
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail=0
problem() {
	echo "check-docs: $*" >&2
	fail=1
}

# 코드 블록 밖의 제목 단계만 (### 제목 → 3)
headings() {
	awk '
		/^```/ { fence = !fence; next }
		!fence && /^#+ / { match($0, /^#+/); print RLENGTH }
	' "$1"
}

# 코드 블록 — 여는 줄(언어 포함)부터 닫는 줄까지 그대로
blocks() {
	awk '
		/^```/ { print; fence = !fence; next }
		fence { print }
	' "$1"
}

# 이 레포와 템플릿의 make 대상
{
	sed -n 's/^\([a-z][a-z0-9-]*\):.*/\1/p' "$root/Makefile"
	[ -f "$root/examples/consumer-template/Makefile" ] &&
		sed -n 's/^\([a-z][a-z0-9-]*\):.*/\1/p' "$root/examples/consumer-template/Makefile"
} | sort -u >"$tmp/targets"

n=0
for doc in "$docs"/*.md; do
	[ -f "$doc" ] || continue
	case "$doc" in
	*.ko.md)
		[ -f "${doc%.ko.md}.md" ] || problem "$(basename "$doc") has no English original $(basename "${doc%.ko.md}.md")"
		continue
		;;
	esac
	n=$((n + 1))
	ko="${doc%.md}.ko.md"
	name="$(basename "$doc")"
	if [ ! -f "$ko" ]; then
		problem "$name has no Korean version $(basename "$ko")"
		continue
	fi
	headings "$doc" >"$tmp/h.en"
	headings "$ko" >"$tmp/h.ko"
	if ! cmp -s "$tmp/h.en" "$tmp/h.ko"; then
		problem "$name and $(basename "$ko") have different heading structure ($(wc -l <"$tmp/h.en" | tr -d ' ') vs $(wc -l <"$tmp/h.ko" | tr -d ' ') headings) — add or remove the section in both"
	fi
	blocks "$doc" >"$tmp/b.en"
	blocks "$ko" >"$tmp/b.ko"
	if ! cmp -s "$tmp/b.en" "$tmp/b.ko"; then
		problem "$name and $(basename "$ko") have different code blocks — commands must match in both (comments in code stay English):"
		diff "$tmp/b.en" "$tmp/b.ko" | sed 's/^/    /' >&2 || true
	fi
	# make 다음 첫 대상 — make -s deploy APP=x → deploy
	sed -n 's/^.*make \(-[a-zA-Z] \)*\([a-z][a-z0-9-]*\).*/\2/p' "$tmp/b.en" | sort -u >"$tmp/used"
	while read -r target; do
		grep -qx "$target" "$tmp/targets" || problem "$name uses 'make $target', which no Makefile defines"
	done <"$tmp/used"
done

[ "$fail" -eq 0 ] || exit 1
echo "check-docs: ok ($n documents, English + Korean)"
