#!/bin/sh
# 소비처 앱의 manifest를 검사하고, 폰에 놓을 manifest를 만든다. 기기 없이 돈다 (bats가 본다).
# 배포 계약: .docs/phases/phase-2/03-deploy-and-ingress-contract.md "1. 앱 배포 계약"
#
#   app-manifest.sh check APP_DIR              통과하면 "name host port" 한 줄, 아니면 이유와 1
#   app-manifest.sh render MANIFEST WORKDIR     [runtime]에 working_dir = WORKDIR을 넣어 출력
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
	command="$(sed -n 's/^[[:space:]]*command[[:space:]]*=[[:space:]]*\[[[:space:]]*"\([^"]*\)".*/\1/p' "$toml" | head -n 1)"
	case "$command" in
	/opt/node/bin/node | /opt/nimwake/bin/*) ;;
	'') fail "[runtime] command 가 없다" ;;
	*) fail "command '$command' — 이 레포가 제공하는 런타임만: /opt/node/bin/node (guest/node.lock)" ;;
	esac
	echo "$name $host $port"
}

cmd_render() {
	toml="${1:?usage: app-manifest.sh render MANIFEST WORKDIR}"
	workdir="${2:?usage: app-manifest.sh render MANIFEST WORKDIR}"
	awk -v wd="$workdir" '
		{ print }
		/^[[:space:]]*\[runtime\][[:space:]]*$/ && !done {
			print "working_dir = \"" wd "\""
			done = 1
		}
	' "$toml"
}

case "${1:-}" in
check) shift; cmd_check "$@" ;;
render) shift; cmd_render "$@" ;;
*)
	echo "usage: app-manifest.sh check APP_DIR | render MANIFEST WORKDIR" >&2
	exit 2
	;;
esac
