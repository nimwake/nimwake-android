# 03. 배포 계약과 ingress provider 계약 — 소비처가 이 레포로 폰에 배포한다

> **Phase 2** › 배포 · ingress 계약
>
> 요구사항 원장: [PRD §15 Optional Network Integrations](../../prd/02-architecture/03-network.md) ·
> [§19 Release Cleanup](../../prd/03-operations/01-storage-and-logs.md) · [§31 Rollback](../../prd/04-delivery/01-build-and-update.md) ·
> [§37–§39 프로필](../../prd/05-profiles/01-network-profiles.md) · [§40 Security](../../prd/05-profiles/02-security-and-backup.md).
> Core 쪽: §21 manifest · §61 "ingress security는 ingress 구현의 책임" · §76 `SIGHUP` 재적재 · §81 `X-Forwarded-For`.
> 앞선 결정: [02. Ingress](02-ingress.md) (Tailscale은 사설, 공개는 Cloudflare Tunnel)

---

## 경계 — 누가 무엇을 아는가

```text
nimwake (Core)          lifecycle · gateway · Host 라우팅 · §76 재적재 · §81 XFF
                        Android도, 도메인도, Cloudflare도 모른다 (Core Rule 6 · 7)
                              ▲ 프로세스 · 신호 · manifest 디렉터리 (Core §74)
nimwake-android (이 레포)  설치 · 부팅 · supervisor · 감시
                        + 앱 배포 계약 (deploy-app)        ← 소비처가 부른다
                        + ingress provider 계약 (플러그인)  ← cloudflare · 이후 다른 것
                        도메인 · 토큰 · 실제 앱은 모른다
                              ▲ make deploy-app APP=… · host.conf · secrets/
소비처 (개인 레포, 비공개)  실제 앱(Next.js 등) · 공개 hostname · Cloudflare 계정 · 토큰
                        이 레포를 버전으로 고정해 쓴다
```

**Core에 새로 필요한 것은 없다.** Host 라우팅 · `--listen` · §76 · §81이 이미 있다.

---

## 1. 앱 배포 계약

### 소비처가 넘기는 것

```text
<app>/
├── nimwake.toml      Core §21 manifest — 단, working_dir은 쓰지 않는다 (배포가 채운다)
├── bundle/           실행에 필요한 전부. 폰에서 빌드하지 않는다 (npm install · next build 금지)
└── exposure          public | lan — 없으면 lan. ingress provider는 public 앱의 host만 받는다 (04)
```

`exposure`를 `nimwake.toml`에 넣지 않는 이유: Core manifest는 모르는 키를 거부한다(`deny_unknown_fields`). 노출은 Host Layer의 관심사다.

| manifest 항목 | 규칙 |
| ------------- | ---- |
| `name` | 앱 식별자. 폰의 경로 이름이 된다 |
| `[server] host` | **공개 hostname 그대로** (예: `blog.example.com`). Core는 Host로 라우팅하고, ingress provider는 이 이름들을 gateway로 보낸다 — Host를 바꿔 쓸 필요가 없다 |
| `[server] port` | 폰 안에서 유일해야 한다 (Core §21 검증) |
| `[runtime] command` | 이 레포가 제공하는 런타임만: `/opt/node/bin/node`(`guest/node.lock`). 다른 런타임은 같은 방식으로 늘린다 |
| `[runtime] working_dir` | **쓰지 않는다** — 쓰면 거부한다. 배포가 release 디렉터리로 채운다 (아래) |
| `[runtime.env]` | 앱은 `HOSTNAME=127.0.0.1` 등으로 **loopback에만** 연다 (Core §61) |

### 배포 — `make deploy-app APP=<dir>`

