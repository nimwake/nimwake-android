# 06. A1 실험 E2–E4 — proot 아래의 실패 경로

> **마일스톤:** A1 · A2 · **일시:** 2026-10-09 · **결과:** E2 · E3 · E4(nimwaked SIGKILL) 기대대로. **E4(proot SIGKILL)에서 고아가 남는 결함** → supervisor가 정리하도록 고쳐 실기기에서 5초 안에 복구
>
> Core `v0.1.0` Android 8항목의 **Daemon recovery**를 보강한다.

---

## 환경

[05](05-a5-network.md)와 같다. Core `17975b1` (v0.1.0-rc1). 24h soak 중이었다.

**운영 daemon과 섞지 않는다.** 실험 daemon은 별도 경로 · 포트에서 돈다 — `tests/device/experiments.sh`.

| | 운영 | 실험 |
| - | ---- | ---- |
| binary | `/opt/nimwake/bin/` | `/opt/nimwake-exp/bin/` (같은 binary 복사) |
| gateway | `:8080` | `127.0.0.1:8090` |
| app | `echo` | `crash`(:3201, `crash-server`) · `group`(:3202, `group-server` — 손자 `sleep 600`을 만들고 reap하지 않는다) |

supervisor · soak sampler의 패턴(`^/opt/nimwake/bin/`)에 실험 process가 걸리지 않는다. 실험 전후 운영 daemon pid(13274)와 soak 표본에 변화 없음.

## 결과

```text
== e2
e2 request 1: 502 0.026031
e2 request 2: 502 0.026382
e2 request 3: 502 0.042204
== e3
e3 awake: server=8733 grandchild=8734 alive=yes
e3 after idle: server=gone grandchild=gone
== e4
e4[nimwaked] after:  wrapper=gone daemon=gone server=gone grandchild=gone
e4[proot] after:  wrapper=gone daemon=alive server=alive grandchild=alive
== e4-term
e4-term after SIGTERM to orphan daemon (15s): daemon=alive server=alive grandchild=alive
```

| 실험 | 질문 | 결과 |
| ---- | ---- | ---- |
| **E2** | readiness 대기 중 app이 죽으면 바로 실패하는가 | **예.** `startup_timeout` 10s를 기다리지 않고 26–42ms에 `502` |
| **E3** | idle stop이 process group 단위라 손자까지 정리되는가 | **예.** 3초 idle 뒤 server · 손자 모두 사라짐 |
| **E4** nimwaked SIGKILL | app이 남는가 | **남지 않는다.** proot(`--kill-on-exit`)가 남은 tracee를 모두 죽인다 |
| **E4** proot SIGKILL | app이 남는가 | **남는다.** nimwaked · app · 손자가 고아로 산다 |
| e4-term | 고아 nimwaked에 SIGTERM이면 정리되는가 | **아니다.** 15초 동안 그대로 |

## 관찰 — proot를 잃은 nimwaked는 고장 난 상태다

e4-term 실험의 daemon 로그:

```text
unexpected error when polling the I/O driver: Os { code: 38, kind: Unsupported, message: "Function not implemented" }
```

proot가 해 주던 syscall 변환이 끊기자 Tokio I/O driver가 `ENOSYS`로 멈췄다. 그래서 SIGTERM(graceful shutdown)이 돌지 않고, app도 정리되지 않는다. 경로 변환도 없으므로 새 app을 띄울 수도 없다.

운영에서 이것이 일어나는 경로: Android가 메모리 압박 등으로 **proot process만** 죽이는 경우. supervisor는 daemon이 죽었다고 보고(exit 137) 재기동하지만, 고아 nimwaked가 port 8080을 쥐고 있어 새 daemon은 bind 실패(69)를 반복한다 → crash loop → `UNHEALTHY`.

Core 결함은 아니다 — proot가 사라진 process의 성질이다. Core에 올릴 것은 없다.

## 조치 — supervisor가 고아를 정리한다

`host/lib/supervisor.sh`의 `reap_orphan_daemon`:

1. 재기동 직전(STARTING)에 nimwaked가 남아 있으면 고아다 — 래퍼만 죽은 것
2. 그 자식(app)들의 **process group**에 TERM → 3초 → KILL. app은 각자 group leader다(Core `process_group(0)`) — group으로 보내야 손자까지 간다
3. nimwaked에 KILL — graceful을 기대하지 않는다

`nimwake-host stop`도 SIGTERM에 반응하지 않는 daemon을 같은 방법으로 정리한다.

### 실기기 확인 — 실험 daemon을 맡는 별도 supervisor로

```text
e4-supervised before: wrapper=8974 daemon=8983 server=9014 grandchild=9015
e4-supervised recovered in 5s: new daemon=9084
e4-supervised old: daemon=gone server=gone grandchild=gone
e4-supervised after: 200 0.100084 (new server 9120)

12:09:58 state BACKOFF — exit 137 — restart 1 in 0s
12:09:58 orphan nimwaked 8983 (its wrapper is gone), application(s): 9014 — killing them
12:10:02 state RUNNING — nimwaked pid 9084, ready after 1s
```

proot SIGKILL → **5초** 안에 고아 정리 · 새 daemon RUNNING · 요청 정상.

### 기기 없는 테스트

bats 2개 추가 (전체 24): 가짜 proot(`fake-proot`, 자식을 죽이지 않는다)와 TERM을 무시하는 가짜 daemon(`orphan` 모드)으로

- 래퍼가 죽으면 재기동 전에 고아 daemon과 app을 정리하고 daemon은 하나만 남는다
- `stop`이 TERM을 무시하는 daemon과 app을 정리한다

## 남은 것

- [ ] 운영 supervisor는 24h · 72h soak 동안 이전 코드로 돈다. 이 수정은 soak 뒤 `make deploy`로 들어간다 — soak 중 proot가 죽으면 이전 동작(crash loop)이 나타날 수 있고, 그러면 soak 리포트에 드러난다
