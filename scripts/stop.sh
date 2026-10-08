#!/bin/sh
# 기기의 nimwaked를 graceful하게 내린다 → SIGTERM (Core PRD §74).
#
# supervisor(nimwake-host)가 설치되어 있으면 그것에 맡긴다 — stop을 요청해야 재기동하지 않는다.
# 없으면 daemon에 직접 SIGTERM을 보낸다. proot 아래에서 comm이 `/opt/nimwake/bi`로 잘려
# `pkill -x nimwaked`는 아무것도 찾지 못하므로 전체 경로를 `^`로 묶어 찾는다. (validation/01)
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"

ssh "$device" sh -s <<'EOF'
if command -v nimwake-host >/dev/null 2>&1; then
	exec nimwake-host stop
fi

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
