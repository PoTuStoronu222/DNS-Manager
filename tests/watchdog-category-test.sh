#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
for fn in test_results_max_age_for_category watchdog_test_results_fresh watchdog_select_category_results watchdog_merge_category_results; do
    awk -v fn="$fn" '$0==fn "() {" {p=1} p {print} p && /^}$/ {exit}' dns-manager.sh >> "$tmp/functions.sh"
done
awk '/^watchdog_refresh_category_results\(\) \(/ {p=1} p {print} p && /^\)$/ {exit}' dns-manager.sh >> "$tmp/functions.sh"
awk '/^test_dns_catalog\(\) \(/ {p=1} p {print} p && /^\)$/ {exit}' dns-manager.sh >> "$tmp/functions.sh"
awk '/^watchdog_pick_replacement\(\) \{/,/^watchdog_apply_slot_candidate\(\) \{/' dns-manager.sh | sed '$d' >> "$tmp/functions.sh"
. "$tmp/functions.sh"
STATE_DIR="$tmp/state"; TMP_DIR="$tmp/work"; DNS_CHECK_STAMP_DIR="$tmp/checks"; mkdir -p "$STATE_DIR" "$TMP_DIR" "$DNS_CHECK_STAMP_DIR"
DNS_CATALOG="$tmp/catalog"; TEST_RESULTS="$STATE_DIR/dns-test-results.conf"; TEST_RESULTS_META="$STATE_DIR/dns-test-results.meta"
cat > "$DNS_CATALOG" <<'EOF_CATALOG'
# DNSCATVER=test
slow|clean|tag|Slow|https://slow.example/query|global|ok
fast|clean|tag|Fast|https://fast.example/query|global|ok
ru|regional|tag|RU|https://ru.example/query|ru|ok
ads|adblock|tag|Ads|https://ads.example/query|global|ok
EOF_CATALOG
printf '%s\n' 'untouched|other|Untouched|11|OK' 'slow|clean|Newer|7|OK' > "$TEST_RESULTS"
printf 'timestamp=1\ntest_scope=all\n' > "$TEST_RESULTS_META"
printf '%s\n' "$(($(date +%s)+60))" > "$DNS_CHECK_STAMP_DIR/slow"
HAS_CURL=yes HAS_DIG=yes BOOTSTRAP_DNS='1.1.1.1,8.8.8.8'
TEST_BATCH_DEFAULT=2 TEST_PROGRESS_EVERY=2 TEST_RESULTS_MAX_AGE=21600
C_WHITE= C_CYAN= C_GREEN= C_YELLOW= C_NC=
acquire_test_lock() { [ "${LOCK_BUSY:-0}" != 1 ]; }
release_test_lock() { :; }
warn_msg() { :; }
log_tx() { :; }
category_ru() { printf '%s' "$1"; }
dns_catalog_version() { printf test; }
file_hash() { cksum "$1" | awk '{print $1 ":" $2}'; }
count_dns() { grep -c '|' "$DNS_CATALOG"; }
dns_url() { awk -F'|' -v id="$1" '$1==id {print $5;exit}' "$DNS_CATALOG"; }
normalize_url() { printf '%s' "$1"; }
watchdog_scope_category() { printf clean; }
watchdog_desired_cat() { printf clean; }
test_one_dns() {
    case "$1" in slow) _ms=80; _cat=clean;; fast) _ms=20; _cat=clean;; ru) _ms=50; _cat=regional;; *) _ms=40; _cat=adblock;; esac
    if [ "${MODE:-ok}" = offline ]; then printf '%s|%s|name|-1|FAIL\n' "$1" "$_cat" > "$TMP_DIR/t.$1"; return 1; fi
    printf '%s|%s|name|%s|OK\n' "$1" "$_cat" "$_ms" > "$TMP_DIR/t.$1"
}
watchdog_refresh_category_results clean || exit 1
grep -Fxq 'untouched|other|Untouched|11|OK' "$TEST_RESULTS" || exit 2
grep -Fxq 'slow|clean|Newer|7|OK' "$TEST_RESULTS" || exit 3
grep -Fxq 'fast|clean|name|20|OK' "$TEST_RESULTS" || exit 20
grep -Fxq 'timestamp=1' "$TEST_RESULTS_META" || exit 21
[ -s "$DNS_CHECK_STAMP_DIR/fast" ] && [ -s "$DNS_CHECK_STAMP_DIR/ru" ] || exit 22
[ "$(cat "$DNS_CHECK_STAMP_DIR/fast")" = "$(sed -n 's/^timestamp=//p' "$STATE_DIR/watchdog-category-clean.meta")" ] || exit 26
grep -Fxq 'test_scope=clean' "$STATE_DIR/watchdog-category-clean.meta" || exit 4
[ "$(wc -l < "$STATE_DIR/watchdog-category-clean.results" | tr -d ' ')" = 3 ] || exit 5
watchdog_select_category_results clean || exit 6
[ "$WD_CATEGORY_RESULTS" = "$STATE_DIR/watchdog-category-clean.results" ] || exit 7
TEST_RESULTS="$WD_CATEGORY_RESULTS"; TEST_RESULTS_META="$WD_CATEGORY_META"
: > "$tmp/used"; : > "$tmp/tried"; WATCHDOG_VERIFIED_ONLY=1
[ "$(watchdog_pick_replacement 1 "$tmp/used" "$tmp/tried" 0 clean)" = 'fast|clean' ] || exit 8
printf 'fast\n' > "$tmp/tried"
[ "$(watchdog_pick_replacement 1 "$tmp/used" "$tmp/tried" 0 clean)" = 'slow|clean' ] || exit 9
printf 'slow\n' >> "$tmp/tried"
if watchdog_pick_replacement 1 "$tmp/used" "$tmp/tried" 0 clean; then exit 10; fi
watchdog_refresh_category_results regional || exit 11
grep -Fxq 'test_scope=regional' "$STATE_DIR/watchdog-category-regional.meta" || exit 12
[ "$(wc -l < "$STATE_DIR/watchdog-category-regional.results" | tr -d ' ')" = 1 ] || exit 13
# A newer completed manual check must not be replaced by an older background scan.
_before="$(cksum "$STATE_DIR/dns-test-results.conf")"
printf 'timestamp=%s\ntest_scope=all\n' "$(($(date +%s)+60))" > "$STATE_DIR/dns-test-results.meta"
watchdog_merge_category_results "$STATE_DIR/watchdog-category-clean.results" "$STATE_DIR/watchdog-category-clean.meta" clean || exit 23
[ "$(cksum "$STATE_DIR/dns-test-results.conf")" = "$_before" ] || exit 24
LOCK_BUSY=1
if watchdog_merge_category_results "$STATE_DIR/watchdog-category-clean.results" "$STATE_DIR/watchdog-category-clean.meta" clean; then exit 25; fi
LOCK_BUSY=0
cat > "$tmp/manual" <<'EOF_FULL_RESULTS'
slow|clean|Slow|80|OK
fast|clean|Fast|20|OK
ru|regional|RU|50|OK
ads|adblock|Ads|40|OK
EOF_FULL_RESULTS
_now="$(date +%s)"
printf 'timestamp=%s\ncatalog_version=test\ncatalog_count=4\ncatalog_hash=%s\ntest_scope=all\n' "$_now" "$(file_hash "$DNS_CATALOG")" > "$tmp/manual.meta"
TEST_RESULTS="$tmp/manual"; TEST_RESULTS_META="$tmp/manual.meta"
watchdog_select_category_results clean || exit 16
[ "$WD_CATEGORY_RESULTS" = "$tmp/manual" ] || exit 17
TEST_RESULTS_MAX_AGE_CLEAN=60
printf 'timestamp=%s\ncatalog_version=test\ncatalog_count=4\ncatalog_hash=%s\ntest_scope=all\n' "$((_now-61))" "$(file_hash "$DNS_CATALOG")" > "$tmp/manual.meta"
watchdog_select_category_results clean || exit 18
[ "$WD_CATEGORY_RESULTS" = "$STATE_DIR/watchdog-category-clean.results" ] || exit 19
MODE=offline
if watchdog_refresh_category_results clean; then exit 14; fi
TEST_RESULTS="$STATE_DIR/watchdog-category-clean.results"; TEST_RESULTS_META="$STATE_DIR/watchdog-category-clean.meta"
if watchdog_select_category_results clean; then exit 15; fi
printf '%s\n' 'OK: isolated category checks rank verified DNS and preserve manual results'
