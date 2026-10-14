# 04. 공개 노출의 보안 — 공개 앱과 LAN 전용 앱, 그리고 계층별 방어

> **Phase 2** › 노출 보안
>
> 요구사항 원장: [PRD §40 Security](../../prd/05-profiles/02-security-and-backup.md) · Core PRD §61("ingress security는 ingress 구현의 책임") · §81.
> 앞선 문서: [02. Ingress](02-ingress.md) · [03. 배포 · ingress 계약](03-deploy-and-ingress-contract.md)

---

## 한 폰에 공개 앱과 LAN 전용 앱 — 어떻게 갈리는가

둘 다 **같은 gateway(:8080)**를 쓰고 **Host로** 갈린다.

```text
                     ┌─ blog.example.com  → 공개 앱
인터넷 → Cloudflare ─┘   Cloudflare에 등록한 이름만 터널로 들어온다
                                   ▼
                        폰 gateway :8080 ── Host로 앱을 고른다
                                   ▲
같은 Wi-Fi ────────────────────────┘   두 이름 모두 닿는다
```

| | 공개 앱 | LAN 전용 앱 |
| - | ------- | ----------- |
| manifest `host` | 공개 도메인 (`blog.example.com`) | 내부 이름 (`notes.home.arpa` — RFC 8375 가정용 이름) |
| Cloudflare Public Hostname | 등록 | **등록하지 않는다** |
| 인터넷에서 | 닿는다 | 닿지 않는다 — 터널은 등록된 이름만 보낸다 |
| 같은 Wi-Fi에서 | 닿는다 | 닿는다 (hosts 파일 · 공유기 DNS) |
| gateway | `NIMWAKE_LISTEN=0.0.0.0:8080`이 필요하다 — LAN 앱에 닿을 길 | |

**LAN 앱이 있으면 gateway를 loopback으로 닫지 않는다.** 닫으면 LAN 앱에 닿을 길이 없다. 공개 앱만 있을 때만 닫는다.

---

## 위협 — 무엇이 바뀌었나

ingress를 켜면 **인터넷의 아무나** 폰의 gateway에 HTTP를 보낼 수 있다. 확인한 위협 (10-14, 기기에서):

| # | 위협 | 지금 | 근거 |
| - | ---- | ---- | ---- |
| **T1** | **공개 앱 하나가 뚫리면 폰 전체가 넘어간다** | proot는 보안 경계가 아니다. 앱(proot의 `nimwake` 사용자)은 실제로 Termux와 **같은 Android uid**다. 앱에서 `~/.ssh/authorized_keys`(SSH 키 추가 → LAN에서 SSH), `~/.termux/boot/`(부팅 때 실행 → 상주), `$PREFIX/etc/ssh`(sshd 호스트 키 6개), `host.conf`를 **읽고 쓸 수 있다** — 기기에서 확인 | Next.js 같은 프레임워크의 원격 코드 실행 취약점은 드물지 않다 |
| **T2** | **LAN 전용 앱이 인터넷에 열린다** | 막는 것은 "Cloudflare에 그 이름이 없다"뿐이다. 와일드카드(`*.example.com`) · Host 재작성 · catch-all을 쓰면 LAN 앱도 열린다. Core는 앱별 접근 제어가 없다 (§61 범위 밖) | 설정 실수 하나 |
| **T3** | 터널 토큰 유출 | 토큰이 있으면 누구나 커넥터를 띄워 **내 hostname의 트래픽을 받는다**. 폰 자체에 들어오는 것은 아니다. 토큰은 T1로 읽힌다 | |
| **T4** | 깨우기 남용 | 인터넷에서 앱을 계속 깨워 메모리 · 배터리를 쓴다. §78 입장 제어 · §80 eviction이 메모리는 지킨다(14). 요청 수 제한은 없다 | |
| **T5** | 느린 · 큰 요청 | gateway에 요청 본문 크기 상한이 없다 (Core 소스 확인). 응답 header 대기는 §75로 제한된다 | |
| **T6** | `X-Forwarded-For` 위조 | 왼쪽 값은 클라이언트가 쓸 수 있다 — 읽는 법이 [02](02-ingress.md)에 있다 | |
| **T7** | LAN 무인증 | 같은 Wi-Fi의 누구나 모든 앱에 닿는다 (집이면 보통 괜찮다) | |

---

## 계층별 방어

### Cloudflare (소비처가 설정)

- Public Hostname은 **공개할 이름을 하나씩**. 와일드카드 · Host 재작성 · `http_status:404`가 아닌 catch-all 금지 — T2
- 외부에서 쓰되 나만 쓸 앱은 **Cloudflare Access**(로그인)를 앞에 — T2 · T4
- WAF · Rate Limiting 규칙 — T4 · T5
- 토큰은 레포 밖, `chmod 600`. 유출되면 대시보드에서 터널 토큰을 갱신한다 — T3

### Android Host Layer (이 레포) — 구현은 [PR B](#남은-것)

| 방어 | 막는 것 |
| ---- | ------- |
| **daemon을 `proot-distro --isolated`로** — Termux 파일 시스템을 guest에 붙이지 않는다. 기기에서 확인: 위 파일들이 모두 보이지 않고, Node · nimwaked는 그대로 돈다(별도 포트의 격리 daemon으로 health · cold start · idle 정지 확인) | **T1의 대부분** — 앱이 SSH 키 · 부팅 스크립트 · 토큰을 볼 수 없다. 단 proot는 ptrace 기반이라 **보안 sandbox가 아니다** — 탈출 취약점이 있으면 여전히 넘어간다. root 없는 Android에서 이보다 강한 격리는 없다 |
| **노출 선언** — 앱마다 `exposure`(`public` · `lan`, 기본 `lan`). ingress provider는 `public`만 받는다. `make apps` · doctor가 보인다 | T2를 **눈에 보이게** — 무엇이 공개될 의도인지 기록. 강제는 Core가 한다(아래) |
| ingress가 켜졌는데 격리가 꺼져 있으면 doctor 경고 | T1 |
| 비밀은 `secrets/`(0700 · 0600), 토큰은 환경으로(명령줄 X), SSH는 키만 · 공개 금지 | T3 · PRD §40 |

### Core (요청 — nimwake 레포의 이슈)

**gateway가 앱별로 접속 peer를 제한한다** — 예: `[server] allow = ["192.168.0.0/16"]`.

```text
터널로 온 요청      peer = 127.0.0.1 (cloudflared)
LAN에서 온 요청     peer = 192.168.x.x
→ LAN 전용 앱이 LAN 대역만 허용하면, Cloudflare 설정이 틀려도 터널 요청은 403
```

provider를 모르는 일반 기능이다 (Core Rule 6 · 7과 맞는다) — 판단 근거는 gateway가 **직접 관측한** peer뿐이다(§81의 맨 오른쪽과 같은 값). 이것이 T2를 **설정이 아니라 코드로** 막는 유일한 자리다.
함께 요청: 요청 본문 크기 상한 · 요청 header 읽기 제한 시간 (T5).

---

## 남은 것

| | |
| - | - |
| PR B | `--isolated` 기본 · `exposure` 선언 · doctor — 기기 반영은 블로그 soak 뒤 (`make restart`가 필요) |
| Core 이슈 | 앱별 peer 제한 · 요청 크기 · header 제한 시간 |
| 기기 검증 (PR 5) | 등록하지 않은 이름이 터널로 들어오지 않는가 · 격리된 운영 daemon |

---

← [03. 배포 · ingress 계약](03-deploy-and-ingress-contract.md) · [Phase 2](README.md)
