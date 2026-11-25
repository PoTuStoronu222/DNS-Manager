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
    if [ "${DNS_MANAGER_AUTO_CATALOG:-0}" = 1 ]; then
        printf 'server_names = []\n'
    else
    printf 'server_names = ['
    i=1
    while [ "$i" -le "$count" ]; do
        [ "$i" -eq 1 ] || printf ', '
        printf "'manager-%s'" "$i"
        i=$((i + 1))
    done
    printf ']\n'
    fi
    sed -n '2,/^\[static\./{ /^\[static\./d; p; }' "$dir/first"
    if [ "${DNS_MANAGER_AUTO_CATALOG:-0}" = 1 ]; then
        cache_dir=${DNS_MANAGER_SOURCE_CACHE:?DNSCrypt source cache is required}
        case "$cache_dir" in *[!A-Za-z0-9_./-]*) echo 'Invalid source cache directory' >&2; exit 1;; esac
        mkdir -p "$cache_dir"
        printf "require_nofilter = true\n"
        printf "disabled_server_names = ['dnscry.pt-moscow-ipv4', 'dnscry.pt-moscow-ipv6', 'dnscry.pt-doh-moscow-ipv4', 'dnscry.pt-doh-moscow-ipv6']\n"
        printf "[sources.'public-resolvers']\n"
        printf "urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md', 'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md']\n"
        printf "cache_file = '%s/public-resolvers.md'\n" "$cache_dir"
        printf "minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'\n"
    else
    i=1
    while IFS= read -r stamp; do
        printf "[static.manager-%s]\nstamp = '%s'\n" "$i" "$stamp"
        i=$((i + 1))
    done < "$dir/stamps"
    fi
    if [ "${DNS_MANAGER_QUERY_LOG:-0}" = 1 ]; then
        printf "[query_log]\nfile = '/tmp/dns-manager-dnscrypt-query.log'\nformat = 'tsv'\n"
    fi
} > "$dir/output"
cat "$dir/output"
