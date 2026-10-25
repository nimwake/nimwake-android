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
#   make verify                    사람 손 없이 도는 기기 검증 전부 (APP_HOST=블로그 host)
#   make secret APP=blog KEY=X < f 앱의 비밀을 폰에 (표준 입력으로만) · make secrets APP=blog — 이름만
#   make new-app NAME=about KIND=static|next [HOST=…] [EXPOSURE=public]  예시에서 새 앱 — 겹치지 않는 port
#   make upgrade REV=v0.1.2        nimwake-android를 올린다 — lock · 이 머신 · 폰(Core · Host Layer) · 앱 전부 재배포
#
# .env (커밋하지 않는다): NIMWAKE_DEVICE, CLOUDFLARE_TOKEN_FILE — .env.example 참고

-include .env
export NIMWAKE_DEVICE

NA := .nimwake-android
APP ?= blog
MODE ?=

.PHONY: setup build deploy rollback ingress token restart status logs verify upgrade secret secrets new-app

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

verify:
	$(MAKE) -C $(NA) verify

new-app:
	$(NA)/scripts/new-app.sh apps "$(NAME)" "$(KIND)" "$(HOST)" "$(EXPOSURE)"

secret:
	$(MAKE) -C $(NA) secret APP=$(APP) KEY=$(KEY)

secrets:
	$(MAKE) -C $(NA) secrets APP=$(APP)

# 올리기는 한 번에 — 문서의 네 단계를 잊지 않게. rev는 태그나 commit SHA만 (main은 움직인다).
# 앱은 새 빌드 도구로 다시 묶어 올린다 — 뜨지 않는 앱은 배포가 이전 release로 되돌린다(deploy-app의 확인)
upgrade:
	@case "$(REV)" in \
	'') echo "upgrade: REV is empty — make upgrade REV=<tag> (see the nimwake-android releases and CHANGELOG)"; exit 1 ;; \
	main | master | HEAD) echo "upgrade: REV=$(REV) moves under you — use a release tag or a commit SHA"; exit 1 ;; \
	esac
	sed -i.bak 's/^rev=.*/rev=$(REV)/' nimwake-android.lock && rm -f nimwake-android.lock.bak
	$(MAKE) setup
	$(MAKE) -C $(NA) fetch-core deploy
	$(MAKE) restart
	@for d in apps/*/; do \
		[ -f "$$d/nimwake.toml" ] || continue; \
		$(MAKE) deploy APP="$$(basename "$$d")" || failed="$$failed $$(basename "$$d")"; \
	done; \
	if [ -n "$$failed" ]; then echo "upgrade: these apps did not redeploy:$$failed — they keep their previous release"; exit 1; fi
	@echo "upgrade: nimwake-android $(REV) — commit nimwake-android.lock, then make verify"
