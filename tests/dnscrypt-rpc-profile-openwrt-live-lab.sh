#!/bin/sh
# Disposable OpenWrt userspace only. Requires Internet and isolated ports.
set -eu
[ "${DNSCRYPT_DISPOSABLE_LAB:-0}" = 1 ] || { echo 'Run only in a disposable OpenWrt lab' >&2; exit 2; }
: "${DNSCRYPT_BOOTSTRAP:?Set DNSCRYPT_BOOTSTRAP to a reachable resolver}"
mkdir -p /var/run /var/lock /etc/rc.d /tmp/.uci /tmp/resolv.conf.d \
    /etc/dns-manager/config /etc/dnscrypt-proxy2 /usr/lib/dns-manager-luci/cache /usr/lib/dns-manager-luci/dnscrypt
if [ "${1:-}" != after-restart ]; then
    # Device/firewall detachment is covered separately by device-detach-openwrt-lab.sh.
    printf '#!/bin/sh\nexit 0\n' > /usr/lib/dns-manager-luci/dnscrypt/dns-manager-device-detach.sh
fi
if [ "${1:-}" = after-restart ]; then
    printf 'nameserver %s\n' "$DNSCRYPT_BOOTSTRAP" > /tmp/resolv.conf.d/resolv.conf.auto
    /sbin/ubusd >/tmp/ubus2.log 2>&1 & sleep 1
    /sbin/procd -S >/tmp/procd2.log 2>&1 & /sbin/rpcd >/tmp/rpcd2.log 2>&1 & sleep 2
    /etc/init.d/dnscrypt-proxy enabled
    /etc/init.d/dnsmasq enabled
    /etc/init.d/dnscrypt-proxy boot
    /etc/init.d/dnsmasq boot
    ready=0
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if nslookup -type=A -port=25664 example.com 127.0.0.1 >/tmp/query-after 2>&1 && grep -q 'Name:' /tmp/query-after; then
            status=$(/usr/lib/dns-manager-luci/backend-dnscrypt.sh call doh_status)
            [ "$(printf '%s' "$status" | jsonfilter -e '@.dnscrypt_profile')" = clean ]
            echo 'PASS: saved DNSCrypt profile and DNS after isolated service restart'
            ready=1
            break
        fi
        sleep 1
    done
    [ "$ready" = 1 ] || { cat /tmp/query-after; exit 1; }
    backend=/usr/lib/dns-manager-luci/backend-dnscrypt.sh
    reply=$(printf '{}' | "$backend" call reset_dns)
    [ "$(printf '%s' "$reply" | jsonfilter -e '@.job')" = action ]
    for reset_attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        reset_status=$(sed -n 's/^status=//p' /var/run/dns-manager-luci/jobs/action/state | tail -n1)
        [ "$reset_status" != running ] && break
        sleep 1
    done
    [ "$reset_status" = done ] || { cat /var/run/dns-manager-luci/jobs/action/output /var/run/dns-manager-luci/dnscrypt-reset.log; exit 1; }
    [ "$(uci -q get dhcp.main.noresolv)" = 0 ]
    [ -z "$(uci -q get dhcp.main.server || true)" ]
    [ ! -e /etc/dns-manager/config/dnscrypt-profile.state ]
    if /etc/init.d/dnscrypt-proxy enabled; then echo 'ERROR: DNSCrypt still enabled'; exit 1; fi
    nslookup -type=A -port=25664 example.com 127.0.0.1 > /tmp/query-stock
    grep -q 'Name:' /tmp/query-stock
    echo 'PASS: RPC reset restores provider DNS and disables DNSCrypt'
    exit 0
fi
printf '%s\n' dnscrypt-proxy2 > /etc/dns-manager/config/dnscrypt-engine
cat > /etc/config/dhcp <<'UCI'
config dnsmasq 'main'
  option port '25664'
  list listen_address '127.0.0.1'
  option localservice '0'
UCI
cat > /usr/bin/dns-manager <<'MANAGER'
#!/bin/sh
TMP_DIR=/tmp
preflight_readonly() { :; }
init_dirs() { :; }
load_config() { BOOTSTRAP_DNS="$DNSCRYPT_BOOTSTRAP"; }
watchdog_service_stop_disable() { :; }
watchdog_cron_remove_owned_block() { :; }
acquire_mutation_lock() { :; }
release_mutation_lock() { :; }
restore_persistent_test_results() { :; }
refresh_runtime_capabilities() { :; }
profile_apply_begin() { :; }
profile_apply_end() { :; }
auto_fill_slots() { SLOT_1=cloudflare; SLOT_2=google; }
dns_url() { case "$1" in cloudflare) printf 'https://cloudflare-dns.com/dns-query';; google) printf 'https://dns.google/dns-query';; *) return 1;; esac; }
normalize_url() { printf '%s' "$1"; }
case "${1:-}" in
    *) exit 1;;
esac
MANAGER
chmod +x /usr/bin/dns-manager
cat > /usr/lib/dns-manager-luci/backend.sh <<'LEGACY'
#!/bin/sh
case "$1:$2" in
  list:) printf '{"status":{},"doh_status":{},"set_profile":{}}\n';;
  call:status|call:doh_status) printf '{"ok":true}\n';;
  *) printf '{"ok":true}\n';;
esac
LEGACY
chmod +x /usr/lib/dns-manager-luci/backend.sh
# Disable nested ujail only in this disposable WSL laboratory.
sed -i '/^[[:space:]]*procd_add_jail/d' /etc/init.d/dnsmasq
/sbin/ubusd >/tmp/ubus.log 2>&1 & sleep 1
/sbin/procd -S >/tmp/procd.log 2>&1 & /sbin/rpcd >/tmp/rpcd.log 2>&1 & sleep 2
/etc/init.d/dnsmasq start
sleep 1
backend=/usr/lib/dns-manager-luci/backend-dnscrypt.sh
reply=$(printf '{"profile":"clean"}' | "$backend" call set_profile)
[ "$(printf '%s' "$reply" | jsonfilter -e '@.job')" = profile ]
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
    status=$(sed -n 's/^status=//p' /var/run/dns-manager-luci/jobs/profile/state | tail -n1)
    [ "$status" != running ] && break
    sleep 1
done
[ "$status" = done ] || { cat /var/run/dns-manager-luci/jobs/profile/state /var/run/dns-manager-luci/jobs/profile/output; exit 1; }
[ "$(uci -q get dhcp.main.server)" = '127.0.0.1#5053' ]
[ "$(uci -q get dhcp.main.noresolv)" = 1 ]
/etc/init.d/dnscrypt-proxy enabled
/etc/init.d/dnsmasq enable
nslookup -type=A -port=25664 example.com 127.0.0.1 > /tmp/query
grep -q 'Name:' /tmp/query
status=$("$backend" call doh_status)
[ "$(printf '%s' "$status" | jsonfilter -e '@.dnscrypt_profile')" = clean ]
[ "$(printf '%s' "$status" | jsonfilter -e '@.dnscrypt_servers[0]')" = cloudflare ]
echo 'PASS: RPC procd job -> DNSCrypt pool -> actual OpenWrt dnsmasq'
