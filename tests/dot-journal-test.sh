#!/bin/sh
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
helper=libexec/dns-manager-dot-journal.sh
j="$t/dns-manager-dot-journal"; target="$t/current"; after="$t/intended"
printf '%s\n' old > "$target"; printf '%s\n' new > "$after"
sh "$helper" prepare "$j" "$target" "$after"
sh "$helper" apply "$j"
[ "$(cat "$target")" = new ] || exit 1
# A new process simulates recovery after interruption/reboot.
sh "$helper" recover "$j"
[ "$(cat "$target")" = old ] && [ ! -e "$j" ] || { echo 'FAIL: journal did not restore previous state' >&2; exit 1; }
sh "$helper" prepare "$j" "$target" "$after"
sh "$helper" recover "$j"
[ "$(cat "$target")" = old ] && [ ! -e "$j" ] || exit 1
sh "$helper" prepare "$j" "$target" "$after"
sh "$helper" apply "$j"
printf '%s\n' external > "$target"
if sh "$helper" recover "$j" >/dev/null 2>&1; then echo 'FAIL: external change was overwritten' >&2; exit 1; fi
[ "$(cat "$target")" = external ] && [ -d "$j" ] || exit 1
printf '%s\n' new > "$target"
sh "$helper" finish "$j"
[ "$(cat "$target")" = new ] && [ ! -e "$j" ] || exit 1
echo 'OK: guarded DoT journal restores interrupted changes and preserves external edits'
