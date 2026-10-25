#!/usr/bin/env bats
# examples/consumer-template/Makefile — 개인 레포가 쓰는 명령의 가드. 기기 없이 돈다.

setup() {
	root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	repo="$BATS_TEST_TMPDIR/my-sites"
	cp -R "$root/examples/consumer-template" "$repo"
}

@test "upgrade needs a REV" {
	run make -s -C "$repo" upgrade
	[ "$status" -ne 0 ]
	[[ "$output" == *"upgrade: REV is empty"* ]]
}

@test "upgrade refuses a moving REV — main, master, HEAD" {
	for rev in main master HEAD; do
		run make -s -C "$repo" upgrade REV="$rev"
		[ "$status" -ne 0 ]
		[[ "$output" == *"REV=$rev moves under you"* ]]
	done
	# lock은 그대로
	grep -q '^rev=v' "$repo/nimwake-android.lock"
}

@test "upgrade writes the lock first, then setup, phone, restart and every app" {
	# -n이어도 하위 make($(MAKE) -C .nimwake-android …)는 들어간다 — 아무것도 하지 않는 자리를 둔다
	mkdir -p "$repo/.nimwake-android"
	printf 'fetch-core deploy restart deploy-app:\n\t@:\n' >"$repo/.nimwake-android/Makefile"
	run make -n -C "$repo" upgrade REV=v9.9.9
	echo "$output"
	[ "$status" -eq 0 ]
	[[ "$output" == *"s/^rev=.*/rev=v9.9.9/"* ]]
	[[ "$output" == *"setup"* ]]
	[[ "$output" == *"fetch-core deploy"* ]]
	[[ "$output" == *"restart"* ]]
	[[ "$output" == *'for d in apps/*/'* ]]
}

@test "secrets.sh refuses bad app names and keys before touching the phone" {
	secrets="$root/scripts/secrets.sh"
	NIMWAKE_DEVICE=nowhere.invalid run "$secrets" set "Bad App" KEY </dev/null
	[ "$status" -eq 2 ]
	[[ "$output" == *"app 'Bad App'"* ]]
	NIMWAKE_DEVICE=nowhere.invalid run "$secrets" set api "../etc/passwd" </dev/null
	[ "$status" -eq 2 ]
	[[ "$output" == *"key '../etc/passwd'"* ]]
	NIMWAKE_DEVICE=nowhere.invalid run "$secrets" rm api ".hidden"
	[ "$status" -eq 2 ]
	NIMWAKE_DEVICE=nowhere.invalid run "$secrets" set api
	[ "$status" -eq 2 ]
	[[ "$output" == *"usage:"* ]]
}

@test "new-app copies the example, picks a free port, and the result passes the deploy contract" {
	newapp="$root/scripts/new-app.sh"
	m="$root/scripts/app-manifest.sh"
	run "$newapp" "$repo/apps" about static
	echo "$output"
	[ "$status" -eq 0 ]
	# 템플릿의 blog(3102) · site(3110)와 겹치지 않는다 — 3200부터
	grep -qx 'port = 3200' "$repo/apps/about/nimwake.toml"
	grep -qx 'PORT = "3200"' "$repo/apps/about/nimwake.toml"
	grep -qx 'allow = \["192.168.0.0/16"\]' "$repo/apps/about/nimwake.toml"
	[ "$(cat "$repo/apps/about/exposure")" = lan ]
	[ ! -e "$repo/apps/about/bundle" ] && [ ! -e "$repo/apps/about/app/node_modules" ]
	grep -q '"name": "about"' "$repo/apps/about/app/package.json"
	[ "$(grep -c '"name": "about"' "$repo/apps/about/app/package-lock.json")" -eq 2 ]

	run "$newapp" "$repo/apps" www static www.example.com public
	grep -qx 'port = 3201' "$repo/apps/www/nimwake.toml"
	! grep -q '^allow' "$repo/apps/www/nimwake.toml"
	grep -qx 'host = "www.example.com"' "$repo/apps/www/nimwake.toml"

	mkdir -p "$repo/apps/about/bundle" "$repo/apps/www/bundle"
	run "$m" check "$repo/apps/about"
	[ "$status" -eq 0 ]
	[ "${lines[${#lines[@]}-1]}" = "about about.example.com 3200 lan" ]
	run "$m" check "$repo/apps/www"
	[ "$output" = "www www.example.com 3201 public" ]
}

@test "new-app refuses an existing folder, a bad name and an unknown kind" {
	newapp="$root/scripts/new-app.sh"
	run "$newapp" "$repo/apps" blog static
	[ "$status" -eq 1 ]
	[[ "$output" == *"already exists"* ]]
	run "$newapp" "$repo/apps" "My App" static
	[[ "$output" == *"name 'My App'"* ]]
	run "$newapp" "$repo/apps" x rails
	[[ "$output" == *"KIND=rails"* ]]
}
