# shellcheck shell=sh
# 배터리 · 전원 감시. config.sh · supervisor.sh 다음에 source한다. supervisor가 정리 작업 주기마다 부른다.
#
# 10-18 · 10-20 기기: USB에 꽂혀 있었는데도 하루 약 45%씩 줄어 두 번 꺼졌다. 아무도 몰랐다 — soak은
# 잔량만 적었고, 충전기가 전류를 못 대는지 · 빠졌는지는 보지 않았다. 꺼지면 Galaxy는 사람이 전원을 눌러야 켜진다.
#
#   ok         꽂혀 있고 충전 중 · 가득 · 충전 보호(NOT_CHARGING) — 잔량이 기준 이상
#   unplugged  충전기가 빠졌다
#   draining   꽂혀 있는데 줄고 있다 (DISCHARGING) — 충전기 · 케이블 · PC USB 포트가 전류를 못 댄다
#   low        잔량이 NIMWAKE_BATTERY_LOW(%) 아래 — 위 무엇이든 이것이 먼저다
#   unknown    읽지 못했다 — Termux:API 앱이 응답하지 않는다 (#67: 한 번 열면 돌아온다)
#
# 상태는 run/battery 한 줄 "LEVEL PCT PLUGGED STATUS TEMP YYYY-MM-DD HH:MM:SS". 바뀔 때만 supervisor.log와 알림.
# unknown은 알리지 않는다 — 알림(termux-notification)도 같은 Termux:API라 닿지 않는다.

# 배터리를 읽어 bat_pct · bat_plugged · bat_status · bat_temp를 채운다. 못 읽으면 1
# Android는 앱에서 /sys/class/power_supply를 막는다 — Termux:API만 된다. 앱이 없으면 명령이 멈추므로 timeout을 건다
battery_read() {
	bat_pct=""
	bat_plugged=NA
	bat_status=NA
	bat_temp=NA
	_json="$(sh -c "$NIMWAKE_BATTERY_CMD" 2>/dev/null | tr -d '\n ')"
	bat_pct="$(printf '%s' "$_json" | sed -n 's/.*"percentage":\([0-9][0-9]*\).*/\1/p')"
	[ -n "$bat_pct" ] || return 1
	_v="$(printf '%s' "$_json" | sed -n 's/.*"plugged":"\([A-Z_]*\)".*/\1/p')"
	[ -n "$_v" ] && bat_plugged="$_v"
	_v="$(printf '%s' "$_json" | sed -n 's/.*"status":"\([A-Z_]*\)".*/\1/p')"
	[ -n "$_v" ] && bat_status="$_v"
	_v="$(printf '%s' "$_json" | sed -n 's/.*"temperature":\(-*[0-9][0-9.]*\).*/\1/p')"
	[ -n "$_v" ] && bat_temp="$(awk -v t="$_v" 'BEGIN { printf "%.1f", t }')"
	return 0
}

# 읽은 값 → LEVEL
battery_level() {
	if [ "$bat_pct" -lt "$NIMWAKE_BATTERY_LOW" ]; then
		echo low
	elif [ "$bat_plugged" = UNPLUGGED ]; then
		echo unplugged
	elif [ "$bat_status" = DISCHARGING ]; then
		echo draining
	else
		echo ok
	fi
}

check_battery() {
	[ "$NIMWAKE_BATTERY_WATCH" = 1 ] || return 0
	_was=""
	if [ -f "$NIMWAKE_RUN/battery" ]; then
		_was="$(cut -d' ' -f1 "$NIMWAKE_RUN/battery")"
	fi
	if battery_read; then
		_level="$(battery_level)"
	else
		_level=unknown
		bat_pct=NA
	fi
	printf '%s %s %s %s %s %s\n' "$_level" "$bat_pct" "$bat_plugged" "$bat_status" "$bat_temp" \
		"$(date '+%Y-%m-%d %H:%M:%S')" >"$NIMWAKE_RUN/battery"
	[ "$_level" = "$_was" ] && return 0

	_now="${bat_pct}% $bat_plugged $bat_status ${bat_temp}°C"
	case "$_level" in
	ok)
		if [ -n "$_was" ]; then
			host_log "battery: ok again — $_now"
		else
			host_log "battery: ok — $_now"
		fi
		;;
	unknown)
		host_log "battery: unknown — termux-battery-status did not answer; open the Termux:API app once"
		;;
	*)
		case "$_level" in
		low) _why="below ${NIMWAKE_BATTERY_LOW}% — the phone powers off when it runs out and needs a person to switch it on" ;;
		unplugged) _why="the charger is unplugged" ;;
		draining) _why="plugged in but discharging — the charger, cable or PC USB port cannot keep up; use a wall charger" ;;
		esac
		host_log "battery: ${_level} — $_now — $_why"
		alert battery "battery ${_level}: ${bat_pct}% — $_why"
		;;
	esac
}
