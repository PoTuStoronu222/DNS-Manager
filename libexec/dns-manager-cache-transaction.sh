#!/bin/sh
# Experimental cache apply/restore. Caller must serialize DNS Manager changes.
# section size ttl guard restart-command [args...]
set -eu
[ "$#" -ge 5 ] || exit 2
section=$1; wanted_size=$2; wanted_ttl=$3; guard=$4
shift 4
package=dhcp
case "$section" in '@dnsmasq[0]') ;; ''|*[!A-Za-z0-9_]*) exit 2 ;; esac
for n in "$wanted_size" "$wanted_ttl"; do
    case "$n" in ''|*[!0-9]*|0[0-9]*) exit 2 ;; esac
    [ "${#n}" -le 5 ] || exit 2
done
[ "$wanted_size" -le 10000 ] && [ "$wanted_ttl" -le 3600 ] || exit 2
[ -r "$guard" ] || exit 1
t="$(mktemp -d /tmp/dns-cache-tx.XXXXXX)" || exit 1
sid=''
cleanup() {
    [ -z "$sid" ] || ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null 2>&1 || true
    rm -rf "$t"
}
trap cleanup EXIT HUP INT TERM
new_session() {
    sid="$(ubus call session create '{"timeout":60}' | jsonfilter -e '@.ubus_rpc_session')"
    case "$sid" in *[!a-f0-9]*|'') return 1;; esac
    [ "${#sid}" -eq 32 ] || return 1
    ubus call session grant "{\"ubus_rpc_session\":\"$sid\",\"scope\":\"uci\",\"objects\":[[\"dhcp\",\"read\"],[\"dhcp\",\"write\"]]}" >/dev/null
}
end_session() {
    ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null
    sid=''
}
read_options() {
    ubus call uci get "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\",\"section\":\"$section\"}" > "$t/current" || return 1
    grep -Eq '"\.type"[[:space:]]*:[[:space:]]*"dnsmasq"' "$t/current" || return 1
    instance="$(sed -n 's/.*"\.name"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9_]*\)".*/\1/p' "$t/current")"
    case "$instance" in ''|*[!A-Za-z0-9_]*) return 1 ;; esac
    current_size='unset'; current_ttl='unset'
    if grep -q '"cachesize"[[:space:]]*:' "$t/current"; then current_size="$(jsonfilter -i "$t/current" -e '@.values.cachesize')"; fi
    if grep -q '"min_cache_ttl"[[:space:]]*:' "$t/current"; then current_ttl="$(jsonfilter -i "$t/current" -e '@.values.min_cache_ttl')"; fi
    for val in "$current_size" "$current_ttl"; do
        case "$val" in unset) ;; ''|*[!0-9]*) return 1 ;; *) [ "${#val}" -le 10 ] || return 1;; esac
    done
}
write_option() {
    key=$1; value=$2; prior=$3
    if [ "$value" = unset ]; then
        [ "$prior" = unset ] || ubus call uci delete "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\",\"section\":\"$section\",\"option\":\"$key\"}" >/dev/null
    else
        ubus call uci set "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\",\"section\":\"$section\",\"values\":{\"$key\":\"$value\"}}" >/dev/null
    fi
}
sh "$guard" "$package" /bin/true || { echo 'Pending or busy UCI configuration' >&2; exit 1; }
new_session; read_options
old_size=$current_size; old_ttl=$current_ttl
expected_instance=$instance
write_option cachesize "$wanted_size" "$old_size"
write_option min_cache_ttl "$wanted_ttl" "$old_ttl"
ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\"}" >/dev/null
end_session
# Marker distinguishes a refused guard from a service that was actually run.
if sh "$guard" "$package" /bin/sh -c '
    touch "$1"; shift
    instance=$1; shift
    "$@" || exit 1
    sleep 1
    state=$(ubus call service list '\''{"name":"dnsmasq"}'\'' | jsonfilter -e "@.dnsmasq.instances.$instance.running") || exit 1
    [ "$state" = true ]
' sh "$t/restarted" "$expected_instance" "$@"; then
    exit 0
fi
echo 'Cache restart failed; attempting to restore previous cache options' >&2
new_session; read_options
if [ "$current_size" != "$wanted_size" ] || [ "$current_ttl" != "$wanted_ttl" ]; then
    echo 'Cache settings changed externally; not overwriting them' >&2; exit 1
fi
write_option cachesize "$old_size" "$current_size"
write_option min_cache_ttl "$old_ttl" "$current_ttl"
ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\"}" >/dev/null
end_session
if [ -e "$t/restarted" ]; then
    sh "$guard" "$package" "$@" || { echo 'Previous settings restored, but dnsmasq restart failed' >&2; exit 1; }
fi
exit 1
