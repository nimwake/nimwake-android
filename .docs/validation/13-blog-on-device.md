# 13. 실제 앱 하나 — Next.js 블로그를 폰에서

> **일시:** 2026-10-14 · **Core:** `v0.1.0-rc6` (`4f7d991`) · **결과:** 폰이 실제 프레임워크 앱을 서빙한다 — cold 1.6–1.7초 · warm 30–50ms · RSS 약 95 MB · SIGTERM에 40ms 안팎으로 내려간다
>
> #45의 2단계. 지금까지 폰은 2 MB `echo` fixture만 서빙했다.

---

## 구성

| | |
| - | - |
| 앱 | `examples/blog` — Next.js 16.3.6 · React 19.3.0, App Router (#47) |
| 빌드 | 개발 머신에서 `make app-blog` → standalone 21 MB (네이티브 모듈 0). 폰은 `node server.js`만 |
| 런타임 | Node 24.21.0 — `/opt/node`, 공식 linux-arm64 tarball, `guest/node.lock`의 sha256으로 확인 |
| manifest | `guest/apps/blog/nimwake.toml` — `blog.local` · 3102 · `HOSTNAME=127.0.0.1`(loopback만) · idle 120초 · startup 30초 |
| 측정 | `make test-app HOST=blog.local` (`tests/device/app.sh`) — 3바퀴, 같은 스크립트로 `echo.local`도 |

## 결과

| | blog (Next.js) | echo (fixture) |
| - | -------------- | -------------- |
| cold — 첫 요청 응답 (curl) | **1.621 · 1.643 · 1.709 s** | 0.045 s |
| cold — Core 분해 `total` | 0.998 · 0.995 · 1.056 s | 0.032 s |
| └ queue | 4.6–6.2 ms | 4.9 ms |
| └ spawn | 26–32 ms | 24 ms |
| └ **readiness** (port가 열리기까지) | **0.96–1.02 s** | 3 ms |
| warm (5번) | 29–50 ms | 15–21 ms |
| RSS (깨어 있을 때) | **92.6 · 96.8 · 94.7 MB** | 0.4 MB |
| 유휴 정지 — `stopping application`에서 프로세스가 사라질 때까지 | **44 · 36 · 45 ms** | 48 ms |
| MemAvailable (측정 뒤) | 2.99 GB | |

## 해석

- **cold start의 거의 전부가 앱 자신의 기동이다.** Nimwake 몫(queue + spawn)은 30–40 ms로 echo와 같다. readiness 약 1초는 Node · Next.js가 port를 열기까지다. curl 기준 0.6초가 더 붙는 것은 첫 요청의 렌더링이다 — 두 번째부터 30–50 ms.
- **SIGTERM에 바로 내려간다** — Core fixture로 치면 `stubborn-server`(SIGTERM 무시)가 아니다. shutdown 제한 10초에 한참 못 미친다.
- **메모리:** 깨어 있는 Next.js 앱 하나가 약 95 MB — #42가 적은 96–118 MB와 같다. 가용 2.9 GB에서 동시에 여러 개도 여유가 있다. §78 · §80 임계값은 이 값과 soak의 MemAvailable 분포로 정한다 (#42).
- **idle 120초:** 개인 블로그면 첫 방문자가 1.6초를 기다리고 그 뒤는 빠르다. 2분 동안 아무도 없으면 95 MB를 돌려준다.

## 관찰

- **Next.js는 프로세스 이름을 바꾼다** — `comm`은 `next-server (v1`, cmdline은 `next-server (v16.3.6)`. 이름으로 앱 프로세스를 찾으면(`pgrep 'node server.js'`) 잡히지 않는다. 처음 측정이 이것 때문에 틀렸다 — 'node가 남지 않았다'는 확인은 실제로는 아무것도 보지 못한 것이었다. 측정 스크립트는 **Core의 SIGUSR1 스냅샷(§79)이 알려 주는 pid**를 쓴다.
- **Core는 정지 완료를 INFO로 남기지 않는다** — `stopping application … reason=idle`만 있다. 정지에 걸린 시간은 프로세스를 직접 봐서 쟀다. Core 쪽에 전할 만한 관측성 간극이다.
- **§81 `X-Forwarded-For`:** 폰 안에서 `X-Forwarded-For: 1.2.3.4`를 보내면 앱은 `1.2.3.4, 127.0.0.1`을 본다. 같은 Wi-Fi의 PC(192.168.0.10)에서 열면 `192.168.0.10` — gateway가 관측한 peer가 맨 오른쪽에 붙는다.
- **같은 Wi-Fi에서 열기:** gateway는 Host header로 앱을 고른다 — `http://192.168.0.25:8080/`은 404. 접속하는 기기의 hosts에 `192.168.0.25 blog.local`을 넣고 `http://blog.local:8080/`. hosts를 고칠 수 없는 폰에서는 Tailscale MagicDNS 등 (#41 · #45-3).
- 측정 중 `SIGUSR1` 스냅샷: `state=RUNNING pid="21783" active=0 pending=0 since_ms=1648 idle_ms=517` — 상태 · OS pid · 유휴 시간이 그대로 보인다.

## 다음 (#45)

- 3. Tailscale I0 — 사람이 기기에서 로그인 · VPN 허용
- 4. 블로그 + ingress로 실사용 soak, `NIMWAKE_MIN_FREE_MEMORY_MB`를 켜고
