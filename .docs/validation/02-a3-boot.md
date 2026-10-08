# 02. A3 부팅 자동 기동 — 재부팅 6회

> **마일스톤:** A3 · **일시:** 2026-10-08 · **결과:** 재부팅 6회 연속 무인 READY · 부팅 직후 전부 SLEEPING

---

## 환경

[01. A1 재검증](01-a1-manual-baseline.md#재검증--2026-10-08-f-droid-termux)과 같다.

| 항목        | 값                                                                  |
| ----------- | ------------------------------------------------------------------- |
| 기기        | Samsung Galaxy A51 5G (`SM-A516N`) · Android 13 · One UI 5.1        |
| Termux      | F-Droid 0.118.3 · Termux:Boot F-Droid (같은 출처)                    |
| proot-distro | 5.9.0 · Ubuntu 26.04.1 LTS                                        |
| Core        | `nimwake/nimwake@adf1e20` (`core.lock`)                              |
| 부팅 스크립트 | `host/boot/00-sshd`, `host/boot/10-nimwake` — `make deploy`가 설치 (22:07:36) |

## 절차

```text
재부팅 → (잠금 해제만, Termux는 열지 않음) → 개발 머신(WSL)에서 make test-boot
```

부팅마다 `00-sshd`와 `10-nimwake`가 `~/.nimwake-host/logs/boot.log`에 기록을 남긴다.
그래서 횟수와 결과는 `make test-boot`를 매번 돌리지 않아도 `boot.log`로 확인된다.

## 결과

스크립트 설치(22:07:36) 이후의 부팅 기록 전부다. 실패(`TIMEOUT`, `exited before ready`)는 없다.

| # | 부팅     | 스크립트 시작 | READY    | 부팅 → READY | `make test-boot` |
| - | -------- | ------------- | -------- | ------------ | ---------------- |
| 1 | 22:18:03 | 22:20:51      | 22:20:54 | 171s         | PASS             |
| 2 | 22:24:07 | 22:25:20      | 22:25:23 | 76s          | PASS             |
| 3 | 22:30:07 | 22:31:38      | 22:31:41 | 94s          | —                |
| 4 | 22:43:44 | 22:45:09      | 22:45:12 | 88s          | —                |
| 5 | 22:51:48 | 22:53:09      | 22:53:12 | 84s          | —                |
| 6 | 23:04:30 | 23:05:42      | 23:05:45 | 75s          | PASS             |

- **스크립트 시작 → READY는 매번 3초**다 (wake lock · storage 확인 2초, nimwaked 기동 → health `404` 1초).
- **부팅 → 스크립트 시작은 72–168초**다. 이 구간은 Android · Termux:Boot의 몫이고 잠금 해제까지의 시간이 섞여 있다. 1회차(168s)만 길다.
- `make test-boot`를 돌린 회차(1, 2, 6)에서 부팅 직후 application 프로세스는 0개(SLEEPING)였고 lifecycle이 통과했다.

예 — 6회차 `boot.log`:

```text
2026-10-08 23:05:42 boot: start (booted at 2026-10-08 23:04:30)
2026-10-08 23:05:44 sshd: started (booted at 2026-10-08 23:04:30)
2026-10-08 23:05:45 ready: health 404 after 1s
```

## 관찰

- **Termux:Boot는 스크립트를 이름 순으로 시작하지만 앞 스크립트가 끝나기를 기다리지 않는다.** `00-sshd`의 기록이 `10-nimwake`의 `boot: start`보다 늦게 찍힌 회차가 대부분이다. 두 스크립트는 서로를 기다리지 않으므로 지금 구조에는 문제가 없다. 순서에 기대는 설계(예: sshd가 떠야 nimwaked 기동)를 하지 않는다.
- **Android는 앱에서 `/proc/uptime`을 읽지 못하게 한다** (`Permission denied`). 부팅 시각은 `uptime -s`로 적는다.
- **기록이 남지 않은 부팅은 이 표에 보이지 않는다.** Termux:Boot가 아예 실행되지 않은 부팅은 `boot.log`에 흔적이 없다. 재부팅 횟수는 사람이 센 값과 `booted at`이 서로 다른 기록 수가 같은지로 확인한다. 이번 6회는 연속으로 기록됐다.

## 남은 것

| 항목 | 상태 |
| ---- | ---- |
| 재부팅 5회 연속 무인 READY | **완료** (6회) |
| 부팅 직후 전부 SLEEPING | **완료** (1, 2, 6회차 확인) |
| 화면 잠금 있음 / 없음 | 미기록. 이번 회차의 잠금 설정을 기록하지 않았다 |
| 화면 꺼짐 + 충전 1시간 뒤 cold start | 미수행 |
| phantom process 제한 해제 | 미수행 (Android 13 → `adb shell device_config ...`) |
