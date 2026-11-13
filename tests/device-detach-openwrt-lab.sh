#!/bin/sh
# Disposable OpenWrt only; replaces firewall configuration and test services.
set -eu
[ "${DNSCRYPT_DISPOSABLE_LAB:-0}" = 1 ] || { echo 'Disposable lab required' >&2; exit 2; }
mkdir -p /var/run /var/lock /etc/rc.d /tmp/.uci /tmp/device-detach
cat > /etc/config/firewall <<'UCI'
config include 'dns_manager_device_dns'
 option type 'nftables'
 option path '/tmp/device-detach/redirects.nft'
 option position 'chain-pre'
 option chain 'dstnat_lan'
config include 'steer_keep'
 option path '/etc/steer/firewall.nft'
UCI
cat > /tmp/firewall-test <<'FIREWALL'
#!/bin/sh
echo reload >> /tmp/device-detach/order
[ ! -e /tmp/device-detach/fail-reload ]
FIREWALL
cat > /etc/init.d/dns-manager-device-dns <<'INIT'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service() { procd_open_instance main; procd_set_param command /bin/sleep 1000; procd_close_instance; }
stop_service() { echo stop >> /tmp/device-detach/order; }
INIT
chmod 755 /tmp/firewall-test /etc/init.d/dns-manager-device-dns
/sbin/ubusd >/tmp/ubus.log 2>&1 & sleep 1
/sbin/procd -S >/tmp/procd.log 2>&1 & /sbin/rpcd >/tmp/rpcd.log 2>&1 & sleep 2
/etc/init.d/dns-manager-device-dns enable
/etc/init.d/dns-manager-device-dns start
touch /tmp/device-detach/assignments /tmp/device-detach/default /tmp/device-detach/redirects.nft
DNS_MANAGER_UCI_GUARD=/tmp/dns-manager-uci-read-guard.sh
DNS_MANAGER_FIREWALL_INIT=/tmp/firewall-test
DNS_MANAGER_DEVICE_ASSIGNMENTS=/tmp/device-detach/assignments
DNS_MANAGER_DEVICE_DEFAULT_ASSIGNMENTS=/tmp/device-detach/default
DNS_MANAGER_DEVICE_NFT=/tmp/device-detach/redirects.nft
DNS_MANAGER_DEVICE_LEGACY_NFT=/tmp/device-detach/legacy.nft
export DNS_MANAGER_UCI_GUARD DNS_MANAGER_FIREWALL_INIT DNS_MANAGER_DEVICE_ASSIGNMENTS DNS_MANAGER_DEVICE_DEFAULT_ASSIGNMENTS DNS_MANAGER_DEVICE_NFT DNS_MANAGER_DEVICE_LEGACY_NFT
uci set firewall.steer_keep.pending=foreign
if sh /tmp/dns-manager-device-detach.sh; then echo 'ERROR: accepted pending firewall change' >&2; exit 1; fi
[ "$(uci -q get firewall.steer_keep.pending)" = foreign ]
/etc/init.d/dns-manager-device-dns running
uci revert firewall
uci set firewall.dns_manager_device_dns.path=/tmp/device-detach/foreign.nft
uci commit firewall
if sh /tmp/dns-manager-device-detach.sh; then echo 'ERROR: removed foreign firewall include' >&2; exit 1; fi
[ "$(uci -q get firewall.dns_manager_device_dns.path)" = /tmp/device-detach/foreign.nft ]
/etc/init.d/dns-manager-device-dns running
uci set firewall.dns_manager_device_dns.path=/tmp/device-detach/redirects.nft
uci commit firewall
touch /tmp/device-detach/fail-reload
if sh /tmp/dns-manager-device-detach.sh; then echo 'ERROR: accepted firewall reload failure' >&2; exit 1; fi
/etc/init.d/dns-manager-device-dns running
[ -e /tmp/device-detach/assignments ]
[ "$(uci -q get firewall.steer_keep.path)" = /etc/steer/firewall.nft ]
rm -f /tmp/device-detach/fail-reload /tmp/device-detach/order
sh /tmp/dns-manager-device-detach.sh
if /etc/init.d/dns-manager-device-dns running || /etc/init.d/dns-manager-device-dns enabled; then echo 'ERROR: device service still active' >&2; exit 1; fi
[ ! -e /tmp/device-detach/assignments ] && [ ! -e /tmp/device-detach/default ]
[ "$(uci -q get firewall.steer_keep.path)" = /etc/steer/firewall.nft ]
[ "$(head -n1 /tmp/device-detach/order)" = reload ]
echo 'PASS: device bindings detach without committing pending or removing Steer config'
