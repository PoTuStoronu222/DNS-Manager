#!/bin/sh
# Experimental procd metadata handoff; not installed or called by the manager.
# The caller must hold the mutation lock and must arrange boot/rollback handling.
set -eu
action="${1:-}"
guard=dns-manager-dot-fw-guard
runtime="${DOT_FIREWALL_RUNTIME:-/var/run/dns-manager-dot}"
state="$runtime/firewall-guard.json"
for cmd in ubus jsonfilter; do command -v "$cmd" >/dev/null 2>&1 || exit 1; done
service_exists() {
    listing="$(ubus call service list "{\"name\":\"$guard\"}")" || return 2
    printf '%s\n' "$listing" | jsonfilter -e "@[\"$guard\"]" | grep -q .
}
guard_rules() {
    data="$(ubus call service get_data "{\"name\":\"$guard\",\"type\":\"firewall\"}")" || return 1
    printf '%s\n' "$data" | jsonfilter -e "@[\"$guard\"].*.firewall"
}
case "$action" in
    start)
        [ ! -e "$state" ] && [ ! -L "$state" ] || { echo 'Firewall guard state already exists' >&2; exit 1; }
        if service_exists; then echo 'Firewall guard service already exists' >&2; exit 1
        else rc=$?; [ "$rc" = 1 ] || exit 1; fi
        # jsonfilter emits one compact JSON array per instance. Never merge or
        # guess ownership when more than one proxy instance supplies metadata.
        proxy_data="$(ubus call service get_data '{"name":"https-dns-proxy","type":"firewall"}')" || exit 1
        printf '%s\n' "$proxy_data" | jsonfilter -e '@' >/dev/null || exit 1
        rules="$(printf '%s\n' "$proxy_data" | jsonfilter -e '@["https-dns-proxy"].*.firewall')" || rules=''
        [ -n "$rules" ] || { echo 'No proxy-owned firewall rules to preserve'; exit 0; }
        case "$rules" in *'
'*) echo 'Multiple firewall metadata owners; refusing handoff' >&2; exit 1;; esac
        case "$rules" in \[*\]) ;; *) echo 'Invalid proxy firewall metadata' >&2; exit 1;; esac
        mkdir -p "$runtime" || exit 1
        [ -d "$runtime" ] && [ ! -L "$runtime" ] || exit 1
        umask 077
        ( set -C; printf '%s\n' "$rules" > "$state" ) 2>/dev/null || { echo 'Cannot claim firewall guard state' >&2; exit 1; }
        if ! ubus call service add "{\"name\":\"$guard\",\"instances\":{\"guard\":{\"command\":[\"/bin/sleep\",\"2147483647\"],\"data\":{\"firewall\":$rules}}}}" >/dev/null; then
            echo 'Firewall guard registration failed; state retained' >&2; exit 1
        fi
        actual="$(guard_rules)" || exit 1
        [ "$actual" = "$rules" ] || { echo 'Firewall guard metadata mismatch; state retained' >&2; exit 1; }
        ;;
    finish)
        [ -f "$state" ] && [ ! -L "$state" ] || { echo 'Firewall guard state unavailable' >&2; exit 1; }
        rules="$(cat "$state")" || exit 1
        actual="$(guard_rules)" || exit 1
        [ "$actual" = "$rules" ] || { echo 'Firewall guard changed; refusing to remove it' >&2; exit 1; }
        listing="$(ubus call service list "{\"name\":\"$guard\"}")" || exit 1
        program="$(printf '%s\n' "$listing" | jsonfilter -e "@[\"$guard\"].instances.guard.command[0]")" || exit 1
        argument="$(printf '%s\n' "$listing" | jsonfilter -e "@[\"$guard\"].instances.guard.command[1]")" || exit 1
        [ "$program" = /bin/sleep ] && [ "$argument" = 2147483647 ] || { echo 'Firewall guard service changed; refusing to remove it' >&2; exit 1; }
        ubus call service delete "{\"name\":\"$guard\"}" >/dev/null || exit 1
        rm -f "$state"
        ;;
    *) echo 'Usage: dns-manager-dot-firewall {start|finish}' >&2; exit 1;;
esac

