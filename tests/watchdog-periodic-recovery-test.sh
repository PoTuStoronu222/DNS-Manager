#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^watchdog_embedded_loop\(\) \{/,/^watchdog_dnscrypt_check\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/loop.sh"
awk '/^watchdog_service_recover\(\) \{/,/^}/' dns-manager.sh > "$tmp/recover.sh"
. "$tmp/loop.sh"
. "$tmp/recover.sh"
STATE_DIR="$tmp" WATCHDOG_ENABLED=1 FORCE_DOH=0 SLOT_1=example PORT_1=5053
SLOT_2='' SLOT_3='' SLOT_4='' SLOT_5='' SLOT_6='' SLOT_RU=''
RESTARTS=0 LOCKED=0 SAVES=0 MISSING=0 SWITCHED=0
watchdog_legacy_engine_allowed() { [ "$SWITCHED" = 0 ]; }
load_config() { :; }
refresh_runtime_capabilities() { :; }
load_watchdog_state() { :; }
watchdog_check_due() { :; }
detect_forced_dns_path() { FORCED_DNS_ACTIVE=1; }
watchdog_resource_guard() { :; }
acquire_mutation_lock() { LOCKED=1; }
release_mutation_lock() { LOCKED=0; }
listener_port_exists() { [ "$MISSING" = 0 ]; }
watchdog_restart_hdp() { [ "$LOCKED" = 1 ]; RESTARTS=$((RESTARTS + 1)); }
save_watchdog_state() { SAVES=$((SAVES + 1)); }
log_msg() { :; }
command() { return 1; }
watchdog_embedded_loop
[ "$RESTARTS" = 0 ] || { echo 'healthy listener caused restart' >&2; exit 1; }
MISSING=1
watchdog_embedded_loop
[ "$RESTARTS" = 1 ] && [ "$LOCKED" = 0 ] && [ "$SAVES" -ge 2 ] || {
    echo 'missing listener was not recovered and persisted under lock' >&2; exit 1;
}
WATCHDOG_ENABLED=0
watchdog_embedded_loop
[ "$RESTARTS" = 1 ] || { echo 'disabled watchdog restarted service' >&2; exit 1; }
WATCHDOG_ENABLED=1
acquire_mutation_lock() { LOCKED=1; SWITCHED=1; }
watchdog_embedded_loop
[ "$RESTARTS" = 1 ] && [ "$LOCKED" = 0 ] || { echo 'engine change raced with recovery' >&2; exit 1; }
printf '%s\n' 'OK: periodic HTTPS recovery observes listeners, lock, setting and engine changes'
