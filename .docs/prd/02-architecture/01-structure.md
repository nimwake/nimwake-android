# 전체 구조와 Host Supervisor

> **Nimwake Android PRD** › 아키텍처
>
> 원문 구간: `PRD.md` §6–§9

---

## 6. 전체 구조

```text
┌───────────────────────────────┐
│          Android OS           │
│                               │
│ Battery Manager               │
│ Wi-Fi                         │
│ Storage                       │
│ Boot Events                   │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│            Termux             │
│                               │
│ host supervisor               │
│ wake lock                     │
│ boot launcher                 │
│ host health                   │
│ network check                 │
│ log rotate                    │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│       Ubuntu proot            │
│                               │
│ nimwaked                      │
│ apps                          │
│ optional ingress              │
└───────────────────────────────┘
```

---

## 7. Host Layer 구성 요소

### 7.1 Boot Launcher

역할:

- Android 부팅 후 Termux 환경 복구
- Wake Lock 획득
- Ubuntu proot 실행
- Host Supervisor 실행
- Nimwake daemon 실행

권장 구조:

```text
Android Boot
   ↓
Termux:Boot
   ↓
host-start.sh
   ↓
termux-wake-lock
   ↓
proot-distro login ubuntu
   ↓
nimwaked
```

---

## 8. Host Supervisor

Android Host Layer의 핵심 상주 프로세스.

가능하면 매우 가볍게 구현한다.

MVP에서는 shell script 또는 소형 Rust binary로 시작할 수 있다.

역할:

```text
Host Supervisor
├── nimwaked health check
├── proot health check
├── network check
├── disk check
├── restart policy
└── host event logging
```

장기적으로 Rust binary `nimwake-hostd`로 구현 가능하다.

---

## 9. 프로세스 계층

```text
Termux
│
├── nimwake-hostd
│
└── Ubuntu proot
    │
    ├── nimwaked
    ├── application processes
    └── optional integrations
```

중요 원칙:

- `nimwake-hostd`는 Android/Termux 레이어에 존재
- `nimwaked`는 Ubuntu/Linux 레이어에 존재
- 두 프로세스의 책임을 섞지 않는다.

---

← [설계 원칙 · 목표 · Non-Goals](../01-product/02-principles-and-goals.md) · [PRD 인덱스](../README.md) · [Boot Recovery · Wake Lock · Battery Optimization](02-boot-and-power.md) →
