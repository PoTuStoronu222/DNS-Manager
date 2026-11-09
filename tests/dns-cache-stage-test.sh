#!/bin/sh
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
for name in budget plan; do cp "libexec/dns-manager-cache-$name.sh" "$t/$name"; chmod +x "$t/$name"; done
stage=libexec/dns-manager-cache-stage.sh
mkdir "$t/profiles"
printf '%s\n' 'aa:bb:cc:dd:ee:01|1,2' 'aa:bb:cc:dd:ee:02|2,1' > "$t/bindings"
printf '%s\n' 'port=54103' 'cache-size=1000' 'server=127.0.0.1#5053' > "$t/profiles/profile_3.conf"
out="$(sh "$stage" 1000 60 0 "$t/bindings" "$t/profiles" "$t/budget" "$t/plan" "$t/profiles-helper")" 2>/dev/null && exit 1
# The caller installs the renderer separately from its staged profile directory.
cp libexec/dns-manager-cache-profiles.sh "$t/render"; chmod +x "$t/render"
out="$(sh "$stage" 1000 60 0 "$t/bindings" "$t/profiles" "$t/budget" "$t/plan" "$t/render")"
[ "$out" = "$(printf 'main|500\nmask_3|500')" ] || exit 1
grep -qx 'cache-size=500' "$t/profiles/profile_3.conf"
grep -qx 'min-cache-ttl=60' "$t/profiles/profile_3.conf"
printf '%s\n' 'aa:bb:cc:dd:ee:03|3' >> "$t/bindings"
printf '%s\n' 'port=54104' 'cache-size=1000' 'server=127.0.0.1#5055' > "$t/profiles/profile_4.conf"
out="$(sh "$stage" 1000 0 0 "$t/bindings" "$t/profiles" "$t/budget" "$t/plan" "$t/render")"
[ "$out" = "$(printf 'main|334\nmask_3|333\nmask_4|333')" ] || exit 1
grep -qx 'cache-size=333' "$t/profiles/profile_3.conf"
grep -qx 'cache-size=333' "$t/profiles/profile_4.conf"
if grep -q '^min-cache-ttl=' "$t/profiles/profile_3.conf"; then exit 1; fi
echo 'OK: binding changes recalculate staged dnsmasq cache allocations'

