#!/bin/sh
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
cp libexec/dns-manager-dot-selection.sh "$t/validator"; chmod +x "$t/validator"
DOT_SELECTION_VALIDATOR="$t/validator"; export DOT_SELECTION_VALIDATOR
dot=catalogs/dot-endpoints.conf; dns=catalogs/dns-8.7-RU-NOSOCIAL.conf
printf '%s\n' 'DoH configuration remains unchanged' > "$t/manager.conf"
printf '%s\n' '1|cloudflare_clean' > "$t/input"
sh libexec/dns-manager-dot-save.sh "$t/input" "$t/dot-slots.conf" "$dot" "$dns"
[ "$(cat "$t/dot-slots.conf")" = '1|cloudflare_clean' ] || exit 1
printf '%s\n' '1|unsupported' > "$t/input"
if sh libexec/dns-manager-dot-save.sh "$t/input" "$t/dot-slots.conf" "$dot" "$dns" >/dev/null 2>&1; then exit 1; fi
[ "$(cat "$t/dot-slots.conf")" = '1|cloudflare_clean' ] || { echo 'FAIL: failed save changed the previous DoT selection' >&2; exit 1; }
[ "$(cat "$t/manager.conf")" = 'DoH configuration remains unchanged' ] || exit 1
printf '%s\n' '1|google_clean' > "$t/input"
printf '%s\n' 'aa:bb:cc:dd:ee:ff|2' > "$t/bindings"
if sh libexec/dns-manager-dot-save.sh "$t/input" "$t/dot-slots.conf" "$dot" "$dns" "$t/bindings" >/dev/null 2>&1; then exit 1; fi
[ "$(cat "$t/dot-slots.conf")" = '1|cloudflare_clean' ] || exit 1
echo 'OK: DoT selections save atomically and preserve DoH and previous selection on failure'
