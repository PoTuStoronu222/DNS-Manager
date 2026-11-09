#!/bin/sh
# Experimental: modify generated dnsmasq profiles in a staging directory only.
# Usage: profile-directory plan-file minimum-ttl total-cache-records
set -eu
[ "$#" = 4 ] || { echo 'Invalid cache profile inputs' >&2; exit 1; }
directory="$1"; plan="$2"; ttl="$3"; total="$4"
for value in "$ttl" "$total"; do
    case "$value" in ''|*[!0-9]*|0[0-9]*) echo 'Invalid cache profile settings' >&2; exit 1;; esac
    [ "${#value}" -le 5 ] || exit 1
done
[ "$ttl" -le 3600 ] && [ "$total" -le 10000 ] || exit 1
[ -d "$directory" ] && [ ! -L "$directory" ] && [ -f "$plan" ] && [ ! -L "$plan" ] || exit 1
t="$(mktemp -d "$directory/.cache-profiles.XXXXXX")" || exit 1
trap 'rm -rf "$t"' EXIT HUP INT TERM
awk -F'|' -v total="$total" '
    NF!=2 || $2 !~ /^[0-9]+$/ || $2>10000 {bad=1; next}
    NR==1 {if ($1!="main") bad=1; sum+=$2; next}
    $1 !~ /^mask_[0-9]+$/ {bad=1; next}
    {mask=substr($1,6); if (mask<1 || mask>63 || mask ~ /^0/ || seen[mask]++) bad=1; sum+=$2; print mask "|" $2}
    END {if (bad || NR<1 || sum!=total) exit 1}
' "$plan" > "$t/masks" || { echo 'Invalid cache allocation plan' >&2; exit 1; }
for file in "$directory"/profile_*.conf; do
    [ -e "$file" ] || [ -L "$file" ] || continue
    name="${file##*/}"; mask="${name#profile_}"; mask="${mask%.conf}"
    case "$mask" in ''|*[!0-9]*|0*) echo 'Invalid profile name' >&2; exit 1;; esac
    awk -F'|' -v mask="$mask" '$1==mask {found=1} END {exit !found}' "$t/masks" || { echo "Unallocated profile $mask" >&2; exit 1; }
done
while IFS='|' read -r mask size; do
    file="$directory/profile_$mask.conf"
    [ -f "$file" ] && [ ! -L "$file" ] || { echo "Missing profile $mask" >&2; exit 1; }
    [ "$(grep -c '^cache-size=' "$file" || true)" = 1 ] || { echo "Invalid cache field in profile $mask" >&2; exit 1; }
    awk -v size="$size" -v ttl="$ttl" '
        /^cache-size=/ {print "cache-size=" size; if (ttl>0) print "min-cache-ttl=" ttl; next}
        /^min-cache-ttl=/ {next}
        {print}
    ' "$file" > "$t/profile_$mask.conf" || exit 1
done < "$t/masks"
# The caller must only pass a private staging directory, so no live dnsmasq
# observes a partially updated set of profile files.
while IFS='|' read -r mask size; do
    mv -f "$t/profile_$mask.conf" "$directory/profile_$mask.conf" || exit 1
done < "$t/masks"

