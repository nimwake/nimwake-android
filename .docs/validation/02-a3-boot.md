# 02. A3 부팅 자동 기동 — 재부팅 6회

> **마일스톤:** A3 · **일시:** 2026-10-08 – 10-09 · **결과:** **A3 완료** — 재부팅 6회 연속 무인 READY · 부팅 직후 전부 SLEEPING · 화면 꺼짐 + 충전 1시간 뒤 cold start PASS
>
> 비밀번호 잠금 기기다. 재부팅 후 잠금 해제 한 번은 사람이 한다.

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

## 화면 잠금 · 화면 꺼짐

- **화면 잠금은 비밀번호다.** 6회 모두 재부팅 후 비밀번호로 한 번 잠금을 풀고 Termux는 열지 않았다. 그 뒤 Termux:Boot가 실행됐다.
  잠금이 있는 기기는 **재부팅 후 한 번은 사람이 잠금을 풀어야** 한다. 완전 무인 재부팅(정전 복구 등)을 원하면 잠금을 없애야 한다 — 보안과 맞바꾸는 운영 선택이다.
- **잠금을 푼 뒤 화면을 꺼도 동작한다.** 6회차 부팅 후 약 11분, 화면 꺼짐 상태에서 `make test-boot` PASS (23:15:28).

```text
ok  every application is asleep after boot
ok  cold start   pid=12736  0.044523s
ok  warm         pid=12736  0.012232s  (same PID)
ok  sleep        pid=12736 gone
ok  cold start   pid=12774  0.045803s  (new PID)
PASS boot
```

잠금 없음 조건은 확인하지 않았다.

## 화면 꺼짐 + 충전 1시간 — 2026-10-09

화면을 끄고 충전기에 연결한 채 **1시간 동안 아무도 기기에 접속하지 않았다.**
처음 기준은 23:15:55였지만 23:23:21에 확인용 ssh가 한 번 붙어 Doze를 깼을 수 있어, 그 시각부터 다시 셌다.

| 시각 | nimwaked pid 10344 | RSS | 비고 |
| ---- | ------------------ | --- | ---- |
| 23:23:21 | 실행 17분 36초 | 2080 KB | 마지막 접속 |
| 00:24:53 | 실행 1시간 19분 08초 | **0 KB** | 1시간 뒤 첫 접속. ssh 1초 만에 붙음 |
| 00:25:27 | 실행 1시간 19분 33초 | 1820 KB (VmSwap 152 KB) | `make test-boot` 직후 |

```text
ok  every application is asleep after boot
ok  cold start   pid=20693  0.102686s
ok  warm         pid=20693  0.012195s  (same PID)
ok  sleep        pid=20693 gone
ok  cold start   pid=20730  0.036452s  (new PID)
PASS boot
```

- **daemon은 재시작 없이 살아 있었다** (같은 pid, 23:05 부팅 이후 연속).
- **1시간 동안 쓰이지 않은 daemon 메모리는 통째로 swap(zram)으로 밀려났다** (RSS 0). 첫 요청에서 다시 올라왔다.
- **그래서 첫 cold start만 103ms로 느렸다.** 평소(35–45ms)의 약 2.5배이고, 바로 다음 cold start는 36ms다. 오래 쉰 뒤 첫 요청의 지연은 soak에서 계속 본다.

## doctor — 2026-10-09

`make doctor`(이 PR)의 첫 실기기 실행.

```text
[OK]     Termux build: F_DROID
[OK]     Termux:Boot installed, same source as Termux (org.fdroid.fdroid)
[OK]     boot script ~/.termux/boot/00-sshd
[OK]     boot script ~/.termux/boot/10-nimwake
[WARN]   sshd password login is enabled — set PasswordAuthentication no (PRD §40)
[OK]     nimwaked installed in Ubuntu (core adf1e20)
[OK]     nimwaked running, health probe 404
[OK]     storage 98996MB free
[OK]     last boot run reached READY (2026-10-08 23:05:42)
[MANUAL] phantom process limit — needs adb (pair wireless debugging, or set ADB)
[MANUAL] battery optimization exemption for Termux, Termux:Boot — needs adb
```

첫 실행은 첫 줄만 출력하고 exit 0으로 끝났다. `ssh … sh -s`로 보낸 스크립트를 안의 `cmd package`가 표준 입력으로 읽어 **나머지 스크립트를 삼켰다.** 오류 없이 조용히 끝나 더 위험하다. 원격 스크립트를 `{ … } </dev/null`로 감싸 고쳤다 — 셸이 블록을 끝까지 읽은 뒤 실행하므로 안의 명령은 `/dev/null`을 읽는다. 같은 구조인 deploy · soak start도 같이 고쳤다.

## 결론과 남은 것

A3 완료 조건(Phase 1 [02-milestones](../phases/phase-1/02-milestones.md#a3--boot--power-mvp-4-5))을 모두 충족했다.

| 항목 | 상태 |
| ---- | ---- |
| 재부팅 5회 연속 무인 READY | **완료** (6회, 비밀번호 잠금 해제 1회 포함) |
| 부팅 직후 전부 SLEEPING | **완료** (1, 2, 6회차 확인) |
| 화면 꺼짐 + 충전 1시간 뒤 cold start | **완료** (daemon 생존, 첫 cold start 103ms) |
| 화면 잠금 | 비밀번호 잠금 확인. 잠금 없음은 미확인 (선택) |
| phantom process 제한 해제 · 배터리 최적화 예외 | **완료** (2026-10-09, 아래) |
| sshd 비밀번호 로그인 | **완료** — 키 로그인만 (`sshd_config.d/10-nimwake.conf`, #8) |

## adb — phantom process · 배터리 최적화 (2026-10-09)

무선 디버깅 페어링 후 개발 머신(WSL)에서 Windows SDK의 `adb.exe`로 했다. 24h soak 중이었고 실행 중인 프로세스에는 영향이 없다.

| 항목 | 전 | 후 |
| ---- | -- | -- |
| `device_config activity_manager max_phantom_processes` | `null` (Android 기본 32) | `2147483647` |
| `settings global settings_enable_monitor_phantom_procs` | `null` | `false` |
| `device_config get_sync_disabled_for_tests` | `none` | `persistent` — 서버 동기화가 값을 되돌리지 못하게 |
| deviceidle whitelist | `com.termux` · `com.termux.boot` 이미 있음 | 그대로 |

```text
[OK]     phantom process limit disabled (max_phantom_processes=2147483647)
[OK]     battery optimization exempt: com.termux
[OK]     battery optimization exempt: com.termux.boot
```

`make doctor`는 처음에 adb를 못 알아봤다. WSL에서 Windows `adb.exe`는 **환경 변수(`ANDROID_SERIAL`)를 받지 않고 출력이 CRLF**다. 무선 디버깅은 같은 기기를 IP와 mDNS 이름으로 두 번 보여 serial 지정이 필요했다 — `doctor`가 serial을 `-s` 인자로 넘기고 `\r`을 지우게 고쳤다.
