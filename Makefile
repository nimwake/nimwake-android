SCRIPTS := $(shell git ls-files '*.sh' 'host/boot/*' 'host/bin/*' 'tests/unit/fixtures/*')

.PHONY: lint test fetch-core deploy run stop doctor test-device test-boot test-recovery

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
