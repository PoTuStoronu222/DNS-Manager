#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d /tmp/dnscrypt-job-grace.XXXXXX)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^profile_job_running\(\) \{/{exit} /^new_job_id\(\) \{/{copy=1} copy{print}' "$root/dns-manager-luci.sh" > "$tmp/functions"
. "$tmp/functions"
# The embedded RPC backend does not enable nounset; some legacy helpers use
# optional positional parameters.
set +u
JOB_DIR="$tmp/jobs"
JOB_MAX_AGE_PROFILE=900
JOB_MAX_AGE_TEST_ALL=1800
JOB_MAX_AGE_TEST_CURRENT=300
JOB_MAX_AGE_TEST_ONE=60
mkdir -p "$JOB_DIR/profile" "$JOB_DIR/action"
for mode in profile action; do
    job="$JOB_DIR/$mode"
    printf 'status=running\nmode=%s\nstarted=%s\n' "$mode" "$(date +%s)" > "$job/state"
    job_process_alive "$job" || { echo "Fresh $mode job was rejected" >&2; exit 1; }
    printf 'status=running\nmode=%s\nstarted=%s\n' "$mode" "$(( $(date +%s) - 31 ))" > "$job/state"
    if job_process_alive "$job"; then echo "Stale $mode job was accepted" >&2; exit 1; fi
    grep -q '^status=failed$' "$job/state"
done
echo 'PASS: procd profile and action jobs get bounded time to record PID'
