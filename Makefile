SCRIPTS := $(shell git ls-files '*.sh')

.PHONY: lint fetch-core deploy run test-device

lint:
	shellcheck $(SCRIPTS)

fetch-core:
	scripts/fetch-core.sh

deploy:
	scripts/deploy.sh

run:
	scripts/run.sh

test-device:
	tests/device/lifecycle.sh
