# Nimwake Android 문서

```text
.docs/
├── PRD.md     ← 원장 (Android Host Layer 요구사항)
└── phases/    ← 실행 계획
```

| 문서                                | 성격                                                             |
| ----------------------------------- | ---------------------------------------------------------------- |
| [**PRD**](PRD.md)                   | **원장.** Android Host Layer가 무엇을 왜 책임지는가              |
| [**Phase 1**](phases/phase-1/README.md) | 실행 계획. Android MVP를 언제 어떤 순서로 만드는가           |

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
| [Phase 1](phases/phase-1/README.md) | `v0.1.0` | Android MVP — Install · Start · Recovery · Boot   | 계획      |

---

## 알려진 정리 작업

- `PRD.md`는 이전 이름(`Ember`, `emberd`)을 쓰고 있다. `Nimwake`, `nimwaked`로 바꾼다. → [A0](phases/phase-1/02-milestones.md)
- `PRD.md`가 1,200라인이다. Core처럼 `prd/NN-*/` 로 쪼개는 것은 A0 이후 필요할 때 한다.
