#!/bin/sh
# 예시 앱을 개발 머신에서 빌드해 폰에 놓을 묶음을 만든다. (#45)
#
#   build-app.sh NAME             examples/NAME → dist/apps/NAME
#   build-app.sh SRC_DIR OUT_DIR  소비처의 앱 → OUT_DIR (예: apps/blog/app → apps/blog/bundle, make deploy-app이 받는 모양)
#   build-app.sh --detect SRC_DIR 쓸 패키지 매니저와 설치할 디렉터리를 "pm root"로 출력한다
#
# 패키지 매니저는 lock 파일로 정한다 — 앱 폴더에서 위로 올라가며 가장 가까운 것 (pnpm-lock.yaml · yarn.lock ·
# package-lock.json, 레포 최상위까지). lock이 위에 있으면 workspace다: 설치는 거기서, 빌드는 앱 폴더에서.
#   NIMWAKE_PM  npm | pnpm | yarn으로 고정
#   BUILD_CMD   빌드 명령을 바꾼다 (앱 폴더에서 돈다) — 예: "pnpm --filter about... build"로 내부 패키지까지
# pnpm · yarn이 PATH에 없으면 Node에 든 corepack이 받는다 (package.json의 packageManager 버전).
#
# 두 종류를 안다 (next.config.*가 있으면 Next.js, 없으면 정적 사이트):
#   Next.js  standalone: .next/standalone/(server.js + 필요한 node_modules)에 static · public을 더한다.
#            manifest command = ["/opt/node/bin/node", "server.js"]
#   정적     Vite · Vite + TanStack Router · Docusaurus …: `run build`의 결과(dist/ · build/ · out/,
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

# 앱 폴더부터 위로 lock 파일을 찾는다. 레포 최상위(.git)까지만 — $HOME에 놓인 관계없는 lock으로 설치하지 않게
find_lock() {
	_d="$1"
	while [ "$_d" != "$HOME" ]; do
		if [ -z "${NIMWAKE_PM:-}" ] || [ "${NIMWAKE_PM:-}" = pnpm ]; then
			[ -f "$_d/pnpm-lock.yaml" ] && { echo "pnpm $_d"; return 0; }
		fi
		if [ -z "${NIMWAKE_PM:-}" ] || [ "${NIMWAKE_PM:-}" = yarn ]; then
			[ -f "$_d/yarn.lock" ] && { echo "yarn $_d"; return 0; }
		fi
		if [ -z "${NIMWAKE_PM:-}" ] || [ "${NIMWAKE_PM:-}" = npm ]; then
			[ -f "$_d/package-lock.json" ] && { echo "npm $_d"; return 0; }
		fi
		if [ -e "$_d/.git" ] || [ "$_d" = / ]; then
			break
		fi
		_d="$(dirname "$_d")"
	done
	return 1
}

detect_pm() {
	case "${NIMWAKE_PM:-}" in
	'' | npm | pnpm | yarn) ;;
	*)
		echo "build-app: NIMWAKE_PM=$NIMWAKE_PM — npm | pnpm | yarn" >&2
		exit 2
		;;
	esac
	find_lock "$1" || {
		echo "build-app: no lock file for $1 — commit package-lock.json, pnpm-lock.yaml or yarn.lock (a build must be reproducible)" >&2
		exit 1
	}
}

if [ "${1:-}" = --detect ]; then
	detect_pm "$(cd "${2:?usage: build-app.sh --detect SRC_DIR}" && pwd -P)"
	exit 0
fi

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

