#!/bin/sh
# dist/ · guest/ · host/ 를 ssh로 기기의 Termux에 올리고,
# binary와 manifest는 proot Ubuntu 안에, Termux:Boot 스크립트는 ~/.termux/boot/ 에 배치한다.
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone, ~/.ssh/config에 정의)
#   FORCE=1         soak이 진행 중이어도 배포한다
set -eu

root="$(cd "$(dirname "$0")/.." && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"
stage='.nimwake-host/stage'

if [ ! -x "$root/dist/aarch64/nimwaked" ]; then
	echo "deploy: dist/aarch64/nimwaked 가 없다. 먼저 make fetch-core" >&2
	exit 1
fi

# soak 중에는 배포하지 않는다 — binary가 바뀌면 그 soak이 무엇을 쟀는지 알 수 없다.
# 이 기기는 여러 작업이 같이 쓴다. 주석으로만 두었을 때 실제로 겹쳤다 (2026-10-12, validation/09)
if [ "${FORCE:-}" != 1 ] && why="$("$root/scripts/device-status.sh" --soak-running)"; then
	echo "deploy: a soak is running on the device ($why) — deploying would change what it measures." >&2
	echo "        make device-status · make soak-stop, or FORCE=1" >&2
	exit 1
fi

# rsync는 쓰지 않는다 (macOS openrsync와 옵션이 다르다).
(cd "$root" && tar -cf - dist/aarch64 guest host) |
	ssh "$device" "rm -rf $stage && mkdir -p $stage && tar -xf - -C $stage"

# Termux $HOME은 proot 안에서 보이지 않으므로 stage를 bind한다.
ssh "$device" "proot-distro login ubuntu --bind \$HOME/$stage:/mnt/nimwake-stage \
	-- sh /mnt/nimwake-stage/guest/setup-ubuntu.sh /mnt/nimwake-stage"

# Host Layer: nimwake-host (supervisor)와 lib. 설정 host.conf는 이미 있으면 덮지 않는다.
# 떠 있는 supervisor는 건드리지 않는다. 새 코드는 다음 nimwake-host start부터 쓰인다.
# `{ … } </dev/null`: 안의 명령이 표준 입력(=이 스크립트)을 삼키지 못하게 한다 (doctor 작업 중 실제로 겪었다)
ssh "$device" sh -s "$stage" <<'EOF'
{
set -eu
stage="$HOME/$1"
host="$HOME/.nimwake-host"
mkdir -p "$host/bin" "$host/lib"
install -m 700 "$stage"/host/bin/* "$host/bin/"
install -m 600 "$stage"/host/lib/*.sh "$host/lib/"
# #!/bin/sh는 Termux에 없다. termux-exec 없이도 돌도록 shebang을 Termux 경로로 바꾼다.
termux-fix-shebang "$host"/bin/*
ln -sf "$host/bin/nimwake-host" "$PREFIX/bin/nimwake-host"
if [ ! -f "$host/host.conf" ]; then
	install -m 600 "$stage/host/host.conf.example" "$host/host.conf"
fi
echo "deploy: nimwake-host installed ($(command -v nimwake-host))"
} </dev/null
EOF

# Termux:Boot는 이 디렉터리의 실행 파일을 이름 순으로 시작한다. 앞 스크립트를 기다리지는 않는다. (validation/02)
# 다음 재부팅부터 10-nimwake가 supervisor를 띄운다.
ssh "$device" "mkdir -p \$HOME/.termux/boot && install -m 700 $stage/host/boot/* \$HOME/.termux/boot/ \
	&& echo 'deploy: boot scripts installed' && ls \$HOME/.termux/boot"

# stage는 설치가 끝나면 쓰지 않는다. 남겨 두면 이전 binary가 쌓이고 공간을 쓴다 (PRD §18)
ssh "$device" "rm -rf \$HOME/$stage" && echo "deploy: stage removed"
