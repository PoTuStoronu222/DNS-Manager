#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^dnssec_probe_doh\(\) \(/,/^\)/' dns-manager.sh > "$tmp/probe.sh"
. "$tmp/probe.sh"
DNSSEC_SCREEN_DIR="$tmp"; SCENARIO=valid
curl() {
    _o=''; _h=''; _kind=''
    while [ $# -gt 0 ]; do
        case "$1" in -o) _o="$2"; shift 2;; -D) _h="$2"; shift 2;; --data-binary) _kind="${2##*.}"; shift 2;; *) shift;; esac
    done
    case "$SCENARIO" in wrong_type) printf 'Content-Type: text/plain\r\n' > "$_h";; *) printf 'Content-Type: application/dns-message\r\n' > "$_h";; esac
    case "$SCENARIO:$_kind" in
        wrong_id:good) printf '\000\064\201\240\000\001\000\001\000\000\000\000' > "$_o";;
        no_ad:good) printf '\022\064\201\200\000\001\000\001\000\000\000\000' > "$_o";;
        accepts_bad:bad) printf '\022\064\201\200\000\001\000\001\000\000\000\000' > "$_o";;
        no_cd_answer:cd) printf '\022\064\201\220\000\001\000\000\000\000\000\000' > "$_o";;
        *:good) printf '\022\064\201\240\000\001\000\001\000\000\000\000' > "$_o";;
        *:bad) printf '\022\064\201\202\000\001\000\000\000\000\000\000' > "$_o";;
        *:cd) printf '\022\064\201\220\000\001\000\001\000\000\000\000' > "$_o";;
        *) return 1;;
    esac
    printf 200
}
dnssec_probe_doh https://dns.example/query dns.example 443 192.0.2.1 example || { echo 'FAIL: valid prefilter rejected' >&2; exit 1; }
for SCENARIO in wrong_type wrong_id no_ad accepts_bad no_cd_answer; do
    if dnssec_probe_doh https://dns.example/query dns.example 443 192.0.2.1 example; then echo "FAIL: $SCENARIO accepted" >&2; exit 1; fi
done
if find "$tmp" -name 'probe-*' | grep -q .; then echo 'FAIL: temporary probe files remain' >&2; exit 1; fi
echo 'OK: DNSSEC DoH prefilter rejects invalid evidence and removes its temporary files'
