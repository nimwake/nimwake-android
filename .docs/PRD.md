# PRD

## 1. 문서 개요

- **프로젝트명:** Nimwake Android Host Layer
- **상위 프로젝트:** Nimwake
- **역할:** Android 스마트폰에서 Nimwake Core를 안정적으로 실행하기 위한 플랫폼 전용 호스트 레이어
- **초기 대상 장비:** Android Smartphone / RAM 4GB / Storage 64GB
- **기본 환경:** Android → Termux → Ubuntu proot → Nimwake
- **핵심 목표:** Android 특유의 제약을 Nimwake Core 바깥에서 흡수하여, Nimwake 자체는 일반 Linux 애플리케이션처럼 동작하게 한다.

---

## 2. 제품 정의

Nimwake Android Host Layer는 Android 스마트폰을 Nimwake 실행 노드로 사용하기 위한 플랫폼 적응 계층이다.

Nimwake Core는 Android를 직접 이해하지 않는다.

Android Host Layer가 다음 문제를 대신 처리한다.

- Termux 기동
- Ubuntu proot 진입
- Nimwake daemon 시작 및 복구
- Android 재부팅 대응
- Battery Optimization 대응
- Wake Lock 관리
- Wi-Fi 절전 대응
- 저장공간 관리
- 프로세스 재시작
- 로그 수집
- 네트워크 점검
- 발열 및 배터리 상태 운영 가이드
- Termux / Android 업데이트 대응

구조:

```text
Android OS
   │
   ▼
Termux
   │
   ▼
Android Host Layer
   │
   ├── Boot
   ├── Wake Lock
   ├── Network
   ├── Health
   ├── Recovery
   └── proot launcher
          │
          ▼
      Ubuntu proot
          │
          ▼
        Nimwake
```

---

## 3. 설계 원칙

### 3.1 Nimwake Core와 Android 책임 분리

Nimwake Core:

```text
HTTP Gateway
App Lifecycle
Scale-to-Zero
Scheduler
Resource Manager
Registry
```

Android Host Layer:

```text
Android Boot
Termux Lifecycle
Wake Lock
proot Lifecycle
Network Availability
Daemon Recovery
Host Health
Storage
```

Nimwake Core에 Android API나 Termux 전용 로직을 직접 넣지 않는다.

---

## 4. 목표

1. Android 재부팅 후 Ember를 자동 복구한다.
2. Termux가 background에서 종료되는 위험을 최소화한다.
3. Ubuntu proot 환경을 자동으로 기동한다.
4. Nimwake daemon이 죽으면 감지하고 복구한다.
5. 네트워크가 끊겼다가 돌아와도 서비스가 복구된다.
6. Android-specific 상태를 Nimwake Core와 분리한다.
7. 사용자가 SSH로 매번 수동 복구하지 않아도 된다.
8. 장기 운영 시 저장공간, 로그, 발열 문제를 관리한다.
9. Android 환경의 이상 상태를 CLI/로그에서 확인할 수 있다.
10. 다른 Android 기기로 이전하기 쉽게 구성한다.

---

## 5. Non-Goals

초기 버전에서는 다음을 목표로 하지 않는다.

- Android 커널 수정
- Root 권한 필수화
- Custom ROM
- Docker 지원
- cgroup hard isolation
- Android 앱 GUI 관리 도구
- MDM
- 배터리 보호를 위한 하드웨어 제어
- Wi-Fi router 자동 설정
- 공인 IP / DNS 자동 구성
- Cloudflare / Tailscale 필수화

---

## 6. 전체 구조

```text
┌───────────────────────────────┐
│          Android OS           │
│                               │
│ Battery Manager               │
│ Wi-Fi                         │
│ Storage                       │
│ Boot Events                   │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│            Termux             │
│                               │
│ host supervisor               │
│ wake lock                     │
│ boot launcher                 │
│ host health                   │
│ network check                 │
│ log rotate                    │
└───────────────┬───────────────┘
                │
                ▼
┌───────────────────────────────┐
│       Ubuntu proot            │
│                               │
│ emberd                        │
│ apps                          │
│ optional ingress              │
└───────────────────────────────┘
```

---

## 7. Host Layer 구성 요소

### 7.1 Boot Launcher

역할:

- Android 부팅 후 Termux 환경 복구
- Wake Lock 획득
- Ubuntu proot 실행
- Host Supervisor 실행
- Nimwake daemon 실행

권장 구조:

