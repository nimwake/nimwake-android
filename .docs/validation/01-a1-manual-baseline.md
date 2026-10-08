# 01. A1 수동 기동 — 첫 실기기 lifecycle

> **마일스톤:** A1 · **일시:** 2026-10-01, 재검증 2026-10-08 · **결과:** lifecycle PASS · graceful stop PASS (두 차례 모두)
>
> 2026-10-08에 Termux를 Google Play 빌드에서 F-Droid 빌드로 재설치하고 같은 Core로 다시 검증했다. → [재검증](#재검증--2026-10-08-f-droid-termux)

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

---

## 재검증 — 2026-10-08 (F-Droid Termux)

A3를 위해 Termux를 Termux:Boot와 같은 출처로 맞췄다. Termux 재설치로 `$HOME`과 sshd 호스트 키가 새로 만들어졌고, Ubuntu는 다시 설치했다. Core binary와 manifest는 그대로다.

### 환경 변경

| 항목                 | 2026-10-01                         | 2026-10-08                                              |
| -------------------- | ---------------------------------- | ------------------------------------------------------- |
| Termux               | Google Play, termux-tools 3.0.9    | **F-Droid** 0.118.3 (`installer=org.fdroid.fdroid`), termux-tools 1.46.0+really1.45.0-1 |
| Termux:Boot          | 미설치                             | **F-Droid** (`installer=org.fdroid.fdroid`) — Termux와 같은 출처 |
| proot / proot-distro | 5.1.107.80 / 5.3.0                 | 5.1.107.96 / 5.9.0                                      |
| Termux 사용자        | —                                  | `u0_a319` (재설치로 uid 변경. Termux sshd는 사용자명을 보지 않는다) |
| Guest · Core         | 변경 없음 (Ubuntu 26.04.1 LTS, `adf1e20`) | 변경 없음                                         |

proot-distro 5.9.0은 rootfs를 `$PREFIX/var/lib/proot-distro/containers/<name>`에 둔다. 5.3.0의 `installed-rootfs/`가 아니다. 설치 여부를 경로로 검사하는 스크립트는 깨진다.

### 경로

```text
make deploy → make run (foreground, ssh) → make test-device → proot 안 nimwaked pid에 kill -TERM
```

### lifecycle

```text
ok  health probe 404
ok  cold start   pid=622  0.033510s
ok  warm         pid=622  0.007632s  (same PID)
ok  /proc/622 visible from Termux
..  waiting 10s for idle → sleep
ok  sleep        pid=622 gone
ok  cold start   pid=846  0.029178s  (new PID)
PASS lifecycle
```

cold start 구간 (daemon 로그 `nimwake::startup`, 세 번):

```text
queue_us=162  spawn_us=16989  readiness_us=4654  total_us=21805
queue_us=44   spawn_us=15429  readiness_us=3626  total_us=19100
queue_us=164  spawn_us=17477  readiness_us=2886  total_us=20528
```

2026-10-01의 `total_us=86812`(readiness 61ms)는 daemon 기동 직후 첫 cold start 한 번이다. 이번에는 기동 후 약 20초 뒤였다. 표본이 작아 출처 변경의 영향으로 해석하지 않는다. 같은 조건의 비교는 A5 bench에서 한다.

### graceful stop

앱이 깨어 있는 상태(echo-server pid 970)에서 proot 안 `nimwaked` pid에 `kill -TERM`.

- 4초 뒤 `nimwaked`, `echo-server`, 바깥 `proot` 모두 없음. `make run` exit 0.
- 로그: `shutdown signal received signal="SIGTERM"` → `gateway is shutting down` → `stopping every application` → `stopping application ... reason=daemon shutdown`

### 관찰 — proot 아래에서 process 이름으로 찾을 수 없다

Termux에서 본 `nimwaked`의 `comm`은 `nimwaked`가 아니라 **잘린 경로 `/opt/nimwake/bi`**다. proot가 binary를 loader로 실행하기 때문이다.

```text
  PID  PPID COMM            ARGS
  371   370 /data/data/com. .../usr/bin/proot --kill-on-exit ... /bin/sh -c /opt/nimwake/bin/nimwaked /home/nimwake/.nimwake/apps
  472   371 /bin/sh         /bin/sh -c /opt/nimwake/bin/nimwaked /home/nimwake/.nimwake/apps
  475   472 /opt/nimwake/bi /opt/nimwake/bin/nimwaked /home/nimwake/.nimwake/apps
```

그래서 `pkill -x nimwaked` / `pgrep -x nimwaked`는 **아무것도 찾지 못하고 실패한다.** 처음 시도에서 "nimwaked가 종료됐다"고 오판할 뻔했다 — 실제로는 계속 떠 있었다.

**A2 supervisor 반영:** daemon을 이름으로 찾지 않는다. 기동 시 pid를 `run/` 아래에 기록하거나, 최소한 전체 경로로 찾는다(`pgrep -f /opt/nimwake/bin/nimwaked`). 생존 판단은 pid가 아니라 health probe(`404`)로 한다 (Core PRD §74).

### A3 사전 확인 — Termux:Boot로 sshd 자동 기동

A3 본 작업(`host/boot/10-nimwake`) 전에 Termux:Boot 경로가 이 기기에서 동작하는지만 확인했다.

```sh
# ~/.termux/boot/00-sshd  (0700)
#!/data/data/com.termux/files/usr/bin/sh
termux-wake-lock
sshd
```

- `~/.termux/boot/`는 Termux:Boot가 만들지 않는다. 직접 만든다.
- 첫 재부팅에서는 개발 머신의 ssh가 `Connection refused`였다. Termux:Boot 앱 1회 실행과 배터리 설정을 확인한 뒤 다시 재부팅해서 성공했다. 어느 조치가 결정적이었는지는 분리하지 않았다.
- 성공한 재부팅: Termux를 열지 않은 상태에서 개발 머신의 `ssh ... 'echo ok'` → `ok`.
- 기기 기록: `uptime` 3분 시점에 `sshd` 실행 시간 1분 48초. **부팅 후 약 1분 12초에 sshd가 떴다.** 부팅 직후 load average가 12.5로 높다.

**A3 반영:** boot script는 단계별 시각을 `logs/boot.log`에 남긴다. 이번처럼 "실행이 안 됐는지, 늦게 됐는지"를 구분할 수 없으면 원인을 좁히지 못한다. 재부팅 후 READY까지 1분 이상을 기본 예상치로 둔다.

---

## 위험 · 후속

| 항목 | 내용 | 영향 |
| ---- | ---- | ---- |
| Termux 출처 | ~~Google Play 빌드~~ → 2026-10-08 Termux · Termux:Boot 모두 F-Droid로 재설치 | **해소.** 재부팅 후 Termux:Boot로 sshd 자동 기동 확인. A3 남은 작업: nimwaked까지 자동 기동, 연속 재부팅, phantom process 해제 |
| 화면 잠금 | 잠금이 있으면 재부팅 후 한 번 풀기 전까지 Termux:Boot가 실행되지 않는다. 이번 확인에서 기기의 잠금 설정은 기록하지 않았다 | A3에서 잠금 있음/없음 각각 확인하고 무인 운영 조건으로 기록 |
| sshd | 재설치로 `PasswordAuthentication`이 기본값(yes)으로 돌아갔다 | key 등록 확인 후 `no`로 끈다 (PRD §40) |
| process 이름 | proot 아래 `comm`이 `/opt/nimwake/bi` | A2 supervisor는 pid 파일 · 전체 경로 · health probe 사용 |
| 기존 Ubuntu | 이전 수동 설치본(`~/ubuntu22-fs`)이 별도로 있다. 이번 검증은 proot-distro Ubuntu만 사용 | 없음. 정리는 사용자 판단 |
| E2–E7 | 미수행 | A1 나머지 |
| Core pin | 브랜치 SHA(`adf1e20`) | #14 머지 후 main SHA로 올리고 재실행 |
