#!/bin/sh
# build-app.sh를 실제 패키지 매니저로 끝까지 — 묶음을 띄워 응답을 본다. 기기 없이 돈다 (examples.yml, 네트워크 필요).
#
#   pnpm · yarn 1 · yarn 4   정적 사이트 (템플릿 site에서 lock을 만들어)
#   pnpm workspace           Next.js 앱이 내부 패키지를 쓴다 — standalone이 깊어지고 node_modules가 링크다
#
# Node는 guest/node.lock의 버전이 PATH에 있어야 한다
set -eu

root="$(cd "$(dirname "$0")/../.." && pwd -P)"
build="$root/scripts/build-app.sh"
t="$(mktemp -d)"
port=3180
server=""
cleanup() {
	[ -z "$server" ] || kill "$server" 2>/dev/null || true
	rm -rf "$t"
}
trap cleanup EXIT
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
# yarn 4는 CI에서 기본이 lock 고정이다 — 시험용 lock을 만들 때는 푼다 (build-app.sh의 --immutable은 그대로)
# 테스트 파일은 $HOME 아래가 아닐 수도 있다 — lock 탐색이 임시 디렉터리에서 끝나게
git init -q "$t"

# serve BUNDLE SCRIPT PATH… — 띄워서 경로마다 200인지
serve() {
	_b="$1"
	_s="$2"
	shift 2
	port=$((port + 1))
	(cd "$_b" && exec env PORT="$port" HOSTNAME=127.0.0.1 NODE_ENV=production node "$_s") >"$t/server.log" 2>&1 &
	server=$!
	_i=0
	until curl -s -o /dev/null "http://127.0.0.1:$port/"; do
		_i=$((_i + 1))
		[ "$_i" -lt 75 ] || { cat "$t/server.log"; exit 1; }
		sleep 0.2
	done
	for _p in "$@"; do
		_c="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$port$_p")"
		echo "  $_p $_c"
		[ "$_c" = 200 ] || { cat "$t/server.log"; exit 1; }
	done
	kill "$server"
	wait "$server" 2>/dev/null || true
	server=""
}

# 출력은 파일로 — 파이프로 거르면 빌드 실패가 가려진다
run_build() {
	if ! "$build" "$1" "$2" >"$t/build.log" 2>&1; then
		cat "$t/build.log"
		exit 1
	fi
	grep 'build-app:' "$t/build.log"
}

site() { # DIR
	mkdir -p "$1"
	cp -R "$root/examples/consumer-template/apps/site/app/." "$1/"
	rm -f "$1/package-lock.json"
	rm -rf "$1/node_modules" "$1/dist"
}

echo "== pnpm, static"
site "$t/pnpm"
(cd "$t/pnpm" && corepack pnpm@10.18.3 install --lockfile-only >/dev/null)
sed 's/"private": true,/"private": true,\n  "packageManager": "pnpm@10.18.3",/' "$t/pnpm/package.json" >"$t/pnpm/p" && mv "$t/pnpm/p" "$t/pnpm/package.json"
run_build "$t/pnpm" "$t/out-pnpm"
serve "$t/out-pnpm" server.mjs / /about

echo "== yarn 1, static"
site "$t/yarn1"
sed 's/"private": true,/"private": true,\n  "packageManager": "yarn@1.22.22",/' "$t/yarn1/package.json" >"$t/yarn1/p" && mv "$t/yarn1/p" "$t/yarn1/package.json"
(cd "$t/yarn1" && corepack yarn install --ignore-scripts >/dev/null 2>&1 && rm -rf node_modules)
run_build "$t/yarn1" "$t/out-yarn1"
serve "$t/out-yarn1" server.mjs / /about

echo "== yarn 4, static"
site "$t/yarn4"
sed 's/"private": true,/"private": true,\n  "packageManager": "yarn@4.9.2",/' "$t/yarn4/package.json" >"$t/yarn4/p" && mv "$t/yarn4/p" "$t/yarn4/package.json"
echo 'nodeLinker: node-modules' >"$t/yarn4/.yarnrc.yml"
(cd "$t/yarn4" && YARN_ENABLE_IMMUTABLE_INSTALLS=false corepack yarn install --mode=skip-build >/dev/null 2>&1 && rm -rf node_modules .yarn/cache)
run_build "$t/yarn4" "$t/out-yarn4"
serve "$t/out-yarn4" server.mjs / /about

