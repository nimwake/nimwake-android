# Network Recovery와 Health Check

> **Nimwake Android PRD** › 아키텍처
>
> 원문 구간: `PRD.md` §13–§15

---

## 13. Network Recovery

Wi-Fi는 장기간 연결 중 다음 문제가 발생할 수 있다.

- AP 재시작
- DHCP 갱신
- Android Wi-Fi sleep
- 인터넷 단절
- VPN/Tunnel 연결 해제

Host Layer는 네트워크 상태를 주기적으로 검사한다.

상태:

```text
ONLINE
DEGRADED
OFFLINE
RECOVERING
```

네트워크 장애 시 Nimwake 자체를 종료하지 않는다.

```text
Internet Offline
      ↓
Apps remain available locally
      ↓
Network returns
      ↓
Ingress integration reconnect
```

---

## 14. Network Health Check

검사 순서 예:

1. Local interface 존재
2. Default route 존재
3. LAN gateway 접근 가능
4. Optional external connectivity check

외부 서비스에 의존하지 않기 위해 public connectivity check는 configurable하게 둔다.

예:

```toml
[network]
check_interval_seconds = 30
internet_check = false
```

---

## 15. Optional Network Integrations

다음은 Android Host Layer의 optional integration이다.

```text
Cloudflare Tunnel
Tailscale
Reverse SSH Tunnel
Caddy
```

Host Layer는 integration process가 죽었을 때 재시작하는 hook을 제공할 수 있다.

Nimwake 자체에는 이 의존성이 없다.

---

← [Boot Recovery · Wake Lock · Battery Optimization](02-boot-and-power.md) · [PRD 인덱스](../README.md) · [proot Lifecycle과 Filesystem Layout](04-proot-and-filesystem.md) →
