#!/usr/bin/env bats
# host/bin/nimwake-host + host/lib/supervisor.sh — 가짜 daemon으로 감시 루프를 끝까지 돌린다.
# 기기 없이 개발 머신(WSL · macOS · CI)에서 돈다. 실제 proot 위의 동작은 tests/device/recovery.sh가 본다.

setup() {
	root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	# 바깥에서 돌리는 테스트는 구현을 모른다 — Phase 2의 nimwake-hostd도 이것으로 검사한다
	# (.docs/phases/phase-2/01-nimwake-hostd.md "행동 계약")
	host="${NIMWAKE_HOST_BIN:-$root/host/bin/nimwake-host}"

	export FAKE_DIR="$BATS_TEST_TMPDIR/fake"
	mkdir -p "$FAKE_DIR"
	echo ok >"$FAKE_DIR/mode"

	export NIMWAKE_HOST_HOME="$BATS_TEST_TMPDIR/host"
	export NIMWAKE_HOST_LIB="$root/host/lib"
	export NIMWAKE_LAUNCH="$BATS_TEST_DIRNAME/fixtures/fake-nimwaked"
	# 테스트마다 경로가 달라 다른 테스트의 가짜 daemon을 건드리지 않는다
	export NIMWAKE_DAEMON_MATCH="fake-nimwaked"
	export NIMWAKE_PROBE="[ -f \"$FAKE_DIR/up\" ]"
	export NIMWAKE_STARTUP_TIMEOUT=5
	export NIMWAKE_HEALTH_INTERVAL=1
	export NIMWAKE_HEALTH_FAILURES=2
	export NIMWAKE_STOP_TIMEOUT=5
	export NIMWAKE_MAX_RESTARTS=5
	export NIMWAKE_RESTART_WINDOW=300
}

teardown() {
	"$host" stop >/dev/null 2>&1 || true
	# orphan 모드의 가짜 daemon은 TERM을 무시한다
	pkill -9 -f "fake-(nimwaked|proot)" 2>/dev/null || true
	if [ -f "$FAKE_DIR/apps" ]; then
		xargs kill -9 <"$FAKE_DIR/apps" 2>/dev/null || true
	fi
	# 가짜 ingress provider의 run (exec sleep)
	if [ -f "$FAKE_DIR/ingress-runs" ]; then
		xargs kill -9 <"$FAKE_DIR/ingress-runs" 2>/dev/null || true
	fi
}

alive() {
	kill -0 "$1" 2>/dev/null
}

state() {
	cut -d' ' -f1 "$NIMWAKE_HOST_HOME/run/state" 2>/dev/null
}

launches() {
	wc -l <"$FAKE_DIR/launches" 2>/dev/null | tr -d ' '
}

# wait_for SECONDS COMMAND... — 조건이 참이 될 때까지 기다린다
wait_for() {
	_limit=$1
	shift
	_i=0
	while ! "$@"; do
		[ "$_i" -ge $((_limit * 5)) ] && return 1
		sleep 0.2
		_i=$((_i + 1))
	done
}

state_is() { [ "$(state)" = "$1" ]; }
launched_at_least() { [ "$(launches)" -ge "$1" ]; }

@test "start → RUNNING, stop → STOPPED with nothing left" {
	run "$host" start
	[ "$status" -eq 0 ]
	wait_for 5 state_is RUNNING

	run "$host" status
	[[ "$output" == *"supervisor  running"* ]]
	[[ "$output" == *"health      OK"* ]]

	run "$host" stop
	[ "$status" -eq 0 ]
	state_is STOPPED
	! pgrep -f "fake-nimwaked"
	[ ! -f "$NIMWAKE_HOST_HOME/run/supervisor.pid" ]
}

@test "a second start does not launch a second supervisor" {
	"$host" start
	wait_for 5 state_is RUNNING
	run "$host" start
	[[ "$output" == *"already running"* ]]
	[ "$(launches)" -eq 1 ]
}

@test "exit 78 → UNHEALTHY, no restart" {
	echo config >"$FAKE_DIR/mode"
	"$host" start
	wait_for 5 state_is UNHEALTHY
	grep -q "exit 78" "$NIMWAKE_HOST_HOME/run/state"
	sleep 2
	[ "$(launches)" -eq 1 ]
}

