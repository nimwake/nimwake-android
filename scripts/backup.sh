#!/bin/sh
# 기기에만 있는 운영 기록을 개발 머신으로 — Termux 데이터가 지워져도 다시 세울 수 있게. (validation/17)
#
#   backup.sh          host.conf · soak 기록(~/nimwake-soak-archive, 진행 중 soak.csv)을 가져온다
#   backup.sh restore  기기에 host.conf가 없을 때만 백업으로 되살린다 (make install이 deploy 전에 부른다)
#
# 가져오지 않는 것: secrets/(ingress 토큰 — 폰 밖에 두지 않는다, make ingress-token으로 다시 넣는다) ·
# 앱(개인 레포에 있다 — make deploy APP=…) · proot Ubuntu(make install이 다시 만든다)
#   NIMWAKE_DEVICE      ssh 대상 (기본 nimwake-phone)
#   NIMWAKE_BACKUP_DIR  백업 위치 (기본 ~/.nimwake-backup/<device>) — 레포 밖이다
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"
dir="${NIMWAKE_BACKUP_DIR:-$HOME/.nimwake-backup/$device}"

cmd_backup() {
	mkdir -p "$dir"
	chmod 700 "$dir"
	# 있는 것만 묶는다 — 갓 설치한 기기에는 soak 기록이 없다
	ssh "$device" 'cd "$HOME" && cp .nimwake-host/logs/soak.csv nimwake-soak-archive/soak-latest.csv 2>/dev/null || true
		set --
		for f in .nimwake-host/host.conf nimwake-soak-archive; do [ -e "$f" ] && set -- "$@" "$f"; done
		[ "$#" -gt 0 ] && tar -cf - "$@"' </dev/null | (cd "$dir" && tar -xf -)
	[ -f "$dir/.nimwake-host/host.conf" ] && chmod 600 "$dir/.nimwake-host/host.conf"
	date '+%Y-%m-%d %H:%M:%S' >"$dir/backed-up-at"
	echo "backup: $device → $dir"
	if [ -f "$dir/.nimwake-host/host.conf" ]; then
		echo "  host.conf: $(grep -c '^NIMWAKE_' "$dir/.nimwake-host/host.conf") settings"
	fi
	echo "  soak records: $(find "$dir/nimwake-soak-archive" -name '*.csv' 2>/dev/null | wc -l | tr -d ' ')"
}

cmd_restore() {
	conf="$dir/.nimwake-host/host.conf"
	[ -f "$conf" ] || return 0
	# 기기에 이미 있으면 그것이 최신이다 — 덮지 않는다
	if ssh "$device" '[ -f "$HOME/.nimwake-host/host.conf" ]' </dev/null; then
		return 0
	fi
	ssh "$device" 'mkdir -p "$HOME/.nimwake-host" && umask 077 && cat >"$HOME/.nimwake-host/host.conf"' <"$conf"
	echo "backup: host.conf restored from $conf (backed up $(cat "$dir/backed-up-at" 2>/dev/null || echo '?')):"
	grep '^NIMWAKE_' "$conf" | sed 's/^/  /'
}

case "${1:-backup}" in
backup) cmd_backup ;;
restore) cmd_restore ;;
*)
	echo "usage: backup.sh [backup | restore]" >&2
	exit 2
	;;
esac
