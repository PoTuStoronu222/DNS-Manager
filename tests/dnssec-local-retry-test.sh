#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^dnssec_candidate_eligible\(\) \{/,/^}/' dns-manager.sh > "$tmp/functions"
awk '/^profile_retry_dnssec_slots\(\) \{/,/^}/' dns-manager.sh >> "$tmp/functions"
. "$tmp/functions"
TMP_DIR="$tmp"; DNSSEC_SCREEN_DIR="$tmp/dnssec-screen.test"; mkdir "$DNSSEC_SCREEN_DIR"
cat > "$DNSSEC_SCREEN_DIR/candidates" <<'EOF_CANDIDATES'
cloudflare_clean|clean|Cloudflare|1|OK
google_clean|clean|Google|2|OK
dagami|bypass|Dagami|3|OK
geodema|bypass|Geodema|4|OK
paesa|bypass|Paesa|5|OK
cynthia|privacy|Cynthia|6|OK
aquilenet|clean|Aquilenet|7|OK
digitalsize|privacy|DigitalSize|8|OK
EOF_CANDIDATES
for id in cloudflare_clean google_clean dagami geodema paesa cynthia aquilenet digitalsize; do : > "$DNSSEC_SCREEN_DIR/$id"; done
reset_slots() {
    SLOT_1=cloudflare_clean SLOT_2=google_clean SLOT_3=dagami SLOT_4=geodema SLOT_5=paesa SLOT_6=cynthia SLOT_RU=region
    PORT_1=5053 PORT_2=5054 PORT_3=5055 PORT_4=5056 PORT_5=5057 PORT_6=5058 PORT_RU=5059
    SLOT_1_CAT=clean SLOT_2_CAT=clean SLOT_3_CAT=bypass SLOT_4_CAT=bypass SLOT_5_CAT=bypass SLOT_6_CAT=privacy
    RESTARTS=0 RESTART_FAIL=0 MODE=seventh
}
dig() { :; }
listener_port_exists() { :; }
local_dns_query_ok() { :; }
dnssec_probe_local() {
    case "$1" in 5053) _t="$SLOT_1";; 5054) _t="$SLOT_2";; 5055) _t="$SLOT_3";; 5056) _t="$SLOT_4";; 5057) _t="$SLOT_5";; 5058) _t="$SLOT_6";; *) return 1;; esac
    case "$MODE:$_t" in seventh:aquilenet|seventh:digitalsize|partial:cloudflare_clean|partial:aquilenet|partial:digitalsize|duplicate:digitalsize) return 0;; *) return 1;; esac
}
dns_cat() { case "$1" in cloudflare_clean|google_clean|aquilenet) printf clean;; dagami|geodema|paesa) printf bypass;; cynthia|digitalsize) printf privacy;; region) printf regional;; *) printf bypass;; esac; }
dns_url() { if [ "${MODE:-}" = duplicate ] && { [ "$1" = region ] || [ "$1" = aquilenet ]; }; then printf 'https://same.example'; else printf 'https://%s.example' "$1"; fi; }
normalize_url() { printf '%s' "$1"; }
slot_set() { eval "SLOT_$1=\$2"; }
slot_cat_set() { eval "SLOT_${1}_CAT=\$2"; }
apply_progress() { :; }
profile_dnssec_restart_services() { RESTARTS=$((RESTARTS+1)); [ "$RESTART_FAIL" = 0 ]; }
profile_prune_failed_slots() { return 1; }
reset_slots
profile_retry_dnssec_slots || { echo 'FAIL: did not reach later working candidates' >&2; exit 1; }
[ "$SLOT_1" = aquilenet ] && [ "$SLOT_2" = digitalsize ] && [ -z "$SLOT_3" ] && [ "$SLOT_RU" = region ] && [ "$RESTARTS" -eq 1 ] || { echo 'FAIL: incorrect later candidate or regional slot' >&2; exit 1; }
reset_slots; MODE=partial
profile_retry_dnssec_slots || { echo 'FAIL: partial retry failed' >&2; exit 1; }
[ "$SLOT_1" = cloudflare_clean ] && [ "$SLOT_2" = aquilenet ] && [ "$SLOT_RU" = region ] || exit 1
reset_slots; MODE=duplicate
profile_retry_dnssec_slots || { echo 'FAIL: failed to skip regional URL duplicate' >&2; exit 1; }
[ "$SLOT_1" = digitalsize ] && [ "$SLOT_RU" = region ] || exit 1
reset_slots; MODE=none
if profile_retry_dnssec_slots; then echo 'FAIL: accepted no working general DNS' >&2; exit 1; fi
[ "$SLOT_RU" = region ] || exit 1
reset_slots; RESTART_FAIL=1
if profile_retry_dnssec_slots; then echo 'FAIL: accepted restart failure' >&2; exit 1; fi
[ "$SLOT_RU" = region ] || exit 1
# Large failing candidate pools cannot cause an unbounded restart loop.
for id in malw_cloudflare shecan dnsbunker dnsforge dnsforge_strict dnsforge_youth doh_lacontrevoie hostux opendns_standard opendns_family adguard_default nextdns_anycast wikimedia ffmuc cloudflare_family cloudflare_security nwps_standard nwps_kids iijjp; do
    : > "$DNSSEC_SCREEN_DIR/$id"
    printf '%s|bypass|Candidate|99|OK\n' "$id" >> "$DNSSEC_SCREEN_DIR/candidates"
done
reset_slots; MODE=none
if profile_retry_dnssec_slots; then echo 'FAIL: all failing candidates accepted' >&2; exit 1; fi
[ "$RESTARTS" -le 6 ] && [ "$SLOT_RU" = region ] || { echo 'FAIL: retry limit or regional state' >&2; exit 1; }
echo 'OK: local DNSSEC failures try later screened candidates with bounded restarts and preserved regional DNS'
