#!/bin/sh
# Sourced by a future DNSCrypt backend after the existing manager functions are
# loaded. Selects DNS using the existing checks without applying configuration.
# On success stdout contains one catalog ID and URL per line, separated by '|'.
dnscrypt_select_profile() (
    local goal tmp started id url count
    goal=${1:-}
    case "$goal" in bypass|clean|security|privacy|adblock|family|all|dnssec) ;; *) return 1 ;; esac
    tmp=$(mktemp "${TMP_DIR:-/tmp}/dnscrypt-profile.XXXXXX") || return 1
    started=0
    cleanup_dnscrypt_profile() {
        if [ "$started" = 1 ]; then profile_apply_end >&2; fi
        rm -f "$tmp"
    }
    trap cleanup_dnscrypt_profile EXIT
    trap 'exit 1' HUP INT TERM
    # This invokes the existing direct DoH tests, including DNSSEC screening.
    started=1
    profile_apply_begin "$goal" >&2 || return 1
    auto_fill_slots "$goal" >&2 || return 1
    count=0
    for id in "${SLOT_1:-}" "${SLOT_2:-}" "${SLOT_3:-}" "${SLOT_4:-}" "${SLOT_5:-}" "${SLOT_6:-}"; do
        [ -n "$id" ] || continue
        case "$id" in *[!A-Za-z0-9_-]*) return 1 ;; esac
        url=$(normalize_url "$(dns_url "$id")") || return 1
        case "$url" in https://*) ;; *) return 1 ;; esac
        case "$url" in *'|'*|*[![:graph:]]*) return 1 ;; esac
        printf '%s|%s\n' "$id" "$url" >> "$tmp" || return 1
        count=$((count + 1))
    done
    [ "$count" -gt 0 ] || return 1
    cat "$tmp"
)
