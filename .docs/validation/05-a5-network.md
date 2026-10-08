# 05. A5 — LAN lifecycle · Wi-Fi 복구 · soak 시운전

> **마일스톤:** A5 · **일시:** 2026-10-09 · **결과:** LAN lifecycle · 동시 cold start 20 → process 1 · Wi-Fi 끊김 41초 뒤 복구, daemon 생존
>
> Core `v0.1.0` Android 8항목의 **Network recovery**. 24h · 72h soak은 별도 리포트.

---

## 환경

[04. A2](04-a2-recovery.md)와 같다. Core `17975b1` (v0.1.0-rc1), supervisor(`nimwake-host`) 경유.

**LAN 노출:** `~/.nimwake-host/host.conf`에 `NIMWAKE_LISTEN=0.0.0.0:8080` — 사용자 승인 후 켰다 (Core PRD §74, 노출은 opt-in). Core는 TLS도 인증도 없다. 같은 LAN 안에서만 쓴다.

```text
listening on http://0.0.0.0:8080 — every application starts asleep
```

## LAN — `make test-lan`

개발 머신(WSL) → LAN → 기기 `192.168.0.25:8080`.

```text
ok  health probe 404 over LAN
ok  cold → warm over LAN  pid=13311 (same PID)
ok  sleep        pid=13311 gone
ok  20 concurrent cold requests → one process (pid 13325)
PASS lan
```

**동시 cold start 20개가 process 하나로 합쳐졌다.** Core의 핵심 불변식(Core PRD §16)이 proot 아래 실기기 · 실제 네트워크에서도 성립한다.

## Wi-Fi 복구 — `make test-wifi`

사람이 기기에서 Wi-Fi를 끄고 약 30초 뒤 켰다.

```text
nimwaked pid=13274
..  LAN down at 01:22:05
ok  LAN back after 41s
ok  nimwaked survived (pid 13274)
ok  request after reconnect → 200 (pid 14256)
PASS wifi
```

- **daemon은 재시작되지 않았다.** 네트워크 장애로 Nimwake를 내리지 않는다 (PRD §13).
- 복구 41초는 Wi-Fi를 끈 시간(약 30초) + 재연결 시간이다. 기기 IP(DHCP)는 그대로였다. IP가 바뀌는 환경에서는 ssh 설정과 ingress가 따라가야 한다 — Host Layer 밖이다.

## soak 시운전

30초 간격 4표본 (Core rc1).

```text
samples          4  (2026-10-09 00:34:01 → 00:35:32)
max gap          31s
non-200          0
cold start       p50 0.020s  p95 0.044s  max 0.044s
apps left awake  0 samples
daemon restarts  0
daemon RSS       2024 → 2276 KB
battery          NA–NA%  max temp NA°C
```

**배터리 · 온도가 NA였다.** Android(SELinux)가 앱에서 `/sys/class/power_supply`를 막는다. sampler가 Termux:API(`termux-battery-status`, timeout 10s)를 쓰도록 바꿨다. `pkg install termux-api`(0.60.0)는 했고, **Termux:API 앱이 없으면 명령이 응답하지 않는다** (timeout → exit 124). 앱 설치 전까지 soak의 배터리 · 온도는 NA다.

## 남은 것

- [ ] Termux:API 앱 (F-Droid) → 배터리 · 온도
- [ ] 24h soak → 72h soak
