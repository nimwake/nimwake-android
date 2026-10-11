# Phase 2 — Host Layer를 Rust로 (`nimwake-hostd`)

> **목표 버전:** `nimwake-android v0.2.0`
> **주제:** supervisor를 Rust binary로 옮긴다 — 같은 계약, 같은 수용 테스트
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
- Optional profile (Tailscale · Cloudflare Tunnel · Caddy, PRD §37–§39) — 복구 hook(#31)이 붙을 자리만 있다
- Backup (PRD §41)

---

← [문서 인덱스](../../README.md) · [Phase 1](../phase-1/README.md)
