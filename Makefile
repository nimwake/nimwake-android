SCRIPTS := $(shell git ls-files '*.sh' 'host/boot/*' 'host/bin/*' 'tests/unit/fixtures/*')

HOURS ?= 24
INTERVAL ?= 300

.PHONY: lint test fetch-core deploy run stop doctor test-device test-boot test-recovery test-lan test-wifi soak-start soak-stop soak-report

lint:
	shellcheck $(SCRIPTS)

# 기기 없이 도는 테스트 (bats-core). host/lib 판단 로직 + 가짜 daemon으로 감시 루프
test:
	bats tests/unit

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

# 장시간 soak — sampler는 기기에서 돈다. make soak-start HOURS=72
soak-start:
	tests/device/soak.sh start $(HOURS) $(INTERVAL)

soak-stop:
	tests/device/soak.sh stop

soak-report:
	tests/device/soak.sh report
