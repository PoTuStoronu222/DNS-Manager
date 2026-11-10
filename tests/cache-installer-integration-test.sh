#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
sh -n dns-manager-luci.sh
sh -n dns-manager.sh
check() {
    marker=$1; source=$2
    awk -v m="$marker" '$0 ~ "<<\047"m"\047$" {capture=1;next} capture && $0==m {exit} capture {print}' dns-manager-luci.sh > "$t/helper"
    cmp "$source" "$t/helper"
    sh -n "$t/helper"
}
check EOF_DM_HELPER_UCI_READ_GUARD libexec/dns-manager-uci-read-guard.sh
check EOF_DM_HELPER_CACHE_TRANSACTION libexec/dns-manager-cache-transaction.sh
echo 'OK: installer embeds the tested cache and UCI helpers'
