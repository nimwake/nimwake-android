# 03. Core v0.1.0-rc1 — 실기기 lifecycle

> **일시:** 2026-10-09 · **결과:** boot 경로 · lifecycle · graceful stop PASS
>
> Core `v0.1.0`은 이 레포의 Android 8항목 리포트를 기다린다. 이후 검증은 rc1 binary로 한다.

---

## 환경

[02. A3](02-a3-boot.md)과 같고 Core만 바뀌었다.

| 항목 | 값 |
| ---- | -- |
| Core | `nimwake/nimwake@17975b1` — release **v0.1.0-rc1** (prerelease), `aarch64-unknown-linux-musl` (cross 0.2.5, rustc 1.99.0) |
| 받는 방법 | `make fetch-core` → GitHub release asset `nimwake-aarch64-linux-musl.tar.gz`. `BUILD_INFO` commit이 `core.lock` rev와 같은지 검사 |
| 이전 | `adf1e20` (v0.0.5 + #11 + #14 브랜치, workflow artifact) |

## 경로

```text
make stop → make deploy → ~/.termux/boot/10-nimwake (부팅 경로 그대로) → make test-boot → make stop → 10-nimwake
```

## 결과

```text
ok  boot reached READY                 (10-nimwake: ready: health 404 after 1s)
ok  health probe 404
ok  every application is asleep after boot
ok  cold start   pid=21242  0.041516s
ok  warm         pid=21242  0.017456s  (same PID)
ok  sleep        pid=21242 gone
ok  cold start   pid=21864  0.040753s  (new PID)
PASS boot
```

graceful stop — app이 깨어 있는 상태에서 `make stop`:

```text
shutdown signal received signal="SIGTERM"
gateway is shutting down, no longer accepting connections
stopping every application
stopping application app=echo ... reason=daemon shutdown
```

정지 후 `/opt/nimwake/bin/` 아래 프로세스 0개.

## 관찰

- **rc1 binary가 자기 버전을 `0.0.1`로 알린다.** 기동 로그 첫 줄이 `nimwaked 0.0.1 — 1 application(s) validated`다. `BUILD_INFO`는 `ref=v0.1.0-rc1`이므로 binary는 맞다. Core의 Cargo 패키지 버전이 release 태그와 맞춰지지 않은 것으로 보인다 — 운영 로그만으로는 어떤 release가 도는지 알 수 없다. Core에 알린다.
- cold start는 adf1e20과 같은 수준이다 (35–45ms).
