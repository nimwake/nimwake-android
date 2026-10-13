#!/bin/sh
# Ubuntu proot 안에서 root로 실행한다. deploy.sh가 stage 디렉터리를 bind해서 부른다.
#   binary → /opt/nimwake/bin
#   manifest → /home/nimwake/.nimwake/apps/<app>/nimwake.toml
#   앱 묶음 → /home/nimwake/apps/<app>   (guest/apps/<app>/artifact가 가리키는 dist/ 경로, #45)
#   Node → /opt/node                      (manifest가 /opt/node를 쓸 때만, guest/node.lock의 버전 · sha256)
# 멱등이다. 기존 manifest와 앱 묶음은 덮는다. Node는 버전이 다를 때만 받는다.
set -eu

stage="${1:?stage directory}"

if ! id nimwake >/dev/null 2>&1; then
	useradd --create-home --shell /bin/sh nimwake
fi

install -d -m 755 /opt/nimwake/bin
# release에 담긴 binary를 모두 놓는다 (nimwaked · nimwake-bench · *-server). 이름을 나열하면
# Core가 binary를 더할 때 조용히 빠진다 — nimwake-bench가 그랬다 (nimwake#25).
for binary in "$stage"/dist/aarch64/*; do
	[ "$(basename "$binary")" = BUILD_INFO ] && continue
	install -m 755 "$binary" /opt/nimwake/bin/
done
install -m 644 "$stage"/dist/aarch64/BUILD_INFO /opt/nimwake/BUILD_INFO

# Node — 예시 앱(examples/)의 런타임. 공식 linux-arm64 tarball을 sha256으로 확인한다.
# 이 Ubuntu 이미지에는 curl · xz가 없다 — proot-distro가 PATH 끝에 붙인 Termux의 것을 쓴다.
if grep -qs '/opt/node/' "$stage"/guest/apps/*/nimwake.toml; then
	lock="$stage/guest/node.lock"
	want="$(sed -n 's/^version=//p' "$lock")"
	if [ "$(/opt/node/bin/node --version 2>/dev/null)" != "v$want" ]; then
		url="$(sed -n 's/^url=//p' "$lock")"
		sha="$(sed -n 's/^sha256=//p' "$lock")"
		tmp="$(mktemp -d)"
		echo "setup-ubuntu: node v$want ← $url"
		curl -fsSL -o "$tmp/node.tar.xz" "$url"
		echo "$sha  $tmp/node.tar.xz" | sha256sum -c - >/dev/null
		rm -rf /opt/node.new
		mkdir -p /opt/node.new
		tar -xJf "$tmp/node.tar.xz" -C /opt/node.new --strip-components=1
		rm -rf /opt/node "$tmp"
		mv /opt/node.new /opt/node
	fi
	echo "setup-ubuntu: node $(/opt/node/bin/node --version)"
fi

apps=/home/nimwake/.nimwake/apps
for dir in "$stage"/guest/apps/*/; do
	app="$(basename "$dir")"
	# 묶음이 필요한 앱: 묶음이 없으면 manifest도 놓지 않는다 — working_dir이 없으면 Core가 기동을 거부한다
	if [ -f "$dir/artifact" ]; then
		src="$stage/$(cat "$dir/artifact")"
		if [ ! -d "$src" ]; then
			echo "setup-ubuntu: skip $app — $(cat "$dir/artifact") is not built (make app-$app)"
			continue
		fi
		rm -rf "/home/nimwake/apps/$app.new"
		install -d -o nimwake -g nimwake /home/nimwake/apps
		cp -R "$src" "/home/nimwake/apps/$app.new"
		chown -R nimwake:nimwake "/home/nimwake/apps/$app.new"
		rm -rf "/home/nimwake/apps/$app"
		mv "/home/nimwake/apps/$app.new" "/home/nimwake/apps/$app"
		echo "setup-ubuntu: $app → /home/nimwake/apps/$app"
	fi
	install -d -o nimwake -g nimwake "$apps/$app"
	install -m 644 -o nimwake -g nimwake "$dir/nimwake.toml" "$apps/$app/nimwake.toml"
done

echo "setup-ubuntu: installed"
sed 's/^/  /' /opt/nimwake/BUILD_INFO
