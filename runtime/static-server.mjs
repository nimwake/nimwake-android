// 정적 빌드 사이트(Vite · Vite + TanStack Router · Docusaurus …)를 내주는 작은 HTTP 서버.
// build-app.sh가 소비처 앱의 빌드 결과(site/)와 함께 묶음에 server.mjs로 넣는다 — 폰에서는 `node server.mjs`.
// Node 내장 모듈만 쓴다: 폰에서 npm install을 하지 않고, 묶음에 네이티브 모듈이 섞일 일도 없다.
//
//   PORT       듣는 port (manifest의 [server] port와 같게) — 필수
//   HOSTNAME   듣는 주소 (기본 127.0.0.1 — 밖에서는 Nimwake gateway를 거쳐서만 닿는다)
//   SITE_DIR   빌드 결과 디렉터리 (기본: 이 파일 옆의 site/)
//   SPA        1(기본) — 없는 경로를 index.html로 (클라이언트 라우터가 그린다: TanStack Router · React Router)
//              0 — 페이지마다 HTML이 있는 사이트(Docusaurus 등): 없는 경로는 404.html
//
// 사이트 루트의 _redirects · _headers (Cloudflare Pages · Netlify와 같은 모양 — Vite면 public/에 둔다):
//   _redirects   한 줄에 하나: `/from /to [301|302|303|307|308]` (기본 302). `*`은 끝까지, `:name`은 한 칸 —
//                to에서 `:splat` · `:name`으로 쓴다. to가 https://…이면 다른 사이트로. 위에서부터 첫 일치
//   _headers     경로 패턴 한 줄, 그 아래 들여 쓴 `Name: value` 줄들. 맞는 블록을 모두 적용하고 같은 이름은 뒤가 이긴다
//                (Cache-Control도 덮을 수 있다). 두 파일 자체는 내주지 않는다
//
// 압축은 하지 않는다 — Cloudflare가 가장자리에서 한다. 캐시: 해시가 붙은 파일은 1년 immutable,
// HTML은 매번 확인(no-cache + ETag → 304). 배포가 바뀌면 HTML이 새 해시 파일을 가리킨다.

