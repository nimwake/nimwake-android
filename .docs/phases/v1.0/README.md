# v1.0으로 가는 길

> **목표 버전:** `nimwake-android v1.0.0`
> **한 줄:** 이 레포의 **바깥 계약을 SemVer로 약속**하고, 그것을 실사용 근거로 받친다. 그 뒤로 계약을 깨는 변경은 major에서만 한다
> **상태:** 진행 중 (2026-10-23 · v0.1.1)

---

## v1.0이 약속하는 것

v1.0은 '기능이 다 있다'가 아니라 **'개인 레포가 이 레포를 믿고 고정해도 된다'** 는 뜻이다. 개인 레포(소비처)와 운영자가 기대는 것만 계약이다 — 구현(sh supervisor, 나중의 Rust `nimwake-hostd`)은 계약이 아니다.

| 계약 | 무엇 | 문서 |
| ---- | ---- | ---- |
| 배포 계약 | 앱 디렉터리 모양(`nimwake.toml` · `exposure` · `bundle/`), manifest 규칙(`working_dir` · `NIMWAKE_DATA_DIR`을 쓰지 않는다, 런타임, port, `allow`와 `exposure`), release · rollback · remove의 의미, `NIMWAKE_DATA_DIR`이 남는 범위 | [03](../phase-2/03-deploy-and-ingress-contract.md) · [온보딩](../../../docs/onboarding.ko.md) |
| make 명령 | 이 레포: `install` · `deploy` · `deploy-app` · `rollback-app` · `remove-app` · `apps` · `logs` · `restart` · `ingress-*` · `backup` · `restore-data` · `doctor` · `device-status` · `verify`. 템플릿: `setup` · `deploy` · `rollback` · `ingress` · `token` · `restart` · `status` · `upgrade` | README · 온보딩 |
| `host.conf` 키 | `NIMWAKE_*` 중 `host.conf.example`에 적힌 것 — 이름과 의미 | `host/host.conf.example` |
| ingress provider | `check` · `install` · `run` · `health`와 받는 환경 변수 | [03](../phase-2/03-deploy-and-ingress-contract.md) |
| 기기의 `nimwake` · `nimwake-host` | 명령과 종료 코드. `status`의 사람용 출력은 계약이 아니다 — 기계는 `nimwake status --json`(Core contract 번호)을 읽는다 | |

**계약이 아닌 것:** 로그 문장, soak CSV 열(더하기만 한다), `status`의 사람용 줄, 내부 파일(`run/*`), 검증 스크립트의 출력.

**v1.0 뒤의 규칙:** 위 계약을 깨는 변경은 major. 없애기 전에 한 minor 동안 경고하며 남긴다(deprecation). 더하는 것은 minor.

## 기준 — 무엇이 남았나

| # | 기준 | 상태 | 누가 |
| - | ---- | ---- | ---- |
| 1 | **배포가 스스로 확인한다** — 새 release가 실제로 응답하지 않으면 이전 release로 되돌린다 | ✓ | #79 |
| 2 | **앱 로그를 개발 머신에서** — `make logs APP=…` | ✓ | #80 |
| 3 | **사람 없이 도는 검증을 한 번에** — `make verify`(lifecycle · recovery · LAN · 실제 앱) + 요약 | ✓ | #81 |
| 4 | **개인 레포의 업그레이드가 명령 하나** — 템플릿 `make upgrade REV=…` | □ | 자동 |
| 5 | **계약 문서** — 위 표를 영문 기본 · 국문으로, 어긋나면 CI가 잡는다 | □ | 자동 |
| 6 | 관측 — Core 상태(socket) · 전원 · 사라진 supervisor · 저장공간 · 네트워크 | ✓ | #60 · #73 · #74 |
| 7 | 복구 — 초기화 기기에 `make install` 한 번 · 설정 · 앱 데이터 백업과 복원 | ✓ | #63 · #64 · #75 |
| 8 | 보안 — 격리(`--isolated`) · 노출 선언 · `allow` · 토큰은 표준 입력으로만 · 비밀은 레포 밖 | ✓ | #56 · #61 |
| 9 | 앱 종류 — Next.js · 정적 사이트 · 상태를 가진 앱(데이터 디렉터리) · 주기 작업 · 웹훅 | ✓ | #68 · #75 · #76 |
| 10 | **실사용 근거** — 벽 충전기로 실제 앱 72h soak(전원 열 포함), 내 도메인(token 모드)으로 공개, 그 상태에서 Wi-Fi 복구 | □ | **사람** — 충전기 · Cloudflare 계정 · Wi-Fi 조작 |

1–5를 먼저 끝내고(사람 없이), 10의 근거가 모이면 `v1.0.0`을 태그한다.

## v1.0에 넣지 않는 것

- **Rust `nimwake-hostd`** ([Phase 2 01](../phase-2/01-nimwake-hostd.md)) — 계약을 바꾸지 않고 구현만 바꾸는 일이라 v1.0 뒤 minor로 할 수 있다. 빌드 방식(D-A9)은 사용자 결정이다
- Tailscale(사용자 결정: 나중에), Caddy(root 없이 80 · 443 불가), 두 번째 플랫폼([Phase 2](../phase-2/README.md#android-고유와-플랫폼-공통))

---

← [문서 인덱스](../../README.md) · [Phase 2](../phase-2/README.md)
