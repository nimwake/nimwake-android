#!/bin/sh
# core.lock에 pin한 Core의 aarch64 binary를 dist/aarch64/로 받는다.
# 빌드는 Core CI(release.yml의 aarch64 job)가 소유한다. 여기서는 받기만 한다.
#
#   tag= 가 있으면  그 GitHub release의 asset을 받는다 (Core v0.1.0-rc1 이후)
#   tag= 가 없으면  rev의 성공한 release.yml run artifact를 받는다 (90일 보관)
#
# 어느 쪽이든 받은 BUILD_INFO의 commit이 core.lock의 rev와 같아야 한다.
# tag는 움직일 수 있으므로 rev가 기준이다.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd -P)"
lock="$root/core.lock"
out="$root/dist/aarch64"
asset='nimwake-aarch64-linux-musl.tar.gz'

repo="$(sed -n 's/^repo=//p' "$lock")"
rev="$(sed -n 's/^rev=//p' "$lock")"
tag="$(sed -n 's/^tag=//p' "$lock")"

if [ -z "$repo" ] || [ -z "$rev" ]; then
	echo "fetch-core: core.lock에 repo= 와 rev= 가 필요하다" >&2
	exit 1
fi

rm -rf "$out"
mkdir -p "$out"

if [ -n "$tag" ]; then
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT
	gh release download "$tag" -R "$repo" -p "$asset" -D "$tmp"
	tar -xzf "$tmp/$asset" -C "$out"
	source_desc="release $tag"
else
	run_id="$(gh run list -R "$repo" --workflow release.yml --commit "$rev" \
		--json databaseId,conclusion \
		--jq '[.[] | select(.conclusion == "success")][0].databaseId // empty')"

	if [ -z "$run_id" ]; then
		echo "fetch-core: $repo@$rev 의 성공한 Release run이 없다." >&2
		echo "  Core 레포에서: gh workflow run release.yml --ref <branch>" >&2
		exit 1
	fi

	gh run download "$run_id" -R "$repo" -n "nimwake-aarch64-$rev" -D "$out"
	source_desc="run $run_id"
fi

chmod +x "$out"/nimwaked "$out"/*-server

built="$(sed -n 's/^commit=//p' "$out/BUILD_INFO")"
if [ "$built" != "$rev" ]; then
	echo "fetch-core: BUILD_INFO commit ($built) ≠ core.lock rev ($rev)" >&2
	rm -rf "$out"
	exit 1
fi

echo "fetch-core: $repo@$rev ($source_desc) → dist/aarch64/"
cat "$out/BUILD_INFO"
