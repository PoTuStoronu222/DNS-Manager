#!/bin/sh
# Detach the Manager-owned per-device redirect before stopping its listeners.
# Caller serializes Manager mutations. This script does not touch Steer rules.
set -e
guard=${DNS_MANAGER_UCI_GUARD:-/usr/lib/dns-manager-luci/cache/uci-read-guard.sh}
device_init=${DNS_MANAGER_DEVICE_INIT:-/etc/init.d/dns-manager-device-dns}
firewall_init=${DNS_MANAGER_FIREWALL_INIT:-/etc/init.d/firewall}
assignments=${DNS_MANAGER_DEVICE_ASSIGNMENTS:-/etc/dns-manager/config/device-dns.conf}
default_assignments=${DNS_MANAGER_DEVICE_DEFAULT_ASSIGNMENTS:-/etc/dns-manager/config/device-dns-default.conf}
nft_file=${DNS_MANAGER_DEVICE_NFT:-/etc/dns-manager/device-dns/redirects.nft}
legacy_nft=${DNS_MANAGER_DEVICE_LEGACY_NFT:-/etc/nftables.d/90-dns-manager-device-dns.nft}
name=dns_manager_device_dns
sid=''
cleanup() {
    [ -z "$sid" ] || ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null 2>&1 || :
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
[ -r "$guard" ] && [ -x "$firewall_init" ] || { echo 'Firewall guard or service missing' >&2; exit 1; }
sh "$guard" firewall /bin/true || { echo 'Pending firewall changes' >&2; exit 1; }
sid=$(ubus call session create '{"timeout":60}' | jsonfilter -e '@.ubus_rpc_session') || exit 1
case "$sid" in ''|*[!0-9a-f]*) exit 1;; esac
[ "${#sid}" -eq 32 ] || exit 1
ubus call session grant "{\"ubus_rpc_session\":\"$sid\",\"scope\":\"uci\",\"objects\":[[\"firewall\",\"read\"],[\"firewall\",\"write\"]]}" >/dev/null
reply=$(ubus call uci get "{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\"}") || exit 1
. /usr/share/libubox/jshn.sh
json_load "$reply" || exit 1
json_select values || exit 1
changed=0
if json_select "$name" 2>/dev/null; then
    json_get_var type '.type'
    json_get_var include_type type
    json_get_var include_path path
    json_get_var position position
    json_get_var chain chain
    [ "$type" = include ] && [ "$include_type" = nftables ] &&
    [ "$include_path" = "$nft_file" ] && [ "$position" = chain-pre ] &&
    [ "$chain" = dstnat_lan ] || { echo 'Unrelated firewall include with Manager name' >&2; exit 1; }
    ubus call uci delete "{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\",\"section\":\"$name\"}" >/dev/null
    ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\"}" >/dev/null
    changed=1
fi
ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null || exit 1
sid=''
# Reload while listeners are still alive. If reload fails, do not stop them.
if [ "$changed" = 1 ] || [ -x "$device_init" ]; then
    sh "$guard" firewall "$firewall_init" reload || { echo 'Firewall reload failed; listeners retained' >&2; exit 1; }
fi
service_absent() {
    _reply=$(ubus -t 5 call service list '{"name":"dns-manager-device-dns"}') || return 1
    _root=$(jsonfilter -s "$_reply" -e '@') || return 1
    case "$_root" in \{*\}) ;; *) return 1;; esac
    if jsonfilter -s "$_reply" -e "@['dns-manager-device-dns']" >/dev/null 2>&1; then
        return 1
    else
        [ "$?" -eq 1 ]
    fi
}
if [ -x "$device_init" ]; then
    # stop_service itself reloads firewall. Holding the read guard prevents it
    # from consuming or committing another process's staged firewall changes.
    if ! sh "$guard" firewall /bin/sh -c '
        if uci -q get firewall.dns_manager_device_dns >/dev/null 2>&1; then exit 1; fi
        "$1" stop
    ' sh "$device_init"; then
        sh "$guard" firewall /bin/sh -c '
            if uci -q get firewall.dns_manager_device_dns >/dev/null 2>&1; then exit 1; fi
        ' && service_absent || { echo 'Device DNS stop failed' >&2; exit 1; }
    fi
    "$device_init" disable || { echo 'Device DNS autostart disable failed' >&2; exit 1; }
    if ! service_absent || "$device_init" enabled >/dev/null 2>&1; then
        echo 'Device DNS remains running or enabled' >&2; exit 1
    fi
else
    service_absent || { echo 'Device DNS service exists without an init script' >&2; exit 1; }
fi
rm -f "$assignments" "$default_assignments" "$nft_file" "$legacy_nft"
