#!/bin/sh
# 기기의 supervisor를 다시 띄운다 — nimwake-host stop · start. host.conf 변경(ingress · 임계값 등)이 반영된다.
# daemon과 앱도 다시 뜬다 (앱 하나만 바꿀 때는 make deploy-app — SIGHUP 재적재라 다른 앱은 그대로).
# soak 중이면 거부한다 — FORCE=1
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

root="$(cd "$(dirname "$0")/.." && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"

if [ "${FORCE:-}" != 1 ] && why="$("$root/scripts/device-status.sh" --soak-running)"; then
	echo "restart: a soak is running ($why) — restarting the daemon would break it. FORCE=1" >&2
	exit 1
fi

ssh "$device" sh -s <<'EOF'
{
set -eu
nimwake-host stop
nimwake-host start
i=0
until grep -q '^RUNNING' "$HOME/.nimwake-host/run/state" 2>/dev/null; do
	i=$((i + 1))
	[ "$i" -le 60 ] || { echo "restart: not RUNNING after 60s" >&2; nimwake-host status; exit 1; }
	sleep 1
done
sleep 2
nimwake-host status
} </dev/null
EOF
