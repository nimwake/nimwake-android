# 07. soak — Core v0.1.0-rc1, 12시간 (부분)

> **일시:** 2026-10-09 01:25 → 13:27 · **결과:** 12.0h 결함 없음 — non-200 0 · 잔존 app 0 · daemon 재기동 0
>
> 24h로 계획했지만 12h에서 멈췄다. Core가 `v0.1.0` 판정 대상(main `d7c5590`, 버전 0.1.0 · `nimwake-bench`)을 내놓아, 판정에 쓰일 soak은 그 binary로 다시 한다 (사용자 결정, B안). 이 리포트는 **Android 8항목의 24h · 72h soak 근거가 아니다** — rc1에서 12시간 동안 본 것의 기록이다.

---

## 환경

[05](05-a5-network.md)와 같다. Core `17975b1` (v0.1.0-rc1), supervisor는 A2 판(고아 정리 전).

| 조건 | 값 |
| ---- | -- |
| sampler | `nimwake-soak` 300초 간격, 기기에서 (개발 머신 없이) |
| 화면 · 전원 | 화면 꺼짐 대부분, 충전기 연결 |
| `host.conf` | `NIMWAKE_LISTEN=0.0.0.0:8080` |
| 중간 작업 | adb로 phantom process 해제 (11시 무렵), 실험 E2–E4 (12:04–12:10, 별도 경로 · 포트) — 운영 daemon은 건드리지 않음 |

원본: 개발 머신 `~/nimwake-soak-archive/soak-rc1-2026-10-09.csv` (145 표본)

## 결과

```text
samples          145  (2026-10-09 01:25:13 → 2026-10-09 13:27:11, 12.0h)
max gap          302s  (> 2x interval means the sampler or Termux was stopped)
non-200          0
cold start       p50 0.043s  p95 0.050s  max 0.109s
apps left awake  0 samples  (should be 0 — scale-to-zero / orphans)
daemon restarts  0
daemon RSS       2176 → 1272 KB  (max 2340)
battery          54–100%  max temp 30.7°C
free storage     99889 → 99862 MB
```

| Core PRD §51 관찰 | 12h 결과 |
| ----------------- | -------- |
| daemon survival | 같은 pid 13274로 12시간 |
| Android background killing | 표본 간격 최대 302s — sampler · Termux가 멈춘 적 없음 |
| memory usage | daemon RSS 증가 없음 (2.2 → 1.3 MB, 쓰지 않는 페이지는 swap으로) |
| battery · temperature | 54–100% (충전 중), 최고 30.7°C. 배터리 · 온도는 Termux:API 설치(01:30) 뒤부터 기록 |
| orphan process | 요청 직전 떠 있던 app 0 (145/145) |
| storage growth | 27 MB 감소 (로그 · soak.csv) |
| repeated lifecycle stability | 145회 cold start → sleep 모두 정상 |
| network recovery | 이 기간에는 시험하지 않음 → [05](05-a5-network.md) |

## 관찰

- **80ms를 넘은 cold start 3건(102–109ms)은 모두 새벽**이다 (03:00 · 03:10 · 06:31). [02](02-a3-boot.md)의 1시간 방치 뒤 첫 cold start(103ms)와 같은 크기로, 오래 쉰 뒤 swap-in으로 보인다. 나머지는 p95 50ms 안이다.
- 배터리가 74–77%에 머물다 마지막에 100%로 찼다. Samsung 배터리 보호 충전으로 보인다 — 장기 운용에서는 바람직한 동작이다.
- 12시간 동안 운영 daemon에 영향을 준 작업은 없었다. 실험 E2–E4는 별도 daemon에서 돌았고 표본에 흔적이 없다.
