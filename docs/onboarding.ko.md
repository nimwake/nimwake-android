# 온보딩 — 내 앱을 Android 폰에서 호스팅하기

[English](onboarding.md)

빈 폴더에서 시작해 내 사이트를 폰에서 돌리고 인터넷에서 열리게 하기까지를 안내한다. 여기서 다루는 것은 **소비처 레포**다. 내 앱과 도메인을 담는 나만의 레포(보통 비공개)로, nimwake-android를 써서 앱을 폰에 올린다.

> 이 문서는 짝으로 유지한다: `onboarding.md`(영문, 기본)와 `onboarding.ko.md`(국문)는 제목과 코드 블록이 같아야 한다. `make lint`가 이것과, 코드 블록에 나오는 `make` 대상이 실제로 있는지를 검사한다.

## 구성 요소의 관계

```text
your consumer repo      apps/<name>/ (source + nimwake.toml) · domain · token file path (.env)
  └── nimwake-android   pinned by nimwake-android.lock — install, supervisor, deploy-app, ingress
        └── phone        Termux → proot Ubuntu → nimwaked (Core) → your apps, woken on demand
              └── Cloudflare Tunnel (optional) → https://<your name>
```

- **nimwake-android**(이 레포)가 폰을 운영한다. 설치, 부팅, 감시, 배포, 앱 공개를 맡는다.
- **소비처 레포**에는 내 앱과 내 도메인만 있다. 비밀은 넣지 않는다. `.env`에는 토큰 파일의 *경로*만 적는다.
- **Core**(`nimwaked`)는 요청의 `Host` 헤더를 보고, manifest에 그 host를 적은 앱으로 보낸다. 첫 요청에 앱을 띄우고, 쓰지 않으면 내린다.

## 필요한 것

