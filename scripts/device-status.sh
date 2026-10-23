#!/bin/sh
# 기기에 지금 무엇이 돌고 있는지 한 번에 본다 — Core binary · supervisor · soak.
# 이 기기는 여러 작업(사람 · 세션)이 같이 쓴다. 배포 · bench · 재시작 전에 먼저 본다. 읽기만 한다.
#
#   device-status.sh                 상태를 출력한다
#   device-status.sh --soak-running  soak이 진행 중이면 0과 그 이유를, 아니면 1을 돌려준다
#                                    (deploy.sh · bench.sh가 쓴다)
#
# soak 진행 중 = sampler가 살아 있다(명령줄이 nimwake-soak — pid 재사용 대비, #20)
#                또는 run/soak.active의 끝 시각이 아직 오지 않았다(재부팅으로 sampler가 잠시 없을 때 — #19)
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"
mode="${1:-}"

case "$mode" in
"" | --soak-running) ;;
*)
	echo "usage: device-status.sh [--soak-running]" >&2
	exit 2
	;;
esac

# 기기에서 돈다. 첫 줄: "soak yes|no 이유", 그 뒤는 사람이 읽는 상태
# `{ … } </dev/null`: 안의 명령이 표준 입력(=이 스크립트)을 삼키지 못하게 한다 (deploy.sh 참고)
out="$(ssh "$device" sh -s <<'EOF'
{
h="$HOME/.nimwake-host"
now="$(date +%s)"
fmt() { date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "$1"; } # portable-ok: 기기(Termux, GNU)에서 돈다

soak=no
why="no sampler, no soak.active"
pid="$(cat "$h/run/soak.pid" 2>/dev/null || true)"
alive=""
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && ps -o args= -p "$pid" 2>/dev/null | grep -q nimwake-soak; then
	alive="$pid"
fi
end=""
interval=""
if [ -f "$h/run/soak.active" ]; then
	read -r end interval <"$h/run/soak.active" || true
fi
if [ -n "$alive" ]; then
	soak=yes
	why="sampler pid $alive"
	[ -n "$end" ] && why="$why, until $(fmt "$end")"
elif [ -n "$end" ] && [ "$end" -gt "$now" ] 2>/dev/null; then
	soak=yes
	why="soak.active until $(fmt "$end") (sampler not running — resumes on boot via 20-soak)"
fi
echo "soak $soak $why"

core="$(proot-distro login ubuntu -- sed -n 's/^\(ref\|commit\)=//p' /opt/nimwake/BUILD_INFO 2>/dev/null | tr '\n' ' ')"
echo "core        ${core:-unknown}(installed binary)"
# 메모리에 있는 binary — Core에게 직접 묻는다 (control socket §85). 없으면 nimwaked.log의 마지막 버전 줄
sock="$h/run/core/nimwake.sock"
cli="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/opt/nimwake/bin/nimwake"
running=""
if [ -S "$sock" ] && [ -x "$cli" ]; then
	running="$("$cli" status --json --socket "$sock" 2>/dev/null | sed -n 's/.*"version":"\([^"]*\)".*/nimwaked \1/p')"
fi
if [ -n "$running" ]; then
	echo "running     $running (control socket — the binary actually in memory)"
else
	running="$(grep -o 'nimwaked [0-9][0-9a-z.-]*' "$h/logs/nimwaked.log" 2>/dev/null | tail -n 1)"
	echo "running     ${running:-unknown} (last line in nimwaked.log — the binary actually in memory)"
fi
if command -v nimwake-host >/dev/null 2>&1; then
	nimwake-host status 2>/dev/null | sed 's/^/host        /'
fi
if [ -f "$h/logs/soak.csv" ]; then
	samples=$(($(wc -l <"$h/logs/soak.csv") - 1))
	first="$(sed -n 2p "$h/logs/soak.csv" | cut -d, -f2)"
	last="$(tail -n 1 "$h/logs/soak.csv" | cut -d, -f2)"
	echo "soak.csv    $samples samples, $first → $last"
fi
echo "uptime      since $(uptime -s 2>/dev/null || echo unknown)"
} </dev/null
EOF
)"

soak_line="$(printf '%s\n' "$out" | head -n 1)"
if [ "$mode" = --soak-running ]; then
	case "$soak_line" in
	"soak yes "*)
		echo "${soak_line#soak yes }"
		exit 0
		;;
	*) exit 1 ;;
	esac
fi

echo "== $device"
case "$soak_line" in
"soak yes "*) echo "soak        RUNNING — ${soak_line#soak yes } — do not deploy, restart or bench" ;;
*) echo "soak        none" ;;
esac
printf '%s\n' "$out" | sed 1d
