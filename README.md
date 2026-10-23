# nimwake-android

Android 스마트폰을 [Nimwake](https://github.com/nimwake/nimwake) 실행 노드로 쓰기 위한 **Host Layer**.
Android 재부팅 · daemon crash · 네트워크 끊김을 사람 손 없이 넘기고, 그 위에서 Nimwake Core가 일반 Linux에서처럼 돌게 한다.

```text
Android
  └── Termux ── Termux:Boot (00-sshd · 10-nimwake) · wake lock
        └── nimwake-host (supervisor)          ← 이 레포
              ├── ingress provider (선택)       ← cloudflared 등 — 집 밖에서 닿게
              └── proot-distro Ubuntu (--isolated)
                    └── nimwaked               ← Core (빌드는 Core CI)
                          └── applications     ← 소비처(개인 레포)가 make deploy-app으로
```

이 레포는 Core 기능을 다시 구현하지 않는다. Android 앱(APK)도 아니다 — Termux 위의 POSIX shell과, Core가 내놓은 aarch64 binary를 배치하는 스크립트다. 조직의 코어 언어는 Rust이고, Host Layer MVP는 shell이다 (이후 `nimwake-hostd`는 Rust).

**이 레포가 하는 일은 둘이다.** 하나는 root 없는 Android를 Linux 서버처럼 쓰게 만드는 것(Termux:Boot · supervisor · proot · Android 제약 우회)이고, 다른 하나는 그 위에 **내 앱을 배포하고 공개하는 계약**(`deploy-app` · ingress provider)이다. 앞의 것은 Android 고유이고, 뒤의 것은 플랫폼 중립으로 설계했다 → [Phase 2](.docs/phases/phase-2/README.md#android-고유와-플랫폼-공통)

## 내 앱을 폰에 배포하기

내 앱 · 도메인 · 토큰은 **개인 레포**에 둔다 — [`examples/consumer-template`](examples/consumer-template/README.md)을 복사해 시작한다. 처음이면 **[온보딩 가이드](docs/onboarding.ko.md)** ([English](docs/onboarding.md))를 따라간다.

```sh
make setup                      # 이 레포를 고정한 버전으로
make deploy APP=blog            # 빌드 → 폰 → SIGHUP 재적재 (다른 앱은 그대로)
make ingress && make token && make restart   # Cloudflare Tunnel로 공개 (선택)
```

공개 앱과 LAN 전용 앱을 한 폰에 함께 둘 수 있다 — 앱마다 `exposure`(public · lan). 보안: [Phase 2 04](.docs/phases/phase-2/04-exposure-security.md)

## 상태

**최신 `v0.2.0`** (2026-10-24) — 배포 확인과 자동 롤백 · `make logs` · `make verify` · `make upgrade` · [계약](docs/contract.ko.md). 다음은 `v1.0.0` — [남은 것](.docs/phases/v1.0/README.md)은 사람이 필요한 실사용 근거뿐. 그 전 `v0.1.1`(2026-10-23) — 정적 사이트 · 앱 데이터 디렉터리 · 배터리 감시 · Core control socket. 첫 릴리스 `v0.1.0`(2026-10-15) — Core `v0.1.0`과 함께. Core의 v0.1.0은 이 레포의 **Android 8항목** 검증을 근거로 태깅됐다. 이제 실사용하며 고친다.

```text
Install ✓   Boot recovery ✓   Cold start ✓   Scale-to-zero ✓
Daemon recovery ✓   Network recovery ✓   24h soak ✓   72h soak ✓
```

→ [Android 8항목 근거](.docs/validation/09-android-acceptance.md) · [마일스톤 현황](.docs/phases/phase-1/02-milestones.md) · [검증 리포트](.docs/validation/)

### Core 호환

| nimwake-android | Core | 검증 |
| --------------- | ---- | ---- |
| **`v0.2.0`** · **`v0.1.1`** · `main` | **`v0.1.4`** (`bf79367`, release asset) | control socket(§85 · §86) — lifecycle · recovery · 실제 앱 ✓ ([18](.docs/validation/18-core-v0.1.4-control-socket.md), #71) |
| **`v0.1.0`** | `v0.1.0` (`b6fec40`, release asset) | rc7과 런타임이 같다 — 기기에서 lifecycle · 블로그 확인 · soak 55h(배터리 방전으로 멈춤, 결함 0) |
| #65 이전 | `v0.1.0-rc7` (`1e2bf91`, release asset) | 10-15 배치 — lifecycle · recovery · LAN · 실제 앱 ✓, §82 peer 제한 · §83 header 상한 ✓ ([16](.docs/validation/16-core-rc7.md), #59). 재부팅 · Wi-Fi ✓ · 초기화 기기 `make install` ✓ ([17](.docs/validation/17-install-wiped-device.md)) |
| #61 이전 | `v0.1.0-rc6` (`4f7d991`, release asset) | [13](.docs/validation/13-blog-on-device.md) · [14](.docs/validation/14-memory-admission-eviction.md) · [15](.docs/validation/15-deploy-and-public-url.md) — 실제 앱 · 메모리 · 배포 · 공개 URL |
| #46 이전 | `v0.1.0-rc5` (`f75b6d2`, release asset) | [12](.docs/validation/12-core-rc5-bench.md) · §50 **다섯 항목 모두** · 재부팅 ✓ · soak 24h에서 멈춤(결함 0) |
| #34 이전 | main `d7c5590` (`nimwaked 0.1.0`, release.yml run artifact) | [08](.docs/validation/08-core-d7c5590-bench.md) · [10](.docs/validation/10-soak-d7c5590-24h.md) · [11](.docs/validation/11-soak-d7c5590-72h.md) — 24h · 72h soak ✓ |
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
| `make soak-start HOURS=24` · `soak-report` · `soak-stop` | 기기에서 도는 장시간 soak (`SOAK_HOST=blog.local SOAK_PATH=/api/whoami`로 실제 앱) |
| `make backup` · `restore-data` | 기기에만 있는 `host.conf` · soak 기록 · 앱 데이터(`/home/nimwake/data`) → 개발 머신 `~/.nimwake-backup/<기기>`. 초기화한 기기면 `make install`이 `host.conf`를, `make restore-data`가 앱 데이터를 되살린다 (토큰은 가져오지 않는다) |
| `make device-status` | 기기에 지금 무엇이 도는가 — Core(설치 · 메모리) · supervisor · soak. 배포 전에 먼저 |
| `make restart` | supervisor를 다시 띄운다 — `host.conf` 변경 반영 (soak 중 거부) |
| `make verify` | 사람 손이 필요 없는 기기 검증 전부 — doctor · Core socket · 전원 · lifecycle · recovery · LAN · 실제 앱. 표와 단계별 로그를 `dist/verify/<UTC>/`에. soak 중 거부 |
| `make logs APP=… [FOLLOW=1]` | 그 앱의 출력(stdout · stderr)과 Core의 사건만 — 시각 · 종류 · 내용. APP 없이는 supervisor · daemon 로그 |
| `make deploy-app APP=…` · `rollback-app NAME=…` · `remove-app NAME=…` · `apps` | 소비처 앱 배포 계약 — release · SIGHUP 재적재 · 노출 |
| `make ingress-enable INGRESS=cloudflare [MODE=quick]` · `ingress-token < 파일` · `ingress-disable` | 집 밖에서 닿게 — provider 설치 · 토큰(표준 입력으로만) |
| `make app-blog` · `make test-app HOST=…` | 예시 Next.js 앱 빌드 · 실제 앱 측정 |

기기에서는 `nimwake-host start | stop | status | logs`.

## 구조

```text
host/bin/      nimwake-host (supervisor CLI) · nimwake-soak (sampler)      ← 기기, Termux
host/lib/      config · policy(재기동 판단) · supervisor · logs · network · ingress
host/boot/     00-sshd · 10-nimwake · 20-soak                             ← ~/.termux/boot/
host/ingress/  provider 플러그인 — cloudflare/{check,install,run,health}
guest/         setup-ubuntu.sh · node.lock · apps/echo · apps/blog (검증용)  ← proot Ubuntu
scripts/       fetch-core · deploy · apps · ingress · build-app · doctor · …  ← 개발 머신
examples/      blog (예시 Next.js) · consumer-template (개인 레포의 출발점 — Next.js · 정적 사이트)
runtime/       static-server.mjs — 정적 사이트 묶음의 server.mjs (Node 내장 모듈만)
tests/unit/    bats — 판단 로직, 가짜 daemon · 가짜 provider로 감시 루프, 배포 계약, soak 요약
tests/device/  실기기 시나리오 — CI에 넣지 않고 결과는 .docs/validation/에
.docs/         PRD · phases(계획) · validation(실기기 리포트)
```

## 문서

- [PRD](.docs/prd/README.md) — Android Host Layer 요구사항
- [Phase 1](.docs/phases/phase-1/README.md) — 레포 셋업 · 마일스톤 · Core 동기화
- [Phase 2](.docs/phases/phase-2/README.md) — Rust hostd 설계 · ingress · 배포 계약 · 노출 보안
- [계약](docs/contract.ko.md) ([English](docs/contract.md)) — 개인 레포와 운영자가 기대도 되는 것. v1.0부터 SemVer
- [온보딩](docs/onboarding.ko.md) ([English](docs/onboarding.md)) — 개인 레포를 만들어 내 앱을 폰에 올리고 공개하기. 영문이 기본, 두 판은 `make lint`가 맞춰 본다
- [검증 리포트](.docs/validation/) — 새 리포트는 [00-template](.docs/validation/00-template.md)에서
