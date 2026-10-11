# 문서 개요와 제품 정의

> **Nimwake Android PRD** › 제품 정의
>
> 원문 구간: `PRD.md` §1–§2

---

## 1. 문서 개요

- **프로젝트명:** Nimwake Android Host Layer
- **상위 프로젝트:** Nimwake
- **역할:** Android 스마트폰에서 Nimwake Core를 안정적으로 실행하기 위한 플랫폼 전용 호스트 레이어
- **초기 대상 장비:** Android Smartphone / RAM 4GB / Storage 64GB
- **기본 환경:** Android → Termux → Ubuntu proot → Nimwake
- **핵심 목표:** Android 특유의 제약을 Nimwake Core 바깥에서 흡수하여, Nimwake 자체는 일반 Linux 애플리케이션처럼 동작하게 한다.

---

## 2. 제품 정의

Nimwake Android Host Layer는 Android 스마트폰을 Nimwake 실행 노드로 사용하기 위한 플랫폼 적응 계층이다.

Nimwake Core는 Android를 직접 이해하지 않는다.

Android Host Layer가 다음 문제를 대신 처리한다.

- Termux 기동
- Ubuntu proot 진입
- Nimwake daemon 시작 및 복구
- Android 재부팅 대응
- Battery Optimization 대응
- Wake Lock 관리
- Wi-Fi 절전 대응
- 저장공간 관리
- 프로세스 재시작
- 로그 수집
- 네트워크 점검
- 발열 및 배터리 상태 운영 가이드
- Termux / Android 업데이트 대응

구조:

```text
Android OS
   │
   ▼
Termux
   │
   ▼
Android Host Layer
   │
   ├── Boot
   ├── Wake Lock
   ├── Network
   ├── Health
   ├── Recovery
   └── proot launcher
          │
          ▼
      Ubuntu proot
          │
          ▼
        Nimwake
```

---

[PRD 인덱스](../README.md) · [설계 원칙 · 목표 · Non-Goals](02-principles-and-goals.md) →
