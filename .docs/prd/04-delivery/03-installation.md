# Installation Flow와 Bootstrap

> **Nimwake Android PRD** › 배포와 설치
>
> 원문 구간: `PRD.md` §35–§36

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

← [Configuration · Host CLI · Doctor](02-configuration-and-cli.md) · [PRD 인덱스](../README.md) · [Tailscale · Cloudflare Tunnel · Caddy 프로필](../05-profiles/01-network-profiles.md) →
