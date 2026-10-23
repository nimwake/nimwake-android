#!/bin/sh
# 소비처 앱을 폰에 배포 · 되돌리기 · 빼기 · 보기. 소비처(개인 레포)가 부르는 입구다.
# 배포 계약: .docs/phases/phase-2/03-deploy-and-ingress-contract.md "1. 앱 배포 계약"
#
#   apps.sh deploy APP_DIR     bundle/ → releases/<id>, working_dir을 채운 manifest, SIGHUP (Core §76)
#   apps.sh rollback NAME      직전 release로 되돌리고 SIGHUP (PRD §31)
#   apps.sh remove NAME        manifest를 빼고 SIGHUP — Core가 정지시키고 라우팅에서 뺀다
#   apps.sh list               앱 · 현재 release · 상태 (SIGUSR1 스냅샷, Core §79)
#
# 다른 앱은 건드리지 않는다 — daemon을 재시작하지 않고 SIGHUP으로 재적재한다. Core가 재적재를 거부하면
# (검증 실패 등) 이전 manifest로 되돌리고 다시 SIGHUP한다. release는 3개만 남긴다 (PRD §19).
# 배포하려는 앱이 진행 중인 soak의 대상이면 거부한다 — FORCE=1
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

root="$(cd "$(dirname "$0")/.." && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"

usage() {
	echo "usage: apps.sh deploy APP_DIR | rollback NAME | remove NAME | list" >&2
	exit 2
}

# 기기에서 도는 스크립트 = 공통 부분 + 명령별 본문. `ssh … sh -s 인자`로 보낸다.
# 본문은 따옴표 없는 heredoc이라 기기 쪽 $는 개발 머신에서 풀리지 않는다
device_lib() {
	cat <<'EOF'
set -eu
rootfs="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs"
manifests="$rootfs/home/nimwake/.nimwake/apps"
apps="$rootfs/home/nimwake/apps"
log="$HOME/.nimwake-host/logs/nimwaked.log"
daemon="$(pgrep -f '^/opt/nimwake/bin/nimwaked' | head -n 1)"
[ -n "$daemon" ] || { echo "apps: nimwaked is not running — nimwake-host start" >&2; exit 1; }

# SIGHUP을 보내고 Core의 재적재 결과 한 줄을 출력한다 (Core §76). 거부되면 1
reload() {
	_n="$(wc -l <"$log")"
	kill -HUP "$daemon"
	_i=0
	while [ "$_i" -lt 50 ]; do
		_line="$(tail -n +"$((_n + 1))" "$log" | grep -E 'reloaded: |keeping the current set' | tail -n 1)"
		if [ -n "$_line" ]; then
			echo "  core: ${_line#*nimwaked: }"
			case "$_line" in *"reloaded: "*) return 0 ;; *) return 1 ;; esac
		fi
		sleep 0.2
		_i=$((_i + 1))
	done
	echo "  core: no reload result in 10s" >&2
	return 1
}
EOF
}

# 원격 셸에 넘길 인자 하나를 작은따옴표로 감싼다. ssh는 인자를 공백으로 이어 붙여 원격 셸이 다시 나누므로,
# 그대로 넘기면 빈 값("")이 사라져 뒤의 인자가 한 칸씩 당겨진다 — FORCE가 비어 있을 때 실제로 그랬다 (10-14 기기)
shell_quote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

on_device() {
	_body="$1"
	shift
	_args=""
	for _a in "$@"; do
		_args="$_args $(shell_quote "$_a")"
	done
	{
		device_lib
		printf '%s\n' "$_body"
	} | ssh "$device" "sh -s --$_args"
}

