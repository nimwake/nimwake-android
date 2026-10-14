#!/bin/sh
# ingress provider를 켜고 · 끄고 · 토큰을 넣는다. 계약: .docs/phases/phase-2/03-deploy-and-ingress-contract.md
#
#   ingress.sh enable PROVIDER [MODE]   provider install + host.conf NIMWAKE_INGRESS (+ cloudflare면 _CF_MODE)
#   ingress.sh token [PROVIDER]         표준 입력의 토큰을 기기의 ~/.nimwake-host/secrets/PROVIDER.token(0600)에
#   ingress.sh disable                  host.conf에서 NIMWAKE_INGRESS를 지운다
#
# 켜고 끈 것은 supervisor가 다시 뜰 때 반영된다 — nimwake-host stop · start (daemon도 재시작된다)
# 토큰은 명령줄 인자로 받지 않는다 — shell history · ps에 남는다. 예: make ingress-token < ~/cf.token
#   NIMWAKE_DEVICE  ssh 대상 (기본 nimwake-phone)
set -eu

device="${NIMWAKE_DEVICE:-nimwake-phone}"

usage() {
	echo "usage: ingress.sh enable PROVIDER [MODE] | token [PROVIDER] < TOKEN | disable" >&2
	exit 2
}

cmd_enable() {
	provider="${1:?usage: ingress.sh enable PROVIDER [MODE]}"
	mode="${2:-}"
	ssh "$device" sh -s "$provider" "$mode" <<'EOF'
{
set -eu
provider="$1"; mode="$2"
host="$HOME/.nimwake-host"
dir="$host/ingress/$provider"
[ -x "$dir/install" ] || { echo "ingress: no provider '$provider' in $host/ingress — make deploy" >&2; exit 1; }
"$dir/install"
conf="$host/host.conf"
sed -i '/^NIMWAKE_INGRESS=/d; /^NIMWAKE_INGRESS_CF_MODE=/d' "$conf" # portable-ok: 기기(Termux, GNU)에서 돈다
echo "NIMWAKE_INGRESS=$provider" >>"$conf"
[ -n "$mode" ] && echo "NIMWAKE_INGRESS_CF_MODE=$mode" >>"$conf"
mkdir -p "$host/secrets"
chmod 700 "$host/secrets"
echo "ingress: $provider enabled${mode:+ ($mode)} in host.conf — applies on the next nimwake-host stop · start"
} </dev/null
EOF
}

cmd_token() {
	provider="${1:-cloudflare}"
	if [ -t 0 ]; then
		echo "ingress: give the token on standard input — make ingress-token < FILE (never as an argument)" >&2
		exit 2
	fi
	# 표준 입력이 그대로 기기의 파일로 간다. 명령줄 · 로그에 토큰이 없다
	tr -d '\r\n' | ssh "$device" "umask 077 && mkdir -p \$HOME/.nimwake-host/secrets && chmod 700 \$HOME/.nimwake-host/secrets \
		&& cat >\$HOME/.nimwake-host/secrets/$provider.token && chmod 600 \$HOME/.nimwake-host/secrets/$provider.token \
		&& echo \"ingress: token saved ($provider, \$(wc -c <\$HOME/.nimwake-host/secrets/$provider.token) bytes)\""
}

cmd_disable() {
	# shellcheck disable=SC2016 # 기기에서 푼다
	ssh "$device" 'sed -i "/^NIMWAKE_INGRESS=/d" $HOME/.nimwake-host/host.conf && echo "ingress: disabled in host.conf — applies on the next nimwake-host stop · start"' # portable-ok: 기기(Termux, GNU)에서 돈다
}

case "${1:-}" in
enable) shift; cmd_enable "$@" ;;
token) shift; cmd_token "$@" ;;
disable) cmd_disable ;;
*) usage ;;
esac
