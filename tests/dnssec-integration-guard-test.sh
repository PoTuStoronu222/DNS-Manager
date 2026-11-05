#!/bin/sh
# Validate DNSSEC gates without changing router services or UCI.
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^verify_selected_doh\(\) \{/,/^}/' dns-manager.sh > "$tmp/verify"
awk '/^profile_prune_failed_slots\(\) \{/,/^}/' dns-manager.sh > "$tmp/prune"
awk '/^watchdog_apply_slot_candidate\(\) \{/,/^}/' dns-manager.sh > "$tmp/candidate"
. "$tmp/verify"
. "$tmp/prune"
. "$tmp/candidate"
TMP_DIR="$tmp"; APPLY_OUTPUT_QUIET=1; C_GREEN=''; C_NC=''
DNS_SELECTION_MODE=profile; DNS_SELECTION_CATEGORY=dnssec
SLOT_1=old; PORT_1=5053; SLOT_2=''; SLOT_3=''; SLOT_4=''; SLOT_5=''; SLOT_6=''; SLOT_RU=ru; PORT_RU=5059
SLOT_1_CAT=clean; PROBE_OK=0; SAVED=0; REBUILD_COUNT=0
verify_applied_doh_config() { :; }
listener_port_exists() { :; }
local_dns_query_ok() { :; }
dnssec_probe_local() { [ "$PROBE_OK" = 1 ]; }
dns_name() { printf '%s' "$1"; }
dns_cat() { printf clean; }
watchdog_desired_cat() { printf dnssec; }
err_msg() { :; }
warn_msg() { :; }
log_msg() { :; }
sleep() { :; }
slot_set() { eval "SLOT_$1=\$2"; }
slot_cat_set() { eval "SLOT_${1}_CAT=\$2"; }
rebuild_selected_hdp_sections() { REBUILD_COUNT=$((REBUILD_COUNT+1)); [ "$REBUILD_COUNT" -eq 1 ]; }
watchdog_restart_hdp() { :; }
watchdog_check_slot() { :; }
save_config() { SAVED=1; }
normalize_ownership_snapshot() { :; }
record_own() { :; }
dns_url() { printf 'https://dns.example/dns-query'; }
normalize_url() { printf '%s' "$1"; }
if verify_selected_doh; then echo 'FAIL: nonvalidating general slot accepted' >&2; exit 1; fi
[ "$FAILED_SLOT" = 1 ] || exit 1
if profile_prune_failed_slots; then echo 'FAIL: RU masked the failure of all general slots' >&2; exit 1; fi
if watchdog_apply_slot_candidate 1 candidate clean old clean; then echo 'FAIL: unverified replacement saved' >&2; exit 1; fi
[ "$SLOT_1" = old ] && [ "$SAVED" -eq 0 ] || { echo 'FAIL: candidate not rolled back before persistence' >&2; exit 1; }
PROBE_OK=1; REBUILD_COUNT=0
verify_selected_doh || { echo 'FAIL: validated general plus regional slot rejected' >&2; exit 1; }
watchdog_apply_slot_candidate 1 candidate clean old clean || { echo 'FAIL: validated replacement rejected' >&2; exit 1; }
[ "$SLOT_1" = candidate ] && [ "$SAVED" -eq 1 ] || exit 1
DNS_SELECTION_CATEGORY=clean; PROBE_OK=0
verify_selected_doh || { echo 'FAIL: existing profile behavior changed' >&2; exit 1; }
echo 'OK: DNSSEC gates reject unverified general candidates without changing regional behavior'
