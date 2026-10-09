# 09. Android 8항목 — Core v0.1.0 판정 근거

> Core [`04-acceptance.md` "Android Device"](https://github.com/nimwake/nimwake/blob/main/.docs/phases/phase-1/04-acceptance.md)는 이 레포의 리포트로 판정한다. 이 문서는 그 **근거 색인**이다 — 수치와 원본은 각 리포트에 있다.
>
> **상태 (2026-10-09 15:30):** 6/8 충족. 24h · 72h soak은 Core `d7c5590`으로 진행 중 (10-09 13:44 → 10-12 13:44).

---

## 기기 · binary

| | |
| - | - |
| 기기 | Samsung Galaxy A51 5G (`SM-A516N`) · Android 13 · Linux 4.19 · 4 GB RAM 급 |
| Host | F-Droid Termux 0.118.3 · Termux:Boot · Termux:API · proot-distro 5.9.0 · Ubuntu 26.04.1 |
| Core | **판정 대상 `d7c5590`** (`nimwaked 0.1.0`, main · release.yml run artifact). 일부 근거는 그 전 `v0.1.0-rc1`(`17975b1`)로 얻었다 — 아래 "binary" 열 |

## 8항목

| 항목 | 상태 | 근거 | binary |
| ---- | ---- | ---- | ------ |
| **Install** | ✓ | 수동 설치로 전 시나리오 통과 ([01](01-a1-manual-baseline.md)) · `make install` 멱등(설치된 기기에서 0 change) ([02-milestones A4](../phases/phase-1/02-milestones.md#a4--install-automation-mvp-1-자동)). 초기화 기기에서 `make install` 한 번은 **72h 뒤** | rc1 · d7c5590 |
| **Boot recovery** | ✓ | 재부팅 6회 연속 무인 READY, 부팅 직후 전부 SLEEPING ([02](02-a3-boot.md)) · supervisor 경유 부팅 ([04](04-a2-recovery.md)) | rc1 |
| **Cold start** | ✓ | loopback · LAN cold start, 1시간 방치 뒤 103ms (swap-in) ([02](02-a3-boot.md) · [05](05-a5-network.md)) · bench cold start 8.79ms vs CI 51.85ms ([08](08-core-d7c5590-bench.md)) | rc1 · **d7c5590** |
| **Scale-to-zero** | ✓ | idle → sleep → 새 PID (lifecycle 전 회차) · 동시 cold start 20 → process 1 (LAN) · storm 1000 → spawn 1 ([05](05-a5-network.md) · [08](08-core-d7c5590-bench.md)) · soak 표본마다 요청 직전 app 0 | rc1 · **d7c5590** |
| **Daemon recovery** | ✓ | `kill -9` → 1–2초 재기동 · exit 78 → UNHEALTHY · stop 잔존 0 ([04](04-a2-recovery.md) · [08](08-core-d7c5590-bench.md)) · proot가 죽은 뒤 고아 정리 → 5초 복구 ([06](06-a1-experiments.md)) | rc1 · **d7c5590** |
| **Network recovery** | ✓ | Wi-Fi 끊김 → 41초 뒤 복구, daemon 재시작 없음 ([05](05-a5-network.md)) | rc1 |
| **24h soak** | 진행 중 | `d7c5590` 72h 실행의 24h 시점 (10-10 13:44). 참고: rc1 12h 결함 없음 ([07](07-soak-rc1-12h.md)) | d7c5590 |
| **72h soak** | 진행 중 | 10-09 13:44 → 10-12 13:44. 재부팅되어도 sampler가 이어서 돈다 (#19 · #20) | d7c5590 |

### 72h 뒤 `d7c5590`으로 다시 돌릴 것

판정 대상 binary로 아직 직접 확인하지 않은 항목이다. 각각 수 분이다.

| 항목 | 명령 | 이유 |
| ---- | ---- | ---- |
| Boot recovery | 재부팅 1회 → `make test-boot` | rc1로만 재부팅했다 |
| Network recovery | `make test-wifi` | rc1로만 했다 |
| Install | Termux 데이터 삭제 → `make install` | 초기화 기기 미검증 (A4 완료 조건) |

`v0.1.0` 태그가 `d7c5590`과 다른 commit을 가리키면 태그 binary로 lifecycle · recovery를 다시 돌린다 ([03-core-sync](../phases/phase-1/03-core-sync.md)).

## Android PRD §44 성공 기준

| # | 기준 | 상태 |
| - | ---- | ---- |
| 1 | 재부팅 후 수동 SSH 없이 복구 | ✓ — 단, **비밀번호 잠금 기기는 재부팅 후 잠금 해제 1회**가 필요하다 ([02](02-a3-boot.md)) |
| 2 | 24시간 이상 안정 | 진행 중 (rc1 12h 결함 없음) |
| 3 | Wi-Fi 재연결 후 자동 복구 | ✓ ([05](05-a5-network.md)) |
| 4 | crash 후 자동 재시작 | ✓ — daemon crash · proot 죽음 모두 ([04](04-a2-recovery.md) · [06](06-a1-experiments.md)) |
| 5 | reboot 후 app은 sleeping | ✓ ([02](02-a3-boot.md)) |
| 6 | 저장공간 부족을 사전 감지 | 부분 — 부팅 때 `boot.log`에 WARN(<1 GB), `make doctor` WARN(<10 GB), soak가 `free_mb`를 기록. 알림 · 자동 정리는 Phase 2 |
| 7 | Core에 Android 전용 코드 없음 | ✓ — Core에 요청한 변경은 모두 플랫폼 중립이다 (listen 주소 · 종료 코드 · health 계약 · 버전 · bench 패키징) |
| 8 | Host Layer 없이 Core는 Linux에서 그대로 | ✓ — Core CI(ubuntu)가 Host Layer 없이 돈다 |

## 판정에 함께 넘길 관찰

- **동시 연결 한계:** proot(ptrace) 비용과 커널 `somaxconn 128` 때문에 동시 연결 수십부터 무너진다. Nimwake 고유 구간이 아니고 홈서버 규모에서는 문제 없다 ([08](08-core-d7c5590-bench.md)). bench의 storm gate는 이 기기에서 늘 실패한다.
- **proot가 죽으면** 고아 nimwaked가 ENOSYS로 멈춘다 — Core 결함이 아니고 Host Layer가 정리한다 ([06](06-a1-experiments.md)).
- **오래 쉰 뒤 첫 cold start**는 100ms 안팎 (swap-in). 평소 p50 40–50ms.
