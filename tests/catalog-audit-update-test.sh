#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^catalog_validate_file\(\) \{/,/^}/' dns-manager.sh > "$tmp/validate.sh"
awk '/^write_catalogs\(\) \{/,/^}/' dns-manager.sh > "$tmp/update.sh"
. "$tmp/validate.sh"
. "$tmp/update.sh"
DNSCAT_VERSION=8.7-RU-NOSOCIAL DNSCAT_REVISION=12
CFG_DIR="$tmp/config"; DNS_CATALOG="$CFG_DIR/catalog"; TEST_RESULTS="$tmp/results"
PERSIST_STATE_DIR="$tmp/persist"; mkdir -p "$CFG_DIR" "$PERSIST_STATE_DIR"
catalog_download() { cp catalogs/dns-8.7-RU-NOSOCIAL.conf "$1"; }
log_msg() { :; }
err_msg() { :; }
# Reconstruct the prior catalogue while preserving every original ID and URL.
awk -F'|' '
  /^# DNSCATREV=/ {$0="# DNSCATREV=7"}
  /^# ENTRIES=/ {$0="# ENTRIES=107"}
  $1 ~ /^(malw_cloudflare|geohide_eu|geohide_us|magicdns|wlrus|geodema)$/ {next}
  $1=="cznic_odvr" {sub(/\|clean\|/, "|security|")}
  $1=="iijjp" {sub(/\|privacy\|/, "|family|")}
  {print}
' catalogs/dns-8.7-RU-NOSOCIAL.conf > "$DNS_CATALOG"
cp "$DNS_CATALOG" "$tmp/old"
printf '%s\n' 'astracat|bypass|AstraCat DNS|20|OK' 'shecan|bypass|Zapret DNS|25|OK' > "$TEST_RESULTS"
write_catalogs
catalog_validate_file "$DNS_CATALOG"
for id in malw_cloudflare geohide_eu geohide_us magicdns wlrus geodema; do
    grep -q "^$id|" "$DNS_CATALOG"
done
# The old identities and endpoints remain untouched. Only two categories are corrected.
awk -F'|' 'NR==FNR {if ($1 !~ /^#/ && NF>=5) {cat[$1]=$2; url[$1]=$5; count++}; next}
  $1 !~ /^#/ && NF>=5 && ($1 in url) {
    if ($5 != url[$1]) bad=1
    if ($2 != cat[$1] && !($1=="cznic_odvr" && $2=="clean" && cat[$1]=="security") && !($1=="iijjp" && $2=="privacy" && cat[$1]=="family")) bad=1
    seen++
  }
  END {exit (bad || seen != count || count != 107)}' "$tmp/old" "$DNS_CATALOG"
grep -q '^astracat|.*|OK$' "$TEST_RESULTS"
grep -q '^shecan|.*|OK$' "$TEST_RESULTS"
# Revision 10 -> 11 changes the visible Comss Router label only.
awk -F'|' 'BEGIN {OFS="|"} /^# DNSCATREV=/ {$0="# DNSCATREV=10"} $1=="comss_adblock_bypass" {$4="Comss.one Router (блокировка рекламы)"} {print}' catalogs/dns-8.7-RU-NOSOCIAL.conf > "$DNS_CATALOG"
printf '%s\n' 'comss_adblock_bypass|bypass|Comss.one Router|25|OK' > "$TEST_RESULTS"
write_catalogs
awk -F'|' '$1=="comss_adblock_bypass" {if ($2!="bypass" || $4!="Comss Router · без рекламы" || $5!="https://router.comss.one/dns-query") exit 1; found=1} END {if (!found) exit 1}' "$DNS_CATALOG"
grep -q '^comss_adblock_bypass|.*|OK$' "$TEST_RESULTS"
# Revision 12 changes MagicDNS's endpoint while keeping its ID and category.
awk -F'|' 'BEGIN {OFS="|"} /^# DNSCATREV=/ {$0="# DNSCATREV=11"} $1=="magicdns" {$5="https://dns.magicdns.ru/dns-query"} {print}' catalogs/dns-8.7-RU-NOSOCIAL.conf > "$DNS_CATALOG"
printf '%s\n' 'magicdns|bypass|MagicDNS|20|OK' 'astracat|bypass|AstraCat|25|OK' > "$TEST_RESULTS"
cp "$TEST_RESULTS" "$PERSIST_STATE_DIR/dns-test-results.conf"
write_catalogs
awk -F'|' '$1=="magicdns" {if ($2!="bypass" || $5!="https://api.magicdns.ru/sync") exit 1; found=1} END {if (!found) exit 1}' "$DNS_CATALOG"
for result in "$TEST_RESULTS" "$PERSIST_STATE_DIR/dns-test-results.conf"; do
    ! grep -q '^magicdns|' "$result"
    grep -q '^astracat|' "$result"
done
# On download failure, a compatible old catalogue is retained.
cp "$tmp/old" "$DNS_CATALOG"
catalog_download() { return 1; }
write_catalogs
cmp -s "$tmp/old" "$DNS_CATALOG"
# The LuCI updater must not replace a newer installed revision with main's
# older catalogue while a test branch is installed.
awk '/^update_catalog_direct\(\) \{/,/^}/' dns-manager-luci.sh > "$tmp/luci-update.sh"
. "$tmp/luci-update.sh"
TMP_ROOT="$tmp"; CATALOG_FILE="$tmp/luci-catalog"
cp catalogs/dns-8.7-RU-NOSOCIAL.conf "$CATALOG_FILE"
fetch_raw_url() { cp "$tmp/old" "$1"; }
catalog_version() { sed -n 's/^# DNSCATVER=//p' "$CATALOG_FILE" | head -n1; }
catalog_revision() { sed -n 's/^# DNSCATREV=//p' "$CATALOG_FILE" | head -n1; }
if update_catalog_direct; then exit 1; else rc=$?; fi
[ "$rc" = 2 ] && cmp -s catalogs/dns-8.7-RU-NOSOCIAL.conf "$CATALOG_FILE"
# LuCI catalog-only updates also discard results for the old endpoint.
awk -F'|' 'BEGIN {OFS="|"} /^# DNSCATREV=/ {$0="# DNSCATREV=11"} $1=="magicdns" {$5="https://dns.magicdns.ru/dns-query"} {print}' catalogs/dns-8.7-RU-NOSOCIAL.conf > "$CATALOG_FILE"
STATE_DIR="$tmp/state"; CHECK_DIR="$tmp/check"; mkdir -p "$STATE_DIR" "$CHECK_DIR"
printf '%s\n' 'magicdns|bypass|MagicDNS|20|OK' 'astracat|bypass|AstraCat|25|OK' > "$STATE_DIR/dns-test-results.conf"
cp "$STATE_DIR/dns-test-results.conf" "$PERSIST_STATE_DIR/dns-test-results.conf"
touch "$CHECK_DIR/magicdns"
fetch_raw_url() { cp catalogs/dns-8.7-RU-NOSOCIAL.conf "$1"; }
update_catalog_direct
for result in "$STATE_DIR/dns-test-results.conf" "$PERSIST_STATE_DIR/dns-test-results.conf"; do
    ! grep -q '^magicdns|' "$result"
    grep -q '^astracat|' "$result"
done
[ ! -e "$CHECK_DIR/magicdns" ]
printf '%s\n' 'OK: catalog upgrade preserves existing IDs, URLs and fallback'
