#!/bin/sh
# Disposable isolated OpenWrt userspace and network namespace only.
set -eu
[ "${DNSCRYPT_DISPOSABLE_LAB:-0}" = 1 ] || { echo 'Run only in a disposable OpenWrt lab' >&2; exit 2; }
mkdir -p /var/run /var/lock /etc/rc.d /tmp/.uci /tmp/resolv.conf.d
cat > /etc/config/dhcp <<'UCI'
config dnsmasq 'main'
  option port '25664'
  list listen_address '127.0.0.1'
  option localservice '0'
UCI
/sbin/ubusd >/tmp/ubus.log 2>&1 & sleep 1
/sbin/procd -S >/tmp/procd.log 2>&1 & /sbin/rpcd >/tmp/rpcd.log 2>&1 & sleep 2
# The disposable WSL namespace cannot start OpenWrt's nested ujail. Use the
# package init unchanged except for its jail declarations in this lab only.
sed -i '/^[[:space:]]*procd_add_jail/d' /etc/init.d/dnsmasq
# A local authoritative answer lets the test verify forwarding without Internet.
/usr/sbin/dnsmasq --no-daemon --no-resolv --no-hosts --port=25663 \
    --listen-address=127.0.0.1 --bind-interfaces --pid-file= \
    --address=/dns-manager-test.example.com/8.8.4.4 >/tmp/upstream.log 2>&1 &
upstream=$!
trap 'kill "$upstream" 2>/dev/null || true' EXIT
sleep 1
if ! nslookup -type=A -port=25663 dns-manager-test.example.com 127.0.0.1 > /tmp/upstream-answer 2>&1; then
    cat /tmp/upstream-answer /tmp/upstream.log; exit 1
fi
/etc/init.d/dnsmasq start
sleep 1
if ! sh /tmp/dns-manager-dnscrypt-dnsmasq.sh 25663 /tmp/dns-manager-uci-read-guard.sh /etc/init.d/dnsmasq restart; then
    ubus call service list '{"name":"dnsmasq"}' || true
    cat /tmp/procd.log /tmp/upstream.log 2>/dev/null || true
    cat /var/etc/dnsmasq.conf.main 2>/dev/null || true
    /usr/sbin/dnsmasq --test -C /var/etc/dnsmasq.conf.main 2>&1 || true
    /usr/sbin/dnsmasq -d -C /var/etc/dnsmasq.conf.main > /tmp/direct.log 2>&1 & direct=$!
    sleep 2
    kill "$direct" 2>/dev/null || true
    cat /tmp/direct.log 2>/dev/null || true
    exit 1
fi
if ! nslookup -type=A -port=25664 dns-manager-test.example.com 127.0.0.1 > /tmp/answer 2>&1 || ! grep -q '8.8.4.4' /tmp/answer; then
    cat /tmp/answer /tmp/upstream-answer /tmp/upstream.log 2>/dev/null || true
    cat /var/etc/dnsmasq.conf.main 2>/dev/null || true
    exit 1
fi
echo 'PASS: actual OpenWrt dnsmasq forwards to the configured local listener'
