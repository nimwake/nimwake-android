SCRIPTS := $(shell git ls-files '*.sh' 'host/boot/*' 'host/bin/*' 'tests/unit/fixtures/*')

HOURS ?= 24
INTERVAL ?= 300

.PHONY: lint test doctor-dev install fetch-core deploy run stop doctor test-device test-boot test-recovery test-lan test-wifi test-experiments bench soak-start soak-stop soak-report

# shellcheck는 bash 문법을, check-portability는 BSD/GNU 옵션 차이(sed -i, date -d …)를 본다
lint:
	shellcheck $(SCRIPTS)
	scripts/check-portability.sh

# 기기 없이 도는 테스트 (bats-core). host/lib 판단 로직 + 가짜 daemon으로 감시 루프
test:
	bats tests/unit

# 개발 머신 점검 (도구 · 버전 · WSL 경로 · 실행 비트 · ssh 설정). 기기에는 접속하지 않는다
doctor-dev:
	scripts/doctor-dev.sh

# 기기 설치: 패키지 · proot Ubuntu · 키 로그인 sshd → deploy → supervisor → doctor. 멱등 (A4)
# deploy가 binary를 다시 놓으므로 soak 중에는 돌리지 않는다
install:
	scripts/install.sh

fetch-core:
	scripts/fetch-core.sh

deploy:
	scripts/deploy.sh

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

# 실패 경로 실험 E2–E4 + 고아 정리 (별도 경로 /opt/nimwake-exp · 포트 :8090 — 운영 daemon과 soak은 건드리지 않는다)
test-experiments:
	tests/device/experiments.sh

# Core PRD §50: CI와 같은 workload(nimwake-bench)를 기기에서 돌려 CI baseline과 비교. soak 중에는 거부한다
bench:
	tests/device/bench.sh

# 장시간 soak — sampler는 기기에서 돈다. make soak-start HOURS=72
soak-start:
	tests/device/soak.sh start $(HOURS) $(INTERVAL)

soak-stop:
	tests/device/soak.sh stop

soak-report:
	tests/device/soak.sh report