```text
Android Boot
   ↓
Termux:Boot
   ↓
host-start.sh
   ↓
termux-wake-lock
   ↓
proot-distro login ubuntu
   ↓
emberd
```

---

## 8. Host Supervisor

Android Host Layer의 핵심 상주 프로세스.

가능하면 매우 가볍게 구현한다.

MVP에서는 shell script 또는 소형 Rust binary로 시작할 수 있다.

역할:

```text
Host Supervisor
├── emberd health check
├── proot health check
├── network check
├── disk check
├── restart policy
└── host event logging
```

장기적으로 Rust binary `nimwake-hostd`로 구현 가능하다.

---

## 9. 프로세스 계층

```text
Termux
│
├── nimwake-hostd
│
└── Ubuntu proot
    │
    ├── emberd
    ├── application processes
    └── optional integrations
```

중요 원칙:

- `nimwake-hostd`는 Android/Termux 레이어에 존재
- `emberd`는 Ubuntu/Linux 레이어에 존재
- 두 프로세스의 책임을 섞지 않는다.

---

## 10. Boot Recovery

Android reboot 후 다음 순서를 목표로 한다.

```text
BOOT_COMPLETED
   ↓
Termux:Boot
   ↓
Host Layer Start
   ↓
Acquire Wake Lock
   ↓
Check Storage
   ↓
Check Network
   ↓
Start Ubuntu proot
   ↓
Start Nimwake
   ↓
Health Check
   ↓
READY
```

애플리케이션은 자동으로 모두 실행하지 않는다.

Ember의 기본 정책을 그대로 따른다.

```text
App State after reboot:

blog       SLEEPING
api        SLEEPING
portfolio  SLEEPING
```

`always_on = true` 앱만 Ember가 다시 실행한다.

---

## 11. Wake Lock

Android가 CPU를 과도하게 sleep시키지 않도록 Termux Wake Lock을 사용한다.

예:

```bash
termux-wake-lock
```

종료:

```bash
termux-wake-unlock
```

Host Layer는 현재 Wake Lock 상태를 운영 로그에 기록한다.

---

## 12. Battery Optimization

설치 가이드에 반드시 포함한다.

사용자는 Android 설정에서 다음 항목을 확인해야 한다.

- Termux battery optimization 제외
- background activity 허용
- background network 허용
- manufacturer-specific battery killer 설정 비활성화

Host Layer는 이 설정을 완전히 강제할 수 없으므로 설치 시 검증 checklist를 제공한다.

---

## 13. Network Recovery

Wi-Fi는 장기간 연결 중 다음 문제가 발생할 수 있다.

- AP 재시작
- DHCP 갱신
- Android Wi-Fi sleep
- 인터넷 단절
- VPN/Tunnel 연결 해제

Host Layer는 네트워크 상태를 주기적으로 검사한다.

상태:

```text
ONLINE
DEGRADED
OFFLINE
RECOVERING
```

네트워크 장애 시 Nimwake 자체를 종료하지 않는다.

```text
Internet Offline
      ↓
Apps remain available locally
      ↓
Network returns
      ↓
Ingress integration reconnect
```

---

## 14. Network Health Check

검사 순서 예:

1. Local interface 존재
2. Default route 존재
3. LAN gateway 접근 가능
4. Optional external connectivity check

외부 서비스에 의존하지 않기 위해 public connectivity check는 configurable하게 둔다.

예:

```toml
[network]
check_interval_seconds = 30
internet_check = false
```

---

## 15. Optional Network Integrations

다음은 Android Host Layer의 optional integration이다.

```text
Cloudflare Tunnel
Tailscale
Reverse SSH Tunnel
Caddy
```

Host Layer는 integration process가 죽었을 때 재시작하는 hook을 제공할 수 있다.

Nimwake 자체에는 이 의존성이 없다.

---

## 16. proot Lifecycle

Ubuntu proot는 Android와 Nimwake 사이의 Linux compatibility layer로 사용한다.

Host Layer는 다음을 관리한다.

- proot 실행 여부
- proot 내부 Nimwake daemon 실행 여부
- 예상 mount 경로
- environment variables
- working directory

MVP 명령 예:

```bash
proot-distro login ubuntu -- \
  /opt/nimwake/bin/emberd
```

실제 경로는 설치 방식에 따라 configurable해야 한다.

---

## 17. Filesystem Layout

### Termux Layer

```text
$HOME/.nimwake-host/
├── config.toml
├── logs/
├── state/
├── scripts/
└── run/
```

