#!/bin/sh
# Disposable OpenWrt userspace only. This replaces /etc/config/dhcp and the
# package dnscrypt-proxy config. Requires Internet and isolated loopback ports.
set -eu
[ "${DNSCRYPT_DISPOSABLE_LAB:-0}" = 1 ] || { echo 'Run only in a disposable OpenWrt lab' >&2; exit 2; }
mkdir -p /var/run /var/lock /etc/rc.d /tmp/.uci /tmp/resolv.conf.d /etc/dnscrypt-proxy2
if [ "${1:-}" = after-restart ]; then
    /sbin/ubusd >/tmp/ubus2.log 2>&1 & sleep 1
    /sbin/procd -S >/tmp/procd2.log 2>&1 & /sbin/rpcd >/tmp/rpcd2.log 2>&1 & sleep 2
    /etc/init.d/dnscrypt-proxy enabled
    /etc/init.d/dnsmasq enabled
    /etc/init.d/dnscrypt-proxy boot
    /etc/init.d/dnsmasq boot
    [ "$(uci -q get dhcp.main.server)" = '127.0.0.1#25663' ]
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if nslookup -type=A -port=25664 example.com 127.0.0.1 >/tmp/query-after 2>&1 && grep -q 'Name:' /tmp/query-after; then
            echo 'PASS: saved config after restarting isolated OpenWrt services'
            exit 0
        fi
        sleep 1
    done
    cat /tmp/query-after; exit 1
fi
cat > /etc/config/dhcp <<'UCI'
config dnsmasq 'main'
  option port '25664'
  list listen_address '127.0.0.1'
  option localservice '0'
UCI
# WSL cannot start OpenWrt's nested ujail. This affects the lab only.
sed -i '/^[[:space:]]*procd_add_jail/d' /etc/init.d/dnsmasq
/sbin/ubusd >/tmp/ubus.log 2>&1 & sleep 1
/sbin/procd -S >/tmp/procd.log 2>&1 & /sbin/rpcd >/tmp/rpcd.log 2>&1 & sleep 2
/etc/init.d/dnsmasq start
sleep 1
TMP_DIR=/tmp
export TMP_DIR
DNS_MANAGER_DNSCRYPT_POOL_APPLY=/tmp/dnscrypt/dns-manager-dnscrypt-pool-apply.sh
DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY=/tmp/dnscrypt/dns-manager-dnscrypt-dnsmasq.sh
DNS_MANAGER_DNSCRYPT_UCI_GUARD=/tmp/dnscrypt/dns-manager-uci-read-guard.sh
export DNS_MANAGER_DNSCRYPT_POOL_APPLY DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY DNS_MANAGER_DNSCRYPT_UCI_GUARD
. /tmp/dnscrypt/dns-manager-dnscrypt-profile-apply.sh
# Control the selection for this integration test; the selector has separate
# tests. The pool, proxy, dnsmasq, UCI, rpcd and procd are real.
dnscrypt_select_profile() { printf 'cloudflare|https://cloudflare-dns.com/dns-query\ngoogle|https://dns.google/dns-query\n'; }
dnscrypt_apply_profile_pool clean 25663 "${DNSCRYPT_BOOTSTRAP:?}" > /tmp/applied
grep -q '^cloudflare|' /tmp/applied
[ "$(uci -q get dhcp.main.noresolv)" = 1 ]
[ "$(uci -q get dhcp.main.cachesize)" = 0 ]
[ "$(uci -q get dhcp.main.server)" = '127.0.0.1#25663' ]
nslookup -type=A -port=25664 example.com 127.0.0.1 > /tmp/query
grep -q 'Name:' /tmp/query
/etc/init.d/dnscrypt-proxy running
/etc/init.d/dnscrypt-proxy enable
/etc/init.d/dnsmasq enable
echo 'PASS: selected DoH pool -> dnscrypt-proxy2 -> OpenWrt dnsmasq'
