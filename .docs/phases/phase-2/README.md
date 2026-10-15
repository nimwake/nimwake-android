# Phase 2 — Host Layer를 Rust로 (`nimwake-hostd`) · 집 밖에서 쓰기

> **목표 버전:** `nimwake-android v0.2.0`
> **주제:** supervisor를 Rust binary로 옮긴다 — 같은 계약, 같은 수용 테스트. 그리고 실제로 폰을 서버로 쓰는 데 필요한 ingress · 메모리 임계값
> **시작 조건:** `nimwake-android v0.1.0` (Phase 1 A6). 설계와 H0 spike는 그 전에 해도 된다 — 기기 운영 daemon을 건드리지 않는다
> **상태:** 설계 (2026-10-11)

---

## 한 줄 정의

> Phase 1의 sh supervisor를 바깥 계약(명령 · 상태 파일 · 로그 · 설정)을 그대로 둔 채 Rust `nimwake-hostd`로 바꾸고, 같은 bats와 같은 실기기 검증으로 동등함을 증명한다.

조직의 코어 언어는 Rust다 ([01-repository-setup](../phase-1/01-repository-setup.md)). Phase 1이 sh였던 것은 D-A1 — 실기기 실험 전에는 무엇이 어려운지 몰랐기 때문이다. 이제 안다.

---

## 문서

| 문서 | 내용 |
| ---- | ---- |
| [01. nimwake-hostd](01-nimwake-hostd.md) | 왜 지금인가 · 범위 · 바뀌지 않는 계약 · 구조 · 빌드와 배포 · 마일스톤 H0–H5 · 열린 질문 |
| [02. Ingress](02-ingress.md) | 집 밖에서 닿기 — Tailscale 먼저, 공개는 Cloudflare Tunnel, Caddy 제외 · `X-Forwarded-For` 읽는 법 · I0–I3 ([#41](https://github.com/nimwake/nimwake-android/issues/41)) |
| [03. 배포 · ingress 계약](03-deploy-and-ingress-contract.md) | 소비처(개인 레포)가 이 레포로 폰에 배포한다 — `deploy-app`(release 디렉터리 + SIGHUP 재적재) · ingress provider 플러그인(`check` · `install` · `run` · `health`, 첫 provider `cloudflare`) · 소비처 템플릿 |
| [04. 노출 보안](04-exposure-security.md) | 공개 앱과 LAN 전용 앱을 함께 · 위협(T1 proot는 경계가 아니다 — 앱이 Termux의 SSH 키 · 부팅 스크립트를 읽고 쓴다, T2 LAN 앱 노출 …) · 계층별 방어(Cloudflare · Android `--isolated` · 노출 선언 · Core 앱별 peer 제한 요청) |

## Core에서 넘어온 일

Core가 "실제로 폰을 서버로 쓴다"를 정리하며 이 레포로 넘겼다 — 둘 다 Core가 판단할 수 없는 **기기의 성질**이다 (Core Rule 6 · 7).

| 이슈 | 내용 | 지금 |
| ---- | ---- | ---- |
| [#41](https://github.com/nimwake/nimwake-android/issues/41) | ingress — 터널/프록시 선택 · 기기 설정 · XFF | 결정 [02](02-ingress.md) · provider 계약과 cloudflare(#53) · quick tunnel로 인터넷 → 폰 200, XFF 확인([15](../../validation/15-deploy-and-public-url.md)). 남음: token 모드(사용자 도메인) |
| [#42](https://github.com/nimwake/nimwake-android/issues/42) | `--min-free-memory-mb` 임계값과 그 soak (Core §78 · §80) | rc6에서 §78 · §80 기기 확인, 실사용 512 MB ([14](../../validation/14-memory-admission-eviction.md)). 남음: 실제 앱 장시간 soak |
| [#45](https://github.com/nimwake/nimwake-android/issues/45) | rc6 → 실제 앱 → (Tailscale) → 실사용 soak | rc6(#46) · Next.js 블로그(#48) · 배포 계약 · 공개 URL(#57). 남음: 사용자 도메인 연결 뒤 72h |

## Android 고유와 플랫폼 공통

이 레포의 일은 둘로 나뉜다. 일반 Linux 서버라면 앞의 것은 운영체제가 거의 공짜로 해 준다.

| Android 고유 — root 없는 Android를 서버처럼 | 일반 Linux에서는 |
| ------------------------------------------- | ---------------- |
| supervisor(재기동 · crash loop · 고아 정리) | systemd `Restart=` |
| Termux:Boot · wake lock · 배터리 예외 · phantom process | systemd가 부팅 때 띄움 |
| proot Ubuntu · `--isolated`(약한 격리) | 전용 사용자 + systemd sandbox · 컨테이너(진짜 격리) |
| `ifconfig`로 네트워크 감시(netlink 차단 우회) | NetworkManager · `network-online` |
| 로그 순환 | journald · logrotate |
| 1024 미만 port 불가 → Caddy 제외 | 80 · 443 사용 가능 |

| 플랫폼 공통 — 경로 · 설치 명령 · 감시 주체만 다르다 |
| ---------------------------------------------------- |
| 앱 배포 계약 `deploy-app`(release · SIGHUP 재적재 · rollback · `exposure`) |
| ingress provider 계약(`check` · `install` · `run` · `health`)과 cloudflare provider |
| 소비처 템플릿 · `build-app` · `node.lock` |
| 위협 모델 T2–T7 (T1 proot만 Android 고유) |

**결정: 지금은 나누지 않는다.** 두 번째 플랫폼(라즈베리파이 · VPS 등)이 실제로 생기기 전에 공통 부분을 떼면 쓰는 곳이 하나뿐인 추상화가 된다. 대신 공통 계약은 Android를 모르게 유지한다 — 새 코드가 공통 쪽에 Termux 경로나 `pkg`를 직접 쓰면 그 자리를 플랫폼 쪽으로 미룬다.

떼어 낼 때의 모양 (두 번째 플랫폼이 생길 때):

```text
nimwake             Core (Linux 어디서나)
nimwake-host-kit    배포 계약 · ingress provider · 템플릿 (플랫폼 중립)
nimwake-android     Termux · proot · Termux:Boot · Android 제약 우회
nimwake-linux       systemd unit · 전용 사용자 · sandbox (얇다)
```

Rust `nimwake-hostd`([01](01-nimwake-hostd.md))도 이 경계를 따른다 — 플랫폼 중립 코어 + 플랫폼별 backend(Android · systemd).

---

## Phase 1에서 넘어온 것

Phase 1이 이미 한 것은 다시 하지 않는다 — hostd는 그것을 **동등하게** 옮긴다.

| 기능 | Phase 1 | Phase 2 |
| ---- | ------- | ------- |
| supervisor · 재기동 · crash loop · 고아 정리 | #4 · #15 | H2 |
| 저장공간 감시 · 부족 시 정리 | #26 · #29 | H3 |
| 로그 순환 | #28 | H3 |
| 네트워크 상태 · 복구 hook | #30 · #31 | H3 |
| TOML 설정 (PRD §32) | — (D-A2: `KEY=value`) | H3 |

## 아직 하지 않는 것

- 앱 release 정리 (PRD §19) — Core에 release 구조가 생긴 뒤
- Caddy 프로필 (PRD §39) — root 없이 80 · 443에 bind할 수 없다 ([02](02-ingress.md))
- Backup (PRD §41)

---

← [문서 인덱스](../../README.md) · [Phase 1](../phase-1/README.md)
