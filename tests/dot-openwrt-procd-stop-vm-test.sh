#!/bin/sh
# Disposable VM only. Temporarily removes live proxy instances via procd.
set -e
[ "${DNS_MANAGER_DISPOSABLE_VM:-}" = yes ] || { echo 'Requires disposable VM' >&2; exit 1; }
[ -r /usr/share/libubox/jshn.sh ] || exit 1
. /usr/share/libubox/jshn.sh
t="$(mktemp -d)"
restore=0
cleanup() {
    if [ "$restore" = 1 ]; then
        ubus call service add "{\"name\":\"https-dns-proxy\",\"instances\":$(cat "$t/instances")}" >/dev/null 2>&1 || {
            echo "Proxy restore failed; instance snapshot retained in $t" >&2; return; }
    fi
    rm -rf "$t"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
snapshot="$(ubus call service list '{"name":"https-dns-proxy"}')"
printf '%s\n' "$snapshot" | jsonfilter -e '@["https-dns-proxy"].instances' > "$t/instances"
[ -s "$t/instances" ] || { echo 'No proxy instances' >&2; exit 1; }
json_load "$snapshot"
json_select https-dns-proxy
json_select instances
json_get_keys instances
[ -n "$instances" ] || exit 1
cp /etc/config/dhcp "$t/dhcp"
cp /etc/config/https-dns-proxy "$t/proxy"
restore=1
for instance in $instances; do
    # Official proxy instances have simple procd-generated names.
    case "$instance" in *[!A-Za-z0-9_-]*|'') exit 1;; esac
    ubus call service delete "{\"name\":\"https-dns-proxy\",\"instance\":\"$instance\"}" >/dev/null
done
cmp -s "$t/dhcp" /etc/config/dhcp || { echo 'DHCP changed on procd stop' >&2; exit 1; }
cmp -s "$t/proxy" /etc/config/https-dns-proxy || { echo 'Proxy config changed on procd stop' >&2; exit 1; }
ubus call service add "{\"name\":\"https-dns-proxy\",\"instances\":$(cat "$t/instances")}" >/dev/null
for instance in $instances; do
    running="$(ubus call service list '{"name":"https-dns-proxy"}' | jsonfilter -e "@[\"https-dns-proxy\"].instances[\"$instance\"].running")"
    [ "$running" = true ] || { echo "Proxy instance $instance failed to start" >&2; exit 1; }
done
cmp -s "$t/dhcp" /etc/config/dhcp || { echo 'DHCP changed on procd restore' >&2; exit 1; }
cmp -s "$t/proxy" /etc/config/https-dns-proxy || { echo 'Proxy config changed on procd restore' >&2; exit 1; }
restore=0
echo 'OK: procd stop and restore did not commit DHCP or proxy configuration in this VM'

