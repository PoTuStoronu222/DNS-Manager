#!/bin/sh
# Experimental allocation helper. It prints a plan and changes no settings.
# Usage: total-records number-of-device-profiles dnsmasq-validates-dnssec(0|1)
set -eu
[ "$#" = 3 ] || { echo 'Expected cache size, profile count and DNSSEC state' >&2; exit 1; }
total="$1"; profiles="$2"; dnssec="$3"
for value in "$total" "$profiles"; do
    case "$value" in ''|*[!0-9]*|0[0-9]*) echo 'Invalid cache allocation' >&2; exit 1;; esac
    [ "${#value}" -le 5 ] || { echo 'Invalid cache allocation' >&2; exit 1; }
done
[ "$total" -le 10000 ] && [ "$profiles" -le 63 ] || { echo 'Cache allocation exceeds its limit' >&2; exit 1; }
case "$dnssec" in 0|1) ;; *) echo 'Invalid DNSSEC state' >&2; exit 1;; esac
if [ "$dnssec" = 1 ] && [ "$total" -lt 150 ]; then
    echo 'dnsmasq DNSSEC requires at least 150 cache records' >&2; exit 1
fi
base=$((total / (profiles + 1)))
remainder=$((total % (profiles + 1)))
main="$base"
if [ "$remainder" -gt 0 ]; then main=$((main + 1)); remainder=$((remainder - 1)); fi
if [ "$dnssec" = 1 ] && [ "$main" -lt 150 ]; then
    main=150
    remaining=$((total - main))
    if [ "$profiles" -gt 0 ]; then base=$((remaining / profiles)); remainder=$((remaining % profiles)); fi
fi
printf 'main|%s\n' "$main"
i=1
while [ "$i" -le "$profiles" ]; do
    size="$base"
    if [ "$remainder" -gt 0 ]; then size=$((size + 1)); remainder=$((remainder - 1)); fi
    printf 'device_%s|%s\n' "$i" "$size"
    i=$((i + 1))
done

