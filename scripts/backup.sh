#!/bin/sh
# 기기에만 있는 운영 기록을 개발 머신으로 — Termux 데이터가 지워져도 다시 세울 수 있게. (validation/17)
#
#   backup.sh               host.conf · soak 기록(~/nimwake-soak-archive, 진행 중 soak.csv) · 앱 데이터를 가져온다
#   backup.sh restore       기기에 host.conf가 없을 때만 백업으로 되살린다 (make install이 deploy 전에 부른다)
#   backup.sh restore-data  앱 데이터(/home/nimwake/data)를 되살린다 — 기기의 그 디렉터리가 비어 있을 때만 (FORCE=1)
#
# 가져오지 않는 것: secrets/(ingress 토큰 — 폰 밖에 두지 않는다, make ingress-token으로 다시 넣는다) ·
# 앱 코드(개인 레포에 있다 — make deploy APP=…) · proot Ubuntu(make install이 다시 만든다)
# 앱 데이터는 앱이 돌고 있으면 쓰는 중일 수 있다 — SQLite라면 앱이 잠든 때(make apps: SLEEPING) 백업한다
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
	# 앱 데이터 (/home/nimwake/data — 배포가 앱마다 만든다). 새로 받아 통째로 바꾼다 — 지워진 파일이 남지 않게
	rm -rf "$dir/app-data.new"
	mkdir -p "$dir/app-data.new"
	ssh "$device" 'd="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/home/nimwake/data"; [ -d "$d" ] && cd "$d" && tar -cf - .' </dev/null |
		(cd "$dir/app-data.new" && tar -xf - 2>/dev/null) || true
	rm -rf "$dir/app-data"
	mv "$dir/app-data.new" "$dir/app-data"
	echo "  app data: $(find "$dir/app-data" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') app(s), $(du -sk "$dir/app-data" | cut -f1) KB"
}

cmd_restore_data() {
	src="$dir/app-data"
	[ -d "$src" ] || {
		echo "backup: no app data in $dir — make backup first" >&2
		exit 1
	}
	# 기기의 데이터가 백업보다 새로울 수 있다 — 비어 있을 때만, 아니면 FORCE=1
	if [ "${FORCE:-}" != 1 ] && ssh "$device" 'd="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/home/nimwake/data"; [ -d "$d" ] && [ -n "$(ls -A "$d")" ]' </dev/null; then
		echo "backup: the phone already has app data — restoring would overwrite newer files. FORCE=1" >&2
		exit 1
	fi
	(cd "$src" && tar -cf - .) |
		ssh "$device" 'd="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/home/nimwake/data"; mkdir -p "$d" && chmod 700 "$d" && tar -xf - -C "$d"'
	echo "backup: app data restored from $src (backed up $(cat "$dir/backed-up-at" 2>/dev/null || echo '?'))"
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
restore-data) cmd_restore_data ;;
*)
	echo "usage: backup.sh [backup | restore | restore-data]" >&2
	exit 2
	;;
esac
