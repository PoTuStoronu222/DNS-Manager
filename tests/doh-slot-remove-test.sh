#!/bin/sh
set -eu
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
awk '/^        set_slot\)$/ {p=1} /^        set_slot_domains\)$/ {p=0} p' dns-manager-luci.sh | sed "s@/etc/dns-manager/config/device-dns.conf@$t/device-dns.conf@g;s@/etc/dns-manager/config/device-dns-default.conf@$t/device-dns-default.conf@g" > "$t/case"
{
    printf 'run_slot() { case set_slot in\n'
    cat "$t/case"
    printf 'esac; }\n'
} > "$t/fn"
. "$t/fn"
jget() { case "$1" in slot) printf '%s' "${test_slot:-1}";; id) printf '%s' "${test_id:-}";; expected) printf '%s' "${test_expected:-old}";; esac; }
json_error() { printf 'error:%s\n' "$1"; }
json_ok() { printf 'ok\n'; }
load_manager() { :; }; acquire_mutation_lock() { :; }; release_mutation_lock() { :; }
load_config() { SLOT_1=old; SLOT_2="${test_second-other}"; SLOT_3=; SLOT_4=; SLOT_5=; SLOT_6=; DNS_PROFILE=hybrid; DNS_SELECTION_CATEGORY=dnssec; }
slot_cat_set() { :; }; sync_profile_from_selected_categories() { DNS_SELECTION_CATEGORY=changed; }
_apply_settings_impl() { printf '%s' "$SLOT_1" > "$t/applied"; printf '%s' "$DNS_SELECTION_CATEGORY" > "$t/profile"; return "${test_fail:-0}"; }
out="$(run_slot)"; [ "$out" = ok ] && [ -f "$t/applied" ] && [ ! -s "$t/applied" ] && [ "$(cat "$t/profile")" = dnssec ] || { echo 'FAIL: slot removal or profile preservation' >&2; exit 1; }
rm -f "$t/applied"
test_expected=stale; out="$(run_slot)"; case "$out" in error:*) ;; *) exit 1;; esac; [ ! -e "$t/applied" ] || exit 1
test_expected=old; test_second=''; export test_second; out="$(run_slot)"; case "$out" in error:*) ;; *) exit 1;; esac; [ ! -e "$t/applied" ] || exit 1
test_second=other; printf '%s\n' 'aa:bb:cc:dd:ee:ff|1,2' > "$t/device-dns.conf"; out="$(run_slot)"; case "$out" in error:*) ;; *) exit 1;; esac; [ ! -e "$t/applied" ] || exit 1
printf '%s\n' 'aa:bb:cc:dd:ee:ff|2' > "$t/device-dns.conf"; out="$(run_slot)"; [ "$out" = ok ] || exit 1
echo 'OK: slot removal checks stale state, last DNS, device bindings and valid removal'
