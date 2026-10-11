#!/bin/sh
# A5 — LAN에서 본 lifecycle과 Wi-Fi 복구. (PRD §13, §44-3, Core PRD §50)
#
#   network.sh lan    개발 머신 → LAN → 기기: health · cold → same PID → sleep → new PID ·
#                     동시 cold start N개가 process 하나로 합쳐지는지
#   network.sh wifi   Wi-Fi를 껐다 켜는 동안 LAN 접근이 끊겼다 돌아오는지 추적한다.
#                     daemon은 재시작 없이 그대로여야 한다 (PRD §13: 네트워크 장애로 Nimwake를 내리지 않는다)
#
# 기기의 nimwaked가 LAN에 열려 있어야 한다 — ~/.nimwake-host/host.conf에 NIMWAKE_LISTEN=0.0.0.0:8080
# (Core 기본값은 loopback이다. 노출은 opt-in — Core PRD §74)
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone). 기기 IP는 ssh 설정의 HostName에서 읽는다
#   NIMWAKE_PORT    gateway port (기본 8080)
#   CONCURRENCY     동시 cold start 요청 수 (기본 20)
#   IDLE_WAIT       idle → sleep 대기 초 (기본 10)
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"
port="${NIMWAKE_PORT:-8080}"
concurrency="${CONCURRENCY:-20}"
idle_wait="${IDLE_WAIT:-10}"

# ssh -G는 접속하지 않고 설정만 푼다
ip="$(ssh -G "$device" 2>/dev/null | awk '$1 == "hostname" { print $2 }')"
gateway="http://$ip:$port/"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

# 표준 출력: "<http_code> <body>"
lan_get() {
	_body="$(mktemp)"
	_code="$(curl -s -m 30 -o "$_body" -w '%{http_code}' -H "Host: $1" "$gateway" 2>/dev/null || true)"
	echo "${_code:-000} $(tr -d '\n' <"$_body")"
	rm -f "$_body"
}

lan_health() {
	[ "$(lan_get nimwake-health.invalid | cut -d' ' -f1)" = 404 ]
}

daemon_pid() {
	ssh -o ConnectTimeout=5 "$device" "pgrep -f '^/opt/nimwake/bin/nimwaked' | head -n 1" 2>/dev/null || true
}

app_alive() {
	ssh "$device" "[ -d /proc/$1 ]"
}

cmd_lan() {
	echo "== LAN $gateway"
	lan_health || fail "no 404 from $gateway — is NIMWAKE_LISTEN=0.0.0.0:$port set in ~/.nimwake-host/host.conf?"
	echo "ok  health probe 404 over LAN"

	# 다른 요청이 app을 깨워 두었을 수 있으므로 먼저 잠들 때까지 기다린다
	sleep "$idle_wait"

	# shellcheck disable=SC2046 # "code pid"를 두 인자로 나눈다
	set -- $(lan_get echo.local)
	[ "$1" = 200 ] || fail "cold request: http $1"
	cold="$2"
	# shellcheck disable=SC2046 # "code pid"를 두 인자로 나눈다
	set -- $(lan_get echo.local)
	if [ "$1" != 200 ] || [ "$2" != "$cold" ]; then
		fail "warm request: expected pid $cold, got http $1 pid ${2:-}"
	fi
	echo "ok  cold → warm over LAN  pid=$cold (same PID)"

	sleep "$idle_wait"
	if app_alive "$cold"; then
		fail "pid $cold still alive after ${idle_wait}s idle"
	fi
	echo "ok  sleep        pid=$cold gone"

	# 동시 cold start: N개 요청이 process 하나로 합쳐져야 한다 (Core 핵심 불변식)
	out="$(mktemp -d)"
	i=0
	while [ "$i" -lt "$concurrency" ]; do
		lan_get echo.local >"$out/$i" &
		i=$((i + 1))
	done
	wait
	codes="$(cut -d' ' -f1 "$out"/* | sort | uniq -c | tr -s ' ')"
	pids="$(awk '$1 == 200 { print $2 }' "$out"/* | sort -u)"
	rm -rf "$out"
	[ "$(printf '%s\n' "$codes" | tr -d ' ')" = "${concurrency}200" ] || fail "concurrent cold start: http codes:$codes"
	[ "$(printf '%s\n' "$pids" | wc -l | tr -d ' ')" = 1 ] || fail "concurrent cold start spawned more than one process: $pids"
	echo "ok  $concurrency concurrent cold requests → one process (pid $pids)"

	echo "PASS lan"
}

cmd_wifi() {
	lan_health || fail "no 404 from $gateway before the test — run network.sh lan first"
	before="$(daemon_pid)"
	[ -n "$before" ] || fail "cannot read the nimwaked pid over ssh"
	echo "nimwaked pid=$before. Now turn Wi-Fi OFF on the phone, wait ~30s, then turn it back ON."
	echo "watching $gateway (up to 10 minutes)..."
	# supervisor.log의 시각과 비교하므로 기기 시계로 받아 둔다
	device_start="$(ssh "$device" "date '+%Y-%m-%d %H:%M:%S'")"

	start="$(date +%s)"
	down_at=""
	while :; do
		now="$(date +%s)"
		[ $((now - start)) -lt 600 ] || fail "LAN access did not go down and come back within 10 minutes"
		if lan_health; then
			if [ -n "$down_at" ]; then
				echo "ok  LAN back after $((now - down_at))s"
				break
			fi
		elif [ -z "$down_at" ]; then
			down_at="$now"
			echo "..  LAN down at $(date '+%H:%M:%S')"
		fi
		sleep 2
	done

	after="$(daemon_pid)"
	[ "$after" = "$before" ] || fail "nimwaked pid changed $before → ${after:-none} — it should survive a network outage"
	echo "ok  nimwaked survived (pid $after)"

	# shellcheck disable=SC2046 # "code pid"를 두 인자로 나눈다
	set -- $(lan_get echo.local)
	[ "$1" = 200 ] || fail "request after reconnect: http $1"
	echo "ok  request after reconnect → 200 (pid $2)"

	# supervisor도 끊김과 복구를 보았는가 (host/lib/network.sh). 30초마다 보므로 짧은 끊김은 놓칠 수 있다 —
	# 그래서 실패가 아니라 경고다. 판정은 위의 LAN 복구 · daemon 생존이다
	# shellcheck disable=SC2016 # $HOME은 기기에서 푼다
	sup_log='$HOME/.nimwake-host/logs/supervisor.log'
	seen=""
	i=0
	while [ "$i" -lt 45 ]; do
		seen="$(ssh "$device" "grep -E 'network .* → ' $sup_log 2>/dev/null | awk -v t='$device_start' '\$1 \" \" \$2 >= t'" || true)"
		printf '%s\n' "$seen" | grep -q '→ ONLINE' && break
		sleep 2
		i=$((i + 2))
	done
	if printf '%s\n' "$seen" | grep -q '→ ONLINE'; then
		printf '%s\n' "$seen" | sed 's/^/    /'
		echo "ok  supervisor recorded the outage and the recovery"
	else
		echo "WARN supervisor recorded no network change since the test began (outage shorter than NIMWAKE_NET_INTERVAL, or an older nimwake-host)"
	fi
	echo "PASS wifi"
}

case "${1:-}" in
lan) cmd_lan ;;
wifi) cmd_wifi ;;
*)
	echo "usage: network.sh lan | wifi" >&2
	exit 2
	;;
esac
