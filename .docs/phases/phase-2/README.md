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

## Core에서 넘어온 일

Core가 "실제로 폰을 서버로 쓴다"를 정리하며 이 레포로 넘겼다 — 둘 다 Core가 판단할 수 없는 **기기의 성질**이다 (Core Rule 6 · 7).

| 이슈 | 내용 | 지금 |
| ---- | ---- | ---- |
| [#41](https://github.com/nimwake/nimwake-android/issues/41) | ingress — 터널/프록시 선택 · 기기 설정 · XFF | 결정 제안 [02](02-ingress.md). XFF 확인은 §81이 든 Core(rc5 이후) |
| [#42](https://github.com/nimwake/nimwake-android/issues/42) | `--min-free-memory-mb` 임계값과 그 soak (Core §78 · §80) | `host.conf` 전달 · soak의 MemAvailable 기록 (#43). 임계값은 데이터로, §80 eviction은 rc5 이후 Core |

둘 다 **v0.1.0 판정(rc5) 뒤 `core.lock`을 올려야** 끝까지 갈 수 있다 — §80 · §81은 rc5에 없다.

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
