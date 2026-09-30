# 01. 레포지토리 셋업

> **Phase 1 — Android MVP** › 레포지토리 셋업
>
> 요구사항 원장: [PRD §3, §7–§9, §16–§17, §35–§36](../../PRD.md), Core [PRD §49](https://github.com/nimwake/nimwake/blob/main/.docs/prd/04-platform/02-android.md)

---

## 1. 이 레포가 만드는 것과 만들지 않는 것

```text
만든다                                   만들지 않는다
─────────────────────────────           ─────────────────────────────
Termux 레이어 shell (host/)              gateway · lifecycle · proxy
Ubuntu proot 레이어 설정 (guest/)        nimwaked 소스 (Core 소유)
설치 · 배포 스크립트                     Core binary 빌드 (Core CI 소유)
실기기 시나리오 스크립트                 Android 앱 (APK, Gradle)
                                         Core 테스트의 재구현
```

이름에 "android"가 있지만 **Gradle/Android Studio 프로젝트가 아니다.** 산출물은 shell 스크립트이고, Core binary는 Core CI가 만든 aarch64 artifact를 받아 쓴다.

### 언어

Nimwake 조직의 코어 언어는 **Rust**다. 이 레포도 그 원칙을 따른다.

| 대상                                 | 언어       | 비고                                                                 |
| ------------------------------------ | ---------- | -------------------------------------------------------------------- |
| Core (`nimwaked`, fixture)           | **Rust**   | Core 레포 소유. 빌드도 Core CI가 한다 → [§5](#5-core-binary-조달)    |
| Host Layer MVP (`host/`, `guest/`)   | POSIX sh   | Termux 기동 · proot 진입 · 재기동 같은 glue. → [D-A1](03-core-sync.md#이-레포의-설계-결정) |
| Host Layer 이후 (`nimwake-hostd`)    | **Rust**   | shell로 부족해지면 Rust binary로 옮긴다 (PRD §8)                     |

Phase 1 동안 이 레포에는 컴파일할 코드가 없다. Rust toolchain은 `nimwake-hostd`를 시작할 때 들인다.

---

## 2. 디렉터리 구조

```text
nimwake-android/
├── README.md
├── Makefile                  # 개발자 진입점 (lint / test / fetch-core / deploy)
├── core.lock                 # 검증 대상 Core commit pin
├── .gitattributes            # LF 강제, *.sh eol=lf
├── .editorconfig
│
├── host/                     # Termux 레이어 — Termux 사용자로 실행
│   ├── bin/nimwake-host      # start | stop | status | logs | doctor
│   ├── lib/                  # config.sh log.sh proot.sh health.sh supervisor.sh
│   ├── boot/10-nimwake       # → ~/.termux/boot/ 로 설치
│   └── host.conf.example
│
├── guest/                    # Ubuntu proot 레이어
│   ├── setup-ubuntu.sh       # proot 안에서 실행: 사용자 · 디렉터리 · binary 배치
│   └── apps/echo/nimwake.toml  # 검증용 manifest (Core fixture `echo-server`)
│
├── install/
│   └── install-android.sh    # 기기에서 실행하는 bootstrap (PRD §36)
│
├── scripts/                  # 개발 머신(macOS / WSL)에서 실행
│   ├── fetch-core.sh         # core.lock SHA의 Core aarch64 artifact → dist/
│   └── deploy.sh             # dist/ host/ guest/ 를 ssh로 기기에 올린다
│
├── tests/
│   ├── unit/                 # bats — host/lib 로직 (backoff, config, crash-loop 판정)
│   └── device/               # 실기기 시나리오 — 개발 머신에서 ssh로 구동
│       ├── lifecycle.sh      # cold → same PID → idle → sleep → new PID
│       ├── recovery.sh       # nimwaked kill → 재기동 → health
│       ├── boot.sh           # 재부팅 후 복구 확인
│       └── soak.sh           # 주기 요청 + RSS / 온도 / orphan 기록
│
├── .docs/
│   ├── PRD.md
│   ├── phases/
│   └── validation/           # 실기기 검증 리포트 (기기 · OS · Core SHA · 결과)
│
└── .github/workflows/
    └── ci.yml                # shellcheck / shfmt / bats
```

`dist/`는 gitignore한다.

### 기기 위 배치 (PRD §17)

```text
Termux   $HOME/.nimwake-host/{host.conf, lib/, logs/, state/, run/}
         $PREFIX/bin/nimwake-host               → lib 진입점 symlink
         $HOME/.termux/boot/10-nimwake

Ubuntu   /opt/nimwake/bin/{nimwaked, echo-server, ...}
         /home/nimwake/.nimwake/apps/<app>/nimwake.toml
```

`/sdcard`는 쓰지 않는다. (PRD §17, §40)

---

## 3. 개발환경 — macOS와 WSL

개발 머신은 **macOS** 또는 **Windows + WSL2(Ubuntu)** 둘 중 하나다. Windows 네이티브(PowerShell, Git Bash)는 지원하지 않는다.
모든 스크립트는 두 환경과 CI(ubuntu)에서 **같은 명령으로** 동작해야 한다.

### 필요한 도구

| 도구                   | macOS                         | WSL2 Ubuntu                                  |
| ---------------------- | ----------------------------- | -------------------------------------------- |
| git, make, ssh, curl   | 기본 / Xcode CLT              | `apt install build-essential openssh-client` |
| gh (GitHub CLI)        | `brew install gh`             | `apt install gh`                             |
| shellcheck, shfmt      | `brew install shellcheck shfmt` | `apt install shellcheck shfmt`             |
| bats-core              | `brew install bats-core`      | `apt install bats`                           |
| adb (선택)             | `brew install android-platform-tools` | `apt install adb`                    |

`make doctor-dev`가 위 도구의 존재와 버전을 확인한다. 교차 컴파일 도구는 필요 없다. → [§5](#5-core-binary-조달)

### WSL 규칙

1. **레포는 WSL 파일시스템에 clone한다.** `~/dev/nimwake/nimwake-android` — `/mnt/c/...` 금지.
   Windows 파일시스템에서는 실행 비트가 사라지고, `git status`가 모든 파일을 mode 변경으로 보며, 빌드가 수 배 느리다.
   지금 `C:\Users\...\nimwake-android`에 있는 체크아웃은 WSL 안으로 다시 clone한다. Core 레포도 같다.
2. `git config --global core.autocrlf false` + `.gitattributes`의 `* text=auto eol=lf`. CRLF가 섞인 shell은 Termux에서 `$'\r': command not found`로 죽는다.
3. 실행 비트는 `git update-index --chmod=+x`로 커밋한다. CI가 `test -x`로 검사한다.
4. **WSL은 USB 장치를 보지 못한다.** 기기 접근은 ssh가 기본이다. adb가 필요하면 Wireless debugging(`adb pair` / `adb connect`)을 쓴다. usbipd-win은 선택.
5. 기본 NAT 네트워킹으로 WSL → 폰(LAN) 방향은 된다. 폰 → WSL 방향이 필요할 때만 `networkingMode=mirrored`를 쓴다. MVP 흐름(ssh push)에는 필요 없다.

### 이식성 규칙 — BSD(macOS)와 GNU(WSL, CI) 공통

개발 머신 스크립트(`scripts/`, `tests/device/`)는 `#!/bin/sh` POSIX로 쓰고, 다음을 쓰지 않는다.

| 쓰지 않는다                     | 대신                                   |
| ------------------------------- | -------------------------------------- |
| `sed -i`                        | 임시 파일로 쓰고 `mv`                  |
| `readlink -f`, `realpath`       | `cd "$(dirname "$0")" && pwd -P`       |
| `date -d`, `date +%N`           | `date +%s` 만                          |
| `grep -P`                       | `grep -E`                              |
| `rsync` (macOS는 openrsync)     | `tar -cf - … \| ssh … tar -xf -`       |
| `timeout`                       | 스크립트 안의 polling loop              |
| bash 전용 문법 (`[[`, 배열)     | POSIX `[`                              |

기기 쪽 스크립트(`host/`, `guest/`, `install/`)는 Termux의 `sh`(dash 계열)와 Ubuntu `sh`에서 돈다. 규칙은 같다.
CI의 `shellcheck -s sh`가 bash 문법을 잡는다. BSD/GNU 옵션 차이는 lint가 못 잡으므로 CI를 macOS runner에서도 한 번 돌린다.

---

## 4. 기기 접근

```text
개발 머신 (macOS / WSL)
     │  ssh -p 8022   (Termux sshd, key auth)
     ▼
Termux ── proot-distro login ubuntu ── nimwaked
```

`~/.ssh/config`:

```text
Host nimwake-phone
    HostName 192.168.x.x
    Port 8022
    User u0_aXXX
    IdentityFile ~/.ssh/nimwake_phone
```

`scripts/deploy.sh`와 `tests/device/*`는 `NIMWAKE_DEVICE`(기본값 `nimwake-phone`) 하나만 받는다.
password 로그인은 끈다. (PRD §40)

---

## 5. Core binary 조달

**빌드는 Core가 소유한다.** 이 레포는 Core CI가 만든 aarch64 artifact를 내려받기만 한다.

Core의 `release.yml`은 `v0.0.5`에 들어가지만, 그때까지 기다리면 실기기 피드백이 `v0.0.4` / `v0.0.5`에 들어갈 수 없다.
그래서 release 전체가 아니라 **aarch64 빌드 job만 Core에 먼저 들이는 것**을 요청했다. → [nimwake#3](https://github.com/nimwake/nimwake/issues/3)

```text
core.lock
   │  repo = nimwake/nimwake
   │  rev  = <full commit SHA>
   │  note = v0.0.3 merge commit
   ▼
Core CI (nimwake#3)  → artifact  nimwake-aarch64-<sha>
   ▼
scripts/fetch-core.sh  → gh run download … → dist/aarch64/
   ├── nimwaked
   ├── echo-server          # 응답 body = 자기 pid → same/new PID를 HTTP로 관측
   ├── crash-server
   ├── group-server         # 손자 process 생성 → process group 정리 관측
   ├── slow-start-server
   └── BUILD_INFO           # Core commit, rustc, target, 빌드 방식
```

- target(`aarch64-unknown-linux-musl` static 제안)과 빌드 방식은 Core가 정한다.
- 기기에서 빌드하지 않는다. (PRD §29)
- branch 이름이 아니라 **commit SHA**로 pin한다. 검증 리포트는 항상 SHA를 남긴다.
- Core `v0.0.5` 이후에는 release artifact로 옮긴다. `fetch-core.sh`의 다운로드 경로만 바뀐다.

### nimwake#3이 A1보다 늦어지면

A0는 binary가 필요 없다. A1 시작 시점에 Core job이 아직 없으면, 개발자가 **Core 레포에서** 한 번 수동 빌드해 `dist/aarch64/`에 둔다.
이 레포에 빌드 스크립트나 workflow를 만들지 않는다. 리포트의 `BUILD_INFO`에 "수동 빌드"를 남긴다.

### private repo 접근

Core와 이 레포 모두 private이다.

- 로컬: `gh auth login`한 개발자 본인의 권한으로 내려받는다.
- CI에서 artifact가 필요해지면 Core `actions:read` 권한만 가진 fine-grained token을 secret으로 둔다. Phase 1 CI(lint · unit)에는 필요 없다.

---

## 6. CI

| workflow         | trigger                              | 내용                                                                                 |
| ---------------- | ------------------------------------ | ------------------------------------------------------------------------------------ |
| `ci.yml`         | PR, push `main`                      | `shellcheck -s sh`, `shfmt -d`, `bats tests/unit`, 실행 비트 검사. ubuntu + macos matrix |

aarch64 binary의 smoke는 Core CI(nimwake#3)가 한다. Android 동작은 어느 CI도 증명하지 않는다.

**실기기 테스트는 CI에 넣지 않는다.** 결과는 `.docs/validation/`에 리포트로 남긴다.
리포트 필수 항목: 기기 모델 · Android 버전 · 제조사 스킨 · Termux 버전과 설치 경로(F-Droid / GitHub) · proot-distro 버전 · Core SHA · 시나리오별 결과 · 측정값.

---

## 7. 버전과 브랜치

- 이 레포는 Core와 **독립된 버전**을 쓴다. Phase 1 완료 = `nimwake-android v0.1.0`.
- 마일스톤은 `A0`–`A6`로 부른다. Core `v0.0.x`와 혼동하지 않기 위해서다.
- 브랜치 · 커밋 · PR 규칙은 Core [Development Rules](https://github.com/nimwake/nimwake/blob/main/.docs/prd/06-conventions/01-development-rules.md)를 따른다.
- 호환 표는 `README.md`에 둔다.

```text
nimwake-android   core.lock          검증 리포트
A2                <v0.0.3 SHA>       validation/01-...
```

---

[Phase 1](README.md) · [02. 마일스톤](02-milestones.md) →
