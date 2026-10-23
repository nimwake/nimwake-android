# 계약 — nimwake-android가 약속하는 것

[English](contract.md) · [온보딩](onboarding.ko.md)

소비처 레포와 운영자가 기대도 되는 것을 모두 적는다. **v1.0.0부터 SemVer를 따른다:** 아래 것을 바꾸거나 없애려면 major 버전이 필요하고, minor 버전은 더하기만 한다. 없앨 것은 적어도 한 minor 동안 경고와 함께 남긴다. 여기에 없는 것 — 로그 문장, 사람이 읽는 `status` 줄, `~/.nimwake-host/run/` 아래 파일, 테스트 출력 — 은 어느 릴리스에서든 바뀔 수 있다.

> `make lint`가 `host/host.conf.example`의 모든 키가 이 문서에 있는지, 코드 블록의 `make` 대상이 실제로 있는지 검사한다.

## 버전

| | |
| - | - |
| 소비처 레포가 고정하는 것 | `nimwake-android.lock` → `rev=<릴리스 태그나 commit SHA>`, `main`은 쓰지 않는다 |
| 이 레포가 Core를 고정하는 것 | `core.lock` → Core 릴리스 태그와 그 commit. `make fetch-core`가 commit을 확인한다 |
| 앱의 Node | `guest/node.lock` — 버전과 sha256. 폰에 `/opt/node/bin/node`로 설치된다 |

## 앱 디렉터리

```text
apps/<name>/
  nimwake.toml   Core manifest
  exposure       public | lan  (missing means lan)
  app/           source, built on your machine (package.json + package-lock.json)
  bundle/        what runs on the phone — produced by the build, never built on the phone
```

배포가 폰을 건드리기 전에 검사하는 manifest 규칙:

| 규칙 | |
| ---- | - |
| `name` | 소문자, 숫자, `-` — 폰의 경로 이름이 된다 |
| `[server] host` | 공개 hostname. 앱 하나에 host 하나 |
| `[server] port` | 1024–65535, 8080 제외, 폰에서 겹치지 않게 |
| `[server] allow` | 한 줄로. `public` 앱은 `127.0.0.1`을 넣거나 `allow`를 빼야 한다. `allow`가 없는 `lan` 앱은 경고 |
| `[runtime] command` | `/opt/node/bin/node` 또는 `/opt/nimwake/bin/` 아래 binary |
| `working_dir`, `NIMWAKE_DATA_DIR` | 적지 않는다 — 배포가 둘 다 채운다 |
| bundle | 네이티브 모듈(`*.node`) 없음 |

앱이 받는 것:

| | |
| - | - |
| 작업 디렉터리 | release 디렉터리 — **배포마다 바뀐다** |
| `NIMWAKE_DATA_DIR` | `/home/nimwake/data/<name>`(0700) — 재배포, rollback, `remove-app`을 거쳐 남고 `make backup`이 복사한다 |
| 네트워크 | `127.0.0.1:<port>`에서 듣는다. 요청은 gateway를 거쳐 `X-Forwarded-For`와 함께 온다(맨 오른쪽 값이 gateway가 본 peer) |

## 배포의 의미

| 명령 | 약속 |
| ---- | ---- |
| `deploy-app` | 묶음이 새 release가 된다. Core는 다른 앱을 건드리지 않고 다시 읽는다. 새 release를 한 번 깨워 보고 **뜨지 않으면 되돌린다**(`NO_VERIFY=1`이면 건너뛴다). release는 최근 셋을 남긴다 |
| `rollback-app` | 직전 release로 |
| `remove-app` | 앱이 멈추고 라우팅에서 빠진다. release와 데이터는 폰에 남는다 |
| `exposure` | `public` 앱만 ingress에 넘긴다 |

## 명령

이 레포:

```sh
make install                      # set up a phone (idempotent)
make deploy                       # Core and Host Layer onto the phone
make restart                      # restart the supervisor (reads host.conf)
make deploy-app APP=<dir>         # deploy one app directory
make rollback-app NAME=<name>
make remove-app NAME=<name>
make apps                         # apps, host, port, exposure, release, state
make logs APP=<name>              # LINES=, FOLLOW=1
make ingress-enable INGRESS=cloudflare
make ingress-token INGRESS=cloudflare
make ingress-disable
make backup                       # host.conf, soak records, app data → ~/.nimwake-backup/<device>
make restore-data
make doctor
make device-status
make verify                       # every check that needs no hands
```

소비처 템플릿:

```sh
make setup
make deploy APP=<name>
make rollback APP=<name>
make ingress
make token
make restart
make status
make logs APP=<name>
make verify
make upgrade REV=<tag>
```

