# 03. Core 동기화

> **Phase 1 — Android MVP** › Core 동기화
>
> 이 문서는 두 레포 사이의 **계약과 피드백 경로**를 소유한다. Core 요구사항 자체는 Core PRD가 소유하고,
> Core에 요청하는 변경의 상세 내용은 Core 이슈가 소유한다. 여기에는 요약과 링크만 둔다.

---

## 동기화 지점

| Core                       | Android                    | 주고받는 것                                                     |
| -------------------------- | -------------------------- | --------------------------------------------------------------- |
| 지금                       | A0                         | Core 이슈 #3–#7 등록 (아래)                                     |
| `v0.0.3` merge + #3        | A1 시작                    | `core.lock` = v0.0.3 merge SHA, 그 SHA의 aarch64 artifact        |
| `v0.0.4` 진행 중           | A1 결과                    | 실험 E1–E7 결과 → 기존 이슈에 코멘트 또는 새 Core 이슈           |
| `v0.0.4` 완료              | A5                         | E2E workload · `RequestTrace`/`StartupTrace` 지표를 기기에서 재실행 |
| `v0.0.5` 판정 전           | A5 24h soak                | soak 리포트 → Core stress · leak 판정의 참고 자료              |
| `v0.0.5` `release.yml`     | `fetch-core.sh` 경로 변경  | workflow artifact → release artifact                            |
| `v0.1.0` 직전              | A6 72h soak                | Android 체크리스트 → Core acceptance                            |

`core.lock`을 올릴 때마다 A1 lifecycle · A2 recovery 시나리오를 다시 돌리고 리포트를 남긴다.

---

## Core 이슈

Core `v0.0.3` 코드(PR #2)를 읽고 실기기 없이 확정된 간극과, 이 계획이 유효하기 위한 선행 변경이다.

| 이슈 | 내용 | Android 쪽 영향 | 필요 시점 |
| ---- | ---- | --------------- | --------- |
| [nimwake#3](https://github.com/nimwake/nimwake/issues/3) | aarch64 빌드 artifact job (`nimwaked` + fixture) | 이 레포는 빌드하지 않고 artifact만 받는다 | **A1 시작 전** |
| [nimwake#4](https://github.com/nimwake/nimwake/issues/4) | Android 검증 시점을 `v0.1.0` 이후 → `v0.0.3` 이후 병렬로 (Core PRD §50, phase 문서) | 단일 출처 규칙상 이 계획의 전제 | A1 시작 전 |
| [nimwake#5](https://github.com/nimwake/nimwake/issues/5) | gateway listen address 설정 — 지금은 `127.0.0.1:8080` 고정 | LAN에서 접근 불가. **A5 blocker** | A5 전 (`v0.0.4` 권장) |
| [nimwake#6](https://github.com/nimwake/nimwake/issues/6) | 종료 코드로 실패 원인 구분 (`78` 설정 오류 / `69` bind / `1`) | supervisor의 crash-loop 판정 (PRD §24) | A2 (없으면 휴리스틱) |
| [nimwake#7](https://github.com/nimwake/nimwake/issues/7) | host interface 계약 — health probe가 app을 깨우지 않음, 인자 · 신호 명시 | supervisor health probe (D-A5) | A2 |

### 이슈가 해결되기 전의 임시 방식

- **#3**: A1까지 늦어지면 Core 레포에서 한 번 수동 빌드한다. 이 레포에 빌드 스크립트를 만들지 않는다. → [01 §5](01-repository-setup.md#5-core-binary-조달)
- **#5**: A1–A4는 기기 내부 loopback 또는 `ssh -L 8080:127.0.0.1:8080`. Termux 쪽 TCP relay는 쓰지 않는다 — 측정값을 오염시킨다.
- **#6**: "기동 후 N초 안에 종료"를 연속 K회 보면 crash-loop로 판정한다.
- **#7**: 미등록 Host로 요청해 `404`를 받으면 alive. 미등록 Host는 `acquire()` 전에 반환되므로 app을 깨우지 않는다 (`gateway/mod.rs` `handle`).

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
| D-A5 | health probe는 미등록 Host → `404`                          | probe가 app을 깨우면 scale-to-zero가 무력화된다. [nimwake#7](https://github.com/nimwake/nimwake/issues/7) 결과에 따라 교체 |
| D-A6 | 실기기 테스트는 CI 밖, 결과는 `.docs/validation/` 리포트    | 기기 · 제조사 · OS 조합이 CI로 재현되지 않는다                                         |
| D-A7 | 개발환경은 macOS와 WSL2만 지원                              | 팀 개발환경. Windows 네이티브 shell은 CRLF · 실행 비트 · POSIX 차이로 기기 스크립트를 깨뜨린다 |

---

← [02. 마일스톤](02-milestones.md) · [Phase 1](README.md)
