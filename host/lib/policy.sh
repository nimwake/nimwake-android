# shellcheck shell=sh
# 재기동 판단. 부작용 없는 함수만 둔다 — tests/unit/policy.bats가 검증한다.
# (A2, PRD §23 Restart Policy · §24 Crash Loop, Core PRD §74 종료 코드)
#
# POSIX sh에는 local이 없으므로 함수 안의 변수는 `_policy_` 접두사로 충돌을 피한다.

# nimwaked 종료 코드 → 할 일
#   stopped  정상 종료 (0). 재기동하지 않는다
#   config   설정 오류 (78, EX_CONFIG). 재기동해도 나아지지 않는다 → UNHEALTHY
#   retry    bind 실패 (69), 그 외 오류 (1), 신호로 죽음 (128+N) → backoff 후 재기동
policy_classify_exit() {
	case "$1" in
	0) echo stopped ;;
	78) echo config ;;
	*) echo retry ;;
	esac
}

# window 안에서 n번째(1부터) 재기동 전에 기다릴 초. 0 → 5 → 15 → 60 → 60 … (PRD §23)
policy_backoff() {
	case "$1" in
	1) echo 0 ;;
	2) echo 5 ;;
	3) echo 15 ;;
	*) echo 60 ;;
	esac
}

# 재기동 시각(epoch 초) 목록에서 window 밖의 것을 버리고 남은 것을 공백으로 잇는다.
#   policy_prune NOW WINDOW [TS ...]
policy_prune() {
	_policy_now=$1
	_policy_window=$2
	shift 2
	_policy_kept=""
	for _policy_ts in "$@"; do
		if [ $((_policy_now - _policy_ts)) -lt "$_policy_window" ]; then
			_policy_kept="${_policy_kept:+$_policy_kept }$_policy_ts"
		fi
	done
	echo "$_policy_kept"
}

# 공백으로 이은 목록의 원소 수.
policy_count() {
	# shellcheck disable=SC2086 # 의도적으로 단어로 나눈다
	set -- $1
	echo $#
}

# window 안 재기동 횟수가 상한에 닿았으면 참(0)이다. → crash loop, 더 재기동하지 않는다 (PRD §24)
#   policy_crash_loop COUNT MAX
policy_crash_loop() {
	[ "$1" -ge "$2" ]
}
