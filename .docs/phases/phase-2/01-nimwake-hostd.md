# 01. `nimwake-hostd` — supervisor를 Rust로

> **Phase 2** › nimwake-hostd 설계
>
> 요구사항 원장: [PRD §8 Host Supervisor](../../prd/02-architecture/01-structure.md), [§32 Configuration · §33 Host CLI](../../prd/04-delivery/02-configuration-and-cli.md).
> 결정 D-A1(“MVP는 POSIX shell, 이후 `nimwake-hostd`는 조직 코어 언어 Rust로”)의 **이후**를 정한다.

---

## 왜 지금인가 — shell이 부족해진 곳

Phase 1 동안 Host Layer는 sh로 약 900라인이 되었다 (`host/lib` 5개 · `host/bin` 2개 · `host/boot` 3개).
동작은 했지만, 아래는 **shell이라서 생긴 비용**이다. 모두 Phase 1에서 실제로 겪었다.

| 문제 | 겪은 곳 | Rust에서 |
| ---- | ------- | -------- |
| 프로세스를 **이름으로** 찾는다 — proot 아래 comm이 잘리고(`/opt/nimwake/bi`), `pgrep -f`가 자기 셸을 잡고, pid가 재사용된다 | validation/01 · #15 · #20 | 자식은 `Child` 핸들로 쥔다. 손자(`nimwaked`)는 pidfd · `/proc/<pid>/stat`의 ppid로 |
| 할 일이 **루프 하나에 직렬**이다 — health 30초 · 네트워크 30초 · 정리 10분이 한 `while`에서 돈다. 복구 hook이 60초 걸리면 health probe가 그만큼 밀린다 | #26 · #28 · #31 | 독립 task. hook은 자기 timeout을 가진 task |
| **상태가 파일 여러 개**다 — `run/state` · `run/network` · `run/storage` · `run/hung` · `run/stop`을 subshell들이 나눠 쓴다 | #4 · #26 · #30 | 상태는 한 프로세스 메모리. 파일은 **바깥에 보여 주는 용도**로만 쓴다 |
| **TOML을 읽을 수 없다** — PRD §32는 TOML인데 `host.conf`는 `KEY=value`를 source한다 | D-A2 | `toml` crate (Core와 같은 버전) |
| 오류 처리 · 시각 계산 · 이식성 — `set -e` 함정, GNU/BSD `date` 차이, `wc -c`의 공백 | #19 · #26 · `check-portability.sh` | 타입과 표준 라이브러리 |
| 테스트가 **가짜 명령 바꿔치기**에 기댄다 (`ifconfig()` 함수, `NIMWAKE_PROBE`) | `tests/unit/*.bats` | 단위 테스트는 trait 경계에서. bats는 **행동 계약 검사**로 남긴다 (아래) |

반대로 shell이 **충분한 곳**도 있다. 그것은 옮기지 않는다 (아래 "범위").

---

## 범위

| 옮긴다 (`nimwake-hostd`) | 그대로 둔다 (sh) |
| ------------------------ | ---------------- |
| supervisor 루프 — 기동 · health · 종료 코드 분류 · backoff · crash loop (`supervisor.sh` · `policy.sh`) | Termux:Boot 진입점 `host/boot/*` — 몇 줄이고, Termux:Boot가 sh를 부른다 |
| 고아 정리 (`reap_orphan_daemon`) | 설치 · 배포 `install/` · `scripts/` — 개발 머신 쪽, 한 번 돈다 |
| 네트워크 감시 · 복구 hook (`network.sh`) | 실기기 테스트 `tests/device/` |
| 저장공간 감시 · 로그 순환 · 정리 (`check_storage` · `logs.sh`) | soak sampler `nimwake-soak` — 측정 도구다 |
| CLI `nimwake-host start · stop · status · logs` (+ PRD §33의 `restart · network · storage`) | `make doctor` — 개발 머신에서 ssh로 돈다 |
| 설정 읽기 — TOML, 그리고 기존 `host.conf` | |

