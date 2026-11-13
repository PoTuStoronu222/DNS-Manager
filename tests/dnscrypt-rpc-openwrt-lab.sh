#!/bin/sh
# Disposable OpenWrt userspace only: replaces Manager and init files.
set -eu
[ "${DNSCRYPT_DISPOSABLE_LAB:-0}" = 1 ] || { echo 'Run only in a disposable OpenWrt lab' >&2; exit 2; }
mkdir -p /var/run /var/lock /etc/rc.d /etc/dns-manager/config /usr/lib/dns-manager-luci/dnscrypt
printf '%s\n' dnscrypt-proxy2 > /etc/dns-manager/config/dnscrypt-engine
cat > /usr/bin/dns-manager <<'MANAGER'
#!/bin/sh
preflight_readonly() { :; }
init_dirs() { :; }
load_config() { BOOTSTRAP_DNS=1.1.1.1; }
acquire_mutation_lock() { :; }
release_mutation_lock() { :; }
restore_persistent_test_results() { :; }
refresh_runtime_capabilities() { :; }
case "${1:-}" in
    *) exit 1;;
esac
MANAGER
chmod +x /usr/bin/dns-manager
cat > /usr/lib/dns-manager-luci/backend.sh <<'LEGACY'
#!/bin/sh
case "$1:$2" in
  list:) printf '{"status":{},"doh_status":{},"set_profile":{}}\n';;
  call:status|call:doh_status|call:network_status) printf '{"ok":true,"other":"preserved"}\n';;
  *) printf '{"ok":true}\n';;
esac
LEGACY
chmod +x /usr/lib/dns-manager-luci/backend.sh
cat > /etc/init.d/dnscrypt-proxy <<'SERVICE'
#!/bin/sh
case "$1" in running|enable) exit 0;; *) exit 1;; esac
SERVICE
chmod +x /etc/init.d/dnscrypt-proxy
cat > /usr/lib/dns-manager-luci/dnscrypt/dns-manager-dnscrypt-profile.sh <<'SELECT'
#!/bin/sh
SELECT
cat > /usr/lib/dns-manager-luci/dnscrypt/dns-manager-dnscrypt-profile-apply.sh <<'APPLY'
#!/bin/sh
dnscrypt_apply_profile_pool() { printf 'cloudflare|https://cloudflare-dns.com/dns-query\n'; }
APPLY
/sbin/ubusd >/tmp/ubus.log 2>&1 & sleep 1
/sbin/procd -S >/tmp/procd.log 2>&1 & sleep 2
backend=/usr/lib/dns-manager-luci/backend-dnscrypt.sh
status=$("$backend" call status)
[ "$(printf '%s' "$status" | jsonfilter -e '@.dnscrypt_engine')" = dnscrypt-proxy2 ]
[ "$(printf '%s' "$status" | jsonfilter -e '@.dnscrypt_running')" = 1 ]
[ "$(printf '%s' "$status" | jsonfilter -e '@.other')" = preserved ]
blocked=$(printf '{}' | "$backend" call set_slot)
[ "$(printf '%s' "$blocked" | jsonfilter -e '@.ok')" = false ]
reply=$(printf '{"profile":"clean"}' | "$backend" call set_profile)
[ "$(printf '%s' "$reply" | jsonfilter -e '@.job')" = profile ]
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    status=$(sed -n 's/^status=//p' /var/run/dns-manager-luci/jobs/profile/state | tail -n1)
    [ "$status" != running ] && break
    sleep 1
done
[ "$status" = done ] || { cat /var/run/dns-manager-luci/jobs/profile/output; exit 1; }
grep -qx 'profile=clean' /etc/dns-manager/config/dnscrypt-profile.state
status=$("$backend" call doh_status)
[ "$(printf '%s' "$status" | jsonfilter -e '@.dnscrypt_profile')" = clean ]
[ "$(printf '%s' "$status" | jsonfilter -e '@.dnscrypt_servers[0]')" = cloudflare ]
echo 'PASS: DNSCrypt RPC state, blocked slot action and procd profile job'
