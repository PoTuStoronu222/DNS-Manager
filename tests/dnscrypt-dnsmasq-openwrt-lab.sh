#!/bin/sh
# Disposable OpenWrt userspace only. This test replaces /etc/config/dhcp.
set -eu
[ "${DNSCRYPT_DISPOSABLE_LAB:-0}" = 1 ] || { echo 'Run only in a disposable OpenWrt lab' >&2; exit 2; }
mkdir -p /var/run /var/lock /etc/rc.d /tmp/.uci
cat > /etc/config/dhcp <<'UCI'
config dnsmasq 'main'
  list server '/ru/77.88.8.8'
  list server '1.1.1.1'
  option cachesize '500'
  option local '/lan/'
UCI
cat > /etc/init.d/dnsmasq <<'INIT'
#!/bin/sh /etc/rc.common
START=19
USE_PROCD=1
start_service() { procd_open_instance main; procd_set_param command /bin/sleep 1000; procd_close_instance; }
INIT
chmod +x /etc/init.d/dnsmasq
/sbin/ubusd >/tmp/ubus.log 2>&1 & sleep 1
/sbin/procd -S >/tmp/procd.log 2>&1 & /sbin/rpcd >/tmp/rpcd.log 2>&1 & sleep 2
/etc/init.d/dnsmasq start
uci set dhcp.main.local=/pending/
if sh /tmp/dns-manager-dnscrypt-dnsmasq.sh 5053 /tmp/dns-manager-uci-read-guard.sh /bin/true; then
    echo 'ERROR: pending change accepted' >&2; exit 1
fi
[ "$(uci -q get dhcp.main.local)" = /pending/ ]
uci revert dhcp
sh /tmp/dns-manager-dnscrypt-dnsmasq.sh 5053 /tmp/dns-manager-uci-read-guard.sh /bin/true
[ "$(uci -q get dhcp.main.noresolv)" = 1 ]
[ "$(uci -q get dhcp.main.cachesize)" = 0 ]
[ "$(uci -q get dhcp.main.server)" = '/ru/77.88.8.8 127.0.0.1#5053' ]
[ "$(uci -q get dhcp.main.local)" = /lan/ ]
echo 'PASS: isolated UCI apply preserves regional route and rejects pending changes'
cat > /tmp/fail-once <<'FAIL'
#!/bin/sh
[ -e /tmp/failed ] && exit 0
touch /tmp/failed
exit 1
FAIL
chmod +x /tmp/fail-once
if sh /tmp/dns-manager-dnscrypt-dnsmasq.sh 5053 /tmp/dns-manager-uci-read-guard.sh /tmp/fail-once; then
    echo 'ERROR: failed restart accepted' >&2; exit 1
fi
[ "$(uci -q get dhcp.main.noresolv)" = 0 ]
[ "$(uci -q get dhcp.main.cachesize)" = 1000 ]
[ "$(uci -q get dhcp.main.server)" = '/ru/77.88.8.8' ]
echo 'PASS: failed restart restores standard DNS and regional route'
uci -q delete dhcp.main.server
uci commit dhcp
sh /tmp/dns-manager-dnscrypt-dnsmasq.sh 5053 /tmp/dns-manager-uci-read-guard.sh /bin/true
[ "$(uci -q get dhcp.main.server)" = '127.0.0.1#5053' ]
rm -f /tmp/failed
if sh /tmp/dns-manager-dnscrypt-dnsmasq.sh 5053 /tmp/dns-manager-uci-read-guard.sh /tmp/fail-once; then
    echo 'ERROR: failed restart accepted without domain routes' >&2; exit 1
fi
[ "$(uci -q get dhcp.main.noresolv)" = 0 ]
[ "$(uci -q get dhcp.main.cachesize)" = 1000 ]
[ -z "$(uci -q get dhcp.main.server || true)" ]
echo 'PASS: stock baseline without domain routes'
