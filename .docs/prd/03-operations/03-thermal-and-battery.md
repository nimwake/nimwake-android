# Thermal과 Battery 운영

> **Nimwake Android PRD** › 운영
>
> 원문 구간: `PRD.md` §26–§28

---

## 26. Thermal 운영

스마트폰은 장기간 서버 부하에서 발열 문제가 생길 수 있다.

Host Layer MVP에서는 hardware temperature 제어를 하지 않는다.

대신 가능한 경우 temperature 정보를 읽어 상태를 표시한다.

상태 예:

```text
NORMAL
WARM
HOT
CRITICAL
```

정확한 센서 접근은 기기별 차이가 크므로 optional capability로 둔다.

---

## 27. Thermal Policy

가능한 경우 다음 정책을 지원한다.

예:

```text
HOT
 ↓
new app cold start 제한
 ↓
existing request만 처리
```

CRITICAL:

```text
low priority apps stop
```

MVP에서는 warning만 제공하고 자동 thermal scheduling은 Post-MVP로 둔다.

---

## 28. Battery 운영

서버 운용 시 상시 전원 연결이 기본이다.

운영 가이드:

- 배터리 팽창 여부 주기적 확인
- 과도한 발열 환경 피하기
- 케이스 제거 고려
- 가능하면 충전 제한 기능 사용
- 화면 상시 켜기 금지
- 고부하 빌드는 서버에서 수행하지 않기

Host Layer에서 build를 수행하지 않는 정책은 발열 감소에도 중요하다.

---

← [Health Model과 Restart Policy](02-health-and-restart.md) · [PRD 인덱스](../README.md) · [장애 시나리오](04-failure-scenarios.md) →
