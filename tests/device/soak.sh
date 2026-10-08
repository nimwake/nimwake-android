#!/bin/sh
# 장시간 soak — 기기의 sampler(nimwake-soak)를 다루고 결과를 요약한다. (A5 · A6, Core PRD §51)
#
#   soak.sh start [HOURS] [INTERVAL]   sampler를 기기에서 백그라운드로 띄운다 (기본 24h · 300s)
#   soak.sh stop                       sampler를 멈춘다
#   soak.sh report                     soak.csv를 가져와 요약한다 — 실행 중에도 된다
#
# sampler는 기기에서 돈다. 개발 머신은 72시간 켜 둘 필요가 없다.
# 새 soak을 시작하면 이전 soak.csv는 soak-<시각>.csv로 옮긴다.
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"

cmd_start() {
	hours="${1:-24}"
	interval="${2:-300}"
	ssh "$device" sh -s "$hours" "$interval" <<'EOF'
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
	running="$(ssh "$device" 'p=$HOME/.nimwake-host/run/soak.pid; [ -f "$p" ] && kill -0 "$(cat "$p")" 2>/dev/null && echo yes || echo no')"
	if [ -z "$csv" ]; then
		echo "soak: no soak.csv on the device" >&2
		exit 1
	fi

	echo "sampler running: $running"
	printf '%s\n' "$csv" | summarize
}

# soak.csv(표준 입력)를 요약한다. 기기 없이 tests/unit/soak.bats가 검증한다.
summarize() {
	awk -F, '
		# nearest-rank 백분위: ceil(n * p)번째 (1부터)
		function rank(n, p,   r) { r = int(n * p); if (r < n * p) r++; return r < 1 ? 1 : r }
		NR == 1 { next }
		{
			n++
			if (n == 1) { first = $1; first_time = $2; free_first = $12 }
			last = $1; last_time = $2; free_last = $12
			# RSS는 daemon이 없던 표본(NA)을 건너뛰고 측정된 처음 · 마지막 값을 쓴다
			if ($8 != "NA") { if (rss_first == "") rss_first = $8; rss_last = $8 }
			if (n > 1 && $1 - prev > max_gap) max_gap = $1 - prev
			prev = $1
			if ($3 != "200") { bad++; bad_list = bad_list "\n    " $2 " http=" $3 " state=" $9 }
			else { lat[++m] = $4 }
			if ($6 != "0") orphan++
			if ($7 != "NA" && $7 != daemon) { if (daemon != "") restarts++; daemon = $7 }
			if ($8 != "NA" && $8 + 0 > rss_max) rss_max = $8 + 0
			if ($10 != "NA") { b = $10 + 0; if (bmin == "" || b < bmin) bmin = b; if (bmax == "" || b > bmax) bmax = b }
			if ($11 != "NA") { t = $11 + 0; if (tmax == "" || t > tmax) tmax = t }
		}
		END {
			printf "samples          %d  (%s → %s, %.1fh)\n", n, first_time, last_time, (last - first) / 3600
			printf "max gap          %ds  (> 2x interval means the sampler or Termux was stopped)\n", max_gap
			printf "non-200          %d%s\n", bad, bad_list
			if (m > 0) {
				# 삽입 정렬 — 표본은 수백 개 수준이다
				for (i = 2; i <= m; i++) { v = lat[i]; j = i - 1; while (j > 0 && lat[j] > v) { lat[j + 1] = lat[j]; j-- } lat[j + 1] = v }
				printf "cold start       p50 %.3fs  p95 %.3fs  max %.3fs\n", lat[rank(m, 0.5)], lat[rank(m, 0.95)], lat[m]
			}
			printf "apps left awake  %d samples  (should be 0 — scale-to-zero / orphans)\n", orphan
			printf "daemon restarts  %d\n", restarts
			printf "daemon RSS       %s → %s KB  (max %d)\n", rss_first, rss_last, rss_max
			printf "battery          %s–%s%%  max temp %s°C\n", bmin == "" ? "NA" : bmin, bmax == "" ? "NA" : bmax, tmax == "" ? "NA" : tmax
			printf "free storage     %s → %s MB\n", free_first, free_last
		}'
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
