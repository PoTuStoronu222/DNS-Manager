#!/bin/sh
# Disposable OpenWrt lab only. This modifies the dhcp package.
set -eu
if [ "${1:-}" = during_restart ]; then
    uci set dhcp.main.local=/concurrent/ 8>&- 9>&- &
    writer=$!
    sleep 1
    kill -0 "$writer" || { echo 'ERROR: concurrent writer did not wait' >&2; exit 1; }
    /etc/init.d/dnsmasq restart
    exit
fi
uci set dhcp.main.local=/pending/
if sh /tmp/dns-manager-uci-read-guard.sh dhcp /etc/init.d/dnsmasq restart 2>/dev/null; then
    echo 'ERROR: restart accepted pending dhcp changes' >&2; exit 1
fi
[ "$(ubus call service list '{"name":"dnsmasq"}' | jsonfilter -e '@.dnsmasq.instances.main.running')" = true ]
uci -q revert dhcp
sh /tmp/dns-manager-uci-cache.sh main 700 120
sh /tmp/dns-manager-uci-read-guard.sh dhcp /etc/init.d/dnsmasq restart
sleep 1
grep -qx 'cache-size=700' /var/etc/dnsmasq.conf.main
grep -qx 'min-cache-ttl=120' /var/etc/dnsmasq.conf.main
[ "$(ubus call service list '{"name":"dnsmasq"}' | jsonfilter -e '@.dnsmasq.instances.main.running')" = true ]
# If descriptors leaked to the service, this operation would block forever.
uci set dhcp.main.local=/after-restart/ &
writer=$!
sleep 1
if kill -0 "$writer" 2>/dev/null; then kill "$writer" 2>/dev/null || true; echo 'ERROR: UCI lock leaked' >&2; exit 1; fi
wait "$writer"
[ "$(uci -q get dhcp.main.local)" = /after-restart/ ]
uci -q revert dhcp
sh /tmp/dns-manager-uci-read-guard.sh dhcp /bin/sh /tmp/dnsmasq-restart-guard-openwrt.sh during_restart
sleep 1
[ "$(uci -q get dhcp.main.local)" = /concurrent/ ]
if grep -q 'local=/concurrent/' /var/etc/dnsmasq.conf.main; then echo 'ERROR: concurrent change was applied' >&2; exit 1; fi
uci -q revert dhcp
echo 'OK: guarded restart rejects pending changes, applies cache and releases UCI locks'
