#!/bin/sh
set -eu
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
sed -n '/^update_check_json() {/,/^}/p' dns-manager-luci.sh > "$work/function.sh"
. "$work/function.sh"
UPDATE_CHECK_LOCK="$work/lock"
UPDATE_CHECK_CACHE="$work/update-check.cache"
printf '%s\n' "$(date +%s)" > "$UPDATE_CHECK_CACHE"
log="$work/calls"
acquire_runtime_lock() { [ "${locked:-0}" = 0 ]; }
release_runtime_lock() { :; }
update_check_json_luci() { echo luci >> "$log"; }
component_update_check() { echo components >> "$log"; }
status_json() { printf '%s\n' '{"ok":true}'; }
json_error() { printf '%s\n' '{"ok":false}'; }
for force in 0 1; do
    INPUT="{\"force\":$force}"
    update_check_json > "$work/result"
    grep -q '"ok":true' "$work/result"
done
[ "$(grep -c '^luci$' "$log")" = 2 ]
[ "$(grep -c '^components$' "$log")" = 2 ]
locked=1
if update_check_json > "$work/result"; then exit 1; fi
grep -q '"ok":false' "$work/result"
printf '%s\n' 'OK: version checks fetch fresh data and report an active lock'
