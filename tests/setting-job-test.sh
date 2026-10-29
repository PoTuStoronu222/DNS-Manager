#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
awk '/^job_start_setting\(\) \{/,/^}/' "$ROOT/dns-manager-luci.sh" > "$tmp/job"
awk '/^job_start_action\(\) \{/,/^}/' "$ROOT/dns-manager-luci.sh" > "$tmp/action"
awk '/^apply_live_setting\(\) \{/,/^}/' "$ROOT/dns-manager-luci.sh" > "$tmp/apply"
(
    . "$tmp/job"
    JOB_DIR="$tmp/jobs"; mkdir -p "$JOB_DIR"
    RUNTIME_DIR="$tmp/runtime"; mkdir -p "$RUNTIME_DIR"
    acquire_runtime_lock() { :; }; release_runtime_lock() { :; }
    job_active() { return 1; }
    job_prepare() { mkdir -p "$JOB_DIR/$1"; : > "$JOB_DIR/$1/state"; : > "$JOB_DIR/$1/output"; }
    job_write() { printf '%s=%s\n' "$2" "$3" >> "$JOB_DIR/$1/state"; }
    job_record_pid() { :; }
    json_error() { echo ERROR; }
    json_quote() { printf '"%s"' "$1"; }
    run_action() {
        while [ ! -f "$tmp/continue" ]; do sleep 0.1; done
        [ "$DNSMGR_SETTING_WORKER" = 1 ] && [ "$RPC_METHOD" = set_setting ]
        printf '{"ok":true,"force_owner":"steer"}'
    }
    job_start_setting force 1 > "$tmp/reply"
    grep -Fq '"job":"setting"' "$tmp/reply"
    grep -Fqx 'status=running' "$JOB_DIR/setting/state"
    : > "$tmp/continue"
    wait
    grep -Fqx 'result=ok' "$JOB_DIR/setting/state"
    grep -Fqx 'status=done' "$JOB_DIR/setting/state"
    grep -Fq '"force_owner":"steer"' "$JOB_DIR/setting/output"
)
(
    . "$tmp/apply"
    acquire_mutation_lock() { echo lock >> "$tmp/order"; }
    release_mutation_lock() { echo unlock >> "$tmp/order"; }
    load_config() { echo load >> "$tmp/order"; FORCE_DOH=0; BLOCK_EXTERNAL_DNS=1; }
    _apply_extras_now_impl() { echo "apply:$1:$FORCE_DOH:$BLOCK_EXTERNAL_DNS" >> "$tmp/order"; }
    FORCE_DOH=1 BLOCK_EXTERNAL_DNS=0
    apply_live_setting force 1
    [ "$(cat "$tmp/order")" = "$(printf 'lock\nload\napply:force:1:1\nunlock')" ]
    : > "$tmp/order"
    apply_live_setting force 0
    [ "$(cat "$tmp/order")" = "$(printf 'lock\nload\nunlock')" ]
)
(
    . "$tmp/action"
    JOB_DIR="$tmp/actions"; RUNTIME_DIR="$tmp/runtime-actions"; mkdir -p "$JOB_DIR" "$RUNTIME_DIR"
    acquire_runtime_lock() { :; }; release_runtime_lock() { :; }
    job_active() { return 1; }
    job_prepare() { mkdir -p "$JOB_DIR/$1"; : > "$JOB_DIR/$1/state"; : > "$JOB_DIR/$1/output"; }
    job_write() { printf '%s=%s\n' "$2" "$3" >> "$JOB_DIR/$1/state"; }
    job_record_pid() { :; }; json_error() { echo ERROR; }; json_quote() { printf '"%s"' "$1"; }
    INPUT='{"mac":"aa:bb:cc:dd:ee:ff","slots":"1,2"}'
    run_action() { [ "$DNSMGR_ACTION_WORKER:$RPC_METHOD" = '1:set_device_dns' ]; [ "$INPUT" = '{"mac":"aa:bb:cc:dd:ee:ff","slots":"1,2"}' ]; printf '{"ok":true}'; }
    job_start_action set_device_dns > "$tmp/action-reply"
    grep -Fq '"job":"action"' "$tmp/action-reply"
    wait
    grep -Fqx 'name=set_device_dns' "$JOB_DIR/action/state"
    grep -Fqx 'result=ok' "$JOB_DIR/action/state"
    grep -Fqx 'status=done' "$JOB_DIR/action/state"
)
echo 'OK: settings run as background jobs and reload state under lock'
