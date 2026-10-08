#!/bin/sh
# 기기의 nimwaked에 SIGTERM을 보내고 정지를 기다린다 → graceful shutdown (Core PRD §74).
# 부팅 때 10-nimwake가 띄운 daemon처럼 foreground 세션이 없는 경우에 쓴다.
#
# proot 아래에서 comm은 `/opt/nimwake/bi`로 잘려 `pkill -x nimwaked`는 아무것도 찾지 못한다.
# 전체 경로를 `^`로 묶어 daemon 자신만 고른다. (validation/01)
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"

ssh "$device" sh -s <<'EOF'
daemon='^/opt/nimwake/bin/nimwaked'

if ! pgrep -f "$daemon" >/dev/null; then
	echo "stop: nimwaked is not running"
	exit 0
fi

pkill -TERM -f "$daemon"
echo "stop: SIGTERM sent"

# app의 shutdown_timeout만큼 기다려야 할 수 있다.
waited=0
while pgrep -f "$daemon" >/dev/null; do
	if [ "$waited" -ge 30 ]; then
		echo "stop: nimwaked still running after 30s" >&2
		exit 1
	fi
	sleep 1
	waited=$((waited + 1))
done
echo "stop: nimwaked exited after ${waited}s"
EOF
