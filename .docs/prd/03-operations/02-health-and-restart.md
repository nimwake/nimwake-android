# Health Model과 Restart Policy

> **Nimwake Android PRD** › 운영
>
> 원문 구간: `PRD.md` §21–§25

---

## 21. Health Model

Android Host 전체 상태:

```text
HEALTHY
DEGRADED
UNHEALTHY
RECOVERING
```

HEALTHY:

```text
Termux OK
Wake Lock OK
proot OK
nimwaked OK
storage OK
```

DEGRADED 예:

```text
internet offline
low storage
high temperature warning
optional tunnel unavailable
```

UNHEALTHY 예:

```text
proot launch failure
nimwaked repeated crash
storage critically low
```

---

## 22. Nimwake Health Check

Host Layer는 Nimwake Admin IPC 또는 local health endpoint를 통해 상태를 확인한다.

우선순위:

```text
Unix Socket IPC
   ↓
Fallback local health endpoint
```

단순 PID 존재만으로 healthy 판정하지 않는다.

---

## 23. Restart Policy

Nimwake daemon crash:

```text
Crash
  ↓
Restart
  ↓
Health Check
```

반복 crash 방지:

```text
1st restart   immediate
2nd restart   +5 sec
3rd restart   +15 sec
4th restart   +60 sec
...
```

Exponential Backoff을 사용한다.

예:

```toml
[recovery]
max_restarts = 5
restart_window_seconds = 300
```

반복 실패 시 `UNHEALTHY`로 전환한다.

---

## 24. Crash Loop 방지

다음 상황에서는 무한 재시작하지 않는다.

```text
invalid config
corrupted database
missing executable
disk full
permission failure
```

Host Layer는 failure reason을 기록하고 operator intervention이 필요한 상태로 둔다.

---

## 25. Android Process Kill 대응

Android가 Termux를 종료할 수 있다.

Host Layer는 완전한 방지를 보장할 수 없다.

대신 다음 전략을 사용한다.

1. Battery Optimization 제외
2. Wake Lock
3. Termux:Boot
4. 최소 상주 프로세스
5. 낮은 메모리 footprint
6. 장애 후 자동 복구

Nimwake 앱 자체는 대부분 sleeping 상태이므로 Android LMK 압박도 줄인다.

---

← [Storage · Release Cleanup · Log Rotation](01-storage-and-logs.md) · [PRD 인덱스](../README.md) · [Thermal과 Battery 운영](03-thermal-and-battery.md) →