# pm을 쓸 수 있게 한다 — PATH에 없으면 corepack shim을 임시 디렉터리에 (package.json 스크립트 안의 호출까지 닿게)
pm_ready() {
	[ "$pm" != npm ] || return 0
	# WSL의 PATH에는 Windows 쪽 도구(/mnt/c/…)가 섞인다 — 다른 Node의 오래된 corepack이라 믿지 않는다
	case "$(node_cmd sh -c "command -v $pm" 2>/dev/null || true)" in
	'' | /mnt/*) ;;
	*) return 0 ;;
	esac
	shims="$(mktemp -d)"
	trap 'rm -rf "$shims"' EXIT
	node_cmd corepack enable --install-directory "$shims" "$pm"
	PATH="$shims:$PATH"
	export PATH COREPACK_ENABLE_DOWNLOAD_PROMPT=0
}

pm_install() {
	case "$pm" in
	npm) (cd "$pm_root" && node_cmd npm ci --no-audit --no-fund) ;;
	pnpm) (cd "$pm_root" && node_cmd pnpm install --frozen-lockfile) ;;
	yarn)
		case "$(cd "$pm_root" && node_cmd yarn --version)" in
		1.*) (cd "$pm_root" && node_cmd yarn install --frozen-lockfile) ;;
		*) (cd "$pm_root" && node_cmd yarn install --immutable) ;;
		esac
		;;
	esac
}

# 패키지 매니저의 audit을 JSON으로 — 형식이 셋이다:
#   npm · pnpm  한 덩어리, metadata.vulnerabilities
#   yarn 1      줄마다 JSON, type: auditSummary의 data.vulnerabilities (깨끗하면 그 한 줄뿐)
#   yarn 2+     줄마다 JSON, children.Severity. 깨끗하면 출력 없이 0 — 레지스트리에 못 닿아도 출력이 없지만 0이 아니다
pm_audit_json() {
	case "$pm" in
	npm) (cd "$pm_root" && node_cmd npm audit --omit=dev --json) ;;
	pnpm) (cd "$pm_root" && node_cmd pnpm audit --prod --json) ;;
	yarn)
		case "$(cd "$pm_root" && node_cmd yarn --version)" in
		1.*) (cd "$pm_root" && node_cmd yarn audit --groups dependencies --json) ;;
		*) (cd "$pm_root" && node_cmd yarn npm audit --all --recursive --environment production --json) ;;
		esac
		;;
	esac
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
	# audit은 취약점이 있으면 0이 아닌 코드로 끝난다 — 결과는 출력에서 읽는다
	rc=0
	raw="$(pm_audit_json 2>/dev/null)" || rc=$?
	counts="$(printf '%s' "$raw" | node_cmd node -e 'let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
		const line = (v) => console.log([v.critical, v.high, v.moderate, v.low].map((n) => n || 0).join(" "));
		try { const j = JSON.parse(s); if (j.metadata) return line(j.metadata.vulnerabilities); } catch {}
		const rows = s.split("\n").filter(Boolean).flatMap((l) => { try { return [JSON.parse(l)]; } catch { return []; } });
		const sum = rows.find((r) => r.type === "auditSummary");
		if (sum) return line(sum.data.vulnerabilities);
		const adv = rows.filter((r) => r.children && r.children.Severity);
		if (adv.length) { const v = {}; for (const r of adv) { const k = r.children.Severity.toLowerCase(); v[k] = (v[k] || 0) + 1; } return line(v); }
		console.log(""); })' || true)"
	if [ -z "$counts" ] && [ "$pm" = yarn ] && [ -z "$raw" ] && [ "$rc" -eq 0 ]; then
		counts="0 0 0 0"
	fi
	if [ -z "$counts" ]; then
		echo "build-app: $pm audit could not run (offline?) — production dependencies were not checked" >&2
		return 0
	fi
	# shellcheck disable=SC2086 # "critical high moderate low"를 넷으로 나눈다
	set -- $counts
	if [ "$1" -gt 0 ] || [ "$2" -gt 0 ]; then
		echo "build-app: $pm audit — $1 critical, $2 high, $3 moderate in production dependencies (run $pm audit for details)" >&2
		if [ "$mode" = fail ]; then
			echo "build-app: stopping (NIMWAKE_AUDIT=fail)" >&2
			exit 1
		fi
	else
		echo "build-app: $pm audit — no critical or high in production dependencies (moderate $3, low $4)"
	fi
}

cd "$src"
kind=static
for f in next.config.js next.config.mjs next.config.ts next.config.cjs; do
	[ -f "$f" ] && kind=next
done
# shellcheck disable=SC2046 # "pm root"를 둘로 나눈다
set -- $(detect_pm "$src")
pm="$1"
pm_root="$2"
echo "build-app: $pm ($pm_root)"
pm_ready
pm_install
audit_deps
if [ -n "${BUILD_CMD:-}" ]; then
	NEXT_TELEMETRY_DISABLED=1 node_cmd sh -c "$BUILD_CMD"
else
	NEXT_TELEMETRY_DISABLED=1 node_cmd "$pm" run build
fi

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
	echo "build-app: $name (static, $site/, $pm) → $out ($(du -sk "$out" | cut -f1) KB, node v$want)"
	exit 0
fi

# workspace면 standalone이 레포 모양을 지킨다 — server.js가 .next/standalone/<앱 경로>/ 아래에 있다
rel=""
if [ ! -f .next/standalone/server.js ]; then
	rel="${src#"$pm_root"/}"
	[ "$rel" != "$src" ] && [ -f ".next/standalone/$rel/server.js" ] || {
		echo "build-app: .next/standalone/server.js 가 없다 — next.config의 output: \"standalone\"" >&2
		exit 1
	}
fi
app_out="$out${rel:+/$rel}"

rm -rf "$out"
mkdir -p "$out"
# 심볼릭 링크는 그대로 옮긴다 — pnpm의 node_modules는 .pnpm을 가리키는 링크다
cp -R .next/standalone/. "$out/"
mkdir -p "$app_out/.next"
cp -R .next/static "$app_out/.next/static"
[ -d public ] && cp -R public "$app_out/public"
# 글은 요청 때도 읽는다 (lib/posts.js — 정적 생성 밖의 경로)
[ -d content ] && cp -R content "$app_out/content"
# manifest는 늘 server.js다 — workspace면 맨 위에서 앱의 것을 부른다 (ESM · CJS 어느 쪽이든 동적 import로)
if [ -n "$rel" ]; then
	echo "import(\"./$rel/server.js\");" >"$out/server.js"
fi

# 네이티브 모듈은 빌드 머신의 CPU용이다(x86_64) — 폰(aarch64)에서 로드되는 순간 깨진다.
# sharp는 Next.js 이미지 최적화의 선택 의존성이다. 예시 앱은 images.unoptimized라 쓰지 않으므로 뺀다.
# pnpm은 node_modules/.pnpm/sharp@… · @img+… 아래에 둔다
find "$out" \( -type d -o -type l \) \( -name sharp -o -name '@img' -o -name 'sharp@*' -o -name '@img+*' \) -path '*node_modules*' -prune -exec rm -rf {} +
native="$(find "$out" -name '*.node' | sed "s#^$out/##")"
if [ -n "$native" ]; then
	echo "build-app: 네이티브 모듈이 묶음에 있다 — 폰(aarch64)에서 깨진다:" >&2
	printf '%s\n' "$native" | sed 's/^/  /' >&2
	exit 1
fi

echo "build-app: $name ($pm) → $out ($(du -sk "$out" | cut -f1) KB, node v$want)"
