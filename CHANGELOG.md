# Changelog

이 레포(Android Host Layer)의 변경 기록이다. Core(`nimwaked`)의 변경은 [Core 레포](https://github.com/nimwake/nimwake)가 기록한다.
형식은 [Keep a Changelog](https://keepachangelog.com/ko/1.1.0/), 버전은 [SemVer](https://semver.org/lang/ko/)를 따른다.

릴리스할 때 `[Unreleased]`를 `[X.Y.Z] — YYYY-MM-DD`로 바꾸고 `make release-check TAG=vX.Y.Z`로 확인한 뒤 태그를 단다.
태그를 push하면 `.github/workflows/release.yml`이 같은 검사를 거쳐 GitHub Release를 만든다.

## [Unreleased]

### Added

- **정적 빌드 사이트** — Vite · Vite + TanStack Router · Docusaurus 같은 정적 사이트를 Next.js 앱처럼 `make deploy APP=…`로. `build-app.sh`가 `next.config.*`가 없으면 빌드 결과(`dist/` · `build/` · `out/`)를 `site/`에, 정적 서버 `runtime/static-server.mjs`(Node 내장 모듈만 · SPA fallback · 해시 파일 immutable 캐시 · ETag · 경로 탈출 · 점 파일 차단)를 `server.mjs`로 묶는다. 템플릿 예시 `apps/site`. 폰에서 cold 1.1s · warm 40–80ms · RSS 58 MB

## [0.1.0] — 2026-10-15

첫 릴리스. Android 폰(root 없음, Termux)을 Nimwake 서버로 — 설치 · 부팅 자동 기동 · 감시와 복구, 그 위에 내 앱을 배포하고 공개하는 계약까지. 기기 검증은 [Android 8항목 근거](https://github.com/nimwake/nimwake-android/blob/main/.docs/validation/09-android-acceptance.md)와 [validation/16](https://github.com/nimwake/nimwake-android/blob/main/.docs/validation/16-core-rc7.md) · [17](https://github.com/nimwake/nimwake-android/blob/main/.docs/validation/17-install-wiped-device.md)에 있다.

### Core

- `core.lock`으로 Core binary를 commit SHA나 태그에 고정한다. 이 레포는 빌드하지 않고 Core CI의 aarch64 artifact만 받는다 (#2, D-A3 · D-A4)
- **Core `v0.1.0`** (`b6fec40`) — rc7(`1e2bf91`)과 런타임이 같다(그 뒤는 기본값 테스트 · dependabot · 버전). 기기에서 lifecycle · 블로그 확인
- rc7에서 #59의 넷: 배치 · 초기화 기기 `make install` · 태그 binary로 lifecycle · recovery · 재부팅 · Wi-Fi · §82 앱별 peer 제한(`[server] allow`) · §83 header 읽기 15초 (#61–#63). 그 전 rc6 (`4f7d991`, #46) — §79 SIGUSR1 상태 스냅샷 · §80 유휴 eviction · §81 `X-Forwarded-For` · `--version`
- 판정 대상이었던 rc5 (#36): rc3 이후 들어온 §77 crash-loop backoff · §78 메모리 입장 제어가 매 요청 경로를 지나 앞선 증거를 돌려 쓸 수 없었다 — rc4로 옮겼다가(#34) 런타임이 같은 rc5로. soak은 24h에서 멈췄다(결함 0, 실제 앱 우선 — #45)
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
- **`allow`와 `exposure` 맞춤** (Core §82): 배포 계약 검사가 public 앱의 `allow`에 127.0.0.1이 빠지면 거부(터널 요청이 모두 403), lan 앱에 `allow`가 없거나 127.0.0.1이 들어 있으면 경고한다 (validation/16)
- **백업**: `make backup`이 기기에만 있는 `host.conf`와 soak 기록을 개발 머신(레포 밖)으로, `make install`이 초기화한 기기에 `host.conf`를 되살린다. 토큰은 폰 밖으로 꺼내지 않는다 (validation/17)
- **사라진 supervisor 감지**: supervisor가 감시 주기마다 `run/heartbeat`를 남기고, 다음 `start`가 이전 실행이 종료 기록 없이 끝났으면 마지막 heartbeat와 부팅 시각으로 **재부팅**인지 **폰이 켜진 채 죽었는지**(Android가 Termux를 내림 — Termux:Boot가 다시 돌지 않는다)를 `supervisor.log` · `status`(`last-lost`) · `make doctor`에 남긴다 (10-15 기기에서 로그가 아무 기록 없이 끊긴 일에서)
- **CI**: shellcheck(버전 고정) · 이식성 금지 패턴 검사 · bats, ubuntu는 항상 · macOS는 개발 머신 코드가 바뀔 때 (#9)
- **릴리스**: `CHANGELOG.md`, `make release-check TAG=…`(CHANGELOG 절 · 정식 릴리스면 `core.lock`이 Core 태그에 고정), 태그 push → `release.yml`이 소스 묶음과 sha256을 GitHub Release로 (#27)
- **메모리 임계값**: `host.conf` `NIMWAKE_MIN_FREE_MEMORY_MB` → Core `--min-free-memory-mb` (§78 입장 제어 · §80 eviction, 기기에서 둘 다 확인) · soak이 MemAvailable을 기록 (#43, validation/14)
- **실제 앱**: 예시 Next.js 블로그(`examples/blog`) — 개발 머신에서 standalone으로 빌드(`make app-blog`, 네이티브 모듈이 섞이면 멈춘다) · 폰에는 Node(`guest/node.lock`, sha256 확인)와 묶음만 · `make test-app`(cold · warm · RSS · 유휴 정지 · SIGUSR1). 폰에서 cold 1.6s · warm 30–50ms · RSS 약 95 MB (#47, #48, validation/13). soak이 실제 앱을 잰다 — `SOAK_HOST` · `SOAK_PATH` (#49)
- **앱 배포 계약** (Phase 2 03): 소비처 앱(`nimwake.toml` — `working_dir` 없이 · `bundle/` · `exposure`)을 `make deploy-app APP=…`이 `releases/<id>`에 놓고 SIGHUP 재적재 — 다른 앱은 그대로, 거부되면 되돌림, release 3개 보관. `rollback-app` · `remove-app` · `apps` (#52)
- **ingress provider 플러그인** (Phase 2 03): `host/ingress/<provider>/{check,install,run,health}` — supervisor가 daemon과 따로 감시 · 78은 재기동 안 함 · 네트워크 복구 때 다시 붙인다. 첫 provider **cloudflare**(token · quick). `make ingress-enable` · `ingress-token`(표준 입력으로만, `secrets/` 0600) · `ingress-disable` · `restart` (#53, #54)
- **소비처 템플릿** `examples/consumer-template` — 개인 레포의 출발점: 이 레포 버전 고정 · Makefile(setup · deploy · rollback · ingress · token · restart · status) · Cloudflare 공개 순서 (#54)
- **노출 보안** (Phase 2 04): daemon과 앱을 `proot-distro --isolated`로(기본) — 격리하지 않으면 앱이 Termux의 SSH 키 · 부팅 스크립트를 읽고 쓴다(기기에서 확인). 앱마다 `exposure`(public · lan, 기본 lan) — ingress는 public 앱만. doctor가 노출 · 격리를 보인다 (#55, #56). Core에 앱별 peer 제한을 요청 (nimwake#66)

### Fixed

- proot가 SIGKILL로 죽으면 남는 고아 `nimwaked`와 application을 supervisor가 정리한다 — 5초 안에 복구 (#15)
- `doctor`가 sshd 실제 적용값(`sshd -T`)으로 비밀번호 로그인을 판정한다 (#8)
- `doctor`가 WSL에서 Windows `adb.exe`로도 동작한다 (#12)
- `fetch-core` · `setup-ubuntu.sh`가 artifact의 모든 binary에 실행 권한을 주고 설치한다 (#16)
- `make deploy`가 끝나면 기기의 stage 디렉터리를 지운다 — 이전 binary가 남아 있었다 (#29)
- `make test-boot`가 부팅이 진행 중이면 READY까지 기다린다 — ssh가 붙자마자 돌면 READY 2초 전에 FAIL했다 (#35). '부팅 직후 모두 SLEEPING' 검사는 soak 중이거나 READY 5분 뒤면 이유를 출력하고 건너뛴다 — sampler가 app을 깨운다 (#39)
- 기기 검증에서 찾은 셋 (#57, validation/15): `deploy-app`의 원격 인자가 빈 값에서 밀렸다(ssh가 인자를 공백으로 잇는다) · provider가 `host.conf`의 `NIMWAKE_INGRESS_*`를 못 받았다 · ingress pid가 바깥 서브셸이라 cloudflared가 고아로 남았다

### Docs

- PRD를 `.docs/prd/NN-그룹/NN-주제.md`로 나눴다. `§N` 번호는 그대로다 (#25)
- 검증 리포트 `.docs/validation/01–15`: 수동 기준선 · 부팅 · rc1 · recovery · LAN · 실험 · soak(rc1 12h · `d7c5590` 24h · 72h) · bench(`d7c5590` · rc5) · 8항목 근거 · 실제 앱(13) · 메모리 임계값(14) · 배포와 공개 URL(15) (#6, #10, #17, #21, #24, #33, #34, #36, #48, #50, #57). rc4 · rc5 재검증 — Boot · Network recovery (#35, #37)
- Phase 2 설계: supervisor를 Rust `nimwake-hostd`로 — 같은 바깥 계약, `supervisor.bats`가 수용 테스트 (#32) · ingress 결정(02, #44) · 배포 · ingress 계약(03, #51) · 노출 보안(04, #55)

### Known limits

- 비밀번호 잠금 기기는 재부팅 뒤 잠금을 한 번 풀어야 Termux:Boot가 돈다 (Android 정책)
- 동시 연결 수십부터 무너진다 — 커널 `somaxconn 128`과 proot(ptrace) 비용. 홈서버 규모에서는 문제 없다 ([validation/08](https://github.com/nimwake/nimwake-android/blob/main/.docs/validation/08-core-d7c5590-bench.md))
- 앱 release 정리(PRD §19)는 Core에 release 구조가 생긴 뒤 — 소비처 앱은 `deploy-app`이 release 3개를 관리한다
- **proot는 보안 sandbox가 아니다.** `--isolated`가 Termux 파일을 감추지만 ptrace 기반이라 탈출 취약점이 있으면 넘어간다 — root 없는 Android의 한계 (Phase 2 04)
- LAN 전용 앱은 manifest에 `allow`(LAN 대역)를 적어야 터널 요청이 403이 된다 — 적지 않으면 'Cloudflare에 그 이름을 등록하지 않는다'로만 막힌다. 배포 계약 검사가 경고한다
- ingress token 모드(내 도메인)와 네트워크 복구 때의 재연결은 아직 기기에서 보지 못했다 (validation/15)
