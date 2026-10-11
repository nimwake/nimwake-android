# Storage · Release Cleanup · Log Rotation

> **Nimwake Android PRD** › 운영
>
> 원문 구간: `PRD.md` §18–§20

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

← [proot Lifecycle과 Filesystem Layout](../02-architecture/04-proot-and-filesystem.md) · [PRD 인덱스](../README.md) · [Health Model과 Restart Policy](02-health-and-restart.md) →
