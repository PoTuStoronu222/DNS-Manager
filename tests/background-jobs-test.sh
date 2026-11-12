#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMPCASE="$(mktemp -d)"
trap 'rm -rf "$TMPCASE"' EXIT INT TERM
awk '/^background_start\(\) \{/{copy=1} /^job_start_action\(\) \{/{copy=0} copy{print}' "$ROOT/dns-manager-luci.sh" > "$TMPCASE/operations.sh"
. "$TMPCASE/operations.sh"
RUNTIME_DIR="$TMPCASE/run"; JOB_DIR="$RUNTIME_DIR/jobs"; mkdir -p "$JOB_DIR"
job_prepare() { mkdir -p "$JOB_DIR/$1"; : > "$JOB_DIR/$1/state"; : > "$JOB_DIR/$1/output"; }
job_write() { printf '%s=%s\n' "$2" "$3" >> "$JOB_DIR/$1/state"; }
job_state_value() { sed -n "s/^$2=//p" "$1" | tail -n1; }
job_record_pid() { job_write "$1" pid "$2"; }
job_active() { [ -f "$JOB_DIR/$1/state" ] && [ "$(job_state_value "$JOB_DIR/$1/state" status)" = running ]; }
job_process_alive() { return 0; }
acquire_runtime_lock() { mkdir "$1"; }
release_runtime_lock() { rmdir "$1"; }
json_error() { printf '{"ok":false,"error":"%s"}' "$1"; }
json_quote() { printf '"%s"' "$1"; }
ubus() { case "$1:$2:$3" in call:service:list) printf '{}';; call:service:delete) :;; call:service:set) printf '%s' "$4" > "$TMPCASE/procd.json";; *) return 1;; esac; }
load_manager() { return 0; }
cfg_get() { [ "$1" != SLOT_1 ] || printf '%s' "${MOCK_SLOT:-}"; }
uci() {
 case "$3" in
  'https-dns-proxy.@https-dns-proxy[0]') [ "${MOCK_SYSTEM:-0}" = 1 ];;
  'https-dns-proxy.@https-dns-proxy[0].resolver_url') echo https://custom.example/dns-query;;
  'https-dns-proxy.@https-dns-proxy[0].listen_port') echo 5053;;
  *) return 1;;
 esac
}
system_instance_slot() { return 1; }
job_start_test_current() { echo current >> "$TMPCASE/steps"; job_prepare test_current; job_write test_current status done; job_write test_current result "${MOCK_CURRENT_RESULT:-ok}"; job_write test_current finished 1; printf '{"ok":true}'; }
job_start_test_system() { echo system >> "$TMPCASE/steps"; job_prepare test_system; job_write test_system status done; job_write test_system result "${MOCK_SYSTEM_RESULT:-ok}"; job_write test_system finished 1; printf '{"ok":true}'; }
update_all_json() { echo update >> "$TMPCASE/steps"; printf '{"ok":true,"message":"updated"}'; }

background_start combined > "$TMPCASE/reply"
grep -q '"ok":true' "$TMPCASE/reply"
grep -q '"name":"dns-manager-job-combined"' "$TMPCASE/procd.json"
grep -q '"worker","combined"' "$TMPCASE/procd.json"
background_start combined > "$TMPCASE/reply"
grep -q '"resumed":true' "$TMPCASE/reply"

MOCK_SLOT=one; MOCK_SYSTEM=1; : > "$TMPCASE/steps"
background_worker combined
[ "$(cat "$TMPCASE/steps")" = "$(printf 'current\nsystem')" ]
[ "$(job_state_value "$JOB_DIR/combined/state" result)" = ok ]
[ "$(job_state_value "$JOB_DIR/combined/state" status)" = done ]

job_prepare combined; MOCK_CURRENT_RESULT=fail; : > "$TMPCASE/steps"
background_worker combined
[ "$(cat "$TMPCASE/steps")" = "$(printf 'current\nsystem')" ]
[ "$(job_state_value "$JOB_DIR/combined/state" status)" = failed ]

job_prepare combined; MOCK_SLOT=''; MOCK_CURRENT_RESULT=ok; : > "$TMPCASE/steps"
background_worker combined
[ "$(cat "$TMPCASE/steps")" = system ]
[ "$(job_state_value "$JOB_DIR/combined/state" result)" = ok ]

job_prepare combined; MOCK_SYSTEM=0; : > "$TMPCASE/steps"
background_worker combined
[ "$(job_state_value "$JOB_DIR/combined/state" status)" = failed ]

job_prepare update; : > "$TMPCASE/steps"
background_worker update
[ "$(cat "$TMPCASE/steps")" = update ]
[ "$(job_state_value "$JOB_DIR/update/state" status)" = done ]
[ "$(cat "$JOB_DIR/update/output")" = '{"ok":true,"message":"updated"}' ]
awk '/^job_json\(\) \{/{copy=1} /^log_json\(\) \{/{copy=0} copy{print}' "$ROOT/dns-manager-luci.sh" > "$TMPCASE/job-json.sh"
. "$TMPCASE/job-json.sh"
printf 'one "quoted"\ntwo \\path\n' > "$JOB_DIR/combined/output"
job_json combined > "$TMPCASE/job.json"
node -e 'const x=JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")); if(x.output!=="one \"quoted\"\ntwo \\path") process.exit(1)' "$TMPCASE/job.json"
printf '%s\n' 'OK: background worker registration, duplicate requests and both DNS stages'
