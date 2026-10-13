# Changelog

이 레포(Android Host Layer)의 변경 기록이다. Core(`nimwaked`)의 변경은 [Core 레포](https://github.com/nimwake/nimwake)가 기록한다.
형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/), 버전은 [SemVer](https://semver.org/lang/ko/)를 따른다.

릴리스할 때 `[Unreleased]`를 `[X.Y.Z] — YYYY-MM-DD`로 바꾸고 `make release-check TAG=vX.Y.Z`로 확인한 뒤 태그를 단다.
태그를 push하면 `.github/workflows/release.yml`이 같은 검사를 거쳐 GitHub Release를 만든다.

## [Unreleased]

`v0.1.0` 후보. Phase 1 — Android MVP. 기기 검증은 [Android 8항목 근거](https://github.com/nimwake/nimwake-android/blob/main/.docs/validation/09-android-acceptance.md)에 있다.

### Core

- `core.lock`으로 Core binary를 commit SHA나 태그에 고정한다. 이 레포는 빌드하지 않고 Core CI의 aarch64 artifact만 받는다 (#2, D-A3 · D-A4)
- 판정 대상: **Core `v0.1.0-rc5`** (#36). rc3 이후 들어온 §77 crash-loop backoff · §78 메모리 입장 제어가 매 요청 경로를 지나 앞선 증거를 돌려 쓸 수 없다 — rc4로 옮겼다가(#34) 런타임이 같은 rc5로. 72h soak은 rc5로 진행 중
- 그 전 검증: Core main `d7c5590` (`nimwaked 0.1.0`, `nimwake-bench` 포함, #16) — 72h soak 결함 없음 (#33). 처음은 `v0.1.0-rc1` (#7)

### Added

- **수동 기동 경로**: `make fetch-core` · `deploy` · `run` · `stop` — Termux → proot Ubuntu 26.04 → `nimwaked` (#2)
- **supervisor** `nimwake-host start | stop | status | logs`: health probe(미등록 Host → 404), 종료 코드 분류, backoff, crash loop → `UNHEALTHY` (#4)
- **부팅 자동 기동**: Termux:Boot의 `00-sshd` · `10-nimwake`, 단계별 `boot.log`, READY 대기 (#3, #6)
- **설치**: `make install` — 기기 설치를 한 번에, 다시 돌려도 바뀌는 것이 없다 (#14)
- **점검**: `make doctor`(기기 — wake lock · 배터리 예외 · phantom process · sshd · 저장공간) (#6, #8, #12), `make doctor-dev`(개발 머신) (#13)
- **실기기 테스트** `tests/device/`: lifecycle · recovery · boot · LAN · Wi-Fi 복구 · 실패 경로 실험 E2–E4 (#2, #5, #15)
- **bench**: `make bench` — Core와 같은 workload를 기기에서 돌려 CI baseline과 비교 (#16)
- **soak**: 기기에서 도는 sampler와 `make soak-start | soak-stop | soak-report` (#5). 재부팅 뒤 이어서 돈다 (#19, #20). `--md` · `--hours N`로 리포트용 표와 구간 판정 (#23)
- **저장공간 감시**: supervisor가 운영 중 10분마다 보고 1 GB 아래면 `supervisor.log`와 Android 알림, `status`에 표시. 부족하면 알리기 전에 순환된 이전 로그를 먼저 지운다 (#26, #29)
- **로그 순환**: `supervisor.log` · `nimwaked.log` · `boot.log`가 20 MB를 넘으면 `.1`–`.3`으로 민다. daemon이 연 채 쓰는 로그도 잃지 않게 copytruncate. 기동 직전과 RUNNING 동안 10분마다 (#28)
- **네트워크 상태 감시** (PRD §13–§14): supervisor가 30초마다 인터페이스 · 게이트웨이(설정 시) · 외부(설정 시)를 보고 `ONLINE` · `DEGRADED` · `OFFLINE`을 바뀔 때만 `supervisor.log`에 남긴다. `status`에 표시. 끊겨도 Nimwake는 내리지 않는다. Android가 netlink · `/proc/net`을 막아 인터페이스는 `ifconfig`로 본다 — `make install`이 `net-tools`를 설치한다 (#30). 돌아올 때 `RECOVERING`을 거치며 `NIMWAKE_NET_ON_RECOVER`(ingress 재연결 등, PRD §15)를 시간 제한을 걸고 돌린다. `make doctor`가 상태와 게이트웨이 설정을 보고, `make test-wifi`가 supervisor 기록을 확인한다 (#31)
- **기기 상태와 보호**: `make device-status` — 설치된 Core binary와 **실제 메모리에 있는** binary, supervisor · 네트워크 · 저장공간, soak 진행과 끝 시각. 이 기기는 여러 작업이 같이 쓴다 — soak 중에는 `make deploy`(`install` 포함) · `make bench`가 거부한다, `FORCE=1`로 강행 (#38)
- **CI**: shellcheck(버전 고정) · 이식성 금지 패턴 검사 · bats, ubuntu는 항상 · macOS는 개발 머신 코드가 바뀔 때 (#9)
- **릴리스**: `CHANGELOG.md`, `make release-check TAG=…`(CHANGELOG 절 · 정식 릴리스면 `core.lock`이 Core 태그에 고정), 태그 push → `release.yml`이 소스 묶음과 sha256을 GitHub Release로 (#27)

### Fixed

- proot가 SIGKILL로 죽으면 남는 고아 `nimwaked`와 application을 supervisor가 정리한다 — 5초 안에 복구 (#15)
- `doctor`가 sshd 실제 적용값(`sshd -T`)으로 비밀번호 로그인을 판정한다 (#8)
- `doctor`가 WSL에서 Windows `adb.exe`로도 동작한다 (#12)
- `fetch-core` · `setup-ubuntu.sh`가 artifact의 모든 binary에 실행 권한을 주고 설치한다 (#16)
- `make deploy`가 끝나면 기기의 stage 디렉터리를 지운다 — 이전 binary가 남아 있었다 (#29)
- `make test-boot`가 부팅이 진행 중이면 READY까지 기다린다 — ssh가 붙자마자 돌면 READY 2초 전에 FAIL했다 (#35). '부팅 직후 모두 SLEEPING' 검사는 soak 중이거나 READY 5분 뒤면 이유를 출력하고 건너뛴다 — sampler가 app을 깨운다 (#39)

### Docs

- PRD를 `.docs/prd/NN-그룹/NN-주제.md`로 나눴다. `§N` 번호는 그대로다 (#25)
- 검증 리포트 `.docs/validation/01–12`: 수동 기준선 · 부팅 · rc1 · recovery · LAN · 실험 · soak(rc1 12h · `d7c5590` 24h · 72h) · bench(`d7c5590` · rc5) · 8항목 근거 (#6, #10, #17, #21, #24, #33, #34, #36). rc4 · rc5 재검증 — Boot · Network recovery (#35, #37)
- Phase 2 설계: supervisor를 Rust `nimwake-hostd`로 — 같은 바깥 계약, `supervisor.bats`가 수용 테스트 (#32)

### Known limits

- 비밀번호 잠금 기기는 재부팅 뒤 잠금을 한 번 풀어야 Termux:Boot가 돈다 (Android 정책)
- 동시 연결 수십부터 무너진다 — 커널 `somaxconn 128`과 proot(ptrace) 비용. 홈서버 규모에서는 문제 없다 ([validation/08](https://github.com/nimwake/nimwake-android/blob/main/.docs/validation/08-core-d7c5590-bench.md))
- 앱 release 정리(PRD §19)는 Core에 release 구조가 생긴 뒤
