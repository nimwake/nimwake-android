# 14. 메모리 임계값 — §78 입장 제어 · §80 유휴 eviction을 기기에서

> **일시:** 2026-10-14 · **Core:** `v0.1.0-rc6` (`4f7d991`) · **결과:** 둘 다 기기에서 동작한다. 실사용 임계값 512 MB로 블로그 72h soak 시작 (10-14 11:11 → 10-17 11:11)
>
> #42 · #45의 4단계. Core는 임계값을 받아 판단할 뿐이고, 그 값은 기기의 성질이다 (Core Rule 7).

---

## 방법

`host.conf`의 `NIMWAKE_MIN_FREE_MEMORY_MB`를 바꾸고 supervisor를 재시작해 `--min-free-memory-mb`로 넘긴다 (#43). 앱은 Next.js 블로그(#48), 메모리는 `/proc/meminfo`의 MemAvailable — Core가 보는 값과 같다.

## 결과

### §80 유휴 eviction — 임계값을 가용 바로 아래에

| 시도 | 임계값 | 블로그를 깨운 뒤 MemAvailable | 결과 |
| ---- | ------ | ----------------------------- | ---- |
| A1 | 가용 − 60 MB (2977) | 3037 → **2989** | eviction 없음 — 가용이 임계값 위에 남았다 |
| A2 | 가용 − 20 MB (3020) | 3040 → **2996** | **7초 뒤 eviction** |

```text
INFO nimwake_core::eviction: evicting the longest-idle application to free memory app="blog" idle_ms=7061 available_mb=2994 required_mb=3020
INFO nimwake_core::app::transition: stopping application app=blog operation_id=op#2 process=proc#1 reason=memory pressure
```

내린 뒤 가용은 3042 MB로 돌아왔고, 다음 요청은 다시 입장해 cold(1.67초)로 응답했다.

### §78 입장 제어 — 임계값을 가용보다 훨씬 위에 (999999 MB)

```text
WARN nimwake_core::app::transition: refusing to wake: not enough free memory app=blog available_mb=3038 required_mb=999999
WARN nimwake_core::gateway: acquire failed app="blog" status=503 Service Unavailable error=not enough free memory to start: 3038MiB available, 999999MiB required
WARN nimwake_core::eviction: memory is low but no application is idle; nothing to evict available_mb=3037 required_mb=999999
```

요청은 **503**. 10초 뒤 eviction 루프가 `nothing to evict`를 남긴다 — 깨어 있는 앱이 없으니 맞는 판단이다.

## 발견 — 임계값은 RSS가 아니라 MemAvailable 감소로 잡는다

블로그가 깨어 있을 때 **RSS는 93–97 MB**(#48)인데 **MemAvailable은 약 45–50 MB만 줄었다** — 공유 페이지(Node binary · 라이브러리)와 파일 캐시가 RSS에는 들어가고 MemAvailable 감소에는 덜 들어간다. A1이 eviction을 일으키지 못한 이유다.

→ "앱 N개를 동시에 깨워도 되는가"는 **RSS 합이 아니라 MemAvailable 감소의 합**으로 본다. Core가 §52(app별 예상 RSS)를 수집할 때도 이 차이를 알아야 한다 — Core에 전할 근거.

## 실사용 임계값 — 512 MB

- 평소 MemAvailable 약 3.0 GB (rc5 soak 중간 · 위 측정), 블로그 하나가 깨어 있으면 약 50 MB 감소
- 512 MB에서는 일상 사용으로 eviction이 일어나지 않는다. 다른 Android 앱이 메모리를 크게 쓸 때 **Android(lmkd)가 Termux를 죽이기 전에 Nimwake가 먼저 물러나는** 선이다
- 이 soak이 MemAvailable 분포를 쌓는다(#43 · `mem_avail_mb`) → 그것으로 다시 정한다. `/proc/pressure/memory`(PSI)는 앱에 막혀 있어 Android가 언제 죽이기 시작하는지는 직접 볼 수 없다

## 실사용 soak — 시작 조건

```text
make soak-start HOURS=72 SOAK_HOST=blog.local SOAK_PATH=/api/whoami     (#49)
Core     v0.1.0-rc6, --min-free-memory-mb 512
앱       blog (Next.js, idle 120초) · echo
표본     5분마다 /api/whoami — idle 120초보다 길어 매 표본이 '잠든 블로그의 첫 방문자'(cold)
첫 표본  2026-10-14 11:11:04 · 200 · 1.626 s · apps_before 0 · MemAvailable 2986 MB
ingress  없음 — LAN(같은 Wi-Fi)만. Tailscale은 미룸 (#41 · #45-3)
```

판정 리포트는 끝난 뒤(10-17 11:11).