import { createServer } from "node:http";
import { createReadStream, readFileSync } from "node:fs";
import { stat } from "node:fs/promises";
import { extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const TYPES = {
	".html": "text/html; charset=utf-8",
	".htm": "text/html; charset=utf-8",
	".js": "text/javascript; charset=utf-8",
	".mjs": "text/javascript; charset=utf-8",
	".css": "text/css; charset=utf-8",
	".json": "application/json; charset=utf-8",
	".map": "application/json; charset=utf-8",
	".webmanifest": "application/manifest+json",
	".txt": "text/plain; charset=utf-8",
	".xml": "application/xml; charset=utf-8",
	".svg": "image/svg+xml",
	".png": "image/png",
	".jpg": "image/jpeg",
	".jpeg": "image/jpeg",
	".gif": "image/gif",
	".webp": "image/webp",
	".avif": "image/avif",
	".ico": "image/x-icon",
	".woff": "font/woff",
	".woff2": "font/woff2",
	".ttf": "font/ttf",
	".otf": "font/otf",
	".wasm": "application/wasm",
	".mp4": "video/mp4",
	".webm": "video/webm",
	".mp3": "audio/mpeg",
	".pdf": "application/pdf",
};

// Vite(assets/name-abc123.js) · Docusaurus(main.abc12345.js) · webpack([contenthash]) 모양
const HASHED = /[.-][0-9a-zA-Z_-]{8,}\.[a-z0-9]+$/;

// `/blog/:slug/*` → 정규식과 자리 이름들
function compilePattern(pattern) {
	const keys = [];
	let re = "";
	for (let i = 0; i < pattern.length; i++) {
		const c = pattern[i];
		if (c === "*") {
			keys.push("splat");
			re += "(.*)";
		} else if (c === ":" && /[A-Za-z]/.test(pattern[i + 1] ?? "")) {
			let name = "";
			while (/[A-Za-z0-9_]/.test(pattern[i + 1] ?? "")) name += pattern[++i];
			keys.push(name);
			re += "([^/]+)";
		} else {
			re += c.replace(/[.+?^${}()|[\]\\]/g, "\\$&");
		}
	}
	return { re: new RegExp(`^${re}$`), keys };
}

function readRules(file) {
	try {
		return readFileSync(file, "utf8").split(/\r?\n/);
	} catch {
		return [];
	}
}

const REDIRECT_STATUS = new Set([301, 302, 303, 307, 308]);

export function parseRedirects(lines) {
	const rules = [];
	for (const raw of lines) {
		const line = raw.trim();
		if (line === "" || line.startsWith("#")) continue;
		const [from, to, code] = line.split(/\s+/);
		const status = code === undefined ? 302 : Number(code);
		if (!from?.startsWith("/") || !to || !REDIRECT_STATUS.has(status)) {
			console.error(`static-server: _redirects: ignored "${line}" — /from /to [301|302|303|307|308]`);
			continue;
		}
		rules.push({ ...compilePattern(from), to, status });
	}
	return rules;
}

export function parseHeaders(lines) {
	const rules = [];
	let current = null;
	for (const raw of lines) {
		if (raw.trim() === "" || raw.trim().startsWith("#")) continue;
		if (!/^\s/.test(raw)) {
			current = { ...compilePattern(raw.trim()), headers: [] };
			rules.push(current);
			continue;
		}
		const m = raw.trim().match(/^([A-Za-z0-9-]+):\s*(.*)$/);
		if (!current || !m) {
			console.error(`static-server: _headers: ignored "${raw.trim()}" — a path line, then indented "Name: value" lines`);
			continue;
		}
		current.headers.push([m[1], m[2]]);
	}
	return rules;
}

function fill(to, keys, match) {
	let out = to;
	keys.forEach((k, i) => {
		out = out.replaceAll(`:${k}`, match[i + 1] ?? "");
	});
	return out;
}

export function createStaticServer({ root, spa = true }) {
	root = resolve(root);
	const redirects = parseRedirects(readRules(join(root, "_redirects")));
	const headerRules = parseHeaders(readRules(join(root, "_headers")));

	// _headers — 맞는 블록을 모두, 같은 이름은 뒤가 이긴다 (대소문자를 가리지 않고)
	function withRules(urlPath, headers) {
		for (const rule of headerRules) {
			if (!rule.re.test(urlPath)) continue;
			for (const [name, value] of rule.headers) {
				for (const k of Object.keys(headers)) if (k.toLowerCase() === name.toLowerCase()) delete headers[k];
				headers[name] = value;
			}
		}
		return headers;
	}

	// 요청 경로 → root 안의 파일 경로. root를 벗어나거나 점 파일이면 null
	function toFile(urlPath) {
		let path;
		try {
			path = decodeURIComponent(urlPath);
		} catch {
			return null;
		}
		if (path.includes("\0")) return null;
		const segments = path.split("/").filter(Boolean);
		// .env · .git 같은 것을 내주지 않는다 (.well-known은 인증서 · 앱 연결에 쓰인다)
		if (segments.some((s) => s.startsWith(".") && s !== ".well-known")) return null;
		// 규칙 파일은 서버의 설정이다
		if (segments.length === 1 && (segments[0] === "_redirects" || segments[0] === "_headers")) return null;
		const file = resolve(root, ...segments);
		if (file !== root && !file.startsWith(root + sep)) return null;
		return file;
	}

	async function fileStat(file) {
		try {
			const s = await stat(file);
			return s.isFile() ? s : null;
		} catch {
			return null;
		}
	}

	// 파일 → 디렉터리의 index.html → .html을 붙인 것 (/about → about.html, Docusaurus의 trailingSlash: false)
	async function lookup(file) {
		for (const candidate of [file, join(file, "index.html"), file + ".html"]) {
			const s = await fileStat(candidate);
			if (s) return { file: candidate, stat: s };
		}
		return null;
	}

	function send(req, res, status, found, cacheControl, urlPath) {
		const { file, stat: s } = found;
		const etag = `W/"${s.size.toString(16)}-${Math.floor(s.mtimeMs).toString(16)}"`;
		const headers = withRules(urlPath, {
			"Content-Type": TYPES[extname(file).toLowerCase()] ?? "application/octet-stream",
			"Cache-Control": cacheControl,
			ETag: etag,
			"Last-Modified": s.mtime.toUTCString(),
			"X-Content-Type-Options": "nosniff",
		});
		if (status === 200 && req.headers["if-none-match"] === etag) {
			res.writeHead(304, headers);
			res.end();
			return;
		}
		headers["Content-Length"] = s.size;
		res.writeHead(status, headers);
		if (req.method === "HEAD") {
			res.end();
			return;
		}
		createReadStream(file)
			.on("error", () => res.destroy())
			.pipe(res);
	}

	function cacheFor(file) {
		if (file.endsWith(".html")) return "no-cache";
		if (HASHED.test(file)) return "public, max-age=31536000, immutable";
		return "public, max-age=3600";
	}

	async function notFound(req, res, urlPath) {
		const page = await lookup(join(root, "404.html"));
		if (page) {
			send(req, res, 404, page, "no-cache", urlPath);
			return;
		}
		res.writeHead(404, withRules(urlPath, { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-cache" }));
		res.end(req.method === "HEAD" ? undefined : "not found\n");
	}

	return createServer(async (req, res) => {
		try {
			if (req.method !== "GET" && req.method !== "HEAD") {
				res.writeHead(405, { Allow: "GET, HEAD", "Content-Type": "text/plain; charset=utf-8" });
				res.end("method not allowed\n");
				return;
			}
			const [urlPath, query] = (req.url ?? "/").split("#")[0].split("?");
			for (const rule of redirects) {
				const m = urlPath.match(rule.re);
				if (!m) continue;
				let location = fill(rule.to, rule.keys, m);
				// 질의 문자열은 따라간다 — to에 이미 있으면 그것을
				if (query !== undefined && !location.includes("?")) location += `?${query}`;
				res.writeHead(rule.status, withRules(urlPath, { Location: location, "Cache-Control": "no-cache" }));
				res.end();
				return;
			}
			const file = toFile(urlPath);
			if (file === null) {
				await notFound(req, res, urlPath);
				return;
			}
			const found = await lookup(file);
			if (found) {
				send(req, res, 200, found, cacheFor(found.file), urlPath);
				return;
			}
			// 확장자가 없는 경로는 페이지다 — 클라이언트 라우터에 맡긴다. /assets/x.js 같은 파일은 없으면 404
			// (index.html을 JS로 내주면 브라우저가 알아보기 힘든 오류를 낸다)
			if (spa && extname(urlPath) === "") {
				const index = await lookup(join(root, "index.html"));
				if (index) {
					send(req, res, 200, index, "no-cache", urlPath);
					return;
				}
			}
			await notFound(req, res, urlPath);
		} catch (err) {
			console.error(`static-server: ${req.method} ${req.url}: ${err?.stack ?? err}`);
			if (!res.headersSent) res.writeHead(500, { "Content-Type": "text/plain; charset=utf-8" });
			res.end();
		}
	});
}

// `node server.mjs`로 돌 때만 듣는다 (테스트는 createStaticServer를 import한다)
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
	const port = Number(process.env.PORT);
	if (!Number.isInteger(port) || port <= 0) {
		console.error("static-server: PORT is required (the manifest [server] port)");
		process.exit(78);
	}
	const host = process.env.HOSTNAME || "127.0.0.1";
	const root = process.env.SITE_DIR || fileURLToPath(new URL("./site/", import.meta.url));
	const spa = process.env.SPA !== "0";
	const server = createStaticServer({ root, spa });
	server.listen(port, host, () => {
		console.log(`static-server: ${root} on http://${host}:${port} (spa ${spa ? "on" : "off"})`);
	});
	// Nimwake는 유휴 앱을 SIGTERM으로 내린다 — 열린 연결을 기다리지 않고 바로 끝낸다
	for (const signal of ["SIGTERM", "SIGINT"]) {
		process.on(signal, () => {
			server.close();
			server.closeAllConnections?.();
			process.exit(0);
		});
	}
}
