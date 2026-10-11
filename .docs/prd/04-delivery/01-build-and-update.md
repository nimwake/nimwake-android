# Build · Update · Rollback

> **Nimwake Android PRD** › 배포와 설치
>
> 원문 구간: `PRD.md` §29–§31

---

## 29. Build Policy

Android 서버에서 애플리케이션 build를 기본적으로 수행하지 않는다.

```text
External Builder
   ↓
Artifact
   ↓
Android
   ↓
Nimwake Deploy
```

이유:

- CPU 부하
- RAM spike
- 발열
- storage I/O
- 배터리 스트레스
- build dependency 복잡도

단, 작은 Rust/Go binary 등의 수동 build는 사용자 선택 사항이다.

---

## 30. Update Strategy

두 종류의 업데이트를 분리한다.

### Nimwake Update

```text
new nimwake binary
   ↓
stop nimwaked
   ↓
replace
   ↓
start
   ↓
health check
```

### Android Host Layer Update

```text
host scripts / nimwake-hostd
```

Android OS / Termux / Ubuntu 업데이트와 Nimwake 업데이트를 분리한다.

---

## 31. Rollback

Nimwake binary 업데이트 실패 시 직전 버전으로 rollback할 수 있어야 한다.

예:

```text
~/.nimwake-host/bin/

nimwaked-current
nimwaked-prev
```

업데이트 후 health check 실패 시 이전 binary를 다시 실행한다.

---

← [장애 시나리오](../03-operations/04-failure-scenarios.md) · [PRD 인덱스](../README.md) · [Configuration · Host CLI · Doctor](02-configuration-and-cli.md) →
