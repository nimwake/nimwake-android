#!/usr/bin/env bats
# scripts/check-docs.sh — docs/의 영문 · 국문 문서가 같은 뼈대와 같은 명령을 갖는가. make lint가 돌린다.

setup() {
	root="$(cd "$BATS_TEST_DIRNAME/../.." && pwd -P)"
	check="$root/scripts/check-docs.sh"
	export ROOT="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$ROOT/docs" "$ROOT/examples/consumer-template"
	printf 'lint:\n\ttrue\ninstall:\n\ttrue\n' >"$ROOT/Makefile"
	printf 'deploy:\n\ttrue\n' >"$ROOT/examples/consumer-template/Makefile"
	cat >"$ROOT/docs/guide.md" <<'EOF'
# Guide

## Install

```sh
make install          # once
make deploy APP=site
```

## Use

Text.
EOF
	cat >"$ROOT/docs/guide.ko.md" <<'EOF'
# 안내

## 설치

```sh
make install          # once
make deploy APP=site
```

## 쓰기

글.
EOF
}

@test "an English and Korean pair with the same headings and code passes" {
	run "$check"
	echo "$output"
	[ "$status" -eq 0 ]
	[[ "$output" == *"ok (1 documents"* ]]
}

@test "a document without its Korean version fails, and the other way round" {
	rm "$ROOT/docs/guide.ko.md"
	run "$check"
	[ "$status" -eq 1 ]
	[[ "$output" == *"guide.md has no Korean version guide.ko.md"* ]]

	echo "# 고아" >"$ROOT/docs/orphan.ko.md"
	run "$check"
	[[ "$output" == *"orphan.ko.md has no English original"* ]]
}

@test "a section added to one language only fails" {
	printf '\n## Upgrade\n\nMore.\n' >>"$ROOT/docs/guide.md"
	run "$check"
	[ "$status" -eq 1 ]
	[[ "$output" == *"different heading structure (4 vs 3 headings)"* ]]
}

@test "a heading inside a code block is not a heading" {
	printf '\n```sh\n# a comment\n```\n' | tee -a "$ROOT/docs/guide.md" >>"$ROOT/docs/guide.ko.md"
	run "$check"
	[ "$status" -eq 0 ]
}

@test "a command changed in one language only fails and shows the difference" {
	sed 's/APP=site/APP=blog/' "$ROOT/docs/guide.ko.md" >"$ROOT/t" && mv "$ROOT/t" "$ROOT/docs/guide.ko.md"
	run "$check"
	[ "$status" -eq 1 ]
	[[ "$output" == *"different code blocks"* ]]
	[[ "$output" == *"APP=blog"* ]]
}

@test "a make target no Makefile defines fails" {
	for f in guide.md guide.ko.md; do
		sed 's/make deploy APP=site/make publish APP=site/' "$ROOT/docs/$f" >"$ROOT/t" && mv "$ROOT/t" "$ROOT/docs/$f"
	done
	run "$check"
	[ "$status" -eq 1 ]
	[[ "$output" == *"uses 'make publish', which no Makefile defines"* ]]
}

@test "the real docs pass" {
	unset ROOT
	run "$check"
	echo "$output"
	[ "$status" -eq 0 ]
}

@test "the contract must document every host.conf key" {
	mkdir -p "$ROOT/host"
	printf "#NIMWAKE_LISTEN=0.0.0.0:8080\nNIMWAKE_NEW_THING=1\n" >"$ROOT/host/host.conf.example"
	for f in contract.md contract.ko.md; do
		printf "# C\n\n## Keys\n\n| \`NIMWAKE_LISTEN\` | x |\n" >"$ROOT/docs/$f"
	done
	run "$check"
	[ "$status" -eq 1 ]
	[[ "$output" == *"contract.md does not document host.conf key NIMWAKE_NEW_THING"* ]]
	[[ "$output" == *"contract.ko.md does not document host.conf key NIMWAKE_NEW_THING"* ]]
	[[ "$output" != *"key NIMWAKE_LISTEN"* ]]
}
