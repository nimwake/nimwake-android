# 12. Core v0.1.0-rc4 — CI와 같은 workload 비교 (PRD §50) · 72h soak 재시작

> **일시:** 2026-10-12 · **결과:** §50의 다섯 항목 중 **네 개를 채웠다.**
> 기기에서 cold start의 **절반 이상이 process spawn**이다(CI는 5분의 1).
> lifecycle stress 1000 사이클에서 **고아·좀비·FD 누수 0**. proxy overhead는
> 측정 농도 문제로 못 채웠다.
>
> [08](08-core-d7c5590-bench.md)의 1차 비교를 rc4로 다시 했다. 그쪽은 Core의
> baseline 형식에 §50 항목 절반이 없었고 cold start 분해를 표본 하나로 계산했다.

---

## 왜 rc4인가

72h soak은 `d7c5590`에서 돌았고 그 뒤 Core main에 다섯 개가 들어왔다.

```text
nimwake#46  §76 manifest 재적재      SIGHUP
nimwake#47  §77 crash-loop backoff   매 acquire 경로를 지난다
nimwake#48  §78 메모리 입장 제어      매 acquire 경로를 지난다
nimwake#50  로그 ANSI 제거           기기 로그의 39.3%가 escape였다
nimwake#51 #52  overhead 지표 수정
```

§77과 §78은 **매 `acquire` 경로에 코드를 더한다** — soak이 지나는 길이다.
그 증거를 새 코드에 돌려 쓸 수 없으므로 기기 검증을 rc4에서 다시 한다.

## 환경

[08](08-core-d7c5590-bench.md)과 같고 Core만 바뀌었다.

| 항목 | 값 |
| ---- | -- |
| Core | `v0.1.0-rc4` (`5fab4155`) — release asset, `core.lock`에 `tag=`로 고정 |
| 확인 | `make deploy` → `nimwake-host stop` → `start` → `nimwaked 0.1.0-rc4 — 1 application(s) validated` |
| 로그 | 재시작 이후 6줄에 ANSI escape **0개** (nimwake#50 확인) |
| 깨우기 | cold start 200/48ms · warm 200/15ms |

### `deploy`만으로는 새 코드가 돌지 않는다

`deploy`는 바이너리를 놓고 **떠 있는 supervisor는 건드리지 않는다.** 배치 직후에도
돌고 있던 daemon은 옛 바이너리를 메모리에 들고 있었다 — 버전 줄이 `0.1.0`이었고
로그에 ANSI가 계속 쌓였다.

**그 상태로 soak을 시작하면 또 옛 런타임을 재게 된다.** `stop` → `start`로
재시작하고 버전 줄을 확인한 뒤에 시작했다.

## §50 비교

같은 `nimwake-bench`를 같은 workload로 양쪽에서 돌렸다. cold start 분해는
**양쪽 모두 표본 1,000개**다.

| 지표 | CI Linux | Android 기기 | 배수 |
| --- | ---: | ---: | ---: |
| cold start queue | 0.027 ms | 1.106 ms | **41.0×** |
| cold start spawn | 0.170 ms | 5.762 ms | **33.9×** |
| cold start readiness | 0.046 ms | 0.851 ms | 18.5× |
| cold start total | 0.916 ms | 10.687 ms | 11.7× |
| daemon RSS | 5.56 MB | **2.05 MB** | 0.4× |
| CPU (wall 대비) | 103.2 % | **9.3 %** | 0.1× |
| concurrency knee | 50 (11,036 rps) | **1 (122 rps)** | — |
| knee p95 | 6.05 ms | 12.36 ms | 2.0× |

### 먼저 무너지는 것은 process spawn이다

절대 배수로는 actor queue가 41배로 가장 크지만 **값이 1.1ms다.** 비중을 보면
답이 분명하다.

```text
         queue    spawn     readiness   나머지
CI        2.9%    18.6%      5.0%       73.5%
기기     10.3%    53.9%      8.0%       27.8%
```

proot(ptrace)이 fork/exec를 감싸는 비용이 여기 드러난다. [08](08-core-d7c5590-bench.md)이
동시 연결에서 같은 원인을 짚었다.

### daemon은 병목이 아니다

RSS가 CI의 0.4배, CPU가 0.1배다. **적게 쓰는 것이 좋은 소식이 아니다** — 처리량이
다른 곳에서 막혀 daemon이 할 일이 없다는 뜻이다. 무릎이 동시성 1이고 122 rps다.

### lifecycle stress는 깨끗하다

1000 사이클 × 10 app을 218초에 돌렸다. **기기에서 처음 측정됐다** — [08](08-core-d7c5590-bench.md)은
`--stress` 없이 돌아 이 절이 없었다.

| 항목 | 값 | 판정 |
| ---- | -- | ---- |
| spawned processes | 1000 | |
| failed requests | 0 | ✓ |
| orphan processes | 0 | ✓ |
| zombie processes | 0 | ✓ |
| ports left open | 0 | ✓ |
| FD | 12 → 12 | ✓ |
| RSS | 2.2 → 2.5 MB | ✓ |

### cold-start storm은 여전히 실패한다

1000 동시 요청에 **실패 915건**([08](08-core-d7c5590-bench.md)은 916건).
회귀가 아니다. **spawn은 1 · backend pid 1**로 Core의 기동 중복 제거 불변식은
지켜졌다. 실패한 것은 연결이고 원인은 `somaxconn 128`이다.

`nimwake-bench`는 이것으로 correctness gate를 실패 처리한다(exit 1). **이 기기에서는
늘 그렇다.**

## 채우지 못한 항목

### proxy overhead — 측정 농도가 무릎을 넘었다

```text
기기 무릎     concurrency 1
warm 측정     8 동시 연결 (rc4의 기본값)
direct p50    27.7 ms
gateway p50   15.1 ms   ← gateway가 더 빠르다
proxy_overhead_p50_ms = -13.4
```

proxy를 한 번 더 거치는데 더 빠를 수는 없다. 그 농도에서는 `echo-server`
fixture가 먼저 막혀 **비교 기준이 병목**이 된다.

Core에 `--warm-connections`를 더해 고쳤다(nimwake#54). **rc4에는 없다.**
농도 1로 재려면 그 수정이 들어간 build가 필요하다.

### proxy connect 구간 — trace가 다르다

cold start 분해는 `nimwake::startup`의 세 구간(queue · spawn · readiness)이다.
proxy connect는 `nimwake::request`의 `proxy_connect_us`에 있고 `--trace-json`으로
꺼낼 수 있다. bench가 요청 trace를 모으지 않아 분해에 없다.

## 72h soak 재시작

rc4 런타임으로 다시 시작했다.

```text
시작      2026-10-12 18:52:40 · 72h · 300초 주기
daemon    pid 1151 (nimwaked 0.1.0-rc4)
첫 표본   http=200 · 18ms · RSS 2024 KB · 배터리 77% · 30.1°C
이전 CSV  soak-20261012-185237.csv로 보존 (d7c5590, 72.0h, 표본 862개)
```

`d7c5590`의 72h 결과는 [11](11-soak-d7c5590-72h.md)에 있다. 완주했고 전 항목
깨끗했지만 **그 build에는 위 다섯 개가 없다.**

---

← [11 soak 72h](11-soak-d7c5590-72h.md) · [09 Android 8항목](09-android-acceptance.md) · [문서 인덱스](../README.md)
