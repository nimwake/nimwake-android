#!/usr/bin/env bats
# host/lib/network.sh — 네트워크 상태 감시 (PRD §13–§14).
# ifconfig · ping · curl을 셸 함수로 바꿔 기기 없이 상태 판정을 본다.
# data/ifconfig-android.txt는 실기기(Galaxy A51, Android 13, Termux net-tools)에서 받은 그대로다.

setup() {
	root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	data="$BATS_TEST_DIRNAME/data"
	export NIMWAKE_HOST_HOME="$BATS_TEST_TMPDIR/host"
	. "$root/host/lib/config.sh"
	. "$root/host/lib/supervisor.sh"
	. "$root/host/lib/alert.sh"
	. "$root/host/lib/network.sh"
	log="$NIMWAKE_LOGS/supervisor.log"

	IFCONFIG_OUT="$data/ifconfig-android.txt"
	GATEWAY_UP=1
	INTERNET_UP=1
}

ifconfig() { cat "$IFCONFIG_OUT"; }
ping() { [ "$GATEWAY_UP" = 1 ]; }
curl() { [ "$INTERNET_UP" = 1 ]; }

state() { cut -d' ' -f1 "$NIMWAKE_RUN/network"; }

@test "the interface is read from Android's ifconfig output, skipping lo" {
	[ "$(net_interface)" = "wlan0 192.168.0.25" ]
}

@test "an interface that is down or has no address does not count" {
	IFCONFIG_OUT="$BATS_TEST_TMPDIR/ifconfig"
	cat >"$IFCONFIG_OUT" <<'EOF'
lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
        inet 127.0.0.1  netmask 255.0.0.0

wlan0: flags=4099<UP,BROADCAST,MULTICAST>  mtu 1500
        inet 192.168.0.25  netmask 255.255.255.0

rmnet0: flags=4163<UP,RUNNING>  mtu 1500
        unspec 00-00-00-00
EOF
	[ -z "$(net_interface)" ]
}

@test "another interface counts when it is the one that is up (mobile data)" {
	IFCONFIG_OUT="$BATS_TEST_TMPDIR/ifconfig"
	cat >"$IFCONFIG_OUT" <<'EOF'
rmnet_data0: flags=65<UP,RUNNING>  mtu 1500
        inet 10.20.30.40  netmask 255.255.255.252
EOF
	[ "$(net_interface)" = "rmnet_data0 10.20.30.40" ]
}

@test "with no gateway or internet check configured, an address means ONLINE" {
	[ "$(net_classify)" = "ONLINE wlan0 192.168.0.25" ]
}

@test "no interface → OFFLINE" {
	IFCONFIG_OUT=/dev/null
	[ "$(net_classify)" = "OFFLINE no interface with an address" ]
}

@test "unreachable gateway or internet → DEGRADED, only when configured" {
	GATEWAY_UP=0
	INTERNET_UP=0
	# 설정하지 않은 검사는 실패해도 상태를 바꾸지 않는다
	[ "$(net_classify)" = "ONLINE wlan0 192.168.0.25" ]

	NIMWAKE_NET_GATEWAY=192.168.0.1
	[ "$(net_classify)" = "DEGRADED wlan0 192.168.0.25 — gateway 192.168.0.1 unreachable" ]

	GATEWAY_UP=1
	NIMWAKE_NET_INTERNET_URL=http://example.invalid/
	[ "$(net_classify)" = "DEGRADED wlan0 192.168.0.25 — http://example.invalid/ unreachable" ]

	INTERNET_UP=1
	[ "$(net_classify)" = "ONLINE wlan0 192.168.0.25" ]
}

@test "check_network logs only transitions and keeps the time of the last change" {
	check_network
	[ "$(state)" = ONLINE ]
	since="$(cut -d' ' -f2-3 "$NIMWAKE_RUN/network")"
	check_network
	[ "$(grep -c "network " "$log")" -eq 1 ]
	grep -q "network ? → ONLINE — wlan0 192.168.0.25" "$log"
	[ "$(cut -d' ' -f2-3 "$NIMWAKE_RUN/network")" = "$since" ]

	IFCONFIG_OUT=/dev/null
	check_network
	check_network
	[ "$(state)" = OFFLINE ]
	grep -q "network ONLINE → OFFLINE — no interface with an address" "$log"

	IFCONFIG_OUT="$data/ifconfig-android.txt"
	check_network
	grep -q "network OFFLINE → RECOVERING" "$log"
	grep -q "network RECOVERING → ONLINE" "$log"
	[ "$(state)" = ONLINE ]
}

# 복구 (PRD §13 "Network returns → Ingress integration reconnect")

@test "the recover hook runs only when coming back from OFFLINE or DEGRADED" {
	export NIMWAKE_NET_ON_RECOVER="echo reconnected >>\"$BATS_TEST_TMPDIR/hook\""
	# 처음 본 ONLINE은 복구가 아니다
	check_network
	[ ! -f "$BATS_TEST_TMPDIR/hook" ]
	! grep -q RECOVERING "$log"

	NIMWAKE_NET_GATEWAY=192.168.0.1
	GATEWAY_UP=0
	check_network
	[ "$(state)" = DEGRADED ]
	[ ! -f "$BATS_TEST_TMPDIR/hook" ]

	GATEWAY_UP=1
	check_network
	[ "$(state)" = ONLINE ]
	[ "$(cat "$BATS_TEST_TMPDIR/hook")" = reconnected ]
	grep -q "network DEGRADED → RECOVERING" "$log"
	grep -q "network: on-recover hook ok" "$log"
	# 순서: RECOVERING → hook → ONLINE
	recovering="$(grep -n "→ RECOVERING" "$log" | cut -d: -f1)"
	hook="$(grep -n "hook ok" "$log" | cut -d: -f1)"
	online="$(grep -n "RECOVERING → ONLINE" "$log" | cut -d: -f1)"
	[ "$recovering" -lt "$hook" ] && [ "$hook" -lt "$online" ]

	# 이미 ONLINE이면 다시 돌리지 않는다
	check_network
	[ "$(wc -l <"$BATS_TEST_TMPDIR/hook" | tr -d ' ')" -eq 1 ]
}

@test "a failing or hanging recover hook is logged and the state still becomes ONLINE" {
	command -v timeout >/dev/null || skip "no timeout(1) on this machine"
	export NIMWAKE_NET_HOOK_TIMEOUT=1
	echo "OFFLINE 2026-10-11 00:00:00 no interface with an address" >"$NIMWAKE_RUN/network"

	export NIMWAKE_NET_ON_RECOVER="exit 7"
	check_network
	grep -q "network: on-recover hook failed (exit 7)" "$log"
	[ "$(state)" = ONLINE ]

	echo "OFFLINE 2026-10-11 00:00:00 no interface with an address" >"$NIMWAKE_RUN/network"
	export NIMWAKE_NET_ON_RECOVER="sleep 30"
	start="$(date +%s)"
	check_network
	[ $(($(date +%s) - start)) -lt 10 ]
	grep -q "network: on-recover hook timed out after 1s" "$log"
	[ "$(state)" = ONLINE ]
}
