#!/bin/sh
# Export the DNSCrypt project's signed resolver source as JSON without changing DNS.
set -eu
umask 077
cache_dir=${DNS_MANAGER_SOURCE_CACHE:-/etc/dns-manager/config/dnscrypt-sources}
binary=${DNS_MANAGER_DNSCRYPT_BIN:-/usr/sbin/dnscrypt-proxy}
mkdir -p "$cache_dir"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/dns-manager-source.XXXXXX")
trap 'rm -f "$tmp/config.toml" "$tmp/list.json"; rmdir "$tmp" 2>/dev/null || :' EXIT
trap 'exit 1' HUP INT TERM
# The proxy downloads and verifies the project's minisign signature before parsing.
case "$cache_dir" in *[!A-Za-z0-9_./-]*) echo 'Invalid source cache directory' >&2; exit 1;; esac
cat > "$tmp/config.toml" <<EOF
listen_addresses = ['127.0.0.1:55399']
server_names = []
[sources.'public-resolvers']
urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md', 'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md']
cache_file = '$cache_dir/public-resolvers.md'
minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
EOF
"$binary" -config "$tmp/config.toml" -list-all -json > "$tmp/list.json"
[ -s "$tmp/list.json" ] || { echo 'Empty DNSCrypt resolver list' >&2; exit 1; }
cat "$tmp/list.json"
