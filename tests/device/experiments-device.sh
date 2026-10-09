#!/data/data/com.termux/files/usr/bin/sh
# A1 실기기 실험 E2–E4 — 기기(Termux)에서 돈다. tests/device/experiments.sh가 ssh로 보낸다.
#   ssh <기기> sh -s <setup|e2|e3|e4|teardown> < tests/device/experiments-device.sh
#
# 운영 중인 nimwaked(/opt/nimwake, :8080)와 섞이지 않게 **별도 경로 · 포트**의 실험 daemon을 쓴다.
#   binary   /opt/nimwake-exp/bin/   ← supervisor · soak sampler의 패턴 `^/opt/nimwake/bin/`에 걸리지 않는다
#   apps     /home/nimwake/.nimwake-exp/apps/{crash,group}
#   gateway  127.0.0.1:8090
# Phase 1 03-core-sync "실기기 실험" 표의 질문에 답한다.

{
set -eu

gateway='http://127.0.0.1:8090/'
log="$HOME/.nimwake-host/logs/exp-nimwaked.log"
daemon='^/opt/nimwake-exp/bin/nimwaked'
# `[p]root`: 이 명령을 실행하는 셸의 명령줄에 패턴 문자열이 있어도 잡히지 않게 한다
wrapper='[p]root .*/opt/nimwake-exp/bin/nimwaked'

guest() {
	proot-distro login ubuntu -- sh -c "$1"
}

alive() {
	[ -n "$1" ] && [ -d "/proc/$1" ]
}

# 출력: "<http_code> <seconds>"
request() {
	curl -s -o /dev/null -m 30 -w '%{http_code} %{time_total}' -H "Host: $1" "$gateway" || true
}

wait_health() {
	i=0
	until [ "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: nimwake-health.invalid' "$gateway" || true)" = 404 ]; do
		i=$((i + 1))
		if [ "$i" -ge 30 ]; then
			echo "FAIL: experiment daemon did not come up — $log" >&2
			tail -n 5 "$log" >&2
			exit 1
		fi
		sleep 1
	done
}

start_daemon() {
	if pgrep -f "$daemon" >/dev/null; then
		return
	fi
	nohup proot-distro login ubuntu --user nimwake -- \
		/opt/nimwake-exp/bin/nimwaked /home/nimwake/.nimwake-exp/apps --port 8090 >>"$log" 2>&1 &
	wait_health
}

grandchild() {
	guest 'cat /tmp/nimwake-exp-grandchild.pid 2>/dev/null' || true
}

case "${1:-}" in
setup)
	# shellcheck disable=SC2016 # $apps는 guest(proot Ubuntu) 안에서 풀린다
	guest '
