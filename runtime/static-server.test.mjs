// node --test runtime/ — 정적 서버의 계약. 기기 없이 돈다 (examples.yml)
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { request } from "node:http";
import { createStaticServer } from "./static-server.mjs";

let dir;
const servers = {};

// 원시 요청 — fetch는 경로의 ..를 정규화해 버려 탈출 시도를 보낼 수 없다
function get(server, path, { method = "GET", headers = {} } = {}) {
	const { port } = server.address();
	return new Promise((resolveP, reject) => {
		const req = request({ host: "127.0.0.1", port, path, method, headers }, (res) => {
			let body = "";
			res.setEncoding("utf8");
			res.on("data", (c) => (body += c));
			res.on("end", () => resolveP({ status: res.statusCode, headers: res.headers, body }));
		});
		req.on("error", reject);
		req.end();
	});
}

function listen(opts) {
	const server = createStaticServer(opts);
	return new Promise((r) => server.listen(0, "127.0.0.1", () => r(server)));
}

before(async () => {
	dir = await mkdtemp(join(tmpdir(), "static-server-"));
	const site = join(dir, "site");
	await mkdir(join(site, "assets"), { recursive: true });
	await mkdir(join(site, "docs"), { recursive: true });
	await mkdir(join(site, ".git"), { recursive: true });
	await writeFile(join(site, "index.html"), "<p>home</p>");
	await writeFile(join(site, "assets", "index-B4x9kQ2z.js"), "console.log(1)");
	await writeFile(join(site, "robots.txt"), "User-agent: *");
	await writeFile(join(site, "docs", "index.html"), "<p>docs</p>");
	await writeFile(join(site, "about.html"), "<p>about</p>");
	await writeFile(join(site, "404.html"), "<p>missing</p>");
	await writeFile(join(site, ".env"), "SECRET=1");
	await writeFile(join(site, ".git", "config"), "[core]");
	await writeFile(join(dir, "outside.txt"), "outside");
	servers.spa = await listen({ root: site, spa: true });
	servers.mpa = await listen({ root: site, spa: false });

	// _redirects · _headers가 있는 사이트
	const ruled = join(dir, "ruled");
	await mkdir(join(ruled, "assets"), { recursive: true });
	await writeFile(join(ruled, "index.html"), "<p>ruled</p>");
	await writeFile(join(ruled, "new.html"), "<p>new</p>");
	await writeFile(join(ruled, "assets", "app-AbCd1234.js"), "1");
	await writeFile(join(ruled, "_redirects"), [
		"# comments and blank lines are fine",
		"",
		"/old /new 301",
		"/blog/* /posts/:splat 308",
		"/u/:name /users/:name",
		"/away https://example.org/x 302",
		"/broken",
		"/also-broken /x 418",
	].join("\n"));
	await writeFile(join(ruled, "_headers"), [
		"/*",
		"  X-Frame-Options: DENY",
		"  Strict-Transport-Security: max-age=31536000",
		"/assets/*",
		"  Cache-Control: public, max-age=60",
		"  X-Frame-Options: SAMEORIGIN",
	].join("\n"));
	servers.ruled = await listen({ root: ruled, spa: true });
});

after(async () => {
	for (const s of Object.values(servers)) s.close();
	await rm(dir, { recursive: true, force: true });
});

test("index and files are served with their types", async () => {
	const home = await get(servers.spa, "/");
	assert.equal(home.status, 200);
	assert.equal(home.body, "<p>home</p>");
	assert.match(home.headers["content-type"], /^text\/html/);
	const js = await get(servers.spa, "/assets/index-B4x9kQ2z.js");
	assert.equal(js.status, 200);
	assert.match(js.headers["content-type"], /^text\/javascript/);
});

test("SPA: a route without an extension falls back to index.html (client router draws it)", async () => {
	for (const path of ["/posts/42", "/settings/profile?tab=1"]) {
		const r = await get(servers.spa, path);
		assert.equal(r.status, 200, path);
		assert.equal(r.body, "<p>home</p>", path);
	}
});

test("SPA: a missing asset is 404, not index.html", async () => {
	const r = await get(servers.spa, "/assets/missing-AbCdEf12.js");
	assert.equal(r.status, 404);
	assert.equal(r.body, "<p>missing</p>");
});

