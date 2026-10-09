# NN. 제목 — 무엇을 검증했나

> **마일스톤:** A? · **일시:** YYYY-MM-DD · **결과:** 한 줄 (PASS / FAIL과 핵심 수치)
>
> Core `v0.1.0` Android 8항목 중 해당 항목이 있으면 적는다.

<!--
새 리포트는 이 파일을 복사해 `NN-<마일스톤>-<주제>.md`로 만든다. 번호는 이어 붙인다.
필수 항목은 Phase 1 01-repository-setup §6에 있다. 이전 리포트와 같은 환경이면 "NN과 같다"로 줄이고 바뀐 것만 적는다.
-->

---

## 환경

| 항목 | 값 |
| ---- | -- |
| 기기 | 모델 (`SM-…`) |
| Android | 버전 · 제조사 스킨 |
| Termux | 버전 · 설치 경로 (F-Droid / GitHub / Google Play). Termux:Boot · Termux:API도 같은 출처인지 |
| proot / proot-distro | 버전 |
| Guest | Ubuntu 버전 |
| Core | `nimwake/nimwake@<sha>` (tag) — `make fetch-core`의 `BUILD_INFO` |
| 이 레포 | `main@<sha>` 또는 PR 번호 |
| `host.conf` | 기본값과 다른 것 (예: `NIMWAKE_LISTEN`) |

## 절차

```text
make … → make … (재부팅 · Wi-Fi 등 사람이 한 조작은 그렇게 적는다)
```

## 결과

명령 출력은 그대로 붙인다. 숫자는 출처(어느 로그 · 어느 표본)와 함께.

```text
```

## 관찰

기대와 다른 것, 처음 확인된 가정, 작업 중 고친 결함 (원인 · 조치).

## 남은 것

- [ ]
