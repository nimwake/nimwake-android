# nimwake-android

Android 스마트폰을 [Nimwake](https://github.com/nimwake/nimwake) 실행 노드로 쓰기 위한 **Host Layer**.
Android 재부팅 · daemon crash · 네트워크 끊김을 사람 손 없이 넘기고, 그 위에서 Nimwake Core가 일반 Linux에서처럼 돌게 한다.

```text
Android
  └── Termux ── Termux:Boot (00-sshd · 10-nimwake) · wake lock
        └── nimwake-host (supervisor)          ← 이 레포
              └── proot-distro Ubuntu
                    └── nimwaked               ← Core (빌드는 Core CI)
                          └── applications
```

이 레포는 Core 기능을 다시 구현하지 않는다. Android 앱(APK)도 아니다 — Termux 위의 POSIX shell과, Core가 내놓은 aarch64 binary를 배치하는 스크립트다. 조직의 코어 언어는 Rust이고, Host Layer MVP는 shell이다 (이후 `nimwake-hostd`는 Rust).

## 상태

Phase 1 (`nimwake-android v0.1.0`) 진행 중. Core `v0.1.0`은 이 레포의 **Android 8항목** 검증 리포트를 기다린다.

```text
Install ✓   Boot recovery ✓   Cold start ✓   Scale-to-zero ✓
Daemon recovery ✓   Network recovery ✓   24h · 72h soak (진행 중, 10-12 종료)
```

→ [마일스톤 현황](.docs/phases/phase-1/02-milestones.md) · [검증 리포트](.docs/validation/)

### Core 호환

| nimwake-android | Core | 검증 |
| --------------- | ---- | ---- |
| `main` | main `d7c5590` (`nimwaked 0.1.0`, release.yml run artifact) | [08](.docs/validation/08-core-d7c5590-bench.md) · 72h soak 진행 중 |
| #16 이전 | `v0.1.0-rc1` (`17975b1`) | [03](.docs/validation/03-core-v0.1.0-rc1.md) · [04](.docs/validation/04-a2-recovery.md) · [05](.docs/validation/05-a5-network.md) · [06](.docs/validation/06-a1-experiments.md) · [07](.docs/validation/07-soak-rc1-12h.md) |

`core.lock`이 Core를 commit SHA로 고정한다. `make fetch-core`는 그 release asset을 받아 `BUILD_INFO`의 commit을 확인한다.

## 개발 환경

**macOS** 또는 **Windows + WSL2(Ubuntu)**. Windows 네이티브 셸(PowerShell, Git Bash)은 쓰지 않는다.
WSL에서는 레포를 WSL 파일시스템(`~/dev/...`)에 clone한다 — `/mnt/c`에서는 실행 비트가 사라지고 CRLF가 섞인다.

| 도구 | 용도 |
| ---- | ---- |
| `git`, `make`, `ssh`, `curl`, `gh` | 기본 · Core release 받기 |
| ShellCheck **0.11.0** | `make lint` (CI와 같은 버전) |
| bats-core | `make test` |
| adb (선택) | `make doctor`의 phantom process · 배터리 최적화 점검 |

→ 자세히: [01. 레포지토리 셋업 §3](.docs/phases/phase-1/01-repository-setup.md#3-개발환경--macos와-wsl) (이식성 규칙 포함)

## 기기 준비

사람이 하는 것은 ssh가 열릴 때까지다. 나머지는 `make install`이 한다 (멱등).

1. **Termux · Termux:Boot · Termux:API를 같은 출처(F-Droid)에서** 설치한다. 서명이 달라 출처를 섞으면 애드온이 동작하지 않는다. Termux:Boot는 한 번 연다.
2. Termux: `pkg install -y openssh && passwd && sshd && whoami`
3. 개발 머신 `~/.ssh/config`에 `Host nimwake-phone` (HostName, Port 8022, User, IdentityFile) → `ssh-copy-id -i <키>.pub nimwake-phone`
4. `make install` — 패키지 · proot Ubuntu 26.04 · **키 로그인만 허용하는 sshd** · deploy · supervisor · doctor.
   ssh가 아직 안 되면 위 단계를 안내하고 멈춘다.
5. 배터리 최적화 예외 · Android 12–13 phantom process 제한 해제는 adb가 필요하다 — `make doctor`가 점검한다.

비밀번호 잠금이 있는 기기는 재부팅 후 **잠금을 한 번 풀어야** Termux:Boot가 돈다. 패키지 설치 중에는 재부팅하지 않는다.

## 명령

모두 개발 머신에서 실행한다. 기기는 `NIMWAKE_DEVICE`(기본 `nimwake-phone`) ssh로 다룬다.

| 명령 | 하는 일 |
| ---- | ------- |
| `make doctor-dev` | 개발 머신 점검 — 도구 · ShellCheck 버전 · WSL 경로 · 실행 비트 · ssh 설정 (처음에 한 번) |
| `make install` | 기기 설치 (멱등) — 패키지 · proot Ubuntu · 키 로그인 sshd → deploy → supervisor → doctor. soak 중에는 돌리지 않는다 |
| `make fetch-core` | `core.lock`의 Core aarch64 binary → `dist/aarch64/` |
| `make deploy` | binary · manifest(proot Ubuntu), `nimwake-host`, Termux:Boot 스크립트 설치. `host.conf`는 있으면 보존 |
| `make doctor` | 설치 · 운영 상태 `[OK]/[WARN]/[FAIL]/[MANUAL]` |
| `make stop` / `make run` | 내리기 / foreground로 띄우기 (평소에는 부팅 때 supervisor가 띄운다) |
| `make lint` · `make test` | ShellCheck + 이식성 검사 · bats (기기 없이) |
| `make test-device` | 기기 loopback lifecycle |
| `make test-boot` | 재부팅 후: 마지막 부팅 READY · SLEEPING · lifecycle |
| `make test-recovery` | `kill -9` → 재기동 · exit 78 → UNHEALTHY · stop 잔존 0 |
| `make test-lan` · `make test-wifi` | LAN lifecycle · 동시 cold start · Wi-Fi 복구 (`NIMWAKE_LISTEN=0.0.0.0:8080` 필요) |
| `make test-experiments` | 실패 경로 실험 E2–E4 + 고아 정리 — 별도 경로 · 포트의 실험 daemon이라 운영 daemon · soak과 섞이지 않는다 |
| `make soak-start HOURS=24` · `soak-report` · `soak-stop` | 기기에서 도는 장시간 soak |

기기에서는 `nimwake-host start | stop | status | logs`.

## 구조

```text
host/bin/      nimwake-host (supervisor CLI) · nimwake-soak (sampler)      ← 기기, Termux
host/lib/      config · policy(재기동 판단) · supervisor
host/boot/     00-sshd · 10-nimwake                                       ← ~/.termux/boot/
guest/         setup-ubuntu.sh · apps/echo (검증용 manifest)              ← proot Ubuntu
scripts/       fetch-core · deploy · doctor · run · stop · check-portability   ← 개발 머신
tests/unit/    bats — 판단 로직, 가짜 daemon으로 감시 루프, soak 요약
tests/device/  실기기 시나리오 — CI에 넣지 않고 결과는 .docs/validation/에
.docs/         PRD · phases(계획) · validation(실기기 리포트)
```

## 문서

- [PRD](.docs/PRD.md) — Android Host Layer 요구사항
- [Phase 1](.docs/phases/phase-1/README.md) — 레포 셋업 · 마일스톤 · Core 동기화
- [검증 리포트](.docs/validation/) — 새 리포트는 [00-template](.docs/validation/00-template.md)에서
