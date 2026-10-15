# 16. Core `v0.1.0-rc7` — 배치 · lifecycle · recovery · §82 peer 제한 · §83 header 상한

> **일시:** 2026-10-15 · **Core:** `v0.1.0-rc7` (`1e2bf91`, release asset) · **결과:** #59의 넷 중 **1(배치)** · **3의 일부(lifecycle · recovery · LAN)** · **4(§82 · §83)** 통과. 남은 것은 사람 손이 필요한 셋 — 초기화 기기 `make install` · 재부팅 · Wi-Fi
>
> [#59](https://github.com/nimwake/nimwake-android/issues/59) · Core nimwake#68(§82) · #69(§83)

---

## 0. 그 전에 — 폰이 꺼져 있었다

10-15 오후, sshd와 gateway가 모두 거부했다. **재부팅이 아니었다** — 가동 2일 19시간, `supervisor.log`는 10-14 17:54에서 종료 기록 없이 끊겼다. 메모리가 거의 찼다(여유 173 MB, swap 900 MB). **Android가 Termux를 통째로 내렸고**, Termux:Boot는 재부팅 때만 돌므로 사람이 Termux를 열 때까지 꺼져 있었다.

→ #60: supervisor가 heartbeat를 남기고, 다음 `start`가 **재부팅인지 폰이 켜진 채 죽었는지**를 `supervisor.log` · `status` · doctor에 남긴다. 이 배치부터 기기에 들어가 있다.

격리 daemon으로 다시 띄워 rc6 블로그 soak을 시작했다가, rc7이 나와 **1시간(12 표본, 실패 0, cold p95 1.64s)에서 멈췄다** — 판정 대상이 rc7이다.

## 1. rc7 배치

`core.lock` → `make fetch-core`(BUILD_INFO commit 확인) → `make deploy` → `make restart`

```text
core        1e2bf91744acc8ad9a1c125af7f555dc975f0e0e v0.1.0-rc7 (installed binary)
running     nimwaked 0.1.0-rc7 (last line in nimwaked.log — the binary actually in memory)
launch: proot-distro login ubuntu --isolated --user nimwake -- /opt/nimwake/bin/nimwaked … --listen 0.0.0.0:8080 --min-free-memory-mb 512
```

## 2. 태그 binary로 — lifecycle · recovery · LAN · 실제 앱

| 시험 | 결과 |
| ---- | ---- |
| `make test-device` | PASS — cold 0.107s · warm 0.018s(같은 PID) · idle 정지 · 새 PID로 cold 0.054s |
| `make test-recovery` | PASS — `kill -9` 뒤 재기동 · exit 78 → UNHEALTHY(재기동 없음) · stop 뒤 잔존 0 |
| `make test-lan` | PASS — LAN cold → warm · 동시 cold 20개 → 프로세스 하나 |
| `make test-app HOST=blog.local` | cold 1.649 · 1.686s (readiness 약 1s, Nimwake 몫 30ms 남짓) · warm 27–52ms · RSS 95–96 MB · SIGTERM 정지 35–46ms — rc6([13](13-blog-on-device.md))과 같다 |

## 3. §82 앱별 peer 제한

시험 앱 둘을 배포 계약(`make deploy-app`)으로 — echo-server, `idle 30s`.

| 앱 | exposure | `allow` |
| -- | -------- | ------- |
| `lanapp` | lan | `["192.168.0.0/16"]` |
| `pubapp` | public | 없음 |

터널(cloudflared)은 폰 안에서 gateway에 붙으므로 **터널 요청의 peer는 `127.0.0.1`이다**([15](15-deploy-and-public-url.md)의 XFF 맨 오른쪽). 폰 안에서 `127.0.0.1`로 보낸 요청이 그 조건 그대로다 — Cloudflare 없이 본다.

| 요청 | 결과 |
| ---- | ---- |
| `lanapp` ← 127.0.0.1 (터널의 peer) | **403** |
| 403 뒤 `lanapp` 상태 | **SLEEPING, pid 없음** — 앱을 깨우지 않았다 |
| `lanapp` ← LAN(개발 PC) | 200 |
| `pubapp` ← 127.0.0.1 · LAN | 200 · 200 |

```text
WARN nimwake_core::gateway: peer is not allowed to reach this application app="lanapp" peer=127.0.0.1
```

**host bit가 켜진 CIDR** — `allow = ["192.168.0.9/16"]`로 재배포:

```text
core: reload failed to read manifests; keeping the current set … TOML parse error at line 6, column 9
  `192.168.0.9/16` has bits set outside its /16 prefix; did you mean `192.168.0.0/16`?
apps: Core rejected the reload — restoring the previous manifest
```

이전 manifest로 복원 → `lanapp`은 여전히 127.0.0.1에 403. 재적재에서는 exit 78이 아니라 '현재 set 유지'다(§76) — 배포 계약이 되돌린다.

## 4. §83 header 읽기 상한

개발 PC에서 소켓을 열고 header를 끝내지 않은 채 기다린다 (python, 서버가 끊을 때까지):

| 보낸 것 | 서버가 끊은 시각 |
| ------- | ---------------- |
| request line + `Host:` 한 줄, 빈 줄 없음 | **16.3s** (응답 없이 close) |
| 아무것도 | **16.3s** |

기본 15초 + 네트워크. 바로 뒤 정상 요청 200. 처음에 `nc`로 재면 38초로 보였다 — nc가 입력이 끝날 때까지 원격 종료를 알아채지 못했다(측정 도구의 문제).

본문 상한 `--max-request-body-mb`는 기본 꺼짐이라 운영 설정을 바꾸지 않았다.

## 5. 이 레포 쪽 — `allow`와 `exposure`를 맞춘다

§82로 T2(LAN 앱이 터널로 열림)를 **코드가 막을 수 있게 됐다**. 대신 둘이 어긋나면 반대 사고가 난다 — public 앱의 `allow`에 127.0.0.1이 빠지면 인터넷 요청이 모두 403이다. 배포 계약 검사(`app-manifest.sh check`)가 본다:

| exposure | allow | 검사 |
| -------- | ----- | ---- |
| lan | 없음 | 경고 — LAN 대역을 넣으라고 |
| lan | `127.*` · `0.0.0.0/0` 포함 | 경고 |
| public | 127.0.0.1을 빠뜨림 | **거부** |

## 남은 것 (#59)

| | 필요한 것 |
| - | ---------- |
| 2. 초기화 기기 `make install` → 블로그까지 | Termux 데이터 삭제 — 사람이 폰에서, ssh 키를 다시 등록 |
| 3. `make test-boot` | 재부팅 — 잠금 해제 |
| 3. `make test-wifi` | Wi-Fi 끄고 켜기 |
| 그 뒤 | rc7로 72h soak (실제 앱) |

시험 앱 `lanapp` · `pubapp`과 release 디렉터리는 지웠다. 앱은 blog · echo(LAN).