test("SPA off (Docusaurus): directory index, .html-less path, and 404.html", async () => {
	assert.equal((await get(servers.mpa, "/docs/")).body, "<p>docs</p>");
	assert.equal((await get(servers.mpa, "/docs")).body, "<p>docs</p>");
	assert.equal((await get(servers.mpa, "/about")).body, "<p>about</p>");
	const missing = await get(servers.mpa, "/posts/42");
	assert.equal(missing.status, 404);
	assert.equal(missing.body, "<p>missing</p>");
});

test("hashed assets are immutable, HTML is revalidated, the rest is cached for an hour", async () => {
	assert.equal((await get(servers.spa, "/assets/index-B4x9kQ2z.js")).headers["cache-control"], "public, max-age=31536000, immutable");
	assert.equal((await get(servers.spa, "/")).headers["cache-control"], "no-cache");
	assert.equal((await get(servers.spa, "/posts/42")).headers["cache-control"], "no-cache");
	assert.equal((await get(servers.spa, "/robots.txt")).headers["cache-control"], "public, max-age=3600");
});

test("a matching ETag gets 304 without a body", async () => {
	const first = await get(servers.spa, "/");
	const again = await get(servers.spa, "/", { headers: { "If-None-Match": first.headers.etag } });
	assert.equal(again.status, 304);
	assert.equal(again.body, "");
});

test("nothing outside the site, and no dot files", async () => {
	for (const path of ["/../outside.txt", "/%2e%2e/outside.txt", "/assets/..%2f..%2foutside.txt", "/.env", "/.git/config", "/%00"]) {
		const r = await get(servers.mpa, path);
		assert.equal(r.status, 404, path);
		assert.ok(!r.body.includes("outside") && !r.body.includes("SECRET") && !r.body.includes("[core]"), path);
	}
	// SPA에서도 탈출 시도는 index.html이 아니라 404
	assert.equal((await get(servers.spa, "/.env")).status, 404);
});

test("HEAD has headers only; other methods are 405", async () => {
	const head = await get(servers.spa, "/", { method: "HEAD" });
	assert.equal(head.status, 200);
	assert.equal(head.headers["content-length"], String("<p>home</p>".length));
	assert.equal(head.body, "");
	const post = await get(servers.spa, "/", { method: "POST" });
	assert.equal(post.status, 405);
	assert.equal(post.headers.allow, "GET, HEAD");
});

test("_redirects: status, splat, placeholders, query string, other sites — first match wins", async () => {
	const old = await get(servers.ruled, "/old");
	assert.equal(old.status, 301);
	assert.equal(old.headers.location, "/new");
	const blog = await get(servers.ruled, "/blog/2026/hello?ref=x");
	assert.equal(blog.status, 308);
	assert.equal(blog.headers.location, "/posts/2026/hello?ref=x");
	const user = await get(servers.ruled, "/u/mini");
	assert.equal(user.status, 302);
	assert.equal(user.headers.location, "/users/mini");
	const away = await get(servers.ruled, "/away");
	assert.equal(away.headers.location, "https://example.org/x");
	// 잘못된 줄은 무시된다 — 그 경로는 평소대로(SPA)
	assert.equal((await get(servers.ruled, "/broken")).status, 200);
	assert.equal((await get(servers.ruled, "/also-broken")).status, 200);
});

test("_headers: every matching block applies, the later one wins, also on 404 and redirects", async () => {
	const home = await get(servers.ruled, "/");
	assert.equal(home.headers["x-frame-options"], "DENY");
	assert.equal(home.headers["strict-transport-security"], "max-age=31536000");
	const js = await get(servers.ruled, "/assets/app-AbCd1234.js");
	assert.equal(js.headers["cache-control"], "public, max-age=60");
	assert.equal(js.headers["x-frame-options"], "SAMEORIGIN");
	const missing = await get(servers.ruled, "/assets/missing-AbCd1234.js");
	assert.equal(missing.status, 404);
	assert.equal(missing.headers["x-frame-options"], "SAMEORIGIN");
	assert.equal((await get(servers.ruled, "/old")).headers["x-frame-options"], "DENY");
});

test("the rule files themselves are not served", async () => {
	for (const path of ["/_redirects", "/_headers"]) {
		const r = await get(servers.mpa, path);
		assert.equal(r.status, 404, path);
	}
	const r = await get(servers.ruled, "/_headers");
	assert.ok(!r.body.includes("X-Frame-Options"));
});
