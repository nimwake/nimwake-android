# Nimwake Android PRD

Android Host Layer 요구사항 정의서. **이 트리가 원장(Single Source of Truth)이다.**

Android Host Layer가 **무엇을 왜 책임지는가**를 정의한다. Core 요구사항은 [Core PRD](https://github.com/nimwake/nimwake/blob/main/.docs/prd/README.md)가 소유한다.
실행 순서와 마일스톤 작업은 [페이즈 문서](../phases/phase-1/README.md)가 담당한다. 두 문서가 충돌하면 PRD가 이긴다.

---

## 제품 정의 — `01-product/`

- [문서 개요와 제품 정의](01-product/01-overview.md) — `§1–§2`
- [설계 원칙 · 목표 · Non-Goals](01-product/02-principles-and-goals.md) — `§3–§5`

## 아키텍처 — `02-architecture/`

- [전체 구조와 Host Supervisor](02-architecture/01-structure.md) — `§6–§9`
- [Boot Recovery · Wake Lock · Battery Optimization](02-architecture/02-boot-and-power.md) — `§10–§12`
- [Network Recovery와 Health Check](02-architecture/03-network.md) — `§13–§15`
- [proot Lifecycle과 Filesystem Layout](02-architecture/04-proot-and-filesystem.md) — `§16–§17`

## 운영 — `03-operations/`

- [Storage · Release Cleanup · Log Rotation](03-operations/01-storage-and-logs.md) — `§18–§20`
- [Health Model과 Restart Policy](03-operations/02-health-and-restart.md) — `§21–§25`
- [Thermal과 Battery 운영](03-operations/03-thermal-and-battery.md) — `§26–§28`
- [장애 시나리오](03-operations/04-failure-scenarios.md) — `§42`

## 배포와 설치 — `04-delivery/`

- [Build · Update · Rollback](04-delivery/01-build-and-update.md) — `§29–§31`
- [Configuration · Host CLI · Doctor](04-delivery/02-configuration-and-cli.md) — `§32–§34`
- [Installation Flow와 Bootstrap](04-delivery/03-installation.md) — `§35–§36`

## 선택 프로필과 보안 — `05-profiles/`

- [Tailscale · Cloudflare Tunnel · Caddy 프로필](05-profiles/01-network-profiles.md) — `§37–§39`
- [Security와 Backup](05-profiles/02-security-and-backup.md) — `§40–§41`

## MVP — `06-mvp/`

- [MVP Scope와 성공 기준](06-mvp/01-scope-and-success.md) — `§43–§44`
- [권장 운영 구성과 제품 경계](06-mvp/02-operating-setup-and-boundary.md) — `§45–§46`

---

## 섹션 번호 규칙

`§N`은 문서 간 참조를 위한 **안정 식별자**다. Core PRD와 같은 규칙이다.

- 섹션을 다른 파일로 옮기더라도 번호는 유지한다. (`§42 장애 시나리오`는 운영 그룹에 있다)
- 새 섹션은 기존 번호 사이에 끼워 넣지 않고 **다음 빈 번호를 사용한다.** (현재 최대: `§46`)
- 따라서 파일 안에서 번호가 연속하지 않을 수 있다. 읽는 순서는 파일 이름의 `NN` 접두사가 결정한다.
- 이 레포의 다른 문서는 `PRD §N`으로 참조한다. Core PRD를 가리킬 때는 `Core PRD §N`으로 쓴다.

---

[문서 인덱스](../README.md) · [Phase 1](../phases/phase-1/README.md)
