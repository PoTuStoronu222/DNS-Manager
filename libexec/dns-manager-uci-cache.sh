#!/bin/sh
# Isolated UCI staging for cache options. This helper does not restart dnsmasq.
# The optional fourth argument exists for tests using a disposable UCI package.
set -eu
section=${1:-}
size=${2:-}
ttl=${3:-}
package=${4:-dhcp}
case "$section" in '@dnsmasq[0]') ;; ''|*[!A-Za-z0-9_]*) exit 2 ;; esac
case "$package" in ''|*[!A-Za-z0-9_]*) exit 2 ;; esac
case "$size" in ''|*[!0-9]*) exit 2 ;; esac
case "$ttl" in ''|*[!0-9]*) exit 2 ;; esac
[ "$size" -le 10000 ] && [ "$ttl" -le 3600 ] || exit 2
sid=''
cleanup() {
    [ -z "$sid" ] || ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null 2>&1 || true
}
trap cleanup EXIT HUP INT TERM
sid="$(ubus call session create '{"timeout":60}' | jsonfilter -e '@.ubus_rpc_session')"
case "$sid" in *[!a-f0-9]*|'') exit 1 ;; esac
[ "${#sid}" -eq 32 ] || exit 1
ubus call session grant "{\"ubus_rpc_session\":\"$sid\",\"scope\":\"uci\",\"objects\":[[\"$package\",\"read\"],[\"$package\",\"write\"]]}" >/dev/null
ubus call uci set "{\"ubus_rpc_session\":\"$sid\",\"config\":\"$package\",\"section\":\"$section\",\"values\":{\"cachesize\":\"$size\",\"min_cache_ttl\":\"$ttl\"}}" >/dev/null
ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"$package\"}" >/dev/null
