#!/bin/sh
# Validate an independent DoT slot selection without changing router state.
set -eu
selection="${1:-}"; dot_catalog="${2:-}"; dns_catalog="${3:-}"
[ "$#" -ge 3 ] || { echo 'Selection or catalog is unavailable' >&2; exit 1; }
shift 3
[ "$#" -gt 0 ] || set -- /dev/null
[ -r "$selection" ] && [ -r "$dot_catalog" ] && [ -r "$dns_catalog" ] || { echo 'Selection or catalog is unavailable' >&2; exit 1; }
for bindings do
    [ -r "$bindings" ] || { echo 'Device bindings are unavailable' >&2; exit 1; }
done
awk -F'|' '
    FILENAME==ARGV[1] {
        if ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/) next
        if (NF==3 && $1 ~ /^[A-Za-z0-9_-]+$/) dot[$1]++
        next
    }
    FILENAME==ARGV[2] {
        if ($0 ~ /^#/ || $0 ~ /^[[:space:]]*$/) next
        if (NF>=5 && $1 ~ /^[A-Za-z0-9_-]+$/) { cat[$1]=$2; count[$1]++ }
        next
    }
    FILENAME==ARGV[3] {
        if ($0 ~ /^[[:space:]]*$/) next
        if (NF!=2 || $2 !~ /^[A-Za-z0-9_-]+$/ || !($1 ~ /^[1-6]$/ || $1=="RU")) { error="Invalid slot entry"; exit 1 }
        if (seen_slot[$1]++ || seen_id[$2]++) { error="Duplicate slot or DNS"; exit 1 }
        if (dot[$2]!=1 || count[$2]!=1) { error="DoT endpoint not confirmed: " $2; exit 1 }
        if (($1=="RU" && cat[$2]!="regional") || ($1!="RU" && cat[$2]=="regional")) { error="DNS category does not match slot: " $2; exit 1 }
        if ($1!="RU") general++
        next
    }
    {
        if ($0 ~ /^[[:space:]]*$/) next
        if (NF!=2 || $1 !~ /^[0-9A-Fa-f:]+$/ || $2 !~ /^[1-6,]+$/) { error="Invalid device binding"; exit 1 }
        n=split($2,device_slots,",")
        for(i=1;i<=n;i++) if (device_slots[i] !~ /^[1-6]$/ || !seen_slot[device_slots[i]]) { error="Device binding requires missing DoT slot: " device_slots[i]; exit 1 }
    }
    END {
        if (error!="") { print error > "/dev/stderr"; exit 1 }
        if (!general) { print "At least one general DoT slot is required" > "/dev/stderr"; exit 1 }
    }
' "$dot_catalog" "$dns_catalog" "$selection" "$@"

