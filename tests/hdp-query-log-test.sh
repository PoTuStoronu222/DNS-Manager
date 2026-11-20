#!/bin/sh
set -eu
sed -n '/^job_start_setting() {/,/^}/p' dns-manager-luci.sh | grep -Fq 'hdp_query_log:0|hdp_query_log:1' || { echo 'HTTPS query log setting is rejected by job validation'; exit 1; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export tmp
DNS_MANAGER_QUERY_UCI_CONFIG="$tmp/dns-manager-config"
export DNS_MANAGER_QUERY_UCI_CONFIG
awk '/^hdp_query_setting\(\) \(/,/^\)/' dns-manager-luci.sh | sed 's|/etc/init.d/dnsmasq reload|mock_reload|g' > "$tmp/helper"
uci() {
    local action key file val
    [ "$1" != -q ] || shift
    action=$1; shift
    case "$action" in
        changes) [ ! -f "$tmp/pending" ] || echo pending;;
        get) key=$1; file="$tmp/$(printf '%s' "$key" | tr '[]@.' '____')"; [ -f "$file" ] && cat "$file";;
        set) key=${1%%=*}; val=${1#*=}; printf '%s' "$val" > "$tmp/$(printf '%s' "$key" | tr '[]@.' '____')";;
        delete) file="$tmp/$(printf '%s' "$1" | tr '[]@.' '____')"; [ -f "$file" ] && rm -f "$file";;
        commit) :;;
        *) return 1;;
    esac
}
mock_reload() { if [ -f "$tmp/fail_reload" ]; then rm -f "$tmp/fail_reload"; return 1; fi; }
. "$tmp/helper"
key='dhcp.@dnsmasq[0].logqueries'
hdp_query_setting 1
[ "$(uci get "$key")" = 1 ] && [ "$(uci get dns-manager.global.hdp_query_previous)" = absent ]
hdp_query_setting 0
! uci get "$key" && ! uci get dns-manager.global.hdp_query_log
uci set "$key=0"
hdp_query_setting 1 && hdp_query_setting 0
[ "$(uci get "$key")" = 0 ]
uci set "$key=1"
hdp_query_setting 1 && hdp_query_setting 0
[ "$(uci get "$key")" = 1 ]
uci delete "$key"
touch "$tmp/fail_reload"
if hdp_query_setting 1; then echo 'reload failure was ignored'; exit 1; fi
! uci get "$key"
hdp_query_setting 0
touch "$tmp/pending"
if hdp_query_setting 1; then echo 'pending UCI changes were committed'; exit 1; fi
echo 'OK: HTTPS DNS query logging preserves existing settings and handles reload failure'
