#!/bin/sh
# Experimental read-only plan. The assignment file uses MAC|slot,slot.
set -eu
[ "$#" = 4 ] || [ "$#" = 5 ] || { echo 'Expected total, DNSSEC state, bindings, budget helper and optional active profiles' >&2; exit 1; }
total="$1"; dnssec="$2"; bindings="$3"; budget="$4"
[ -r "$bindings" ] && [ -x "$budget" ] || { echo 'Bindings or cache allocator are unavailable' >&2; exit 1; }
t="$(mktemp -d "${TMPDIR:-/tmp}/dns-cache-plan.XXXXXX")" || exit 1
trap 'rm -rf "$t"' EXIT HUP INT TERM
# Match the device service's unique slot bit masks. Reject malformed inputs
# rather than undercounting profiles and potentially exceeding the budget.
awk -F'|' '
    /^[[:space:]]*$/ {next}
    {
        if (NF!=2) {bad=1; next}
        n=split($1, mac, ":")
        if (n!=6) {bad=1; next}
        for(i=1;i<=6;i++) if (mac[i] !~ /^[[:xdigit:]][[:xdigit:]]$/) {bad=1; next}
        if ($2 ~ /[^1-6,[:space:]]/) {bad=1; next}
        n=split($2, slots, /[,[:space:]]+/); mask=0; seen=" "
        for(i=1;i<=n;i++) {
            if (slots[i]=="") continue
            if (slots[i] !~ /^[1-6]$/) {bad=1; continue}
            token=" " slots[i] " "
            if (index(seen, token)==0) {mask += 2^(slots[i]-1); seen=seen slots[i] " "}
        }
        if (mask==0) {bad=1; next}
        print mask
    }
    END {if (bad) exit 1}
' "$bindings" > "$t/masks-raw" || { echo 'Invalid device bindings' >&2; exit 1; }
sort -n -u "$t/masks-raw" > "$t/masks"
if [ "$#" = 5 ]; then
    # The live service can skip a binding when its upstream is unavailable.
    # Allocate only for profiles it actually prepared, not every saved binding.
    [ -f "$5" ] && [ ! -L "$5" ] || exit 1
    awk -F'|' 'NF!=3 || $2 !~ /^[0-9]+$/ || $2<1 || $2>63 || seen[$2]++ {bad=1; next} {print $2} END {if (bad) exit 1}' "$5" > "$t/active-raw" || exit 1
    sort -n -u "$t/active-raw" > "$t/active"
    awk 'FILENAME==ARGV[1] {allowed[$1]=1; next} !($1 in allowed) {bad=1} END {exit bad?1:0}' "$t/masks" "$t/active" || { echo 'Active profile is not present in bindings' >&2; exit 1; }
    cp "$t/active" "$t/masks"
fi
count="$(wc -l < "$t/masks" | tr -d ' ')"
"$budget" "$total" "$count" "$dnssec" > "$t/budget"
awk -F'|' 'NR==FNR {if ($1=="main") main=$2; else values[++n]=$2; next}
            {print "mask_" $1 "|" values[++i]}
            END {if (main=="") exit 1}
           ' "$t/budget" "$t/masks" > "$t/devices"
sed -n '1p' "$t/budget"
cat "$t/devices"