cmd_deploy() {
	dir="${1:?usage: apps.sh deploy APP_DIR}"
	dir="$(cd "$dir" && pwd -P)"
	# shellcheck disable=SC2046 # "name host port exposure"를 네 인자로 나눈다
	set -- $("$root/scripts/app-manifest.sh" check "$dir")
	name="$1"
	host="$2"
	exposure="$4"
	id="$(date -u +%Y%m%dT%H%M%SZ)"
	workdir="/home/nimwake/apps/$name/releases/$id"
	stage=".nimwake-host/stage-app-$name"
	echo "== deploy $name ($host, $exposure) → release $id"

	# 1) 묶음과 manifest를 기기의 stage로 (표준 입력을 tar가 쓴다 — 스크립트는 다음 ssh로)
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT
	"$root/scripts/app-manifest.sh" render "$dir/nimwake.toml" "$workdir" >"$tmp/nimwake.toml"
	mkdir -p "$tmp/bundle"
	(cd "$dir/bundle" && tar -cf - .) | (cd "$tmp/bundle" && tar -xf -)
	(cd "$tmp" && tar -cf - nimwake.toml bundle) |
		ssh "$device" "rm -rf \$HOME/$stage && mkdir -p \$HOME/$stage && tar -xf - -C \$HOME/$stage"

	# 2) 기기에서: soak 대상 확인 → release로 옮김 → manifest 교체 → SIGHUP → 거부면 되돌림 → 정리
	on_device "$(
		cat <<'EOF'
name="$1"; host="$2"; id="$3"; stage="$HOME/$4"; force="$5"; exposure="$6"; keep=3
trap 'rm -rf "$stage"' EXIT
s="$HOME/.nimwake-host/run/soak.active"
if [ -f "$s" ] && [ "$force" != 1 ] && [ "$(cut -d' ' -f3 "$s")" = "$host" ]; then
	echo "apps: a soak is measuring $host — redeploying would change what it measures. FORCE=1" >&2
	exit 1
fi
rel="$apps/$name/releases/$id"
mkdir -p "$apps/$name/releases" "$manifests/$name"
mv "$stage/bundle" "$rel"
echo "  bundle: $(du -sk "$rel" | cut -f1) KB → /home/nimwake/apps/$name/releases/$id"
cur="$manifests/$name/nimwake.toml"
prev=""
if [ -f "$cur" ]; then
	prev="$stage/prev.toml"
	cp "$cur" "$prev"
fi
cp "$stage/nimwake.toml" "$cur"
if ! reload; then
	echo "apps: Core rejected the reload — restoring the previous manifest" >&2
	if [ -n "$prev" ]; then cp "$prev" "$cur"; else rm -rf "${manifests:?}/$name"; fi
	rm -rf "$rel"
	reload >/dev/null || true
	exit 1
fi
if [ -f "$apps/$name/current" ]; then
	mv "$apps/$name/current" "$apps/$name/previous"
fi
echo "$id" >"$apps/$name/current"
# 노출 선언 — ingress provider는 public 앱의 host만 받는다 (host/lib/ingress.sh, Phase 2 04)
was="$(cat "$apps/$name/exposure" 2>/dev/null || echo lan)"
echo "$exposure" >"$apps/$name/exposure"
if [ "$was" != "$exposure" ]; then
	echo "  exposure $was → $exposure — the ingress picks it up on the next make restart"
fi
# 최근 keep개, 그리고 current · previous는 남긴다 (PRD §19)
cur_id="$(cat "$apps/$name/current")"
prev_id="$(cat "$apps/$name/previous" 2>/dev/null || true)"
ls -1 "$apps/$name/releases" | sort -r | tail -n +$((keep + 1)) | while read -r old; do
	if [ "$old" != "$cur_id" ] && [ "$old" != "$prev_id" ]; then
		rm -rf "${apps:?}/$name/releases/$old"
		echo "  removed old release $old"
	fi
done
echo "  ok — the next request to $host starts release $id"
EOF
	)" "$name" "$host" "$id" "$stage" "${FORCE:-}" "$exposure"
}

