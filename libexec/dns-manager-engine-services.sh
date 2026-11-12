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

stop_disable() {
    script="$initdir/$1"
    [ -x "$script" ] || return 0
    "$script" stop || { printf 'Failed to stop %s\n' "$1" >&2; return 1; }
    "$script" disable || { printf 'Failed to disable %s\n' "$1" >&2; return 1; }
    if "$script" running >/dev/null 2>&1; then
        printf 'Still running: %s\n' "$1" >&2
        return 1
    fi
    if "$script" enabled >/dev/null 2>&1; then
        printf 'Still enabled: %s\n' "$1" >&2
        return 1
    fi
}

if [ "$action" = quiesce ]; then
    # Both the package service and our slot service must be stopped: installing
    # dnscrypt-proxy2 may automatically enable and start its own service.
    for service in https-dns-proxy dnscrypt-proxy dns-manager-dnscrypt; do
        stop_disable "$service" || exit 1
    done
    exit 0
fi

case "$engine" in
    https-dns-proxy) target=https-dns-proxy ;;
    dnscrypt-proxy2) target=dns-manager-dnscrypt ;;
esac

# Never knowingly start a second manager while another service is enabled or
# running. The caller must have restored DNS and performed quiesce first.
for service in https-dns-proxy dnscrypt-proxy dns-manager-dnscrypt; do
    [ "$service" = "$target" ] && continue
    script="$initdir/$service"
    [ -x "$script" ] || continue
    if "$script" enabled >/dev/null 2>&1 || "$script" running >/dev/null 2>&1; then
        printf 'Conflicting service is active or enabled: %s\n' "$service" >&2
        exit 1
    fi
done
script="$initdir/$target"
[ -x "$script" ] || { printf 'Missing service: %s\n' "$target" >&2; exit 1; }
# rc.common's procd start may not propagate start_service's failure. Validate
# explicitly before enabling the experimental slot service at boot.
if [ "$engine" = dnscrypt-proxy2 ]; then
    "$script" check || { printf 'Invalid dnscrypt-proxy2 configuration\n' >&2; exit 1; }
fi
"$script" enable || { printf 'Failed to enable %s\n' "$target" >&2; exit 1; }
if ! "$script" start; then
    "$script" disable >/dev/null 2>&1 || true
    printf 'Failed to start %s\n' "$target" >&2
    exit 1
fi