@test "killed daemon is restarted and becomes RUNNING again" {
	"$host" start
	wait_for 5 state_is RUNNING
	pkill -KILL -f "fake-nimwaked"
	wait_for 5 launched_at_least 2
	wait_for 5 state_is RUNNING
	grep -q "exit 137" "$NIMWAKE_HOST_HOME/logs/supervisor.log"
}

@test "repeated crashes → crash loop → UNHEALTHY" {
	echo crash >"$FAKE_DIR/mode"
	export NIMWAKE_MAX_RESTARTS=2
	"$host" start
	# 기동 1 → 0s → 기동 2 → 5s → 기동 3 → crash loop
	wait_for 15 state_is UNHEALTHY
	grep -q "crash loop: 2 restarts" "$NIMWAKE_HOST_HOME/run/state"
	[ "$(launches)" -eq 3 ]
}

@test "a daemon that stops answering health probes is replaced" {
	echo hung >"$FAKE_DIR/mode"
	"$host" start
	wait_for 10 launched_at_least 2
	grep -q "health probe failed" "$NIMWAKE_HOST_HOME/logs/supervisor.log"
}

@test "exit 0 from outside (make stop) → STOPPED, no restart" {
	"$host" start
	wait_for 5 state_is RUNNING
	pkill -TERM -f "fake-nimwaked"
	wait_for 5 state_is STOPPED
	sleep 2
	[ "$(launches)" -eq 1 ]
}

@test "stop during backoff ends promptly" {
	echo crash >"$FAKE_DIR/mode"
	"$host" start
	# 두 번째 crash 뒤 5초 backoff에 들어간다
	wait_for 10 launched_at_least 2
	wait_for 5 state_is BACKOFF
	run "$host" stop
	[ "$status" -eq 0 ]
	state_is STOPPED
}