```text
1. 검사      manifest 필수 항목 · working_dir 없음 · bundle/ 있음 · command의 런타임이 있음
2. 올린다    bundle → /home/nimwake/apps/<name>/releases/<id>     (id = UTC 시각 + 묶음 해시)
3. manifest  working_dir = 그 release로 채워 ~/.nimwake/apps/<name>/nimwake.toml에
4. 재적재    nimwaked에 SIGHUP (Core §76) — 다른 앱은 건드리지 않는다
5. 확인      재적재 결과를 로그에서 본다. 실패하면 이전 manifest로 되돌리고 다시 SIGHUP
6. 정리      release는 최근 3개만 — 현재와 직전(롤백 대상)은 지우지 않는다 (PRD §19)
```

**release 디렉터리를 새로 만드는 이유:** Core §76은 spec이 같은 앱을 건드리지 않는다. 같은 경로에 파일만 바꾸면 **떠 있는 앱은 옛 코드로 계속 돈다.** `working_dir`이 바뀌면 Core가 "바뀐 앱"으로 보고 정지시키고, 다음 요청이 새 코드로 cold start한다.

| 명령 | |
| ---- | - |
| `make deploy-app APP=<dir>` | 위 순서 |
| `make rollback-app NAME=<name>` | 직전 release로 manifest를 되돌리고 SIGHUP (PRD §31) |
| `make remove-app NAME=<name>` | manifest를 빼고 SIGHUP — Core가 정지시키고 라우팅에서 뺀다. 마지막 앱이면 Core가 거부한다(§76) |
| `make apps` | 폰의 앱 · 현재 release · 상태(SIGUSR1 스냅샷, §79) |

`SIGHUP`은 drain하지 않는다(Core §76) — 바뀐 앱에 응답 중이던 요청은 끊긴다. 배포는 운영자의 의도된 행위로 본다.

**지금의 `guest/apps/`는 이 레포의 검증용 앱(echo · 예시 blog)으로 남는다.** 소비처 앱은 `deploy-app`만 쓴다 — `make deploy`(Host Layer 배포)와 섞이지 않는다.

---

## 2. ingress provider 계약

### 모양

```text
host/ingress/<provider>/
├── check      필요한 것이 있는가 — 바이너리 · 설정 · 비밀. 없으면 무엇이 없는지 한 줄로, 0이 아닌 코드
├── install    필요한 것을 설치한다 (멱등) — make install INGRESS=<provider>가 부른다
├── run        포그라운드로 돈다. 끝나면 supervisor가 재기동 (backoff · crash loop, PRD §23–§24)
│              종료 코드 78 = 설정 오류 → 재기동하지 않는다 (nimwaked와 같은 규칙, Core §74)
└── health     지금 연결돼 있는가 — 0이면 연결됨. supervisor가 주기적으로 부른다
```

### provider가 받는 것 (환경 변수)

| 이름 | 값 |
| ---- | -- |
| `NIMWAKE_GATEWAY` | `http://127.0.0.1:8080` — 보낼 곳 |
| `NIMWAKE_INGRESS_HOSTS` | manifest들의 `[server] host` (공백 구분) — 공개할 이름 |
| `NIMWAKE_SECRETS` | `~/.nimwake-host/secrets/` (0700, 파일 0600) — 토큰은 여기에만. 레포 · 로그에 남기지 않는다 (PRD §40) |
| `NIMWAKE_INGRESS_*` | provider별 설정 (`host.conf`) |

### provider가 지킬 것 — 이것이 계약의 전부다

