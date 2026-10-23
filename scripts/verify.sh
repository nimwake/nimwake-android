#!/bin/sh
# 사람 손이 필요 없는 기기 검증을 한 번에 — 릴리스 전 · 배포 뒤 · 의심스러울 때. (v1.0 기준 3)
#
#   doctor        [FAIL]이 없다
#   socket        Core control socket이 응답한다 (nimwake status --json, §85)
#   power         Termux:API로 배터리를 읽는다 · 충전기에 꽂혀 있고 방전 중이 아니다
#   lifecycle     make test-device — cold → warm(같은 pid) → idle 정지 → 새 pid
#   recovery      make test-recovery — kill -9 → 재기동 · exit 78 → UNHEALTHY · 잔존 0
#   lan           make test-lan — LAN에 열려 있을 때만 (NIMWAKE_LISTEN=0.0.0.0:…), 아니면 SKIP
#   app           make test-app HOST=… — 설치된 앱이 있을 때만 (기본 blog.local · APP_HOST로 바꾼다)
#
# 사람이 필요한 것(재부팅 · Wi-Fi 끊기 · 초기화 설치)은 넣지 않는다 — make test-boot · test-wifi · install.
# recovery가 daemon을 내렸다 올리므로 soak 중이면 거부한다 — FORCE=1.
# 각 단계의 전체 출력은 dist/verify/<UTC>/에, 요약은 끝에 표로 (그리고 summary.md).
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -u

root="$(cd "$(dirname "$0")/.." && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"

if [ "${FORCE:-}" != 1 ] && why="$("$root/scripts/device-status.sh" --soak-running)"; then
	echo "verify: a soak is running ($why) — recovery restarts the daemon. FORCE=1" >&2
	exit 1
fi

out="$root/dist/verify/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$out"
rows=""
failed=0

# step NAME COMMAND... — 출력은 out/NAME.log, 결과 줄을 rows에. 명령의 마지막 줄을 요약으로
step() {
	_name="$1"
	shift
	_start="$(date +%s)"
	printf '== %-10s ' "$_name"
	if "$@" >"$out/$_name.log" 2>&1; then
		_result=PASS
	else
		_rc=$?
		if [ "$_rc" -eq 77 ]; then
			_result=SKIP
		else
			_result=FAIL
			failed=$((failed + 1))
		fi
	fi
	_secs=$(($(date +%s) - _start))
	_last="$(grep -v '^$' "$out/$_name.log" | tail -n 1 | cut -c1-90)"
	echo "$_result (${_secs}s) $_last"
	rows="$rows| $_name | $_result | ${_secs}s | $(printf '%s' "$_last" | sed 's/|/\\|/g') |
"
}

# 77 = SKIP (autotools 관례)
check_doctor() {
	"$root/scripts/doctor.sh" || true
	! grep -q '^\[FAIL\]' "$out/doctor.log"
}
check_socket() {
	ssh "$device" '. "$HOME/.nimwake-host/lib/config.sh" && "$NIMWAKE_CORE_CLI" status --json --socket "$NIMWAKE_SOCKET"' </dev/null | tee /dev/stderr |
		grep -q '"contract":1'
}
check_power() {
	json="$(ssh "$device" 'timeout 10 termux-battery-status' </dev/null | tr -d '\n ')" # portable-ok: timeout은 기기(Termux)에서 돈다
	echo "$json"
	pct="$(printf '%s' "$json" | sed -n 's/.*"percentage":\([0-9]*\).*/\1/p')"
	plugged="$(printf '%s' "$json" | sed -n 's/.*"plugged":"\([A-Z_]*\)".*/\1/p')"
	st="$(printf '%s' "$json" | sed -n 's/.*"status":"\([A-Z_]*\)".*/\1/p')"
	[ -n "$pct" ] || { echo "battery unreadable — open the Termux:API app once"; return 1; }
	echo "battery ${pct}% $plugged $st"
	[ "$plugged" != UNPLUGGED ] && [ "$st" != DISCHARGING ]
}
check_lan() {
	if ! ssh "$device" 'grep -q "^NIMWAKE_LISTEN=0\.0\.0\.0:" "$HOME/.nimwake-host/host.conf"' </dev/null; then
		echo "skipped — the gateway is not open to the LAN (NIMWAKE_LISTEN)"
		return 77
	fi
	"$root/tests/device/network.sh" lan
}
check_app() {
	host="${APP_HOST:-blog.local}"
	if ! "$root/scripts/apps.sh" list 2>/dev/null | awk -v h="$host" '$2 == h { found = 1 } END { exit !found }'; then
		echo "skipped — no app with host $host (APP_HOST=…)"
		return 77
	fi
	FORCE="${FORCE:-}" "$root/tests/device/app.sh" "$host" 2 >"$out/app.detail" 2>&1
	rc=$?
	cat "$out/app.detail"
	# 요약 줄: cold start들과 마지막 RSS
	cold="$(sed -n 's/^round [0-9]* cold [0-9]* \([0-9.]*\).*/\1/p' "$out/app.detail" | cut -c1-5 | tr '\n' ' ')"
	rss="$(sed -n 's/^round [0-9]* rss_mb \([0-9.]*\).*/\1/p' "$out/app.detail" | tail -n 1)"
	echo "$host cold ${cold:-?}s · rss ${rss:-?} MB"
	return "$rc"
}

echo "verify: $device → $out"
step doctor check_doctor
step socket check_socket
step power check_power
step lifecycle "$root/tests/device/lifecycle.sh"
step recovery "$root/tests/device/recovery.sh"
step lan check_lan
step app check_app

{
	echo "# nimwake-android verify — $(date -u '+%Y-%m-%d %H:%M:%SZ')"
	echo
	echo "\`$(git -C "$root" describe --tags --always --dirty 2>/dev/null)\` · Core \`$(sed -n 's/^tag=//p' "$root/core.lock")\` · device \`$device\`"
	echo
	echo "| step | result | time | last line |"
	echo "| ---- | ------ | ---- | --------- |"
	printf '%s' "$rows"
} >"$out/summary.md"

echo
if [ "$failed" -eq 0 ]; then
	echo "verify: PASS — $out/summary.md"
else
	echo "verify: $failed FAILED — read $out/<step>.log" >&2
	exit 1
fi
