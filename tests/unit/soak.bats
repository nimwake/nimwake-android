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

# 재부팅 대응: 새로 시작하면 끝 시각을 남기고, --resume(20-soak)은 그 시각까지 이어서 돈다

@test "a fresh soak records its end time and interval in soak.active" {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	before="$(date +%s)"
	NIMWAKE_SOAK_SAMPLES=1 run "$root/host/bin/nimwake-soak" 1 2
	[ "$status" -eq 0 ]

	read -r end interval <"$HOME/.nimwake-host/run/soak.active"
	[ "$interval" -eq 1 ]
	[ "$end" -ge $((before + 7200)) ]
	[ "$end" -le $((before + 7205)) ]
}

@test "--resume continues the same soak.csv until the recorded end" {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME/.nimwake-host/run" "$HOME/.nimwake-host/logs"
	echo "$header" >"$HOME/.nimwake-host/logs/soak.csv"
	echo "1000,earlier,200,0.040,1,0,1,1,RUNNING,80,30.0,1" >>"$HOME/.nimwake-host/logs/soak.csv"
	echo "$(($(date +%s) + 3600)) 1" >"$HOME/.nimwake-host/run/soak.active"

	NIMWAKE_SOAK_SAMPLES=1 run "$root/host/bin/nimwake-soak" --resume
	[ "$status" -eq 0 ]
	[ "$(wc -l <"$HOME/.nimwake-host/logs/soak.csv" | tr -d ' ')" -eq 3 ]
	[ -f "$HOME/.nimwake-host/run/soak.active" ]
}

@test "--resume after the end time clears soak.active and samples nothing" {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME/.nimwake-host/run"
	echo "$(($(date +%s) - 10)) 1" >"$HOME/.nimwake-host/run/soak.active"

	run "$root/host/bin/nimwake-soak" --resume
	[ "$status" -eq 0 ]
	[ ! -f "$HOME/.nimwake-host/run/soak.active" ]
	[ ! -f "$HOME/.nimwake-host/logs/soak.csv" ]
}

@test "--resume without an active soak does nothing" {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	run "$root/host/bin/nimwake-soak" --resume
	[ "$status" -eq 0 ]
	[ ! -f "$HOME/.nimwake-host/logs/soak.csv" ]
}

@test "a second sampler does not start while one is running" {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME/.nimwake-host/run"
	# 명령줄에 nimwake-soak가 있는 가짜 sampler
	printf '#!/bin/sh\nsleep 30\n' >"$BATS_TEST_TMPDIR/nimwake-soak"
	chmod +x "$BATS_TEST_TMPDIR/nimwake-soak"
	"$BATS_TEST_TMPDIR/nimwake-soak" &
	running=$!
	echo "$running" >"$HOME/.nimwake-host/run/soak.pid"
	echo "$(($(date +%s) + 3600)) 1" >"$HOME/.nimwake-host/run/soak.active"

	NIMWAKE_SOAK_SAMPLES=1 run "$root/host/bin/nimwake-soak" --resume
	kill "$running"
	[ "$status" -eq 0 ]
	[[ "$output" == *"already running"* ]]
	[ ! -f "$HOME/.nimwake-host/logs/soak.csv" ]
}

# 재부팅 뒤 남은 pid 파일의 번호를 다른 process가 받았을 수 있다 — 그것을 sampler로 보면 soak이 멈춘다
@test "a stale pid reused by another process does not block --resume" {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME/.nimwake-host/run"
	sleep 30 &
	other=$!
	echo "$other" >"$HOME/.nimwake-host/run/soak.pid"
	echo "$(($(date +%s) + 3600)) 1" >"$HOME/.nimwake-host/run/soak.active"

	NIMWAKE_SOAK_SAMPLES=1 run "$root/host/bin/nimwake-soak" --resume
	kill "$other"
	[ "$status" -eq 0 ]
	[ "$(wc -l <"$HOME/.nimwake-host/logs/soak.csv" | tr -d ' ')" -eq 2 ]
}

sample_csv() {
	cat <<EOF
$header
1000,2026-10-09 00:00:00,200,0.040,101,0,9000,2000,RUNNING,80,30.0,100000
1300,2026-10-09 00:05:00,200,0.030,102,0,9000,2100,RUNNING,81,31.0,100000
1600,2026-10-09 00:10:00,000,NA,NA,0,NA,NA,BACKOFF,82,32.0,99990
1900,2026-10-09 00:15:00,200,0.050,103,1,9100,1900,RUNNING,83,35.5,99980
2800,2026-10-09 00:30:00,200,0.060,104,0,9100,2200,RUNNING,84,33.0,99970
EOF
}

@test "summarize counts samples, failures, restarts and orphans" {
	run sh -c "\"$soak\" summarize" < <(sample_csv)
	echo "$output"
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

# macOS(one-true-awk) · Linux(mawk · gawk)에서 요약이 같아야 한다. 이 머신에 있는 구현을 모두 돌린다.
@test "summary is identical across the awk implementations on this machine" {
	summary="$root/tests/device/soak-summary.awk"
	expected="$(sample_csv | awk -F, -f "$summary")"
	for impl in mawk "gawk --posix" original-awk nawk "busybox awk"; do
		command -v "${impl%% *}" >/dev/null 2>&1 || continue
		got="$(sample_csv | $impl -F, -f "$summary" 2>&1)"
		if [ "$got" != "$expected" ]; then
			echo "== $impl differs:"
			echo "$got"
			return 1
		fi
		echo "ok  $impl"
	done
}
