#!/bin/sh
# Disposable OpenWrt userspace only; firewall/nft are lab stubs.
set -eu
mkdir -p /etc/dns-manager/config /etc/dns-manager/device-dns
cat > /etc/dns-manager/config/manager.conf <<'EOF'
SLOT_1='one'
PORT_1='5053'
SLOT_2='two'
PORT_2='5054'
REGIONAL_MODE='doh'
EOF
rm -f /etc/dns-manager/config/cache.conf
printf 'aa:bb:cc:dd:ee:01|1\n' > /etc/dns-manager/config/device-dns.conf
/usr/sbin/dnsmasq -k --no-resolv --port=5053 --listen-address=127.0.0.1 --pid-file=/tmp/lab-proxy1.pid & p1=$!
trap 'kill "$p1" 2>/dev/null || true' EXIT
sleep 1
/etc/init.d/dns-manager-device-dns start
sleep 1
grep -qx 'cache-size=0' /etc/dns-manager/device-dns/profiles/profile_1.conf
service="$(ubus call service list '{"name":"dns-manager-device-dns"}')"
pid="$(printf '%s' "$service" | jsonfilter -e '@.*.instances.profile_1.pid')"
[ -n "$pid" ]
reply="$(printf '{"total":1200,"ttl":10}' | DNSMGR_ACTION_WORKER=1 sh /usr/lib/dns-manager-luci/backend.sh call set_cache)"
[ "$(printf '%s' "$reply" | jsonfilter -e '@.ok')" = true ] || { echo "RPC failed: $reply" >&2; exit 1; }
[ "$(uci -q get dhcp.main.cachesize)" = 1200 ]
[ "$(uci -q get dhcp.main.min_cache_ttl)" = 10 ]
. /tmp/cache-legacy-function.sh
DNSMASQ_PERF=1
apply_dnsmasq_perf
[ "$(uci -q get dhcp.main.cachesize)" = 1200 ]
[ "$(ubus call service list '{"name":"dns-manager-device-dns"}' | jsonfilter -e '@.*.instances.profile_1.pid')" = "$pid" ]
grep -qx 'cache-size=0' /etc/dns-manager/device-dns/profiles/profile_1.conf
if grep -q '^min-cache-ttl=' /etc/dns-manager/device-dns/profiles/profile_1.conf; then exit 1; fi
uci set dhcp.main.local=/uncommitted/
reply="$(printf '{"total":1400,"ttl":20}' | DNSMGR_ACTION_WORKER=1 sh /usr/lib/dns-manager-luci/backend.sh call set_cache)"
[ "$(printf '%s' "$reply" | jsonfilter -e '@.ok')" = false ]
[ "$(uci -q get dhcp.main.local)" = /uncommitted/ ]
[ "$(uci -q get dhcp.main.cachesize)" = 1200 ]
uci -q revert dhcp
uci set 'firewall.@defaults[0].input=ACCEPT'
reply="$(printf '{"total":1600,"ttl":15}' | DNSMGR_ACTION_WORKER=1 sh /usr/lib/dns-manager-luci/backend.sh call set_cache)"
[ "$(printf '%s' "$reply" | jsonfilter -e '@.ok')" = true ]
[ "$(uci -q get 'firewall.@defaults[0].input')" = ACCEPT ]
[ "$(ubus call service list '{"name":"dns-manager-device-dns"}' | jsonfilter -e '@.*.instances.profile_1.pid')" = "$pid" ]
uci -q revert firewall
status="$(sh /usr/lib/dns-manager-luci/backend.sh call network_status)"
[ "$(printf '%s' "$status" | jsonfilter -e '@.cache_total')" = 1600 ]
[ "$(printf '%s' "$status" | jsonfilter -e '@.cache_ttl')" = 15 ]
/etc/init.d/dns-manager-device-dns restart
grep -qx 'cache-size=0' /etc/dns-manager/device-dns/profiles/profile_1.conf
[ "$(uci -q get dhcp.main.cachesize)" = 1600 ]
. /tmp/cache-uninstall-function.sh
stock_uci_value_normalized() { printf 1000; }
DNSMASQ_PERF=0; NTP_PRESET_USER_SET=0; BLOCK_EXTERNAL_DNS=0
uci set dhcp.main.cachesize=2000
uci commit dhcp
uninstall_reset_manager_extras
[ "$(uci -q get dhcp.main.cachesize)" = 2000 ]
uci set dhcp.main.cachesize=1600
uci commit dhcp
uninstall_reset_manager_extras
[ "$(uci -q get dhcp.main.cachesize)" = 1000 ]
[ "$(uci -q get dhcp.main.min_cache_ttl)" = 0 ]
echo 'OK: main DNS cache changes without restarting bindings or touching firewall'
