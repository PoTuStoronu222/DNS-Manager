#!/bin/sh
# Experimental dnsmasq upstream transaction. The caller serializes Manager
# mutations and verifies that the DNSCrypt listener is answering first.
# Usage: script port guard restart-command [args...]
# jshn uses optional shell variables and is not compatible with nounset.
set -e
[ "$#" -ge 3 ] || exit 2
port=$1; guard=$2; shift 2
case "$port" in ''|*[!0-9]*) exit 2;; esac
[ "${#port}" -le 5 ] && [ "$port" -gt 0 ] && [ "$port" -le 65535 ] || exit 2
[ -r "$guard" ] || exit 1
. /usr/share/libubox/jshn.sh
section='@dnsmasq[0]'
dir=$(mktemp -d /tmp/dnscrypt-dnsmasq.XXXXXX) || exit 1
sid=''
cleanup() {
    [ -z "$sid" ] || ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null 2>&1 || :
    rm -rf "$dir"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
session_open() {
    sid=$(ubus call session create '{"timeout":60}' | jsonfilter -e '@.ubus_rpc_session') || return 1
    case "$sid" in ''|*[!0-9a-f]*) return 1;; esac
    [ "${#sid}" -eq 32 ] || return 1
    ubus call session grant "{\"ubus_rpc_session\":\"$sid\",\"scope\":\"uci\",\"objects\":[[\"dhcp\",\"read\"],[\"dhcp\",\"write\"]]}" >/dev/null
}
session_close() {
    ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null || return 1
    sid=''
}
sh "$guard" dhcp /bin/true || { echo 'Pending DHCP changes; not changing DNS' >&2; exit 1; }
session_open
ubus call uci get "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\",\"section\":\"$section\"}" > "$dir/current" || exit 1
json_load "$(cat "$dir/current")" || exit 1
json_select values || exit 1
json_get_var type '.type'
[ "$type" = dnsmasq ] || exit 1
json_get_var instance '.name'
case "$instance" in ''|*[!A-Za-z0-9_]*) exit 1;; esac
# Keep domain-specific entries, including regional routing, but replace common
# upstreams as requested for a fresh Manager configuration.
: > "$dir/domains"
json_get_type server_type server || server_type=''
case "$server_type" in
    array)
        json_select server || exit 1
        json_get_keys keys
        for key in $keys; do
            json_get_var value "$key"
            case "$value" in /*/*) printf '%s\n' "$value" >> "$dir/domains";; esac
        done
        json_select .. || exit 1 ;;
    string)
        json_get_var value server
        case "$value" in /*/*) printf '%s\n' "$value" >> "$dir/domains";; esac ;;
    '') ;;
    *) echo 'Unsupported dnsmasq server option' >&2; exit 1 ;;
esac
build_request() {
    mode=$1
    json_init
    json_add_string ubus_rpc_session "$sid"
    json_add_string config dhcp
    json_add_string section "$section"
    json_add_object values
    if [ "$mode" = encrypted ] || [ -s "$dir/domains" ]; then
        json_add_array server
        while IFS= read -r value; do [ -n "$value" ] && json_add_string '' "$value"; done < "$dir/domains"
        [ "$mode" != encrypted ] || json_add_string '' "127.0.0.1#$port"
        json_close_array
    fi
    if [ "$mode" = encrypted ]; then
        json_add_string noresolv 1
        json_add_string cachesize 0
    else
        json_add_string noresolv 0
        json_add_string cachesize 1000
    fi
    json_close_object
    json_dump
}
ubus call uci set "$(build_request encrypted)" >/dev/null || exit 1
ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\"}" >/dev/null || exit 1
session_close
if sh "$guard" dhcp /bin/sh -c '
    instance=$1; shift
    "$@" || exit 1
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        state=$(ubus -t 3 call service list '\''{"name":"dnsmasq"}'\'' | jsonfilter -e "@.dnsmasq.instances.$instance.running") || state=unknown
        [ "$state" = true ] && exit 0
        sleep 1
    done
    exit 1
' sh "$instance" "$@"; then
    exit 0
fi
# The caller requested stock DNS as the failure state. Isolate the UCI
# session so another interface's pending changes are not committed here.
echo 'dnsmasq restart failed; restoring standard DNS' >&2
session_open
# Another actor may have changed the active options after our commit. Do not
# overwrite those later changes while attempting recovery.
ubus call uci get "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\",\"section\":\"$section\"}" > "$dir/after" || exit 1
json_load "$(cat "$dir/after")" || exit 1
json_select values || exit 1
json_get_var after_noresolv noresolv
json_get_var after_cachesize cachesize
[ "$after_noresolv" = 1 ] && [ "$after_cachesize" = 0 ] || { echo 'DNS settings changed concurrently; not overwriting them' >&2; exit 1; }
json_get_type after_type server
[ "$after_type" = array ] || { echo 'DNS servers changed concurrently; not overwriting them' >&2; exit 1; }
json_select server || exit 1
json_get_keys after_keys
: > "$dir/after-servers"
for key in $after_keys; do json_get_var value "$key"; printf '%s\n' "$value" >> "$dir/after-servers"; done
cat "$dir/domains" > "$dir/expected-servers"
printf '127.0.0.1#%s\n' "$port" >> "$dir/expected-servers"
cmp -s "$dir/expected-servers" "$dir/after-servers" || { echo 'DNS servers changed concurrently; not overwriting them' >&2; exit 1; }
if [ ! -s "$dir/domains" ]; then
    # rpcd rejects an empty UCI list. Delete the previously installed server
    # option within this same session instead of sending server: [].
    ubus call uci delete "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\",\"section\":\"$section\",\"option\":\"server\"}" >/dev/null || exit 1
fi
ubus call uci set "$(build_request stock)" >/dev/null || exit 1
ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\"}" >/dev/null || exit 1
session_close
sh "$guard" dhcp "$@" || echo 'Standard DNS saved, but dnsmasq restart failed' >&2
exit 1
