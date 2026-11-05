#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^provider_fallback_replace_servers\(\) \(/,/^\)/' dns-manager.sh > "$tmp/functions"
awk '/^provider_fallback_apply_journal\(\) \(/,/^\)/' dns-manager.sh >> "$tmp/functions"
. "$tmp/functions"
uci() { printf '%s\n' invoked >> "$tmp/uci-invoked"; return 1; }
if provider_fallback_replace_servers cfg123 "$tmp/before" "$tmp/after"; then
    echo 'FAIL: unresolved UCI race is not blocked' >&2
    exit 1
fi
if provider_fallback_apply_journal "$tmp/journal" cfg123 "$tmp/before" "$tmp/after" "$tmp/config"; then
    echo 'FAIL: unsafe fallback transaction is not blocked' >&2
    exit 1
fi
[ ! -e "$tmp/uci-invoked" ] && [ ! -e "$tmp/journal" ] || {
    echo 'FAIL: blocked operation changed state' >&2
    exit 1
}
echo 'OK: provider fallback remains disabled while the UCI race is unresolved'
