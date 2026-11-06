#!/bin/sh
# Disposable VM integration test, not a production switch implementation.
# Temporarily replaces live proxy instances and always restores them on exit.
set -e
[ "${DNS_MANAGER_DISPOSABLE_VM:-}" = yes ] || { echo 'Requires disposable VM' >&2; exit 1; }
[ -x /etc/init.d/dns-manager-dot ] && [ -r /usr/share/libubox/jshn.sh ] || exit 1
. /usr/share/libubox/jshn.sh
t="$(mktemp -d)"; restore=0; dot_started=0
helper="${DOT_FIREWALL_HELPER:-libexec/dns-manager-dot-firewall.sh}"
DOT_FIREWALL_RUNTIME="$t/guard"; export DOT_FIREWALL_RUNTIME
cleanup() {
    if [ "$dot_started" = 1 ]; then /etc/init.d/dns-manager-dot stop >/dev/null 2>&1 || true; fi
    if [ "$restore" = 1 ]; then
        ubus call service add "{\"name\":\"https-dns-proxy\",\"instances\":$(cat "$t/instances")}" >/dev/null 2>&1 || {
            echo "Proxy restore failed; instance snapshot retained in $t" >&2; return; }
    fi
    if [ -f "$DOT_FIREWALL_RUNTIME/firewall-guard.json" ]; then
        if ! sh "$helper" finish >/dev/null 2>&1; then
            echo "Guard cleanup failed; state retained in $t" >&2; return
        fi
        /etc/init.d/firewall reload >/dev/null 2>&1 || true
    fi
    rm -rf "$t"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
ubus call service list '{"name":"dns-manager-dot"}' | grep -q '"running": true' && { echo 'DoT already running' >&2; exit 1; }
[ -r "$helper" ] || exit 1
snapshot="$(ubus call service list '{"name":"https-dns-proxy"}')"
printf '%s\n' "$snapshot" | jsonfilter -e '@["https-dns-proxy"].instances' > "$t/instances"
[ -s "$t/instances" ] || exit 1
json_load "$snapshot"; json_select https-dns-proxy; json_select instances; json_get_keys instances
[ -n "$instances" ] || exit 1
cp /etc/config/dhcp "$t/dhcp"; cp /etc/config/https-dns-proxy "$t/proxy"
sh "$helper" start
restore=1
for instance in $instances; do
    case "$instance" in *[!A-Za-z0-9_-]*|'') exit 1;; esac
    ubus call service delete "{\"name\":\"https-dns-proxy\",\"instance\":\"$instance\"}" >/dev/null
done
dot_started=1
/etc/init.d/dns-manager-dot start >/dev/null
[ ! -f "$DOT_FIREWALL_RUNTIME/firewall-guard.json" ] || {
    /etc/init.d/firewall reload >/dev/null
    nft list ruleset | grep -Fq 'dns-manager-dot-fw-guard' || { echo 'DNS firewall guard missing' >&2; exit 1; }
}
if [ "${DOT_TEST_INJECT_FAILURE:-no}" = yes ]; then echo 'Injected failure'; exit 1; fi
for port in 5053 5054; do
    ok=0
    for try in 1 2 3 4 5; do
        if dig @127.0.0.1 -p "$port" example.com A +short +time=3 +tries=1 | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then ok=1; break; fi
        sleep 1
    done
    [ "$ok" = 1 ] || { echo "DoT slot on port $port failed" >&2; exit 1; }
done
ports=53
[ "${DOT_TEST_STEER:-yes}" = yes ] && ports='53 5300'
for port in $ports; do
    dig @127.0.0.1 -p "$port" example.com A +short +time=4 +tries=1 |
        grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || { echo "DNS path $port failed" >&2; exit 1; }
done
cmp -s "$t/dhcp" /etc/config/dhcp && cmp -s "$t/proxy" /etc/config/https-dns-proxy || { echo 'UCI configuration changed' >&2; exit 1; }
echo "OK: two DoT slots answered through tested DNS paths (Steer: ${DOT_TEST_STEER:-yes})"

