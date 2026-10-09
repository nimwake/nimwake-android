#!/data/data/com.termux/files/usr/bin/sh
# 기기(Termux)에서 도는 설치 단계. (A4, PRD §35–§36)
# 개발 머신의 scripts/install.sh가 ssh로 보낸다: ssh <기기> sh -s < install/install-android.sh
#
# **멱등**이다. 이미 된 것은 건드리지 않고 `[=]`, 바꾼 것은 `[+]`로 알린다.
# 설치가 끝난 기기에서 다시 돌리면 `[+]`가 하나도 없어야 한다.
#
# 하지 않는 것:
#   - Android 앱 설치(Termux:Boot · Termux:API) — 사람이 F-Droid에서 한다. 출처만 확인한다
#   - 키 생성 · 업로드 (PRD §36). 키는 사람이 ssh-copy-id로 등록한다
#   - binary · manifest 배치 — scripts/deploy.sh (설치와 업데이트가 같은 경로를 쓴다)
#   - phantom process · 배터리 최적화 — adb가 필요하다. make doctor가 점검한다

# 셸이 블록 전체를 읽은 뒤 실행한다. 안의 명령(pkg, cmd, proot-distro)이 표준 입력을 읽어
# 아직 실행하지 않은 스크립트를 삼키지 못하게 한다 (scripts/doctor.sh 참고).
{
set -eu

changed=0
done_() { echo "[=] $*"; }
did() {
	echo "[+] $*"
	changed=$((changed + 1))
}
warn() { echo "[!] $*"; }

if [ -z "${PREFIX:-}" ] || ! command -v termux-info >/dev/null 2>&1; then
	echo "install-android: not running in Termux" >&2
	exit 1
fi

# --- Android 앱: 같은 출처인가 (설치는 사람이) -----------------------------
pkgs="$(cmd package list packages -i com.termux 2>/dev/null || true)"
src() {
	printf '%s\n' "$pkgs" | sed -n "s/^package:$1[[:space:]][[:space:]]*installer=//p"
}
termux_src="$(src 'com\.termux')"
for app in boot api; do
	app_src="$(src "com\\.termux\\.$app")"
	if ! printf '%s\n' "$pkgs" | grep -q "^package:com\.termux\.${app}[[:space:]]"; then
		warn "Termux:$app is not installed — install it from the same source as Termux ($termux_src)"
	elif [ "$app_src" != "$termux_src" ]; then
		warn "Termux:$app source ($app_src) differs from Termux ($termux_src) — reinstall from one source"
	else
		done_ "Termux:$app ($app_src)"
	fi
done

# --- Termux 패키지 ------------------------------------------------------
# 이미 있으면 pkg를 부르지 않는다 — pkg install은 그 패키지를 업그레이드할 수 있다.
missing=""
for p in openssh proot-distro termux-api; do
	if dpkg -s "$p" >/dev/null 2>&1; then
		done_ "package $p"
	else
		missing="$missing $p"
	fi
done
if [ -n "$missing" ]; then
	# shellcheck disable=SC2086 # 패키지 목록을 인자로 나눈다
	pkg install -y $missing
	did "packages:$missing"
fi

# --- Ubuntu guest (D-A8: 26.04 고정, 컨테이너 이름 ubuntu) -------------------
if proot-distro login ubuntu -- true >/dev/null 2>&1; then
	# shellcheck disable=SC2016 # $VERSION_ID는 guest 안에서 풀린다
	done_ "proot Ubuntu ($(proot-distro login ubuntu -- sh -c '. /etc/os-release; echo "$VERSION_ID"' 2>/dev/null))"
else
	proot-distro install --name ubuntu ubuntu:26.04
	did "proot Ubuntu 26.04"
fi

# --- sshd: 키가 등록돼 있으면 키 로그인만 (PRD §40) ---------------------------
conf="$PREFIX/etc/ssh/sshd_config.d/10-nimwake.conf"
want='# nimwake-android: 키 로그인만 허용한다 (PRD §40). sshd_config가 Include로 먼저 읽는다.
PasswordAuthentication no
KbdInteractiveAuthentication no'
if [ ! -s "$HOME/.ssh/authorized_keys" ]; then
	warn "no key in ~/.ssh/authorized_keys — password login stays on. Register a key with ssh-copy-id, then run install again"
elif [ -f "$conf" ] && [ "$(cat "$conf")" = "$want" ]; then
	done_ "sshd key login only"
else
	mkdir -p "$(dirname "$conf")"
	printf '%s\n' "$want" >"$conf"
	chmod 600 "$conf"
	sshd -t
	# 리스너만 다시 띄운다. 지금 이 ssh 세션(sshd-session)은 끊기지 않는다.
	pkill -x sshd || true
	sshd
	did "sshd key login only ($conf)"
fi

if pgrep -x sshd >/dev/null; then
	done_ "sshd running"
else
	sshd
	did "sshd started"
fi

# --- Termux:Boot 디렉터리 (스크립트는 deploy가 넣는다) ----------------------
if [ -d "$HOME/.termux/boot" ]; then
	done_ "$HOME/.termux/boot"
else
	mkdir -p "$HOME/.termux/boot"
	did "$HOME/.termux/boot"
fi

echo "install-android: $changed change(s)"
} </dev/null
