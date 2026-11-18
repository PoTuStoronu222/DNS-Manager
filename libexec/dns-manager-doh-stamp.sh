#!/bin/sh
# Convert an HTTPS DoH endpoint or validate a DNSCrypt stamp.
# This helper does not change DNS settings or start any service.
set -eu
LC_ALL=C
export LC_ALL

fail() { printf '%s\n' "Unsupported DoH URL: $1" >&2; exit 1; }
[ "$#" -eq 1 ] || fail 'expected one URL'
case "$1" in
    sdns://*)
        stamp=${1#sdns://}
        case "$stamp" in ''|*[!A-Za-z0-9_-]*) fail 'invalid stamp encoding' ;; esac
        [ "${#stamp}" -le 1024 ] || fail 'stamp too long'
        case $((${#stamp} % 4)) in 0) padding= ;; 2) padding='==' ;; 3) padding='=' ;; *) fail 'invalid stamp encoding' ;; esac
        if printf 'test' | base64 >/dev/null 2>&1; then
            decode() { base64 -d; }
        elif command -v ucode >/dev/null 2>&1; then
            decode() { ucode -e 'import { stdin } from "fs"; print(b64dec(stdin.read("all")));'; }
        else
            fail 'neither base64 nor ucode is available'
        fi
        if command -v hexdump >/dev/null 2>&1; then
            decimal_bytes() { hexdump -v -e '1/1 "%u "'; }
        elif command -v od >/dev/null 2>&1; then
            decimal_bytes() { od -An -v -tu1; }
        else
            fail 'neither hexdump nor od is available'
        fi
        bytes=$(printf '%s%s' "$stamp" "$padding" | tr '_-' '/+' | decode | decimal_bytes) || fail 'invalid stamp encoding'
        printf '%s\n' "$bytes" | awk '
            { for (i = 1; i <= NF; i++) b[++n] = $i }
            END {
                if (n < 44 || b[1] != 1) exit 1
                p = 10; addr = b[p]; p += addr + 1
                if (addr < 1 || p > n || b[p] != 32) exit 1
                p += 33
                if (p > n || b[p] < 1 || p + b[p] != n) exit 1
            }
        ' || fail 'invalid DNSCrypt stamp'
        printf '%s\n' "$1"
        exit 0
        ;;
esac
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
if printf 'test' | base64 >/dev/null 2>&1; then
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
