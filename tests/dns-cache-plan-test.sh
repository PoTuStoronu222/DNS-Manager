#!/bin/sh
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
cp libexec/dns-manager-cache-budget.sh "$t/budget"; chmod +x "$t/budget"
plan=libexec/dns-manager-cache-plan.sh
printf '%s\n' 'aa:bb:cc:dd:ee:01|1,2' 'aa:bb:cc:dd:ee:02|2,1,1' 'aa:bb:cc:dd:ee:03|3' > "$t/bindings"
out="$(sh "$plan" 1000 0 "$t/bindings" "$t/budget")"
[ "$out" = "$(printf 'main|334\nmask_3|333\nmask_4|333')" ] || { echo 'Shared groups were counted incorrectly' >&2; exit 1; }
printf '%s\n' 'aa:bb:cc:dd:ee:01|1,2' 'aa:bb:cc:dd:ee:03|3' 'aa:bb:cc:dd:ee:04|4' > "$t/bindings"
out="$(sh "$plan" 1000 0 "$t/bindings" "$t/budget")"
[ "$out" = "$(printf 'main|250\nmask_3|250\nmask_4|250\nmask_8|250')" ] || { echo 'Added binding was not reallocated' >&2; exit 1; }
printf '%s\n' 'aa:bb:cc:dd:ee:01|1,2' > "$t/bindings"
out="$(sh "$plan" 1000 0 "$t/bindings" "$t/budget")"
[ "$out" = "$(printf 'main|500\nmask_3|500')" ] || { echo 'Removed binding was not reallocated' >&2; exit 1; }
: > "$t/bindings"
[ "$(sh "$plan" 1000 0 "$t/bindings" "$t/budget")" = 'main|1000' ] || exit 1
printf '%s\n' 'zz:bb:cc:dd:ee:01|1' > "$t/bindings"
if sh "$plan" 1000 0 "$t/bindings" "$t/budget" >/dev/null 2>&1; then echo 'Invalid MAC accepted' >&2; exit 1; fi
printf '%s\n' 'aa:bb:cc:dd:ee:01|1,7' > "$t/bindings"
if sh "$plan" 1000 0 "$t/bindings" "$t/budget" >/dev/null 2>&1; then echo 'Invalid slot accepted' >&2; exit 1; fi
echo 'OK: cache plan counts unique binding groups and reallocates the total'

