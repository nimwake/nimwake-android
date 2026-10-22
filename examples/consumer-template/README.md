# 개인 레포 템플릿 — 내 앱을 Android 폰 서버에, Cloudflare로 공개

이 디렉터리를 통째로 복사해 **개인 레포**(비공개 권장)를 시작한다. 폰을 다루는 일은 모두 [nimwake-android](https://github.com/nimwake/nimwake-android)가 하고, 이 레포는 **내 앱과 내 도메인**만 갖는다.

```text
nimwake-android  설치 · 부팅 · supervisor · 감시 · 앱 배포(deploy-app) · ingress(cloudflare)
이 레포          apps/<앱>/ (Next.js · 정적 사이트 소스 + nimwake.toml) · 도메인 · 토큰 파일 경로(.env)
```

배포 계약: nimwake-android `.docs/phases/phase-2/03-deploy-and-ingress-contract.md`

## 구성

```text
nimwake-android.lock    쓸 nimwake-android 버전 — 태그나 commit으로 고정한다
Makefile                setup · deploy · rollback · ingress · token · restart · status
.env.example            NIMWAKE_DEVICE · CLOUDFLARE_TOKEN_FILE (토큰 자체가 아니라 파일 경로)
apps/blog/nimwake.toml  host = 공개 hostname, working_dir 없음
apps/blog/app/          Next.js 앱 (output: standalone, images.unoptimized)
apps/site/nimwake.toml  정적 사이트 — command는 server.mjs, env SPA
apps/site/app/          Vite + React + TanStack Router (빌드 결과 dist/)
```

## 처음 한 번

1. **폰 준비** — nimwake-android README대로 `make install` (Termux · Termux:Boot · 키 로그인 sshd · Ubuntu · Core).
2. **이 레포**
   ```sh
   cp .env.example .env          # NIMWAKE_DEVICE, CLOUDFLARE_TOKEN_FILE
   make setup                    # .nimwake-android/ 에 lock의 rev
   ```
3. **도메인을 Cloudflare에** — 도메인의 네임서버를 Cloudflare로 옮긴다 (Cloudflare 대시보드 → Add a site).
4. **터널** — Cloudflare Zero Trust → Networks → Tunnels → Create a tunnel (Cloudflared)
   - 토큰을 복사해 **레포 밖** 파일에 둔다: `~/.secrets/cloudflare-tunnel.token`, `chmod 600`
   - **Public Hostname:** `blog` · `example.com` → Service `HTTP` · `localhost:8080`
     (폰의 Nimwake gateway. 앱의 port가 아니다 — Nimwake가 Host로 앱을 고른다)
5. **폰에 ingress 켜기**
   ```sh
   make ingress                  # cloudflared 설치 + host.conf NIMWAKE_INGRESS=cloudflare
   make token                    # CLOUDFLARE_TOKEN_FILE → 폰 secrets/ (표준 입력으로만, 0600)
   make restart                  # supervisor가 cloudflared를 띄운다
   make status                   # ingress cloudflare RUNNING — connected
   ```
6. **앱 배포**
   - `apps/blog/nimwake.toml`의 `host`를 Public Hostname과 **같게**: `blog.example.com`
   ```sh
   make deploy APP=blog          # 빌드 → 폰 → SIGHUP 재적재 (다른 앱은 그대로)
   ```
   → `https://blog.example.com`

## 계정 없이 먼저 시험 — quick tunnel

```sh
make ingress MODE=quick && make restart && make status
# ingress cloudflare RUNNING — connected https://<무작위>.trycloudflare.com
```

토큰도 도메인도 없이 공개 URL이 생긴다. 다시 뜰 때마다 URL이 바뀌고, Host는 manifest의 첫 host로 맞춰 보낸다 (앱 하나).

## 매일

```sh
make deploy APP=blog       # 새 release. 다음 요청부터 새 코드 (Core가 바뀐 앱만 내린다)
make rollback APP=blog     # 직전 release로
make status
```

## 정적 빌드 사이트 — Vite · Vite + TanStack Router · Docusaurus

`next.config.*`가 없는 앱은 **정적 사이트**로 묶인다. `make deploy APP=site`가 `npm run build`의 결과(`dist/` · `build/` · `out/` 중 `index.html`이 있는 곳, 또는 `STATIC_DIR=…`)를 `bundle/site/`에, nimwake-android의 정적 서버(`runtime/static-server.mjs`, Node 내장 모듈만)를 `bundle/server.mjs`로 넣는다. 폰에서는 Nimwake가 그 서버를 깨우고 재운다.

새 정적 사이트는 `apps/site`를 복사해 시작한다:

1. `apps/<이름>/app/`에 프로젝트 — `package.json`의 `build`가 정적 파일을 낸다. **`package-lock.json`을 커밋한다** (빌드는 `npm ci`)
2. `apps/<이름>/nimwake.toml` — `name` · `host` · `port`(앱마다 다르게) · `PORT`를 바꾼다. `command`는 그대로 `server.mjs`
3. `SPA` — 클라이언트 라우터(TanStack Router · React Router)면 `"1"`: 없는 경로에 `index.html`을 줘 새로고침 · 직접 링크가 열린다. 페이지마다 HTML이 있는 사이트(Docusaurus · Astro 정적)면 `"0"`: 없는 경로는 `404.html`
4. `apps/<이름>/exposure` — `public` 또는 `lan`
5. `make deploy APP=<이름>`

| | 동작 |
| - | - |
| `/about` 같은 경로 | 파일 → `about/index.html` → `about.html` → (SPA면) `index.html` |
| 해시가 붙은 파일 (`assets/index-B4x9kQ2z.js`) | `Cache-Control: immutable`, 1년 |
| HTML | `no-cache` + ETag — 배포하면 바로 새 버전 |
| 없는 `/assets/…` | 404 (SPA여도 `index.html`을 JS로 주지 않는다) |
| `.env` · `.git` 같은 점 파일, `..` | 404 (`.well-known`만 연다) |
| 압축 | 하지 않는다 — Cloudflare가 가장자리에서 한다 |

- 빌드 때 넣는 값(`VITE_*`)은 **브라우저에 그대로 보인다** — 비밀을 넣지 않는다. 개인 레포의 `.env`에 두고 빌드 환경으로 넘긴다
- `base`(Vite) · `baseUrl`(Docusaurus)은 `/` — 사이트는 자기 hostname의 루트에 선다
- 폰에서: cold start 약 1.1초, warm 40–80ms, 깨어 있을 때 약 58 MB. 정적 사이트가 여러 개여도 깨어 있는 것만 메모리를 쓴다

## 앱을 만들 때

- `next.config.mjs`의 `output: "standalone"` · `images.unoptimized: true`는 지운다면 폰에서 깨진다 — 네이티브 모듈(sharp 등)은 빌드 머신의 CPU용이다. 빌드가 네이티브 모듈을 찾으면 멈춘다
- 앱은 `HOSTNAME=127.0.0.1`로 loopback에만 연다 — 밖에서는 gateway(그리고 Cloudflare)를 거쳐서만 닿는다
- 접속자 주소는 `X-Forwarded-For` — Cloudflare가 넣은 값 뒤에 gateway가 본 `127.0.0.1`이 붙는다. **맨 오른쪽 `127.0.0.1`의 바로 왼쪽 하나**가 Cloudflare가 본 클라이언트다 (Core PRD §81, nimwake-android Phase 2 02)
- 앱은 쓰지 않으면 내려간다 (`idle_timeout_seconds`). 다음 첫 요청은 cold start — Next.js는 폰에서 약 1.6초 (nimwake-android validation/13)
- 런타임은 nimwake-android가 제공하는 Node(`guest/node.lock`)뿐이다. `package.json`의 `engines`와 맞춘다

## 보안

- 토큰은 레포에 넣지 않는다 — `.env`는 경로만, `.gitignore`에 있다
- 공개 앱만 있으면 폰의 `host.conf`에서 `NIMWAKE_LISTEN`을 비워 gateway를 loopback으로 닫는다 — LAN에 인증 없이 열려 있지 않게. LAN 전용 앱이 있으면 열어 둔다 (아래)
- Cloudflare Public Hostname은 **공개할 이름을 하나씩** — 와일드카드(`*.example.com`) · Host 재작성은 LAN 전용 앱까지 연다
- 나만 쓸 앱을 밖에서 열려면 Cloudflare Access(로그인)를 앞에. WAF · Rate Limiting 규칙도
- **공개 앱 하나가 뚫리면 폰 전체가 넘어갈 수 있다** — proot는 보안 경계가 아니다. 앱이 Termux의 SSH 키 · 부팅 스크립트를 읽고 쓸 수 있다 (nimwake-android Phase 2 04). 공개 앱의 의존성은 최신으로 유지한다

## 공개 앱과 LAN 전용 앱을 함께

한 폰에 둘 다 띄울 수 있다. 같은 gateway를 쓰고 **Host로** 갈린다.

| | 공개 앱 | LAN 전용 앱 |
| - | - | - |
| `nimwake.toml` `host` | `blog.example.com` | `notes.home.arpa` (가정용 이름, RFC 8375) |
| Cloudflare Public Hostname | 등록 | **등록하지 않는다** |
| 인터넷에서 | 닿는다 | 닿지 않는다 |
| 같은 Wi-Fi에서 | 닿는다 | 닿는다 — hosts 파일이나 공유기 DNS에 `notes.home.arpa → 폰 IP` |

- LAN 전용 앱이 있으면 폰의 gateway는 LAN에 열려 있어야 한다 (`NIMWAKE_LISTEN=0.0.0.0:8080`) — 같은 Wi-Fi의 누구나 인증 없이 닿는다
- **LAN 전용 앱에는 `allow`를 적는다** (Core `v0.1.0-rc7` 이상). 터널 요청은 폰 안의 cloudflared에서 오므로 peer가 `127.0.0.1`이다 — LAN 대역만 허용하면 Cloudflare 설정이 틀려도 터널 요청은 **403**이고 앱을 깨우지 않는다:
  ```toml
  [server]
  host  = "notes.home.arpa"
  port  = 3103
  allow = ["192.168.0.0/16"]   # 한 줄로. host bit 없이 (192.168.0.9/16은 거부된다)
  ```
  `allow`가 없으면 막는 것은 'Cloudflare에 그 이름이 없다'뿐이다 — `make deploy`가 경고한다. 공개 앱은 `allow`를 적지 않는다(적으면 `127.0.0.1/32`가 있어야 한다 — 없으면 배포가 거부한다)
- 앱마다 **`exposure` 파일**로 의도를 적는다 — `apps/<앱>/exposure`에 `public` 또는 `lan`. **없으면 `lan`**. nimwake-android가 `public` 앱의 이름만 ingress에 넘기고 `make status`에 보인다. 공개 앱인 `apps/blog`에는 `public`이 들어 있다
- nimwake-android는 daemon과 앱을 **격리 모드**(`proot-distro --isolated`)로 띄운다 — 앱이 Termux의 SSH 키 · 부팅 스크립트를 볼 수 없다. 끄지 않는다 (`NIMWAKE_ISOLATED=1`)
