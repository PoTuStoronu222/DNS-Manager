#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
# Execute the real candidate and rollback logic; replace only the absolute
# init-script call with a mock so this test never touches host services.
awk '/^watchdog_apply_slot_candidate\(\) \{/,/^WATCHDOG_RESTART_COUNT=/' dns-manager.sh | sed '$d; s@/etc/init.d/https-dns-proxy restart@fake_proxy_restart@' > "$tmp/candidate.sh"
. "$tmp/candidate.sh"
PORT_1=5053
slot_set() { SLOT_1="$2"; }
slot_cat_set() { SLOT_1_CAT="$2"; }
rebuild_selected_hdp_sections() {
    REBUILDS=$((REBUILDS+1))
    if [ "$MODE" = rollback_rebuild_failure ] && [ "$REBUILDS" -gt 1 ]; then return 1; fi
    printf '%s\n' "$SLOT_1" > "$tmp/proxy-config"
}
watchdog_restart_hdp() { return 0; }
fake_proxy_restart() { [ "$MODE" != rollback_restart_failure ]; }
watchdog_check_slot() { [ "$SLOT_1" = candidate ] && { [ "$MODE" = success ] || [ "$MODE" = save_failure ]; }; }
save_config() { [ "$MODE" != save_failure ] || return 1; printf '%s\n' "$SLOT_1" > "$tmp/selected"; }
normalize_ownership_snapshot() { :; }
normalize_url() { printf '%s' "$1"; }
dns_url() { printf 'https://%s.example/dns-query' "$1"; }
dns_name() { printf '%s' "$1"; }
record_own() { :; }
log_msg() { :; }
sleep() { :; }
reset_case() { SLOT_1=old SLOT_1_CAT=clean REBUILDS=0 WATCHDOG_ROLLBACK_UNCERTAIN=0; printf 'old\n' > "$tmp/proxy-config"; printf 'old\n' > "$tmp/selected"; }
reset_case; MODE=bad_response
if watchdog_apply_slot_candidate 1 candidate clean old clean; then exit 1; fi
[ "$SLOT_1" = old ] && [ "$(cat "$tmp/proxy-config")" = old ] && [ "$(cat "$tmp/selected")" = old ] && [ "$WATCHDOG_ROLLBACK_UNCERTAIN" = 0 ] || exit 2
reset_case; MODE=save_failure
if watchdog_apply_slot_candidate 1 candidate clean old clean; then exit 3; fi
[ "$SLOT_1" = old ] && [ "$(cat "$tmp/proxy-config")" = old ] && [ "$(cat "$tmp/selected")" = old ] && [ "$WATCHDOG_ROLLBACK_UNCERTAIN" = 0 ] || exit 4
reset_case; MODE=rollback_restart_failure
if watchdog_apply_slot_candidate 1 candidate clean old clean; then exit 5; fi
[ "$SLOT_1" = old ] && [ "$(cat "$tmp/selected")" = old ] && [ "$WATCHDOG_ROLLBACK_UNCERTAIN" = 1 ] || exit 6
reset_case; MODE=rollback_rebuild_failure
if watchdog_apply_slot_candidate 1 candidate clean old clean; then exit 7; fi
[ "$SLOT_1" = old ] && [ "$(cat "$tmp/selected")" = old ] && [ "$WATCHDOG_ROLLBACK_UNCERTAIN" = 1 ] || exit 8
reset_case; MODE=success
watchdog_apply_slot_candidate 1 candidate clean old clean || exit 9
[ "$SLOT_1" = candidate ] && [ "$(cat "$tmp/selected")" = candidate ] && [ "$WATCHDOG_ROLLBACK_UNCERTAIN" = 0 ] || exit 10
printf '%s\n' 'OK: candidate rollback restores selected DNS and reports uncertain recovery'