### Ubuntu Layer

```text
/home/nimwake/.nimwake/
├── apps/
├── logs/
├── data/
├── config/
└── nimwake.sock
```

가능하면 앱 artifact와 DB는 Android internal storage의 안정적인 경로를 사용한다.

공유 스토리지(`/sdcard`)는 권한 및 filesystem semantics 문제 때문에 Nimwake 내부 데이터의 기본 위치로 사용하지 않는다.

---

## 18. Storage Policy

64GB 저장공간을 기준으로 다음 정책을 제공한다.

예:

```text
System + Apps       20~30GB
Nimwake Releases      10GB
Logs                 1GB
Databases            variable
Free Reserve        >= 10GB 권장
```

Host Layer는 free storage threshold를 감시한다.

```toml
[storage]
minimum_free_gb = 5
warning_free_gb = 10
```

---

## 19. Release Cleanup

Nimwake 앱 release가 누적되면 자동 정리가 필요하다.

기본값 예:

```text
Keep latest releases per app: 3
```

예:

```text
blog/releases/

001
002
003
004
005
```

정리 후:

```text
003
004
005
```

현재 release와 rollback target은 삭제하지 않는다.

---

## 20. Log Rotation

Host Layer 로그와 Nimwake 로그 모두 무한 증가하면 안 된다.

기본 정책 예:

```toml
[logging]
max_file_mb = 20
max_files = 3
```

Host Layer 로그:

```text
host.log
boot.log
network.log
recovery.log
```

---

## 21. Health Model

Android Host 전체 상태:

```text
HEALTHY
DEGRADED
UNHEALTHY
RECOVERING
```

HEALTHY:

```text
Termux OK
Wake Lock OK
proot OK
emberd OK
storage OK
```

DEGRADED 예:

```text
internet offline
low storage
high temperature warning
optional tunnel unavailable
```

UNHEALTHY 예:

```text
proot launch failure
emberd repeated crash
storage critically low
```

---

## 22. Nimwake Health Check

Host Layer는 Nimwake Admin IPC 또는 local health endpoint를 통해 상태를 확인한다.

우선순위:

```text
Unix Socket IPC
   ↓
Fallback local health endpoint
```

단순 PID 존재만으로 healthy 판정하지 않는다.

---

## 23. Restart Policy

Nimwake daemon crash:

```text
Crash
  ↓
Restart
  ↓
Health Check
```

반복 crash 방지:

```text
1st restart   immediate
2nd restart   +5 sec
3rd restart   +15 sec
4th restart   +60 sec
...
```

Exponential Backoff을 사용한다.

예:

```toml
[recovery]
max_restarts = 5
restart_window_seconds = 300
```

반복 실패 시 `UNHEALTHY`로 전환한다.

---

## 24. Crash Loop 방지

다음 상황에서는 무한 재시작하지 않는다.

```text
invalid config
corrupted database
missing executable
disk full
permission failure
```

Host Layer는 failure reason을 기록하고 operator intervention이 필요한 상태로 둔다.

---

## 25. Android Process Kill 대응

Android가 Termux를 종료할 수 있다.

Host Layer는 완전한 방지를 보장할 수 없다.

대신 다음 전략을 사용한다.

1. Battery Optimization 제외
2. Wake Lock
3. Termux:Boot
4. 최소 상주 프로세스
5. 낮은 메모리 footprint
6. 장애 후 자동 복구

Nimwake 앱 자체는 대부분 sleeping 상태이므로 Android LMK 압박도 줄인다.

---

## 26. Thermal 운영

스마트폰은 장기간 서버 부하에서 발열 문제가 생길 수 있다.

Host Layer MVP에서는 hardware temperature 제어를 하지 않는다.

대신 가능한 경우 temperature 정보를 읽어 상태를 표시한다.

상태 예:

```text
NORMAL
WARM
HOT
CRITICAL
```

정확한 센서 접근은 기기별 차이가 크므로 optional capability로 둔다.

---

## 27. Thermal Policy

가능한 경우 다음 정책을 지원한다.

예:

```text
HOT
 ↓
new app cold start 제한
 ↓
existing request만 처리
```

CRITICAL:

```text
low priority apps stop
```

MVP에서는 warning만 제공하고 자동 thermal scheduling은 Post-MVP로 둔다.

---

## 28. Battery 운영

서버 운용 시 상시 전원 연결이 기본이다.

운영 가이드:

