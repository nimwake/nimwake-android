# 17. 초기화한 기기에 `make install` 한 번 — Core `v0.1.0-rc7`

> **일시:** 2026-10-15 · **Core:** `v0.1.0-rc7` (`1e2bf91`) · **결과:** PASS — Termux 데이터를 지운 폰에서 `make install` 한 번(7분 35초)으로 rc7 · 격리 daemon · 블로그까지 돌아왔다. A4(Install)의 완료 조건
>
> [#59](https://github.com/nimwake/nimwake-android/issues/59)의 마지막 항목 · [09 Android 8항목](09-android-acceptance.md)이 "rc5 soak 뒤"로 미뤄 둔 것

---

## 0. 지우기 전에

진행 중이던 rc7 soak(2 표본, 실패 0)을 멈추고, 폰에만 있는 것을 개발 머신으로 옮겼다 — soak 기록, `host.conf`, 로그. Termux 데이터를 지우면 proot Ubuntu(앱 · Node · Core)까지 함께 사라진다.

## 1. 사람이 한 것

| | |
| - | - |
| 폰 | 설정 → 앱 → Termux → 저장공간 → **데이터 삭제** (Termux:Boot · Termux:API는 그대로) |
| 폰 | Termux를 열어 bootstrap → `pkg install -y openssh && passwd && sshd && whoami` |
| 개발 머신 | `ssh-keygen -R "[192.168.0.25]:8022"` (호스트 키가 바뀌었다) → `ssh-copy-id` |

**걸린 것 하나:** 개발 머신에 공개 키 파일(`nimwake_phone.pub`)이 없어 `ssh-copy-id`가 실패했다. 개인 키에서 다시 꺼냈다 — `ssh-keygen -y -f ~/.ssh/nimwake_phone > ~/.ssh/nimwake_phone.pub`. 새 키를 만들 일은 아니다.

## 2. `make install` — 455초, exit 0

```text
== device: packages · proot Ubuntu · sshd     Termux 패키지 26개 · proot-distro 5.10.0 · termux-api
                                              [+] proot Ubuntu 26.04
                                              [+] sshd key login only
== deploy                                     setup-ubuntu: node v24.21.0 ← nodejs.org (sha256 확인)
                                              setup-ubuntu: blog → /home/nimwake/apps/blog
                                              nimwake-host · 부팅 스크립트
== supervisor                                 state RUNNING, ready after 1s
== doctor                                     nimwaked 0.1.0-rc7 · health 404 · sshd key only · storage · network
```

doctor의 WARN 둘은 예상대로다 — `host.conf`가 기본값이라 게이트웨이 점검이 꺼져 있고, 재부팅 전이라 `boot.log`가 없다.

## 3. 설정 되살리기 → 블로그

`host.conf`는 기기에만 있는 운영자 설정이라 install이 기본값(loopback)으로 만든다. 백업에서 되돌리고 `make restart`:

```text
NIMWAKE_LISTEN=0.0.0.0:8080 · NIMWAKE_NET_GATEWAY=192.168.0.1 · NIMWAKE_MIN_FREE_MEMORY_MB=512
launch: proot-distro login ubuntu --isolated --user nimwake -- /opt/nimwake/bin/nimwaked … --listen 0.0.0.0:8080 --min-free-memory-mb 512
```

| | |
| - | - |
| blog `/api/whoami` (LAN) | 200 · cold 1.58s · RSS 94 MB · node v24.21.0 |
| blog `/` | 200 |
| echo | 200 |
| `make apps` | blog · echo, SLEEPING |

부팅 자동 기동은 같은 날 초기화 직전에 rc7로 확인했다 ([16](16-core-rc7.md) §6).

## 4. 고칠 것 (출시 뒤)

- **`host.conf`가 초기화에서 살아남지 않는다.** 사람이 기억해서 되살려야 했다. 개발 머신에 사본을 두고 install이 그것을 쓰게 하면 한 번에 끝난다
- 첫 단계 안내(`make install`이 ssh 전에 보이는 것)에 '공개 키 파일이 없으면 개인 키에서 꺼낸다'를 넣는다
- 소비처 앱(개인 레포)은 install 뒤 `make deploy APP=…`로 다시 올린다 — 앱은 개인 레포에 있으므로 폰이 기억하지 않아도 된다(배포 계약의 의도)

## 그 뒤

rc7 블로그 72h soak을 다시 시작했다 (10-15 19:32 → 10-18). #59의 넷이 모두 끝났다 — Core `v0.1.0` 태그를 기다린다.
