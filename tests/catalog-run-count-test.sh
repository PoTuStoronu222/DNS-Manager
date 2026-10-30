#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^test_dns_catalog\(\) \(/ {p=1} p {print} p && /^\)$/ {exit}' dns-manager.sh > "$tmp/catalog-run.sh"
. "$tmp/catalog-run.sh"
TMP_DIR="$tmp"; DNS_CATALOG="$tmp/catalog"; TEST_RESULTS="$tmp/results"; TEST_RESULTS_META="$tmp/meta"
HAS_CURL=yes; TEST_BATCH_DEFAULT=2; TEST_BATCH=2; TEST_PROGRESS_EVERY=2
C_WHITE= C_CYAN= C_GREEN= C_YELLOW= C_NC=
acquire_test_lock() { :; }
release_test_lock() { :; }
warn_msg() { :; }
log_tx() { :; }
dns_catalog_version() { printf '%s' test; }
file_hash() { cksum "$1" | awk '{print $1 ":" $2}'; }
test_one_dns() { printf '%s|clean|Test|10|OK\n' "$1" > "$TMP_DIR/t.$1"; }
for count in 3 12 5; do
    : > "$DNS_CATALOG"
    i=1
    while [ "$i" -le "$count" ]; do
        printf 'dns%s|clean|tag|DNS %s|https://dns%s.example/query\n' "$i" "$i" "$i" >> "$DNS_CATALOG"
        i=$((i+1))
    done
    test_dns_catalog > "$tmp/output"
    [ "$(wc -l < "$TEST_RESULTS" | tr -d ' ')" = "$count" ]
    grep -Fxq "catalog_count=$count" "$TEST_RESULTS_META"
    grep -Fq "проверено 0 из $count" "$tmp/output"
    grep -Fq "Всего: $count" "$tmp/output"
done
printf '%s\n' 'OK: full DNS checks follow growing and shrinking catalog counts'
