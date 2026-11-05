#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^dnssec_probe_local\(\) \(/,/^\)/' dns-manager.sh > "$tmp/probe.sh"
. "$tmp/probe.sh"
DIG_SCENARIO=valid
dig() {
    query=''; cdflag=0
    for arg in "$@"; do
        case "$arg" in cloudflare.com|dnssec-failed.org) query="$arg";; +cdflag) cdflag=1;; esac
    done
    case "$DIG_SCENARIO:$query:$cdflag" in
        *:cloudflare.com:*)
            case "$DIG_SCENARIO" in missing_ad) flags='qr rd ra';; *) flags='qr rd ra ad';; esac
            printf ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1234\n;; flags: %s; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1\n' "$flags"
            # Real dig places answer count on the flags line, not header.
            ;;
        timeout:dnssec-failed.org:*) return 1;;
        accepts_bad:dnssec-failed.org:0) printf ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1234\n;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1\n';;
        *:dnssec-failed.org:0) printf ';; ->>HEADER<<- opcode: QUERY, status: SERVFAIL, id: 1234\n;; flags: qr rd ra; QUERY: 1, ANSWER: 0, AUTHORITY: 0, ADDITIONAL: 1\n';;
        empty_cd:dnssec-failed.org:1) printf ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1234\n;; flags: qr rd ra cd; QUERY: 1, ANSWER: 0, AUTHORITY: 0, ADDITIONAL: 1\n';;
        *:dnssec-failed.org:1) printf ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1234\n;; flags: qr rd ra cd; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1\n';;
        *) return 1;;
    esac
}
dnssec_probe_local 5053 || { echo 'FAIL: validating resolver rejected' >&2; exit 1; }
for DIG_SCENARIO in missing_ad accepts_bad empty_cd timeout; do
    if dnssec_probe_local 5053; then echo "FAIL: $DIG_SCENARIO accepted" >&2; exit 1; fi
done
if dnssec_probe_local invalid; then echo 'FAIL: invalid port accepted' >&2; exit 1; fi
echo 'OK: local DNSSEC capability probe fails closed on bad or incomplete responses'
