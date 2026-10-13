---
title: 이 페이지를 깨우는 것
date: 2026-10-14
---
`/api/whoami`를 열면 이 앱이 지금 어떤 상태인지 보인다.

- pid — 새로 깨어났으면 바뀐다
- uptime_s — 깨어난 지 몇 초인가
- rss_mb — 깨어 있는 동안 쓰는 메모리
- x_forwarded_for — 누가 요청했는가. 맨 오른쪽 값만 Nimwake gateway가 직접 본 것이다

## 메모리

Next.js 앱 하나는 깨어 있으면 100MB 안팎을 쓴다. 폰의 가용 메모리는 3GB 정도다. 여러 앱을 동시에 깨워 두면 Android가 먼저 Termux를 죽일 수 있다. 그래서 Nimwake는 가용 메모리가 일정 아래로 떨어지면 가장 오래 쉬고 있는 앱부터 내린다.
