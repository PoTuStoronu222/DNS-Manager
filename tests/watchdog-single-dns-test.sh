#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^watchdog_slot_target_run\(\) \{/,/^watchdog_service_recover_run\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/target.sh"
. "$tmp/target.sh"
TMP_DIR="$tmp"
awk '/^watchdog_probe_single_candidate\(\) \(/ {p=1} p {print} p && /^\)$/ {exit}' dns-manager.sh > "$tmp/probe.sh"
. "$tmp/probe.sh"
HAS_CURL=yes BOOTSTRAP_DNS='1.1.1.1,8.8.8.8,9.9.9.9,4.4.4.4'
test_one_dns() { printf '%s\n' "$BOOTSTRAP_DNS" > "$tmp/probe-bootstrap"; printf '%s\n' "$1" > "$TMP_DIR/t.$1"; return "${PROBE_FAIL:-0}"; }
watchdog_probe_single_candidate candidate || exit 1
[ "$(cat "$tmp/probe-bootstrap")" = '1.1.1.1,8.8.8.8,9.9.9.9' ] || exit 2
[ ! -e "$tmp/t.candidate" ] && [ -z "$(find "$tmp" -maxdepth 1 -name 'wd-single-probe.*' -print)" ] || exit 3
PROBE_FAIL=1
if watchdog_probe_single_candidate candidate; then exit 4; fi
[ -z "$(find "$tmp" -maxdepth 1 -name 'wd-single-probe.*' -print)" ] || exit 5
PROBE_FAIL=0
WATCHDOG_ENABLED=1 WATCHDOG_AUTOREPLACE=1
SLOT_1=old SLOT_2= SLOT_3= SLOT_4= SLOT_5= SLOT_6= SLOT_RU= PORT_1=5053
WD_SINGLE_TRIED_1=
MODE=ok CHECKS=0 APPLY=0 PROBES=0 LOADS=0
dns_cat() { if [ "$MODE" = custom ]; then printf custom; else printf clean; fi; }
dns_name() { printf '%s' "$1"; }
dns_url() { printf 'https://%s.example/dns-query' "$1"; }
normalize_url() { printf '%s' "$1"; }
watchdog_resource_guard() { return 0; }
acquire_mutation_lock() { return 0; }
release_mutation_lock() { return 0; }
load_config() { LOADS=$((LOADS+1)); [ "$MODE" != changed ] || [ "$LOADS" -lt 2 ] || SLOT_1=new; [ "$MODE" != disabled ] || [ "$LOADS" -lt 2 ] || WATCHDOG_AUTOREPLACE=0; return 0; }
watchdog_slot_config_matches() { [ "$SLOT_1" = "$2" ] && [ "$PORT_1" = "$3" ]; }
watchdog_check_slot() { CHECKS=$((CHECKS+1)); [ "$MODE" = recovered ] && [ "$CHECKS" -ge 2 ]; }
watchdog_common_dns_outage() { case "$MODE" in uncertain) return 2;; *) return 0;; esac; }
watchdog_pick_replacement() {
    [ "$5" = clean ] || return 1
    if ! grep -qxF candidate "$3"; then printf 'candidate|clean\n'
    elif ! grep -qxF candidate2 "$3"; then printf 'candidate2|clean\n'
    fi
}
watchdog_probe_single_candidate() { PROBES=$((PROBES+1)); [ "$MODE" != offline ]; }
watchdog_apply_slot_candidate() { APPLY=$((APPLY+1)); [ "$MODE" != rollback ]; }
log_msg() { :; }
reset_case() { SLOT_1=old SLOT_2= PORT_1=5053 WATCHDOG_ENABLED=1 WATCHDOG_AUTOREPLACE=1 WD_SINGLE_TRIED_1= CHECKS=0 APPLY=0 PROBES=0 LOADS=0; }
reset_case; MODE=offline
if watchdog_slot_target_run 1 old 5053 single; then exit 11; fi
[ "$PROBES" = 1 ] && [ "$APPLY" = 0 ] && [ "$SLOT_1" = old ] || exit 12
if watchdog_slot_target_run 1 old 5053 single; then exit 27; fi
[ "$PROBES" = 2 ] && [ "$APPLY" = 0 ] && printf '%s\n' "$WD_SINGLE_TRIED_1" | grep -qxF candidate2 || exit 28
reset_case; MODE=ok
watchdog_slot_target_run 1 old 5053 single || exit 13
[ "$PROBES" = 1 ] && [ "$APPLY" = 1 ] || exit 14
reset_case; MODE=uncertain
if watchdog_slot_target_run 1 old 5053 single; then exit 15; fi
[ "$PROBES" = 0 ] && [ "$APPLY" = 0 ] || exit 16
reset_case; MODE=changed
if watchdog_slot_target_run 1 old 5053 single; then exit 17; fi
[ "$PROBES" = 1 ] && [ "$APPLY" = 0 ] || exit 18
reset_case; MODE=disabled
if watchdog_slot_target_run 1 old 5053 single; then exit 29; fi
[ "$PROBES" = 1 ] && [ "$APPLY" = 0 ] || exit 30
reset_case; MODE=custom
if watchdog_slot_target_run 1 old 5053 single; then exit 31; fi
[ "$PROBES" = 0 ] && [ "$APPLY" = 0 ] || exit 32
reset_case; MODE=recovered
watchdog_slot_target_run 1 old 5053 single || exit 19
[ "$PROBES" = 1 ] && [ "$APPLY" = 0 ] || exit 20
reset_case; MODE=ok; WATCHDOG_AUTOREPLACE=0
if watchdog_slot_target_run 1 old 5053 single; then exit 21; fi
[ "$PROBES" = 0 ] && [ "$APPLY" = 0 ] || exit 22
reset_case; MODE=ok; SLOT_2=other
if watchdog_slot_target_run 1 old 5053 single; then exit 23; fi
[ "$PROBES" = 0 ] && [ "$APPLY" = 0 ] || exit 24
reset_case; MODE=rollback
if watchdog_slot_target_run 1 old 5053 single; then exit 25; fi
[ "$PROBES" = 1 ] && [ "$APPLY" = 1 ] && [ "$SLOT_1" = old ] || exit 26
printf '%s\n' 'OK: single-DNS replacement requires a confirmed independent candidate'
