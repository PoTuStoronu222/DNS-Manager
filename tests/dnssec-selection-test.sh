#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
for fn in dnssec_candidate_eligible watchdog_scope_category watchdog_desired_cat watchdog_target_live_count; do
    awk -v fn="$fn" '$0==fn "() {"{f=1} f{print} f && /^}/{exit}' dns-manager.sh >> "$tmp/functions"
done
awk '/^auto_fill_slots\(\) \{/,/^select_slot\(\) \{/' dns-manager.sh | sed '$d' >> "$tmp/functions"
. "$tmp/functions"
TMP_DIR="$tmp"; TEST_RESULTS="$tmp/results"; DNS_SELECTION_MODE=profile; DNS_SELECTION_CATEGORY=dnssec
SLOT_1=''; SLOT_2=''; SLOT_3=''; SLOT_4=''; SLOT_5=''; SLOT_6=''; SLOT_RU=region
cat > "$TEST_RESULTS" <<'EOF_RESULTS'
nonvalidator|clean|Fast unknown|1|OK
cloudflare_clean|clean|Cloudflare|20|OK
google_clean|clean|Google|30|OK
adguard_default|adblock|AdGuard|40|FAIL
region|regional|Regional|2|OK
EOF_RESULTS
ensure_test_results_fresh() { [ "$1" = all ]; }
dns_url() { printf 'https://%s.example/dns-query' "$1"; }
normalize_url() { printf '%s' "$1"; }
slot_set() { eval "SLOT_$1=\$2"; }
slot_cat_set() { eval "SLOT_${1}_CAT=\$2"; }
warn_msg() { :; }; pause() { :; }
dns_cat() { case "$1" in cloudflare_clean|google_clean) printf clean;; region) printf regional;; esac; }
watchdog_check_slot() { :; }
auto_fill_slots dnssec || { echo 'FAIL: candidate selection failed' >&2; exit 1; }
[ "$SLOT_1" = cloudflare_clean ] && [ "$SLOT_2" = google_clean ] && [ -z "$SLOT_3" ] || { echo 'FAIL: wrong candidates selected' >&2; exit 1; }
[ "$SLOT_RU" = region ] || { echo 'FAIL: regional slot changed' >&2; exit 1; }
[ "$(watchdog_scope_category)" = dnssec ] || exit 1
[ "$(watchdog_desired_cat 1)" = clean ] || exit 1
[ "$(watchdog_desired_cat RU)" = regional ] || exit 1
[ "$(watchdog_target_live_count)" = 2 ] || exit 1
if dnssec_candidate_eligible nonvalidator; then echo 'FAIL: unobserved candidate admitted' >&2; exit 1; fi
# Exercise actual profile application orchestration with mocked service apply.
awk '/^profile_apply_begin\(\) \{/,/^menu_category_select\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/profile"
. "$tmp/profile"
NTP_IP_FALLBACK=0; FORCE_DOH=0; DNSMASQ_PERF=0; WATCHDOG_ENABLED=0
HYBRID_PORT_1=5053; HYBRID_PORT_2=5054; HYBRID_PORT_3=5055
HYBRID_PORT_4=5056; HYBRID_PORT_5=5057; HYBRID_PORT_6=5058
SLOT_RU=region; SLOT_RU_CAT=regional; PORT_RU=5059; TLD_RU_ENABLED=1
TEST_SCOPE=''; APPLIED=0
test_dns_catalog() { TEST_SCOPE="$1"; }
auto_fill_slots() { [ "$1" = dnssec ] || return 1; SLOT_1=cloudflare_clean; SLOT_RU=wrong; PORT_RU=1; TLD_RU_ENABLED=0; }
apply_settings() {
    [ "$DNS_SELECTION_MODE" = profile ] && [ "$DNS_SELECTION_CATEGORY" = dnssec ] &&
    [ "$SLOT_RU" = region ] && [ "$PORT_RU" = 5059 ] && [ "$TLD_RU_ENABLED" = 1 ] || return 1
    APPLIED=1
}
apply_profile_now dnssec || { echo 'FAIL: profile orchestration failed' >&2; exit 1; }
[ "$TEST_SCOPE" = all ] && [ "$APPLIED" = 1 ] || exit 1
echo 'OK: DNSSEC candidate pool is separate from categories and preserves regional selection'
