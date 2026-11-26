#!/bin/sh
set -eu
backend=$1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^append_update_message\(\) \{/,/^update_all_json\(\) \{/ {print; if ($0 ~ /^update_all_json\(\) \{/) capture=1; next} capture {print; if ($0 ~ /^}/) exit}' "$backend" > "$tmp/update.sh"
. "$tmp/update.sh"
RUNTIME_DIR="$tmp"
acquire_runtime_lock() { return 0; }
release_runtime_lock() { :; }
json_quote() { printf '"%s"' "$1"; }
json_update_state() { printf '%s' "$1"; }
manager_version() { printf 'current'; }
read_installed_luci_version() { printf 'current'; }
package_version() { printf 'current'; }
catalog_version() { printf 'catalog'; }
catalog_revision() { printf 'revision'; }
update_manager_json() { printf current; }
update_json() { printf current; }
update_hdp_json() { echo hdp >> "$tmp/calls"; printf current; }
update_catalog_direct() { echo catalog >> "$tmp/calls"; return 0; }
uci() { printf '%s' "$engine"; }
for engine in dnscrypt-proxy2 https-dns-proxy; do
    : > "$tmp/calls"
    update_all_json > "$tmp/result"
    grep -q '"ok":true' "$tmp/result"
    [ "$(grep -c '^catalog$' "$tmp/calls")" -eq 1 ]
    if [ "$engine" = dnscrypt-proxy2 ]; then
        ! grep -q '^hdp$' "$tmp/calls"
    else
        [ "$(grep -c '^hdp$' "$tmp/calls")" -eq 1 ]
    fi
done
printf 'OK: catalog update runs with both engines and does not update HTTPS DNS Proxy under DNSCrypt\n'