cmd_rollback() {
	name="${1:?usage: apps.sh rollback NAME}"
	on_device "$(
		cat <<'EOF'
name="$1"
prev="$(cat "$apps/$name/previous" 2>/dev/null || true)"
cur="$(cat "$apps/$name/current" 2>/dev/null || true)"
if [ -z "$prev" ] || [ ! -d "$apps/$name/releases/$prev" ]; then
	echo "apps: $name has no previous release" >&2
	exit 1
fi
m="$manifests/$name/nimwake.toml"
cp "$m" "$m.bak"
sed -i "s#^working_dir = .*#working_dir = \"/home/nimwake/apps/$name/releases/$prev\"#" "$m" # portable-ok: 기기(Termux, GNU)에서 돈다
echo "== rollback $name: $cur → $prev"
if reload; then
	echo "$prev" >"$apps/$name/current"
	echo "$cur" >"$apps/$name/previous"
	rm -f "$m.bak"
else
	mv "$m.bak" "$m"
	reload >/dev/null || true
	exit 1
fi
EOF
	)" "$name"
}

cmd_remove() {
	name="${1:?usage: apps.sh remove NAME}"
	on_device "$(
		cat <<'EOF'
name="$1"
m="$manifests/$name/nimwake.toml"
[ -f "$m" ] || { echo "apps: no app $name" >&2; exit 1; }
mkdir -p "$apps/$name"
mv "$m" "$apps/$name/removed.toml"
rmdir "$manifests/$name" 2>/dev/null || true
echo "== remove $name (releases kept in /home/nimwake/apps/$name)"
if ! reload; then
	echo "apps: Core kept the current set — restoring $name" >&2
	mkdir -p "$manifests/$name"
	mv "$apps/$name/removed.toml" "$m"
	reload >/dev/null || true
	exit 1
fi
EOF
	)" "$name"
}

cmd_list() {
	on_device "$(
		cat <<'EOF'
# 상태는 Core에게 직접 묻는다 — control socket (§85 · §86 `nimwake status --json`, #71).
# socket이 없는 daemon(Core v0.1.2 전, 또는 업그레이드 뒤 재시작 전)이면 예전처럼 SIGUSR1 스냅샷을 로그에서 읽는다
sock="$HOME/.nimwake-host/run/core/nimwake.sock"
cli="$rootfs/opt/nimwake/bin/nimwake"
json=""
if [ -S "$sock" ] && [ -x "$cli" ]; then
	json="$("$cli" status --json --socket "$sock" 2>/dev/null | tr '{' '\n')"
fi
if [ -z "$json" ]; then
	n="$(wc -l <"$log")"
	kill -USR1 "$daemon"
	sleep 0.5
	snap="$(tail -n +$((n + 1)) "$log")"
fi
printf '%-10s %-28s %-6s %-8s %-18s %s\n' NAME HOST PORT EXPOSURE RELEASE STATE
for m in "$manifests"/*/nimwake.toml; do
	name="$(sed -n 's/^name = "\(.*\)"/\1/p' "$m")"
	host="$(sed -n 's/^host = "\(.*\)"/\1/p' "$m")"
	port="$(sed -n 's/^port = \([0-9]*\)/\1/p' "$m")"
	# 없으면 lan — 공개하지 않는 쪽이 기본이다 (Phase 2 04)
	exposure="$(cat "$apps/$name/exposure" 2>/dev/null || echo lan)"
	rel="$(cat "$apps/$name/current" 2>/dev/null || echo -)"
	if [ -n "$json" ]; then
		line="$(printf '%s\n' "$json" | grep "\"name\":\"$name\"" | head -n 1)"
		st="$(printf '%s' "$line" | sed -n 's/.*"state":"\([A-Z_]*\)".*/\1/p')"
		pid="$(printf '%s' "$line" | sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p')"
		state="${st:+$st pid ${pid:--}}"
	else
		state="$(printf '%s\n' "$snap" | grep "app app=\"$name\"" | sed -n 's/.* state=\([A-Z]*\) pid="\([^"]*\)".*/\1 pid \2/p' | tail -n 1)"
	fi
	printf '%-10s %-28s %-6s %-8s %-18s %s\n' "$name" "$host" "$port" "$exposure" "$rel" "${state:-?}"
done
EOF
	)"
}

case "${1:-}" in
deploy) shift; cmd_deploy "$@" ;;
rollback) shift; cmd_rollback "$@" ;;
remove) shift; cmd_remove "$@" ;;
list) cmd_list ;;
*) usage ;;
esac
