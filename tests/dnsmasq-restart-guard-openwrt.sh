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
if [ "${1:-}" = rpc_during_restart ]; then
    sid="$(cat /tmp/dns-cache-test-sid)"
    ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\"}" 8>&- 9>&- &
    writer=$!
    sleep 1
    kill -0 "$writer" || { echo 'ERROR: concurrent RPC commit did not wait' >&2; exit 1; }
    /etc/init.d/dnsmasq restart
    exit
fi
if [ "${1:-}" = fail_once ]; then
    if [ ! -e /tmp/dns-cache-restart-failed ]; then touch /tmp/dns-cache-restart-failed; exit 1; fi
    exec /etc/init.d/dnsmasq restart
fi
if [ "${1:-}" = false_success_once ]; then
    if [ ! -e /tmp/dns-cache-false-success ]; then
        touch /tmp/dns-cache-false-success
        /etc/init.d/dnsmasq stop
        exit 0
    fi
    exec /etc/init.d/dnsmasq restart
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
sid="$(ubus call session create '{"timeout":60}' | jsonfilter -e '@.ubus_rpc_session')"
ubus call session grant "{\"ubus_rpc_session\":\"$sid\",\"scope\":\"uci\",\"objects\":[[\"dhcp\",\"read\"],[\"dhcp\",\"write\"]]}" >/dev/null
ubus call uci set "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\",\"section\":\"main\",\"values\":{\"local\":\"/rpc-concurrent/\"}}" >/dev/null
printf '%s' "$sid" > /tmp/dns-cache-test-sid
sh /tmp/dns-manager-uci-read-guard.sh dhcp /bin/sh /tmp/dnsmasq-restart-guard-openwrt.sh rpc_during_restart
sleep 1
[ "$(uci -q get dhcp.main.local)" = /rpc-concurrent/ ]
if grep -q 'local=/rpc-concurrent/' /var/etc/dnsmasq.conf.main; then echo 'ERROR: concurrent RPC commit was applied' >&2; exit 1; fi
ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null
tx=/tmp/dns-manager-cache-transaction.sh
guard=/tmp/dns-manager-uci-read-guard.sh
sh "$tx" main 900 180 "$guard" /etc/init.d/dnsmasq restart
[ "$(uci -q get dhcp.main.cachesize)" = 900 ]
[ "$(uci -q get dhcp.main.min_cache_ttl)" = 180 ]
grep -qx 'cache-size=900' /var/etc/dnsmasq.conf.main
rm -f /tmp/dns-cache-restart-failed
if sh "$tx" main 800 30 "$guard" /bin/sh /tmp/dnsmasq-restart-guard-openwrt.sh fail_once; then echo 'ERROR: failed restart was accepted' >&2; exit 1; fi
[ "$(uci -q get dhcp.main.cachesize)" = 900 ]
[ "$(uci -q get dhcp.main.min_cache_ttl)" = 180 ]
grep -qx 'cache-size=900' /var/etc/dnsmasq.conf.main
rm -f /tmp/dns-cache-false-success
if sh "$tx" '@dnsmasq[0]' 800 30 "$guard" /bin/sh /tmp/dnsmasq-restart-guard-openwrt.sh false_success_once; then echo 'ERROR: stopped dnsmasq was accepted as success' >&2; exit 1; fi
[ "$(uci -q get dhcp.main.cachesize)" = 900 ]
[ "$(ubus call service list '{"name":"dnsmasq"}' | jsonfilter -e '@.dnsmasq.instances.main.running')" = true ]
uci -q delete dhcp.main.min_cache_ttl
uci commit dhcp
rm -f /tmp/dns-cache-restart-failed
if sh "$tx" main 800 30 "$guard" /bin/sh /tmp/dnsmasq-restart-guard-openwrt.sh fail_once; then echo 'ERROR: failed restart was accepted' >&2; exit 1; fi
[ "$(uci -q get dhcp.main.cachesize)" = 900 ]
if uci -q get dhcp.main.min_cache_ttl >/dev/null; then echo 'ERROR: absent TTL was not restored' >&2; exit 1; fi
uci set dhcp.main.local=/pending-transaction/
if sh "$tx" main 800 30 "$guard" /etc/init.d/dnsmasq restart 2>/dev/null; then echo 'ERROR: transaction accepted pending UCI changes' >&2; exit 1; fi
[ "$(uci -q get dhcp.main.cachesize)" = 900 ]
[ "$(uci -q get dhcp.main.local)" = /pending-transaction/ ]
uci -q revert dhcp
echo 'OK: cache transaction restores previous options, including an absent TTL'
echo 'OK: guarded restart rejects pending changes, applies cache and releases UCI locks'
