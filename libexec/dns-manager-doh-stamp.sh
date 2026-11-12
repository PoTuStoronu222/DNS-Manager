#!/bin/sh
# Convert an HTTPS DoH endpoint to the DNS stamp format used by dnscrypt-proxy.
# This helper does not change DNS settings or start any service.
set -eu
LC_ALL=C
export LC_ALL

fail() { printf '%s\n' "Unsupported DoH URL: $1" >&2; exit 1; }
[ "$#" -eq 1 ] || fail 'expected one URL'
case "$1" in https://*) rest=${1#https://} ;; *) fail 'HTTPS is required' ;; esac
case "$rest" in *'?'*|*'#'*|*'@'*|*[![:graph:]]*) fail 'query, fragment, credentials or whitespace' ;; esac
case "$rest" in */*) host=${rest%%/*}; path=/${rest#*/} ;; *) host=$rest; path=/ ;; esac
[ -n "$host" ] || fail 'missing hostname'
case "$host" in *[!a-zA-Z0-9.:-]*|.*|*..*|*:|:*|*:*:*) fail 'invalid hostname or port' ;; esac
case "$host" in
    *:*) port=${host##*:}; host_name=${host%:*};
        case "$port" in ''|*[!0-9]*) fail 'invalid port' ;; esac
        [ "${#port}" -le 5 ] && [ "$port" -gt 0 ] && [ "$port" -le 65535 ] || fail 'invalid port'
        ;;
    *) host_name=$host ;;
esac
[ -n "$host_name" ] || fail 'missing hostname'
case "$path" in *[!a-zA-Z0-9._~/%!\$\&\'\(\)\*\+,\;=:@-]*) fail 'unsupported path character' ;; esac
[ "${#host}" -le 255 ] && [ "${#path}" -le 255 ] || fail 'hostname or path too long'

lp() {
    length=${#1}
    octal=$(printf '%03o' "$length")
    printf "\\$octal%s" "$1"
}

# DNS-over-HTTPS, zero properties, no fixed IP or certificate pin.
# With no pin dnscrypt-proxy uses its normal TLS certificate validation.
if command -v base64 >/dev/null 2>&1; then
    encode() { base64; }
elif command -v ucode >/dev/null 2>&1; then
    encode() { ucode -e 'import { stdin } from "fs"; print(b64enc(stdin.read("all")));'; }
else
    fail 'neither base64 nor ucode is available'
fi
encoded=$({
    printf '\002\000\000\000\000\000\000\000\000\000\000'
    lp "$host"
    lp "$path"
} | encode) || fail 'base64 encoding failed'
[ -n "$encoded" ] || fail 'base64 encoding failed'
encoded=$(printf '%s' "$encoded" | tr -d '\n=' | tr '/+' '_-')
printf 'sdns://%s\n' "$encoded"
