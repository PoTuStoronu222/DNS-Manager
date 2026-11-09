#!/bin/sh
set -eu
helper=libexec/dns-manager-cache-budget.sh
for total in 0 1 149 150 151 1000 4096 10000; do
    for profiles in 0 1 2 17 63; do
        for dnssec in 0 1; do
            if [ "$dnssec" = 1 ] && [ "$total" -lt 150 ]; then
                if sh "$helper" "$total" "$profiles" "$dnssec" >/dev/null 2>&1; then exit 1; fi
                continue
            fi
            output="$(sh "$helper" "$total" "$profiles" "$dnssec")"
            printf '%s\n' "$output" | awk -F'|' -v total="$total" -v profiles="$profiles" -v dnssec="$dnssec" '
                NR==1 {if ($1!="main" || (dnssec==1 && $2<150)) exit 1}
                $2 !~ /^[0-9]+$/ {exit 1}
                {sum += $2}
                END {if (NR!=profiles+1 || sum!=total) exit 1}
            ' || { echo "Incorrect cache allocation: $total $profiles $dnssec" >&2; exit 1; }
        done
    done
done
for bad in '-1 1 0' '010 1 0' '10001 1 0' '100 64 0' '100 1 2'; do
    # Intentional word splitting passes each malformed argument separately.
    if sh "$helper" $bad >/dev/null 2>&1; then echo "Invalid allocation accepted: $bad" >&2; exit 1; fi
done
echo 'OK: common cache budget is distributed without exceeding the requested total'

