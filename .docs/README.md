# Nimwake Android 문서

```text
.docs/
├── prd/         ← 원장 (Android Host Layer 요구사항)
├── phases/      ← 실행 계획
└── validation/  ← 실기기 검증 리포트 (NN-마일스톤-주제.md, 00-template)
```

| 문서                                | 성격                                                             |
| ----------------------------------- | ---------------------------------------------------------------- |
| [**PRD**](prd/README.md)             | **원장.** Android Host Layer가 무엇을 왜 책임지는가              |
| [**Phase 1**](phases/phase-1/README.md) | 실행 계획. Android MVP를 언제 어떤 순서로 만드는가           |
| [**Validation**](validation/)       | 실기기에서 본 것. CI로 재현할 수 없는 결과는 여기에만 있다. Core `v0.1.0` 판정 근거는 [09](validation/09-android-acceptance.md) |

---

## 단일 출처 규칙

Core 레포의 규칙을 그대로 따른다. → [nimwake/.docs/README.md](https://github.com/nimwake/nimwake/blob/main/.docs/README.md)

1. **요구사항은 PRD에만 존재한다.** 페이즈 문서는 PRD 섹션을 링크한다.
2. **Core 요구사항은 Core PRD가 소유한다.** 이 레포는 Core의 lifecycle · 상태 머신 · 품질 기준을 다시 쓰지 않는다.
3. **충돌하면 PRD가 이긴다.** Android 실기기에서 Core 가정이 깨지면 Core PRD를 먼저 고친다.
4. 한 파일은 하나의 주제를 다루며 300라인을 넘기지 않는다.
5. 파일 이름은 `NN-kebab-case`로 읽는 순서를 고정한다.

---

## 페이즈 현황

| 페이즈                              | 버전     | 주제                                               | 상태      |
| ----------------------------------- | -------- | -------------------------------------------------- | --------- |
| [Phase 1](phases/phase-1/README.md) | `v0.1.0` | Android MVP — Install · Start · Recovery · Boot   | 완료 — `v0.1.0` (2026-10-15) |
| [Phase 2](phases/phase-2/README.md) | — | ingress · 메모리 임계값 · 배포 계약 · 노출 보안 (Rust hostd는 설계만) | ingress · 배포 · 보안 완료 — `v0.1.1`. hostd는 D-A9 결정 대기 |
| [**v1.0**](phases/v1.0/README.md) | `v1.0.0` | 바깥 계약을 SemVer로 약속 · 실사용 근거 | 진행 중 — 기준 10개 중 5개 남음 |

---

## 알려진 정리 작업

- 없음.
