SCRIPTS := $(shell git ls-files '*.sh' 'host/boot/*')

.PHONY: lint fetch-core deploy run stop test-device test-boot

lint:
	shellcheck $(SCRIPTS)

fetch-core:
	scripts/fetch-core.sh

deploy:
	scripts/deploy.sh

run:
	scripts/run.sh

stop:
	scripts/stop.sh

test-device:
	tests/device/lifecycle.sh

test-boot:
	tests/device/boot.sh
