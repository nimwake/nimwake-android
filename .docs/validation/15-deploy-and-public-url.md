# 15. 실사용 직전 — 격리된 daemon · 앱 배포 계약 · Cloudflare로 공개 URL

> **일시:** 2026-10-14 · **Core:** `v0.1.0-rc6` (`4f7d991`) · **결과:** 개인 레포의 배포 경로와 공개 URL이 기기에서 끝까지 동작한다. 그 과정에서 **버그 셋**을 찾아 고쳤다
>
> Phase 2 [03 배포 · ingress 계약](../phases/phase-2/03-deploy-and-ingress-contract.md) · [04 노출 보안](../phases/phase-2/04-exposure-security.md)의 기기 검증 (PR 5). #45 · #41.

---

## 0. 블로그 soak — 6.3h에서 멈춤

검증을 위해 멈췄다 (사용자 결정). `~/nimwake-soak-archive/soak-blog-rc6-stopped.csv`

| | |
| - | - |
| 표본 | 76 (10-14 11:11 → 17:29, 6.3h) |
| non-200 · 잔존 app · daemon 재기동 | 0 · 0 · 0 |
| cold start (blog, Next.js) | p50 1.665s · p95 1.720s · max 2.265s |
| MemAvailable | min 2694 · p50 2930 MB — 임계값 512 MB는 한참 아래 |

## 1. 격리된 운영 daemon

`make deploy` → `make restart`:

```text
launch: proot-distro login ubuntu --isolated --user nimwake -- /opt/nimwake/bin/nimwaked … --min-free-memory-mb 512
```

격리된 상태에서 blog cold 200 (1.63s, RSS 96 MB) · echo 200 (35ms) · doctor 정상. 격리하면 앱에서 Termux 파일(SSH 키 · 부팅 스크립트)이 보이지 않는다 ([04](../phases/phase-2/04-exposure-security.md) T1).

## 2. 앱 배포 계약 — 템플릿 모양의 시험 앱 `hello`

| 단계 | Core | 결과 |
| ---- | ---- | ---- |
| v1 배포 | `reloaded: +1 -0 ~0 =2` | `hello v1` |
| v2 재배포 | `~1` — 바뀐 앱만 내림 | 새 release로 cold start → `hello v2` |
| `rollback-app` | `~1` | `hello v1` |
| `working_dir`을 쓴 manifest | — | 계약 검사가 배포 전에 거부 |
| 포트 충돌(3102) | `reload rejected by validation … duplicate port 3102` | **이전 manifest로 복원**, `hello v1` 계속 서빙 |
| `remove-app` | `-1` | `hello.local` 404 |

**다른 앱은 건드리지 않는다:** blog는 위 전 과정 동안 **같은 pid 7877** — SIGHUP 재적재(Core §76)가 바뀌지 않은 앱을 그대로 둔다.

## 3. Cloudflare quick tunnel — 인터넷에서 폰으로

공개 앱 `pub`(`exposure=public`, examples/blog 묶음) + `make ingress-enable INGRESS=cloudflare MODE=quick` → `make restart`. cloudflared는 Termux 패키지(2026.10.0)로 설치됐다.

```text
ingress     cloudflare RUNNING — connected https://<무작위>.trycloudflare.com
```

개발 PC에서 **인터넷 → Cloudflare → 폰**:

| | |
| - | - |
| `/` · 글 페이지 | 200 (첫 요청 2.7s — cold start 포함) |
| 앱이 받은 Host | `pub.example.test` (quick 모드가 manifest의 host로 맞춘다) |
| `X-Forwarded-Proto` | `https` (Cloudflare) |
| `X-Forwarded-For` | `222.109.5.13, 127.0.0.1` — Cloudflare가 본 클라이언트, gateway가 본 cloudflared |
| XFF 위조 (`6.6.6.6`을 보냄) | `6.6.6.6,222.109.5.13, 127.0.0.1` — **맨 오른쪽 `127.0.0.1`의 바로 왼쪽이 실제 클라이언트**. [02](../phases/phase-2/02-ingress.md)의 읽는 법 그대로 |
| cloudflared `kill -9` | `exit 137 — restart 1 in 0s` → 1초 뒤 새 cloudflared 하나, 새 URL로 200 |

검증 뒤 원래대로: ingress 끔 · `pub` 제거 · 재시작 → cloudflared 0, 앱 blog · echo(LAN), daemon 격리.

## 4. 찾아 고친 것 — 단위 테스트가 놓쳤다

| # | 증상 | 원인 | 고침 |
| - | ---- | ---- | ---- |
| 1 | `deploy-app`이 기기에서 `6: parameter not set` | ssh는 인자를 공백으로 이어 원격 셸이 다시 나눈다 — 빈 `FORCE`가 사라져 뒤 인자가 당겨졌다. **`deploy-app`은 이 전까지 기기에서 한 번도 돈 적이 없었다** | 원격 인자를 하나씩 작은따옴표로 (`scripts/apps.sh` `shell_quote`) |
| 2 | quick 모드인데 `check`가 토큰을 찾았다 | `host.conf`는 셸 변수로만 읽힌다 — provider(별도 프로세스)가 `NIMWAKE_INGRESS_CF_MODE`를 못 받았다 | `NIMWAKE_INGRESS_*`를 provider에 내보낸다 |
| 3 | cloudflared를 죽이자 재기동한 것이 계속 `exit 1` | 2를 고치며 서브셸을 두 겹 만들었다 — 기록한 pid(11277)가 바깥 셸이고 cloudflared(11278)는 고아로 남아 metrics port를 붙잡았다. `stop`도 cloudflared를 남겼을 것이다 | `&`로 갈라진 셸에서 바로 `exec` (`ingress_exec`) — 기록한 pid = provider |

셋 다 bats에 회귀 테스트를 더했다 (2: host.conf 설정이 provider에 닿는다 · 3: 기록 pid = 실제 provider, 죽이면 교체되고 stop 뒤 고아 없음). 1은 기기에서만 재현된다 — 위 2의 검증이 그 테스트다.

## 아직 보지 못한 것

- **token 모드(내 도메인)** — Cloudflare 계정이 필요하다. 사용자가 터널을 만든 뒤: Public Hostname의 Host가 그대로 오는가, **등록하지 않은 이름(LAN 앱)은 들어오지 않는가**
- 네트워크가 끊겼다 돌아올 때 ingress 재연결(#31 RECOVERING) — 사람이 Wi-Fi를 조작해야 한다
- 실제 앱 + ingress로 72h soak (#45 4단계)
