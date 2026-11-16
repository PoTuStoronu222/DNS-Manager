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
    for option in noresolv localuse cachesize server; do
        uci -q delete "dhcp.@dnsmasq[0].$option" || :
    done
    uci commit dhcp
}

add_regional_servers() {
    [ "${DNS_MANAGER_IGNORE_REGIONAL:-0}" != 1 ] || return 0
    regional_mode=$(uci -q get dns-manager.global.dnscrypt_regional_mode || :)
    case "$regional_mode" in
        yandex) regional_ips='77.88.8.8 77.88.8.1' ;;
        isp) regional_ips=$(uci -q get dns-manager.global.dnscrypt_regional_ips || :)
             [ -n "$regional_ips" ] || return 1 ;;
        *) return 0 ;;
    esac
    for zone in ru su xn--p1ai by kz avito.st wbcontent.net wbstatic.net ozonusercontent.com ae-pic-a1.aliexpress-media.com yastatic.net; do
        for ip in $regional_ips; do
            uci add_list "dhcp.@dnsmasq[0].server=/$zone/$ip" || return 1
        done
    done
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
        add_regional_servers &&
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
