#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^watchdog_restart_hdp\(\) \{/,/^}/' dns-manager.sh | sed 's@/etc/init.d/https-dns-proxy restart@fake_proxy_restart@' > "$tmp/restart.sh"
awk '/^watchdog_service_recover_run\(\) \{/,/^}/' dns-manager.sh > "$tmp/recover.sh"
awk '/^watchdog_loop_repair_cooldown_ok\(\) \{/,/^}/' dns-manager.sh > "$tmp/cooldown.sh"
. "$tmp/restart.sh"
. "$tmp/recover.sh"
. "$tmp/cooldown.sh"
NOW=1000 RESTARTS=0 WATCHDOG_ENABLED=1 WATCHDOG_MAX_RESTARTS=2 WATCHDOG_RESTART_COOLDOWN=300
WATCHDOG_LAST_RESTART_TS=0 WATCHDOG_RESTART_COUNT=0
date() { printf '%s\n' "$NOW"; }
sleep() { :; }
fake_proxy_restart() { RESTARTS=$((RESTARTS+1)); }
refresh_runtime_capabilities() { :; }
expected_managed_slots() { printf 0; }
acquire_mutation_lock() { :; }
release_mutation_lock() { :; }
load_config() { :; }
watchdog_resource_guard() { :; }
log_msg() { :; }
watchdog_service_recover_run || exit 1
[ "$RESTARTS" = 1 ] || exit 2
NOW=1120
if watchdog_service_recover_run; then exit 3; fi
[ "$RESTARTS" = 1 ] || exit 4
NOW=1300
watchdog_service_recover_run || exit 5
[ "$RESTARTS" = 2 ] || exit 6
WD_REPAIR_TS_1=0 WD_RECOVERY_BLOCKED_1=1
if watchdog_loop_repair_cooldown_ok 1; then exit 7; fi
WD_RECOVERY_BLOCKED_1=0
watchdog_loop_repair_cooldown_ok 1 || exit 8
WD_REPAIR_TS_1=1200 WATCHDOG_REPAIR_COOLDOWN=300
if watchdog_loop_repair_cooldown_ok 1; then exit 9; fi
printf '%s\n' 'OK: repeated service recovery obeys cooldown and uncertain rollback blocks retries'
