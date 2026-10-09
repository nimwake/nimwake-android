#!/bin/sh
# 개발 머신 점검 — macOS 또는 WSL2에서 이 레포를 쓸 준비가 됐는가. (A0, Phase 1 01 §3)
# 기기는 make doctor가 본다. 여기는 기기에 접속하지 않는다.
#
#   [OK] 기대한 상태 · [WARN] 동작은 하지만 고칠 것 · [FAIL] 이대로는 안 된다 (exit 1) · [MANUAL] 선택
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
#   ADB             adb 실행 파일 (기본 adb)
set -eu

root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$root"
device="${NIMWAKE_DEVICE:-nimwake-phone}"
adb="${ADB:-adb}"
shellcheck_version='0.11.0'

failed=0
ok() { echo "[OK]     $*"; }
warn() { echo "[WARN]   $*"; }
fail() {
	echo "[FAIL]   $*"
	failed=1
}
manual() { echo "[MANUAL] $*"; }

# --- 환경 ---------------------------------------------------------------

case "$(uname -s)" in
Darwin) ok "macOS $(sw_vers -productVersion 2>/dev/null || true)" ;;
Linux)
	if grep -qi microsoft /proc/version 2>/dev/null; then
		ok "WSL2"
		# /mnt/c는 Windows 파일시스템이다. 실행 비트가 사라지고 CRLF가 섞인다.
		case "$root" in
		/mnt/*) fail "repo is on the Windows filesystem ($root) — clone it under ~/ inside WSL" ;;
		*) ok "repo on the WSL filesystem ($root)" ;;
		esac
	else
		ok "Linux"
	fi
	;;
*) warn "unsupported OS $(uname -s) — macOS or WSL2 is expected (D-A7)" ;;
esac

autocrlf="$(git config --get core.autocrlf || true)"
case "$autocrlf" in
'' | false | input) ok "git core.autocrlf=${autocrlf:-unset}" ;;
*) warn "git core.autocrlf=$autocrlf — shell scripts may get CRLF; set it to false" ;;
esac

# --- 도구 ---------------------------------------------------------------

for tool in git make ssh curl awk tar; do
	if command -v "$tool" >/dev/null 2>&1; then
		ok "$tool"
	else
		fail "$tool is missing"
	fi
done

if ! command -v gh >/dev/null 2>&1; then
	fail "gh is missing — make fetch-core downloads Core releases with it"
elif gh auth status >/dev/null 2>&1; then
	ok "gh (logged in)"
else
	fail "gh is not logged in — gh auth login (Core is a private repo)"
fi

if ! command -v shellcheck >/dev/null 2>&1; then
	fail "shellcheck is missing — make lint (CI uses $shellcheck_version)"
else
	version="$(shellcheck --version | awk '/^version:/ { print $2 }')"
	if [ "$version" = "$shellcheck_version" ]; then
		ok "shellcheck $version"
	else
		warn "shellcheck $version — CI uses $shellcheck_version, warnings differ between versions"
	fi
fi

if command -v bats >/dev/null 2>&1; then
	ok "bats $(bats --version | awk '{ print $2 }')"
else
	fail "bats is missing — make test"
fi

if command -v "$adb" >/dev/null 2>&1; then
	ok "adb ($adb)"
else
	manual "adb not found — optional, make doctor uses it for phantom process · battery checks (set ADB)"
fi

# --- 레포 ---------------------------------------------------------------

# git이 실행 비트를 잃으면 기기에서 Permission denied가 난다. CI의 같은 검사.
not_executable=""
for f in $(git ls-files '*.sh' 'host/bin/*' 'host/boot/*' 'tests/unit/fixtures/*'); do
	case "$f" in host/lib/*) continue ;; esac
	[ -x "$f" ] || not_executable="$not_executable $f"
done
if [ -z "$not_executable" ]; then
	ok "executable bits"
else
	fail "not executable:$not_executable — chmod +x"
fi

if [ -x dist/aarch64/nimwaked ]; then
	ok "Core binary in dist/ ($(sed -n 's/^ref=//p' dist/aarch64/BUILD_INFO))"
else
	warn "no Core binary in dist/ — make fetch-core"
fi

# --- 기기 접속 설정 (접속은 하지 않는다) -----------------------------------

# ssh -G는 접속하지 않고 설정만 푼다. alias가 정의돼 있지 않으면 hostname이 alias 그대로다.
target="$(ssh -G "$device" 2>/dev/null | awk '$1 == "hostname" { print $2 }')"
port="$(ssh -G "$device" 2>/dev/null | awk '$1 == "port" { print $2 }')"
if [ -n "$target" ] && [ "$target" != "$device" ]; then
	ok "ssh $device → $target:$port"
else
	warn "ssh host $device is not in ~/.ssh/config — Host $device / HostName <phone IP> / Port 8022 / IdentityFile"
fi

exit "$failed"
