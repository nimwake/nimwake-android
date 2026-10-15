#!/bin/sh
# 기기 설치 — 개발 머신에서 한 번에. (A4, PRD §35–§36)
#
#   install/install-android.sh  (기기: 패키지 · proot Ubuntu · 키 로그인 sshd)
#     → make fetch-core (dist/가 없을 때)
#     → scripts/deploy.sh (binary · manifest · nimwake-host · Termux:Boot 스크립트)
#     → nimwake-host start → RUNNING
#     → scripts/doctor.sh
#
# 멱등이다. 설치된 기기에 다시 돌려도 된다 — 다만 deploy가 binary를 다시 놓으므로 soak 중에는 돌리지 않는다.
# 처음 기기는 ssh가 없어 이 스크립트가 시작할 수 없다. 그 단계는 사람이 한다 (아래 first_steps).
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

root="$(cd "$(dirname "$0")/.." && pwd -P)"
device="${NIMWAKE_DEVICE:-nimwake-phone}"

first_steps() {
	ip="$(ssh -G "$device" 2>/dev/null | awk '$1 == "hostname" { print $2 }')"
	key="$(ssh -G "$device" 2>/dev/null | awk '$1 == "identityfile" { print $2; exit }')"
	cat >&2 <<EOF
install: cannot ssh to $device with a key yet. First time on a new device:

  On the phone
    1. F-Droid: Termux, Termux:Boot, Termux:API (same source). Open Termux:Boot once.
    2. Termux:  pkg install -y openssh && passwd && sshd && whoami

  On this machine
    3. ~/.ssh/config:
         Host $device
             HostName <phone IP>   (now: $ip)
             Port 8022
             User <whoami>
             IdentityFile ${key:-~/.ssh/nimwake_phone}
    4. ssh-copy-id -i ${key:-~/.ssh/nimwake_phone}.pub $device     (asks the passwd once)
       no .pub file? derive it from the private key — do not make a new key:
         ssh-keygen -y -f ${key:-~/.ssh/nimwake_phone} > ${key:-~/.ssh/nimwake_phone}.pub
       wiped the phone (Termux data)? its host key changed:
         ssh-keygen -R "[<phone IP>]:8022"
    5. make install

install turns password login off once a key is registered.
EOF
	exit 1
}

ssh -o BatchMode=yes -o ConnectTimeout=10 "$device" true 2>/dev/null || first_steps

echo "== device: packages · proot Ubuntu · sshd"
ssh "$device" sh -s <"$root/install/install-android.sh"

if [ ! -x "$root/dist/aarch64/nimwaked" ]; then
	echo "== fetch-core"
	"$root/scripts/fetch-core.sh"
fi

# 초기화한 기기면 host.conf가 없다 — make backup이 받아 둔 것이 있으면 되살린다 (deploy는 없을 때 기본값을 놓는다)
"$root/scripts/backup.sh" restore

echo "== deploy"
"$root/scripts/deploy.sh"

echo "== supervisor"
ssh "$device" sh -s <<'EOF'
{
nimwake-host start
waited=0
until [ "$(cut -d' ' -f1 "$HOME/.nimwake-host/run/state" 2>/dev/null)" = RUNNING ]; do
	state="$(cut -d' ' -f1 "$HOME/.nimwake-host/run/state" 2>/dev/null)"
	if [ "$state" = UNHEALTHY ] || [ "$waited" -ge 90 ]; then
		nimwake-host status
		exit 1
	fi
	sleep 1
	waited=$((waited + 1))
done
nimwake-host status
} </dev/null
EOF

echo "== doctor"
"$root/scripts/doctor.sh"