1. `NIMWAKE_INGRESS_HOSTS`로 들어온 HTTP를 `NIMWAKE_GATEWAY`로 **Host를 그대로** 보낸다
2. gateway 말고 다른 것을 공개하지 않는다 (SSH 공개 금지, PRD §40)
3. 클라이언트 주소는 `X-Forwarded-For`에 넣는다 — gateway가 자기가 본 peer(127.0.0.1)를 뒤에 붙인다 (Core §81). 앱이 읽는 법은 [02](02-ingress.md#x-forwarded-for를-app이-어떻게-읽어야-하나-core-prd-81)
4. 비밀을 로그에 남기지 않는다

### 켜기

```text
host.conf   NIMWAKE_INGRESS=cloudflare          (비우면 없음 — 지금처럼 LAN만)
            NIMWAKE_LISTEN=                      (공개 앱만 있으면 비워 gateway를 loopback으로 닫는다. LAN 전용 앱이 있으면 0.0.0.0 유지 — 04)
secrets/    cloudflare.token
```

- supervisor가 nimwaked와 **따로** 감시한다 — ingress가 죽어도 daemon은 그대로, daemon이 재기동돼도 ingress는 그대로
- 네트워크가 돌아올 때(`RECOVERING`, #31) ingress를 다시 붙인다 — `NIMWAKE_NET_ON_RECOVER`를 provider가 채운다
- `nimwake-host status` · `make doctor`에 `ingress` 줄 (`health` 결과)

### 첫 provider — `cloudflare`

| 방식 | 언제 | 설정 |
| ---- | ---- | ---- |
| **token** (remote-managed tunnel) | 실사용 | Cloudflare 대시보드에서 Public Hostname → `http://localhost:8080`. 폰에는 토큰만 (`cloudflared tunnel run --token`) |
| **quick** (`trycloudflare.com`) | 계정 없이 시험 | 무작위 hostname이라 manifest의 host와 다르다 → `--http-host-header <manifest host>`로 Host를 맞춘다. 앱 하나만 |

- `cloudflared`는 Termux 패키지로 있다 (2026.10.0, 10-14 확인) — `install`은 `pkg install cloudflared`
- 기기에서 확인할 것: Host가 그대로 오는가 · XFF · 끊김 복구 · 배터리 · 데이터 (I2)

### 다음 provider (계약만 맞추면 된다)

| provider | 공개 범위 | 메모 |
| -------- | --------- | ---- |
| `tailscale-funnel` | 공개 (`*.ts.net`) | 도메인 없이 고정 HTTPS |
| `tailscale` | 사설 (tailnet) | 공개가 아닌 관리용 — [02](02-ingress.md) |
| `caddy` | 공개 | root 없이 80 · 443 불가 + 포트 포워딩 — 하지 않는다 ([02](02-ingress.md)) |

---

## 3. 소비처 템플릿 — 이 레포가 예시로 준다

```text
examples/consumer-template/        → 소비처가 복사해 개인 레포를 시작한다
├── nimwake-android.lock           이 레포의 버전 고정 (core.lock과 같은 모양)
├── apps/blog/nimwake.toml         host = "blog.example.com" (자리표시자)
├── apps/blog/                     Next.js 앱 (examples/blog와 같은 구성)
├── .env.example                   NIMWAKE_DEVICE · CLOUDFLARE_TUNNEL_TOKEN=… (실제 값은 넣지 않는다)
└── Makefile                       build → nimwake-android의 deploy-app · 토큰을 secrets/로
```

`examples/blog/DEPLOY.md` — Cloudflare로 공개하는 순서 (도메인 연결 → 터널 → Public Hostname → 토큰 → `make install INGRESS=cloudflare` → `make deploy-app`).

---

## PR 순서

| # | 내용 | 기기 |
| - | ---- | ---- |
| 1 | 이 문서 | — |
| 2 | `deploy-app` · `rollback-app` · `remove-app` · `apps` + SIGHUP 재적재 확인 | 블로그 soak 뒤 (재적재가 soak 대상 앱을 건드린다) |
| 3 | ingress 플러그인 틀 + `cloudflare` provider · supervisor 감시 · status/doctor | 코드는 지금, 기기는 soak 뒤 |
| 4 | `examples/blog/DEPLOY.md` · `examples/consumer-template/` | — |
| 5 | 기기 — quick tunnel로 공개 URL · Host · XFF · 끊김 복구, gateway loopback | soak 뒤 |

---

← [02. Ingress](02-ingress.md) · [Phase 2](README.md)
