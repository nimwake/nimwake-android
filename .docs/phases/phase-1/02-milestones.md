# 02. 마일스톤

> **Phase 1 — Android MVP** › 마일스톤
>
> 요구사항 원장: [PRD §10–§12, §22–§25, §35–§36, §43–§44](../../PRD.md)

---

## MVP 범위와 마일스톤 매핑

| MVP 항목              | 내용                                                  | 마일스톤   |
| --------------------- | ----------------------------------------------------- | ---------- |
| [1] Install           | Termux · Ubuntu proot · nimwaked binary / config      | A1 수동 → A4 자동 |
| [2] Start             | Android → Termux → proot → nimwaked                   | A2         |
| [3] Recovery          | nimwaked crash → supervisor 감지 → 재기동              | A2         |
| [4] Boot              | reboot → Termux:Boot → proot → nimwaked               | A3         |
| [5] Power             | wake lock · battery optimization · phantom process    | A3         |
| [6] Real lifecycle    | LAN HTTP → wake → 200 → idle → sleep                  | A1 기기 내 → A5 LAN |

```text
A0 ─▶ A1 ─▶ A2 ─▶ A3 ─▶ A4 ─▶ A5 ─▶ A6
repo  수동   start  boot  install LAN   72h
      실험   recov  power  자동   24h
```

