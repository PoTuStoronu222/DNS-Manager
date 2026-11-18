#!/bin/sh
set -eu
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^watchdog_service_migrate_legacy\(\) \{/,/^}/' dns-manager.sh > "$tmp/migrate"
. "$tmp/migrate"
CFG_DIR="$tmp/config"; WATCHDOG_SERVICE_PATH="$tmp/missing-service"; WATCHDOG_SERVICE_MARKER=unused
mkdir -p "$CFG_DIR"
watchdog_service_stop_disable() { printf 'stop\n' >> "$tmp/actions"; }
watchdog_remove_legacy_daemon() { printf 'remove\n' >> "$tmp/actions"; }
watchdog_legacy_engine_allowed() { return 0; }
watchdog_service_start_enable() { printf 'start\n' >> "$tmp/actions"; }
for values in 0:0 1:0 0:1; do
    WATCHDOG_ENABLED=${values%:*}; FORCE_DOH=${values#*:}
    printf "WATCHDOG_ENABLED='%s'\nFORCE_DOH='%s'\nSLOT_1='astracat'\n" "$WATCHDOG_ENABLED" "$FORCE_DOH" > "$CFG_DIR/manager.conf"
    cp "$CFG_DIR/manager.conf" "$tmp/expected"
    : > "$tmp/actions"
    watchdog_service_migrate_legacy
    cmp "$CFG_DIR/manager.conf" "$tmp/expected"
    grep -qx stop "$tmp/actions" && grep -qx remove "$tmp/actions"
    if [ "$values" = 0:0 ]; then ! grep -qx start "$tmp/actions"; else grep -qx start "$tmp/actions"; fi
done
printf '%s\n' 'OK: watchdog migration respects saved enabled, disabled and forced-DNS settings'
