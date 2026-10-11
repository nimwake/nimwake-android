# 장애 시나리오

> **Nimwake Android PRD** › 운영
>
> 원문 구간: `PRD.md` §42

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

← [Thermal과 Battery 운영](03-thermal-and-battery.md) · [PRD 인덱스](../README.md) · [Build · Update · Rollback](../04-delivery/01-build-and-update.md) →
