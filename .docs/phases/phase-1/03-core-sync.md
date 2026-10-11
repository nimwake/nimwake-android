# 03. Core 동기화

> **Phase 1 — Android MVP** › Core 동기화
>
> 이 문서는 두 레포 사이의 **계약과 피드백 경로**를 소유한다. Core 요구사항 자체는 Core PRD가 소유하고,
> Core에 요청하는 변경의 상세 내용은 Core 이슈가 소유한다. 여기에는 요약과 링크만 둔다.

---

## 동기화 지점

| Core                       | Android                    | 주고받는 것                                                     |
| -------------------------- | -------------------------- | --------------------------------------------------------------- |
| `v0.0.5` merge 이후        | A1                         | `core.lock` = Core SHA, 그 SHA의 aarch64 artifact (`release.yml`) — 완료 |
| `v0.1.0-rc1` (2026-10-08)  | A1–A3 · A5 재검증          | `core.lock` = `tag=v0.1.0-rc1`, release asset (#7). boot · lifecycle · recovery · LAN 통과 — 완료 |
| `v0.1.0` 준비 중           | A1 결과                    | 실험 E2–E4 — Core 결함 없음. proot가 죽은 뒤의 고아는 supervisor가 정리 (#15) — 완료 → [validation/06](../../validation/06-a1-experiments.md) |
| main `d7c5590` (2026-10-09) | A1–A3 · A5 재검증 · A5 bench | `core.lock` = rev `d7c5590`(`tag=` 없음, release.yml run artifact, #16). `nimwaked 0.1.0` · `nimwake-bench`. lifecycle · recovery · LAN 통과, bench 비교를 nimwake#25에 전달 — 완료 → [validation/08](../../validation/08-core-d7c5590-bench.md) |
| `v0.1.0` 준비 중           | A5 24h · A6 72h soak       | Core `d7c5590`으로 72h — 10-09 13:44 → 10-12 13:44 — **24h 결함 없음** → [validation/10](../../validation/10-soak-d7c5590-24h.md), 72h **진행 중**. rc1 12h는 참고 → [validation/07](../../validation/07-soak-rc1-12h.md) |
| `v0.1.0` 직전              | A6 72h soak                | Android 체크리스트 → Core acceptance ([Core PRD §65](https://github.com/nimwake/nimwake/blob/main/.docs/prd/03-delivery/08-definition-of-done.md)) |

`v0.1.0` 태그가 `d7c5590`과 다른 commit을 가리키면, 태그 binary로 lifecycle · recovery를 다시 돌리고 72h 결과와의 관계를 리포트에 적는다.

`core.lock`을 올릴 때마다 A1 lifecycle · A2 recovery 시나리오를 다시 돌리고 리포트를 남긴다.

### 계획과 달라진 점

이 계획은 Core `v0.0.3` 직후 A0를 시작해 `v0.0.4` · `v0.0.5`에 실기기 피드백을 넣는 것을 전제했다.
실제로는 Core가 `v0.0.5`까지 먼저 나갔다 (2026-09-30). 그 두 지점은 지났고, **실기기 피드백은 모두 `v0.1.0` 판정으로 모인다.**
구조 변경이 필요한 발견이 나오면 `v0.1.0` 전에 Core 이슈로 올린다.

---

## Core 이슈

Core `v0.0.3` 코드(PR #2)를 읽고 실기기 없이 확정된 간극과, 이 계획이 유효하기 위한 선행 변경이다.

| 이슈 | 내용 | Android 쪽 영향 | 상태 |
| ---- | ---- | --------------- | ---- |
| [nimwake#3](https://github.com/nimwake/nimwake/issues/3) | aarch64 빌드 artifact job (`nimwaked` + fixture) | 이 레포는 빌드하지 않고 artifact만 받는다 | 해결 — nimwake#10 (`release.yml` aarch64 job), smoke 수정 nimwake#14 |
| [nimwake#4](https://github.com/nimwake/nimwake/issues/4) | Android 검증 시점을 `v0.1.0` 이후 → `v0.0.3` 이후 병렬로 (Core PRD §50, phase 문서) | 단일 출처 규칙상 이 계획의 전제 | nimwake#13 |
| [nimwake#5](https://github.com/nimwake/nimwake/issues/5) | gateway listen address 설정 | LAN 접근 (A5) | 해결 — nimwake#9 (`--listen`, `NIMWAKE_LISTEN`) |
| [nimwake#6](https://github.com/nimwake/nimwake/issues/6) | 종료 코드로 실패 원인 구분 | supervisor의 crash-loop 판정 (PRD §24) | 해결 — nimwake#9 |
| [nimwake#7](https://github.com/nimwake/nimwake/issues/7) | host interface 계약 — health probe가 app을 깨우지 않음, 인자 · 신호 명시 | supervisor health probe (D-A5) | 해결 — nimwake#9 |
| [nimwake#24](https://github.com/nimwake/nimwake/issues/24) | `v0.1.0-rc1` binary가 버전을 `0.0.1`로 알림 (workspace 버전 미갱신) | 운영 로그로 release를 구분 못 함 | 해결 — nimwake#27 (`nimwaked 0.1.0`, 태그 gate) |
| [nimwake#25](https://github.com/nimwake/nimwake/issues/25) | aarch64 asset에 `nimwake-bench` | PRD §50 기기 비교 (A5) | 해결 — nimwake#26. Core가 이 레포의 `chmod` 누락을 짚어 #16에서 고침. CPU 지표도 추가됨 |

### 이 레포가 쓰는 Core 계약

nimwake#9가 [Core PRD §74 Host Interface](https://github.com/nimwake/nimwake/blob/main/.docs/prd/04-platform/03-host-interface.md)로 고정했다. 바뀌면 Core가 CHANGELOG와 PR 본문에 명시한다.

- **실행:** `nimwaked [APPS_DIR] [--listen ADDR] [--port PORT]`. 기동 성공 시 stdout에 `listening on http://…` 한 줄.
- **Listen:** 기본 `127.0.0.1:8080`. LAN은 `--listen 0.0.0.0:8080`으로 opt-in (A5). A1–A4는 loopback.
- **종료:** `SIGTERM`/`SIGINT` → 모든 app 정지 완료까지 기다린 뒤 종료. managed child 잔존 0.
- **종료 코드:** `0` 정상 · `78` 설정 오류 (재기동 안 함, `UNHEALTHY`) · `69` bind 실패 · `1` 그 외 (backoff 후 재시도).
- **Health probe:** 미등록 Host (`Host: nimwake-health.invalid`) → `404`. 어떤 app의 lifecycle도 건드리지 않는다.

실기기 실험에서 새 간극이 나오면 Core 이슈로 올리고 이 표에 한 줄 추가한다.

---

## 실기기 실험

A1에서 수행한다. 대부분 Core fixture로 관측한다. 결과가 기대와 다르면 Core 이슈로 올린다.

| ID | 질문                                                                 | 방법                                                                                 | 기대                                   |
| -- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | -------------------------------------- |
| E1 | proot 아래에서 `/proc`이 child를 올바르게 보이는가                   | `echo-server` 응답 pid와 proot 안 `ps` / `/proc/<pid>/stat` 비교                     | 일치. Phase 3 Resource Manager 전제    |
| E2 | `tokio::process`의 exit 감지가 제때 되는가                            | `crash-server` 기동 후 종료 → Core가 상태를 바꾸기까지의 지연                        | Linux CI와 같은 자릿수                 |
| E3 | process group 신호가 손자까지 닿는가                                 | `group-server`(손자 생성) → idle stop → proot 안 잔존 process 확인                   | 잔존 0. `process_group(0)` + killpg 동작 |
| E4 | daemon이 SIGKILL로 죽으면 child가 남는가                             | 요청으로 app을 깨운 뒤 `kill -9 nimwaked`, 그리고 `kill -9 <proot pid>` 각각         | 결과 기록. 남으면 A2 orphan 정리 설계  |
| E5 | Termux 쪽 SIGTERM이 graceful shutdown으로 이어지는가                 | `kill -TERM <proot-distro pid>` vs proot 안 nimwaked pid에 직접 → `shutdown_timeout` 준수 여부 | `stop` 경로 결정 근거                  |
| E6 | 재기동 직후 같은 port bind가 되는가                                  | nimwaked 재시작을 1초 간격으로 10회                                                   | `address in use` 없음                  |
| E7 | 화면 꺼짐 · Doze에서 idle timer와 cold start가 정상인가              | wake lock 유무 × 화면 꺼짐 1시간 → idle 도달 시각, 다음 cold start latency           | wake lock 있으면 timer 오차 < 수 초    |

실험에 필요한 fixture(`echo-server`, `crash-server`, `group-server`, `slow-start-server`)는 #3의 artifact 목록에 들어 있다.

---

## 이 레포의 설계 결정

| ID   | 결정                                                       | 이유                                                                                   |
| ---- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| D-A1 | Host Layer MVP는 POSIX shell. 이후 `nimwake-hostd`는 조직 코어 언어인 Rust로 | PRD §8이 허용. 실험 결과 전에는 무엇이 어려운지 모른다. MVP 단계에서 Termux에 Rust toolchain 불필요 |
| D-A2 | `host.conf`는 `KEY=value` (shell source)                   | shell에서 TOML을 안전하게 파싱할 수 없다. PRD §32의 TOML은 hostd 도입 시점에 전환      |
| D-A3 | Core binary 빌드는 Core CI가 소유한다. 이 레포는 artifact만 받는다 ([nimwake#3](https://github.com/nimwake/nimwake/issues/3)) | 빌드 책임이 두 레포로 갈라지지 않는다. target · 빌드 방식은 Core가 정한다 |
| D-A4 | Core는 commit SHA로 `core.lock`에 pin                       | 검증 리포트의 재현성. branch 이름은 움직인다                                            |
| D-A5 | health probe는 미등록 Host → `404`                          | probe가 app을 깨우면 scale-to-zero가 무력화된다. Core §74 계약 ([nimwake#7](https://github.com/nimwake/nimwake/issues/7)) |
| D-A6 | 실기기 테스트는 CI 밖, 결과는 `.docs/validation/` 리포트    | 기기 · 제조사 · OS 조합이 CI로 재현되지 않는다                                         |
| D-A7 | 개발환경은 macOS와 WSL2만 지원                              | 팀 개발환경. Windows 네이티브 shell은 CRLF · 실행 비트 · POSIX 차이로 기기 스크립트를 깨뜨린다 |
| D-A8 | Guest는 `proot-distro`의 Ubuntu 26.04 (`ubuntu:26.04`)로 고정 | 첫 실기기(A1)가 이 버전으로 통과했다. Core binary는 musl static이라 glibc와 무관하지만, app runtime(Node 등)과 apt 패키지는 guest 버전에 따라 달라진다. alias `ubuntu`는 최신을 가리켜 기기마다 달라진다 |

---

← [02. 마일스톤](02-milestones.md) · [Phase 1](README.md)
