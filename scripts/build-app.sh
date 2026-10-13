#!/bin/sh
# 예시 앱을 개발 머신에서 빌드해 폰에 놓을 묶음을 만든다. (#45)
#
#   build-app.sh NAME     examples/NAME → dist/apps/NAME
#
# Next.js standalone: .next/standalone/(server.js + 필요한 node_modules)에 static · public을 더한다.
# 폰은 이 묶음을 `node server.js`로만 돌린다 — 폰에서 npm install · next build를 하지 않는다
# (Core binary를 Core CI가 빌드하고 폰은 받기만 하는 것과 같은 구조, D-A3).
# 결과는 순수 JS다 — 빌드 머신의 CPU(x86_64)와 폰(aarch64)이 달라도 된다. 네이티브 모듈을 쓰면 깨진다.
#
# Node는 guest/node.lock의 버전을 쓴다. PATH에 그 버전이 없으면 mise로 고른다.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd -P)"
name="${1:?usage: build-app.sh NAME}"
src="$root/examples/$name"
out="$root/dist/apps/$name"

[ -f "$src/package.json" ] || {
	echo "build-app: $src/package.json 이 없다" >&2
	exit 1
}

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

cd "$src"
node_cmd npm ci --no-audit --no-fund
NEXT_TELEMETRY_DISABLED=1 node_cmd npm run build

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

echo "build-app: $name → dist/apps/$name ($(du -sk "$out" | cut -f1) KB, node v$want)"
