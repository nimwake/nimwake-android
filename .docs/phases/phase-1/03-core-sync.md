# 03. Core 동기화

> **Phase 1 — Android MVP** › Core 동기화
>
> 이 문서는 두 레포 사이의 **계약과 피드백 경로**를 소유한다. Core 요구사항 자체는 Core PRD가 소유한다.

---

## 동기화 지점

| Core                       | Android                    | 주고받는 것                                                     |
| -------------------------- | -------------------------- | --------------------------------------------------------------- |
| `v0.0.3` merge             | A0 → A1 시작               | `core.lock` = v0.0.3 merge SHA                                  |
| `v0.0.4` 진행 중           | A1 결과                    | 실험 E1–E7 결과, 피드백 F1–F4 → Core 이슈                      |
| `v0.0.4` 완료              | A5                         | E2E workload · `RequestTrace`/`StartupTrace` 지표를 기기에서 재실행 |
| `v0.0.5` 판정 전           | A5 24h soak                | soak 리포트 → Core stress · leak 판정의 참고 자료              |
| `v0.0.5` `release.yml`     | `core-build.yml` 교체      | aarch64 release artifact 다운로드로 전환                        |
| `v0.1.0` 직전              | A6 72h soak                | Android 체크리스트 → Core acceptance                            |

`core.lock`을 올릴 때마다 A1 lifecycle · A2 recovery 시나리오를 다시 돌리고 리포트를 남긴다.

---

## 선행: Core 문서 수정

단일 출처 규칙상 **Core PRD를 먼저 고쳐야 이 계획이 유효하다.** 현재 Core 문서는 Android 검증을 `v0.1.0` 이후로 두고 있다.

| Core 파일                                                    | 현재                                         | 변경                                                              |
| ------------------------------------------------------------ | -------------------------------------------- | ----------------------------------------------------------------- |
| `.docs/prd/04-platform/02-android.md` §50                    | "Core `v0.1.0` 이후 실제 Android device에서 검증한다." | "Core `v0.0.3` 이후 `nimwake-android`에서 병렬로 검증한다. `v0.1.0` 전에 24h · 72h soak를 통과한다." |
| `.docs/phases/phase-1/README.md` "이 페이즈에서 하지 않는 것" | "Android 검증은 `v0.1.0` **이후**에 수행한다." | 병렬 검증으로 바꾸고 이 레포 Phase 1을 링크                      |
| `.docs/phases/phase-1/04-acceptance.md`                      | Linux CI 항목만                              | "Android Device" 체크리스트 추가 (A6 완료 조건과 같은 8항목)      |
| `.docs/phases/phase-1/05-design-decisions.md`                | —                                            | 다음 번호(D28)로 "Android 검증 시점을 `v0.0.3` 이후로 당김" 기록 |
| `.docs/phases/phase-4/README.md`                             | "Android host tooling" = Later               | host tooling MVP는 `nimwake-android` Phase 1로 이동했음을 명시. Phase 4에는 `nimwake-hostd` 등만 남김 |

