#!/bin/sh
# Experimental one-process DoH pool. Reads one endpoint URL per input line.
# Prints a complete config only after all endpoints and bootstrap IPs validate.
set -eu
LC_ALL=C
export LC_ALL

[ "$#" -eq 2 ] || { echo 'Expected local port and bootstrap IP list' >&2; exit 1; }
port=$1
bootstrap=$2
generator="$(dirname "$0")/dns-manager-dnscrypt-config.sh"
dir=$(mktemp -d /tmp/dns-manager-pool.XXXXXX) || exit 1
trap 'rm -rf "$dir"' EXIT HUP INT TERM
: > "$dir/urls"
: > "$dir/stamps"
count=0

while IFS= read -r url || [ -n "$url" ]; do
    [ -n "$url" ] || { echo 'Empty DoH URL' >&2; exit 1; }
    count=$((count + 1))
    [ "$count" -le 6 ] || { echo 'At most six DoH endpoints are supported' >&2; exit 1; }
    # An absent path and the root path name the same HTTP endpoint.
    key=$url
    case "${url#https://}" in */*) [ "${url#https://*/}" != '' ] || key=${url%/} ;; esac
    if grep -Fqx -- "$key" "$dir/urls"; then echo 'Duplicate DoH URL' >&2; exit 1; fi
    printf '%s\n' "$key" >> "$dir/urls"
    sh "$generator" "$port" "$url" "$bootstrap" > "$dir/item" || exit 1
    stamp=$(sed -n "s/^stamp = '\(sdns:\/\/[A-Za-z0-9_-]*\)'$/\1/p" "$dir/item")
    [ -n "$stamp" ] || { echo 'Invalid generated DNS stamp' >&2; exit 1; }
    [ "$count" -ne 1 ] || cp "$dir/item" "$dir/first"
    printf '%s\n' "$stamp" >> "$dir/stamps"
done
[ "$count" -gt 0 ] || { echo 'At least one DoH endpoint is required' >&2; exit 1; }

{
    printf 'server_names = ['
    i=1
    while [ "$i" -le "$count" ]; do
        [ "$i" -eq 1 ] || printf ', '
        printf "'manager-%s'" "$i"
        i=$((i + 1))
    done
    printf ']\n'
    sed -n '2,/^\[static\./{ /^\[static\./d; p; }' "$dir/first"
    i=1
    while IFS= read -r stamp; do
        printf "[static.manager-%s]\nstamp = '%s'\n" "$i" "$stamp"
        i=$((i + 1))
    done < "$dir/stamps"
} > "$dir/output"
cat "$dir/output"
