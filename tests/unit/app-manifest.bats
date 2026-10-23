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
	# lan인데 allow가 없으면 경고가 앞에 붙는다 — 결과는 마지막 줄
	[ "${lines[${#lines[@]}-1]}" = "blog blog.example.com 3102 lan" ]
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
	[ "${lines[${#lines[@]}-1]}" = "blog blog.local 3102 lan" ]
}

# 노출 선언 (Phase 2 04) — nimwake.toml이 아니라 옆 파일. Core는 모르는 키를 거부한다
@test "exposure defaults to lan, accepts public, refuses anything else" {
	echo public >"$app/exposure"
	run "$m" check "$app"
	[ "$status" -eq 0 ]
	[ "$output" = "blog blog.example.com 3102 public" ]

	printf ' lan \n' >"$app/exposure"
	run "$m" check "$app"
	[ "${lines[${#lines[@]}-1]}" = "blog blog.example.com 3102 lan" ]

	echo internet >"$app/exposure"
	run "$m" check "$app"
	[ "$status" -eq 1 ]
	[[ "$output" == *"exposure 'internet' — public | lan"* ]]
}

# [server] allow (Core §82, rc7) — 터널 요청의 peer는 127.0.0.1이다 (Phase 2 04)
with_allow() {
	awk -v a="$1" '{ print } /^port = / { print "allow = " a }' "$app/nimwake.toml" >"$app/t" && mv "$app/t" "$app/nimwake.toml"
}

@test "a lan app without allow passes with a warning to add the LAN range" {
	run "$m" check "$app"
	[ "$status" -eq 0 ]
	[[ "$output" == *"warning: blog is lan but has no [server] allow"* ]]
}

@test "a lan app limited to the LAN passes quietly" {
	with_allow '["192.168.0.0/16", "10.0.0.0/8"]'
	run "$m" check "$app"
	[ "$status" -eq 0 ]
	[ "$output" = "blog blog.example.com 3102 lan" ]
}

@test "a public app whose allow leaves out 127.0.0.1 is refused — every tunnel request would get 403" {
	echo public >"$app/exposure"
	with_allow '["192.168.0.0/16"]'
	run "$m" check "$app"
	[ "$status" -eq 1 ]
	[[ "$output" == *"does not include 127.0.0.1"* ]]
}

@test "a public app with 127.0.0.1 in allow, or without allow, passes" {
	echo public >"$app/exposure"
	run "$m" check "$app"
	[ "$status" -eq 0 ]
	[ "$output" = "blog blog.example.com 3102 public" ]
	with_allow '["127.0.0.1/32", "192.168.0.0/16"]'
	run "$m" check "$app"
	[ "$status" -eq 0 ]
	[ "$output" = "blog blog.example.com 3102 public" ]
}

@test "a lan app whose allow lets 127.0.0.1 in is warned — the tunnel would get through" {
	with_allow '["0.0.0.0/0"]'
	run "$m" check "$app"
	[ "$status" -eq 0 ]
	[[ "$output" == *"warning: blog is lan but allow includes 127.0.0.1"* ]]
}

@test "allow spread over several lines is refused — the check reads one line" {
	with_allow '['
	run "$m" check "$app"
	[ "$status" -eq 1 ]
	[[ "$output" == *"allow 는 한 줄로"* ]]
}

# 앱의 영구 디렉터리 — working_dir은 release마다 바뀐다. 남겨야 하는 것은 NIMWAKE_DATA_DIR에
@test "render tells the app its data directory inside an existing [runtime.env]" {
	run "$m" render "$app/nimwake.toml" /home/nimwake/apps/blog/releases/20261014T000000Z /home/nimwake/data/blog
	echo "$output"
	[ "$status" -eq 0 ]
	[ "$(printf '%s\n' "$output" | grep -A1 '^\[runtime\.env\]$' | tail -n 1)" = 'NIMWAKE_DATA_DIR = "/home/nimwake/data/blog"' ]
	[ "$(printf '%s\n' "$output" | grep -c '^\[runtime\.env\]$')" -eq 1 ]
	[ "$(printf '%s\n' "$output" | grep -c '^NIMWAKE_DATA_DIR')" -eq 1 ]
}

@test "render adds [runtime.env] at the end when the manifest has none" {
	awk '/^\[runtime\.env\]$/ { skip = 1; next } /^\[/ { skip = 0 } !skip' "$app/nimwake.toml" >"$app/t" && mv "$app/t" "$app/nimwake.toml"
	! grep -q 'runtime.env' "$app/nimwake.toml"
	run "$m" render "$app/nimwake.toml" /w /home/nimwake/data/blog
	echo "$output"
	[ "$(printf '%s\n' "$output" | tail -n 2 | head -n 1)" = "[runtime.env]" ]
	[ "$(printf '%s\n' "$output" | tail -n 1)" = 'NIMWAKE_DATA_DIR = "/home/nimwake/data/blog"' ]
}

@test "a manifest that sets NIMWAKE_DATA_DIR itself is refused" {
	awk '{ print } /^\[runtime\.env\]$/ { print "NIMWAKE_DATA_DIR = \"/tmp/mine\"" }' "$app/nimwake.toml" >"$app/t" && mv "$app/t" "$app/nimwake.toml"
	run "$m" check "$app"
	[ "$status" -eq 1 ]
	[[ "$output" == *"NIMWAKE_DATA_DIR 은 쓰지 않는다"* ]]
}

# 앱의 비밀 — 레포 · manifest 밖, 폰의 /home/nimwake/secrets/<name>. 넣는 것은 make secret
@test "render tells the app its secrets directory next to its data directory" {
	run "$m" render "$app/nimwake.toml" /w /home/nimwake/data/blog /home/nimwake/secrets/blog
	echo "$output"
	[ "$(printf '%s\n' "$output" | grep -A2 '^\[runtime\.env\]$' | tail -n 2 | tr '\n' '|')" = 'NIMWAKE_DATA_DIR = "/home/nimwake/data/blog"|NIMWAKE_SECRETS_DIR = "/home/nimwake/secrets/blog"|' ]
}

@test "a manifest that sets NIMWAKE_SECRETS_DIR itself is refused" {
	awk '{ print } /^\[runtime\.env\]$/ { print "NIMWAKE_SECRETS_DIR = \"/tmp/x\"" }' "$app/nimwake.toml" >"$app/t" && mv "$app/t" "$app/nimwake.toml"
	run "$m" check "$app"
	[ "$status" -eq 1 ]
	[[ "$output" == *"NIMWAKE_SECRETS_DIR 은 쓰지 않는다"* ]]
}
