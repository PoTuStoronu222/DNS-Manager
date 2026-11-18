#!/bin/sh
# Sourced by a future DNSCrypt backend after the existing manager functions are
# loaded. Selects DNS using the existing checks without applying configuration.
# On success stdout contains one catalog ID and URL per line, separated by '|'.
dnscrypt_select_profile() (
    local goal tmp started id url count ms priority native_id native_ms native_url native_scope native_category
    goal=${1:-}
    case "$goal" in bypass|clean|security|privacy|adblock|family|all|dnssec) ;; *) return 1 ;; esac
    tmp=$(mktemp "${TMP_DIR:-/tmp}/dnscrypt-profile.XXXXXX") || return 1
    started=0
    cleanup_dnscrypt_profile() {
        if [ "$started" = 1 ]; then profile_apply_end >&2; fi
        rm -f "$tmp" "$tmp.native"
    }
    trap cleanup_dnscrypt_profile EXIT
    trap 'exit 1' HUP INT TERM
    # This invokes the existing direct DoH tests, including DNSSEC screening.
    if [ "${DNS_MANAGER_PROTOCOL:-mixed}" = native ]; then
        SLOT_1=''; SLOT_2=''; SLOT_3=''; SLOT_4=''; SLOT_5=''; SLOT_6=''
    else
    started=1
    if profile_apply_begin "$goal" >&2; then
        DNSCRYPT_FASTEST_ALL=1 auto_fill_slots "$goal" >&2 || {
            SLOT_1=''; SLOT_2=''; SLOT_3=''; SLOT_4=''; SLOT_5=''; SLOT_6=''
        }
    else
        [ "$goal" = dnssec ] && command -v dig >/dev/null 2>&1 || return 1
        SLOT_1=''; SLOT_2=''; SLOT_3=''; SLOT_4=''; SLOT_5=''; SLOT_6=''
    fi
    fi
    count=0
    for id in "${SLOT_1:-}" "${SLOT_2:-}" "${SLOT_3:-}" "${SLOT_4:-}" "${SLOT_5:-}" "${SLOT_6:-}"; do
        [ -n "$id" ] || continue
        case "$id" in *[!A-Za-z0-9_-]*) return 1 ;; esac
        url=$(normalize_url "$(dns_url "$id")") || return 1
        case "$url" in https://*) ;; *) return 1 ;; esac
        case "$url" in *'|'*|*[![:graph:]]*) return 1 ;; esac
        ms=$(awk -F'|' -v id="$id" '$1==id && $5=="OK" && $4 ~ /^[0-9]+$/ {print $4; exit}' "${TEST_RESULTS:-/dev/null}" 2>/dev/null)
        case "$ms" in ''|*[!0-9]*) ms=2147483647;; esac
        priority=0
        if [ "$goal" = dnssec ]; then
            [ "$(awk -F'|' -v id="$id" '$1==id {print $2; exit}' "${TEST_RESULTS:-/dev/null}")" != privacy ] || priority=1
        fi
        printf '%s|%s|%s|%s\n' "$id" "$url" "$ms" "$priority" >> "$tmp" || return 1
        count=$((count + 1))
    done
    if command -v dnscrypt_catalog_snapshot >/dev/null 2>&1; then
        native_scope=$goal; case "$goal" in all|dnssec) native_scope=native;; esac
        dnscrypt_catalog_snapshot "$native_scope" 2>/dev/null > "$tmp.native" || :
        while IFS='|' read -r native_id native_ms; do
            case "$native_ms" in ''|*[!0-9]*) continue;; esac
            native_url=$(awk -F'|' -v id="$native_id" '$1==id {print $5; exit}' "$HELPERS/dns-manager-dnscrypt-catalog.conf")
            priority=0
            if [ "$goal" = dnssec ]; then
                native_category=$(awk -F'|' -v id="$native_id" '$1==id {print $2; exit}' "$HELPERS/dns-manager-dnscrypt-catalog.conf")
                case "$native_category" in clean|privacy) ;; *) continue;; esac
                [ "$native_category" != privacy ] || priority=1
                [ -n "$native_url" ] && dnscrypt_native_dnssec_probe "$native_url" || continue
            fi
            [ -n "$native_url" ] && printf '%s|%s|%s|%s\n' "$native_id" "$native_url" "$native_ms" "$priority" >> "$tmp"
        done < "$tmp.native"
        rm -f "$tmp.native"
    fi
    if [ ! -s "$tmp" ]; then
        echo 'Для выбранного профиля и протокола не найдено доступных серверов.' >&2
        return 1
    fi
    sort -t'|' -k4,4n -k3,3n "$tmp" | head -n 6 | cut -d'|' -f1,2
)
