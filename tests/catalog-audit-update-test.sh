#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^catalog_validate_file\(\) \{/,/^}/' dns-manager.sh > "$tmp/validate.sh"
awk '/^write_catalogs\(\) \{/,/^}/' dns-manager.sh > "$tmp/update.sh"
. "$tmp/validate.sh"
. "$tmp/update.sh"
DNSCAT_VERSION=8.7-RU-NOSOCIAL DNSCAT_REVISION=8
CFG_DIR="$tmp/config"; DNS_CATALOG="$CFG_DIR/catalog"; TEST_RESULTS="$tmp/results"
PERSIST_STATE_DIR="$tmp/persist"; mkdir -p "$CFG_DIR" "$PERSIST_STATE_DIR"
catalog_download() { cp catalogs/dns-8.7-RU-NOSOCIAL.conf "$1"; }
log_msg() { :; }
err_msg() { :; }
# Reconstruct the prior catalogue while preserving every original ID and URL.
awk -F'|' '
  /^# DNSCATREV=/ {$0="# DNSCATREV=7"}
  /^# ENTRIES=/ {$0="# ENTRIES=107"}
  $1 ~ /^(malw_cloudflare|geohide_ru|geohide_eu|geohide_us|magicdns|wlrus|geodema)$/ {next}
  {print}
' catalogs/dns-8.7-RU-NOSOCIAL.conf > "$DNS_CATALOG"
cp "$DNS_CATALOG" "$tmp/old"
printf '%s\n' 'astracat|bypass|AstraCat DNS|20|OK' 'shecan|bypass|Zapret DNS|25|OK' > "$TEST_RESULTS"
write_catalogs
catalog_validate_file "$DNS_CATALOG"
for id in malw_cloudflare geohide_ru geohide_eu geohide_us magicdns wlrus geodema; do
    grep -q "^$id|" "$DNS_CATALOG"
done
# The old slot identities, categories and endpoints remain untouched.
awk -F'|' 'NR==FNR {if ($1 !~ /^#/ && NF>=5) {cat[$1]=$2; url[$1]=$5; count++}; next}
  $1 !~ /^#/ && NF>=5 && ($1 in url) {if ($2 != cat[$1] || $5 != url[$1]) bad=1; seen++}
  END {exit (bad || seen != count || count != 107)}' "$tmp/old" "$DNS_CATALOG"
grep -q '^astracat|.*|OK$' "$TEST_RESULTS"
grep -q '^shecan|.*|OK$' "$TEST_RESULTS"
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
printf '%s\n' 'OK: catalog upgrade preserves existing IDs, URLs and fallback'
