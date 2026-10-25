#!/bin/sh
# 예시 앱을 개발 머신에서 빌드해 폰에 놓을 묶음을 만든다. (#45)
#
#   build-app.sh NAME             examples/NAME → dist/apps/NAME
#   build-app.sh SRC_DIR OUT_DIR  소비처의 앱 → OUT_DIR (예: apps/blog/app → apps/blog/bundle, make deploy-app이 받는 모양)
#
# 두 종류를 안다 (next.config.*가 있으면 Next.js, 없으면 정적 사이트):
#   Next.js  standalone: .next/standalone/(server.js + 필요한 node_modules)에 static · public을 더한다.
#            manifest command = ["/opt/node/bin/node", "server.js"]
#   정적     Vite · Vite + TanStack Router · Docusaurus …: `npm run build`의 결과(dist/ · build/ · out/,
#            STATIC_DIR로 지정)를 site/에, 이 레포의 runtime/static-server.mjs를 server.mjs로.
#            manifest command = ["/opt/node/bin/node", "server.mjs"], env SPA = "1" | "0"
# 폰은 이 묶음을 `node server.js`로만 돌린다 — 폰에서 npm install · next build를 하지 않는다
# (Core binary를 Core CI가 빌드하고 폰은 받기만 하는 것과 같은 구조, D-A3).
# 결과는 순수 JS다 — 빌드 머신의 CPU(x86_64)와 폰(aarch64)이 달라도 된다. 네이티브 모듈을 쓰면 깨진다.
#
# Node는 guest/node.lock의 버전을 쓴다. PATH에 그 버전이 없으면 mise로 고른다.
# 빌드 전에 묶음에 들어갈 의존성의 알려진 취약점을 본다 — NIMWAKE_AUDIT=warn(기본) · fail · off
set -eu

