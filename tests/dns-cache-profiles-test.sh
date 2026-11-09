#!/bin/sh
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
mkdir "$t/profiles"
printf '%s\n' 'port=54103' 'cache-size=1000' 'server=127.0.0.1#5053' > "$t/profiles/profile_3.conf"
printf '%s\n' 'port=54104' 'cache-size=1000' 'server=127.0.0.1#5055' > "$t/profiles/profile_4.conf"
printf '%s\n' 'main|334' 'mask_3|333' 'mask_4|333' > "$t/plan"
helper=libexec/dns-manager-cache-profiles.sh
sh "$helper" "$t/profiles" "$t/plan" 60 1000
grep -qx 'cache-size=333' "$t/profiles/profile_3.conf"
grep -qx 'min-cache-ttl=60' "$t/profiles/profile_4.conf"
grep -qx 'server=127.0.0.1#5053' "$t/profiles/profile_3.conf"
sh "$helper" "$t/profiles" "$t/plan" 0 1000
if grep -q '^min-cache-ttl=' "$t/profiles/profile_3.conf"; then exit 1; fi
cp "$t/profiles/profile_3.conf" "$t/unchanged"
printf '%s\n' 'main|334' 'mask_3|333' 'mask_5|333' > "$t/plan"
if sh "$helper" "$t/profiles" "$t/plan" 60 1000 >/dev/null 2>&1; then echo 'Missing profile accepted' >&2; exit 1; fi
cmp -s "$t/unchanged" "$t/profiles/profile_3.conf" || { echo 'Staged profile changed before full validation' >&2; exit 1; }
printf '%s\n' 'main|667' 'mask_3|333' > "$t/plan"
if sh "$helper" "$t/profiles" "$t/plan" 60 1000 >/dev/null 2>&1; then echo 'Unallocated staged profile accepted' >&2; exit 1; fi
printf '%s\n' 'main|334' 'mask_3|333' 'mask_3|333' > "$t/plan"
if sh "$helper" "$t/profiles" "$t/plan" 60 1000 >/dev/null 2>&1; then echo 'Duplicate profile accepted' >&2; exit 1; fi
if sh "$helper" "$t/profiles" "$t/plan" 3601 1000 >/dev/null 2>&1; then echo 'Invalid TTL accepted' >&2; exit 1; fi
echo 'OK: staged device DNS profiles receive allocated cache size and TTL'