# validation/06 E4: proot가 SIGKILL로 죽으면 nimwaked · application이 고아로 남고 TERM에 반응하지 않는다.
# 그대로 두면 새 daemon이 port를 못 잡는다. supervisor는 재기동 전에 고아를 정리해야 한다.
@test "an orphaned daemon left by a dead wrapper is killed with its applications before relaunch" {
	echo orphan >"$FAKE_DIR/mode"
	export NIMWAKE_LAUNCH="$BATS_TEST_DIRNAME/fixtures/fake-proot"
	"$host" start
	wait_for 5 state_is RUNNING
	old_daemon="$(head -n 1 "$FAKE_DIR/daemons")"
	old_app="$(head -n 1 "$FAKE_DIR/apps")"
	alive "$old_daemon"
	alive "$old_app"

	pkill -9 -f "fake-proot"
	wait_for 15 launched_at_least 2
	wait_for 10 state_is RUNNING

	! alive "$old_daemon"
	! alive "$old_app"
	grep -q "orphan nimwaked $old_daemon" "$NIMWAKE_HOST_HOME/logs/supervisor.log"
	[ "$(pgrep -f "fake-nimwaked" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "stop kills a daemon that ignores TERM, and its applications" {
	echo orphan >"$FAKE_DIR/mode"
	export NIMWAKE_LAUNCH="$BATS_TEST_DIRNAME/fixtures/fake-proot"
	export NIMWAKE_STOP_TIMEOUT=2
	"$host" start
	wait_for 5 state_is RUNNING
	app="$(head -n 1 "$FAKE_DIR/apps")"

	run "$host" stop
	[ "$status" -eq 0 ]
	! pgrep -f "fake-nimwaked"
	! alive "$app"
}

# 남은 저장공간 감시 (PRD §18, §44-6) — 상태가 바뀔 때만 남기고 알린다

# nimwake-host와 같은 순서로 lib를 읽는다 — 함수를 직접 부르는 테스트용
load_libs() {
	. "$root/host/lib/config.sh"
	. "$root/host/lib/policy.sh"
	. "$root/host/lib/supervisor.sh"
	. "$root/host/lib/logs.sh"
	. "$root/host/lib/network.sh"
	. "$root/host/lib/battery.sh"
}

@test "check_storage logs and notifies only when the level changes" {
	export NIMWAKE_STORAGE_PATH="$BATS_TEST_TMPDIR"
	export NIMWAKE_NOTIFY="echo \"\$1\" >>\"$FAKE_DIR/notified\""
	load_libs
	log="$NIMWAKE_HOST_HOME/logs/supervisor.log"

	NIMWAKE_MIN_FREE_MB=1
	check_storage
	grep -q "storage: ok [0-9]*MB free" "$log"
	[ ! -f "$FAKE_DIR/notified" ]

	NIMWAKE_MIN_FREE_MB=999999999
	check_storage
	check_storage
	[ "$(grep -c "storage: LOW" "$log")" -eq 1 ]
	[ "$(wc -l <"$FAKE_DIR/notified" | tr -d ' ')" -eq 1 ]
	grep -q "^storage low: [0-9]*MB free (< 999999999MB)$" "$FAKE_DIR/notified"
	[ "$(cut -d' ' -f1 "$NIMWAKE_HOST_HOME/run/storage")" = low ]

	NIMWAKE_MIN_FREE_MB=1
	check_storage
	grep -q "storage: ok again" "$log"
	[ "$(wc -l <"$FAKE_DIR/notified" | tr -d ' ')" -eq 1 ]
}

@test "a failing notify command is logged, not fatal" {
	export NIMWAKE_STORAGE_PATH="$BATS_TEST_TMPDIR"
	export NIMWAKE_NOTIFY="exit 3"
	export NIMWAKE_MIN_FREE_MB=999999999
	load_libs
	check_storage
	grep -q "storage: notify failed" "$NIMWAKE_HOST_HOME/logs/supervisor.log"
}

# 정리로 기준 위로 돌아오는 경우는 실제 디스크로 만들 수 없다 — 남은 공간을 순환 로그 유무로 흉내 낸다
@test "low storage removes rotated logs first, and does not alert if that was enough" {
	export NIMWAKE_NOTIFY="echo \"\$1\" >>\"$FAKE_DIR/notified\""
	export NIMWAKE_MIN_FREE_MB=1024
	load_libs
	logs="$NIMWAKE_HOST_HOME/logs"
	echo current >"$logs/nimwaked.log"
	head -c 3072 /dev/zero >"$logs/nimwaked.log.1"
	head -c 2048 /dev/zero >"$logs/supervisor.log.2"
	echo keep >"$logs/soak.csv"
	storage_free_mb() {
		if [ -f "$logs/nimwaked.log.1" ]; then echo 10; else echo 5000; fi
	}

	check_storage
	[ ! -f "$logs/nimwaked.log.1" ]
	[ ! -f "$logs/supervisor.log.2" ]
	[ "$(cat "$logs/nimwaked.log")" = current ]
	[ "$(cat "$logs/soak.csv")" = keep ]
	grep -q "storage: 10MB free — removed 2 rotated log(s), 5KB" "$logs/supervisor.log"
	! grep -q "storage: LOW" "$logs/supervisor.log"
	[ ! -f "$FAKE_DIR/notified" ]
	[ "$(cut -d' ' -f1 "$NIMWAKE_HOST_HOME/run/storage")" = ok ]
}

@test "low storage still alerts when nothing can be removed, and cleanup can be turned off" {
	export NIMWAKE_NOTIFY="echo \"\$1\" >>\"$FAKE_DIR/notified\""
	export NIMWAKE_STORAGE_PATH="$BATS_TEST_TMPDIR"
	export NIMWAKE_MIN_FREE_MB=999999999
	export NIMWAKE_STORAGE_CLEANUP=0
	load_libs
	logs="$NIMWAKE_HOST_HOME/logs"
	echo old >"$logs/boot.log.1"

	check_storage
	# 꺼져 있으면 지우지 않고 알리기만 한다
	[ -f "$logs/boot.log.1" ]
	grep -q "storage: LOW" "$logs/supervisor.log"
	[ "$(wc -l <"$FAKE_DIR/notified" | tr -d ' ')" -eq 1 ]
}

@test "the running supervisor warns once about low storage and status shows it" {
	export NIMWAKE_STORAGE_PATH="$BATS_TEST_TMPDIR"
	export NIMWAKE_HOUSEKEEPING_INTERVAL=1
	export NIMWAKE_MIN_FREE_MB=999999999
	export NIMWAKE_NOTIFY="echo \"\$1\" >>\"$FAKE_DIR/notified\""
	"$host" start
	wait_for 5 state_is RUNNING
	wait_for 5 test -f "$FAKE_DIR/notified"
	# 간격 1초로 여러 번 검사해도 알림은 한 번
	sleep 3
	[ "$(wc -l <"$FAKE_DIR/notified" | tr -d ' ')" -eq 1 ]
	[ "$(grep -c "storage: LOW" "$NIMWAKE_HOST_HOME/logs/supervisor.log")" -eq 1 ]

	run "$host" status
	[[ "$output" == *"storage     LOW "*"MB free (< 999999999MB)"* ]]
}

# 로그 순환 (PRD §20) — 실제 supervisor가 기동 직전과 RUNNING 동안 돌린다

@test "the supervisor rotates a large log before launch and keeps logging" {
	export NIMWAKE_LOG_MAX_KB=1
	mkdir -p "$NIMWAKE_HOST_HOME/logs"
	head -c 4096 /dev/zero | tr '\0' 'x' >"$NIMWAKE_HOST_HOME/logs/nimwaked.log"
	"$host" start
	wait_for 5 state_is RUNNING

	logs="$NIMWAKE_HOST_HOME/logs"
	[ "$(wc -c <"$logs/nimwaked.log.1" | tr -d ' ')" -eq 4096 ]
	grep -q "log: rotated nimwaked.log (4KB, keep 3)" "$logs/supervisor.log"
	# 순환 뒤에도 supervisor는 같은 파일에 계속 쓴다
	grep -q "state RUNNING" "$logs/supervisor.log"
}

# 네트워크 (PRD §13) — 판정은 network.bats가 본다. 여기서는 루프에 붙어 있고 daemon을 건드리지 않는지만
@test "the running supervisor records the network state without touching the daemon" {
	# 닿지 않는 게이트웨이(TEST-NET-1) — 이 머신의 네트워크와 상관없이 ONLINE은 아니다
	export NIMWAKE_NET_GATEWAY=192.0.2.1
	"$host" start
	wait_for 5 state_is RUNNING
	wait_for 10 test -f "$NIMWAKE_HOST_HOME/run/network"
	pid="$(cut -d' ' -f6 "$NIMWAKE_HOST_HOME/run/state")"

	run "$host" status
	echo "$output"
	[[ "$output" == *"network     DEGRADED since "* || "$output" == *"network     OFFLINE since "* ]]
	grep -q "network ? → " "$NIMWAKE_HOST_HOME/logs/supervisor.log"
	# 네트워크가 나빠도 daemon은 그대로다
	state_is RUNNING
	[ "$(cut -d' ' -f6 "$NIMWAKE_HOST_HOME/run/state")" = "$pid" ]
	[ "$(launches)" -eq 1 ]
}

# ingress provider (Phase 2 03 "2. ingress provider 계약") — 가짜 provider로 감시 루프를 본다

# provider 디렉터리와 manifest 하나를 둔다
use_fake_ingress() {
	export NIMWAKE_INGRESS=fake
	export NIMWAKE_INGRESS_DIR="$BATS_TEST_DIRNAME/fixtures/ingress"
	export NIMWAKE_MANIFESTS="$BATS_TEST_TMPDIR/manifests"
	export NIMWAKE_APP_HOME="$BATS_TEST_TMPDIR/apps"
	# 공개 앱 하나와 LAN 전용 앱 하나 — provider는 공개 앱의 host만 받아야 한다 (Phase 2 04)
	mkdir -p "$NIMWAKE_MANIFESTS/blog" "$NIMWAKE_MANIFESTS/notes" "$NIMWAKE_APP_HOME/blog"
	printf 'name = "blog"\n[server]\nhost = "blog.example.com"\nport = 3102\n' >"$NIMWAKE_MANIFESTS/blog/nimwake.toml"
	printf 'name = "notes"\n[server]\nhost = "notes.home.arpa"\nport = 3103\n' >"$NIMWAKE_MANIFESTS/notes/nimwake.toml"
	echo public >"$NIMWAKE_APP_HOME/blog/exposure"
}

ingress_state() { cut -d' ' -f1 "$NIMWAKE_HOST_HOME/run/ingress" 2>/dev/null; }
ingress_state_is() { [ "$(ingress_state)" = "$1" ]; }
ingress_runs() { wc -l <"$FAKE_DIR/ingress-runs" 2>/dev/null | tr -d ' '; }

@test "ingress runs beside the daemon with the contract environment, and stop takes it down" {
	use_fake_ingress
	"$host" start
	wait_for 5 state_is RUNNING
	wait_for 5 ingress_state_is RUNNING
	grep -q "gateway=http://127.0.0.1:8080/ hosts=blog.example.com secrets=$NIMWAKE_HOST_HOME/secrets" "$FAKE_DIR/ingress-env"
	# 비밀 디렉터리는 0700
	[ "$(ls -ld "$NIMWAKE_HOST_HOME/secrets" | cut -c1-10)" = "drwx------" ]
	pid="$(cat "$NIMWAKE_HOST_HOME/run/ingress.pid")"
	# 기록한 pid가 provider 자신이어야 한다 — 바깥 셸이면 그것을 죽여도 provider가 고아로 남는다 (10-14 기기)
	[ "$pid" = "$(head -n 1 "$FAKE_DIR/ingress-runs")" ]

	run "$host" status
	echo "$output"
	[[ "$output" == *"ingress     fake RUNNING — connected https://fake.example"* ]]

	"$host" stop
	! alive "$pid"
	ingress_state_is STOPPED
}

@test "a killed provider is replaced, and no orphan provider is left behind" {
	use_fake_ingress
	"$host" start
	wait_for 5 ingress_state_is RUNNING
	first="$(cat "$NIMWAKE_HOST_HOME/run/ingress.pid")"
	kill -9 "$first"
	# 1번째 재기동은 backoff 0초
	wait_for 5 sh -c "[ \"\$(wc -l <\"$FAKE_DIR/ingress-runs\")\" -ge 2 ]"
	wait_for 5 ingress_state_is RUNNING
	second="$(cat "$NIMWAKE_HOST_HOME/run/ingress.pid")"
	[ "$second" != "$first" ]
	[ "$second" = "$(tail -n 1 "$FAKE_DIR/ingress-runs")" ]

	"$host" stop
	# 기록된 모든 provider가 죽었다 — 고아 없음
	while read -r p; do ! alive "$p"; done <"$FAKE_DIR/ingress-runs"
}

# host.conf는 셸 변수로만 읽힌다 — provider별 설정이 별도 프로세스인 provider에 넘어가야 한다.
# 빠뜨렸을 때 cloudflare quick 모드가 token 모드로 돌았다 (10-14 기기)
@test "provider settings from host.conf (NIMWAKE_INGRESS_*) reach the provider" {
	use_fake_ingress
	mkdir -p "$NIMWAKE_HOST_HOME"
	echo "NIMWAKE_INGRESS_FAKE_SETTING=quick" >"$NIMWAKE_HOST_HOME/host.conf"
	"$host" start
	wait_for 5 ingress_state_is RUNNING
	grep -q "^fake_setting=quick$" "$FAKE_DIR/ingress-env"
}

@test "a dying ingress is restarted with backoff while the daemon keeps running" {
	use_fake_ingress
	echo exit-1 >"$FAKE_DIR/ingress-mode"
	"$host" start
	wait_for 5 state_is RUNNING
	daemon_before="$(cut -d' ' -f6 "$NIMWAKE_HOST_HOME/run/state")"
	# 1번째 재기동은 0초, 2번째는 5초 뒤 (policy_backoff)
	wait_for 10 sh -c "[ \"\$(wc -l <\"$FAKE_DIR/ingress-runs\")\" -ge 3 ]"
	grep -q "ingress BACKOFF — exit 1 — restart" "$NIMWAKE_HOST_HOME/logs/supervisor.log"
	# daemon은 그대로다
	state_is RUNNING
	[ "$(cut -d' ' -f6 "$NIMWAKE_HOST_HOME/run/state")" = "$daemon_before" ]
	[ "$(launches)" -eq 1 ]
}

@test "ingress exit 78 is a configuration error — no restart" {
	use_fake_ingress
	echo exit-78 >"$FAKE_DIR/ingress-mode"
	"$host" start
	wait_for 5 ingress_state_is UNHEALTHY
	grep -q "configuration error (exit 78)" "$NIMWAKE_HOST_HOME/run/ingress"
	sleep 2
	[ "$(ingress_runs)" -eq 1 ]
	state_is RUNNING
}

@test "a failing check keeps ingress down and says why" {
	use_fake_ingress
	echo fail >"$FAKE_DIR/ingress-check"
	"$host" start
	wait_for 5 ingress_state_is UNHEALTHY
	grep -q "check failed: fake: no token" "$NIMWAKE_HOST_HOME/run/ingress"
	[ ! -f "$FAKE_DIR/ingress-runs" ]
	# ingress가 서지 않아도 daemon은 선다 (check는 바로 끝나고 daemon은 아직 STARTING일 수 있다)
	wait_for 5 state_is RUNNING
}

@test "without NIMWAKE_INGRESS nothing runs and status says LAN only" {
	"$host" start
	wait_for 5 state_is RUNNING
	[ ! -f "$NIMWAKE_HOST_HOME/run/ingress" ]
	run "$host" status
	[[ "$output" == *"ingress     none"* ]]
}

# 노출 선언이 없으면 lan — 공개되는 것이 없다는 것을 남긴다 (Phase 2 04)
@test "ingress without any public app runs but warns, and warns when apps are not isolated" {
	use_fake_ingress
	rm -f "$NIMWAKE_APP_HOME/blog/exposure"
	export NIMWAKE_ISOLATED=0
	"$host" start
	wait_for 5 ingress_state_is RUNNING
	grep -q "hosts= secrets=" "$FAKE_DIR/ingress-env"
	grep -q "no app declares exposure=public" "$NIMWAKE_HOST_HOME/logs/supervisor.log"
	grep -q "WARNING NIMWAKE_ISOLATED=0" "$NIMWAKE_HOST_HOME/logs/supervisor.log"
	grep -q "for no public app" "$NIMWAKE_HOST_HOME/run/ingress"
}

# Termux가 통째로 죽은 것처럼 — supervisor와 그 자식까지 SIGKILL, 아무 기록도 남기지 못한다
kill_everything() {
	pkill -9 -f "[_]_supervise" 2>/dev/null || true
	pkill -9 -f "fake-(nimwaked|proot)" 2>/dev/null || true
	sleep 0.5
}

# 10-15 기기: Android가 Termux를 내렸는데 로그가 종료 기록 없이 끊겨 언제 사라졌는지 몰랐다
@test "a supervisor lost while the phone stayed up is reported as killed on the next start" {
	export NIMWAKE_BOOTED_AT="2000-01-01 00:00:00"
	"$host" start
	wait_for 5 state_is RUNNING
	sleep 1.5
	kill_everything

	run "$host" start
	echo "$output"
	[[ "$output" == *"previous run ended without exiting (killed) — last seen 20"*"in state RUNNING"* ]]
	grep -q "previous supervisor ended without exiting (killed)" "$NIMWAKE_HOST_HOME/logs/supervisor.log"
	wait_for 5 state_is RUNNING

	run "$host" status
	[[ "$output" == *"last-lost   "*" killed — last seen "* ]]
}

@test "a supervisor lost to a reboot is reported as reboot" {
	"$host" start
	wait_for 5 state_is RUNNING
	kill_everything
	# 마지막 heartbeat 뒤에 부팅했다
	export NIMWAKE_BOOTED_AT="2999-01-01 00:00:00"
	run "$host" start
	[[ "$output" == *"(reboot) — last seen"*"phone booted at 2999-01-01 00:00:00"* ]]
}

@test "a clean stop is not reported as lost" {
	"$host" start
	wait_for 5 state_is RUNNING
	"$host" stop
	run "$host" start
	[[ "$output" != *"without exiting"* ]]
	[ ! -f "$NIMWAKE_HOST_HOME/run/last-unclean" ]
}

# 배터리 · 전원 감시 (host/lib/battery.sh) — 10-18 · 10-20 기기: USB에 꽂힌 채 하루 약 45%씩 줄어 두 번 꺼졌다
battery() { # pct plugged status
	printf '{\n  "percentage": %s,\n  "plugged": "%s",\n  "status": "%s",\n  "temperature": 29.04\n}\n' "$1" "$2" "$3" >"$FAKE_DIR/battery.json"
}

notified() {
	if [ -f "$FAKE_DIR/notified" ]; then
		wc -l <"$FAKE_DIR/notified" | tr -d ' '
	else
		echo 0
	fi
}

@test "check_battery reports ok, draining, unplugged and low — and notifies only on a change" {
	export NIMWAKE_BATTERY_CMD="cat \"$FAKE_DIR/battery.json\""
	export NIMWAKE_NOTIFY="echo \"\$2: \$1\" >>\"$FAKE_DIR/notified\""
	load_libs
	log="$NIMWAKE_HOST_HOME/logs/supervisor.log"

	battery 100 PLUGGED_USB FULL
	check_battery
	grep -q "battery: ok — 100% PLUGGED_USB FULL 29.0°C" "$log"
	[ "$(cut -d' ' -f1-5 "$NIMWAKE_HOST_HOME/run/battery")" = "ok 100 PLUGGED_USB FULL 29.0" ]
	[ "$(notified)" -eq 0 ]

	# 꽂혀 있는데 줄어든다 — 이번 사고
	battery 80 PLUGGED_USB DISCHARGING
	check_battery
	check_battery
	[ "$(grep -c "battery: draining" "$log")" -eq 1 ]
	grep -q "^battery: battery draining: 80% — plugged in but discharging" "$FAKE_DIR/notified"

	battery 70 UNPLUGGED DISCHARGING
	check_battery
	grep -q "battery: unplugged — 70% UNPLUGGED" "$log"

	# 잔량이 기준 아래면 연결 상태보다 먼저
	battery 15 PLUGGED_USB DISCHARGING
	check_battery
	grep -q "battery: low — 15%.*below 20%" "$log"
	[ "$(notified)" -eq 3 ]

	# 충전 보호(85%에서 멈춤)는 문제가 아니다
	battery 85 PLUGGED_AC NOT_CHARGING
	check_battery
	grep -q "battery: ok again — 85% PLUGGED_AC NOT_CHARGING" "$log"
	[ "$(notified)" -eq 3 ]
}

@test "check_battery is unknown when Termux:API does not answer, and does not notify" {
	export NIMWAKE_BATTERY_CMD="false"
	export NIMWAKE_NOTIFY="echo \"\$1\" >>\"$FAKE_DIR/notified\""
	load_libs
	check_battery
	grep -q "battery: unknown — termux-battery-status did not answer; open the Termux:API app once" "$NIMWAKE_HOST_HOME/logs/supervisor.log"
	[ "$(cut -d' ' -f1-2 "$NIMWAKE_HOST_HOME/run/battery")" = "unknown NA" ]
	[ "$(notified)" -eq 0 ]
}

@test "the battery watch can be turned off" {
	export NIMWAKE_BATTERY_WATCH=0
	export NIMWAKE_BATTERY_CMD="false"
	load_libs
	check_battery
	[ ! -f "$NIMWAKE_HOST_HOME/run/battery" ]
}

@test "status shows the last battery check" {
	mkdir -p "$NIMWAKE_HOST_HOME/run"
	echo "draining 64 PLUGGED_USB DISCHARGING 28.9 2026-10-17 09:31:15" >"$NIMWAKE_HOST_HOME/run/battery"
	run "$host" status
	[[ "$output" == *"battery     draining 64% PLUGGED_USB DISCHARGING 28.9°C (checked 2026-10-17 09:31:15)"* ]]
}

@test "storage and battery notifications carry their kind, so one does not replace the other" {
	export NIMWAKE_STORAGE_PATH="$BATS_TEST_TMPDIR"
	export NIMWAKE_MIN_FREE_MB=999999999
	export NIMWAKE_BATTERY_CMD="cat \"$FAKE_DIR/battery.json\""
	export NIMWAKE_NOTIFY="echo \"\$2\" >>\"$FAKE_DIR/kinds\""
	battery 10 UNPLUGGED DISCHARGING
	load_libs
	housekeeping
	[ "$(sort "$FAKE_DIR/kinds" | tr '\n' ' ')" = "battery storage " ]
}
