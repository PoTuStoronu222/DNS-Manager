#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^catalog_validate_file\(\) \{/,/^}/' dns-manager.sh > "$tmp/validate.sh"
awk '/^catalog_migrate_selected_ids\(\) \{/,/^}/' dns-manager.sh > "$tmp/migrate.sh"
awk '/^write_catalogs\(\) \{/,/^}/' dns-manager.sh > "$tmp/update.sh"
. "$tmp/validate.sh"
. "$tmp/migrate.sh"
. "$tmp/update.sh"
DNSCAT_VERSION=$(sed -n "s/^# DNSCATVER=//p" catalogs/dns-8.8-FULL-CONFIG-CLEAN.conf)
DNSCAT_REVISION=$(sed -n "s/^# DNSCATREV=//p" catalogs/dns-8.8-FULL-CONFIG-CLEAN.conf)
CFG_DIR="$tmp/config"; DNS_CATALOG="$CFG_DIR/catalog"; CONFIG_FILE="$CFG_DIR/manager.conf"; TEST_RESULTS="$tmp/results"
PERSIST_STATE_DIR="$tmp/persist"; mkdir -p "$CFG_DIR" "$PERSIST_STATE_DIR"
catalog_download() { cp catalogs/dns-8.8-FULL-CONFIG-CLEAN.conf "$1"; }
log_msg() { :; }; err_msg() { :; }
cp catalogs/dns-8.7-RU-NOSOCIAL.conf "$DNS_CATALOG"
printf "%s\n" "SLOT_1='astracat'" "WATCHDOG_ENABLED='1'" > "$CONFIG_FILE"
cp "$CONFIG_FILE" "$tmp/before"
write_catalogs
catalog_validate_file "$DNS_CATALOG"
cmp "$CONFIG_FILE" "$tmp/before"
# Old IDs survive except the removed duplicate CZ.NIC entries; Shecan may change.
awk -F'|' 'NR==FNR {if ($1 !~ /^#/ && NF>=5 && $1!="cznic_odvr" && $1!="cznic_odvr_doh") {url[$1]=$5; count++}; next}
  $1 in url {if ($1!="shecan" && $5!=url[$1]) bad=1; seen++}
  END {exit (bad || seen!=count)}' catalogs/dns-8.7-RU-NOSOCIAL.conf "$DNS_CATALOG"
# The formerly shared Zapret endpoint moves selected slots to the new ID.
awk -F'|' 'BEGIN{OFS="|"} $1=="shecan" {$5="https://dns.zapret.moe/dns-query"} {print}' catalogs/dns-8.7-RU-NOSOCIAL.conf > "$tmp/legacy"
printf "%s\n" "SLOT_1='shecan'" "WATCHDOG_ENABLED='1'" > "$CONFIG_FILE"
catalog_migrate_selected_ids "$tmp/legacy" "$DNS_CATALOG"
grep -qx "SLOT_1='zapret_moe'" "$CONFIG_FILE"
grep -qx "WATCHDOG_ENABLED='1'" "$CONFIG_FILE"
awk -F'|' '$5 ~ /^https:\/\/odvr[.]nic[.]cz\// {n++; if ($5 != "https://odvr.nic.cz/dns-query" || $4 != "CZ.NIC ODVR [CZ]") bad=1} END {exit (bad || n != 1)}' "$DNS_CATALOG"
cp "$tmp/before" "$CONFIG_FILE"
# An unavailable source must retain the usable old catalogue and settings.
cp catalogs/dns-8.7-RU-NOSOCIAL.conf "$DNS_CATALOG"
catalog_download() { return 1; }
write_catalogs
cmp catalogs/dns-8.7-RU-NOSOCIAL.conf "$DNS_CATALOG"
cmp "$CONFIG_FILE" "$tmp/before"
printf 'OK: current catalog upgrade and fallback preserve settings\n'
