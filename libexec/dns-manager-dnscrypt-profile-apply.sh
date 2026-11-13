#!/bin/sh
# Sourced by the DNSCrypt backend after the manager and selector are loaded.
# The caller owns the DNS Manager mutation lock and commits UI metadata only
# after this function succeeds. stdout is the applied catalog ID|URL list.
dnscrypt_apply_profile_pool() (
    local goal port bootstrap apply records urls
    goal=${1:-}
    port=${2:-}
    bootstrap=${3:-}
    apply=${DNS_MANAGER_DNSCRYPT_POOL_APPLY:-/usr/lib/dns-manager-luci/dnscrypt/dns-manager-dnscrypt-pool-apply.sh}
    [ -r "$apply" ] || { echo 'DNSCrypt pool apply helper is unavailable' >&2; return 1; }
    records=$(mktemp "${TMP_DIR:-/tmp}/dnscrypt-selected.XXXXXX") || return 1
    urls=$(mktemp "${TMP_DIR:-/tmp}/dnscrypt-urls.XXXXXX") || { rm -f "$records"; return 1; }
    trap 'rm -f "$records" "$urls"' EXIT
    trap 'exit 1' HUP INT TERM
    dnscrypt_select_profile "$goal" > "$records" || return 1
    [ -s "$records" ] || return 1
    # Selector validates and bounds the records; pool helper independently
    # validates every URL and the bootstrap list before changing anything.
    cut -d '|' -f 2 "$records" > "$urls" || return 1
    sh "$apply" "$port" "$bootstrap" < "$urls" || return 1
    cat "$records"
)
