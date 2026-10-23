# 개인 레포 — 내 앱을 nimwake-android로 Android 폰 서버에 배포한다.
# 배포 계약: nimwake-android .docs/phases/phase-2/03-deploy-and-ingress-contract.md
#
#   make setup                     nimwake-android를 nimwake-android.lock의 rev로 .nimwake-android/에
#   make deploy APP=blog           apps/blog/app을 빌드 → apps/blog/bundle → 폰에 배포 (다른 앱은 그대로)
#   make rollback APP=blog         직전 release로
#   make ingress [MODE=quick]      Cloudflare Tunnel provider를 켠다 (다음 restart부터)
#   make token                     CLOUDFLARE_TOKEN_FILE의 토큰을 폰의 secrets/로 (표준 입력으로만)
#   make restart                   폰의 supervisor를 다시 띄운다 — ingress 설정이 반영된다 (앱도 다시 뜬다)
#   make status                    폰의 앱 · Core · supervisor · ingress
#   make logs APP=blog [FOLLOW=1]  그 앱의 출력과 Core의 사건 (LINES=200으로 더)
#
# .env (커밋하지 않는다): NIMWAKE_DEVICE, CLOUDFLARE_TOKEN_FILE — .env.example 참고

-include .env
export NIMWAKE_DEVICE

NA := .nimwake-android
APP ?= blog
MODE ?=

.PHONY: setup build deploy rollback ingress token restart status logs

setup:
	@repo="$$(sed -n 's/^repo=//p' nimwake-android.lock)"; rev="$$(sed -n 's/^rev=//p' nimwake-android.lock)"; \
	if [ ! -d $(NA)/.git ]; then git clone -q "https://github.com/$$repo" $(NA); fi; \
	git -C $(NA) fetch -q origin && git -C $(NA) checkout -q "$$rev" && \
	{ [ "$$rev" != main ] || git -C $(NA) pull -q --ff-only; } && \
	echo "nimwake-android $$(git -C $(NA) rev-parse --short HEAD) ($$rev)"

# 폰에서는 빌드하지 않는다 — 여기서 standalone으로 만들어 bundle/로
build:
	$(NA)/scripts/build-app.sh apps/$(APP)/app apps/$(APP)/bundle

deploy: build
	$(MAKE) -C $(NA) deploy-app APP=$(CURDIR)/apps/$(APP)

rollback:
	$(MAKE) -C $(NA) rollback-app NAME=$(APP)

ingress:
	$(MAKE) -C $(NA) ingress-enable INGRESS=cloudflare MODE=$(MODE)

token:
	@[ -n "$(CLOUDFLARE_TOKEN_FILE)" ] || { echo "CLOUDFLARE_TOKEN_FILE is empty — set it in .env"; exit 1; }
	$(MAKE) -C $(NA) ingress-token INGRESS=cloudflare < "$(CLOUDFLARE_TOKEN_FILE)"

restart:
	$(MAKE) -C $(NA) restart

status:
	$(MAKE) -C $(NA) apps device-status

logs:
	$(MAKE) -C $(NA) logs APP=$(APP)
