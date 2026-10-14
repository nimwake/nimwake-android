#!/usr/bin/env bats
# host/lib/config.sh — 기동 명령이 설정대로 만들어지는가. 기기 없이 돈다.

setup() {
	root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	export NIMWAKE_HOST_HOME="$BATS_TEST_TMPDIR/host"
	unset NIMWAKE_LAUNCH NIMWAKE_ISOLATED
}

launch() {
	sh -c ". \"$root/host/lib/config.sh\"; echo \"\$NIMWAKE_LAUNCH\""
}

# 격리하지 않으면 앱이 Termux의 SSH 키 · 부팅 스크립트를 읽고 쓴다 (Phase 2 04 T1, 10-14 기기에서 확인)
@test "the daemon is launched isolated by default" {
	run launch
	echo "$output"
	[[ "$output" == "proot-distro login ubuntu --isolated --user nimwake -- /opt/nimwake/bin/nimwaked "* ]]
}

@test "NIMWAKE_ISOLATED=0 launches without isolation, from the environment or host.conf" {
	NIMWAKE_ISOLATED=0 run launch
	[[ "$output" == "proot-distro login ubuntu --user nimwake -- "* ]]

	mkdir -p "$NIMWAKE_HOST_HOME"
	echo "NIMWAKE_ISOLATED=0" >"$NIMWAKE_HOST_HOME/host.conf"
	run launch
	[[ "$output" != *"--isolated"* ]]
}
