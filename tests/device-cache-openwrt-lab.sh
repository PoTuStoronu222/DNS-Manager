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
printf 'total=1000\nttl=0\n' > /etc/dns-manager/config/cache.conf
printf 'aa:bb:cc:dd:ee:01|1\n' > /etc/dns-manager/config/device-dns.conf
/usr/sbin/dnsmasq -k --no-resolv --port=5053 --listen-address=127.0.0.1 --pid-file=/tmp/lab-proxy1.pid &
p1=$!
/usr/sbin/dnsmasq -k --no-resolv --port=5054 --listen-address=127.0.0.1 --pid-file=/tmp/lab-proxy2.pid &
p2=$!
trap 'kill "$p1" "$p2" 2>/dev/null || true' EXIT
sleep 1
/etc/init.d/dns-manager-device-dns start
sleep 1
[ "$(uci -q get dhcp.main.cachesize)" = 500 ]
grep -qx 'cache-size=500' /etc/dns-manager/device-dns/profiles/profile_1.conf
[ "$(ubus call service list '{"name":"dns-manager-device-dns"}' | jsonfilter -e '@.*.instances.profile_1.running')" = true ]
printf 'aa:bb:cc:dd:ee:02|1,2\n' >> /etc/dns-manager/config/device-dns.conf
/etc/init.d/dns-manager-device-dns restart
sleep 1
[ "$(uci -q get dhcp.main.cachesize)" = 334 ]
grep -qx 'cache-size=333' /etc/dns-manager/device-dns/profiles/profile_1.conf
grep -qx 'cache-size=333' /etc/dns-manager/device-dns/profiles/profile_3.conf
printf 'total=1000\nttl=60\n' > /etc/dns-manager/config/cache.conf
/etc/init.d/dns-manager-device-dns restart
grep -qx 'min-cache-ttl=60' /etc/dns-manager/device-dns/profiles/profile_3.conf
[ "$(uci -q get dhcp.main.min_cache_ttl)" = 60 ]
printf 'aa:bb:cc:dd:ee:01|1\n' > /etc/dns-manager/config/device-dns.conf
/etc/init.d/dns-manager-device-dns restart
[ "$(uci -q get dhcp.main.cachesize)" = 500 ]
grep -qx 'cache-size=500' /etc/dns-manager/device-dns/profiles/profile_1.conf
reply="$(printf '{"total":1200,"ttl":10}' | DNSMGR_ACTION_WORKER=1 sh /usr/lib/dns-manager-luci/backend.sh call set_cache)"
[ "$(printf '%s' "$reply" | jsonfilter -e '@.ok')" = true ] || { echo "RPC failed: $reply" >&2; exit 1; }
[ "$(uci -q get dhcp.main.cachesize)" = 600 ]
grep -qx 'cache-size=600' /etc/dns-manager/device-dns/profiles/profile_1.conf
grep -qx 'min-cache-ttl=10' /etc/dns-manager/device-dns/profiles/profile_1.conf
uci set dhcp.main.local=/uncommitted/
reply="$(printf '{"total":1400,"ttl":20}' | DNSMGR_ACTION_WORKER=1 sh /usr/lib/dns-manager-luci/backend.sh call set_cache)"
[ "$(printf '%s' "$reply" | jsonfilter -e '@.ok')" = false ] || { echo "RPC accepted pending UCI: $reply" >&2; exit 1; }
grep -qx 'total=1200' /etc/dns-manager/config/cache.conf
grep -qx 'ttl=10' /etc/dns-manager/config/cache.conf
[ "$(uci -q get dhcp.main.local)" = /uncommitted/ ]
[ "$(uci -q get dhcp.main.cachesize)" = 600 ]
uci -q revert dhcp
/etc/init.d/dns-manager-device-dns restart
grep -qx 'cache-size=600' /etc/dns-manager/device-dns/profiles/profile_1.conf
reply="$(printf '{"total":1600,"ttl":15}' | sh /usr/lib/dns-manager-luci/backend.sh call set_cache)"
[ "$(printf '%s' "$reply" | jsonfilter -e '@.job')" = action ] || { echo "RPC job failed: $reply" >&2; exit 1; }
i=0
while [ "$i" -lt 30 ]; do
    job="$(printf '{"id":"action"}' | sh /usr/lib/dns-manager-luci/backend.sh call job)"
    status="$(printf '%s' "$job" | jsonfilter -e '@.status')"
    [ "$status" = running ] || break
    sleep 1; i=$((i+1))
done
[ "$status" = done ] || { echo "RPC job did not finish: $job" >&2; exit 1; }
[ "$(printf '%s' "$job" | jsonfilter -e '@.result')" = ok ]
[ "$(uci -q get dhcp.main.cachesize)" = 800 ]
grep -qx 'cache-size=800' /etc/dns-manager/device-dns/profiles/profile_1.conf
status="$(sh /usr/lib/dns-manager-luci/backend.sh call network_status)"
[ "$(printf '%s' "$status" | jsonfilter -e '@.cache_total')" = 1600 ]
[ "$(printf '%s' "$status" | jsonfilter -e '@.cache_ttl')" = 15 ]
uci set 'firewall.@defaults[0].input=ACCEPT'
reply="$(printf '{"total":2000,"ttl":25}' | DNSMGR_ACTION_WORKER=1 sh /usr/lib/dns-manager-luci/backend.sh call set_cache)"
[ "$(printf '%s' "$reply" | jsonfilter -e '@.ok')" = false ] || { echo 'RPC accepted pending firewall change' >&2; exit 1; }
[ "$(uci -q get 'firewall.@defaults[0].input')" = ACCEPT ]
grep -qx 'total=1600' /etc/dns-manager/config/cache.conf
[ "$(ubus call service list '{"name":"dns-manager-device-dns"}' | jsonfilter -e '@.*.instances.profile_1.running')" = true ]
uci -q revert firewall
: > /etc/dns-manager/config/device-dns.conf
/etc/init.d/dns-manager-device-dns restart
[ "$(uci -q get dhcp.main.cachesize)" = 1600 ]
if [ -f /etc/dns-manager/device-dns/profiles/profile_1.conf ]; then echo 'A removed binding left a profile' >&2; exit 1; fi
echo 'OK: active device cache groups reallocate, TTL applies, restart restores allocations'
