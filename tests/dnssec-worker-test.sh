#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^test_one_dns\(\) \{/,/^test_dns_catalog\(\) \(/' dns-manager.sh | sed '$d' > "$tmp/worker"
. "$tmp/worker"
TMP_DIR="$tmp"; DNSSEC_SCREEN_DIR="$tmp/screen"; mkdir "$DNSSEC_SCREEN_DIR"; HAS_DIG=no; BOOTSTRAP_DNS=1.1.1.1
normalize_url() { printf '%s' "$1"; }
dns_url() { printf 'https://dns.example/dns-query'; }
dns_name() { printf 'DNS'; }
dns_cat() { printf clean; }
url_host() { printf dns.example; }
url_port() { printf 443; }
resolve_host_fallback() { printf '192.0.2.1'; }
validate_dns_message() { :; }
dnssec_candidate_eligible() { :; }
dnssec_probe_doh() { [ "$5" = later ]; }
curl() {
    _o=''; _h=''
    while [ $# -gt 0 ]; do case "$1" in -o) _o="$2"; shift 2;; -D) _h="$2"; shift 2;; *) shift;; esac; done
    printf 'wire' > "$_o"; printf 'Content-Type: application/dns-message\r\n' > "$_h"; printf '200|0.01|'
}
test_one_dns early
[ ! -f "$DNSSEC_SCREEN_DIR/early" ] || { echo 'FAIL: nonvalidating candidate marked valid' >&2; exit 1; }
grep -q '^early|clean|DNS|10|OK$' "$TMP_DIR/t.early" || { echo 'FAIL: DNSSEC failure changed availability result' >&2; exit 1; }
test_one_dns later
[ -f "$DNSSEC_SCREEN_DIR/later" ] || { echo 'FAIL: valid candidate not marked' >&2; exit 1; }
grep -q '^later|clean|DNS|10|OK$' "$TMP_DIR/t.later" || exit 1
echo 'OK: DNSSEC screening is separate from ordinary availability results'
