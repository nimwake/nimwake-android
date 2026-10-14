#!/usr/bin/env bats
# scripts/app-manifest.sh — 소비처 앱의 배포 계약 검사와 manifest 만들기. 기기 없이 돈다.
# 계약: .docs/phases/phase-2/03-deploy-and-ingress-contract.md "1. 앱 배포 계약"

setup() {
	root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	m="$root/scripts/app-manifest.sh"
	app="$BATS_TEST_TMPDIR/blog"
	mkdir -p "$app/bundle"
	echo "console.log(1)" >"$app/bundle/server.js"
	cat >"$app/nimwake.toml" <<'EOF'
name = "blog"

[server]
host = "blog.example.com"
port = 3102

[runtime]
command = ["/opt/node/bin/node", "server.js"]

[runtime.env]
PORT = "3102"
HOSTNAME = "127.0.0.1"

[lifecycle]
idle_timeout_seconds = 120
startup_timeout_seconds = 30
shutdown_timeout_seconds = 10
max_pending_requests = 256
EOF
}

@test "a valid consumer app passes and reports name host port" {
	run "$m" check "$app"
	echo "$output"
	[ "$status" -eq 0 ]
	[ "$output" = "blog blog.example.com 3102 lan" ]
}

@test "working_dir is refused — the deploy fills it with the release directory" {
	# BSD sed는 치환에서 \n을 줄바꿈으로 읽지 않는다 — awk로 넣는다
	awk '{ print } /^command = / { print "working_dir = \"/somewhere\"" }' "$app/nimwake.toml" >"$app/t" && mv "$app/t" "$app/nimwake.toml"
	run "$m" check "$app"
	[ "$status" -eq 1 ]
	[[ "$output" == *"working_dir 은 쓰지 않는다"* ]]
}

@test "a missing bundle is refused — nothing is built on the phone" {
	rm -rf "$app/bundle"
	run "$m" check "$app"
	[ "$status" -eq 1 ]
	[[ "$output" == *"bundle/"* ]]
}

@test "only runtimes this repo provides are accepted" {
	sed -i.bak 's#/opt/node/bin/node#/usr/bin/python3#' "$app/nimwake.toml"
	run "$m" check "$app"
	[ "$status" -eq 1 ]
	[[ "$output" == *"이 레포가 제공하는 런타임만"* ]]
}

@test "ports below 1024 and the gateway port are refused" {
	for p in 80 8080 99999 abc; do
		sed -i.bak "s#^port = .*#port = $p#" "$app/nimwake.toml"
		run "$m" check "$app"
		[ "$status" -eq 1 ] || { echo "accepted port $p"; return 1; }
	done
}

@test "names are path-safe" {
	sed -i.bak 's#^name = .*#name = "../etc"#' "$app/nimwake.toml"
	run "$m" check "$app"
	[ "$status" -eq 1 ]
	[[ "$output" == *"소문자"* ]]
}

@test "render puts working_dir right under [runtime] and changes nothing else" {
	run "$m" render "$app/nimwake.toml" /home/nimwake/apps/blog/releases/20261014T000000Z
	echo "$output"
	[ "$status" -eq 0 ]
	# [runtime] 바로 다음 줄
	[ "$(printf '%s\n' "$output" | grep -A1 '^\[runtime\]$' | tail -n 1)" = 'working_dir = "/home/nimwake/apps/blog/releases/20261014T000000Z"' ]
	# [runtime.env]에는 넣지 않는다 — 한 번만
	[ "$(printf '%s\n' "$output" | grep -c '^working_dir')" -eq 1 ]
	# 나머지는 그대로
	diff <(printf '%s\n' "$output" | grep -v '^working_dir') "$app/nimwake.toml"
	# 렌더 결과는 다시 check를 통과하지 않는다(working_dir이 있으므로) — 폰에 놓을 것이지 소비처가 쓸 것이 아니다
}

@test "the example blog manifest shape is accepted when working_dir is left out" {
	ex="$BATS_TEST_TMPDIR/ex"
	mkdir -p "$ex/bundle"
	grep -v '^working_dir' "$root/guest/apps/blog/nimwake.toml" >"$ex/nimwake.toml"
	run "$m" check "$ex"
	echo "$output"
	[ "$status" -eq 0 ]
	[ "$output" = "blog blog.local 3102 lan" ]
}

# 노출 선언 (Phase 2 04) — nimwake.toml이 아니라 옆 파일. Core는 모르는 키를 거부한다
@test "exposure defaults to lan, accepts public, refuses anything else" {
	echo public >"$app/exposure"
	run "$m" check "$app"
	[ "$status" -eq 0 ]
	[ "$output" = "blog blog.example.com 3102 public" ]

	printf ' lan \n' >"$app/exposure"
	run "$m" check "$app"
	[ "$output" = "blog blog.example.com 3102 lan" ]

	echo internet >"$app/exposure"
	run "$m" check "$app"
	[ "$status" -eq 1 ]
	[[ "$output" == *"exposure 'internet' — public | lan"* ]]
}
