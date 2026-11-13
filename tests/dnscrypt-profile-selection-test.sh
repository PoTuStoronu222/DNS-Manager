#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR=$(mktemp -d /tmp/dnscrypt-selection-test.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
. "$ROOT/libexec/dns-manager-dnscrypt-profile.sh"

profile_apply_begin() { printf 'begin:%s\n' "$1" >> "$TMP_DIR/calls"; [ "${FAIL_BEGIN:-0}" != 1 ]; }
profile_apply_end() { printf 'end\n' >> "$TMP_DIR/calls"; }
auto_fill_slots() {
    printf 'select:%s\n' "$1" >> "$TMP_DIR/calls"
    [ "${FAIL_SELECT:-0}" != 1 ] || return 1
    SLOT_1=one SLOT_2=two SLOT_3= SLOT_4= SLOT_5= SLOT_6=
}
dns_url() { case "$1" in one) printf 'https://one.example/dns-query';; two) printf 'https://two.example/sync';; *) return 1;; esac; }
normalize_url() { printf '%s' "$1"; }

SLOT_1=original
dnscrypt_select_profile clean > "$TMP_DIR/result"
[ "$SLOT_1" = original ]
printf 'one|https://one.example/dns-query\ntwo|https://two.example/sync\n' > "$TMP_DIR/expected"
cmp "$TMP_DIR/expected" "$TMP_DIR/result"
printf 'begin:clean\nselect:clean\nend\n' > "$TMP_DIR/expected-calls"
cmp "$TMP_DIR/expected-calls" "$TMP_DIR/calls"

: > "$TMP_DIR/calls"
FAIL_SELECT=1
if dnscrypt_select_profile dnssec > "$TMP_DIR/result"; then exit 1; fi
[ ! -s "$TMP_DIR/result" ]
printf 'begin:dnssec\nselect:dnssec\nend\n' > "$TMP_DIR/expected-calls"
cmp "$TMP_DIR/expected-calls" "$TMP_DIR/calls"
FAIL_SELECT=0 FAIL_BEGIN=1
: > "$TMP_DIR/calls"
if dnscrypt_select_profile bypass > "$TMP_DIR/result"; then exit 1; fi
[ ! -s "$TMP_DIR/result" ]
printf 'begin:bypass\nend\n' > "$TMP_DIR/expected-calls"
cmp "$TMP_DIR/expected-calls" "$TMP_DIR/calls"
if dnscrypt_select_profile invalid > "$TMP_DIR/result"; then exit 1; fi
[ ! -s "$TMP_DIR/result" ]

# Exercise the manager's actual selection algorithm with controlled results.
tr -d '\r' < "$ROOT/dns-manager.sh" | awk '/^select_slot\(\) \{/{exit} /^auto_fill_slots\(\) \{/{copy=1} copy{print}' > "$TMP_DIR/auto-fill.sh"
. "$TMP_DIR/auto-fill.sh"
TEST_RESULTS="$TMP_DIR/results"
printf 'c1|clean|Clean fast|20|OK\nc2|clean|Clean slow|80|OK\np1|privacy|Privacy|5|OK\nf1|family|Family|1|OK\nb1|bypass|Bypass|9|FAIL\n' > "$TEST_RESULTS"
ensure_test_results_fresh() { return 0; }
warn_msg() { :; }
pause() { :; }
profile_apply_begin() {
    if [ "$1" = dnssec ]; then
        DNSSEC_SCREEN_DIR="$TMP_DIR/screen"
        mkdir -p "$DNSSEC_SCREEN_DIR"
        : > "$DNSSEC_SCREEN_DIR/c1"
        : > "$DNSSEC_SCREEN_DIR/p1"
    fi
}
profile_apply_end() { :; }
dnssec_candidate_eligible() { case "$1" in c1|p1) return 0;; *) return 1;; esac; }
dns_url() { printf 'https://%s.example/dns-query' "$1"; }
slot_set() { case "$1" in 1) SLOT_1=$2;; 2) SLOT_2=$2;; 3) SLOT_3=$2;; 4) SLOT_4=$2;; 5) SLOT_5=$2;; 6) SLOT_6=$2;; *) return 1;; esac; }
slot_cat_set() { :; }
unset FAIL_BEGIN FAIL_SELECT
dnscrypt_select_profile clean > "$TMP_DIR/result"
printf 'c1|https://c1.example/dns-query\nc2|https://c2.example/dns-query\n' > "$TMP_DIR/expected"
cmp "$TMP_DIR/expected" "$TMP_DIR/result"
dnscrypt_select_profile dnssec > "$TMP_DIR/result"
printf 'c1|https://c1.example/dns-query\np1|https://p1.example/dns-query\n' > "$TMP_DIR/expected"
cmp "$TMP_DIR/expected" "$TMP_DIR/result"
cut -d '|' -f2 "$TMP_DIR/result" | sh "$ROOT/libexec/dns-manager-dnscrypt-pool.sh" 5053 1.1.1.1 > "$TMP_DIR/pool.toml"
grep -Fxq "server_names = ['manager-1', 'manager-2']" "$TMP_DIR/pool.toml"
[ -z "${DNSCRYPT_BIN:-}" ] || "$DNSCRYPT_BIN" -config "$TMP_DIR/pool.toml" -check >/dev/null 2>&1
if dnscrypt_select_profile bypass > "$TMP_DIR/result"; then exit 1; fi
[ ! -s "$TMP_DIR/result" ]
printf '%s\n' 'DNSCrypt profile selection reuses existing checks without applying settings'
