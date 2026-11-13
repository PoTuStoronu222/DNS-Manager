#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP_DIR=$(mktemp -d /tmp/dnscrypt-profile-apply-test.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
. "$ROOT/libexec/dns-manager-dnscrypt-profile-apply.sh"

dnscrypt_select_profile() {
    [ "$1" = clean ] || return 1
    [ "${SELECTION_FAIL:-0}" = 0 ] || return 1
    printf 'one|https://one.example/dns-query\ntwo|https://two.example/sync\n'
}
DNS_MANAGER_DNSCRYPT_POOL_APPLY="$TMP_DIR/apply.sh"
DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY="$TMP_DIR/dnsmasq.sh"
DNS_MANAGER_DNSCRYPT_UCI_GUARD="$TMP_DIR/guard.sh"
: > "$DNS_MANAGER_DNSCRYPT_UCI_GUARD"
cat > "$DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY" <<'EOF_DNSMASQ'
#!/bin/sh
printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" > "$TMP_DIR/dnsmasq-arguments"
[ "${DNSMASQ_FAIL:-0}" = 0 ]
EOF_DNSMASQ
cat > "$DNS_MANAGER_DNSCRYPT_POOL_APPLY" <<'EOF_FAKE'
#!/bin/sh
printf '%s|%s\n' "$1" "$2" > "$TMP_DIR/arguments"
cat > "$TMP_DIR/received"
[ "${APPLY_FAIL:-0}" = 0 ]
EOF_FAKE
export TMP_DIR APPLY_FAIL DNSMASQ_FAIL

dnscrypt_apply_profile_pool clean 5053 1.1.1.1 > "$TMP_DIR/result"
printf '5053|1.1.1.1\n' > "$TMP_DIR/expected-args"
cmp "$TMP_DIR/arguments" "$TMP_DIR/expected-args"
printf 'https://one.example/dns-query\nhttps://two.example/sync\n' > "$TMP_DIR/expected-urls"
cmp "$TMP_DIR/received" "$TMP_DIR/expected-urls"
printf 'one|https://one.example/dns-query\ntwo|https://two.example/sync\n' > "$TMP_DIR/expected-records"
cmp "$TMP_DIR/result" "$TMP_DIR/expected-records"
printf '5053|%s|/etc/init.d/dnsmasq|restart\n' "$DNS_MANAGER_DNSCRYPT_UCI_GUARD" > "$TMP_DIR/expected-dnsmasq"
cmp "$TMP_DIR/dnsmasq-arguments" "$TMP_DIR/expected-dnsmasq"

printf 'exit 1\n' > "$DNS_MANAGER_DNSCRYPT_UCI_GUARD"
rm -f "$TMP_DIR/arguments"
if dnscrypt_apply_profile_pool clean 5053 1.1.1.1 > "$TMP_DIR/result"; then exit 1; fi
[ ! -s "$TMP_DIR/result" ] && [ ! -f "$TMP_DIR/arguments" ]
: > "$DNS_MANAGER_DNSCRYPT_UCI_GUARD"

DNSMASQ_FAIL=1
if dnscrypt_apply_profile_pool clean 5053 1.1.1.1 > "$TMP_DIR/result"; then exit 1; fi
[ ! -s "$TMP_DIR/result" ]
DNSMASQ_FAIL=0

APPLY_FAIL=1
if dnscrypt_apply_profile_pool clean 5053 1.1.1.1 > "$TMP_DIR/result"; then exit 1; fi
[ ! -s "$TMP_DIR/result" ]
APPLY_FAIL=0 SELECTION_FAIL=1
rm -f "$TMP_DIR/arguments"
if dnscrypt_apply_profile_pool clean 5053 1.1.1.1 > "$TMP_DIR/result"; then exit 1; fi
[ ! -s "$TMP_DIR/result" ] && [ ! -f "$TMP_DIR/arguments" ]
if find "$TMP_DIR" -name 'dnscrypt-selected.*' -o -name 'dnscrypt-urls.*' | grep -q .; then exit 1; fi
printf '%s\n' 'DNSCrypt profile selection passes checked URLs to pool application'
