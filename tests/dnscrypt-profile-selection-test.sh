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

# Compare native DNSCrypt with the checked DoH candidates by measured RTT.
HELPERS="$ROOT/libexec"
TEST_RESULTS="$TMP_DIR/ranking"
printf 'one|clean|One|90|OK\ntwo|clean|Two|100|OK\n' > "$TEST_RESULTS"
dnscrypt_catalog_snapshot() { [ "$1" = clean ] && printf 'native_adguard_unfiltered|20\n'; }
dnscrypt_select_profile clean > "$TMP_DIR/result"
[ "$(sed -n '1s/|.*//p' "$TMP_DIR/result")" = native_adguard_unfiltered ]
DNS_MANAGER_PROTOCOL=native dnscrypt_select_profile clean > "$TMP_DIR/native-only"
grep -q '^native_adguard_unfiltered|' "$TMP_DIR/native-only"
! grep -q '^one|' "$TMP_DIR/native-only"

dnscrypt_catalog_snapshot() {
    [ "$1" = dnssec ] || return 1
    printf 'native_quad9_unfiltered|20\nnative_adguard_unfiltered|10\nnative_adguard_family|1\n'
}
dnscrypt_native_dnssec_probe() { case "$1" in *ADTkuOS45LjEwOjg0NDM*) return 0;; *) return 1;; esac; }
mkdir -p "$TMP_DIR/jobs/profile"
JOB_DIR="$TMP_DIR/jobs"
dnscrypt_select_profile dnssec > "$TMP_DIR/result"
grep -q "^progress_total=3$" "$JOB_DIR/profile/state"
grep -q "^progress_done=3$" "$JOB_DIR/profile/state"
unset JOB_DIR
grep -q '^native_quad9_unfiltered|' "$TMP_DIR/result"
! grep -q '^native_adguard_' "$TMP_DIR/result"
(
    mkdir "$TMP_DIR/bin"
    printf '#!/bin/sh\nexit 0\n' > "$TMP_DIR/bin/dig"
    chmod +x "$TMP_DIR/bin/dig"
    PATH="$TMP_DIR/bin:$PATH"; export PATH
    FAIL_BEGIN=1
    dnscrypt_select_profile dnssec > "$TMP_DIR/native-only"
    grep -q '^native_quad9_unfiltered|' "$TMP_DIR/native-only"
    ! grep -q '^one|' "$TMP_DIR/native-only"
)
# A listed but unreachable bypass server must not be reported as absent.
dnscrypt_catalog_snapshot() { [ "$1" = bypass ] && printf 'native_quic|FAIL\n'; }
if DNS_MANAGER_PROTOCOL=native dnscrypt_select_profile bypass > "$TMP_DIR/result" 2> "$TMP_DIR/error"; then exit 1; fi
grep -q 'Не найдено доступных DNSCrypt-серверов' "$TMP_DIR/error"
! grep -q 'В каталоге нет' "$TMP_DIR/error"
# Privacy must have a native candidate and must never silently use DoH.
dnscrypt_catalog_snapshot() { [ "$1" = privacy ] && printf 'native_cryptostorm_fr|15\n'; }
DNS_MANAGER_PROTOCOL=native dnscrypt_select_profile privacy > "$TMP_DIR/native-only"
grep -q '^native_cryptostorm_fr|sdns://' "$TMP_DIR/native-only"
! grep -q '^one|' "$TMP_DIR/native-only"
unset -f dnscrypt_catalog_snapshot 2>/dev/null || unset dnscrypt_catalog_snapshot

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
# The all-profile pool must use the six fastest working entries, rather than
# reserving a place for each category; failed and duplicate URLs are skipped.
printf 'a|clean|A|10|OK\nb|clean|B|20|OK\nc|privacy|C|30|OK\nd|clean|D|40|OK\ne|clean|E|50|OK\nf|clean|F|60|OK\ng|bypass|G|500|OK\nh|clean|H|1|FAIL\n' > "$TEST_RESULTS"
dnscrypt_select_profile all > "$TMP_DIR/result"
printf 'a|https://a.example/dns-query\nb|https://b.example/dns-query\nc|https://c.example/dns-query\nd|https://d.example/dns-query\ne|https://e.example/dns-query\nf|https://f.example/dns-query\n' > "$TMP_DIR/expected"
cmp "$TMP_DIR/expected" "$TMP_DIR/result"
printf 'c1|clean|Clean fast|20|OK\nc2|clean|Clean slow|80|OK\np1|privacy|Privacy|5|OK\nf1|family|Family|1|OK\nb1|bypass|Bypass|9|FAIL\n' > "$TEST_RESULTS"
dnscrypt_select_profile dnssec > "$TMP_DIR/result"
printf 'c1|https://c1.example/dns-query\np1|https://p1.example/dns-query\n' > "$TMP_DIR/expected"
cmp "$TMP_DIR/expected" "$TMP_DIR/result"
cut -d '|' -f2 "$TMP_DIR/result" | sh "$ROOT/libexec/dns-manager-dnscrypt-pool.sh" 5053 1.1.1.1 > "$TMP_DIR/pool.toml"
grep -Fxq "server_names = ['manager-1', 'manager-2']" "$TMP_DIR/pool.toml"
[ -z "${DNSCRYPT_BIN:-}" ] || "$DNSCRYPT_BIN" -config "$TMP_DIR/pool.toml" -check >/dev/null 2>&1
if dnscrypt_select_profile bypass > "$TMP_DIR/result"; then exit 1; fi
[ ! -s "$TMP_DIR/result" ]
printf '%s\n' 'DNSCrypt profile selection reuses existing checks without applying settings'
