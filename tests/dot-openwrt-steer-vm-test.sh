#!/bin/sh
# Optional test for an already-configured disposable OpenWrt VM with real Steer.
set -eu
[ "${DNS_MANAGER_DISPOSABLE_VM:-}" = yes ] || { echo 'Requires disposable VM' >&2; exit 1; }
helper="${DOT_FIREWALL_HELPER:-libexec/dns-manager-dot-firewall.sh}"
[ -r "$helper" ] && [ -x /etc/init.d/steer ] || exit 1
if ! /etc/init.d/steer running >/dev/null 2>&1; then
    pgrep -x steerd >/dev/null 2>&1 || { echo 'Steer is not running' >&2; exit 1; }
fi
[ "$(uci -q get https-dns-proxy.config.force_dns)" = 0 ] || { echo 'Proxy forced DNS must be disabled for this fixture' >&2; exit 1; }
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
DOT_FIREWALL_RUNTIME="$t"; export DOT_FIREWALL_RUNTIME
nft list chain inet steer prerouting_dns > "$t/chain-before"
grep -Eq 'udp dport 53.*redirect to :5300' "$t/chain-before" || exit 1
grep -Eq 'tcp dport 53.*redirect to :5300' "$t/chain-before" || exit 1
sh "$helper" start
[ ! -e "$t/firewall-guard.json" ] || { echo 'Unexpected proxy firewall guard with forced DNS disabled' >&2; exit 1; }
for transport in +notcp +tcp; do
    dig @127.0.0.1 -p 5300 example.com A +short +time=4 +tries=1 "$transport" |
        grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || { echo "Steer DNS query failed: $transport" >&2; exit 1; }
done
nft list chain inet steer prerouting_dns | sed -E 's/counter packets [0-9]+ bytes [0-9]+/counter packets N bytes N/g' > "$t/chain-after"
sed -E 's/counter packets [0-9]+ bytes [0-9]+/counter packets N bytes N/g' "$t/chain-before" > "$t/chain-normalized"
cmp -s "$t/chain-normalized" "$t/chain-after" || { echo 'Steer DNS chain changed' >&2; exit 1; }
echo 'OK: real Steer DNS remains active with no proxy forced-DNS metadata'

