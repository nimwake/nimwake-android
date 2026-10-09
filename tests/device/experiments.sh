#!/bin/sh
# A1 실기기 실험 E2–E4 (Phase 1 03-core-sync "실기기 실험").
#
#   E2  readiness 대기 중 app이 죽으면 startup_timeout까지 기다리지 않고 바로 실패하는가
#   E3  idle stop이 process group 단위로 정리해 손자 process까지 사라지는가
#   E4  nimwaked · proot가 SIGKILL로 죽으면 app process가 남는가
#
# 운영 중인 nimwaked(/opt/nimwake, :8080)와 soak은 건드리지 않는다 — 별도 경로 · 포트의 실험 daemon을 쓰고
# 끝나면 치운다. 결과는 사람이 읽어 .docs/validation/에 리포트로 남긴다 (판정은 자동화하지 않았다).
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

here="$(cd "$(dirname "$0")" && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"

on_device() {
	ssh "$device" sh -s "$1" <"$here/experiments-device.sh"
}

trap 'on_device teardown' EXIT

on_device setup
for step in e2 e3 e4; do
	echo "== $step"
	on_device "$step"
done
echo "== teardown"
