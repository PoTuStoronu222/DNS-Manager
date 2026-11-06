#!/bin/sh
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
script=libexec/dns-manager-dot-config.sh; catalog=catalogs/dot-endpoints.conf
sh "$script" cloudflare_clean 5053 "$catalog" > "$t/stubby.yml"
grep -qx '  - 127.0.0.1@5053' "$t/stubby.yml"
grep -qx 'tls_authentication: GETDNS_AUTHENTICATION_REQUIRED' "$t/stubby.yml"
grep -qx '  - GETDNS_TRANSPORT_TLS' "$t/stubby.yml"
[ "$(grep -c '^  - address_data:' "$t/stubby.yml")" = 2 ]
grep -qx '    tls_auth_name: "one.one.one.one"' "$t/stubby.yml"
if sh "$script" missing 5053 "$catalog" > /dev/null 2>&1; then exit 1; fi
if sh "$script" cloudflare_clean '5053;evil' "$catalog" > /dev/null 2>&1; then exit 1; fi
printf '%s\n' 'bad|dns.example|999.1.1.1' > "$t/bad"
if sh "$script" bad 5053 "$t/bad" > /dev/null 2>&1; then exit 1; fi
printf '%s\n' 'bad|x";evil|1.1.1.1' > "$t/bad"
if sh "$script" bad 5053 "$t/bad" > /dev/null 2>&1; then exit 1; fi
printf '%s\n' 'bad|dns.example|1.1.1.1' 'bad|dns.example|1.0.0.1' > "$t/bad"
if sh "$script" bad 5053 "$t/bad" > /dev/null 2>&1; then exit 1; fi
echo 'OK: DoT slot generator uses strict TLS and rejects invalid endpoint data'
