#!/bin/sh
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
cp libexec/dns-manager-dot-selection.sh "$t/validator"; chmod +x "$t/validator"
DOT_SELECTION_VALIDATOR="$t/validator"; DOT_DEVICE_CONFIG_DIR="$t/no-bindings"
export DOT_SELECTION_VALIDATOR DOT_DEVICE_CONFIG_DIR
dot=catalogs/dot-endpoints.conf; dns=catalogs/dns-8.7-RU-NOSOCIAL.conf
draft=libexec/dns-manager-dot-draft.sh
printf '%s\n' '1|cloudflare_clean' '2|some_custom_doh' 'RU|yandex_ru' > "$t/current"
out="$(sh "$draft" "$t/current" "$t/saved" "$dot" "$dns")"
[ "$out" = "$(printf '1|cloudflare_clean\nRU|yandex_ru')" ] || exit 1
printf '%s\n' '1|google_clean' > "$t/saved"
out="$(sh "$draft" "$t/current" "$t/saved" "$dot" "$dns")"
[ "$out" = '1|google_clean' ] || { echo 'Saved selection was not preserved' >&2; exit 1; }
printf '%s\n' 'aa:bb:cc:dd:ee:ff|2' > "$t/bindings"
if sh "$draft" "$t/current" "$t/saved" "$dot" "$dns" "$t/bindings" >/dev/null 2>&1; then echo 'Missing device slot accepted' >&2; exit 1; fi
rm "$t/saved"
if sh "$draft" "$t/current" "$t/saved" "$dot" "$dns" "$t/bindings" >/dev/null 2>&1; then echo 'Missing mapped device slot accepted' >&2; exit 1; fi
printf '%s\n' '1|unknown' > "$t/current"
if sh "$draft" "$t/current" "$t/saved" "$dot" "$dns" >/dev/null 2>&1; then echo 'Unconfirmed DoT guessed' >&2; exit 1; fi
printf '%s\n' '1|cloudflare_clean' '1|google_clean' > "$t/current"
if sh "$draft" "$t/current" "$t/saved" "$dot" "$dns" >/dev/null 2>&1; then echo 'Duplicate slot accepted' >&2; exit 1; fi
echo 'OK: DoT draft preserves saved choices and maps only verified matching slots'

