# Configuration · Host CLI · Doctor

> **Nimwake Android PRD** › 배포와 설치
>
> 원문 구간: `PRD.md` §32–§34

---

## 32. Configuration

Host Layer config 예:

```toml
[host]
name = "android-node-01"

[proot]
distribution = "ubuntu"
nimwaked_binary = "/usr/local/bin/nimwaked"

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
[OK] nimwaked
[OK] wake lock
[WARN] battery optimization status unknown
[OK] storage
[OK] network
[OK] boot script
```

Android 설정 중 자동 판별이 불가능한 항목은 수동 확인 안내를 제공한다.

---

← [Build · Update · Rollback](01-build-and-update.md) · [PRD 인덱스](../README.md) · [Installation Flow와 Bootstrap](03-installation.md) →