root="$(cd "$(dirname "$0")/.." && pwd -P)"
if [ $# -ge 2 ]; then
	src="$(cd "$1" && pwd -P)"
	mkdir -p "$2"
	out="$(cd "$2" && pwd -P)"
	name="$(basename "$src")"
else
	name="${1:?usage: build-app.sh NAME | build-app.sh SRC_DIR OUT_DIR}"
	src="$root/examples/$name"
	out="$root/dist/apps/$name"
fi

[ -f "$src/package.json" ] || {
	echo "build-app: $src/package.json 이 없다" >&2
	exit 1
}

# OUT_DIR을 통째로 바꾼다 — 소스 · 그 상위 · 홈 · / 이면 지우지 않는다 (소비처가 경로를 잘못 줄 수 있다).
# 빌드 전에 본다 — 몇 분 걸려 빌드한 뒤에 거절하지 않게
case "$src/" in
"$out"/*)
	echo "build-app: OUT_DIR $out 이 소스($src)를 품는다 — 다른 경로를 준다" >&2
	exit 1
	;;
esac
if [ "$out" = / ] || [ "$out" = "$HOME" ] || [ "$out" = "$root" ]; then
	echo "build-app: OUT_DIR $out 은 지울 수 없다" >&2
	exit 1
fi

want="$(sed -n 's/^version=//p' "$root/guest/node.lock")"
node_cmd() {
	if [ "$(node --version 2>/dev/null)" = "v$want" ]; then
		"$@"
	elif command -v mise >/dev/null 2>&1; then
		mise exec "node@$want" -- "$@"
	else
		echo "build-app: Node v$want 이 필요하다 — mise install node@$want (make doctor-dev)" >&2
		exit 1
	fi
}

# 묶음에 들어갈 의존성(dev 제외)의 알려진 취약점 — 공개 앱 하나가 뚫리면 폰 전체가 넘어갈 수 있다 (Phase 2 04 T1).
#   NIMWAKE_AUDIT  warn(기본 — critical · high를 알린다) · fail(그러면 멈춘다) · off
audit_deps() {
	mode="${NIMWAKE_AUDIT:-warn}"
	case "$mode" in
	off) return 0 ;;
	warn | fail) ;;
	*)
		echo "build-app: NIMWAKE_AUDIT=$mode — warn | fail | off" >&2
		exit 2
		;;
	esac
	# npm audit은 취약점이 있으면 0이 아닌 코드로 끝난다 — 결과는 JSON의 metadata에서 읽는다
	counts="$(node_cmd npm audit --omit=dev --json 2>/dev/null |
		node_cmd node -e 'let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
			try { const v = JSON.parse(s).metadata.vulnerabilities; console.log([v.critical, v.high, v.moderate, v.low].map((n) => n || 0).join(" ")); }
			catch { console.log(""); } })' || true)"
	if [ -z "$counts" ]; then
		echo "build-app: npm audit could not run (offline?) — production dependencies were not checked" >&2
		return 0
	fi
	# shellcheck disable=SC2086 # "critical high moderate low"를 넷으로 나눈다
	set -- $counts
	if [ "$1" -gt 0 ] || [ "$2" -gt 0 ]; then
		echo "build-app: npm audit — $1 critical, $2 high, $3 moderate in production dependencies (npm audit --omit=dev for details, npm audit fix to update)" >&2
		if [ "$mode" = fail ]; then
			echo "build-app: stopping (NIMWAKE_AUDIT=fail)" >&2
			exit 1
		fi
	else
		echo "build-app: npm audit — no critical or high in production dependencies (moderate $3, low $4)"
	fi
}

cd "$src"
kind=static
for f in next.config.js next.config.mjs next.config.ts next.config.cjs; do
	[ -f "$f" ] && kind=next
done
node_cmd npm ci --no-audit --no-fund
audit_deps
NEXT_TELEMETRY_DISABLED=1 node_cmd npm run build

if [ "$kind" = static ]; then
	# 빌드 결과 디렉터리 — Vite는 dist/, Docusaurus는 build/, 그 밖의 정적 export는 out/
	site="${STATIC_DIR:-}"
	if [ -z "$site" ]; then
		for d in dist build out; do
			if [ -f "$d/index.html" ]; then
				site="$d"
				break
			fi
		done
	fi
	[ -n "$site" ] && [ -f "$site/index.html" ] || {
		echo "build-app: 정적 빌드 결과(index.html)를 찾지 못했다 — dist/ · build/ · out/ 중 어디도 아니면 STATIC_DIR=…" >&2
		exit 1
	}
	rm -rf "$out"
	mkdir -p "$out"
	cp -R "$site" "$out/site"
	cp "$root/runtime/static-server.mjs" "$out/server.mjs"
	echo "build-app: $name (static, $site/) → $out ($(du -sk "$out" | cut -f1) KB, node v$want)"
	exit 0
fi

[ -f .next/standalone/server.js ] || {
	echo "build-app: .next/standalone/server.js 가 없다 — next.config의 output: \"standalone\"" >&2
	exit 1
}

rm -rf "$out"
mkdir -p "$out"
cp -R .next/standalone/. "$out/"
mkdir -p "$out/.next"
cp -R .next/static "$out/.next/static"
[ -d public ] && cp -R public "$out/public"
# 글은 요청 때도 읽는다 (lib/posts.js — 정적 생성 밖의 경로)
[ -d content ] && cp -R content "$out/content"

# 네이티브 모듈은 빌드 머신의 CPU용이다(x86_64) — 폰(aarch64)에서 로드되는 순간 깨진다.
# sharp는 Next.js 이미지 최적화의 선택 의존성이다. 예시 앱은 images.unoptimized라 쓰지 않으므로 뺀다.
rm -rf "$out/node_modules/sharp" "$out/node_modules/@img"
native="$(find "$out" -name '*.node' | sed "s#^$out/##")"
if [ -n "$native" ]; then
	echo "build-app: 네이티브 모듈이 묶음에 있다 — 폰(aarch64)에서 깨진다:" >&2
	printf '%s\n' "$native" | sed 's/^/  /' >&2
	exit 1
fi

echo "build-app: $name → $out ($(du -sk "$out" | cut -f1) KB, node v$want)"
