#!/bin/sh
# dist/ 와 guest/ 를 ssh로 기기의 Termux에 올리고, proot Ubuntu 안에 배치한다.
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
(cd "$root" && tar -cf - dist/aarch64 guest) |
	ssh "$device" "rm -rf $stage && mkdir -p $stage && tar -xf - -C $stage"

# Termux $HOME은 proot 안에서 보이지 않으므로 stage를 bind한다.
ssh "$device" "proot-distro login ubuntu --bind \$HOME/$stage:/mnt/nimwake-stage \
	-- sh /mnt/nimwake-stage/guest/setup-ubuntu.sh /mnt/nimwake-stage"
