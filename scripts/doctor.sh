#!/bin/sh
# 기기의 설치 · 운영 상태를 점검한다. (A3, PRD §34)
#
#   [OK]      기대한 상태
#   [WARN]    동작은 하지만 고쳐야 할 것
#   [FAIL]    동작하지 않는다 — 종료 코드 1
#   [MANUAL]  자동으로 확인할 수 없다 — 사람이 확인한다
#
# Termux 권한으로 볼 수 있는 것은 ssh로, Android 설정(phantom process · 배터리 최적화)은 adb로 본다.
# adb가 없거나 기기가 연결되지 않았으면 그 항목은 [MANUAL]로 남긴다.
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
#   ADB             adb 실행 파일 (기본 adb). WSL에서는 Windows SDK의 adb.exe 경로를 줄 수 있다
#   ANDROID_SERIAL  adb 기기가 여럿일 때 대상 (예: 192.168.0.25:41047)
#
# WSL에서 Windows adb.exe를 쓰면 두 가지가 다르다 (실제로 겪었다):
#   - 환경 변수가 Windows 프로그램에 넘어가지 않는다 → ANDROID_SERIAL을 `-s` 인자로 넘긴다
#   - 출력 줄 끝이 CRLF다 → `device\r`가 `device`와 같지 않다. 모든 출력에서 `\r`을 지운다
# 무선 디버깅은 같은 기기를 IP와 mDNS 이름으로 두 번 보이기도 한다 — 그래서 ANDROID_SERIAL이 필요하다.
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"
adb="${ADB:-adb}"

adb_run() {
	if [ -n "${ANDROID_SERIAL:-}" ]; then
		"$adb" -s "$ANDROID_SERIAL" "$@"
	else
		"$adb" "$@"
	fi 2>/dev/null | tr -d '\r'
}

# 스크립트는 표준 입력으로 간다. 안의 명령(cmd, proot-distro 등)이 표준 입력을 읽으면
# 아직 실행하지 않은 나머지 스크립트를 삼키고 조용히 끝난다 — 실제로 겪었다.
# `{ … } </dev/null`로 감싸면 셸이 블록 전체를 먼저 읽고, 안의 명령은 /dev/null을 읽는다.
device_report="$(ssh "$device" sh -s <<'EOF'
{
ok() { echo "[OK]     $*"; }
warn() { echo "[WARN]   $*"; }
fail() { echo "[FAIL]   $*"; }

# Termux:Boot는 Termux와 같은 출처 · 서명이어야 한다. (validation/01)
release="$(termux-info 2>/dev/null | sed -n 's/^TERMUX_APK_RELEASE=//p')"
case "$release" in
F_DROID | GITHUB) ok "Termux build: $release" ;;
"") warn "Termux build: unknown (termux-info)" ;;
*) warn "Termux build: $release — Termux:Boot must come from the same source" ;;
esac

pkgs="$(cmd package list packages -i com.termux 2>/dev/null || true)"
termux_src="$(printf '%s\n' "$pkgs" | sed -n 's/^package:com\.termux[[:space:]][[:space:]]*installer=//p')"
boot_src="$(printf '%s\n' "$pkgs" | sed -n 's/^package:com\.termux\.boot[[:space:]][[:space:]]*installer=//p')"
if [ -z "$pkgs" ]; then
	warn "installed packages: unknown (cmd package)"
elif ! printf '%s\n' "$pkgs" | grep -q '^package:com\.termux\.boot'; then
	fail "Termux:Boot is not installed"
elif [ "$boot_src" = "$termux_src" ]; then
	ok "Termux:Boot installed, same source as Termux ($boot_src)"
else
	fail "Termux:Boot source ($boot_src) differs from Termux ($termux_src)"
fi

for script in 00-sshd 10-nimwake; do
	if [ -x "$HOME/.termux/boot/$script" ]; then
		ok "boot script ~/.termux/boot/$script"
	else
		fail "boot script ~/.termux/boot/$script is missing or not executable — make deploy"
	fi
done

# 파일을 grep하지 않고 실제 적용값(sshd -T)을 본다. sshd_config는 sshd_config.d/*.conf를 Include하고
# 같은 키는 먼저 나온 값이 이긴다 — 본문만 보면 sshd_config.d의 설정을 놓친다.
sshd_effective="$(sshd -T 2>/dev/null | tr 'A-Z' 'a-z')"
if [ -z "$sshd_effective" ]; then
	warn "sshd config could not be read (sshd -T)"
elif printf '%s\n' "$sshd_effective" | grep -qx 'passwordauthentication no' &&
	printf '%s\n' "$sshd_effective" | grep -qx 'kbdinteractiveauthentication no'; then
	ok "sshd allows key login only"
else
	warn "sshd allows password login — PasswordAuthentication no · KbdInteractiveAuthentication no in \$PREFIX/etc/ssh/sshd_config.d/ (PRD §40)"
fi

