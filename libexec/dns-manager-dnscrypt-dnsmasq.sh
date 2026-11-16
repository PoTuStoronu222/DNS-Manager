#!/bin/sh
# Configure the main dnsmasq instance for DNSCrypt or restore OpenWrt defaults.
set -e
mode=encrypted
case "${1:-}" in restore|clean) mode=stock; shift ;; esac
[ "$#" -eq 1 ] || exit 2
port=$1
case "$port" in ''|*[!0-9]*) exit 2;; esac
[ "$port" -gt 0 ] && [ "$port" -le 65535 ] || exit 2

restore_dns() {
    uci -q delete 'dhcp.@dnsmasq[0].noresolv' || :
    uci -q delete 'dhcp.@dnsmasq[0].localuse' || :
    uci -q delete 'dhcp.@dnsmasq[0].cachesize' || :
    uci -q delete 'dhcp.@dnsmasq[0].server' || :
    uci commit dhcp
}

service dnsmasq stop
trap 'restore_dns || :; service dnsmasq start || :; exit 1' HUP INT TERM
if [ "$mode" = encrypted ]; then
    if ! {
        uci set 'dhcp.@dnsmasq[0].noresolv=1' &&
        uci set 'dhcp.@dnsmasq[0].localuse=1' &&
        uci set 'dhcp.@dnsmasq[0].cachesize=0' &&
        { uci -q delete 'dhcp.@dnsmasq[0].server' || :; } &&
        uci add_list "dhcp.@dnsmasq[0].server=127.0.0.1#$port" &&
        uci commit dhcp && service dnsmasq start
    }; then
        restore_dns || :
        service dnsmasq start || :
        exit 1
    fi
else
    if ! restore_dns; then
        service dnsmasq start || :
        exit 1
    fi
    service dnsmasq start
fi
trap - HUP INT TERM
