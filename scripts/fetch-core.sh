#!/bin/sh
# core.lock에 pin한 Core commit의 aarch64 artifact를 dist/aarch64/로 받는다.
# 빌드는 Core CI(release.yml의 aarch64 job)가 소유한다. 여기서는 받기만 한다.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd -P)"
lock="$root/core.lock"
out="$root/dist/aarch64"

repo="$(sed -n 's/^repo=//p' "$lock")"
rev="$(sed -n 's/^rev=//p' "$lock")"

if [ -z "$repo" ] || [ -z "$rev" ]; then
	echo "fetch-core: core.lock에 repo= 와 rev= 가 필요하다" >&2
	exit 1
fi

run_id="$(gh run list -R "$repo" --workflow release.yml --commit "$rev" \
	--json databaseId,conclusion \
	--jq '[.[] | select(.conclusion == "success")][0].databaseId // empty')"

if [ -z "$run_id" ]; then
	echo "fetch-core: $repo@$rev 의 성공한 Release run이 없다." >&2
	echo "  Core 레포에서: gh workflow run release.yml --ref <branch>" >&2
	exit 1
fi

rm -rf "$out"
mkdir -p "$out"
gh run download "$run_id" -R "$repo" -n "nimwake-aarch64-$rev" -D "$out"
chmod +x "$out"/nimwaked "$out"/*-server

echo "fetch-core: $repo@$rev (run $run_id) → dist/aarch64/"
cat "$out/BUILD_INFO"
