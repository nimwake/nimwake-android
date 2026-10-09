# 08. Core d7c5590 재검증 · CI와 같은 workload 비교 (PRD §50)

> **일시:** 2026-10-09 · **결과:** 새 Core로 lifecycle · recovery · LAN PASS. bench는 **cold start는 CI보다 빠르고 RSS는 작지만, 동시 연결이 늘면 무너진다** — 원인은 Nimwake가 아니라 proot(ptrace)와 Android 커널의 `somaxconn 128`
>
> Core PRD §50 "저사양 환경에서 어느 구간이 먼저 무너지는가"에 대한 첫 답.

---

## 환경

[07](07-soak-rc1-12h.md)과 같고 Core와 supervisor가 바뀌었다.

| 항목 | 값 |
| ---- | -- |
| Core | main `d7c5590` — `nimwaked 0.1.0` (nimwake#24), aarch64 asset에 `nimwake-bench` (nimwake#25). release.yml run `37883387505` artifact (`tag=` 없음) |
| supervisor | 고아 정리 포함 (#15) |
| 커널 | Android 13, Linux 4.19.87 · `net.core.somaxconn=128` · `tcp_max_syn_backlog=256` (adb shell로 읽음, 앱 권한으로는 막힘) |
| fd 한도 | Termux 32768, proot 10240 — 병목 아님 |

## 재검증 — 새 Core

`make deploy` → supervisor 재시작(새 코드) → `nimwaked 0.1.0 — 1 application(s) validated`.

| 시나리오 | 결과 |
| -------- | ---- |
| `make test-device` | PASS — cold 45ms / warm 11ms / sleep / new PID 47ms |
| `make test-recovery` | PASS — `kill -9` → 2초 안에 RUNNING, exit 78 → UNHEALTHY, stop 잔존 0 |
| `make test-lan` | PASS — 동시 cold start 20 → process 1 |

## bench — `make bench` (CI baseline = 같은 commit)

원본: 개발 머신 `~/nimwake-soak-archive/bench-d7c5590/` (device-report · CI performance-report)

| 지표 | CI Linux | 기기 (proot) |
| ---- | -------: | -----------: |
| cold start total | 51.85 ms (readiness 51.39) | **8.79 ms** (spawn 5.83, readiness 1.89) |
| daemon RSS | 5.6 MB | **2.0 MB** |
| warm p50 / p95 (nimwake) | 0.90 / 1.91 ms | 18.14 / **1039.55 ms** |
| warm p50 / p95 (direct backend) | 0.40 / 0.63 ms | 27.05 / **1054.49 ms** |
| warm throughput (direct / nimwake) | 19163 / 7818 req/s | **50 / 25 req/s** |
| concurrency 1 | 0.21 ms, 4560 req/s | 5.63 ms, 169 req/s |
| p95 2배 첫 지점 | concurrency 10 | concurrency 10 |
| 첫 오류 | 없음 (1000까지 0) | **concurrency 50** (172 errors) |
| cold-start storm 1000 | 실패 0, spawn 1 | **실패 916**, spawn 1 |

`nimwake-bench`는 storm 실패로 correctness gate를 실패 처리했다(exit 1). 그래도 **spawn은 1 · backend pid 1** — 1000개 동시 요청이 process 하나로 합쳐지는 Core 불변식은 기기에서도 지켜졌다. 실패한 것은 연결 자체다.

## 해석 — 무엇이 먼저 무너지는가

1. **연결 수락 대기열 (커널).** 기기 `somaxconn`이 128이다. 동시 연결이 몰리면 대기열이 넘쳐 SYN이 버려지고 클라이언트는 1초 뒤 재전송한다 → p95가 정확히 ~1초, 재전송을 넘기면 실패. **direct backend도 똑같이 나쁘다** — Nimwake gateway 탓이 아니다. CI도 concurrency 250 이상에서 같은 1초 tail(p99 1072ms)이 보인다; 기기는 그 지점이 10–50으로 내려온다. root 없이는 바꿀 수 없다.
2. **proot의 syscall 비용.** direct backend 처리량이 CI의 1/400(50 vs 19163 req/s)이다. proot는 ptrace로 모든 syscall을 가로채고, bench 클라이언트까지 proot 안에서 돌았다 — 이 수치에는 클라이언트 쪽 비용도 들어 있다. Nimwake 자체 overhead는 이 잡음 속에서 측정되지 않는다(음수로 나옴).
3. **Nimwake 고유 구간은 문제가 없다.** cold start는 CI보다 빠르고(readiness 1.9ms — CI의 51ms는 readiness polling 간격으로 보인다), RSS는 2 MB, process 합치기는 정확하다.

**운영 함의:** 홈서버 규모(동시 연결 한 자릿수)에서는 문제 없다 — concurrency 1에서 p50 5.6ms, 24h soak 계열의 cold start p50 43ms. 동시 연결 수십 이상이 몰리는 공개 서비스에는 이 구성이 맞지 않는다.

## 남은 것 — 72h soak 뒤

- [ ] proot 비용 분리: musl static binary는 Termux에서 proot 없이도 돈다 — 같은 bench를 proot 밖에서 돌려 (1)과 (2)를 나눈다
- [ ] 낮은 동시성(`--max-concurrency 10`)으로 같은 workload를 다시 돌려 gate 밖의 수치를 남긴다
- [x] `bench.sh`가 gate 실패 때 리포트를 가져오지 못하던 결함 — 리포트를 먼저 가져오고 종료 코드는 마지막에 돌려주게 고쳤다
