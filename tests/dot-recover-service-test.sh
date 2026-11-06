#!/bin/sh
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
cp libexec/dns-manager-dot-journal.sh "$t/helper"; chmod +x "$t/helper"
sed -e "s|^JOURNAL=.*|JOURNAL=$t/dns-manager-dot-journal|" -e "s|^TARGET=.*|TARGET=$t/dot-slots.conf|" -e "s|^HELPER=.*|HELPER=$t/helper|" files/dns-manager-dot-recover.init > "$t/service"
. "$t/service"
logger() { :; }
printf '%s\n' '1|cloudflare_clean' > "$TARGET"
printf '%s\n' '1|google_clean' > "$t/after"
"$HELPER" prepare "$JOURNAL" "$TARGET" "$t/after"
"$HELPER" apply "$JOURNAL"
start
[ "$(cat "$TARGET")" = '1|cloudflare_clean' ] && [ ! -e "$JOURNAL" ] || { echo 'FAIL: interrupted DoT selection was not recovered' >&2; exit 1; }
"$HELPER" prepare "$JOURNAL" "$TARGET" "$t/after"
printf '%s\n' "$t/other" > "$JOURNAL/target"
if start; then echo 'FAIL: recovery accepted unexpected target' >&2; exit 1; fi
[ "$(cat "$TARGET")" = '1|cloudflare_clean' ] && [ -d "$JOURNAL" ] || exit 1
echo 'OK: boot recovery restores only the owned DoT selection'
