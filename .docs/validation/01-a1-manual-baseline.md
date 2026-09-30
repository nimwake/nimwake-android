# 01. A1 수동 기동 — 첫 실기기 lifecycle

> **마일스톤:** A1 · **일시:** 2026-10-01 · **결과:** lifecycle PASS · graceful stop PASS

---

## 환경

| 항목              | 값                                                              |
| ----------------- | --------------------------------------------------------------- |
| 기기              | Samsung Galaxy A51 5G (`SM-A516N`)                               |
| Android           | 13 (SDK 33) · One UI 5.1                                         |
| Termux            | **Google Play** 설치 (`installer=com.android.vending`), termux-tools 3.0.9 |
| Termux:Boot       | 미설치                                                           |
| proot / proot-distro | 5.1.107.80 / 5.3.0                                           |
| Guest             | Ubuntu 26.04.1 LTS (`proot-distro install ubuntu`)               |
| Core              | `nimwake/nimwake@adf1e20` — v0.0.5 + #11 + #14, `aarch64-unknown-linux-musl` (cross 0.2.5, rustc 1.98.1) |
| 개발 머신         | Windows 11 + WSL2 Ubuntu, 같은 LAN, ssh `:8022` key auth         |

## 경로

```text
make fetch-core → make deploy → nimwaked 기동 (nohup, Termux) → make test-device
```

## 결과

### lifecycle (`tests/device/lifecycle.sh`, 기기 loopback)

```text
ok  health probe 404
ok  cold start   pid=20001  0.020311s
ok  warm         pid=20001  0.009517s  (same PID)
ok  /proc/20001 visible from Termux
..  waiting 10s for idle → sleep
ok  sleep        pid=20001 gone
ok  cold start   pid=20038  0.027682s  (new PID)
PASS lifecycle
```

cold start 구간 (daemon 로그 `nimwake::startup`):

```text
queue_us=356  spawn_us=24983  readiness_us=61471  total_us=86812
```

### graceful stop (E5 일부)

앱이 깨어 있는 상태에서 proot 안 `nimwaked` pid에 `kill -TERM`.

- `nimwaked`, `echo-server` 1초 안에 종료. 잔존 0.
- 바깥 `proot` process(`--kill-on-exit`)는 그 뒤에 따라서 종료.
- 로그: `shutdown signal received` → `gateway is shutting down` → `stopping every application` → `stopping application ... reason=daemon shutdown`

## 관찰

- **E1 부분 확인:** proot는 pid namespace를 만들지 않는다. Core가 본 child pid가 Termux의 `/proc`에 그대로 보인다.
- process tree: `proot` → `/bin/sh -c` → `nimwaked` → `echo-server`. `proot-distro login -- CMD`가 `sh -c`를 한 겹 끼운다. supervisor가 신호를 보낼 대상을 정할 때 고려해야 한다 (E5 본 실험).
- 비대화형 ssh에서 proot가 `can't sanitize binding "/proc/self/fd/0"` 경고를 낸다. tty가 없어서 생기는 경고이고 동작과 무관하다.

## 위험 · 후속

| 항목 | 내용 | 영향 |
| ---- | ---- | ---- |
| Termux 출처 | Google Play 빌드. Termux:Boot는 F-Droid/GitHub 빌드와 **같은 출처·서명**이어야 한다 | **A3 blocker 가능성.** Play에서 Termux:Boot를 받을 수 있는지 확인하거나, F-Droid/GitHub 빌드로 재설치 |
| 기존 Ubuntu | 이전 수동 설치본(`~/ubuntu22-fs`)이 별도로 있다. 이번 검증은 proot-distro Ubuntu만 사용 | 없음. 정리는 사용자 판단 |
| E2–E7 | 미수행 | A1 나머지 |
| Core pin | 브랜치 SHA(`adf1e20`) | #14 머지 후 main SHA로 올리고 재실행 |
