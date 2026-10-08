#!/bin/sh
# dist/ · guest/ · host/ 를 ssh로 기기의 Termux에 올리고,
# binary와 manifest는 proot Ubuntu 안에, Termux:Boot 스크립트는 ~/.termux/boot/ 에 배치한다.
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone, ~/.ssh/config에 정의)
set -eu

root="$(cd "$(dirname "$0")/.." && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"
stage='.nimwake-host/stage'

if [ ! -x "$root/dist/aarch64/nimwaked" ]; then
	echo "deploy: dist/aarch64/nimwaked 가 없다. 먼저 make fetch-core" >&2
	exit 1
fi

# rsync는 쓰지 않는다 (macOS openrsync와 옵션이 다르다).
(cd "$root" && tar -cf - dist/aarch64 guest host) |
	ssh "$device" "rm -rf $stage && mkdir -p $stage && tar -xf - -C $stage"

# Termux $HOME은 proot 안에서 보이지 않으므로 stage를 bind한다.
ssh "$device" "proot-distro login ubuntu --bind \$HOME/$stage:/mnt/nimwake-stage \
	-- sh /mnt/nimwake-stage/guest/setup-ubuntu.sh /mnt/nimwake-stage"

# Termux:Boot는 이 디렉터리의 실행 파일을 이름 순으로 시작한다. 앞 스크립트를 기다리지는 않는다. (validation/02)
# 다음 재부팅부터 nimwaked가 자동으로 뜬다. 이미 떠 있는 daemon은 건드리지 않는다.
ssh "$device" "mkdir -p \$HOME/.termux/boot && install -m 700 $stage/host/boot/* \$HOME/.termux/boot/ \
	&& echo 'deploy: boot scripts installed' && ls \$HOME/.termux/boot"
