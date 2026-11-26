#!/bin/sh
# Sourced by the DNSCrypt backend after the manager and selector are loaded.
# The caller owns the DNS Manager mutation lock and commits UI metadata only
# after this function succeeds. stdout is the applied catalog ID|URL list.
dnscrypt_apply_profile_pool() (
    local goal port bootstrap apply dnsmasq_apply records urls config init backup had_config dnsmasq_ready server found
    goal=${1:-}
    port=${2:-}
    bootstrap=${3:-}
    apply=${DNS_MANAGER_DNSCRYPT_POOL_APPLY:-/usr/lib/dns-manager-luci/dnscrypt/dns-manager-dnscrypt-pool-apply.sh}
    dnsmasq_apply=${DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY:-/usr/lib/dns-manager-luci/dnscrypt/dns-manager-dnscrypt-dnsmasq.sh}
    config=${DNS_MANAGER_DNSCRYPT_CONFIG:-/etc/dnscrypt-proxy2/dnscrypt-proxy.toml}
    init=${DNS_MANAGER_DNSCRYPT_INIT:-/etc/init.d/dnscrypt-proxy}
    [ -r "$apply" ] || { echo 'DNSCrypt pool apply helper is unavailable' >&2; return 1; }
    [ -r "$dnsmasq_apply" ] || { echo 'DNSCrypt dnsmasq helper is unavailable' >&2; return 1; }
    records=$(mktemp "${TMP_DIR:-/tmp}/dnscrypt-selected.XXXXXX") || return 1
    urls=$(mktemp "${TMP_DIR:-/tmp}/dnscrypt-urls.XXXXXX") || { rm -f "$records"; return 1; }
    backup=$(mktemp "$(dirname "$config")/.dnscrypt-previous.XXXXXX") || { rm -f "$records" "$urls"; return 1; }
    trap 'rm -f "$records" "$urls"; [ -z "$backup" ] || rm -f "$backup"' EXIT
    trap 'exit 1' HUP INT TERM
    dnscrypt_select_profile "$goal" > "$records" || return 1
    [ -s "$records" ] || return 1
    if [ -n "${JOB_DIR:-}" ]; then
        printf 'phase=Применяю выбранные серверы и проверяю DNS\nprogress_total=0\n' >> "$JOB_DIR/profile/state"
    fi
    if [ "${DNS_MANAGER_PROTOCOL:-mixed}" = native ]; then
        if awk -F'|' 'NF != 2 || $2 !~ /^sdns:\/\// {bad=1} END {exit !bad}' "$records"; then
            echo 'Удалите DoH-серверы из набора: выбран только DNSCrypt.' >&2
            return 1
        fi
    fi
    # Selector validates and bounds the records; pool helper independently
    # validates every URL and the bootstrap list before changing anything.
    cut -d '|' -f 2 "$records" > "$urls" || return 1
    had_config=0
    [ ! -L "$config" ] || return 1
    if [ -e "$config" ]; then
        [ -f "$config" ] && cp -p "$config" "$backup" || return 1
        had_config=1
    fi
    sh "$apply" "$port" "$bootstrap" < "$urls" || return 1
    dnsmasq_ready=0
    if [ "${DNS_MANAGER_KEEP_DNSMASQ:-0}" = 1 ] &&
       [ "$(uci -q get 'dhcp.@dnsmasq[0].noresolv')" = 1 ] && service dnsmasq running >/dev/null 2>&1; then
        found=0
        for server in $(uci -q get 'dhcp.@dnsmasq[0].server'); do
            case "$server" in
                "127.0.0.1#$port") found=1;;
                /*) ;;
                *) found=0; break;;
            esac
        done
        [ "$found" = 1 ] && dnsmasq_ready=1
    fi
    if [ "$dnsmasq_ready" != 1 ] && ! sh "$dnsmasq_apply" "$port"; then
        # The pool helper has already switched the proxy. Restore its previous
        # configuration so a failed dnsmasq update does not silently change
        # the DNS servers behind an existing profile.
        if [ "$had_config" = 1 ]; then
            if mv -f "$backup" "$config"; then
                backup=''
                "$init" restart >/dev/null 2>&1 || echo 'Failed to restart previous DNSCrypt pool' >&2
            else
                echo "Failed to restore DNSCrypt configuration; backup retained at $backup" >&2
                backup=''
            fi
        else
            # dnsmasq may still reference this listener if even its fallback
            # restart failed; keep the answering pool alive in that case.
            echo 'Previous DNSCrypt configuration absent; keeping the new listener running' >&2
        fi
        return 1
    fi
    cat "$records"
)
