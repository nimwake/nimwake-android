# 설계 원칙 · 목표 · Non-Goals

> **Nimwake Android PRD** › 제품 정의
>
> 원문 구간: `PRD.md` §3–§5

---

## 3. 설계 원칙

### 3.1 Nimwake Core와 Android 책임 분리

Nimwake Core:

```text
HTTP Gateway
App Lifecycle
Scale-to-Zero
Scheduler
Resource Manager
Registry
```

Android Host Layer:

```text
Android Boot
Termux Lifecycle
Wake Lock
proot Lifecycle
Network Availability
Daemon Recovery
Host Health
Storage
```

Nimwake Core에 Android API나 Termux 전용 로직을 직접 넣지 않는다.

---

## 4. 목표

1. Android 재부팅 후 Nimwake를 자동 복구한다.
2. Termux가 background에서 종료되는 위험을 최소화한다.
3. Ubuntu proot 환경을 자동으로 기동한다.
4. Nimwake daemon이 죽으면 감지하고 복구한다.
5. 네트워크가 끊겼다가 돌아와도 서비스가 복구된다.
6. Android-specific 상태를 Nimwake Core와 분리한다.
7. 사용자가 SSH로 매번 수동 복구하지 않아도 된다.
8. 장기 운영 시 저장공간, 로그, 발열 문제를 관리한다.
9. Android 환경의 이상 상태를 CLI/로그에서 확인할 수 있다.
10. 다른 Android 기기로 이전하기 쉽게 구성한다.

---

## 5. Non-Goals

초기 버전에서는 다음을 목표로 하지 않는다.

- Android 커널 수정
- Root 권한 필수화
- Custom ROM
- Docker 지원
- cgroup hard isolation
- Android 앱 GUI 관리 도구
- MDM
- 배터리 보호를 위한 하드웨어 제어
- Wi-Fi router 자동 설정
- 공인 IP / DNS 자동 구성
- Cloudflare / Tailscale 필수화

---

← [문서 개요와 제품 정의](01-overview.md) · [PRD 인덱스](../README.md) · [전체 구조와 Host Supervisor](../02-architecture/01-structure.md) →
