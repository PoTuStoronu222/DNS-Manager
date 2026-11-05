#!/bin/sh
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^verify_after_apply_with_repair\(\) \{/,/^dnsmasq_failure_diagnostics\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/dispatch"
. "$tmp/dispatch"
PROFILE_APPLY=1; DNS_SELECTION_MODE=profile; DNS_SELECTION_CATEGORY=dnssec; REGIONAL_TOGGLE_APPLY=0
verify_after_apply() {
    CHECKS=$((CHECKS+1))
    if [ "$CHECKS" -gt 1 ]; then return 0; fi
    FAILED_SLOT="$FAIL_SLOT"; return 1
}
profile_retry_dnssec_slots() { RETRIES=$((RETRIES+1)); return 0; }
profile_prune_failed_slots() { PRUNES=$((PRUNES+1)); return 0; }
tx_snapshot_after_apply() { SNAPSHOTS=$((SNAPSHOTS+1)); }
CHECKS=0; RETRIES=0; PRUNES=0; SNAPSHOTS=0; FAIL_SLOT=1
verify_after_apply_with_repair || exit 1
[ "$CHECKS" = 2 ] && [ "$RETRIES" = 1 ] && [ "$PRUNES" = 0 ] && [ "$SNAPSHOTS" = 1 ] || exit 2
CHECKS=0; RETRIES=0; SNAPSHOTS=0; FAIL_SLOT=RU
if verify_after_apply_with_repair; then echo 'FAIL: regional failure was retried as a general slot' >&2; exit 3; fi
[ "$RETRIES" = 0 ] && [ "$SNAPSHOTS" = 0 ] || exit 4
CHECKS=0; RETRIES=0; SNAPSHOTS=0; FAIL_SLOT=''
if verify_after_apply_with_repair; then echo 'FAIL: infrastructure failure was retried as a DNSSEC candidate' >&2; exit 5; fi
[ "$RETRIES" = 0 ] || exit 6
CHECKS=0; RETRIES=0; PRUNES=0; SNAPSHOTS=0; FAIL_SLOT=1; DNS_SELECTION_CATEGORY=clean
verify_after_apply_with_repair || exit 7
[ "$RETRIES" = 0 ] && [ "$PRUNES" = 1 ] || exit 8
echo 'OK: DNSSEC retry is limited to failed general slots and preserves ordinary profiles'
