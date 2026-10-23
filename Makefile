SCRIPTS := $(shell git ls-files '*.sh' 'host/boot/*' 'host/bin/*' 'host/ingress/*' 'tests/unit/fixtures/*')

HOURS ?= 24
INTERVAL ?= 300
ROUNDS ?= 3

.PHONY: lint test doctor-dev release-check install backup restore-data fetch-core app-blog deploy device-status deploy-app rollback-app remove-app apps ingress-enable ingress-token ingress-disable restart run stop doctor test-device test-boot test-recovery test-lan test-wifi test-app test-experiments bench soak-start soak-stop soak-report

# shellcheck는 bash 문법을, check-portability는 BSD/GNU 옵션 차이(sed -i, date -d …)를,
# check-docs는 docs/의 영문 · 국문 문서가 같은 뼈대 · 같은 명령인지를 본다
lint:
	shellcheck $(SCRIPTS)
	scripts/check-portability.sh
	scripts/check-docs.sh

# 기기 없이 도는 테스트 (bats-core). host/lib 판단 로직 + 가짜 daemon으로 감시 루프
test:
	bats tests/unit

# 개발 머신 점검 (도구 · 버전 · WSL 경로 · 실행 비트 · ssh 설정). 기기에는 접속하지 않는다
doctor-dev:
	scripts/doctor-dev.sh

# 태그 전 검사 — make release-check TAG=v0.1.0. 태그 push 뒤 release.yml이 같은 검사를 한다 (CHANGELOG.md 머리말)
release-check:
	scripts/release-check.sh $(TAG)

# 기기 설치: 패키지 · proot Ubuntu · 키 로그인 sshd → deploy → supervisor → doctor. 멱등 (A4)
# deploy가 binary를 다시 놓으므로 soak 중에는 거부한다 (FORCE=1로 강행)
install:
	scripts/install.sh

fetch-core:
	scripts/fetch-core.sh

# 예시 앱(Next.js 블로그)을 개발 머신에서 빌드한다 → dist/apps/blog. deploy가 폰에 놓는다 (#45)
app-blog:
	scripts/build-app.sh blog

# soak이 진행 중이면 거부한다 — make deploy FORCE=1로 강행
deploy:
	scripts/deploy.sh

# 기기에 지금 무엇이 도는가 — Core binary(설치 · 실행 중) · supervisor · soak. 이 기기는 여러 작업이 같이 쓴다.
# 배포 · bench · 재시작 전에 먼저 본다. 읽기만 한다
device-status:
	scripts/device-status.sh

# 기기에만 있는 host.conf · soak 기록 → ~/.nimwake-backup/<device> (install이 초기화 기기에 되살린다)
backup:
	scripts/backup.sh

# 앱 데이터(/home/nimwake/data)를 백업에서 — 폰의 그 디렉터리가 비어 있을 때만 (FORCE=1)
restore-data:
	scripts/backup.sh restore-data

# 소비처(개인 레포)의 앱 — nimwake.toml(working_dir 없이) + bundle/. 다른 앱은 건드리지 않는다 (SIGHUP 재적재)
# 계약: .docs/phases/phase-2/03-deploy-and-ingress-contract.md
deploy-app:
	scripts/apps.sh deploy $(APP)

rollback-app:
	scripts/apps.sh rollback $(NAME)

remove-app:
	scripts/apps.sh remove $(NAME)

apps:
	scripts/apps.sh list

# ingress provider (host/ingress/<provider>) — 켠 것은 다음 nimwake-host stop · start부터
#   make ingress-enable INGRESS=cloudflare [MODE=quick]   ·   make ingress-token < 토큰파일   ·   make ingress-disable
ingress-enable:
	scripts/ingress.sh enable $(INGRESS) $(MODE)

ingress-token:
	scripts/ingress.sh token $(INGRESS)

ingress-disable:
	scripts/ingress.sh disable

# 기기의 supervisor를 다시 띄운다 — host.conf 변경이 반영된다. daemon · 앱도 다시 뜬다. soak 중이면 거부 (FORCE=1)
restart:
	scripts/restart.sh

run:
	scripts/run.sh

stop:
	scripts/stop.sh

doctor:
	scripts/doctor.sh

test-device:
	tests/device/lifecycle.sh

test-boot:
	tests/device/boot.sh

test-recovery:
	tests/device/recovery.sh

# LAN에서 본 lifecycle · 동시 cold start. 기기 host.conf에 NIMWAKE_LISTEN=0.0.0.0:8080이 필요하다
test-lan:
	tests/device/network.sh lan

# Wi-Fi를 껐다 켜는 동안 지켜본다 (사람이 기기에서 Wi-Fi를 조작한다)
test-wifi:
	tests/device/network.sh wifi

# 실제 앱 하나를 잰다 — cold(Core 분해) · warm · RSS · 유휴 정지 · SIGUSR1. make test-app HOST=blog.local ROUNDS=3
test-app:
	tests/device/app.sh $(HOST) $(ROUNDS)

# 실패 경로 실험 E2–E4 + 고아 정리 (별도 경로 /opt/nimwake-exp · 포트 :8090 — 운영 daemon과 soak은 건드리지 않는다)
test-experiments:
	tests/device/experiments.sh

# Core PRD §50: CI와 같은 workload(nimwake-bench)를 기기에서 돌려 CI baseline과 비교. soak 중에는 거부한다
bench:
	tests/device/bench.sh

# 장시간 soak — sampler는 기기에서 돈다. make soak-start HOURS=72 [SOAK_HOST=blog.local SOAK_PATH=/api/whoami]
soak-start:
	tests/device/soak.sh start $(HOURS) $(INTERVAL) $(SOAK_HOST) $(SOAK_PATH)

soak-stop:
	tests/device/soak.sh stop

# make soak-report ARGS="--md --hours 24" — 리포트용 표, 72h 중 처음 24h만
soak-report:
	tests/device/soak.sh report $(ARGS)
