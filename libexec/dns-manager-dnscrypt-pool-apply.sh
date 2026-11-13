#!/bin/sh
# Apply a Manager-owned pool. Caller must hold DNS Manager's mutation lock.
# Reads DoH URLs from stdin; no dnsmasq, firewall or other package settings
# are changed here. Requires an existing Manager-owned config for recovery.
set -eu

[ "$#" -eq 2 ] || { echo 'Expected local port and bootstrap IP list' >&2; exit 1; }
port=$1
bootstrap=$2
binary=${DNS_MANAGER_DNSCRYPT_BIN:-/usr/sbin/dnscrypt-proxy}
init=${DNS_MANAGER_DNSCRYPT_INIT:-/etc/init.d/dns-manager-dnscrypt}
config=${DNS_MANAGER_DNSCRYPT_CONFIG:-/etc/dns-manager/config/dnscrypt-pool.toml}
generator="$(dirname "$0")/dns-manager-dnscrypt-pool.sh"
[ -x "$binary" ] && [ -x "$init" ] && [ -f "$config" ] && [ ! -L "$config" ] || { echo 'DNSCrypt service or existing config unavailable' >&2; exit 1; }

dir=$(dirname "$config")
candidate=$(mktemp "$dir/.dnscrypt-pool-new.XXXXXX") || exit 1
backup=$(mktemp "$dir/.dnscrypt-pool-old.XXXXXX") || { rm -f "$candidate"; exit 1; }
changed=0
cleanup() {
    rm -f "$candidate"
    if [ "$changed" -eq 1 ]; then
        if mv -f "$backup" "$config"; then
            "$init" restart >/dev/null 2>&1 || echo 'Failed to restart restored DNSCrypt config' >&2
        else
            echo "Failed to restore previous DNSCrypt config; backup retained at $backup" >&2
        fi
    else
        rm -f "$backup"
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
sh "$generator" "$port" "$bootstrap" > "$candidate" || exit 1
"$binary" -config "$candidate" -check >/dev/null 2>&1 || { echo 'Invalid DNSCrypt pool configuration' >&2; exit 1; }
cp -p "$config" "$backup" || exit 1
chmod 0600 "$candidate" || exit 1
mv -f "$candidate" "$config" || exit 1
changed=1

pool_query_ok() {
    if command -v dig >/dev/null 2>&1; then
        dig @127.0.0.1 -p "$port" example.com A +time=2 +tries=1 +short 2>/dev/null |
            awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {ok=1} END {exit !ok}'
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup -port="$port" example.com 127.0.0.1 2>/dev/null |
            awk '/^Address [0-9]+: / {a=$NF} /^Address: / {a=$2} a ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && a !~ /^127\./ && a != "0.0.0.0" {ok=1} END {exit !ok}'
    else
        return 1
    fi
}

ok=0
if "$init" restart >/dev/null 2>&1; then
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if "$init" running >/dev/null 2>&1 && pool_query_ok; then ok=1; break; fi
        sleep 1
    done
fi
if [ "$ok" -eq 1 ]; then changed=0; exit 0; fi

# Preserve the previous pool when the new service or DNS query fails.
echo 'New DNSCrypt pool did not answer; restoring previous config' >&2
exit 1
