#!/bin/sh
# Optional real Stubby + dig integration test; requires outbound TCP/853.
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
cp libexec/dns-manager-dot-selection.sh "$t/validator"
cp libexec/dns-manager-dot-config.sh "$t/generator"
chmod +x "$t/validator" "$t/generator"
DOT_SELECTION_VALIDATOR="$t/validator"; DOT_CONFIG_GENERATOR="$t/generator"
DOT_STUBBY="${STUBBY_BIN:-stubby}"; DOT_DIG="${DIG_BIN:-dig}"; TMPDIR="$t"
export DOT_SELECTION_VALIDATOR DOT_CONFIG_GENERATOR DOT_STUBBY DOT_DIG TMPDIR
printf '%s\n' '1|cloudflare_clean' > "$t/selection"
sh libexec/dns-manager-dot-probe.sh "$t/selection" catalogs/dot-endpoints.conf catalogs/dns-8.7-RU-NOSOCIAL.conf
DOT_TEST_SELECTION="$t/selection"; export DOT_TEST_SELECTION
python3 tests/dot-probe-collision-test.py
sed 's/one.one.one.one/dns.google/' catalogs/dot-endpoints.conf > "$t/bad-catalog"
if sh libexec/dns-manager-dot-probe.sh "$t/selection" "$t/bad-catalog" catalogs/dns-8.7-RU-NOSOCIAL.conf >/dev/null 2>&1; then
    echo 'FAIL: invalid TLS name was accepted' >&2; exit 1
fi
if find "$t" -maxdepth 1 -name 'dns-manager-dot-probe.*' | grep -q .; then echo 'FAIL: temporary probe files remained' >&2; exit 1; fi
if ps -eo args= | grep -F "$t/dns-manager-dot-probe." | grep -F stubby >/dev/null; then echo 'FAIL: temporary Stubby process remained' >&2; exit 1; fi
echo 'OK: preflight uses a temporary isolated listener and rejects bad TLS'
