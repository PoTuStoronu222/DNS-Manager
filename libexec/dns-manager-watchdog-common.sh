#!/bin/sh
# Stop the legacy watchdog before DNSCrypt operations or engine changes.
dns_manager_stop_watchdog() {
    watchdog_service_stop_disable || return 1
    wd_reply=$(ubus -t 5 call service list '{"name":"dns-watchdog"}' 2>/dev/null) || return 1
    wd_root=$(jsonfilter -s "$wd_reply" -e '@' 2>/dev/null) || return 1
    case "$wd_root" in \{*\}) ;; *) return 1 ;; esac
    if jsonfilter -s "$wd_reply" -e "@['dns-watchdog']" >/dev/null 2>&1; then
        return 1
    else
        wd_rc=$?
        [ "$wd_rc" -eq 1 ] || return 1
    fi
    watchdog_cron_remove_owned_block
}
