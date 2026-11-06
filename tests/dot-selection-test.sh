#!/bin/sh
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
validator=libexec/dns-manager-dot-selection.sh
dot=catalogs/dot-endpoints.conf; dns=catalogs/dns-8.7-RU-NOSOCIAL.conf
printf '%s\n' '1|cloudflare_clean' > "$t/slots"
sh "$validator" "$t/slots" "$dot" "$dns" || exit 1
printf '%s\n' '1|cloudflare_clean' '2|google_clean' > "$t/slots"
sh "$validator" "$t/slots" "$dot" "$dns" || exit 1
printf '%s\n' 'aa:bb:cc:dd:ee:ff|1,2' > "$t/bindings"
sh "$validator" "$t/slots" "$dot" "$dns" "$t/bindings" || exit 1
printf '%s\n' 'aa:bb:cc:dd:ee:ff|1,3' > "$t/bindings"
if sh "$validator" "$t/slots" "$dot" "$dns" "$t/bindings" >/dev/null 2>&1; then echo 'FAIL: switching with a missing device DNS slot accepted' >&2; exit 1; fi
for invalid in '1|unconfirmed' '1|cloudflare_clean\n2|cloudflare_clean' '1|cloudflare_clean\n1|google_clean' 'RU|cloudflare_clean' '1|cloudflare_clean\n7|google_clean'; do
    printf '%b\n' "$invalid" > "$t/slots"
    if sh "$validator" "$t/slots" "$dot" "$dns" >/dev/null 2>&1; then echo 'FAIL: invalid DoT selection accepted' >&2; exit 1; fi
done
echo 'OK: DoT selection allows one or more documented, distinct servers and validates slot roles'
