# Phase 1 — Android MVP

> **목표 버전:** `nimwake-android v0.1.0`
> **주제:** Install · Start · Recovery · Boot · Power · Real lifecycle
> **시작 조건:** Core `v0.0.3 — HTTP + Scale-to-Zero` merge
> **상태:** 진행 중 — A0 · A1 · A2 · A3 · A5 완료, A4는 초기화 기기 검증 남음, **72h soak 진행 중** (Core `d7c5590`, 2026-10-09 13:44 → 10-12 13:44)
> Core `v0.1.0`은 이 레포의 Android 8항목을 기다린다 — 7개 충족 (24h soak ✓), 72h soak 남음. → [Android 8항목 근거](../../validation/09-android-acceptance.md) · [02 현황](02-milestones.md#현황--2026-10-09)

---

## 한 줄 정의

> Android 재부팅과 daemon crash를 사람 손 없이 넘기고, 그 위에서 Core lifecycle이 그대로 동작함을 실기기로 증명한다.

이 레포는 **Host Adapter / Supervisor**다. Core 기능을 다시 구현하지 않는다. → [PRD §3](../../prd/01-product/02-principles-and-goals.md)

---

## 왜 Core `v0.0.3` 직후인가

Android에서 검증할 것은 Nimwake 내부 알고리즘이 아니라 **Android 환경에서 Core lifecycle이 살아남는가**다.
그 질문은 실제 HTTP → spawn → readiness → proxy → idle → SIGTERM이 한 줄로 이어진 `v0.0.3`부터 물을 수 있다.

반대로 `/proc` 가시성, proot 아래의 signal · process group, Android sleep, Termux background kill은
Linux CI로 재현할 수 없다. `v0.1.0` 이후에 발견하면 구조 변경이 되고, 그 전에 발견하면 수정이 된다.

```text
Core                                   Android (이 레포)

v0.0.1  Lifecycle Foundation
v0.0.2  Process Runtime
v0.0.3  HTTP + Scale-to-Zero
v0.0.4  E2E + Perf baseline
v0.0.5  Stress + Qualification ──────▶ A0  Repository bootstrap (최소판)
   │    (+ host interface §74)         A1  Manual baseline + 실험
   │                                   A2  Start + Supervisor
   │         ◀──── 실험 결과 · 이슈 ──── A3  Boot + Power
   │                                   A4  Install automation
   │    (v0.0.4 workload 비교) ────────▶ A5  LAN lifecycle + 24h soak
   │                                   A6  72h soak
   ▼                                        │
v0.1.0  Core MVP  ◀──────── Android 체크리스트 ┘
```

계획은 `v0.0.3` 직후 시작을 전제했지만 Core가 `v0.0.5`까지 먼저 나갔다.
실기기 피드백은 모두 `v0.1.0` 판정으로 모인다. → [03 계획과 달라진 점](03-core-sync.md#계획과-달라진-점)

Core와 이 레포의 동기화 지점, Core에 요청한 변경(빌드 artifact, 문서 수정, 인터페이스)은 [03. Core 동기화](03-core-sync.md)에 있다.
Core binary 빌드는 Core CI가 소유한다. 이 레포는 빌드하지 않는다. → [nimwake#3](https://github.com/nimwake/nimwake/issues/3)

---

## 문서

| 문서                                               | 내용                                                     |
| -------------------------------------------------- | -------------------------------------------------------- |
| [01. 레포지토리 셋업](01-repository-setup.md)      | 디렉터리 구조 · macOS/WSL 개발환경 · 빌드 · CI · Core pin |
| [02. 마일스톤](02-milestones.md)                   | A0 ~ A6 작업 항목과 완료 조건                            |
| [03. Core 동기화](03-core-sync.md)                 | 동기화 지점 · Core 이슈 #3–#7 · 실기기 실험 목록          |

---

## 이 페이즈에서 하지 않는 것

- Cloudflare Tunnel · Tailscale · Caddy (PRD §15, §37–§39) — LAN `curl`로 충분하다
- `nimwake-hostd` Rust binary (PRD §8) — MVP는 shell. 필요가 드러나면 Phase 2
- Host CLI 전체 (PRD §33) — `start` / `stop` / `status` / `logs` / `doctor` 최소 집합만
- Network 상태 머신 · storage 정리 · log rotation 자동화 (PRD §13, §18–§20) — Phase 2
- Thermal · battery 자동 정책 (PRD §26–§28) — soak 관찰 항목으로만
- binary rollback · backup (PRD §31, §41)

---

[문서 인덱스](../../README.md) · [PRD](../../prd/README.md)
