#!/bin/sh
# Experimental, read-only configuration generator for one isolated Stubby slot.
# No services, UCI files, or router configuration are changed by this script.
set -eu
id="${1:-}"; port="${2:-}"; catalog="${3:-}"
case "$id" in ''|*[!A-Za-z0-9_-]*) echo 'Invalid DNS identifier' >&2; exit 1;; esac
case "$port" in ''|*[!0-9]*) echo 'Invalid local port' >&2; exit 1;; esac
[ "$port" -ge 1024 ] 2>/dev/null && [ "$port" -le 65535 ] 2>/dev/null || { echo 'Invalid local port' >&2; exit 1; }
[ -r "$catalog" ] || { echo 'DoT catalog not readable' >&2; exit 1; }
row="$(awk -F'|' -v id="$id" '$1==id && NF==3 {line=$0;n++} END {if(n==1)print line; else exit 1}' "$catalog")" || { echo 'DoT endpoint not found or duplicated' >&2; exit 1; }
host="$(printf '%s\n' "$row" | cut -d'|' -f2)"
ips="$(printf '%s\n' "$row" | cut -d'|' -f3 | tr ',' ' ')"
case "$host" in ''|.*|*.|*..*|*[!A-Za-z0-9.-]*) echo 'Invalid TLS authentication name' >&2; exit 1;; esac
for ip in $ips; do
    if ! printf '%s\n' "$ip" | awk -F. 'NF!=4{exit 1} {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i+0>255) exit 1}'; then echo 'Invalid upstream IPv4 address' >&2; exit 1; fi
done
[ -n "$ips" ] || { echo 'No upstream address' >&2; exit 1; }
printf '%s\n' 'resolution_type: GETDNS_RESOLUTION_STUB' 'dns_transport_list:' '  - GETDNS_TRANSPORT_TLS' 'tls_authentication: GETDNS_AUTHENTICATION_REQUIRED' 'edns_client_subnet_private: 1' 'round_robin_upstreams: 1' 'listen_addresses:'
printf '  - 127.0.0.1@%s\n' "$port"
printf '%s\n' 'upstream_recursive_servers:'
for ip in $ips; do printf '  - address_data: %s\n    tls_auth_name: "%s"\n' "$ip" "$host"; done
