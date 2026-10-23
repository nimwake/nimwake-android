# 18. Core `v0.1.4` — control socket으로 상태를 묻는다 (§85 · §86)

> **일시:** 2026-10-23 · **Core:** `v0.1.4` (`bf79367`) · **결과:** PASS — 상태를 로그 파싱 없이 Core에게 직접 묻는다. lifecycle · recovery · 실제 앱 그대로
>
> [#71](https://github.com/nimwake/nimwake-android/issues/71). v0.1.2(기동 직후 SIGTERM에 app이 살아남는다) · v0.1.3(FAILED app이 있으면 CLI가 실패한다)은 건너뛰었다

---

## 1. 어디에 socket을 두나

Core는 `--control-socket PATH`로 socket을 만들고(기본 꺼짐), **디렉터리를 만들어 주지 않는다**(없으면 78). 이 기기에서 걸린 것 둘:

| | |
| - | - |
| 격리 | daemon은 `proot-distro --isolated` 안이다 — Termux 경로(`~/.nimwake-host/run`)가 보이지 않는다 |
| 길이 | proot 안 경로를 Termux에서 보면 `…/containers/ubuntu/rootfs/run/nimwake/nimwake.sock` = **116바이트** — Unix socket 한계 108을 넘는다. 실제로 `cannot reach …: Permission denied` |

**짧은 Termux 디렉터리 하나만 bind한다:** `~/.nimwake-host/run/core`(68바이트) → proot 안 `/run/nimwake`.

```text
launch: proot-distro login ubuntu --isolated --bind /data/data/com.termux/files/home/.nimwake-host/run/core:/run/nimwake
        --user nimwake -- /opt/nimwake/bin/nimwaked … --control-socket /run/nimwake/nimwake.sock
srw-------  nimwake.sock
```

앱에 새로 보이는 것은 이 socket(0600, 같은 uid)뿐이다 — 같은 uid라 앱은 원래 daemon에 신호를 보낼 수 있었다. 격리(Termux 홈 · SSH 키가 안 보인다)는 그대로다.

CLI(`/opt/nimwake/bin/nimwake`)는 정적 binary라 **Termux에서 그대로 돈다** — proot를 거치지 않아 **22ms**.

## 2. 실험 daemon (별도 port 8099)

| | |
| - | - |
| `nimwake status` | `nimwaked 0.1.4` · 표 |
| `--json` | `{"contract":1,"version":"0.1.4","apps":[{"name":"echo",…,"state":"RUNNING","pid":9745,…}]}` |
| pid | 9745 = `/proc/9745/cmdline` → `/opt/nimwake/bin/echo-server 3197` — OS pid다 |
| `NIMWAKE_SOCKET` | 플래그 없이도 된다 |
| 정지 | socket이 지워지고 잔존 프로세스 0 |

## 3. 운영 daemon

| | |
| - | - |
| 폰에서 `nimwake status` | 래퍼(`$PREFIX/bin/nimwake`)가 socket 경로를 넘긴다 |
| `nimwake-host status` | `core        nimwaked 0.1.4 — echo SLEEPING, blog SLEEPING (control socket)` |
| `make apps` | socket의 JSON으로 — `SIGUSR1` + 로그 grep 대신 (없는 daemon이면 예전 방식) |
| `make device-status` | `running     nimwaked 0.1.4 (control socket — the binary actually in memory)` |
| `make test-device` · `test-recovery` | PASS — `kill -9` 뒤 재기동, **남은 socket을 지우고 새로 만든다**, 다시 응답 |
| `make test-app HOST=blog.local` | cold 1.58–1.65s · RSS 95 MB — 앱 pid를 socket으로 |

**정지 시간:** 테스트의 `stop_ms`(0.1–0.2초 polling)는 64 · 189 · 68ms로 거칠다. Core가 이제 정지 완료를 직접 남긴다 — **`took_ms` 77 · 80 · 67ms**. 앞으로는 이것이 기준이다(리포트 13의 35–46ms도 polling 값이었다).

## 남은 것

- `SIGUSR1`은 Core에 그대로 있다 — socket이 없는 daemon을 위한 fallback으로 남겼다
- 실제 앱으로 72h soak (벽 충전기로 바꾼 뒤, 전원 열과 함께)
