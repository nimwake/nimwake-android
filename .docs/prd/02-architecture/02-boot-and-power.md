# Boot Recovery · Wake Lock · Battery Optimization

> **Nimwake Android PRD** › 아키텍처
>
> 원문 구간: `PRD.md` §10–§12

---

## 10. Boot Recovery

Android reboot 후 다음 순서를 목표로 한다.

```text
BOOT_COMPLETED
   ↓
Termux:Boot
   ↓
Host Layer Start
   ↓
Acquire Wake Lock
   ↓
Check Storage
   ↓
Check Network
   ↓
Start Ubuntu proot
   ↓
Start Nimwake
   ↓
Health Check
   ↓
READY
```

애플리케이션은 자동으로 모두 실행하지 않는다.

Nimwake의 기본 정책을 그대로 따른다.

```text
App State after reboot:

blog       SLEEPING
api        SLEEPING
portfolio  SLEEPING
```

`always_on = true` 앱만 Nimwake가 다시 실행한다.

---

## 11. Wake Lock

Android가 CPU를 과도하게 sleep시키지 않도록 Termux Wake Lock을 사용한다.

예:

```bash
termux-wake-lock
```

종료:

```bash
termux-wake-unlock
```

Host Layer는 현재 Wake Lock 상태를 운영 로그에 기록한다.

---

## 12. Battery Optimization

설치 가이드에 반드시 포함한다.

사용자는 Android 설정에서 다음 항목을 확인해야 한다.

- Termux battery optimization 제외
- background activity 허용
- background network 허용
- manufacturer-specific battery killer 설정 비활성화

Host Layer는 이 설정을 완전히 강제할 수 없으므로 설치 시 검증 checklist를 제공한다.

---

← [전체 구조와 Host Supervisor](01-structure.md) · [PRD 인덱스](../README.md) · [Network Recovery와 Health Check](03-network.md) →
