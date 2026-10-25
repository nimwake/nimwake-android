#!/bin/sh
# 소비처 레포에 새 앱 폴더를 만든다 — 예시를 복사하고 name · host · port를 채운다. 템플릿의 make new-app이 부른다.
#
#   new-app.sh APPS_DIR NAME KIND [HOST] [EXPOSURE]
#     KIND      static (Vite · TanStack Router · Docusaurus — apps/site에서) | next (Next.js — apps/blog에서)
#     HOST      공개 hostname (기본 NAME.example.com — Cloudflare에 등록할 이름으로 바꾼다)
#     EXPOSURE  lan(기본 — allow를 LAN 대역으로 넣는다) | public
#
# port는 APPS_DIR의 다른 앱과 겹치지 않게 3200부터 고른다. 다른 레포가 같은 폰에 올린 앱과의 충돌은
# Core가 배포 때 거부하고 이전 상태로 되돌린다 — 그때 nimwake.toml의 port와 PORT를 바꾼다
set -eu

root="$(cd "$(dirname "$0")/.." && pwd -P)"
apps="${1:?usage: new-app.sh APPS_DIR NAME KIND [HOST] [EXPOSURE]}"
name="${2:?usage: new-app.sh APPS_DIR NAME KIND [HOST] [EXPOSURE]}"
kind="${3:?usage: new-app.sh APPS_DIR NAME KIND [HOST] [EXPOSURE]}"
host="${4:-$name.example.com}"
exposure="${5:-lan}"

fail() {
	echo "new-app: $*" >&2
	exit 1
}

case "$name" in
*[!a-z0-9-]* | -*) fail "name '$name' — lowercase letters, digits and '-' (it becomes a path on the phone)" ;;
esac
case "$kind" in
static) example=site ;;
next) example=blog ;;
*) fail "KIND=$kind — static | next" ;;
esac
case "$exposure" in
lan | public) ;;
*) fail "EXPOSURE=$exposure — lan | public" ;;
esac
case "$host" in
*[!A-Za-z0-9.-]* | '') fail "host '$host' — a hostname" ;;
esac
src="$root/examples/consumer-template/apps/$example"
dest="$apps/$name"
[ -d "$src" ] || fail "no example at $src"
[ ! -e "$dest" ] || fail "$dest already exists"

# 이 레포의 다른 앱이 쓰는 port를 피한다
used="$(cat "$apps"/*/nimwake.toml 2>/dev/null | sed -n 's/^port = \([0-9][0-9]*\).*/\1/p' | sort -u)"
port=3200
while printf '%s\n' "$used" | grep -qx "$port"; do
	port=$((port + 1))
done

mkdir -p "$dest"
# 소스만 — 빌드 결과 · 의존성 · 묶음은 다시 만든다
(cd "$src" && tar -cf - --exclude=bundle --exclude=node_modules --exclude=dist --exclude=build --exclude=.next --exclude=exposure .) |
	(cd "$dest" && tar -xf -)

old_port="$(sed -n 's/^port = \([0-9][0-9]*\).*/\1/p' "$dest/nimwake.toml" | head -n 1)"
allow=""
if [ "$exposure" = lan ]; then
	# 터널(peer 127.0.0.1)로는 닿지 않게 — LAN 대역만 (Core §82)
	allow='allow = ["192.168.0.0/16"]'
fi
awk -v name="$name" -v host="$host" -v port="$port" -v old="$old_port" -v allow="$allow" '
	/^name = / { print "name = \"" name "\""; next }
	/^host = / { print "host = \"" host "\""; next }
	/^port = / { print "port = " port; if (allow != "") print allow; next }
	/^allow = / { next }
	{ gsub("\"" old "\"", "\"" port "\""); print }
' "$dest/nimwake.toml" >"$dest/nimwake.toml.new"
mv "$dest/nimwake.toml.new" "$dest/nimwake.toml"
echo "$exposure" >"$dest/exposure"
if [ -f "$dest/app/package.json" ]; then
	sed "s/^  \"name\": \"[^\"]*\"/  \"name\": \"$name\"/" "$dest/app/package.json" >"$dest/app/package.json.new"
	mv "$dest/app/package.json.new" "$dest/app/package.json"
fi
# lock의 이름(맨 위와 packages[""]) — 처음 두 번만. 의존성의 name은 건드리지 않는다
if [ -f "$dest/app/package-lock.json" ]; then
	awk -v name="$name" -v old="$example" '
		n < 2 && index($0, "\"name\": \"" old "\"") { sub("\"name\": \"" old "\"", "\"name\": \"" name "\""); n++ }
		{ print }
	' "$dest/app/package-lock.json" >"$dest/app/package-lock.json.new"
	mv "$dest/app/package-lock.json.new" "$dest/app/package-lock.json"
fi

echo "new-app: $dest ($kind from $example, host $host, port $port, $exposure)"
echo "  next: edit $dest/app, then make deploy APP=$name"
[ "$exposure" = public ] && echo "  public: add $host as a Public Hostname in your Cloudflare tunnel → http://localhost:8080"
exit 0
