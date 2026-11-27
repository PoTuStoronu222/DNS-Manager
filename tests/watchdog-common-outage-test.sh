#!/bin/sh
set -u
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^watchdog_embedded_loop\(\) \{/,/^watchdog_dnscrypt_check\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/loop.sh"
awk '/^watchdog_loop_reset_slot\(\) \{/,/^}/' dns-manager.sh > "$tmp/reset.sh"
awk '/^watchdog_loop_track_slot\(\) \{/,/^}/' dns-manager.sh > "$tmp/track.sh"
. "$tmp/loop.sh"; . "$tmp/reset.sh"; . "$tmp/track.sh"
STATE_DIR="$tmp" WATCHDOG_ENABLED=1 WATCHDOG_AUTOREPLACE=1 WATCHDOG_FAIL_THRESHOLD=2 FORCE_DOH=0
SLOT_1=first SLOT_2=second SLOT_3='' SLOT_4='' SLOT_5='' SLOT_6='' SLOT_RU=''
PORT_1=5053 PORT_2=5054 REPAIRS=0 saved1=0 saved2=0 MODE=offline
watchdog_legacy_engine_allowed() { :; }; load_config() { :; }; refresh_runtime_capabilities() { :; }
load_watchdog_state() { WD_FAIL_1=$saved1; WD_FAIL_2=$saved2; WD_ID_1=first; WD_ID_2=second; }
save_watchdog_state() { saved1=$WD_FAIL_1; saved2=$WD_FAIL_2; }
watchdog_check_due() { :; }; detect_forced_dns_path() { :; }; watchdog_resource_guard() { :; }
acquire_mutation_lock() { :; }; release_mutation_lock() { :; }; watchdog_service_recover() { :; }
watchdog_refresh_listener_snapshot() { :; }; watchdog_listener_snapshot_has_port() { :; }
dns_cat() { printf clean; }; watchdog_append_check_record() { :; }; watchdog_save_check_results() { rm -f "$1"; }
local_dns_query_ok() { [ "$MODE" = healthy ] || { [ "$MODE" = partial ] && [ "$1" = 5053 ]; }; }
watchdog_loop_repair_cooldown_ok() { :; }; watchdog_loop_mark_repair() { :; }
watchdog_slot_target_run() { REPAIRS=$((REPAIRS+1)); }
log_msg() { :; }
watchdog_embedded_loop; watchdog_embedded_loop
[ "$saved1:$saved2:$REPAIRS" = 0:0:0 ] || { echo 'common outage accumulated failures' >&2; exit 1; }
MODE=partial; watchdog_embedded_loop
[ "$saved1:$saved2:$REPAIRS" = 0:1:0 ] || { echo 'first individual failure triggered replacement' >&2; exit 1; }
watchdog_embedded_loop
[ "$REPAIRS" = 1 ] || { echo 'persistent individual failure did not trigger replacement' >&2; exit 1; }
MODE=healthy; watchdog_embedded_loop
[ "$saved1:$saved2" = 0:0 ] || { echo 'healthy servers did not clear failures' >&2; exit 1; }
echo 'OK: common outage and individual DNS failure'