- 배터리 팽창 여부 주기적 확인
- 과도한 발열 환경 피하기
- 케이스 제거 고려
- 가능하면 충전 제한 기능 사용
- 화면 상시 켜기 금지
- 고부하 빌드는 서버에서 수행하지 않기

Host Layer에서 build를 수행하지 않는 정책은 발열 감소에도 중요하다.

---

## 29. Build Policy

Android 서버에서 애플리케이션 build를 기본적으로 수행하지 않는다.

```text
External Builder
   ↓
Artifact
   ↓
Android
   ↓
Nimwake Deploy
```

이유:

- CPU 부하
- RAM spike
- 발열
- storage I/O
- 배터리 스트레스
- build dependency 복잡도

단, 작은 Rust/Go binary 등의 수동 build는 사용자 선택 사항이다.

---

## 30. Update Strategy

두 종류의 업데이트를 분리한다.

### Nimwake Update

```text
new nimwake binary
   ↓
stop emberd
   ↓
replace
   ↓
start
   ↓
health check
```

### Android Host Layer Update

```text
host scripts / nimwake-hostd
```

Android OS / Termux / Ubuntu 업데이트와 Nimwake 업데이트를 분리한다.

---

## 31. Rollback

Nimwake binary 업데이트 실패 시 직전 버전으로 rollback할 수 있어야 한다.

예:

```text
~/.nimwake-host/bin/

emberd-current
emberd-prev
```

업데이트 후 health check 실패 시 이전 binary를 다시 실행한다.

---

## 32. Configuration

Host Layer config 예:

```toml
[host]
name = "android-node-01"

[proot]
distribution = "ubuntu"
ember_binary = "/usr/local/bin/emberd"

[boot]
auto_start = true
wake_lock = true

[health]
interval_seconds = 30

[recovery]
auto_restart = true
max_restarts = 5
restart_window_seconds = 300

[storage]
warning_free_gb = 10
minimum_free_gb = 5

[network]
check_interval_seconds = 30
internet_check = false

[logging]
max_file_mb = 20
max_files = 3
```

---

## 33. Host CLI

향후 Android 전용 CLI 제공 가능:

```bash
nimwake-host status
nimwake-host start
nimwake-host stop
nimwake-host restart
nimwake-host logs
nimwake-host network
nimwake-host storage
nimwake-host doctor
```

예:

```text
$ nimwake-host status

Host        android-node-01
Status      HEALTHY

Termux      OK
Wake Lock   ACTIVE
Ubuntu      RUNNING
Nimwake       RUNNING
Network     ONLINE
Storage     31 GB free
```

---

## 34. Doctor Command

`nimwake-host doctor`는 설치 및 운영 상태를 검사한다.

검사 항목:

```text
[OK] Termux
[OK] proot-distro
[OK] Ubuntu
[OK] emberd
[OK] wake lock
[WARN] battery optimization status unknown
[OK] storage
[OK] network
[OK] boot script
```

Android 설정 중 자동 판별이 불가능한 항목은 수동 확인 안내를 제공한다.

---

## 35. Installation Flow

초기 설치 UX:

```text
Install Termux
   ↓
Install required packages
   ↓
Install proot-distro
   ↓
Install Ubuntu
   ↓
Install Nimwake
   ↓
Install Host Layer
   ↓
Configure Boot
   ↓
Configure Wake Lock
   ↓
Run doctor
   ↓
READY
```

가능하면 bootstrap script로 자동화한다.

```bash
curl ... | sh
```

실제 공개 배포 시에는 curl pipe shell 외에 다운로드 후 검증 방식도 제공한다.

---

## 36. Bootstrap Script 책임

`install-android.sh`:

- dependency 확인
- proot 설치
- Ubuntu 존재 여부 확인
- host directory 생성
- config 생성
- boot script 설치
- Nimwake binary 배치
- doctor 실행

Secret이나 private key는 자동 생성/업로드하지 않는다.

---

## 37. Optional Tailscale Profile

관리용 VPN을 원하는 경우:

```text
Developer
   ↓
Tailscale
   ↓
Android
   ↓
SSH / Nimwake
```

Host Layer는 Tailscale 설치 가이드와 health hook 정도만 제공한다.

필수 dependency가 아니다.

---

## 38. Optional Cloudflare Tunnel Profile

Public service 노출 예:

```text
Internet
   ↓
Cloudflare Tunnel
   ↓
Nimwake
```

Host Layer는 tunnel process 재기동 hook을 지원할 수 있다.

