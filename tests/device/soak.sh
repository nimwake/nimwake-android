#!/bin/sh
# 장시간 soak — 기기의 sampler(nimwake-soak)를 다루고 결과를 요약한다. (A5 · A6, Core PRD §51)
#
#   soak.sh start [HOURS] [INTERVAL]   sampler를 기기에서 백그라운드로 띄운다 (기본 24h · 300s)
#   soak.sh stop                       sampler를 멈춘다
#   soak.sh report                     soak.csv를 가져와 요약한다 — 실행 중에도 된다
#   soak.sh summarize < soak.csv       요약만 한다 (기기 없이)
#
# sampler는 기기에서 돈다. 개발 머신은 72시간 켜 둘 필요가 없다.
# 새 soak을 시작하면 이전 soak.csv는 soak-<시각>.csv로 옮긴다.
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

here="$(cd "$(dirname "$0")" && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"

cmd_start() {
	hours="${1:-24}"
	interval="${2:-300}"
	# `{ … } </dev/null`: termux-wake-lock 등이 표준 입력(=이 스크립트)을 삼키지 못하게 한다 (scripts/doctor.sh 참고)
	ssh "$device" sh -s "$hours" "$interval" <<'EOF'
{
set -eu
host="$HOME/.nimwake-host"
if [ -f "$host/run/soak.pid" ] && kill -0 "$(cat "$host/run/soak.pid")" 2>/dev/null; then
	echo "soak: already running (pid $(cat "$host/run/soak.pid"))" >&2
	exit 1
fi
if [ -f "$host/logs/soak.csv" ]; then
	mv "$host/logs/soak.csv" "$host/logs/soak-$(date +%Y%m%d-%H%M%S).csv"
fi
termux-wake-lock
nohup "$host/bin/nimwake-soak" "$2" "$1" >/dev/null 2>&1 &
echo "soak: started (pid $!) — ${1}h, every ${2}s → ~/.nimwake-host/logs/soak.csv"
} </dev/null
EOF
}

cmd_stop() {
	ssh "$device" sh -s <<'EOF'
pid_file="$HOME/.nimwake-host/run/soak.pid"
if [ -f "$pid_file" ] && kill "$(cat "$pid_file")" 2>/dev/null; then
	echo "soak: stopped"
else
	echo "soak: not running"
fi
EOF
}

cmd_report() {
	csv="$(ssh "$device" 'cat $HOME/.nimwake-host/logs/soak.csv 2>/dev/null')"
	running="$(ssh "$device" 'p=$HOME/.nimwake-host/run/soak.pid; if [ -f "$p" ] && kill -0 "$(cat "$p")" 2>/dev/null; then echo yes; else echo no; fi')"
	if [ -z "$csv" ]; then
		echo "soak: no soak.csv on the device" >&2
		exit 1
	fi

	echo "sampler running: $running"
	printf '%s\n' "$csv" | summarize
}

# soak.csv(표준 입력)를 요약한다. 기기 없이 tests/unit/soak.bats가 검증한다.
summarize() {
	awk -F, -f "$here/soak-summary.awk"
}

case "${1:-}" in
start) shift; cmd_start "$@" ;;
stop) cmd_stop ;;
report) cmd_report ;;
summarize) summarize ;;
*)
	echo "usage: soak.sh start [HOURS] [INTERVAL] | stop | report | summarize < soak.csv" >&2
	exit 2
	;;
esac
