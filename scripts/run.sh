#!/bin/sh
# A1: 기기에서 nimwaked를 foreground로 띄운다. Ctrl-C로 SIGINT → graceful shutdown.
# supervisor(A2)가 생기기 전의 수동 기동 경로다.
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"

exec ssh -t "$device" "termux-wake-lock 2>/dev/null; \
	proot-distro login ubuntu --user nimwake \
	-- /opt/nimwake/bin/nimwaked /home/nimwake/.nimwake/apps $*"