Nimwake Core는 Cloudflare를 모른다.

---

## 39. Optional Caddy Profile

공인 IP와 port forwarding 환경:

```text
Internet
   ↓
Router
   ↓
Caddy
   ↓
Nimwake
```

Android에서 Caddy 운영이 적합한지는 환경별로 판단한다.

TLS termination은 Nimwake 밖에서 수행한다.

---

## 40. Security

Host Layer 기본 원칙:

- Android root 권한 불필요
- 앱 internal port는 loopback
- Nimwake admin은 Unix Socket
- SSH는 가능하면 key auth
- Public SSH exposure 금지 권장
- secret은 shared storage에 두지 않음
- `/sdcard`에 DB/secret 저장 금지 권장
- app artifact와 runtime data 분리
- Host Layer log에 secret 기록 금지

---

## 41. Backup

MVP에서는 자동 원격 backup을 필수로 하지 않는다.

백업 대상:

```text
Nimwake config
App manifests
SQLite DB
Application persistent data
Host config
```

백업 제외 가능:

```text
build artifacts
old releases
logs
```

향후 `nimwake-host backup`을 제공할 수 있다.

---

## 42. 장애 시나리오

### Android Reboot

```text
Boot
→ Termux:Boot
→ Host Layer
→ proot
→ Nimwake
```

### Nimwake Crash

```text
detect
→ restart
→ health check
```

### Wi-Fi Down

```text
service unavailable externally
→ local processes remain
→ reconnect
```

### Storage Low

```text
warning
→ release cleanup
→ log cleanup
→ critical alert
```

### App Memory Pressure

```text
Nimwake Resource Manager
→ app eviction
```

### Host Memory Pressure

```text
Nimwake app count reduced
→ Android still may kill Termux
→ boot/recovery strategy
```

---

## 43. MVP Scope

### Phase 0 — Manual Baseline

- Termux
- Ubuntu proot
- Nimwake 수동 실행
- SSH 접근
- 기본 서비스 검증

### Phase 1 — Boot Layer

- Termux:Boot
- host-start script
- wake lock
- proot automatic startup
- Nimwake automatic startup

### Phase 2 — Health / Recovery

- Nimwake health check
- restart policy
- exponential backoff
- recovery logs

### Phase 3 — Network / Storage

- network state
- storage threshold
- release cleanup hook
- log rotation

### Phase 4 — Host CLI

- status
- logs
- doctor
- restart
- storage
- network

### Phase 5 — Optional Integrations

- Tailscale profile
- Cloudflare Tunnel profile
- Caddy guide

### Phase 6 — Hardening

- binary rollback
- upgrade flow
- backup
- thermal monitoring
- long-running soak test

---

## 44. 성공 기준

초기 Android 머신에서 다음이 만족되면 MVP 성공으로 본다.

1. Android 재부팅 후 수동 SSH 없이 Ember가 복구된다.
2. 24시간 이상 안정적으로 Nimwake daemon이 동작한다.
3. Wi-Fi 재연결 후 서비스가 자동 복구된다.
4. Nimwake crash 후 자동 재시작된다.
5. 앱들은 reboot 후 기본적으로 sleeping 상태를 유지한다.
6. 저장공간 부족 상태를 사전에 감지한다.
7. Host Layer가 Nimwake Core의 Android-specific 코드 추가 없이 동작한다.
8. Host Layer를 제거해도 Nimwake Core는 일반 Linux에서 그대로 동작한다.

---

## 45. 권장 초기 운영 구성

```text
Android Phone
RAM 4GB / Storage 64GB
        │
        ▼
      Termux
        │
        ├── nimwake-hostd / host scripts
        │
        ├── wake lock
        │
        └── Ubuntu proot
                │
                ├── emberd
                ├── app processes
                └── optional tunnel/VPN
```

항상 실행:

```text
Host Supervisor
Nimwake
Optional ingress / VPN
```

On-Demand:

```text
Next.js
Node API
Python API
AI Agent
Rust / Go services
```

---

## 46. 제품 경계

최종 경계는 다음처럼 정의한다.

```text
Android Host Layer

"Android에서 Ember를 살아 있게 만드는 책임"


Nimwake Core

"필요한 애플리케이션만 살아 있게 만드는 책임"
```

이 두 책임을 분리함으로써 Ember는 일반 Linux PaaS로 유지되고, Android Host Layer만 Android 특유의 운영 문제를 해결한다.