echo "== pnpm workspace, Next.js with an internal package"
w="$t/mono"
mkdir -p "$w/apps/web/app" "$w/packages/greet"
cat >"$w/package.json" <<'EOF'
{ "name": "mono", "private": true, "packageManager": "pnpm@10.18.3" }
EOF
printf 'packages:\n  - apps/*\n  - packages/*\n' >"$w/pnpm-workspace.yaml"
cat >"$w/packages/greet/package.json" <<'EOF'
{ "name": "@mono/greet", "version": "0.0.0", "main": "index.js" }
EOF
echo 'module.exports = { greet: () => "hello from a workspace package" };' >"$w/packages/greet/index.js"
next="$(sed -n 's/.*"next": "\([^"]*\)".*/\1/p' "$root/examples/blog/package.json")"
react="$(sed -n 's/.*"react": "\([^"]*\)".*/\1/p' "$root/examples/blog/package.json")"
cat >"$w/apps/web/package.json" <<EOF
{ "name": "web", "private": true, "scripts": { "build": "next build" },
  "dependencies": { "@mono/greet": "workspace:*", "next": "$next", "react": "$react", "react-dom": "$react" } }
EOF
cat >"$w/apps/web/next.config.mjs" <<'EOF'
export default { output: "standalone", images: { unoptimized: true } };
EOF
cat >"$w/apps/web/app/layout.jsx" <<'EOF'
export default function Layout({ children }) { return <html><body>{children}</body></html>; }
EOF
cat >"$w/apps/web/app/page.jsx" <<'EOF'
import { greet } from "@mono/greet";
export default function Page() { return <p>{greet()}</p>; }
EOF
(cd "$w" && corepack pnpm install --lockfile-only >/dev/null)
[ "$("$build" --detect "$w/apps/web")" = "pnpm $w" ]
run_build "$w/apps/web" "$t/out-mono"
serve "$t/out-mono" server.js /
[ -z "$(find "$t/out-mono" -name '*.node' | head -n 1)" ]

echo "== a known-vulnerable dependency is caught by every audit"
# lodash 4.17.20 — high. NIMWAKE_AUDIT=fail이면 빌드가 멈춰야 한다
vuln() { # NAME PACKAGE_MANAGER EXTRA-CONFIG
	v="$t/vuln-$1"
	mkdir -p "$v"
	cat >"$v/package.json" <<EOF
{ "name": "v", "private": true, "packageManager": "$2",
  "scripts": { "build": "mkdir -p dist && echo hi > dist/index.html" }, "dependencies": { "lodash": "4.17.20" } }
EOF
	[ -z "$3" ] || echo "$3" >"$v/.yarnrc.yml"
	case "$2" in
	pnpm*) (cd "$v" && corepack pnpm install --lockfile-only >/dev/null) ;;
	*) (cd "$v" && YARN_ENABLE_IMMUTABLE_INSTALLS=false corepack yarn install >/dev/null 2>&1 && rm -rf node_modules .yarn/cache) ;;
	esac
	if NIMWAKE_AUDIT=fail "$build" "$v" "$t/out-vuln-$1" >"$t/build.log" 2>&1; then
		cat "$t/build.log"
		echo "$1: a vulnerable dependency passed" >&2
		exit 1
	fi
	grep -q 'NIMWAKE_AUDIT=fail' "$t/build.log" || { cat "$t/build.log"; exit 1; }
	echo "  $1: $(grep -o '[0-9]* critical, [0-9]* high' "$t/build.log")"
}
vuln pnpm pnpm@10.18.3 ""
vuln yarn1 yarn@1.22.22 ""
vuln yarn4 yarn@4.9.2 "nodeLinker: node-modules"

echo "PASS package managers"
