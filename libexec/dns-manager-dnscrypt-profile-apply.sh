#!/bin/sh
# Sourced by the DNSCrypt backend after the manager and selector are loaded.
# The caller owns the DNS Manager mutation lock and commits UI metadata only
# after this function succeeds. stdout is the applied catalog ID|URL list.
dnscrypt_apply_profile_pool() (
    local goal port bootstrap apply dnsmasq_apply guard records urls
    goal=${1:-}
    port=${2:-}
    bootstrap=${3:-}
    apply=${DNS_MANAGER_DNSCRYPT_POOL_APPLY:-/usr/lib/dns-manager-luci/dnscrypt/dns-manager-dnscrypt-pool-apply.sh}
    dnsmasq_apply=${DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY:-/usr/lib/dns-manager-luci/dnscrypt/dns-manager-dnscrypt-dnsmasq.sh}
    guard=${DNS_MANAGER_DNSCRYPT_UCI_GUARD:-/usr/lib/dns-manager-luci/cache/uci-read-guard.sh}
    [ -r "$apply" ] || { echo 'DNSCrypt pool apply helper is unavailable' >&2; return 1; }
    [ -r "$dnsmasq_apply" ] && [ -r "$guard" ] || { echo 'DNSCrypt dnsmasq transaction is unavailable' >&2; return 1; }
    # Refuse pending DHCP changes before restarting an already active pool.
    sh "$guard" dhcp /bin/true || { echo 'Pending DHCP changes; profile not changed' >&2; return 1; }
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
    sh "$dnsmasq_apply" "$port" "$guard" /etc/init.d/dnsmasq restart || return 1
    cat "$records"
)
