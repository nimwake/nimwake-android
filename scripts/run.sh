#!/bin/sh
# A1: 기기에서 nimwaked를 foreground로 띄운다. Ctrl-C로 SIGINT → graceful shutdown.
# supervisor(A2)가 생기기 전의 수동 기동 경로다.
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"

# 부팅 때 10-nimwake가 띄운 daemon이 있으면 port가 겹쳐 69(bind 실패)로 끝난다. 먼저 알려 준다.
if ssh "$device" "pgrep -f '^/opt/nimwake/bin/nimwaked'" >/dev/null; then
	echo "run: nimwaked is already running on the device (started at boot?). make stop first." >&2
	exit 1
fi

exec ssh -t "$device" "termux-wake-lock 2>/dev/null; \
	proot-distro login ubuntu --user nimwake \
	-- /opt/nimwake/bin/nimwaked /home/nimwake/.nimwake/apps $*"
