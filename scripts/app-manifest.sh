#!/bin/sh
# 소비처 앱의 manifest를 검사하고, 폰에 놓을 manifest를 만든다. 기기 없이 돈다 (bats가 본다).
# 배포 계약: .docs/phases/phase-2/03-deploy-and-ingress-contract.md "1. 앱 배포 계약"
#
#   app-manifest.sh check APP_DIR              통과하면 "name host port exposure" 한 줄, 아니면 이유와 1
#                                               exposure: APP_DIR/exposure — public | lan. 없으면 lan (Phase 2 04)
#   app-manifest.sh render MANIFEST WORKDIR [DATA_DIR]
#                                               [runtime]에 working_dir = WORKDIR을, DATA_DIR을 주면
#                                               [runtime.env]에 NIMWAKE_DATA_DIR = DATA_DIR을 넣어 출력
#
# 이 셸은 TOML을 해석하지 않는다 — 배포 계약이 쓰는 줄 모양(key = "value", key = 숫자)만 읽는다.
# 최종 검증은 Core가 한다 (§21 · §76: 전부-또는-전무, 거부되면 apps.sh가 되돌린다).
set -eu

fail() {
	echo "app-manifest: $*" >&2
	exit 1
}

# key의 첫 값 — 따옴표를 벗긴다. 같은 key가 여러 section에 있으면 첫 것 (name · host · port는 하나뿐이다)
value() {
	sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*\$/\1/p" "$2" | head -n 1
}

cmd_check() {
	dir="${1:?usage: app-manifest.sh check APP_DIR}"
	toml="$dir/nimwake.toml"
	[ -f "$toml" ] || fail "$toml 이 없다"
	[ -d "$dir/bundle" ] || fail "$dir/bundle/ 이 없다 — 빌드한 결과를 bundle/에 둔다 (폰에서 빌드하지 않는다)"

	name="$(value name "$toml")"
	host="$(value host "$toml")"
	port="$(value port "$toml")"
	[ -n "$name" ] || fail "name 이 없다"
	case "$name" in
	*[!a-z0-9-]* | -*) fail "name '$name' — 소문자 · 숫자 · '-'만 (폰의 경로 이름이 된다)" ;;
	esac
	[ -n "$host" ] || fail "[server] host 가 없다 — 공개 hostname을 그대로 쓴다"
	case "$port" in
	'' | *[!0-9]*) fail "[server] port 가 숫자가 아니다: '$port'" ;;
	esac
	[ "$port" -ge 1024 ] && [ "$port" -le 65535 ] || fail "port $port — 1024–65535 (root 없이 1024 아래는 열 수 없다)"
	[ "$port" != 8080 ] || fail "port 8080 은 gateway가 쓴다"
	grep -q '^[[:space:]]*\[runtime\][[:space:]]*$' "$toml" || fail "[runtime] section이 없다"
	if grep -q '^[[:space:]]*working_dir[[:space:]]*=' "$toml"; then
		fail "working_dir 은 쓰지 않는다 — 배포가 release 디렉터리로 채운다"
	fi
	if grep -q '^[[:space:]]*NIMWAKE_DATA_DIR[[:space:]]*=' "$toml"; then
		fail "NIMWAKE_DATA_DIR 은 쓰지 않는다 — 배포가 앱의 영구 디렉터리(/home/nimwake/data/<name>)로 채운다"
	fi
	command="$(sed -n 's/^[[:space:]]*command[[:space:]]*=[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p' "$toml" | head -n 1)"
	case "$command" in
	/opt/node/bin/node | /opt/nimwake/bin/*) ;;
	'') fail "[runtime] command 가 없다" ;;
	*) fail "command '$command' — 이 레포가 제공하는 런타임만: /opt/node/bin/node (guest/node.lock)" ;;
	esac
	# 노출 선언 — 인터넷에 공개할 의도인가. 없으면 lan(안전한 쪽). nimwake.toml에 넣지 않는다: Core가 모르는 키를 거부한다
	exposure=lan
	if [ -f "$dir/exposure" ]; then
		exposure="$(tr -d ' \t\r\n' <"$dir/exposure")"
		case "$exposure" in
		public | lan) ;;
		*) fail "exposure '$exposure' — public | lan" ;;
		esac
	fi
	check_allow
	echo "$name $host $port $exposure"
}

# [server] allow — Core §82(rc7): gateway가 직접 본 TCP peer로만 판단, 넘으면 403이고 앱을 깨우지 않는다.
# ingress(cloudflared)는 폰 안에서 붙으므로 터널 요청의 peer는 127.0.0.1이다 — exposure와 맞물린다 (Phase 2 04)
check_allow() {
	_line="$(grep '^[[:space:]]*allow[[:space:]]*=' "$toml" | head -n 1 || true)"
	if [ -z "$_line" ]; then
		if [ "$exposure" = lan ]; then
			echo "app-manifest: warning: $name is lan but has no [server] allow — only the Cloudflare hostname list keeps it off the internet. Add allow = [\"192.168.0.0/16\"] (your LAN) so a tunnel request gets 403 even if that list is wrong" >&2
		fi
		return 0
	fi
	case "$_line" in
	*\]*) ;;
	*) fail "allow 는 한 줄로 적는다 — allow = [\"192.168.0.0/16\"] (이 검사는 TOML을 해석하지 않는다)" ;;
	esac
	_cidrs="$(printf '%s\n' "$_line" | sed 's/^[^[]*\[//; s/\].*//' | tr ',' ' ' | tr -d '\t"')"
	_tunnel=no
	for _c in $_cidrs; do
		case "$_c" in
		127.* | 0.0.0.0/0) _tunnel=yes ;;
		esac
	done
	if [ "$exposure" = public ] && [ "$_tunnel" = no ]; then
		fail "$name is public but allow ($_cidrs) does not include 127.0.0.1 — the tunnel connects from 127.0.0.1, so every internet request would get 403. Drop allow, or add \"127.0.0.1/32\""
	fi
	if [ "$exposure" = lan ] && [ "$_tunnel" = yes ]; then
		echo "app-manifest: warning: $name is lan but allow includes 127.0.0.1 (or everything) — a tunnel request would get through. Keep allow to your LAN range" >&2
	fi
	return 0
}

