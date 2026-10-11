# 권장 운영 구성과 제품 경계

> **Nimwake Android PRD** › MVP
>
> 원문 구간: `PRD.md` §45–§46

---

## 45. 권장 초기 운영 구성

```text
Android Phone
RAM 4GB / Storage 64GB
        │
        ▼
      Termux
        │
        ├── nimwake-hostd / host scripts
        │
        ├── wake lock
        │
        └── Ubuntu proot
                │
                ├── nimwaked
                ├── app processes
                └── optional tunnel/VPN
```

항상 실행:

```text
Host Supervisor
Nimwake
Optional ingress / VPN
```

On-Demand:

```text
Next.js
Node API
Python API
AI Agent
Rust / Go services
```

---

## 46. 제품 경계

최종 경계는 다음처럼 정의한다.

```text
Android Host Layer

"Android에서 Nimwake를 살아 있게 만드는 책임"


Nimwake Core

"필요한 애플리케이션만 살아 있게 만드는 책임"
```

이 두 책임을 분리함으로써 Nimwake는 일반 Linux PaaS로 유지되고, Android Host Layer만 Android 특유의 운영 문제를 해결한다.

---

← [MVP Scope와 성공 기준](01-scope-and-success.md) · [PRD 인덱스](../README.md)
