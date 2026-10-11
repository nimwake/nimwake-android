# shellcheck shell=sh
# Host Layer 설정. ~/.nimwake-host/host.conf (KEY=value, shell이 source한다)가 있으면 읽고
# 없는 값은 아래 기본값을 쓴다. 형식 결정: Phase 1 D-A2. 예시: host/host.conf.example
#
# 기기 밖(WSL의 bats)에서도 돌 수 있도록 기동 · probe 명령을 설정으로 바꿀 수 있다.

NIMWAKE_HOST_HOME="${NIMWAKE_HOST_HOME:-$HOME/.nimwake-host}"

if [ -f "$NIMWAKE_HOST_HOME/host.conf" ]; then
	# shellcheck source=/dev/null
	. "$NIMWAKE_HOST_HOME/host.conf"
fi

# nimwaked (proot Ubuntu 안)
: "${NIMWAKE_DAEMON:=/opt/nimwake/bin/nimwaked}"
: "${NIMWAKE_APPS:=/home/nimwake/.nimwake/apps}"
# 비우면 Core 기본값(127.0.0.1:8080). LAN에 열려면 0.0.0.0:8080 — opt-in이다 (Core PRD §74)
: "${NIMWAKE_LISTEN:=}"

: "${NIMWAKE_LAUNCH:=proot-distro login ubuntu --user nimwake -- $NIMWAKE_DAEMON $NIMWAKE_APPS${NIMWAKE_LISTEN:+ --listen $NIMWAKE_LISTEN}}"
# proot 아래에서 comm이 잘리므로 전체 경로로 찾는다. `^`는 래퍼(proot, sh -c)를 제외한다 (validation/01)
: "${NIMWAKE_DAEMON_MATCH:=^$NIMWAKE_DAEMON}"

# health probe — 미등록 Host는 어떤 app도 깨우지 않는다 (Core PRD §74)
_nimwake_port="${NIMWAKE_LISTEN##*:}"
: "${NIMWAKE_GATEWAY:=http://127.0.0.1:${_nimwake_port:-8080}/}"
# 비우면 기본 probe(curl → 404). 테스트는 성공/실패만 돌려주는 명령으로 바꾼다
: "${NIMWAKE_PROBE:=}"

# 시간 (초)
: "${NIMWAKE_STARTUP_TIMEOUT:=60}"
: "${NIMWAKE_HEALTH_INTERVAL:=30}"
: "${NIMWAKE_HEALTH_FAILURES:=3}"
: "${NIMWAKE_STOP_TIMEOUT:=30}"

# 재기동 (PRD §23–§24)
: "${NIMWAKE_MAX_RESTARTS:=5}"
: "${NIMWAKE_RESTART_WINDOW:=300}"

# 정리 작업(저장공간 검사 · 로그 순환)을 RUNNING 동안 몇 초마다 할지
: "${NIMWAKE_HOUSEKEEPING_INTERVAL:=600}"

# 남은 저장공간 감시 (PRD §18, §44-6). 기준은 10-nimwake의 부팅 검사와 같다
: "${NIMWAKE_MIN_FREE_MB:=1024}"
: "${NIMWAKE_STORAGE_PATH:=$HOME}"
# 1이면 부족할 때 알리기 전에 순환된 이전 로그를 지운다. 0이면 알리기만 한다
: "${NIMWAKE_STORAGE_CLEANUP:=1}"

# 로그 순환 (PRD §20) — 파일당 상한(KB)과 남길 이전 파일 수. 기본은 PRD의 20 MB × 3
: "${NIMWAKE_LOG_MAX_KB:=20480}"
: "${NIMWAKE_LOG_KEEP:=3}"

# 네트워크 상태 감시 (PRD §13–§14, host/lib/network.sh). 게이트웨이 · 외부 검사는 비우면 건너뛴다
: "${NIMWAKE_NET_INTERVAL:=30}"
: "${NIMWAKE_NET_GATEWAY:=}"
: "${NIMWAKE_NET_INTERNET_URL:=}"
# OFFLINE · DEGRADED에서 돌아올 때 돌릴 명령 (ingress 재연결 등, PRD §15). 비우면 상태만 바뀐다
: "${NIMWAKE_NET_ON_RECOVER:=}"
: "${NIMWAKE_NET_HOOK_TIMEOUT:=60}"

# 알림 명령. 메시지는 $1로 받는다. 비우면 supervisor.log에만 남긴다
if [ -z "${NIMWAKE_NOTIFY+set}" ]; then
	if command -v termux-notification >/dev/null 2>&1; then
		# shellcheck disable=SC2016 # $1은 알릴 때 sh -c가 푼다
		NIMWAKE_NOTIFY='termux-notification --id nimwake-storage --title Nimwake --content "$1"'
	else
		NIMWAKE_NOTIFY=''
	fi
fi

NIMWAKE_RUN="$NIMWAKE_HOST_HOME/run"
NIMWAKE_LOGS="$NIMWAKE_HOST_HOME/logs"
mkdir -p "$NIMWAKE_RUN" "$NIMWAKE_LOGS"
