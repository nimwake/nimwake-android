#!/bin/sh
# Core PRD §50 — CI Linux와 Android 실기기에서 **같은 workload**로 같은 지표를 비교한다.
#
#   1. CI가 같은 Core commit에서 낸 baseline.txt를 받는다 (release asset 또는 release.yml run artifact)
#   2. 기기의 proot Ubuntu에서 nimwake-bench를 그 baseline과 비교하며 돌린다
#   3. 리포트 · 기기 baseline을 dist/bench/로 가져온다
#
# 비교 항목: proxy overhead p50/p95 · cold start breakdown · daemon RSS · CPU · concurrency knee point
#
# nimwake-bench는 부하를 건다 (동시 연결 1000까지). **soak 중에는 거부한다** — 측정이 섞인다.
# 운영 daemon(:8080)은 그대로 두고 bench는 자기 daemon을 따로 띄운다.
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
#   BENCH_ARGS      nimwake-bench에 더 줄 인자 (예: --max-concurrency 250)
#   FORCE=1         soak 중이어도 돌린다
set -eu

root="$(cd "$(dirname "$0")/../.." && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"
lock="$root/core.lock"
out="$root/dist/bench"
repo="$(sed -n 's/^repo=//p' "$lock")"
rev="$(sed -n 's/^rev=//p' "$lock")"
tag="$(sed -n 's/^tag=//p' "$lock")"

# pid만 보면 재사용된 pid를 sampler로 본다(#20). 재부팅으로 sampler가 잠시 없어도 soak은 진행 중이다(#19)
if [ "${FORCE:-}" != 1 ] && why="$("$root/scripts/device-status.sh" --soak-running)"; then
	echo "bench: a soak is running on the device ($why) — bench would load the CPU and skew it. make soak-stop, or FORCE=1" >&2
	exit 1
fi

built="$(ssh "$device" "proot-distro login ubuntu -- sed -n 's/^commit=//p' /opt/nimwake/BUILD_INFO" </dev/null)"
if [ "$built" != "$rev" ]; then
	echo "bench: the device has Core ${built:-?}, core.lock says $rev — make deploy first" >&2
	exit 1
fi

rm -rf "$out"
mkdir -p "$out/ci"
if [ -n "$tag" ]; then
	gh release download "$tag" -R "$repo" -p baseline.txt -p performance-report.md -D "$out/ci"
else
	run_id="$(gh run list -R "$repo" --workflow release.yml --commit "$rev" \
		--json databaseId,conclusion \
		--jq '[.[] | select(.conclusion == "success")][0].databaseId // empty')"
	[ -n "$run_id" ] || {
		echo "bench: no successful release.yml run for $rev" >&2
		exit 1
	}
	gh run download "$run_id" -R "$repo" -n performance-report -D "$out/ci"
fi
echo "bench: CI baseline for $(printf '%s' "$rev" | cut -c1-7)"
cat "$out/ci/baseline.txt"

# proot 안에서 Termux 쪽 디렉터리를 bind해 baseline을 주고 리포트를 받는다
ssh "$device" 'rm -rf $HOME/.nimwake-host/bench && mkdir -p $HOME/.nimwake-host/bench && chmod 777 $HOME/.nimwake-host/bench'
ssh "$device" 'cat > $HOME/.nimwake-host/bench/ci-baseline.txt' <"$out/ci/baseline.txt"

echo "bench: running on the device (several minutes)"
# nimwake-bench는 correctness gate(예: cold-start storm 실패)에 걸리면 0이 아닌 코드로 끝나지만
# 리포트는 이미 썼다. 기기에서는 그 gate에 걸리는 것이 측정 결과다 (validation/08) — 리포트를 먼저 가져오고
# 종료 코드는 마지막에 돌려준다.
status=0
# shellcheck disable=SC2086 # BENCH_ARGS는 단어로 나눈다
ssh "$device" "proot-distro login ubuntu --user nimwake --bind \$HOME/.nimwake-host/bench:/mnt/bench -- \
	/opt/nimwake/bin/nimwake-bench \
	--nimwaked /opt/nimwake/bin/nimwaked --echo-server /opt/nimwake/bin/echo-server \
	--commit android-$(printf '%s' "$rev" | cut -c1-7) \
	--baseline /mnt/bench/ci-baseline.txt \
	--out /mnt/bench/device-report.md --baseline-out /mnt/bench/device-baseline.txt \
	${BENCH_ARGS:-}" </dev/null || status=$?

ssh "$device" 'cat $HOME/.nimwake-host/bench/device-report.md' >"$out/device-report.md"
ssh "$device" 'cat $HOME/.nimwake-host/bench/device-baseline.txt' >"$out/device-baseline.txt"
echo "bench: dist/bench/device-report.md (vs CI dist/bench/ci/performance-report.md)"
cat "$out/device-report.md"
if [ "$status" -ne 0 ]; then
	echo "bench: nimwake-bench exited $status (correctness gate) — the report above is complete" >&2
fi
exit "$status"
