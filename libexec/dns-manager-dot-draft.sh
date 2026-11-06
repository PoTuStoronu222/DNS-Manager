#!/bin/sh
# Prepare a DoT selection for review; never changes the active DNS or saves it.
# Inputs: current DoH slots, saved DoT slots, verified DoT catalog, DNS catalog.
set -eu
[ "$#" -ge 4 ] || { echo 'DoT selection inputs are unavailable' >&2; exit 1; }
current="$1"; saved="$2"; dot_catalog="$3"; dns_catalog="$4"; shift 4
validator="${DOT_SELECTION_VALIDATOR:-/usr/libexec/dns-manager-dot-selection}"
[ -r "$current" ] && [ -r "$dot_catalog" ] && [ -r "$dns_catalog" ] && [ -x "$validator" ] || { echo 'DoT selection inputs are unavailable' >&2; exit 1; }
if [ -e "$saved" ] || [ -L "$saved" ]; then
    [ -f "$saved" ] && [ ! -L "$saved" ] && [ -r "$saved" ] || { echo 'Saved DoT selection is unavailable' >&2; exit 1; }
    "$validator" "$saved" "$dot_catalog" "$dns_catalog" "$@" || exit 1
    cat "$saved"
    exit 0
fi
t="$(mktemp "${TMPDIR:-/tmp}/dns-manager-dot-draft.XXXXXX")" || exit 1
trap 'rm -f "$t"' EXIT HUP INT TERM
# Preserve slot positions and only suggest the exact catalog identifier when
# it has one documented DoT endpoint. Never infer a DoT name from a DoH URL.
awk -F'|' '
    FILENAME==ARGV[1] { if ($0 !~ /^#/ && NF==3) endpoint[$1]++; next }
    /^[[:space:]]*$/ { next }
    NF!=2 || !($1 ~ /^[1-6]$/ || $1=="RU") || $2 !~ /^[A-Za-z0-9_-]+$/ { bad=1; exit }
    seen[$1]++ { bad=1; exit }
    endpoint[$2]==1 { print $1 "|" $2 }
    END { if (bad) exit 1 }
' "$dot_catalog" "$current" > "$t" || { echo 'Invalid current DNS selection' >&2; exit 1; }
[ -s "$t" ] || { echo 'No matching DoT servers; choose servers first' >&2; exit 1; }
"$validator" "$t" "$dot_catalog" "$dns_catalog" "$@" || { echo 'Select DoT servers for all required slots' >&2; exit 1; }
cat "$t"

