#!/bin/sh
# Disposable VM only: stops the proxy and reloads firewall.
set -eu
[ "${DNS_MANAGER_DISPOSABLE_VM:-}" = yes ] || { echo 'Requires disposable VM' >&2; exit 1; }
helper="${DOT_FIREWALL_HELPER:-libexec/dns-manager-dot-firewall.sh}"
[ -r "$helper" ] && [ -x /etc/init.d/https-dns-proxy ] || exit 1
/etc/init.d/https-dns-proxy running >/dev/null 2>&1 || { echo 'Proxy must be running' >&2; exit 1; }
t="$(mktemp -d)"; DOT_FIREWALL_RUNTIME="$t"; export DOT_FIREWALL_RUNTIME
cleanup() {
    /etc/init.d/https-dns-proxy start >/dev/null 2>&1 || true
    if [ -f "$t/firewall-guard.json" ] && ! sh "$helper" finish >/dev/null 2>&1; then
        echo "Guard cleanup failed; state retained in $t" >&2
        return
    fi
    /etc/init.d/firewall reload >/dev/null 2>&1 || true
    rm -rf "$t"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
sh "$helper" start
[ -f "$t/firewall-guard.json" ] || { echo 'Expected proxy firewall metadata' >&2; exit 1; }
if sh "$helper" start >/dev/null 2>&1; then echo 'Duplicate guard accepted' >&2; exit 1; fi
/etc/init.d/https-dns-proxy stop >/dev/null
/etc/init.d/firewall reload >/dev/null
rules="$(nft list ruleset | grep -F 'dns-manager-dot-fw-guard')" || { echo 'Handoff rules missing' >&2; exit 1; }
printf '%s\n' "$rules" | grep -Eq 'tcp dport 53.*redirect to :53' || exit 1
printf '%s\n' "$rules" | grep -Eq 'udp dport 53.*redirect to :53' || exit 1
printf '%s\n' "$rules" | grep -Eq 'tcp dport 853.*(reject|handle_reject)' || exit 1
printf '%s\n' "$rules" | grep -Eq 'udp dport 853.*(reject|handle_reject)' || exit 1
/etc/init.d/https-dns-proxy start >/dev/null
cp "$t/firewall-guard.json" "$t/original"
printf '%s\n' '[]' > "$t/firewall-guard.json"
if sh "$helper" finish >/dev/null 2>&1; then echo 'Changed guard state accepted' >&2; exit 1; fi
cp "$t/original" "$t/firewall-guard.json"
sh "$helper" finish
[ ! -e "$t/firewall-guard.json" ] || exit 1
echo 'OK: actual proxy firewall metadata was preserved during VM handoff'

