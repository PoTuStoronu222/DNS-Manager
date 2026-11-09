#!/bin/sh
# Experimental: prepare a shared cache plan and private staged dnsmasq files.
# No UCI settings, live services, or DNS traffic are changed.
# total ttl dnssec bindings staged-profile-dir budget-helper plan-helper profile-helper
set -eu
[ "$#" = 8 ] || { echo 'Invalid cache staging inputs' >&2; exit 1; }
total="$1"; ttl="$2"; dnssec="$3"; bindings="$4"; profiles="$5"
budget="$6"; planner="$7"; renderer="$8"
[ -x "$budget" ] && [ -x "$planner" ] && [ -x "$renderer" ] || { echo 'Cache staging helper unavailable' >&2; exit 1; }
t="$(mktemp "${TMPDIR:-/tmp}/dns-cache-stage.XXXXXX")" || exit 1
trap 'rm -f "$t"' EXIT HUP INT TERM
"$planner" "$total" "$dnssec" "$bindings" "$budget" > "$t" || exit 1
"$renderer" "$profiles" "$t" "$ttl" "$total" || exit 1
cat "$t"

