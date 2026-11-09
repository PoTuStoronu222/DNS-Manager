#!/bin/sh
# Isolated rpcd UCI session for DNS Manager's single named firewall include.
set -eu
operation=${1:-}
path=/etc/dns-manager/device-dns/redirects.nft
name=dns_manager_device_dns
case "$operation" in ensure|remove) ;; *) exit 2 ;; esac
sid=''
cleanup() { [ -z "$sid" ] || ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null 2>&1 || true; }
trap cleanup EXIT HUP INT TERM
sid="$(ubus call session create '{"timeout":60}' | jsonfilter -e '@.ubus_rpc_session')"
case "$sid" in ''|*[!a-f0-9]*) exit 1;; esac
[ "${#sid}" -eq 32 ] || exit 1
ubus call session grant "{\"ubus_rpc_session\":\"$sid\",\"scope\":\"uci\",\"objects\":[[\"firewall\",\"read\"],[\"firewall\",\"write\"]]}" >/dev/null
req="{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\",\"section\":\"$name\"}"
rc=0
existing="$(ubus call uci get "$req" 2>/dev/null)" || rc=$?
[ "$rc" = 0 ] || [ "$rc" = 4 ] || exit 1
if [ -n "$existing" ]; then
    printf '%s' "$existing" | grep -Eq '"\.type"[[:space:]]*:[[:space:]]*"include"' || exit 1
    [ "$(printf '%s' "$existing" | jsonfilter -e '@.values.type')" = nftables ] || exit 1
    [ "$(printf '%s' "$existing" | jsonfilter -e '@.values.path')" = "$path" ] || exit 1
    [ "$(printf '%s' "$existing" | jsonfilter -e '@.values.position')" = chain-pre ] || exit 1
    [ "$(printf '%s' "$existing" | jsonfilter -e '@.values.chain')" = dstnat_lan ] || exit 1
    if [ "$operation" = remove ]; then
        ubus call uci delete "$req" >/dev/null
        ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\"}" >/dev/null
    elif [ "$(printf '%s' "$existing" | jsonfilter -e '@.values.enabled')" != 1 ]; then
        ubus call uci set "{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\",\"section\":\"$name\",\"values\":{\"enabled\":\"1\"}}" >/dev/null
        ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\"}" >/dev/null
    fi
elif [ "$operation" = ensure ]; then
    ubus call uci add "{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\",\"type\":\"include\",\"name\":\"$name\",\"values\":{\"enabled\":\"1\",\"type\":\"nftables\",\"path\":\"$path\",\"position\":\"chain-pre\",\"chain\":\"dstnat_lan\"}}" >/dev/null
    ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\"}" >/dev/null
fi
