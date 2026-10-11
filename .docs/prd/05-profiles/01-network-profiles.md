# Tailscale · Cloudflare Tunnel · Caddy 프로필

> **Nimwake Android PRD** › 선택 프로필과 보안
>
> 원문 구간: `PRD.md` §37–§39

---

## 37. Optional Tailscale Profile

관리용 VPN을 원하는 경우:

```text
Developer
   ↓
Tailscale
   ↓
Android
   ↓
SSH / Nimwake
```

Host Layer는 Tailscale 설치 가이드와 health hook 정도만 제공한다.

필수 dependency가 아니다.

---

## 38. Optional Cloudflare Tunnel Profile

Public service 노출 예:

```text
Internet
   ↓
Cloudflare Tunnel
   ↓
Nimwake
```

Host Layer는 tunnel process 재기동 hook을 지원할 수 있다.

Nimwake Core는 Cloudflare를 모른다.

---

## 39. Optional Caddy Profile

공인 IP와 port forwarding 환경:

```text
Internet
   ↓
Router
   ↓
Caddy
   ↓
Nimwake
```

Android에서 Caddy 운영이 적합한지는 환경별로 판단한다.

TLS termination은 Nimwake 밖에서 수행한다.

---

← [Installation Flow와 Bootstrap](../04-delivery/03-installation.md) · [PRD 인덱스](../README.md) · [Security와 Backup](02-security-and-backup.md) →
