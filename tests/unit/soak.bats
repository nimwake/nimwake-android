#!/usr/bin/env bats
# soak — 기기 sampler의 CSV 형식과 개발 머신 쪽 요약. 실제 soak은 기기에서 돈다.

setup() {
	root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	soak="$root/tests/device/soak.sh"
}

header='epoch,time,http,seconds,app_pid,apps_before,daemon_pid,daemon_rss_kb,state,battery_pct,battery_temp_c,free_mb'

@test "the sampler writes one well-formed row per sample" {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	NIMWAKE_SOAK_SAMPLES=2 run "$root/host/bin/nimwake-soak" 1 1
	[ "$status" -eq 0 ]

	csv="$HOME/.nimwake-host/logs/soak.csv"
	[ "$(head -n 1 "$csv")" = "$header" ]
	[ "$(wc -l <"$csv" | tr -d ' ')" -eq 3 ]
	# 기기가 아니므로 gateway가 없다 → http 000, 그래도 열 수는 같다
	awk -F, 'NR > 1 && NF != 12 { exit 1 }' "$csv"
	awk -F, 'NR > 1 && $3 != "000" { exit 1 }' "$csv"
	[ ! -f "$HOME/.nimwake-host/run/soak.pid" ]
}

@test "summarize counts samples, failures, restarts and orphans" {
	run "$soak" summarize <<EOF
$header
1000,2026-10-09 00:00:00,200,0.040,101,0,9000,2000,RUNNING,80,30.0,100000
1300,2026-10-09 00:05:00,200,0.030,102,0,9000,2100,RUNNING,81,31.0,100000
1600,2026-10-09 00:10:00,000,NA,NA,0,NA,NA,BACKOFF,82,32.0,99990
1900,2026-10-09 00:15:00,200,0.050,103,1,9100,1900,RUNNING,83,35.5,99980
2800,2026-10-09 00:30:00,200,0.060,104,0,9100,2200,RUNNING,84,33.0,99970
EOF
	[ "$status" -eq 0 ]
	[[ "$output" == *"samples          5"* ]]
	[[ "$output" == *"max gap          900s"* ]]
	[[ "$output" == *"non-200          1"* ]]
	[[ "$output" == *"http=000 state=BACKOFF"* ]]
	# 200인 표본 4개: 0.030 0.040 0.050 0.060 → nearest-rank p50은 2번째, p95는 4번째
	[[ "$output" == *"p50 0.040s  p95 0.060s  max 0.060s"* ]]
	[[ "$output" == *"apps left awake  1 samples"* ]]
	[[ "$output" == *"daemon restarts  1"* ]]
	[[ "$output" == *"daemon RSS       2000 → 2200 KB  (max 2200)"* ]]
	[[ "$output" == *"max temp 35.5°C"* ]]
}
