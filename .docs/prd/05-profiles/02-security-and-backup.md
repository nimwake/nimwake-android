# Security와 Backup

> **Nimwake Android PRD** › 선택 프로필과 보안
>
> 원문 구간: `PRD.md` §40–§41

---

## 40. Security

Host Layer 기본 원칙:

- Android root 권한 불필요
- 앱 internal port는 loopback
- Nimwake admin은 Unix Socket
- SSH는 가능하면 key auth
- Public SSH exposure 금지 권장
- secret은 shared storage에 두지 않음
- `/sdcard`에 DB/secret 저장 금지 권장
- app artifact와 runtime data 분리
- Host Layer log에 secret 기록 금지

---

## 41. Backup

MVP에서는 자동 원격 backup을 필수로 하지 않는다.

백업 대상:

```text
Nimwake config
App manifests
SQLite DB
Application persistent data
Host config
```

백업 제외 가능:

```text
build artifacts
old releases
logs
```

향후 `nimwake-host backup`을 제공할 수 있다.

---

← [Tailscale · Cloudflare Tunnel · Caddy 프로필](01-network-profiles.md) · [PRD 인덱스](../README.md) · [MVP Scope와 성공 기준](../06-mvp/01-scope-and-success.md) →
