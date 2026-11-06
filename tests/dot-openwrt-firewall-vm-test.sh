#!/bin/sh
# Destructive integration test for a disposable OpenWrt VM only.
# It stops/restarts https-dns-proxy and reloads firewall; never run on a router.
set -eu
[ "${DNS_MANAGER_DISPOSABLE_VM:-}" = yes ] || { echo 'Requires DNS_MANAGER_DISPOSABLE_VM=yes on a disposable VM' >&2; exit 1; }
guard=dns-manager-dot-fw-test
for cmd in ubus nft; do command -v "$cmd" >/dev/null 2>&1 || exit 1; done
[ -x /etc/init.d/https-dns-proxy ] && [ -x /etc/init.d/firewall ] || exit 1
ubus call service list "{\"name\":\"$guard\"}" | grep -Fq '"guard"' && { echo 'Test guard already exists' >&2; exit 1; }
/etc/init.d/https-dns-proxy running >/dev/null 2>&1 || { echo 'Proxy is not running; refusing to change its original state' >&2; exit 1; }
cleanup() {
    ubus call service delete "{\"name\":\"$guard\"}" >/dev/null 2>&1 || true
    /etc/init.d/https-dns-proxy start >/dev/null 2>&1 || true
    /etc/init.d/firewall reload >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
# Known LAN-only fixture: the real switch must derive and validate actual rules.
ubus call service add '{"name":"dns-manager-dot-fw-test","instances":{"guard":{"command":["/bin/sleep","9999"],"data":{"firewall":[{"type":"redirect","target":"DNAT","src":"lan","proto":"tcp udp","src_dport":"53","dest_port":"53","family":"any","reflection":false},{"type":"rule","src":"lan","dest":"*","proto":"tcp udp","dest_port":"853","target":"REJECT"}]}}}}' >/dev/null
/etc/init.d/https-dns-proxy stop >/dev/null
/etc/init.d/firewall reload >/dev/null
rules="$(nft list ruleset | grep -F 'dns-manager-dot-fw-test')" || { echo 'Test guard rules were not installed' >&2; exit 1; }
printf '%s\n' "$rules" | grep -Eq 'tcp dport 853.*(reject|handle_reject)' || { echo 'Missing TCP/853 block' >&2; exit 1; }
printf '%s\n' "$rules" | grep -Eq 'udp dport 853.*(reject|handle_reject)' || { echo 'Missing UDP/853 block' >&2; exit 1; }
printf '%s\n' "$rules" | grep -Eq 'tcp dport 53.*redirect to :53' || { echo 'Missing TCP DNS redirect' >&2; exit 1; }
printf '%s\n' "$rules" | grep -Eq 'udp dport 53.*redirect to :53' || { echo 'Missing UDP DNS redirect' >&2; exit 1; }
echo 'OK: VM fixture keeps DNS interception and DoT rejection after firewall reload'

