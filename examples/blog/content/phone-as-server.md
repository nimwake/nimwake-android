---
title: 서랍 속 폰을 서버로
date: 2026-10-14
---
쓰지 않는 Galaxy A51을 홈서버로 쓴다. Android 위에 Termux, 그 안에 proot Ubuntu, 그 안에서 Nimwake가 돈다.

## 왜 폰인가

- 이미 있다. 배터리가 UPS다.
- 전기를 거의 안 쓴다 — 72시간 동안 CPU는 거의 유휴였다.
- 다만 메모리가 작다. 앱을 늘 띄워 두면 금방 찬다.

## 그래서 scale-to-zero

이 블로그는 평소에 꺼져 있다. 요청이 오면 Nimwake가 깨우고, 한동안 아무도 안 오면 다시 내린다. 이 글을 읽는 지금 이 페이지를 내준 프로세스는 방금 깨어났을 수도 있다.

```text
요청 → Nimwake gateway → (자고 있으면) node server.js 기동 → 응답
                         (한동안 조용하면) 내린다
```