A0은 기기도 Core binary도 필요 없다.
A1부터 실기기와 Core aarch64 artifact([nimwake#3](https://github.com/nimwake/nimwake/issues/3))가 필요하다.

Core가 이미 `v0.0.5`까지 나갔으므로 A0는 **A1에 필요한 최소판**(`core.lock` · `fetch-core` · `deploy`)만 먼저 하고,
CI · bats · `host/lib`은 실기기 결과를 본 뒤에 채운다. → [03 계획과 달라진 점](03-core-sync.md#계획과-달라진-점)

### 현황 — 2026-10-09

Core `v0.1.0-rc1`, 기기 Galaxy A51 5G · Android 13 · F-Droid Termux.

| 마일스톤 | 상태 | 근거 |
| -------- | ---- | ---- |
| A0 | 완료 — `make doctor-dev`(개발 머신 도구 점검)만 남음 | #2 · #4 · #9 · #11 |
| A1 | 완료. 실험은 E1 · E5만 정식 수행, E2–E4 남음 | [validation/01](../../validation/01-a1-manual-baseline.md) · [03](../../validation/03-core-v0.1.0-rc1.md) |
| A2 | **완료** — 완료 조건 4개 충족. crash 뒤 orphan 정리(E4)는 남음 | [validation/04](../../validation/04-a2-recovery.md) |
| A3 | **완료** — 재부팅 6회 무인 READY, 1시간 뒤 cold start. phantom process 해제 남음 | [validation/02](../../validation/02-a3-boot.md) |
| A4 | 미착수 | — |
| A5 | LAN · 동시 cold start · Wi-Fi 복구 완료. **24h soak 진행 중** (10-09 01:25 시작). Core workload 비교 남음 | [validation/05](../../validation/05-a5-network.md) |
| A6 | 미착수 (24h soak 다음) | — |

---

## A0 — Repository bootstrap

기기 없이 끝나는 것. 개발 머신 두 종류(macOS, WSL)에서 같은 명령이 도는 것을 확인한다.

- [x] `.gitattributes`, `.gitignore`(`dist/`), `.editorconfig` (#11)
- [x] `PRD.md` 이름 정리: `Ember` → `Nimwake`, `emberd` → `nimwaked` — 20곳 (#11)
- [x] `Makefile`: `lint` · `test` · `fetch-core` · `deploy` (+ `run` · `stop` · `doctor` · `test-*` · `soak-*`) · [ ] `doctor-dev`
- [x] `core.lock` + `scripts/fetch-core.sh` — release asset(`tag=`) 또는 run artifact, `BUILD_INFO` commit 검사 (#7)
- [x] CI — ubuntu 항상, macOS는 개발 머신 코드가 바뀔 때만 (#4 · #9)
- [x] `host/lib` + `tests/unit` — policy · supervisor(가짜 daemon) · soak, bats 22개 (#4 · #5)
- [x] README: 개발환경(macOS / WSL) 셋업, 기기 준비, 명령, Core 호환 표 (#11)
- [x] `.docs/validation/00-template.md` — 리포트 01–05의 형식을 템플릿으로 (#11)

**완료 조건**

- macOS와 WSL 각각에서 `make doctor-dev lint test`가 성공한다.
- `ci.yml`이 ubuntu · macos 양쪽에서 통과한다.

---

## A1 — Manual baseline + 실기기 실험

PRD §43 Phase 0. 자동화 전에 **손으로** 전 경로를 한 번 통과시키고, Core 가정을 실기기에서 확인한다.
여기서 나온 결과가 Core `v0.1.0`으로 가는 첫 피드백이다.

**선행 조건:** Core aarch64 artifact — Core `release.yml`. → [01 §5](01-repository-setup.md#5-core-binary-조달)

- [x] `make fetch-core`로 `core.lock` SHA의 artifact를 `dist/aarch64/`에 받는다
- [x] Termux + Termux:Boot — **같은 출처**로 설치. Google Play → **F-Droid**로 재설치 (validation/01 재검증). Termux:API도 F-Droid
- [x] `pkg install proot-distro openssh` → `proot-distro install ubuntu:26.04` ([D-A8](03-core-sync.md#이-레포의-설계-결정))
- [x] Termux sshd + key auth, 개발 머신 `~/.ssh/config`. 비밀번호 로그인 끔 (`sshd_config.d/10-nimwake.conf`, #8)
- [x] `scripts/deploy.sh`로 `dist/` + `guest/apps/echo` 배치
- [x] proot 안에서 `nimwaked` 수동 실행, Termux 쪽에서 `curl -H 'Host: echo.local' 127.0.0.1:8080`
- [x] `tests/device/lifecycle.sh` 초판: cold → same PID → idle → sleep → new PID
- [ ] [03. Core 동기화 — 실기기 실험](03-core-sync.md#실기기-실험) E1–E7 수행 — 정식으로는 E1(`/proc` 가시성) · E5(SIGTERM 경로)만. E6(빠른 재기동 bind)은 recovery에서, E7(화면 꺼짐 idle)은 A3 1시간 확인에서 간접 확인. **E2 · E3 · E4 남음**
- [x] 첫 검증 리포트 `validation/01-*.md`

**완료 조건**

- 기기 내부(loopback)에서 lifecycle 시나리오가 Core E2E와 같은 결과를 낸다 (cold → same PID → sleep → new PID).
- E1–E7 결과가 리포트에 있고, 실패 항목은 Core 이슈로 올라가 있다.

---

## A2 — Start + Supervisor (MVP [2] [3])

PRD §8, §22–§24. `host/`의 첫 실체.

```text
nimwake-host start
   └── supervisor loop (Termux, background)
         ├── proot-distro login ubuntu --user nimwake -- /opt/nimwake/bin/nimwaked <apps>
         ├── health probe  (30s)
         └── exit 감지 → backoff → 재기동
```

- [x] `host.conf` (`KEY=value`, shell에서 source) — 형식 결정은 [03 D-A2](03-core-sync.md#이-레포의-설계-결정)
- [x] `nimwake-host start | stop | status | logs`
- [x] 단일 실행 보장: `run/supervisor.pid` + 명령줄 확인 (중복 supervisor 금지)
- [x] health probe — **app host를 쓰지 않는다** (§ 아래)
- [x] restart backoff `0s → 5s → 15s → 60s`, `max_restarts` / `restart_window_seconds` (PRD §23)
- [x] crash-loop 판정 → `UNHEALTHY`로 두고 멈춤 (PRD §24)
- [x] `stop`: nimwaked에 SIGTERM → Core의 graceful shutdown 완료 대기 → 잔존 process 확인
- [ ] crash 후 orphan 정리 (E4 결과에 따라) — E4 미수행
- [x] `tests/unit`: backoff 계산, window 판정, 가짜 daemon 감시 루프 — bats
- [x] `tests/device/recovery.sh` — 실기기 PASS: `kill -9` → 1초 안에 재기동, exit 78 → UNHEALTHY (proot-distro가 종료 코드를 전달함), stop 후 잔존 0 → [validation/04](../../validation/04-a2-recovery.md)

### Health probe가 app을 깨우면 안 된다

probe가 등록된 app의 `Host`로 요청하면 그 요청이 `acquire()`를 거쳐 **app을 깨우고 idle timer를 계속 리셋한다.**
supervisor가 scale-to-zero를 무력화한다.

probe: 등록되지 않은 Host(`Host: nimwake-health.invalid`)로 요청해 **`404`가 오면 gateway alive**로 본다.
Core가 이것을 계약으로 고정했다 — 미등록 Host 요청은 어떤 app의 lifecycle도 건드리지 않는다. → [Core §74](https://github.com/nimwake/nimwake/blob/main/.docs/prd/04-platform/03-host-interface.md)

crash-loop 판정은 **종료 코드 기반**이다 (§74): `78`이면 재기동하지 않고 `UNHEALTHY`, `69` · `1`이면 backoff 후 재시도, `0`이면 정상 종료.

**완료 조건** — 충족 (2026-10-09)

- [x] `kill -9 <nimwaked>` → 한 backoff 주기 안에 재기동, health `OK`, 이후 lifecycle 시나리오 통과.
- [x] invalid manifest → 재시도하지 않고 `UNHEALTHY` + 원인 기록.
- [x] `nimwake-host stop` 후 proot 안에 app process가 남지 않는다.
- [x] supervisor가 30분 동안 probe를 보내는 중에도 app이 idle → sleep 한다 — 24h soak 중 supervisor가 30초마다 probe하는 동안 5분 간격 표본의 `apps_before`가 계속 0.

---

## A3 — Boot + Power (MVP [4] [5])

PRD §10–§12, §25.

- [x] `host/boot/10-nimwake`: `termux-wake-lock` → storage 확인 → `nimwake-host start` → RUNNING 대기 (network 확인은 하지 않는다 — gateway는 loopback · LAN과 무관하게 뜬다). `00-sshd`가 따로 sshd를 띄운다
- [x] boot 로그 `logs/boot.log`: 각 단계 시각 기록. `/proc/uptime`은 Android가 막아 시작 줄에 `uptime -s`(부팅 시각)를 적는다
- [ ] 설치 checklist (자동 판별 불가 항목 수동 확인, PRD §12) — Termux:Boot 1회 실행만 확인. 배터리 최적화 예외 · phantom process는 adb 페어링 뒤 `make doctor`로 확인:
  - Termux battery optimization 제외, background 활동 · 데이터 허용
  - 제조사 battery killer (Samsung "절전 예외 앱", Xiaomi autostart 등)
  - **Android 12+ phantom process killer** — child process 제한 해제
    (Android 14+: 개발자 옵션 "하위 프로세스 제한 사용 중지", 12–13: `adb shell device_config put activity_manager max_phantom_processes 2147483647`)
  - Termux:Boot를 설치 후 한 번 실행
- [x] doctor 최소판 — 기기 CLI가 아니라 개발 머신의 `make doctor`(ssh + adb)로 했다. `[OK]/[WARN]/[FAIL]/[MANUAL]` (PRD §34, #6 · #8)
- [x] `tests/device/boot.sh`: 수동 재부팅 후 ssh가 올라오면 마지막 부팅의 READY · health · SLEEPING · lifecycle

**완료 조건** — 충족 (2026-10-09) → [validation/02](../../validation/02-a3-boot.md)

- [x] 재부팅 5회 연속, 사람 손 없이 READY. 부팅 직후 모든 app이 SLEEPING. (PRD §10, §44-1, §44-5) — 6회. 비밀번호 잠금 기기라 재부팅 후 잠금 해제 1회는 사람이 한다
- [x] 화면 꺼짐 + 충전 연결 상태로 1시간 뒤 cold start 성공 — daemon 생존, 첫 cold start 103ms (swap-in)

---

## A4 — Install automation (MVP [1] 자동)

PRD §35–§36.

- [ ] `install/install-android.sh`: 의존성 → proot-distro → Ubuntu → `guest/setup-ubuntu.sh` → host 배치 → boot script → `doctor`
- [ ] **멱등**: 두 번 실행해도 결과가 같고, 기존 `host.conf`와 app manifest를 덮지 않는다
- [ ] binary 배치는 `deploy.sh`와 같은 경로를 쓴다 (설치와 업데이트가 갈라지지 않게)
- [ ] secret · key를 생성하거나 업로드하지 않는다 (PRD §36)

**완료 조건**

- 초기화한 기기(또는 Termux 데이터 삭제)에서 `install-android.sh` 한 번 + checklist 수동 항목만으로 A3 완료 조건을 다시 통과한다.

---

## A5 — LAN lifecycle + 24h soak (MVP [6])

- [x] LAN 접근: `host.conf`의 `NIMWAKE_LISTEN=0.0.0.0:8080` (외부 노출은 opt-in, Core §74) → `make test-lan`
- [x] concurrent cold start: LAN에서 동시 요청 20개 → PID 하나
- [x] Wi-Fi 끊김 → 41초 뒤 복구, daemon 재기동 없이 요청 성공 → [validation/05](../../validation/05-a5-network.md)
- [ ] Core `v0.0.4` workload를 기기에서 실행해 CI Linux와 같은 지표로 비교 (Core PRD §50) — `nimwake-bench`가 aarch64 artifact에 없다. Core에 요청 필요
- [ ] `tests/device/soak.sh` 24h: daemon 생존 · RSS · 온도 · 배터리 · orphan · storage 증가 — **진행 중** (2026-10-09 01:25 → 10-10 01:25)

**완료 조건**

- 개발 머신에서 LAN으로 lifecycle 시나리오 통과.
- 24h soak 리포트가 Core `v0.1.0` 판정 전에 전달된다.

---

## A6 — 72h soak → `nimwake-android v0.1.0`

- [ ] 72h soak (Core PRD §51 관찰 항목 전부)
- [ ] PRD §44 성공 기준 1–8 확인
- [ ] Core `v0.1.0` Android 체크리스트에 결과 링크

**완료 조건**

- 아래 체크리스트 전부 ✓ 이고 Core `v0.1.0` acceptance에서 참조된다.

```text
Android Device
──────────────
Install ✓   Boot recovery ✓   Cold start ✓   Scale-to-zero ✓
Daemon recovery ✓   Network recovery ✓   24h soak ✓   72h soak ✓
```

2026-10-09 현재 — 6개 충족, soak 2개 남음:

| 항목 | 상태 | 근거 |
| ---- | ---- | ---- |
| Install | ✓ (수동 — A4 자동화 전) | validation/01 |
| Boot recovery | ✓ | validation/02 · 04 |
| Cold start | ✓ | validation/01 · 03 |
| Scale-to-zero | ✓ | validation/01 · 03 · 05 |
| Daemon recovery | ✓ | validation/04 |
| Network recovery | ✓ | validation/05 |
| 24h soak | 진행 중 | — |
| 72h soak | 24h 다음 | — |

---

← [01. 레포지토리 셋업](01-repository-setup.md) · [Phase 1](README.md) · [03. Core 동기화](03-core-sync.md) →
