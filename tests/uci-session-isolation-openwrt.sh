#!/bin/sh
# Run on an isolated OpenWrt installation. Uses a temporary UCI package only.
set -eu
pkg="dns_cache_isolation_$$"
file="/etc/config/$pkg"
sid=''
cleanup() {
    [ -z "$sid" ] || ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null 2>&1 || true
    uci -q revert "$pkg" >/dev/null 2>&1 || true
    rm -f "$file"
}
trap cleanup EXIT HUP INT TERM
(set -C; printf "config example 'main'\n\toption own 'old'\n\toption foreign 'old'\n" > "$file")
uci set "$pkg.main.foreign=pending"
sid="$(ubus call session create '{"timeout":60}' | jsonfilter -e '@.ubus_rpc_session')"
case "$sid" in *[!a-f0-9]*|'') echo 'Invalid session' >&2; exit 1;; esac
ubus call session grant "{\"ubus_rpc_session\":\"$sid\",\"scope\":\"uci\",\"objects\":[[\"$pkg\",\"read\"],[\"$pkg\",\"write\"]]}" >/dev/null
ubus call uci set "{\"ubus_rpc_session\":\"$sid\",\"config\":\"$pkg\",\"section\":\"main\",\"values\":{\"own\":\"new\"}}" >/dev/null
ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"$pkg\"}" >/dev/null
grep -q "option own 'new'" "$file"
grep -q "option foreign 'old'" "$file"
[ "$(uci -q get "$pkg.main.foreign")" = pending ]
uci -q changes "$pkg" | grep -q 'foreign=.*pending'
printf '%s\n' 'OK: isolated commit retained the foreign pending change without committing it'
sh /tmp/dns-manager-uci-cache.sh main 1200 0 "$pkg"
grep -q "option cachesize '1200'" "$file"
grep -q "option min_cache_ttl '0'" "$file"
grep -q "option foreign 'old'" "$file"
[ "$(uci -q get "$pkg.main.foreign")" = pending ]
sh /tmp/dns-manager-uci-cache.sh main 800 180 "$pkg"
grep -q "option cachesize '800'" "$file"
grep -q "option min_cache_ttl '180'" "$file"
if sh /tmp/dns-manager-uci-cache.sh main 10001 0 "$pkg"; then exit 1; fi
grep -q "option cachesize '800'" "$file"
printf '%s\n' 'OK: cache helper commits only validated cache options and retains foreign changes'
