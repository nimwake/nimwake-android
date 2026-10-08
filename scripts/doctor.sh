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
#   ANDROID_SERIAL  adb 기기가 여럿일 때 대상 (adb가 직접 읽는다)
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"
adb="${ADB:-adb}"

device_report="$(ssh "$device" sh -s <<'EOF'
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

if grep -Eq '^[[:space:]]*PasswordAuthentication[[:space:]]+no' "$PREFIX/etc/ssh/sshd_config" 2>/dev/null; then
	ok "sshd password login disabled"
else
	warn "sshd password login is enabled — set PasswordAuthentication no (PRD §40)"
fi

commit="$(proot-distro login ubuntu -- sed -n 's/^commit=//p' /opt/nimwake/BUILD_INFO 2>/dev/null || true)"
if [ -n "$commit" ]; then
	ok "nimwaked installed in Ubuntu (core $(printf '%s' "$commit" | cut -c1-7))"
else
	fail "nimwaked is not installed in Ubuntu — make deploy"
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
EOF
)"

adb_report="$(
	if command -v "$adb" >/dev/null 2>&1 && [ "$("$adb" get-state 2>/dev/null)" = device ]; then
		# Android 12–13은 phantom process를 32개로 제한한다. 넘으면 Termux의 child가 죽는다.
		max="$("$adb" shell device_config get activity_manager max_phantom_processes 2>/dev/null | tr -d '\r')"
		case "$max" in
		2147483647) echo "[OK]     phantom process limit disabled (max_phantom_processes=$max)" ;;
		"" | null) echo "[WARN]   phantom process limit is the Android default (32) — adb shell device_config put activity_manager max_phantom_processes 2147483647" ;;
		*) echo "[WARN]   phantom process limit max_phantom_processes=$max" ;;
		esac

		# 배터리 "제한 없음"은 deviceidle whitelist에 들어간다. 줄 형식: user,<package>,<uid>
		whitelist="$("$adb" shell dumpsys deviceidle whitelist 2>/dev/null | tr -d '\r')"
		for package in com.termux com.termux.boot; do
			if printf '%s\n' "$whitelist" | grep -q ",$package,"; then
				echo "[OK]     battery optimization exempt: $package"
			else
				echo "[WARN]   battery optimization applies to $package — set battery to Unrestricted"
			fi
		done
	else
		echo "[MANUAL] phantom process limit — needs adb (pair wireless debugging, or set ADB)"
		echo "[MANUAL] battery optimization exemption for Termux, Termux:Boot — needs adb"
	fi
)"

printf '%s\n%s\n' "$device_report" "$adb_report"

if printf '%s\n%s\n' "$device_report" "$adb_report" | grep -q '^\[FAIL\]'; then
	exit 1
fi
