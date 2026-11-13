#!/bin/sh
# Experimental service lifecycle helper; does not install packages or change DNS.
set -eu

initdir=${DNS_MANAGER_INIT_DIR:-/etc/init.d}
action=${1:-}
engine=${2:-}
case "$action:$engine" in
    quiesce:https-dns-proxy|quiesce:dnscrypt-proxy2|start:https-dns-proxy|start:dnscrypt-proxy2) ;;
    *) printf '%s\n' 'Expected quiesce|start and https-dns-proxy|dnscrypt-proxy2' >&2; exit 2 ;;
esac

service_absent() {
    # A failed procd delete can mean either "already absent" or a real ubus
    # failure. Only accept the former after a successful, valid service list.
    _service_reply=$(ubus -t 5 call service list "{\"name\":\"$1\"}" 2>/dev/null) || return 1
    _service_root=$(jsonfilter -s "$_service_reply" -e '@' 2>/dev/null) || return 1
    case "$_service_root" in \{*\}) ;; *) return 1 ;; esac
    if jsonfilter -s "$_service_reply" -e "@['$1']" >/dev/null 2>&1; then
        return 1
    else
        _service_filter_rc=$?
        [ "$_service_filter_rc" -eq 1 ]
    fi
}

stop_disable() {
    script="$initdir/$1"
    [ -x "$script" ] || return 0
    if ! "$script" stop && ! service_absent "$1"; then
        printf 'Failed to stop %s\n' "$1" >&2
        return 1
    fi
    "$script" disable || { printf 'Failed to disable %s\n' "$1" >&2; return 1; }
    if ! service_absent "$1"; then
        printf 'Service still registered or procd unavailable: %s\n' "$1" >&2
        return 1
    fi
    if "$script" enabled >/dev/null 2>&1; then
        printf 'Still enabled: %s\n' "$1" >&2
        return 1
    fi
}

if [ "$action" = quiesce ]; then
    # The package may auto-start its own service during installation.
    for service in https-dns-proxy dnscrypt-proxy dns-manager-dnscrypt; do
        stop_disable "$service" || exit 1
    done
    exit 0
fi

case "$engine" in
    https-dns-proxy) target=https-dns-proxy ;;
    dnscrypt-proxy2) target=dnscrypt-proxy ;;
esac

# Never knowingly start a second manager while another service is enabled or
# running. The caller must have restored DNS and performed quiesce first.
for service in https-dns-proxy dnscrypt-proxy dns-manager-dnscrypt; do
    [ "$service" = "$target" ] && continue
    script="$initdir/$service"
    [ -x "$script" ] || continue
    if "$script" enabled >/dev/null 2>&1 || ! service_absent "$service"; then
        printf 'Conflicting service is active or enabled: %s\n' "$service" >&2
        exit 1
    fi
done
script="$initdir/$target"
[ -x "$script" ] || { printf 'Missing service: %s\n' "$target" >&2; exit 1; }
# rc.common's procd start may not propagate start_service's failure. Validate
# the Manager-owned single-process configuration before enabling it at boot.
if [ "$engine" = https-dns-proxy ]; then
    # A fresh engine switch leaves dnsmasq on provider DNS until the user
    # selects a profile. Package defaults otherwise redirect DNS and may
    # compete with Steer as soon as the service starts.
    force=$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null) || force=''
    integration=$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null) || integration=''
    if [ "$force" != 0 ] || [ "$integration" != - ]; then
        printf 'HTTPS DNS Proxy integration must be disabled before start\n' >&2
        exit 1
    fi
fi
if [ "$engine" = dnscrypt-proxy2 ]; then
    binary=${DNS_MANAGER_DNSCRYPT_BIN:-/usr/sbin/dnscrypt-proxy}
    config=${DNS_MANAGER_DNSCRYPT_CONFIG:-/etc/dnscrypt-proxy2/dnscrypt-proxy.toml}
    [ -x "$binary" ] && [ -f "$config" ] && "$binary" -config "$config" -check >/dev/null 2>&1 || {
        printf 'Invalid dnscrypt-proxy2 configuration\n' >&2
        exit 1
    }
fi
"$script" enable || { printf 'Failed to enable %s\n' "$target" >&2; exit 1; }
if ! "$script" start; then
    "$script" disable >/dev/null 2>&1 || true
    printf 'Failed to start %s\n' "$target" >&2
    exit 1
fi
# rc.common may report a successful start even if no procd instance was
# registered. Do not tell the caller it is safe to point dnsmasq at it then.
for attempt in 1 2 3; do
    if "$script" running >/dev/null 2>&1; then exit 0; fi
    [ "$attempt" -eq 3 ] || sleep 1
done
"$script" stop >/dev/null 2>&1 || true
"$script" disable >/dev/null 2>&1 || true
printf 'Service did not become ready: %s\n' "$target" >&2
exit 1