폰에서: `nimwake-host start | stop | status | logs [N]`, 그리고 `nimwake` — control socket이 설정된 Core CLI(`nimwake status`, `nimwake status --json`. JSON은 Core의 계약이고 자기 `contract` 번호를 담는다).

## `host.conf`

폰의 `~/.nimwake-host/host.conf`, `KEY=value`. 없는 키는 기본값을 쓴다. `make deploy`는 이 파일을 덮지 않고, `make backup`이 사본을 남긴다.

| 키 | 의미 |
| -- | ---- |
| `NIMWAKE_LISTEN` | gateway 주소. 비우면 Core 기본값 `127.0.0.1:8080`, `0.0.0.0:8080`이면 LAN에 연다 |
| `NIMWAKE_CONTROL_SOCKET` | `1`(기본)이면 Core를 control socket과 함께 띄운다 |
| `NIMWAKE_ISOLATED` | `1`(기본)이면 Core와 앱을 격리된 proot에서 띄운다 |
| `NIMWAKE_MIN_FREE_MEMORY_MB` | Core의 메모리 입장 제어와 유휴 eviction 임계값. 비우면 꺼짐 |
| `NIMWAKE_HEALTH_INTERVAL` · `NIMWAKE_HEALTH_FAILURES` | supervisor가 Core를 확인하는 간격과, 몇 번 실패하면 재시작하는지 |
| `NIMWAKE_MAX_RESTARTS` · `NIMWAKE_RESTART_WINDOW` | crash loop 한도 — 이 시간 안에 이만큼 재시작하면 `UNHEALTHY` |
| `NIMWAKE_HOUSEKEEPING_INTERVAL` | 저장공간 · 배터리 · 로그 순환 점검 간격(초) |
| `NIMWAKE_MIN_FREE_MB` · `NIMWAKE_STORAGE_CLEANUP` | 저장공간 부족 알림 기준, 그리고 순환된 로그를 먼저 지울지 |
| `NIMWAKE_NOTIFY` | 알림 명령. 메시지는 `$1`, 종류(`storage`, `battery`)는 `$2` |
| `NIMWAKE_BATTERY_WATCH` · `NIMWAKE_BATTERY_LOW` | 배터리 감시 켜기, 낮은 잔량 기준(%) |
| `NIMWAKE_LOG_MAX_KB` · `NIMWAKE_LOG_KEEP` | 로그 순환 크기와 남길 옛 로그 수 |
| `NIMWAKE_NET_INTERVAL` · `NIMWAKE_NET_GATEWAY` · `NIMWAKE_NET_INTERNET_URL` | 네트워크 감시 간격, 확인할 공유기, 선택적 인터넷 확인 |
| `NIMWAKE_NET_ON_RECOVER` · `NIMWAKE_NET_HOOK_TIMEOUT` | 네트워크가 돌아올 때 돌릴 명령과 그 시간 제한 |
| `NIMWAKE_INGRESS` | ingress provider(`cloudflare`). 비우면 없음 |
| `NIMWAKE_INGRESS_CF_MODE` · `NIMWAKE_INGRESS_CF_QUICK_HOST` · `NIMWAKE_INGRESS_CF_METRICS` | cloudflare provider: `token` 또는 `quick`, quick 모드가 내줄 host, metrics 주소 |

## Ingress provider

`host/ingress/<provider>/`에 실행 파일 넷:

| 파일 | 계약 |
| ---- | ---- |
| `check` | 필요한 것이 다 있으면 0. 아니면 무엇이 없는지 한 줄 |
| `install` | 필요한 것을 설치한다. 멱등 |
| `run` | 포그라운드로 돈다. 끝나면 supervisor가 다시 띄운다. 종료 코드 `78`은 설정 오류라 다시 띄우지 않는다 |
| `health` | 연결돼 있으면 0. 한 줄(예: 공개 URL)을 출력할 수 있다 |

받는 환경 변수: `NIMWAKE_GATEWAY`(보낼 곳), `NIMWAKE_INGRESS_HOSTS`(`public` 앱의 hostname, 공백 구분), `NIMWAKE_SECRETS`(토큰을 두는 0700 디렉터리), `NIMWAKE_LOGS`, 그리고 `host.conf`의 모든 `NIMWAKE_INGRESS_*` 키. provider는 그 이름들을 gateway로 보낸다. cloudflare의 `token` 모드는 `Host` 헤더를 그대로 두고, `quick` 모드는 앱 하나의 host(`NIMWAKE_INGRESS_CF_QUICK_HOST`, 없으면 첫 public 앱)로 바꾼다.
