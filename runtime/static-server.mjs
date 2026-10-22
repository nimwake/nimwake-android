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
// 압축은 하지 않는다 — Cloudflare가 가장자리에서 한다. 캐시: 해시가 붙은 파일은 1년 immutable,
// HTML은 매번 확인(no-cache + ETag → 304). 배포가 바뀌면 HTML이 새 해시 파일을 가리킨다.

import { createServer } from "node:http";
import { createReadStream } from "node:fs";
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

export function createStaticServer({ root, spa = true }) {
	root = resolve(root);

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

	function send(req, res, status, found, cacheControl) {
		const { file, stat: s } = found;
		const etag = `W/"${s.size.toString(16)}-${Math.floor(s.mtimeMs).toString(16)}"`;
		const headers = {
			"Content-Type": TYPES[extname(file).toLowerCase()] ?? "application/octet-stream",
			"Cache-Control": cacheControl,
			ETag: etag,
			"Last-Modified": s.mtime.toUTCString(),
			"X-Content-Type-Options": "nosniff",
		};
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

	async function notFound(req, res) {
		const page = await lookup(join(root, "404.html"));
		if (page) {
			send(req, res, 404, page, "no-cache");
			return;
		}
		res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-cache" });
		res.end(req.method === "HEAD" ? undefined : "not found\n");
	}

	return createServer(async (req, res) => {
		try {
			if (req.method !== "GET" && req.method !== "HEAD") {
				res.writeHead(405, { Allow: "GET, HEAD", "Content-Type": "text/plain; charset=utf-8" });
				res.end("method not allowed\n");
				return;
			}
			const urlPath = (req.url ?? "/").split("?")[0].split("#")[0];
			const file = toFile(urlPath);
			if (file === null) {
				await notFound(req, res);
				return;
			}
			const found = await lookup(file);
			if (found) {
				send(req, res, 200, found, cacheFor(found.file));
				return;
			}
			// 확장자가 없는 경로는 페이지다 — 클라이언트 라우터에 맡긴다. /assets/x.js 같은 파일은 없으면 404
			// (index.html을 JS로 내주면 브라우저가 알아보기 힘든 오류를 낸다)
			if (spa && extname(urlPath) === "") {
				const index = await lookup(join(root, "index.html"));
				if (index) {
					send(req, res, 200, index, "no-cache");
					return;
				}
			}
			await notFound(req, res);
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
