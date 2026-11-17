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
# Simulate the worker finishing after the initial status read but before kill.
mkdir -p "$JOB_DIR/engine"
printf 'status=running\nmode=update\nstarted=%s\npid=999999\n' "$(date +%s)" > "$JOB_DIR/engine/state"
kill() { printf 'result=ok\nstatus=done\n' >> "$JOB_DIR/engine/state"; return 1; }
job_process_alive "$JOB_DIR/engine" || :
[ "$(job_state_value "$JOB_DIR/engine/state" status)" = done ] || { echo 'Completed job overwritten by stale PID check' >&2; exit 1; }
[ ! -s "$JOB_DIR/engine/output" ] || { echo 'Completed job incorrectly reported as failed' >&2; exit 1; }
echo 'PASS: startup grace and completed-job race'