commit="$(proot-distro login ubuntu -- sed -n 's/^commit=//p' /opt/nimwake/BUILD_INFO 2>/dev/null || true)"
# --version은 Core v0.1.0-rc6부터 있다. daemon을 띄우지 않고 binary 자신에게 묻는다
version="$(proot-distro login ubuntu --user nimwake -- /opt/nimwake/bin/nimwaked --version 2>/dev/null || true)"
if [ -n "$commit" ]; then
	ok "nimwaked installed in Ubuntu (core $(printf '%s' "$commit" | cut -c1-7), ${version:-version unknown — older than rc6})"
else
	fail "nimwaked is not installed in Ubuntu — make deploy"
fi
# --min-free-memory-mb는 rc4부터다. 옛 binary에 넘기면 모르는 인자로 설정 오류(78) — host/lib/config.sh
if [ -z "$version" ] && grep -q '^NIMWAKE_MIN_FREE_MEMORY_MB=.' "$HOME/.nimwake-host/host.conf" 2>/dev/null; then
	warn "NIMWAKE_MIN_FREE_MEMORY_MB is set but the installed nimwaked is older than rc6 — check it accepts --min-free-memory-mb (rc4+)"
fi

# proot 아래에서 comm이 잘리므로 전체 경로로 찾는다. 생존 판단은 health probe다. (Core PRD §74)
if pgrep -f '^/opt/nimwake/bin/nimwaked' >/dev/null; then
	code="$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: nimwake-health.invalid' http://127.0.0.1:8080/ || true)"
	if [ "$code" = 404 ]; then
		ok "nimwaked running, health probe 404"
	else
		fail "nimwaked running but health probe returned $code"
	fi
else
	warn "nimwaked is not running (stopped with make stop, or the boot failed)"
fi

free_mb=$(($(df -Pk "$HOME" | awk 'NR == 2 { print $4 }') / 1024))
if [ "$free_mb" -ge 10240 ]; then
	ok "storage ${free_mb}MB free"
else
	warn "storage ${free_mb}MB free (< 10GB, PRD §18)"
fi

# 네트워크 상태는 supervisor가 기록한다 (host/lib/network.sh, PRD §13–§14)
net="$HOME/.nimwake-host/run/network"
if [ ! -f "$net" ]; then
	warn "network state unknown — the running supervisor does not record it yet (make deploy, then nimwake-host stop · start)"
elif grep -q '^ONLINE ' "$net"; then
	ok "network $(cat "$net")"
else
	warn "network $(cat "$net")"
fi
# Android는 앱이 게이트웨이 주소를 읽지 못하게 막는다 — 적어 주어야 게이트웨이 검사가 켜진다
if ! grep -q '^NIMWAKE_NET_GATEWAY=.' "$HOME/.nimwake-host/host.conf" 2>/dev/null; then
	warn "gateway check is off — set NIMWAKE_NET_GATEWAY=<router IP> in ~/.nimwake-host/host.conf (PRD §14)"
fi

log="$HOME/.nimwake-host/logs/boot.log"
if [ ! -f "$log" ]; then
	warn "no boot.log — Termux:Boot has not run 10-nimwake yet"
else
	last="$(awk '/boot: start/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }' "$log")"
	started="$(printf '%s\n' "$last" | head -n 1 | cut -c1-19)"
	if printf '%s\n' "$last" | grep -q 'ready: health 404'; then
		ok "last boot run reached READY ($started)"
	elif printf '%s\n' "$last" | grep -q 'already running'; then
		ok "last boot run found nimwaked already running ($started)"
	else
		fail "last boot run did not reach READY ($started) — see ~/.nimwake-host/logs/"
	fi
fi
} </dev/null
EOF
)"

adb_report="$(
	if command -v "$adb" >/dev/null 2>&1 && [ "$(adb_run get-state)" = device ]; then
		# Android 12–13은 phantom process를 32개로 제한한다. 넘으면 Termux의 child가 죽는다.
		max="$(adb_run shell device_config get activity_manager max_phantom_processes)"
		case "$max" in
		2147483647) echo "[OK]     phantom process limit disabled (max_phantom_processes=$max)" ;;
		"" | null) echo "[WARN]   phantom process limit is the Android default (32) — adb shell device_config put activity_manager max_phantom_processes 2147483647" ;;
		*) echo "[WARN]   phantom process limit max_phantom_processes=$max" ;;
		esac

		# 배터리 "제한 없음"은 deviceidle whitelist에 들어간다. 줄 형식: user,<package>,<uid>
		whitelist="$(adb_run shell dumpsys deviceidle whitelist)"
		for package in com.termux com.termux.boot; do
			if printf '%s\n' "$whitelist" | grep -q ",$package,"; then
				echo "[OK]     battery optimization exempt: $package"
			else
				echo "[WARN]   battery optimization applies to $package — set battery to Unrestricted"
			fi
		done
	else
		echo "[MANUAL] phantom process limit — needs adb (pair wireless debugging; set ADB, and ANDROID_SERIAL if more than one device)"
		echo "[MANUAL] battery optimization exemption for Termux, Termux:Boot — needs adb"
	fi
)"

printf '%s\n%s\n' "$device_report" "$adb_report"

if printf '%s\n%s\n' "$device_report" "$adb_report" | grep -q '^\[FAIL\]'; then
	exit 1
fi
