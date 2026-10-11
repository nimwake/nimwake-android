# shellcheck shell=sh
# 네트워크 상태 감시 (PRD §13–§14). config.sh 다음에 source한다. host_log는 supervisor.sh에 있다.
#
# 검사 순서 (PRD §14):
#   1. local interface — lo가 아닌 인터페이스가 UP · RUNNING이고 IPv4 주소가 있다
#   2. default route  — Android는 앱의 netlink · /proc/net/route를 막는다. 볼 수 없으므로 3이 대신한다
#   3. LAN gateway    — NIMWAKE_NET_GATEWAY를 ping. 비우면 건너뛴다 (게이트웨이 주소도 앱이 알아낼 수 없다)
#   4. external       — NIMWAKE_NET_INTERNET_URL에 HTTP. 비우면 건너뛴다 (PRD: internet_check = false)
#
# 상태: 1이 실패하면 OFFLINE, 1은 되는데 3 · 4 중 하나가 실패하면 DEGRADED, 모두 되면 ONLINE.
# OFFLINE · DEGRADED에서 ONLINE으로 돌아올 때는 RECOVERING을 거친다 — 여기서 NIMWAKE_NET_ON_RECOVER를 돌린다
# (PRD §13 "Network returns → Ingress integration reconnect", §15: tailscale · cloudflared 등을 다시 붙이는 자리).
# 처음 본 상태가 ONLINE이면 복구가 아니므로 돌리지 않는다.
# 상태가 바뀔 때만 supervisor.log에 남기고 run/network 한 줄 "STATE YYYY-MM-DD HH:MM:SS 이유"에 둔다.
# **네트워크가 끊겨도 Nimwake는 내리지 않는다** (PRD §13) — app은 기기 안에서 계속 쓸 수 있다.
#
# 실기기에서 확인한 것 (Android 13, F-Droid Termux): ifconfig(인자 없이)는 ioctl이라 동작하고
# `ifconfig wlan0`과 `ip`(/system/bin/ip 포함)는 막힌다. ping은 게이트웨이까지 된다.

# lo가 아닌 UP · RUNNING 인터페이스 중 IPv4가 있는 첫 것을 "이름 주소"로 출력한다
net_interface() {
	ifconfig 2>/dev/null | awk '
		/^[^ \t]/ {
			name = $1
			sub(/:$/, "", name)
			up = ($0 ~ /[<,]UP[,>]/ && $0 ~ /[<,]RUNNING[,>]/ && name != "lo")
			next
		}
		up && $1 == "inet" && $2 != "127.0.0.1" {
			print name, $2
			exit
		}
	'
}

net_gateway_ok() {
	ping -c 1 -W 2 "$NIMWAKE_NET_GATEWAY" >/dev/null 2>&1
}

net_internet_ok() {
	curl -s -o /dev/null -m 5 "$NIMWAKE_NET_INTERNET_URL" >/dev/null 2>&1
}

# 상태와 이유를 "STATE 이유"로 출력한다
net_classify() {
	_iface="$(net_interface)"
	if [ -z "$_iface" ]; then
		echo "OFFLINE no interface with an address"
		return
	fi
	if [ -n "$NIMWAKE_NET_GATEWAY" ] && ! net_gateway_ok; then
		echo "DEGRADED $_iface — gateway $NIMWAKE_NET_GATEWAY unreachable"
		return
	fi
	if [ -n "$NIMWAKE_NET_INTERNET_URL" ] && ! net_internet_ok; then
		echo "DEGRADED $_iface — $NIMWAKE_NET_INTERNET_URL unreachable"
		return
	fi
	echo "ONLINE $_iface"
}

# net_record FROM TO 이유
net_record() {
	printf '%s %s %s\n' "$2" "$(date '+%Y-%m-%d %H:%M:%S')" "$3" >"$NIMWAKE_RUN/network"
	host_log "network ${1:-?} → $2 — $3"
}

# 복구 hook. 출력은 supervisor.log로 간다. 걸려도 감시 루프가 멈추지 않게 시간을 제한한다
net_run_recover_hook() {
	[ -n "$NIMWAKE_NET_ON_RECOVER" ] || return 0
	host_log "network: on-recover hook: $NIMWAKE_NET_ON_RECOVER"
	_code=0
	if command -v timeout >/dev/null 2>&1; then
		timeout "$NIMWAKE_NET_HOOK_TIMEOUT" sh -c "$NIMWAKE_NET_ON_RECOVER" >>"$NIMWAKE_LOGS/supervisor.log" 2>&1 || _code=$?
	else
		sh -c "$NIMWAKE_NET_ON_RECOVER" >>"$NIMWAKE_LOGS/supervisor.log" 2>&1 || _code=$?
	fi
	case "$_code" in
	0) host_log "network: on-recover hook ok" ;;
	124) host_log "network: on-recover hook timed out after ${NIMWAKE_NET_HOOK_TIMEOUT}s" ;;
	*) host_log "network: on-recover hook failed (exit $_code)" ;;
	esac
}

check_network() {
	_net="$(net_classify)"
	_state="${_net%% *}"
	_why="${_net#* }"
	_was=""
	if [ -f "$NIMWAKE_RUN/network" ]; then
		_was="$(cut -d' ' -f1 "$NIMWAKE_RUN/network")"
	fi
	if [ "$_state" = "$_was" ]; then
		return 0
	fi
	if [ "$_state" = ONLINE ] && { [ "$_was" = OFFLINE ] || [ "$_was" = DEGRADED ]; }; then
		net_record "$_was" RECOVERING "$_why"
		net_run_recover_hook
		_was=RECOVERING
	fi
	net_record "$_was" "$_state" "$_why"
}