| | |
| - | - |
| 폰 | Termux, Termux:Boot, Termux:API를 **같은 출처**(F-Droid)에서 설치한 Android. `make install`로 준비한다 — [README](../README.md#기기-준비) 참고 |
| 개발 머신 | macOS 또는 Windows + WSL2(Ubuntu). `git`, `make`, `ssh`, `curl`, 그리고 [`guest/node.lock`](../guest/node.lock)의 버전과 같은 Node(예: `mise`로) |
| 도메인 | 선택. 없어도 공개 URL을 받을 수 있다(5단계의 quick tunnel) |

## 1. 폰 준비

nimwake-android를 checkout한 곳에서 한 번:

```sh
make install          # packages, proot Ubuntu, key-only sshd, Core, supervisor, doctor
make doctor           # [OK]/[WARN]/[FAIL] for the phone
make backup           # keep host.conf and soak records on this machine
```

ssh가 되기 전까지 사람이 하는 몇 단계(앱 설치, `sshd` 실행, 키 등록)는 README의 기기 준비 절에 있다.

## 2. 소비처 레포 만들기

템플릿을 복사한 뒤, 배포에 쓸 nimwake-android 버전을 고정한다:

```sh
cp -R nimwake-android/examples/consumer-template my-sites
cd my-sites
git init
cp .env.example .env  # NIMWAKE_DEVICE, CLOUDFLARE_TOKEN_FILE — never commit .env
```

`nimwake-android.lock`이 이 레포가 쓸 nimwake-android를 정한다:

```text
repo=nimwake/nimwake-android
rev=v0.1.0
```

- `rev`에는 **릴리스 태그나 commit SHA**를 적는다. 계속 움직이는 `main`은 쓰지 않는다.
- [릴리스](https://github.com/nimwake/nimwake-android/releases)에서 태그를 고르고 [CHANGELOG](../CHANGELOG.md)를 확인한다. 일부 기능은 템플릿이 고정한 것보다 새 버전이 필요하다 — [버전 노트](#버전-노트) 참고.

그 버전을 `.nimwake-android/`(git이 무시)로 받는다:

```sh
make setup
```

## 3. 앱 추가

앱 하나는 `apps/` 아래의 폴더 하나다:

```text
apps/<name>/
  nimwake.toml   Core manifest — name, host, port, command, lifecycle
  exposure       public | lan (missing means lan)
  app/           your project's source (package.json + package-lock.json)
  bundle/        build output — created by make deploy, ignored by git
```

내 앱에 맞는 예시를 골라 복사한다:

| 내 앱 | 복사할 것 | `command` | 참고 |
| ----- | --------- | --------- | ---- |
| 정적 사이트 — Vite, Vite + TanStack Router / React Router, Docusaurus | `apps/site` | `server.mjs` | 클라이언트 라우터면 `SPA = "1"`, URL마다 페이지가 있는 사이트(Docusaurus)면 `"0"` |
| Next.js | `apps/blog` | `server.js` | `next.config.mjs`에 `output: "standalone"`과 `images.unoptimized: true` |

```sh
cp -R apps/site apps/about
```

그다음 `apps/about/nimwake.toml`을 고친다:

| 항목 | 값 |
| ---- | -- |
| `name` | 폴더 이름 — 소문자, 숫자, `-` |
| `[server] host` | 공개 hostname. 방문자가 입력하는 그대로(Cloudflare에 등록하는 이름과 같게) |
| `[server] port`와 `PORT` | 다른 앱이 쓰지 않는 port, 1024–65535, 8080 제외 |
| `[server] allow` | LAN 전용 앱만: `["192.168.0.0/16"]`(내 LAN 대역, 한 줄로) |
| `working_dir` | **적지 않는다** — 배포가 채운다 |

그리고 `apps/about/exposure`: 터널로 공개하려면 `public`, 집 안에서만 쓰려면 `lan`.

배포가 대신 검사하는 규칙(`make deploy`가 폰을 건드리기 전에 거부하거나 경고한다):

- 빌드는 **개발 머신에서** 한다. 폰에서는 빌드하지 않고, 묶음에 네이티브 모듈(`*.node`)이 있으면 안 된다.
- 런타임은 `guest/node.lock`의 Node(`/opt/node/bin/node`) 하나뿐이다.
- `public` 앱의 `allow`에 `127.0.0.1`이 빠지면 안 된다. 터널 요청이 거기서 온다.
- `VITE_*` 같은 빌드 때 넣는 값은 브라우저에 그대로 보인다. 비밀을 넣지 않는다.

## 4. 배포하고 LAN에서 확인

```sh
make deploy APP=about    # build → bundle/ → phone → reload; other apps keep running
make status              # apps, Core, supervisor, ingress
```

집 안의 다른 기기에서 앱에 접속하려면, 폰의 gateway를 LAN에 한 번 연다(기본은 loopback만). 그리고 다시 띄운다:

```sh
ssh nimwake-phone 'echo NIMWAKE_LISTEN=0.0.0.0:8080 >> ~/.nimwake-host/host.conf'
make restart
curl -H 'Host: about.example.com' http://<phone IP>:8080/
```

앱이 쉬고 있다가 받는 첫 요청은 **cold start**다(기준 폰에서 정적 사이트 약 1초, Next.js 1.6초). 그 뒤로는 수십 ms다.

## 5. 공개하기

### 도메인 없이 — quick tunnel

```sh
make ingress MODE=quick
make restart
make status              # ingress cloudflare RUNNING — connected https://<random>.trycloudflare.com
```

계정도 토큰도 필요 없다. 터널이 다시 뜰 때마다 URL이 바뀌고, 공개 앱은 **하나**만 된다(첫 번째 `public` 앱, 또는 폰 `host.conf`의 `NIMWAKE_INGRESS_CF_QUICK_HOST`). 시험용이지 계속 쓰는 용도가 아니다.

### 내 도메인으로 — token 모드

1. 도메인을 Cloudflare에 추가한다(Cloudflare Registrar에서 사면 네임서버 단계가 없다).
2. Zero Trust → Networks → Tunnels → **Create a tunnel**(Cloudflared). 토큰을 레포 **밖**의 파일에 저장하고 `chmod 600`. 그 경로를 `.env`의 `CLOUDFLARE_TOKEN_FILE`에 적는다.
3. 공개 앱마다 **Public Hostname**을 추가한다 — `about.example.com` → `HTTP` `localhost:8080`. 앱 하나에 이름 하나, 와일드카드는 쓰지 않는다.
4. 폰에:

```sh
make ingress
make token               # reads the token file through stdin, stores it 0600 on the phone
make restart
make status
```

도메인 여러 개가 터널 하나, 폰 한 대를 함께 쓸 수 있다. 각각을 Public Hostname으로 추가하고 앱마다 `host`를 따로 준다.

## 6. 매일

```sh
make deploy APP=about    # ship a new release (the phone keeps the last three)
make rollback APP=about  # back to the previous release
make status
```

nimwake-android 올리기: `nimwake-android.lock`의 `rev`를 새 태그로 바꾸고 그 CHANGELOG를 읽은 뒤, 이 머신과 폰을 함께 올린다:

```sh
make setup                                   # fetch the new nimwake-android into .nimwake-android/
make -C .nimwake-android fetch-core deploy   # put its Core and Host Layer on the phone
make restart                                 # run them (apps start again on the next request)
make deploy APP=about                        # rebuild your app with the new build tools
```

## 문제 해결

| 이런 것이 보이면 | 이렇게 한다 |
| ---------------- | ----------- |
| `make deploy`가 `native module`로 멈춤 | 의존성이 컴파일된 `.node` 파일을 담고 있다 — 빼거나 순수 JS 대안을 쓴다 |
| `app-manifest: … does not include 127.0.0.1` | `allow`가 있는 `public` 앱 — `allow`를 지우거나 `"127.0.0.1/32"`를 넣는다 |
| `app-manifest: warning: … lan but has no [server] allow` | 터널이 절대 닿지 않게 `allow = ["192.168.0.0/16"]`을 넣는다 |
| `core: … keeping the current set` | Core가 manifest를 거부했다(port 중복, 잘못된 CIDR …). 배포가 이전 것으로 되돌렸다 — 메시지를 읽는다 |
| 정적 사이트에서 `/`는 되는데 `/about`이 404 | 클라이언트 라우터면 `SPA = "1"` |
| gateway가 503 | 폰 메모리가 부족하다(`NIMWAKE_MIN_FREE_MEMORY_MB`) — 깨어 있는 앱을 줄이거나 임계값을 낮춘다 |
| 며칠 켜 둔 뒤 `ssh: connect … refused` | Android가 Termux를 멈췄다. Termux를 열어 `sshd`, 그다음 `nimwake-host start` |
| quick tunnel URL이 안 열림 | 재시작마다 바뀐다 — `make status`에서 새 URL을 읽는다 |

## 버전 노트

| 기능 | nimwake-android | Core |
| ---- | --------------- | ---- |
| Next.js 앱, `make deploy`, Cloudflare ingress, `exposure` | v0.1.0 | v0.1.0 |
| `[server] allow`(다른 peer는 403, 앱을 깨우지 않음) | v0.1.0 | v0.1.0 |
| 정적 사이트(`server.mjs`, `SPA`) | v0.1.0 이후 — 다음 태그 전까지 commit `8cce97b` | v0.1.0 |
| 폰에서 `nimwake status`(Core control socket) | v0.1.0 이후 | v0.1.2 이상 — v0.1.4를 쓴다 |

## 참고

- [소비처 템플릿 README](../examples/consumer-template/README.md) — 템플릿 자체 설명
- [배포 · ingress 계약](../.docs/phases/phase-2/03-deploy-and-ingress-contract.md) · [노출 보안](../.docs/phases/phase-2/04-exposure-security.md)
- [CHANGELOG](../CHANGELOG.md) · [검증 리포트](../.docs/validation/)
