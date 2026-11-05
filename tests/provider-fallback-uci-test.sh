#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
STATE_DIR="$tmp/state"; mkdir -p "$STATE_DIR"
awk '/^provider_fallback_replace_servers\(\) \(/,/^\)/' dns-manager.sh > "$tmp/functions"
for fn in provider_fallback_journal_create provider_fallback_journal_classify provider_fallback_read_servers provider_fallback_remove_journal provider_fallback_restore_journal provider_fallback_apply_journal; do
    awk -v fn="$fn" '$0==fn "() (" {p=1} p {print} p && /^\)$/ {exit}' dns-manager.sh >> "$tmp/functions"
done
. "$tmp/functions"
uci() {
    _mock_dir=""
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -q|-x) shift ;;
            -P) _mock_dir="$2"; shift 2 ;;
            *) break ;;
        esac
    done
    _mock_cmd="$1"; shift
    case "$_mock_cmd:$1" in
        changes:dhcp) [ ! -f "$tmp/pending" ] || cat "$tmp/pending" ;;
        get:dhcp.cfg123) printf 'dnsmasq\n' ;;
        get:dhcp.cfg123.server)
            if [ -n "$_mock_dir" ] && [ -f "$_mock_dir/dhcp" ]; then
                tr '\n' ' ' < "$_mock_dir/dhcp"
            else
                tr '\n' ' ' < "$tmp/live"
            fi ;;
        delete:dhcp.cfg123.server) [ -n "$_mock_dir" ] || return 1; : > "$_mock_dir/dhcp" ;;
        add_list:dhcp.cfg123.server=*) [ -n "$_mock_dir" ] || return 1; printf '%s\n' "${1#*=}" >> "$_mock_dir/dhcp" ;;
        commit:dhcp)
            [ -n "$_mock_dir" ] && [ ! -f "$tmp/fail-commit" ] || return 1
            cp "$_mock_dir/dhcp" "$tmp/live" ;;
        *) return 1 ;;
    esac
}
printf '%s\n' '127.0.0.1#5053' '/lan/192.168.1.1' > "$tmp/before"
printf '%s\n' '8.8.8.8' '/lan/192.168.1.1' > "$tmp/after"
cp "$tmp/before" "$tmp/live"
provider_fallback_replace_servers cfg123 "$tmp/before" "$tmp/after"
cmp -s "$tmp/live" "$tmp/after" || { echo 'FAIL: fallback list was not applied' >&2; exit 1; }
provider_fallback_replace_servers cfg123 "$tmp/after" "$tmp/before"
cmp -s "$tmp/live" "$tmp/before" || { echo 'FAIL: original list was not restored' >&2; exit 1; }
printf 'dhcp.other.changed=1\n' > "$tmp/pending"
if provider_fallback_replace_servers cfg123 "$tmp/before" "$tmp/after"; then echo 'FAIL: pending changes were ignored' >&2; exit 1; fi
cmp -s "$tmp/live" "$tmp/before" || exit 1
rm "$tmp/pending"
printf '/foreign/9.9.9.9\n' >> "$tmp/live"
if provider_fallback_replace_servers cfg123 "$tmp/before" "$tmp/after"; then echo 'FAIL: concurrent change was ignored' >&2; exit 1; fi
grep -Fxq '/foreign/9.9.9.9' "$tmp/live" || exit 1
cp "$tmp/before" "$tmp/live"; : > "$tmp/fail-commit"
if provider_fallback_replace_servers cfg123 "$tmp/before" "$tmp/after"; then echo 'FAIL: failed commit reported success' >&2; exit 1; fi
cmp -s "$tmp/live" "$tmp/before" || exit 1
rm "$tmp/fail-commit"
printf 'SLOT_1=chosen\n' > "$tmp/config"
provider_fallback_restart_dnsmasq() {
    printf 'restart\n' >> "$tmp/restarts"
    if [ -f "$tmp/fail-restart-once" ]; then rm "$tmp/fail-restart-once"; return 1; fi
    return 0
}
provider_fallback_verify_local() { [ ! -f "$tmp/fail-verify" ]; }
provider_fallback_apply_journal "$tmp/journal" cfg123 "$tmp/before" "$tmp/after" "$tmp/config"
cmp -s "$tmp/live" "$tmp/after" || exit 1
printf 'SLOT_1=changed\n' > "$tmp/config"
if provider_fallback_restore_journal "$tmp/journal" "$tmp/config"; then echo 'FAIL: changed profile was overwritten' >&2; exit 1; fi
cmp -s "$tmp/live" "$tmp/after" || exit 1
printf 'SLOT_1=chosen\n' > "$tmp/config"
provider_fallback_restore_journal "$tmp/journal" "$tmp/config"
cmp -s "$tmp/live" "$tmp/before" && [ ! -e "$tmp/journal" ] || exit 1
: > "$tmp/fail-verify"
if provider_fallback_apply_journal "$tmp/journal" cfg123 "$tmp/before" "$tmp/after" "$tmp/config"; then echo 'FAIL: failed verification accepted' >&2; exit 1; fi
cmp -s "$tmp/live" "$tmp/before" && [ ! -e "$tmp/journal" ] || { echo 'FAIL: failed verification did not roll back' >&2; exit 1; }
rm "$tmp/fail-verify"
: > "$tmp/fail-restart-once"
if provider_fallback_apply_journal "$tmp/journal" cfg123 "$tmp/before" "$tmp/after" "$tmp/config"; then echo 'FAIL: failed restart accepted' >&2; exit 1; fi
cmp -s "$tmp/live" "$tmp/before" && [ ! -e "$tmp/journal" ] || { echo 'FAIL: failed restart did not roll back' >&2; exit 1; }
provider_fallback_apply_journal "$tmp/journal" cfg123 "$tmp/before" "$tmp/after" "$tmp/config"
printf '/third-party/192.168.9.1\n' >> "$tmp/live"
if provider_fallback_restore_journal "$tmp/journal" "$tmp/config"; then echo 'FAIL: external changes overwritten' >&2; exit 1; fi
grep -Fxq '/third-party/192.168.9.1' "$tmp/live" || exit 1
echo 'OK: provider fallback UCI staging and conflict checks'