**Core 기능은 다시 구현하지 않는다** (PRD §3). hostd는 `nimwaked`를 프로세스로만 다룬다 — Core PRD §74 Host Interface 계약(인자 · 신호 · 종료 코드 · health probe)이 유일한 접점이다.

---

## 바깥 계약 — 바꾸지 않는다

이행은 **같은 계약 뒤에서 구현을 바꾸는 것**이다. 부팅 스크립트 · doctor · 실기기 테스트 · soak가 sh 판과 hostd 판을 구별하지 못해야 한다.

| 계약 | 지금 (sh) | hostd |
| ---- | --------- | ----- |
| 명령 | `nimwake-host start\|stop\|status\|logs` | 같은 이름 · 같은 하위 명령 · 같은 종료 코드. `$PREFIX/bin/nimwake-host` |
| 상태 파일 | `run/state` "STATE 시각 이유" · `run/network` · `run/storage` | 같은 형식으로 쓴다 — `10-nimwake`가 `RUNNING`을, doctor가 `network`를 읽는다 |
| 로그 | `logs/supervisor.log` "YYYY-MM-DD HH:MM:SS 메시지", `logs/nimwaked.log` | 같은 경로 · 같은 줄 형식 — `recovery.sh` · `test-wifi`가 grep한다 |
| 설정 | `~/.nimwake-host/host.conf` (`KEY=value`) | 읽는다. `host.toml`이 있으면 그것이 우선 (PRD §32). 둘 다 있으면 경고 |
| 신호 | `stop`은 daemon에 SIGTERM, `STOP_TIMEOUT` 뒤 고아 정리 | 같다 |

### 행동 계약 = 지금의 bats

`tests/unit/supervisor.bats`의 대부분은 가짜 daemon(`fixtures/fake-nimwaked` · `fake-proot`)으로 **바깥에서** `$host`를 돌린다 — start · crash 재기동 · exit 78 · crash loop · health 실패 · 고아 정리 · stop · 저장공간 알림 · 로그 순환 · 네트워크 기록.
구현 언어를 모른다. **그대로 hostd의 수용 테스트가 된다.** `$host`는 `NIMWAKE_HOST_BIN`으로 바꿀 수 있다.

```text
NIMWAKE_HOST_BIN=host/bin/nimwake-host  bats tests/unit/supervisor.bats   # sh 판 (지금)
NIMWAKE_HOST_BIN=target/…/nimwake-hostd bats tests/unit/supervisor.bats   # hostd 판
```

lib를 source해 함수를 직접 부르는 bats(`network.bats` · `logs.bats`, `supervisor.bats`의 `load_libs` 테스트)는 sh 내부 시험이다 — 같은 경우를 Rust 단위 테스트로 옮기고, sh 판을 지울 때 함께 지운다.

---

## 구조

```text
nimwake-hostd (Termux 쪽, proot 밖)
├── supervisor task   proot-distro login … nimwaked 기동 · wait · 종료 코드 분류 · backoff · crash loop
├── health task       30초마다 Host: nimwake-health.invalid → 404 (Core PRD §74)
├── network task      30초마다 인터페이스 · 게이트웨이 · (외부) → 상태 전이, 복구 hook (timeout)
├── housekeeping task 10분마다 저장공간 · 로그 순환 · 정리
└── control           CLI 요청 (stop · status) — unix socket 또는 run/ 파일
```

- **어디서 도는가:** Termux 쪽(proot 밖). `proot-distro`를 띄우고 `termux-notification` · `termux-wake-lock`을 부르기 때문이다. 지금 sh supervisor와 같은 자리다.
- **런타임:** tokio `current_thread` — 기기 자원이 작다. Core와 같은 crate 버전(`tokio` · `toml` · `nix` · `tracing`)을 쓴다.
- **안전:** `unsafe_code = "forbid"` (Core와 같은 lint).
- **Android 제약은 Phase 1에서 확인한 그대로 따른다:** netlink · `/proc/net/*` · `/proc/uptime` 금지 → 인터페이스는 ioctl(`SIOCGIFCONF`, `nix`), 게이트웨이는 설정, ping은 ICMP datagram socket 또는 `ping` 실행. 이 판단은 [validation](../../validation/) · #30에 근거가 있다.

