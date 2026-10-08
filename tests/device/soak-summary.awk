# soak.csv 요약. tests/device/soak.sh summarize가 `awk -F, -f`로 쓴다.
#
# macOS(BSD one-true-awk) · mawk · gawk에서 같은 결과가 나와야 한다. 그래서 보수적으로 쓴다:
#   printf 인자 안에 삼항 연산자를 쓰지 않는다 — 값을 먼저 만든다
#   `}` 뒤에 같은 줄로 문장을 잇지 않는다
#
# 열: epoch,time,http,seconds,app_pid,apps_before,daemon_pid,daemon_rss_kb,state,battery_pct,battery_temp_c,free_mb

# nearest-rank 백분위: ceil(n * p)번째 (1부터)
function rank(n, p,    r) {
	r = int(n * p)
	if (r < n * p)
		r++
	if (r < 1)
		r = 1
	return r
}

function or_na(v) {
	if (v == "")
		return "NA"
	return v
}

NR == 1 {
	next
}

{
	n++
	if (n == 1) {
		first = $1
		first_time = $2
		free_first = $12
	}
	last = $1
	last_time = $2
	free_last = $12

	if (n > 1 && $1 - prev > max_gap)
		max_gap = $1 - prev
	prev = $1

	if ($3 != "200") {
		bad++
		bad_list = bad_list "\n    " $2 " http=" $3 " state=" $9
	} else {
		m++
		lat[m] = $4 + 0
	}

	if ($6 != "0")
		orphan++

	if ($7 != "NA" && $7 != daemon) {
		if (daemon != "")
			restarts++
		daemon = $7
	}

	# RSS는 daemon이 없던 표본(NA)을 건너뛰고 측정된 처음 · 마지막 값을 쓴다
	if ($8 != "NA") {
		if (rss_first == "")
			rss_first = $8
		rss_last = $8
		if ($8 + 0 > rss_max)
			rss_max = $8 + 0
	}

	if ($10 != "NA") {
		b = $10 + 0
		if (bmin == "" || b < bmin)
			bmin = b
		if (bmax == "" || b > bmax)
			bmax = b
	}

	if ($11 != "NA") {
		t = $11 + 0
		if (tmax == "" || t > tmax)
			tmax = t
	}
}

END {
	printf "samples          %d  (%s → %s, %.1fh)\n", n, first_time, last_time, (last - first) / 3600
	printf "max gap          %ds  (> 2x interval means the sampler or Termux was stopped)\n", max_gap
	printf "non-200          %d%s\n", bad, bad_list

	if (m > 0) {
		# 삽입 정렬 — 표본은 수백 개 수준이다
		for (i = 2; i <= m; i++) {
			v = lat[i]
			j = i - 1
			while (j > 0 && lat[j] > v) {
				lat[j + 1] = lat[j]
				j--
			}
			lat[j + 1] = v
		}
		printf "cold start       p50 %.3fs  p95 %.3fs  max %.3fs\n", lat[rank(m, 0.5)], lat[rank(m, 0.95)], lat[m]
	}

	printf "apps left awake  %d samples  (should be 0 — scale-to-zero / orphans)\n", orphan
	printf "daemon restarts  %d\n", restarts
	printf "daemon RSS       %s → %s KB  (max %d)\n", or_na(rss_first), or_na(rss_last), rss_max

	battery_min = or_na(bmin)
	battery_max = or_na(bmax)
	temp_max = or_na(tmax)
	printf "battery          %s–%s%%  max temp %s°C\n", battery_min, battery_max, temp_max
	printf "free storage     %s → %s MB\n", free_first, free_last
}
