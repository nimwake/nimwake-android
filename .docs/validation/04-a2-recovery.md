# 04. A2 supervisor — 실기기 daemon recovery

> **마일스톤:** A2 · **일시:** 2026-10-09 · **결과:** `kill -9` → 1초 안에 재기동 · exit 78 → UNHEALTHY · stop 후 잔존 0 · 재부팅 시 supervisor 경유 READY
>
> Core `v0.1.0` Android 8항목의 **Daemon recovery**.

---

## 환경

[03. Core v0.1.0-rc1](03-core-v0.1.0-rc1.md)과 같다. Core `17975b1` (v0.1.0-rc1).
`make deploy`로 `nimwake-host`(`~/.nimwake-host/{bin,lib}`, `$PREFIX/bin` 링크)와 supervisor를 띄우는 `10-nimwake`를 설치했다. `host.conf`는 기본값.

## 결과 — `make test-recovery`

```text
== 1. kill -9 → restart
ok  RUNNING  nimwaked pid=22891
ok  restarted  pid=22891 → 22967
2026-10-09 00:32:24 state BACKOFF — exit 137 — restart 1 in 0s
2026-10-09 00:32:25 state RUNNING — nimwaked pid 22967, ready after 1s
PASS lifecycle
== 2. configuration error (78) → UNHEALTHY, no restart
configuration error (exit 78) — fix it, then nimwake-host start
ok  UNHEALTHY on exit 78
== 3. stop leaves nothing behind
nimwake-host: stopped after 1s
ok  nothing left after stop
PASS recovery
```

## 확인된 가정

- **`proot-distro login`은 nimwaked의 종료 코드를 그대로 돌려준다.** 빈 apps 디렉터리로 띄운 nimwaked의 `78`(EX_CONFIG)을 supervisor가 받아 재기동하지 않았다. `SIGKILL`은 `137`로 보인다. supervisor의 판단(Core PRD §74 종료 코드 표)이 proot 아래에서도 성립한다.
- **복구는 약 1초다.** `kill -9` → 감지 → backoff 0s → 기동 → health 404. Core의 cold start가 아니라 daemon 기동 시간이다.

## 작업 중 고친 것 — 모두 테스트 · 운영 스크립트 쪽

| 증상 | 원인 | 조치 |
| ---- | ---- | ---- |
| 복구에 "27초"로 찍혔다 | 1초도 안 걸리는 BACKOFF를 ssh polling이 놓치고 15초 timeout을 다 기다렸다. 실제 복구는 2초였다 | 새 pid로 RUNNING이 될 때까지만 기다리고, 시간은 `supervisor.log` 시각으로 본다 |
| stop 뒤 "잔존 프로세스" | `pgrep -f '…\|nimwake-host __supervise'`를 실행하는 **원격 셸 자신의 명령줄**에 패턴이 있어 잡혔다 | 정규식을 `[_]_supervise`로 — 명령줄 문자열에는 맞지 않는다. 같은 패턴인 `make run`의 사전 검사는 이대로였으면 **항상 거부**했다 |
| `status`가 `running (pid 22739)22739` | `${v:+…}${v:-…}`는 v가 있으면 v도 찍는다 | `if`로 |

## 재부팅 — supervisor 경유 부팅 (2026-10-09)

```text
2026-10-09 01:12:26 boot: start (booted at 2026-10-09 00:53:58)
2026-10-09 01:12:28 sshd: started (booted at 2026-10-09 00:53:58)
2026-10-09 01:12:28 supervisor: nimwake-host: supervisor started (pid 11429)
2026-10-09 01:12:30 ready: health 404 after 2s (supervisor RUNNING)
```

`make test-boot` PASS — 부팅 직후 전부 SLEEPING, lifecycle 통과. 부팅부터 스크립트 시작까지 18분은 비밀번호 잠금을 풀기까지의 시간이다 ([02. A3](02-a3-boot.md#화면-잠금--화면-꺼짐)).

재부팅 직전 `pkg install termux-api`가 진행 중이었다. 끊긴 설치가 sshd를 망가뜨렸을 수 있어 `dpkg --audit`로 확인했고 이상은 없었다. **패키지 설치 중에는 재부팅하지 않는다** — 원격 운영에서 sshd를 잃으면 사람이 기기 앞에 가야 한다.

## 남은 것

- [x] 재부팅 → `10-nimwake`가 supervisor 경유로 READY → `make test-boot`
- [ ] soak 중 Android가 daemon을 죽였을 때의 복구 (soak 리포트에서 `daemon_pid` 변화로 본다)
