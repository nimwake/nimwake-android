#!/bin/sh
# 개발 머신 스크립트의 이식성 검사. macOS(BSD)와 WSL · Linux(GNU)에서 같은 명령으로 돌아야 한다.
# (Phase 1 01-repository-setup §3 "이식성 규칙", D-A7)
#
# ShellCheck는 bash 문법은 잡지만 BSD/GNU 옵션 차이는 못 잡는다. 규칙표의 금지 패턴을 grep으로 본다.
# macOS runner를 매번 돌리지 않고도 대부분을 여기서 잡는다. make lint가 부른다.
#
# 기기에서만 도는 부분(ssh로 보내는 heredoc 등)이라 괜찮은 줄은 끝에 `# portable-ok`를 붙인다.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd -P)"
cd "$root"

# 이 파일 자신은 패턴 문자열을 담고 있으므로 뺀다.
files="$(git ls-files 'scripts/*.sh' 'tests/device/*.sh' 'tests/device/*.awk' Makefile | grep -v '^scripts/check-portability\.sh$')"

# 단어 경계: 앞뒤가 이름 문자가 아니어야 한다 (update -d, used -i 같은 오탐을 피한다)
b='(^|[^[:alnum:]_-])'

found=0

# check ERE 대신쓸것
check() {
	# shellcheck disable=SC2086 # 파일 목록을 인자로 나눈다
	hits="$(grep -nE "$1" $files /dev/null |
		grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' |
		grep -v 'portable-ok' || true)"
	if [ -n "$hits" ]; then
		printf '%s\n' "$hits" | sed 's/^/  /'
		echo "    → $2"
		found=1
	fi
}

check "${b}sed( +-[A-Za-z]+)* +-[A-Za-z]*i" 'sed -i 대신 임시 파일에 쓰고 mv'
# shellcheck disable=SC2016 # 확장하지 않는 안내 문구다
check "${b}readlink +-f" 'readlink -f 대신 cd "$(dirname "$0")" && pwd -P'
check "${b}realpath([^[:alnum:]_-]|$)" 'realpath 대신 cd … && pwd -P'
check "${b}date( +[^|;)]*)? +-d" 'date -d 대신 date +%s 만'
check "${b}date +[^|;)]*%N" 'date +%N 대신 date +%s 만'
check "${b}grep( +-[A-Za-z]+)* +-[A-Za-z]*P" 'grep -P 대신 grep -E'
check "${b}rsync([^[:alnum:]_-]|$)" 'rsync(macOS는 openrsync) 대신 tar -cf - … | ssh … tar -xf -'
check "${b}timeout +[0-9]" 'timeout(macOS에 없음) 대신 스크립트 안 polling loop'

if [ "$found" -ne 0 ]; then
	echo "check-portability: macOS(BSD)와 Linux(GNU)에서 다르게 동작하는 명령이 있다" >&2
	exit 1
fi
echo "check-portability: ok ($(printf '%s\n' "$files" | wc -l | tr -d ' ') files)"
