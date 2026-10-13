# 예시 앱 — 폰 서버 블로그 (Next.js)

Nimwake가 Android 폰에서 깨워 서빙하는 **실제 앱의 예시**다 (#45). `echo` fixture(2 MB) 대신 실제 프레임워크로 cold start · 메모리 · 응답 시간을 잰다.

| | |
| - | - |
| 프레임워크 | Next.js 16.3.6 · React 19.3.0 (App Router, 추가 의존성 없음) |
| 런타임 | Node 24.21.0 (LTS) — 폰은 공식 linux-arm64 tarball, 개발 머신은 `mise` |
| 빌드 | **개발 머신에서** `output: "standalone"` → `server.js` + 필요한 `node_modules`만. 폰에서는 `npm install` · `next build`를 하지 않는다 |
| 경로 | `/` 글 목록 · `/posts/<slug>` (빌드 때 정적 생성) · `/api/whoami` (요청 header · pid · RSS) |

```sh
make app-blog          # dist/apps/blog — 폰에 놓을 standalone 묶음
```

폰에서는 Nimwake manifest(`guest/apps/blog/nimwake.toml`)가 이렇게 띄운다.

```text
working_dir  /home/nimwake/apps/blog
command      /opt/node/bin/node server.js
env          PORT=3102 · HOSTNAME=127.0.0.1 · NODE_ENV=production
```

`HOSTNAME=127.0.0.1` — app은 loopback에만 연다. 밖에서는 Nimwake gateway를 거쳐서만 닿는다 (Core PRD §61).

## 글 쓰기

`content/*.md` — 맨 위에 `title` · `date` front matter. 지원하는 문법은 `#`, `##`, `- ` 목록, ```` ``` ```` 코드 블록, 문단뿐이다 (`lib/posts.js`).