이 변경은 Core 레포의 별도 docs PR로 낸다. v0.0.3 PR(#2)에 섞지 않는다.

---

## Core 피드백 항목

Core `v0.0.3` 코드를 읽고 Android 쪽에서 이미 보이는 간극이다. 실기기 없이 확정된 것만 적는다.

### F1 — Gateway가 `127.0.0.1`에만 bind한다 · **A5 blocker**

`crates/nimwaked/src/main.rs`가 `SocketAddr::from(([127, 0, 0, 1], DEFAULT_GATEWAY_PORT))`로 고정한다.
LAN의 다른 기기에서 `curl http://PHONE_IP:8080`이 닿지 않는다.

- 제안: listen address를 설정으로. clap 도입이 부담이면 `NIMWAKE_LISTEN=0.0.0.0:8080` 환경 변수로 시작.
- 기본값은 loopback 유지가 맞다 (PRD §40 — 노출은 opt-in).
- 임시 우회: A1–A4는 기기 내부 loopback 또는 `ssh -L 8080:127.0.0.1:8080`으로 검증한다. Termux 쪽 TCP relay는 쓰지 않는다 — 측정값을 오염시킨다.

### F2 — 종료 코드가 원인을 구분하지 않는다

manifest 오류, port bind 실패, runtime 오류가 모두 `ExitCode::FAILURE`(1)다.
supervisor는 "재시도하면 나을 실패"와 "사람이 고쳐야 하는 실패"를 구분해야 한다. (Android PRD §24 crash-loop 방지)

- 제안: `sysexits` 관례 — 설정 · manifest 오류 `78 (EX_CONFIG)`, bind 실패 `69 (EX_UNAVAILABLE)`, 그 외 `1`.
- 임시: supervisor는 "기동 후 N초 안에 종료"를 연속 K회 보면 crash-loop로 판정한다.

### F3 — health endpoint가 없다

Android PRD §22는 Admin IPC 또는 local health endpoint를 전제한다. Core는 둘 다 Post-MVP다.

- 임시: 미등록 Host로 요청해 `404`를 받으면 alive. 미등록 Host는 `acquire()` 전에 반환되므로 app을 깨우지 않는다 (`gateway/mod.rs` `handle`).
- 제안: 이 동작을 **계약으로 고정**하는 테스트를 Core에 두거나, `acquire()`를 타지 않는 예약 경로(`/__nimwake/health` 등)를 둔다. 어느 쪽이든 "health 요청이 app을 깨우지 않는다"가 Core 테스트로 보장되어야 한다.

### F4 — daemon 실행 인터페이스가 계약이 된다

supervisor는 `nimwaked <apps_dir>` 형태와 SIGINT/SIGTERM graceful shutdown(PR #2의 D27)에 의존한다.

- 제안: 인자 형태 · 신호 · 종료 코드 변경은 Core CHANGELOG에 "host interface" 항목으로 적는다.

실기기 실험에서 나오는 항목은 F5부터 이어 번호를 붙인다.

---

## 실기기 실험

A1에서 수행한다. 대부분 Core fixture로 관측한다. 결과가 기대와 다르면 F 항목으로 올린다.

| ID | 질문                                                                 | 방법                                                                                 | 기대                                   |
| -- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | -------------------------------------- |
| E1 | proot 아래에서 `/proc`이 child를 올바르게 보이는가                   | `echo-server` 응답 pid와 proot 안 `ps` / `/proc/<pid>/stat` 비교                     | 일치. Phase 3 Resource Manager 전제    |
| E2 | `tokio::process`의 exit 감지가 제때 되는가                            | `crash-server` 기동 후 종료 → Core가 상태를 바꾸기까지의 지연                        | Linux CI와 같은 자릿수                 |
| E3 | process group 신호가 손자까지 닿는가                                 | `group-server`(손자 생성) → idle stop → proot 안 잔존 process 확인                   | 잔존 0. `process_group(0)` + killpg 동작 |
| E4 | daemon이 SIGKILL로 죽으면 child가 남는가                             | 요청으로 app을 깨운 뒤 `kill -9 nimwaked`, 그리고 `kill -9 <proot pid>` 각각         | 결과 기록. 남으면 A2 orphan 정리 설계  |
| E5 | Termux 쪽 SIGTERM이 graceful shutdown으로 이어지는가                 | `kill -TERM <proot-distro pid>` vs proot 안 nimwaked pid에 직접 → `shutdown_timeout` 준수 여부 | `stop` 경로 결정 근거                  |
| E6 | 재기동 직후 같은 port bind가 되는가                                  | nimwaked 재시작을 1초 간격으로 10회                                                   | `address in use` 없음                  |
| E7 | 화면 꺼짐 · Doze에서 idle timer와 cold start가 정상인가              | wake lock 유무 × 화면 꺼짐 1시간 → idle 도달 시각, 다음 cold start latency           | wake lock 있으면 timer 오차 < 수 초    |

`group-server`가 `dist/`에 포함되도록 `build-core.sh`에 넣는다.

---

## 이 레포의 설계 결정

| ID   | 결정                                                       | 이유                                                                                   |
| ---- | ---------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| D-A1 | Host Layer MVP는 POSIX shell. `nimwake-hostd`는 필요가 드러나면 | PRD §8이 허용. 실험 결과 전에는 무엇이 어려운지 모른다. Termux에 Rust toolchain 불필요 |
| D-A2 | `host.conf`는 `KEY=value` (shell source)                   | shell에서 TOML을 안전하게 파싱할 수 없다. PRD §32의 TOML은 hostd 도입 시점에 전환      |
| D-A3 | 교차 빌드는 `cargo-zigbuild` · `aarch64-unknown-linux-musl` | macOS · WSL · CI가 Docker 없이 같은 경로. proot glibc와 무관한 static binary          |
| D-A4 | Core는 commit SHA로 pin, `v0.0.5`까지 이 레포가 빌드       | Core release pipeline이 `v0.0.5`에 생긴다. 검증 리포트의 재현성                        |
| D-A5 | health probe는 미등록 Host → `404`                          | probe가 app을 깨우면 scale-to-zero가 무력화된다. F3 해결 시 교체                       |
| D-A6 | 실기기 테스트는 CI 밖, 결과는 `.docs/validation/` 리포트    | 기기 · 제조사 · OS 조합이 CI로 재현되지 않는다                                         |
| D-A7 | 개발환경은 macOS와 WSL2만 지원                              | 팀 개발환경. Windows 네이티브 shell은 CRLF · 실행 비트 · POSIX 차이로 기기 스크립트를 깨뜨린다 |

---

← [02. 마일스톤](02-milestones.md) · [Phase 1](README.md)
