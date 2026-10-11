# proot Lifecycle과 Filesystem Layout

> **Nimwake Android PRD** › 아키텍처
>
> 원문 구간: `PRD.md` §16–§17

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
  /opt/nimwake/bin/nimwaked
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

← [Network Recovery와 Health Check](03-network.md) · [PRD 인덱스](../README.md) · [Storage · Release Cleanup · Log Rotation](../03-operations/01-storage-and-logs.md) →
