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
# 가용 메모리(MB)가 이보다 적으면 Core가 app을 깨우지 않는다(503) · 유휴 app을 내린다 (Core PRD §78 · §80).
# 비우면 넘기지 않는다 — Core 기본값 0(꺼짐). 이 flag는 Core v0.1.0-rc4부터 있다: 그 전 binary는 모르는 인자로
# 설정 오류(78)를 낸다. 이 기기에 맞는 값은 측정으로 정한다 (#42, soak.csv의 mem_avail_mb)
: "${NIMWAKE_MIN_FREE_MEMORY_MB:=}"
# 1이면 daemon(그리고 그것이 띄우는 앱)을 proot-distro --isolated로 — Termux 파일 시스템을 guest에 붙이지 않는다.
# 격리하지 않으면 앱이 Termux의 ~/.ssh/authorized_keys · ~/.termux/boot · sshd 호스트 키를 읽고 쓴다 (같은 Android uid,
# 10-14 기기에서 확인). proot는 보안 sandbox가 아니지만 이것이 root 없이 할 수 있는 격리다 (Phase 2 04, T1)
: "${NIMWAKE_ISOLATED:=1}"
_nimwake_isolated=""
[ "$NIMWAKE_ISOLATED" = 1 ] && _nimwake_isolated=" --isolated"

# Core control socket (§85, Core v0.1.2+). 상태를 로그 파싱 없이 묻는다 — `nimwake status --json` (§86, #71).
# 격리된 proot에는 Termux 경로가 보이지 않고, proot 안 경로를 Termux에서 보면 Unix socket 한계(108바이트)를 넘는다
# (rootfs/run/… = 116). 그래서 짧은 Termux 디렉터리 하나만 proot 안 /run/nimwake로 bind한다 — 앱에 보이는 것은
# 그 socket(0600, 같은 uid)뿐이다. Core는 디렉터리를 만들지 않는다(없으면 78) — supervisor가 기동 전에 만든다
: "${NIMWAKE_CONTROL_SOCKET:=1}"
: "${NIMWAKE_CONTROL_DIR:=$NIMWAKE_HOST_HOME/run/core}"
: "${NIMWAKE_CORE_CLI:=${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/containers/ubuntu/rootfs/opt/nimwake/bin/nimwake}"
_nimwake_bind=""
_nimwake_control=""
if [ "$NIMWAKE_CONTROL_SOCKET" = 1 ]; then
	NIMWAKE_SOCKET="$NIMWAKE_CONTROL_DIR/nimwake.sock"
	export NIMWAKE_SOCKET
	_nimwake_bind=" --bind $NIMWAKE_CONTROL_DIR:/run/nimwake"
	_nimwake_control=" --control-socket /run/nimwake/nimwake.sock"
fi

: "${NIMWAKE_LAUNCH:=proot-distro login ubuntu${_nimwake_isolated}${_nimwake_bind} --user nimwake -- $NIMWAKE_DAEMON $NIMWAKE_APPS${NIMWAKE_LISTEN:+ --listen $NIMWAKE_LISTEN}${NIMWAKE_MIN_FREE_MEMORY_MB:+ --min-free-memory-mb $NIMWAKE_MIN_FREE_MEMORY_MB}${_nimwake_control}}"
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

# ingress provider (host/lib/ingress.sh, Phase 2 03). 비우면 ingress 없음 — gateway는 NIMWAKE_LISTEN대로
: "${NIMWAKE_INGRESS:=}"
: "${NIMWAKE_INGRESS_DIR:=$NIMWAKE_HOST_HOME/ingress}"
# 토큰 등 비밀 — 0700, provider만 읽는다. 레포 · 로그에 남기지 않는다 (PRD §40)
: "${NIMWAKE_SECRETS:=$NIMWAKE_HOST_HOME/secrets}"
# 공개할 hostname을 여기의 manifest들에서 읽는다 (proot Ubuntu 안의 ~/.nimwake/apps — Termux에서 본 경로)
: "${NIMWAKE_MANIFESTS:=${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/containers/ubuntu/rootfs/home/nimwake/.nimwake/apps}"
# 앱 묶음 · release · 노출 선언(exposure: public | lan — 없으면 lan)이 있는 곳 (make deploy-app이 쓴다)
: "${NIMWAKE_APP_HOME:=${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/containers/ubuntu/rootfs/home/nimwake/apps}"

# 배터리 · 전원 감시 (host/lib/battery.sh). 정리 작업 주기마다. 잔량이 LOW(%) 아래거나 충전기가 빠졌거나
# 꽂혀 있는데 줄면 supervisor.log와 알림. 읽는 명령은 테스트가 바꾼다
: "${NIMWAKE_BATTERY_WATCH:=1}"
: "${NIMWAKE_BATTERY_LOW:=20}"
: "${NIMWAKE_BATTERY_CMD:=timeout 10 termux-battery-status}"

# 알림 명령. 메시지는 $1, 종류(storage · battery)는 $2로 받는다 — 종류마다 알림이 따로 남는다.
# 비우면 supervisor.log에만 남긴다
if [ -z "${NIMWAKE_NOTIFY+set}" ]; then
	if command -v termux-notification >/dev/null 2>&1; then
		# shellcheck disable=SC2016 # $1 · $2는 알릴 때 sh -c가 푼다
		NIMWAKE_NOTIFY='termux-notification --id "nimwake-${2:-alert}" --title Nimwake --content "$1"'
	else
		NIMWAKE_NOTIFY=''
	fi
fi

NIMWAKE_RUN="$NIMWAKE_HOST_HOME/run"
NIMWAKE_LOGS="$NIMWAKE_HOST_HOME/logs"
mkdir -p "$NIMWAKE_RUN" "$NIMWAKE_LOGS"
