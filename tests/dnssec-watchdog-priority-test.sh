#!/bin/sh
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
for fn in dnssec_candidate_eligible watchdog_pick_replacement; do awk -v f="$fn" '$0==f "() {"{p=1} p{print} p&&/^}/{exit}' dns-manager.sh >> "$t/picker"; done
. "$t/picker"
TMP_DIR="$t"; TEST_RESULTS="$t/results"; DNS_CATALOG="$t/catalog"; DNS_SELECTION_MODE=profile; DNS_SELECTION_CATEGORY=dnssec
cat > "$TEST_RESULTS" <<'EOF'
unknown|clean|Unknown|1|OK
cloudflare_family|family|Family|2|OK
google_clean|clean|Google|10|OK
wikimedia|privacy|Wikimedia|20|OK
EOF
cp "$TEST_RESULTS" "$DNS_CATALOG"; : > "$t/used"; : > "$t/tried"
watchdog_test_results_fresh() { :; }; dns_url() { printf 'https://%s.example/dns-query' "$1"; }; normalize_url() { printf '%s' "$1"; }
WATCHDOG_VERIFIED_ONLY=1
[ "$(watchdog_pick_replacement 1 "$t/used" "$t/tried" 0 clean)" = 'google_clean|clean' ] || { echo 'FAIL: clean preference or DNSSEC eligibility' >&2; exit 1; }
printf 'google_clean\n' > "$t/tried"
[ -z "$(watchdog_pick_replacement 1 "$t/used" "$t/tried" 0 clean || true)" ] || exit 1
[ "$(watchdog_pick_replacement 1 "$t/used" "$t/tried" 0 privacy)" = 'wikimedia|privacy' ] || exit 1
[ -z "$(watchdog_pick_replacement 1 "$t/used" "$t/tried" 0 family || true)" ] || { echo 'FAIL: family candidate admitted' >&2; exit 1; }

awk '/^watchdog_slot_target_run\(\) \{/,/^watchdog_service_recover_run\(\) \{/' dns-manager.sh | sed '$d' > "$t/target"
. "$t/target"
STATE_DIR="$t"; SLOT_1=old; SLOT_2=; SLOT_3=; SLOT_4=; SLOT_5=; SLOT_6=; SLOT_RU=; PORT_1=5053
WATCHDOG_ENABLED=1; WATCHDOG_AUTOREPLACE=1; WD_SINGLE_TRIED_1=''; WD_CATEGORY_STALE_1=0; WD_DNSSEC_CATEGORY_1=''; APPLIED=0; MODE=normal
dns_cat() { case "$1" in old) if [ "$MODE" = custom ]; then printf custom; else printf family; fi;; wikimedia) printf privacy;; *) printf clean;; esac; }
dns_name() { printf '%s' "$1"; }; watchdog_resource_guard() { :; }; acquire_mutation_lock() { :; }; release_mutation_lock() { :; }; load_config() { :; }
watchdog_slot_config_matches() { [ "$SLOT_1" = "$2" ] && [ "$PORT_1" = "$3" ]; }
watchdog_check_slot() { return 1; }; watchdog_common_dns_outage() { [ "$MODE" != unknown ] || return 2; case "$MODE" in multi_ok|rollback) return 1;; *) return 0;; esac; }
watchdog_select_category_results() { WD_CATEGORY_RESULTS="$t/results"; WD_CATEGORY_META="$t/meta"; }
watchdog_pick_replacement() { case "$5" in privacy) grep -qxF wikimedia "$3" || printf 'wikimedia|privacy\n';; esac; }
watchdog_probe_single_candidate() { [ "$MODE" != down ]; }
watchdog_apply_slot_candidate() { APPLIED=$((APPLIED+1)); [ "$MODE" != rollback ] || return 1; SLOT_1="$2"; }
log_msg() { :; }
if watchdog_slot_target_run 1 old 5053 single; then echo 'FAIL: empty clean category accepted' >&2; exit 1; fi
[ "$WD_DNSSEC_CATEGORY_1" = privacy ] && [ "$SLOT_1" = old ] && [ "$APPLIED" = 0 ] || exit 1
watchdog_slot_target_run 1 old 5053 single || exit 1
[ "$SLOT_1" = wikimedia ] && [ "$APPLIED" = 1 ] || { echo 'FAIL: privacy fallback' >&2; exit 1; }
SLOT_1=old; WD_DNSSEC_CATEGORY_1=privacy; WD_SINGLE_TRIED_1=''; MODE=down; APPLIED=0
if watchdog_slot_target_run 1 old 5053 single; then exit 1; fi
[ "$SLOT_1" = old ] && [ "$APPLIED" = 0 ] || { echo 'FAIL: offline candidate changed DNS' >&2; exit 1; }
MODE=unknown; if watchdog_slot_target_run 1 old 5053 single; then exit 1; fi
[ "$SLOT_1" = old ] && [ "$APPLIED" = 0 ] || exit 1
MODE=custom; WD_DNSSEC_CATEGORY_1=privacy; WD_SINGLE_TRIED_1=''; if watchdog_slot_target_run 1 old 5053 single; then exit 1; fi
[ "$SLOT_1" = old ] && [ "$APPLIED" = 0 ] || { echo 'FAIL: custom DNS was automatically replaced' >&2; exit 1; }
MODE=normal; SLOT_2=other; if watchdog_slot_target_run 1 old 5053; then exit 1; fi
[ "$SLOT_1" = old ] && [ "$APPLIED" = 0 ] || { echo 'FAIL: global outage changed DNS' >&2; exit 1; }
MODE=rollback; WD_DNSSEC_CATEGORY_1=privacy; WD_SINGLE_TRIED_1=''; WD_CATEGORY_STALE_1=0; if watchdog_slot_target_run 1 old 5053; then exit 1; fi
[ "$SLOT_1" = old ] && [ "$APPLIED" = 1 ] || { echo 'FAIL: failed multi-DNS replacement did not preserve selection' >&2; exit 1; }
MODE=multi_ok; WD_DNSSEC_CATEGORY_1=privacy; WD_SINGLE_TRIED_1=''; WD_CATEGORY_STALE_1=0; APPLIED=0; watchdog_slot_target_run 1 old 5053 || exit 1
[ "$SLOT_1" = wikimedia ] && [ "$APPLIED" = 1 ] || { echo 'FAIL: multi-DNS privacy fallback' >&2; exit 1; }
echo 'OK: DNSSEC replacement prefers clean, then privacy, rejects family and preserves DNS on outage'
