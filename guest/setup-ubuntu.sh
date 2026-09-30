#!/bin/sh
# Ubuntu proot 안에서 root로 실행한다. deploy.sh가 stage 디렉터리를 bind해서 부른다.
#   binary → /opt/nimwake/bin
#   manifest → /home/nimwake/.nimwake/apps/<app>/nimwake.toml
# 멱등이다. 기존 manifest는 덮는다 (A1 — 검증용 manifest만 다룬다).
set -eu

stage="${1:?stage directory}"

if ! id nimwake >/dev/null 2>&1; then
	useradd --create-home --shell /bin/sh nimwake
fi

install -d -m 755 /opt/nimwake/bin
for binary in "$stage"/dist/aarch64/nimwaked "$stage"/dist/aarch64/*-server; do
	install -m 755 "$binary" /opt/nimwake/bin/
done
install -m 644 "$stage"/dist/aarch64/BUILD_INFO /opt/nimwake/BUILD_INFO

apps=/home/nimwake/.nimwake/apps
for dir in "$stage"/guest/apps/*/; do
	app="$(basename "$dir")"
	install -d -o nimwake -g nimwake "$apps/$app"
	install -m 644 -o nimwake -g nimwake "$dir/nimwake.toml" "$apps/$app/nimwake.toml"
done

echo "setup-ubuntu: installed"
sed 's/^/  /' /opt/nimwake/BUILD_INFO
