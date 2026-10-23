#!/bin/sh
# 앱의 비밀(API 키 · 웹훅 secret · DB 비밀번호)을 폰에 둔다 — 레포에도 manifest에도 넣지 않는다.
#
#   secrets.sh set APP KEY < FILE   표준 입력의 값을 폰의 /home/nimwake/secrets/APP/KEY(0600)에. 명령줄 · 터미널 입력은 거부
#   secrets.sh list APP             이름과 바뀐 시각만 — 값은 보이지 않는다
#   secrets.sh rm APP KEY
#
# 앱은 NIMWAKE_SECRETS_DIR(배포가 채운다)에서 KEY 파일을 읽는다. 앱은 시작할 때 읽는다 — 쉬고 있으면 다음 요청부터,
# 깨어 있으면 유휴로 내려간 뒤나 make deploy 뒤부터. 비밀은 make backup에 들어가지 않는다 — 원본(비밀번호 관리자 등)에서 다시 넣는다
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"

usage() {
	echo "usage: secrets.sh set APP KEY < FILE | list APP | rm APP KEY" >&2
	exit 2
}

check_app() {
	case "$1" in
	'' | *[!a-z0-9-]* | -*)
		echo "secrets: app '$1' — lowercase letters, digits and '-'" >&2
		exit 2
		;;
	esac
}
check_key() {
	case "$1" in
	'' | *[!A-Za-z0-9_.-]* | .*)
		echo "secrets: key '$1' — letters, digits, '_', '.', '-' (not starting with '.')" >&2
		exit 2
		;;
	esac
}

cmd="${1:-}"
case "$cmd" in
set)
	[ $# -eq 3 ] || usage
	check_app "$2"
	check_key "$3"
	# 값이 셸 기록 · 프로세스 목록 · 화면에 남지 않게 — 파일이나 파이프로만
	if [ -t 0 ]; then
		echo "secrets: give the value on standard input, not the terminal — make secret APP=$2 KEY=$3 < path/to/file" >&2
		exit 2
	fi
	# ssh가 원격으로 보내는 표준 입력은 하나다 — 값만 흐르게 하고 명령은 문자열로 넘긴다.
	# 앱 이름과 키는 위에서 안전한 문자만 허용했다. 빈 값은 거부, 임시 파일에서 옮겨 반쯤 쓴 값이 남지 않게
	# shellcheck disable=SC2016 # \$는 기기에서 푼다
	ssh "$device" "set -eu
d=\"\$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/home/nimwake/secrets/$2\"
mkdir -p \"\$d\"
chmod 700 \"\$(dirname \"\$d\")\" \"\$d\"
umask 077
cat >\"\$d/.$3.new\"
if [ ! -s \"\$d/.$3.new\" ]; then
	rm -f \"\$d/.$3.new\"
	echo 'secrets: the value is empty — nothing stored' >&2
	exit 1
fi
mv \"\$d/.$3.new\" \"\$d/$3\"
echo \"secrets: $2/$3 stored (\$(wc -c <\"\$d/$3\" | tr -d ' ') bytes, 0600) — the app reads it when it starts\""
	;;
list)
	[ $# -eq 2 ] || usage
	check_app "$2"
	ssh "$device" sh -s -- "$2" <<'EOF'
d="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/home/nimwake/secrets/$1"
[ -d "$d" ] || { echo "secrets: $1 has none"; exit 0; }
n=0
for f in "$d"/*; do
	[ -f "$f" ] || continue
	printf '%-28s %s\n' "$(basename "$f")" "$(date -r "$f" '+%Y-%m-%d %H:%M')"
	n=$((n + 1))
done
[ "$n" -gt 0 ] || echo "secrets: $1 has none"
EOF
	;;
rm)
	[ $# -eq 3 ] || usage
	check_app "$2"
	check_key "$3"
	ssh "$device" sh -s -- "$2" "$3" <<'EOF'
f="$PREFIX/var/lib/proot-distro/containers/ubuntu/rootfs/home/nimwake/secrets/$1/$2"
[ -f "$f" ] || { echo "secrets: $1/$2 does not exist" >&2; exit 1; }
rm -f "$f"
echo "secrets: $1/$2 removed"
EOF
	;;
*) usage ;;
esac