---

## 빌드와 배포

| 항목 | 결정 (제안) | 이유 |
| ---- | ----------- | ---- |
| 위치 | **이 레포** `crates/nimwake-hostd/` (Cargo workspace 신설) | Host Layer 코드다. Core 레포는 Android를 모른다 (PRD §44-7 · §44-8) |
| 타깃 | `aarch64-unknown-linux-musl` static, `cross` | Core release.yml과 같은 경로 · 같은 도구 |
| 빌드 주체 | **이 레포 CI** — D-A3을 좁힌다: “Core binary는 Core CI가, Host Layer binary는 이 레포 CI가” | D-A3의 취지(빌드 책임이 둘로 갈라지지 않는다)는 binary마다 지킨다 |
| 배포 | `make deploy`가 hostd binary를 `~/.nimwake-host/bin/`에 놓는다. `NIMWAKE_HOSTD=1`일 때만 `nimwake-host`가 hostd를 가리킨다 → 기본값 전환은 H4 | 한 번에 바꾸지 않는다 |
| release | `release.yml`(#27)이 hostd binary와 sha256을 함께 올린다 — 지금의 "binary 없음"은 hostd 도입과 함께 바뀐다 | |
| 개발 머신 | WSL2 · macOS에 rustup + `cross`(Docker). `make doctor-dev`가 확인한다 | D-A7 |

**결정 D-A9 (제안):** Host Layer의 Rust binary는 이 레포가 빌드한다. Core binary는 여전히 Core CI만 빌드한다 (D-A3 유지).

---

## 마일스톤

| ID | 내용 | 완료 조건 |
| -- | ---- | --------- |
| **H0** | spike — musl static binary가 **proot 밖 Termux에서** 돈다: `proot-distro` 실행 · 신호 · `SIGCHLD` · ioctl 인터페이스 · ping | 기기에서 hello binary가 위 다섯 가지를 한다. 리포트 `validation/NN-h0-spike.md` |
| **H1** | workspace · `nimwake-hostd --version` · CI(build · clippy · test · aarch64 smoke via qemu) | PR CI 통과, artifact에 aarch64 binary |
| **H2** | supervisor 동등 — 기동 · health · 종료 코드 · backoff · crash loop · 고아 · stop | `supervisor.bats`의 lifecycle 테스트가 hostd로 통과 |
| **H3** | 네트워크 · 저장공간 · 로그 순환 동등, TOML 설정 | `supervisor.bats` 전체가 hostd로 통과 + Rust 단위 테스트 |
| **H4** | 기기 opt-in — `NIMWAKE_HOSTD=1`로 배포, recovery · boot · test-wifi · **24h soak** | 기기 리포트. sh 판과 같은 결과 |
| **H5** | 기본값 전환, sh supervisor 제거 | 72h soak, `nimwake-android v0.2.0` |

H0이 실패하면(예: Android seccomp가 musl static을 막는다) **설계를 다시 한다** — 그래서 맨 앞이다. 대안은 `aarch64-linux-android`(NDK) 타깃이다.

---

## 열린 질문

1. **control 경로:** unix socket(`run/hostd.sock`) vs 지금처럼 `run/stop` 파일. socket이 깔끔하지만 Termux `$PREFIX`의 socket 경로 길이 제한(108바이트)을 넘지 않는지 H0에서 본다.
2. **ping:** ICMP datagram socket(`net.ipv4.ping_group_range`)이 앱 uid에 열려 있는가, 아니면 `/system/bin/ping` 실행인가 — H0.
3. **workspace를 Core와 맞출 것인가:** 같은 crate 버전을 쓰되 lock은 따로 둔다(레포가 다르다). Core가 공용 crate(예: Host Interface 타입)를 내면 그때 의존한다 — 지금은 계약이 작아 복사가 낫다.
4. **soak sampler**는 sh로 둔다 — 측정 도구가 측정 대상과 같은 binary이면 안 된다.

---

← [Phase 2](README.md) · [Phase 1 결정 D-A1–D-A8](../phase-1/03-core-sync.md#이-레포의-설계-결정)
