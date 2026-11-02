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
mkdir "$tmp/bin"
cat > "$tmp/bin/nslookup" <<'EOF_NSLOOKUP'
#!/bin/sh
printf 'Server: %s\nAddress: %s\n\nName: example.com\nAddress: 203.0.113.7\n' "$2" "$2"
EOF_NSLOOKUP
chmod +x "$tmp/bin/nslookup"
PATH="$tmp/bin:$PATH"; export PATH
HAS_DIG=no
test_one_dns() { resolve_host_fallback example.com > "$tmp/probe-resolved"; }
watchdog_probe_single_candidate candidate || exit 6
[ "$(cat "$tmp/probe-resolved")" = 203.0.113.7 ] || exit 7
HAS_DIG=yes
WATCHDOG_ENABLED=1 WATCHDOG_AUTOREPLACE=1
SLOT_1=old SLOT_2= SLOT_3= SLOT_4= SLOT_5= SLOT_6= SLOT_RU= PORT_1=5053
WD_SINGLE_TRIED_1=
MODE=ok CHECKS=0 APPLY=0 PROBES=0 LOADS=0 GUARDS=0 LOCKED=0 LOCKS=0
dns_cat() { if [ "$MODE" = custom ]; then printf custom; else printf clean; fi; }
dns_name() { printf '%s' "$1"; }
dns_url() { if [ "$MODE" = urlchange ] && [ -f "$tmp/urlchanged" ] && [ "$1" = candidate ]; then printf 'https://changed.example/dns-query'; else printf 'https://%s.example/dns-query' "$1"; fi; }
normalize_url() { printf '%s' "$1"; }
watchdog_resource_guard() { GUARDS=$((GUARDS+1)); [ "$MODE" != lowmem ] || [ "$GUARDS" -lt 2 ]; }
acquire_mutation_lock() { LOCKS=$((LOCKS+1)); [ "$MODE" != relock_fail ] || [ "$LOCKS" -lt 2 ] || return 1; LOCKED=1; return 0; }
release_mutation_lock() { LOCKED=0; return 0; }
load_config() { LOADS=$((LOADS+1)); [ "$MODE" != changed ] || [ "$LOADS" -lt 2 ] || SLOT_1=new; [ "$MODE" != disabled ] || [ "$LOADS" -lt 2 ] || WATCHDOG_AUTOREPLACE=0; [ "$MODE" != added ] || [ "$LOADS" -lt 2 ] || SLOT_2=other; return 0; }
watchdog_slot_config_matches() { [ "$SLOT_1" = "$2" ] && [ "$PORT_1" = "$3" ]; }
watchdog_check_slot() { CHECKS=$((CHECKS+1)); [ "$MODE" = recovered ] && [ "$CHECKS" -ge 2 ]; }
watchdog_common_dns_outage() { case "$MODE" in uncertain|multi_unknown) return 2;; multi|multi_norestart|multi_uncertain) return 1;; *) return 0;; esac; }
watchdog_pick_replacement() {
    [ "$5" = clean ] || return 1
    if ! grep -qxF candidate "$3"; then printf 'candidate|clean\n'
    elif ! grep -qxF candidate2 "$3"; then printf 'candidate2|clean\n'
    elif ! grep -qxF candidate3 "$3"; then printf 'candidate3|clean\n'
    elif ! grep -qxF candidate4 "$3"; then printf 'candidate4|clean\n'
    fi
}
watchdog_probe_single_candidate() { [ "$LOCKED" = 0 ] || exit 41; PROBES=$((PROBES+1)); [ "$MODE" != urlchange ] || : > "$tmp/urlchanged"; [ "$MODE" != offline ] && { [ "$MODE" != first_down ] || [ "$1" != candidate ]; } && { [ "$MODE" != late ] || [ "$1" = candidate4 ]; }; }
watchdog_apply_slot_candidate() { APPLY=$((APPLY+1)); [ "$MODE" = multi_norestart ] || WATCHDOG_RESTART_COUNT=$((WATCHDOG_RESTART_COUNT+1)); if [ "$MODE" = multi_uncertain ]; then WATCHDOG_ROLLBACK_UNCERTAIN=1; return 1; fi; [ "$MODE" != rollback ] && [ "$MODE" != multi_norestart ] && { [ "$MODE" != multi ] || [ "$2" = candidate3 ]; }; }
log_msg() { :; }
reset_case() { SLOT_1=old SLOT_2= PORT_1=5053 WATCHDOG_ENABLED=1 WATCHDOG_AUTOREPLACE=1 WD_SINGLE_TRIED_1= CHECKS=0 APPLY=0 PROBES=0 LOADS=0 GUARDS=0 LOCKED=0 LOCKS=0; rm -f "$tmp/urlchanged"; }
reset_case; MODE=offline
if watchdog_slot_target_run 1 old 5053 single; then exit 11; fi
[ "$PROBES" = 3 ] && [ "$APPLY" = 0 ] && [ "$SLOT_1" = old ] || exit 12
if watchdog_slot_target_run 1 old 5053 single; then exit 27; fi
[ "$PROBES" = 4 ] && [ "$APPLY" = 0 ] && [ -z "$WD_SINGLE_TRIED_1" ] || exit 28
reset_case; MODE=ok
watchdog_slot_target_run 1 old 5053 single || exit 13
[ "$PROBES" = 1 ] && [ "$APPLY" = 1 ] || exit 14
reset_case; MODE=first_down
watchdog_slot_target_run 1 old 5053 single || exit 44
[ "$PROBES" = 2 ] && [ "$APPLY" = 1 ] || exit 45
reset_case; MODE=late
if watchdog_slot_target_run 1 old 5053 single; then exit 56; fi
[ "$PROBES" = 3 ] && [ "$APPLY" = 0 ] || exit 57
watchdog_slot_target_run 1 old 5053 single || exit 58
[ "$PROBES" = 4 ] && [ "$APPLY" = 1 ] && [ -z "$WD_SINGLE_TRIED_1" ] || exit 59
reset_case; MODE=multi; SLOT_2=other
if watchdog_slot_target_run 1 old 5053; then exit 46; fi
[ "$APPLY" = 2 ] && printf '%s\n' "$WD_SINGLE_TRIED_1" | grep -qxF candidate2 || exit 47
watchdog_slot_target_run 1 old 5053 || exit 48
[ "$APPLY" = 3 ] && [ -z "$WD_SINGLE_TRIED_1" ] || exit 49
reset_case; MODE=multi_norestart; SLOT_2=other
if watchdog_slot_target_run 1 old 5053; then exit 50; fi
[ "$APPLY" = 2 ] && printf '%s\n' "$WD_SINGLE_TRIED_1" | grep -qxF candidate2 || exit 51
reset_case; MODE=multi_uncertain; SLOT_2=other
if watchdog_slot_target_run 1 old 5053; then exit 60; fi
[ "$APPLY" = 1 ] && [ "$WATCHDOG_ROLLBACK_UNCERTAIN" = 1 ] || exit 61
reset_case; MODE=multi_outage; SLOT_2=other
if watchdog_slot_target_run 1 old 5053; then exit 52; fi
[ "$APPLY" = 0 ] && [ "$PROBES" = 0 ] && [ "$SLOT_1" = old ] || exit 53
reset_case; MODE=multi_unknown; SLOT_2=other
if watchdog_slot_target_run 1 old 5053; then exit 54; fi
[ "$APPLY" = 0 ] && [ "$PROBES" = 0 ] && [ "$SLOT_1" = old ] || exit 55
reset_case; MODE=uncertain
if watchdog_slot_target_run 1 old 5053 single; then exit 15; fi
[ "$PROBES" = 0 ] && [ "$APPLY" = 0 ] || exit 16
reset_case; MODE=changed
if watchdog_slot_target_run 1 old 5053 single; then exit 17; fi
[ "$PROBES" = 1 ] && [ "$APPLY" = 0 ] || exit 18
reset_case; MODE=disabled
if watchdog_slot_target_run 1 old 5053 single; then exit 29; fi
[ "$PROBES" = 1 ] && [ "$APPLY" = 0 ] || exit 30
reset_case; MODE=added
if watchdog_slot_target_run 1 old 5053 single; then exit 33; fi
[ "$PROBES" = 1 ] && [ "$APPLY" = 0 ] || exit 34
reset_case; MODE=urlchange
if watchdog_slot_target_run 1 old 5053 single; then exit 35; fi
[ "$PROBES" = 1 ] && [ "$APPLY" = 0 ] || exit 36
reset_case; MODE=lowmem
if watchdog_slot_target_run 1 old 5053 single; then exit 39; fi
[ "$PROBES" = 1 ] && [ "$APPLY" = 0 ] && [ "$SLOT_1" = old ] || exit 40
reset_case; MODE=relock_fail
if watchdog_slot_target_run 1 old 5053 single; then exit 42; fi
[ "$PROBES" = 1 ] && [ "$APPLY" = 0 ] && [ "$LOCKED" = 0 ] && [ "$SLOT_1" = old ] || exit 43
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