# working_dir은 release마다 바뀐다(배포 · rollback). 앱이 남겨야 하는 것(SQLite · 업로드)은 release 밖의
# 영구 디렉터리에 둔다 — 그 경로를 NIMWAKE_DATA_DIR로 알린다. [runtime.env]가 없으면 끝에 만든다(TOML은
# 하위 table을 뒤에 정의해도 된다)
cmd_render() {
	toml="${1:?usage: app-manifest.sh render MANIFEST WORKDIR [DATA_DIR]}"
	workdir="${2:?usage: app-manifest.sh render MANIFEST WORKDIR [DATA_DIR]}"
	data="${3:-}"
	awk -v wd="$workdir" -v data="$data" '
		{ print }
		/^[[:space:]]*\[runtime\][[:space:]]*$/ && !done {
			print "working_dir = \"" wd "\""
			done = 1
		}
		data != "" && /^[[:space:]]*\[runtime\.env\][[:space:]]*$/ && !env {
			print "NIMWAKE_DATA_DIR = \"" data "\""
			env = 1
		}
		END {
			if (data != "" && !env) {
				print ""
				print "[runtime.env]"
				print "NIMWAKE_DATA_DIR = \"" data "\""
			}
		}
	' "$toml"
}

case "${1:-}" in
check) shift; cmd_check "$@" ;;
render) shift; cmd_render "$@" ;;
*)
	echo "usage: app-manifest.sh check APP_DIR | render MANIFEST WORKDIR [DATA_DIR]" >&2
	exit 2
	;;
esac