set -eu
install -d /opt/nimwake-exp/bin
cp /opt/nimwake/bin/nimwaked /opt/nimwake/bin/crash-server /opt/nimwake/bin/group-server /opt/nimwake-exp/bin/
apps=/home/nimwake/.nimwake-exp/apps
install -d -o nimwake -g nimwake "$apps/crash" "$apps/group"
cat >"$apps/crash/nimwake.toml" <<TOML
# E2: 기동 직후 exit 1 — readiness 대기 중 process가 죽는다
name = "crash"
[server]
host = "crash.local"
port = 3201
[runtime]
command = ["/opt/nimwake-exp/bin/crash-server"]
working_dir = "/home/nimwake"
[lifecycle]
idle_timeout_seconds = 3
startup_timeout_seconds = 10
shutdown_timeout_seconds = 5
max_pending_requests = 16
TOML
cat >"$apps/group/nimwake.toml" <<TOML
# E3 · E4: 손자(sleep 600)를 만들고 reap하지 않는다. pid는 파일로 남긴다
name = "group"
[server]
host = "group.local"
port = 3202
[runtime]
command = ["/opt/nimwake-exp/bin/group-server", "3202", "/tmp/nimwake-exp-grandchild.pid"]
working_dir = "/home/nimwake"
[lifecycle]
idle_timeout_seconds = 3
startup_timeout_seconds = 10
shutdown_timeout_seconds = 5
max_pending_requests = 16
TOML
chown nimwake:nimwake "$apps"/*/nimwake.toml
'
	start_daemon
	echo "setup: experiment daemon on :8090 (pid $(pgrep -f "$daemon" | head -n 1))"
	;;

e2)
	# readiness를 기다리는 도중 process가 죽으면 startup_timeout(10s)까지 기다리지 않고 바로 실패해야 한다
	start_daemon
	for n in 1 2 3; do
		echo "e2 request $n: $(request crash.local)"
	done
	;;

e3)
	# idle stop이 process group 단위로 SIGTERM을 보내면 손자도 같이 사라진다
	start_daemon
	echo "e3 wake: $(request group.local)"
	server="$(pgrep -f '^/opt/nimwake-exp/bin/group-server' | head -n 1)"
	gc="$(grandchild)"
	echo "e3 awake: server=$server grandchild=$gc alive=$(alive "$gc" && echo yes || echo no)"
	sleep 10
	echo "e3 after idle: server=$(alive "$server" && echo alive || echo gone) grandchild=$(alive "$gc" && echo alive || echo gone)"
	;;

e4)
	# daemon이 SIGKILL로 죽으면 kill_on_drop · graceful stop이 돌지 않는다. 무엇이 남는가
	for target in nimwaked proot; do
		start_daemon
		echo "e4[$target] wake: $(request group.local)"
		server="$(pgrep -f '^/opt/nimwake-exp/bin/group-server' | head -n 1)"
		gc="$(grandchild)"
		d="$(pgrep -f "$daemon" | head -n 1)"
		w="$(pgrep -f "$wrapper" | head -n 1)"
		echo "e4[$target] before: wrapper=$w daemon=$d server=$server grandchild=$gc"
		if [ "$target" = nimwaked ]; then
			kill -9 "$d"
		else
			kill -9 "$w"
		fi
		sleep 3
		echo "e4[$target] after:  wrapper=$(alive "$w" && echo alive || echo gone) daemon=$(alive "$d" && echo alive || echo gone) server=$(alive "$server" && echo alive || echo gone) grandchild=$(alive "$gc" && echo alive || echo gone)"
		# 다음 경우를 위해 남은 것을 치운다
		for p in "$gc" "$server" "$d" "$w"; do
			alive "$p" && kill -9 "$p" 2>/dev/null || true
		done
		sleep 1
	done
	;;

e4-term)
	# E4에서 proot가 죽으면 daemon · app이 고아로 남았다. 고아 daemon에 SIGTERM을 보내면
	# 그 graceful shutdown이 app(process group)까지 정리하는가 — supervisor의 고아 정리 방법이 이것이다.
	# proot가 없으므로 경로 변환은 끊겼지만 신호는 커널이 전달한다.
	start_daemon
	echo "e4-term wake: $(request group.local)"
	server="$(pgrep -f '^/opt/nimwake-exp/bin/group-server' | head -n 1)"
	gc="$(grandchild)"
	d="$(pgrep -f "$daemon" | head -n 1)"
	w="$(pgrep -f "$wrapper" | head -n 1)"
	kill -9 "$w"
	sleep 2
	echo "e4-term orphaned: daemon=$(alive "$d" && echo alive || echo gone) server=$(alive "$server" && echo alive || echo gone) grandchild=$(alive "$gc" && echo alive || echo gone)"
	kill -TERM "$d"
	waited=0
	while alive "$d" && [ "$waited" -lt 15 ]; do
		sleep 1
		waited=$((waited + 1))
	done
	echo "e4-term after SIGTERM to orphan daemon (${waited}s): daemon=$(alive "$d" && echo alive || echo gone) server=$(alive "$server" && echo alive || echo gone) grandchild=$(alive "$gc" && echo alive || echo gone)"
	for p in "$gc" "$server" "$d"; do
		alive "$p" && kill -9 "$p" 2>/dev/null || true
	done
	;;

e4-supervised)
	# 고아 정리(reap_orphan_daemon)를 실기기에서: 실험 daemon을 맡는 별도 supervisor를 띄우고 proot를 죽인다.
	# $2 = 이번 레포의 host/ 를 올려 둔 디렉터리 (운영 중인 ~/.nimwake-host와 섞지 않는다)
	stage="$2"
	termux-fix-shebang "$stage"/bin/* >/dev/null 2>&1 || true
	pkill -TERM -f "$daemon" 2>/dev/null || true
	sleep 2
	export NIMWAKE_HOST_HOME="$HOME/.nimwake-exp-host"
	export NIMWAKE_HOST_LIB="$stage/lib"
	export NIMWAKE_DAEMON=/opt/nimwake-exp/bin/nimwaked
	export NIMWAKE_APPS=/home/nimwake/.nimwake-exp/apps
	export NIMWAKE_LAUNCH="proot-distro login ubuntu --user nimwake -- $NIMWAKE_DAEMON $NIMWAKE_APPS --port 8090"
	export NIMWAKE_DAEMON_MATCH="$daemon"
	export NIMWAKE_GATEWAY="$gateway"
	export NIMWAKE_HEALTH_INTERVAL=5
	rm -rf "$NIMWAKE_HOST_HOME"
	host="$stage/bin/nimwake-host"
	state() { cut -d' ' -f1 "$NIMWAKE_HOST_HOME/run/state" 2>/dev/null; }

	"$host" start
	i=0
	until [ "$(state)" = RUNNING ]; do i=$((i + 1)); [ "$i" -ge 60 ] && { "$host" status; exit 1; }; sleep 1; done
	echo "e4-supervised wake: $(request group.local)"
	server="$(pgrep -f '^/opt/nimwake-exp/bin/group-server' | head -n 1)"
	gc="$(grandchild)"
	d="$(pgrep -f "$daemon" | head -n 1)"
	w="$(pgrep -f "$wrapper" | head -n 1)"
	echo "e4-supervised before: wrapper=$w daemon=$d server=$server grandchild=$gc"
	killed_at="$(date +%s)"
	kill -9 "$w"

	# 새 daemon(다른 pid)으로 RUNNING이 될 때까지
	i=0
	while :; do
		nd="$(pgrep -f "$daemon" | head -n 1)"
		if [ -n "$nd" ] && [ "$nd" != "$d" ] && [ "$(state)" = RUNNING ]; then
			break
		fi
		i=$((i + 1))
		[ "$i" -ge 60 ] && { echo "FAIL: not recovered"; "$host" status; tail -n 8 "$NIMWAKE_HOST_HOME/logs/supervisor.log"; exit 1; }
		sleep 1
	done
	echo "e4-supervised recovered in $(($(date +%s) - killed_at))s: new daemon=$nd"
	echo "e4-supervised old: daemon=$(alive "$d" && echo alive || echo gone) server=$(alive "$server" && echo alive || echo gone) grandchild=$(alive "$gc" && echo alive || echo gone)"
	echo "e4-supervised after: $(request group.local) (new server $(pgrep -f '^/opt/nimwake-exp/bin/group-server' | head -n 1))"
	grep -E 'orphan|state (BACKOFF|RUNNING)' "$NIMWAKE_HOST_HOME/logs/supervisor.log" | tail -n 4
	"$host" stop
	;;

teardown)
	pkill -TERM -f "$daemon" 2>/dev/null || true
	sleep 2
	pkill -9 -f '^/opt/nimwake-exp/' 2>/dev/null || true
	gc="$(grandchild)"
	alive "$gc" && kill -9 "$gc" 2>/dev/null || true
	guest 'rm -f /tmp/nimwake-exp-grandchild.pid'
	left="$(pgrep -f '^/opt/nimwake-exp/|[p]root .*nimwake-exp' || true)"
	if [ -n "$left" ]; then
		echo "teardown: left: $left"
	else
		echo "teardown: nothing left"
	fi
	;;

*)
	echo "usage: experiments-device.sh setup | e2 | e3 | e4 | teardown" >&2
	exit 2
	;;
esac
} </dev/null
