# shellcheck shell=sh
# 로그 순환 (PRD §20). config.sh 다음에 source한다. host_log는 supervisor.sh에 있다.
#
# 크기가 NIMWAKE_LOG_MAX_KB를 넘으면 FILE → FILE.1 → … → FILE.KEEP로 밀고, 그보다 오래된 것은 지운다.
# 이름을 바꾸지 않고 복사한 뒤 원본을 비운다(copytruncate). nimwaked는 nimwaked.log를 `>>`로 연 채 계속 쓰므로
# 이름을 바꾸면 옮긴 파일에 계속 쓴다. O_APPEND라 비운 뒤의 쓰기는 새 끝에 붙는다.
# 복사와 비우기 사이에 쓰인 몇 줄은 잃을 수 있다 — logrotate copytruncate와 같은 절충이다.
#
# soak.csv는 돌리지 않는다 — soak-report가 처음부터 읽는다.
# 실측: nimwaked.log는 하루 약 0.45 MB (validation/10). 기본 20 MB면 한 달 반에 한 번 돈다.

NIMWAKE_ROTATED_LOGS="supervisor.log nimwaked.log boot.log"

# rotate_log FILE — 돌렸으면 돌리기 전 크기(KB)를 출력한다
rotate_log() {
	_file=$1
	[ -f "$_file" ] || return 0
	_size_kb=$(($(wc -c <"$_file") / 1024))
	[ "$_size_kb" -ge "$NIMWAKE_LOG_MAX_KB" ] || return 0

	if [ "$NIMWAKE_LOG_KEEP" -ge 1 ]; then
		_n=$NIMWAKE_LOG_KEEP
		rm -f "$_file.$_n"
		while [ "$_n" -gt 1 ]; do
			_prev=$((_n - 1))
			if [ -f "$_file.$_prev" ]; then
				mv -f "$_file.$_prev" "$_file.$_n"
			fi
			_n=$_prev
		done
		cp -p "$_file" "$_file.1" || return 0
	fi
	: >"$_file"
	echo "$_size_kb"
}

# 저장공간이 부족할 때(supervisor.sh check_storage) 순환된 이전 로그(.1 …)를 지운다.
# 지금 쓰는 로그와 soak 데이터(soak*.csv)는 남긴다. 지웠으면 "개수 KB"를 출력한다.
drop_rotated_logs() {
	_count=0
	_bytes=0
	for _name in $NIMWAKE_ROTATED_LOGS; do
		for _old in "$NIMWAKE_LOGS/$_name".[0-9]*; do
			[ -f "$_old" ] || continue
			_bytes=$((_bytes + $(wc -c <"$_old")))
			rm -f "$_old"
			_count=$((_count + 1))
		done
	done
	if [ "$_count" -gt 0 ]; then
		echo "$_count $((_bytes / 1024))"
	fi
}

rotate_logs() {
	for _name in $NIMWAKE_ROTATED_LOGS; do
		_kb="$(rotate_log "$NIMWAKE_LOGS/$_name")"
		if [ -n "$_kb" ]; then
			host_log "log: rotated $_name (${_kb}KB, keep $NIMWAKE_LOG_KEEP)"
		fi
	done
}
