# 02. Ingress — 집 밖에서 폰의 Nimwake에 닿기

> **Phase 2** › Ingress
>
> 요구사항 원장: [PRD §15 Optional Network Integrations](../../prd/02-architecture/03-network.md) ·
> [§37–§39 Tailscale · Cloudflare Tunnel · Caddy 프로필](../../prd/05-profiles/01-network-profiles.md) ·
> [§40 Security](../../prd/05-profiles/02-security-and-backup.md).
> Core 쪽 전제: Core PRD §61 "Ingress security는 ingress implementation의 책임", §81 `X-Forwarded-For`.
> 이슈: [#41](https://github.com/nimwake/nimwake-android/issues/41)

---

## 지금

```text
gateway       0.0.0.0:8080  (host.conf NIMWAKE_LISTEN — LAN에 열려 있다)
TLS · 인증    없다
집 밖         닿지 않는다
```

**LAN 안에서는 인증 없이 열려 있다.** 집 밖으로 넓히기 전에 이것부터 줄여야 한다 — 아래 결정의 첫 기준이다.

---

## 결정 (제안)

**1단계 Tailscale, 공개가 필요해지면 Cloudflare Tunnel을 더한다. Caddy는 하지 않는다.**

| | Tailscale | Cloudflare Tunnel | Caddy + 포트 포워딩 |
| - | --------- | ----------------- | ------------------- |
| 닿는 사람 | tailnet 기기만 | 누구나 (공개 도메인) | 누구나 |
| 인증 | **기기 인증 내장** | 없음 — Access를 따로 | 없음 |
| 공유기 · 공인 IP | 불필요 | 불필요 | **포트 포워딩 + 고정 IP/DDNS** |
| TLS | WireGuard (HTTP는 평문이지만 터널 안) | Cloudflare가 끝낸다 | Caddy가 끝낸다 |
| 외부 의존 | Tailscale 조정 서버 | Cloudflare 계정 · 도메인 | 없음 |
| Android 제약 | — | — | **root 없이 80 · 443에 bind할 수 없다** — 높은 포트로 받고 공유기가 옮겨야 한다 |

- "집 밖에서 **내가** 내 폰의 블로그를 본다"가 첫 목표면 Tailscale이 설정이 가장 적고 인증이 따라온다.
- 남에게 공개해야 할 때 Cloudflare Tunnel을 더한다 — 그때도 gateway는 loopback에 두고 `cloudflared`만 닿게 한다.
- Caddy는 Android 포트 제약과 공유기 설정이 겹친다. PRD §39도 "Android에서 적합한지는 환경별로"라고 둔다.

결정은 I0 spike(아래) 결과를 보고 확정한다.

---

## Tailscale의 두 방식 — I0에서 고른다

| | (a) Android 앱 (VpnService) | (b) Termux `tailscaled --tun=userspace-networking` |
| - | --------------------------- | -------------------------------------------------- |
| 설치 | F-Droid · Play 앱, 사람이 로그인 · VPN 허용 | Termux 패키지(있는지 **확인 필요**), CLI 로그인 URL |
| 기기 전체 | 폰 전체가 tailnet에 들어간다 (VPN 슬롯 하나 차지) | Termux 프로세스만 |
| gateway listen | tailnet 주소로 받아야 하므로 `0.0.0.0` 유지 → **LAN 노출도 그대로** | userspace가 들어온 연결을 `127.0.0.1`로 넘긴다면(**확인 필요**) **gateway를 loopback으로 되돌릴 수 있다** |
| 재부팅 · 끊김 | Android의 Always-on VPN에 맡긴다 | Termux:Boot가 띄우고 supervisor가 감시할 수 있다 (`NIMWAKE_NET_ON_RECOVER`, #31) |
| `X-Forwarded-For` 맨 오른쪽 | **클라이언트의 tailnet 주소(100.x)** — 그 자체가 기기 신원 | `127.0.0.1` — 클라이언트가 지워진다. `tailscale serve`가 header를 넣는지 **확인 필요** |

(b)가 LAN 노출을 없앨 수 있어 더 낫지만, 확인할 것이 셋이다. 안 되면 (a)로 하고 LAN 노출은 공유기 쪽(게스트망 분리 등)으로 줄인다.

---

## `X-Forwarded-For`를 app이 어떻게 읽어야 하나 (Core PRD §81)

gateway는 자기가 관측한 peer를 **맨 오른쪽에 덧붙이고** 왼쪽은 검증하지 않는다. 구성마다 믿을 수 있는 값이 다르다.

```text
Tailscale (a)       XFF: [클라이언트가 보낸 것…], 100.101.102.103
                    → 맨 오른쪽 = tailnet 기기. 믿는다

Cloudflare Tunnel   XFF: [클라이언트가 보낸 것…], 203.0.113.7, 127.0.0.1
                         (Cloudflare가 넣은 실제 클라이언트) └ gateway가 본 cloudflared
                    → gateway가 loopback에만 열려 있을 때만, 맨 오른쪽 127.0.0.1의
                      바로 왼쪽 하나(Cloudflare가 넣은 값)를 믿는다. 그 더 왼쪽은 믿지 않는다

LAN 직접 (지금)      XFF: [클라이언트가 보낸 것…], 192.168.0.9
                    → 맨 오른쪽만
```

**규칙: 맨 오른쪽은 항상 믿는다. 그 왼쪽은, 맨 오른쪽이 이 Host Layer가 띄운 프록시(loopback)이고 gateway가 다른 곳에서 닿지 않을 때 한 칸만.**
이 문단을 app 작성 안내(`guest/apps` 예시)에 옮긴다 — I2.

이 확인에는 §81이 들어간 Core가 필요하다. **rc5에는 없다** (nimwake#63, main에만). → v0.1.0 판정 뒤 `core.lock`을 올린 다음.

---

## 마일스톤

| ID | 내용 | 완료 조건 |
| -- | ---- | --------- |
| **I0** | spike — Tailscale (a) · (b)를 기기에서: Termux 패키지 유무, userspace가 inbound를 loopback으로 넘기는가, `tailscale serve` header, 재부팅 뒤 자동 연결 | 리포트 `validation/NN-i0-tailscale.md`. (a)/(b) 선택 |
| **I1** | 설치 · 설정 — `make ingress` (선택한 방식), `host.conf`, (b)면 Termux:Boot `30-tailscale` | 초기화 기기에서 `make install` 뒤 `make ingress` 한 번 |
| **I2** | 검증 — LTE의 다른 기기에서 닿는가 · XFF가 app에 어떻게 오는가(§81 Core) · 끊김 복구(#30 · #31과 묶기) · 배터리 · 발열 · 데이터 사용량 24h | 리포트. app용 XFF 안내 |
| **I3** | 공개가 필요해지면 Cloudflare Tunnel — gateway loopback, `cloudflared` 감시 | 리포트 |

**순서:** I0은 운영 daemon을 건드리지 않아 soak 뒤 아무 때나. I2의 XFF는 §81이 든 Core가 필요하다.

---

## 하지 않는 것

- Core에 ingress를 넣지 않는다 — Core PRD §61 · Rule 6 · 7. 이 레포가 설정과 감시만 한다 (PRD §15 "hook 정도")
- 인증 프록시를 직접 만들지 않는다 — Tailscale 기기 인증 또는 Cloudflare Access를 쓴다
- SSH를 공개하지 않는다 (PRD §40) — 관리는 tailnet 안에서

---

← [01. nimwake-hostd](01-nimwake-hostd.md) · [Phase 2](README.md)
