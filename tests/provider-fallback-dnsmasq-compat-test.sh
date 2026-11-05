#!/bin/sh
# Run against a locally built dnsmasq, not an active router instance.
# Demonstrate whether adding our own servers-file conflicts with an existing one.
set -eu
[ "$#" -eq 1 ] && [ -x "$1" ] || { echo "usage: $0 /path/to/dnsmasq" >&2; exit 2; }
dnsmasq="$1"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT HUP INT TERM
: > "$dir/existing"
: > "$dir/fallback"
printf 'servers-file=%s/existing\n' "$dir" > "$dir/one.conf"
"$dnsmasq" --test --conf-file="$dir/one.conf" > "$dir/out" 2>&1 || { cat "$dir/out" >&2; exit 1; }
printf 'servers-file=%s/existing\nservers-file=%s/fallback\n' "$dir" "$dir" > "$dir/two.conf"
if "$dnsmasq" --test --conf-file="$dir/two.conf" > "$dir/out" 2>&1; then
    echo 'Multiple servers-file options accepted; review fallback design for this version.'
else
    cat "$dir/out"
    echo 'Existing servers-file prevents adding a second one on this version.'
fi
