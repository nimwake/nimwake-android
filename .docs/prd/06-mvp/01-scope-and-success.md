# MVP Scope와 성공 기준

> **Nimwake Android PRD** › MVP
>
> 원문 구간: `PRD.md` §43–§44

---

## 43. MVP Scope

### Phase 0 — Manual Baseline

- Termux
- Ubuntu proot
- Nimwake 수동 실행
- SSH 접근
- 기본 서비스 검증

### Phase 1 — Boot Layer

- Termux:Boot
- host-start script
- wake lock
- proot automatic startup
- Nimwake automatic startup

### Phase 2 — Health / Recovery

- Nimwake health check
- restart policy
- exponential backoff
- recovery logs

### Phase 3 — Network / Storage

- network state
- storage threshold
- release cleanup hook
- log rotation

### Phase 4 — Host CLI

- status
- logs
- doctor
- restart
- storage
- network

### Phase 5 — Optional Integrations

- Tailscale profile
- Cloudflare Tunnel profile
- Caddy guide

### Phase 6 — Hardening

- binary rollback
- upgrade flow
- backup
- thermal monitoring
- long-running soak test

---

## 44. 성공 기준

초기 Android 머신에서 다음이 만족되면 MVP 성공으로 본다.

1. Android 재부팅 후 수동 SSH 없이 Nimwake가 복구된다.
2. 24시간 이상 안정적으로 Nimwake daemon이 동작한다.
3. Wi-Fi 재연결 후 서비스가 자동 복구된다.
4. Nimwake crash 후 자동 재시작된다.
5. 앱들은 reboot 후 기본적으로 sleeping 상태를 유지한다.
6. 저장공간 부족 상태를 사전에 감지한다.
7. Host Layer가 Nimwake Core의 Android-specific 코드 추가 없이 동작한다.
8. Host Layer를 제거해도 Nimwake Core는 일반 Linux에서 그대로 동작한다.

---

← [Security와 Backup](../05-profiles/02-security-and-backup.md) · [PRD 인덱스](../README.md) · [권장 운영 구성과 제품 경계](02-operating-setup-and-boundary.md) →
