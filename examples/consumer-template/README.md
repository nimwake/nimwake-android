# 개인 레포 템플릿 — 내 앱을 Android 폰 서버에, Cloudflare로 공개

이 디렉터리를 통째로 복사해 **개인 레포**(비공개 권장)를 시작한다. 폰을 다루는 일은 모두 [nimwake-android](https://github.com/nimwake/nimwake-android)가 하고, 이 레포는 **내 앱과 내 도메인**만 갖는다.

```text
nimwake-android  설치 · 부팅 · supervisor · 감시 · 앱 배포(deploy-app) · ingress(cloudflare)
이 레포          apps/<앱>/ (Next.js 소스 + nimwake.toml) · 도메인 · 토큰 파일 경로(.env)
```

배포 계약: nimwake-android `.docs/phases/phase-2/03-deploy-and-ingress-contract.md`

## 구성

```text
nimwake-android.lock    쓸 nimwake-android 버전 — 태그나 commit으로 고정한다
Makefile                setup · deploy · rollback · ingress · token · restart · status
.env.example            NIMWAKE_DEVICE · CLOUDFLARE_TOKEN_FILE (토큰 자체가 아니라 파일 경로)
apps/blog/nimwake.toml  host = 공개 hostname, working_dir 없음
apps/blog/app/          Next.js 앱 (output: standalone, images.unoptimized)
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

## 앱을 만들 때

- `next.config.mjs`의 `output: "standalone"` · `images.unoptimized: true`는 지운다면 폰에서 깨진다 — 네이티브 모듈(sharp 등)은 빌드 머신의 CPU용이다. 빌드가 네이티브 모듈을 찾으면 멈춘다
- 앱은 `HOSTNAME=127.0.0.1`로 loopback에만 연다 — 밖에서는 gateway(그리고 Cloudflare)를 거쳐서만 닿는다
- 접속자 주소는 `X-Forwarded-For` — Cloudflare가 넣은 값 뒤에 gateway가 본 `127.0.0.1`이 붙는다. **맨 오른쪽 `127.0.0.1`의 바로 왼쪽 하나**가 Cloudflare가 본 클라이언트다 (Core PRD §81, nimwake-android Phase 2 02)
- 앱은 쓰지 않으면 내려간다 (`idle_timeout_seconds`). 다음 첫 요청은 cold start — Next.js는 폰에서 약 1.6초 (nimwake-android validation/13)
- 런타임은 nimwake-android가 제공하는 Node(`guest/node.lock`)뿐이다. `package.json`의 `engines`와 맞춘다

## 보안

- 토큰은 레포에 넣지 않는다 — `.env`는 경로만, `.gitignore`에 있다
- ingress를 켰으면 폰의 `host.conf`에서 `NIMWAKE_LISTEN`을 비워 gateway를 loopback으로 닫는 것을 권한다 — LAN에 인증 없이 열려 있지 않게
