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
DNS_MANAGER_DNSCRYPT_CONFIG="$TMP_DIR/dnscrypt.toml"
DNS_MANAGER_DNSCRYPT_INIT="$TMP_DIR/init.sh"
export DNS_MANAGER_DNSCRYPT_CONFIG DNS_MANAGER_DNSCRYPT_INIT
printf 'original\n' > "$DNS_MANAGER_DNSCRYPT_CONFIG"
cat > "$DNS_MANAGER_DNSCRYPT_INIT" <<'EOF_INIT'
#!/bin/sh
printf '%s\n' "$1" >> "$TMP_DIR/init-calls"
EOF_INIT
chmod +x "$DNS_MANAGER_DNSCRYPT_INIT"
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
[ "${APPLY_FAIL:-0}" = 0 ] || exit 1
printf 'new\n' > "$DNS_MANAGER_DNSCRYPT_CONFIG"
EOF_FAKE
export TMP_DIR APPLY_FAIL DNSMASQ_FAIL

dnscrypt_apply_profile_pool clean 5053 1.1.1.1 > "$TMP_DIR/result"
printf '5053|1.1.1.1\n' > "$TMP_DIR/expected-args"
cmp "$TMP_DIR/arguments" "$TMP_DIR/expected-args"
printf 'https://one.example/dns-query\nhttps://two.example/sync\n' > "$TMP_DIR/expected-urls"
cmp "$TMP_DIR/received" "$TMP_DIR/expected-urls"
printf 'one|https://one.example/dns-query\ntwo|https://two.example/sync\n' > "$TMP_DIR/expected-records"
cmp "$TMP_DIR/result" "$TMP_DIR/expected-records"
printf '5053|||\n' > "$TMP_DIR/expected-dnsmasq"
cmp "$TMP_DIR/dnsmasq-arguments" "$TMP_DIR/expected-dnsmasq"

DNS_MANAGER_PROTOCOL=native
export DNS_MANAGER_PROTOCOL
printf 'original\n' > "$DNS_MANAGER_DNSCRYPT_CONFIG"
if dnscrypt_apply_profile_pool clean 5053 1.1.1.1 > "$TMP_DIR/result" 2>/dev/null; then exit 1; fi
[ "$(cat "$DNS_MANAGER_DNSCRYPT_CONFIG")" = original ]
unset DNS_MANAGER_PROTOCOL

DNSMASQ_FAIL=1
printf 'original\n' > "$DNS_MANAGER_DNSCRYPT_CONFIG"
if dnscrypt_apply_profile_pool clean 5053 1.1.1.1 > "$TMP_DIR/result"; then exit 1; fi
[ ! -s "$TMP_DIR/result" ]
[ "$(cat "$DNS_MANAGER_DNSCRYPT_CONFIG")" = original ]
[ "$(tail -n 1 "$TMP_DIR/init-calls")" = restart ]
rm -f "$DNS_MANAGER_DNSCRYPT_CONFIG"
if dnscrypt_apply_profile_pool clean 5053 1.1.1.1 > "$TMP_DIR/result"; then exit 1; fi
[ "$(cat "$DNS_MANAGER_DNSCRYPT_CONFIG")" = new ]
[ "$(tail -n 1 "$TMP_DIR/init-calls")" = restart ]
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

# Exercise the actual pool generator twice with persistent UCI settings.
mkdir "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/uci" <<'EOF_UCI'
#!/bin/sh
case "$*" in
    *dc_cache_size) echo 10000;;
    *dc_cache_ttl) echo 900;;
    *dc_cache) echo 1;;
    *dc_force_tcp) echo 1;;
    *dc_block_ipv6) echo 1;;
    *dc_query_log) echo 1;;
    *) exit 1;;
esac
EOF_UCI
cat > "$TMP_DIR/bin/dig" <<'EOF_DIG'
#!/bin/sh
echo 192.0.2.1
EOF_DIG
cat > "$TMP_DIR/bin/sleep" <<'EOF_SLEEP'
#!/bin/sh
exit 0
EOF_SLEEP
cat > "$TMP_DIR/real-init" <<'EOF_INIT2'
#!/bin/sh
exit 0
EOF_INIT2
cat > "$TMP_DIR/real-binary" <<'EOF_BINARY'
#!/bin/sh
exit 0
EOF_BINARY
chmod +x "$TMP_DIR/bin/uci" "$TMP_DIR/bin/dig" "$TMP_DIR/bin/sleep" "$TMP_DIR/real-init" "$TMP_DIR/real-binary"
PATH="$TMP_DIR/bin:$PATH"
DNS_MANAGER_DNSCRYPT_BIN="$TMP_DIR/real-binary"
DNS_MANAGER_DNSCRYPT_INIT="$TMP_DIR/real-init"
DNS_MANAGER_DNSCRYPT_POOL_APPLY="$ROOT/libexec/dns-manager-dnscrypt-pool-apply.sh"
DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY="$TMP_DIR/accept-dnsmasq"
printf '#!/bin/sh\nexit 0\n' > "$DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY"
export PATH DNS_MANAGER_DNSCRYPT_BIN DNS_MANAGER_DNSCRYPT_INIT DNS_MANAGER_DNSCRYPT_POOL_APPLY DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY
unset DNSMASQ_FAIL APPLY_FAIL SELECTION_FAIL

dnscrypt_select_profile() {
    case "$1" in
        clean) echo 'first|https://dns.google/dns-query';;
        family) echo 'second|https://cloudflare-dns.com/dns-query';;
        *) return 1;;
    esac
}
for profile in clean family; do
    dnscrypt_apply_profile_pool "$profile" 5053 1.1.1.1 >/dev/null
    grep -qx 'cache_size = 10000' "$DNS_MANAGER_DNSCRYPT_CONFIG"
    grep -qx 'cache_min_ttl = 900' "$DNS_MANAGER_DNSCRYPT_CONFIG"
    grep -qx 'force_tcp = true' "$DNS_MANAGER_DNSCRYPT_CONFIG"
    grep -qx 'block_ipv6 = true' "$DNS_MANAGER_DNSCRYPT_CONFIG"
    grep -qx "file = '/tmp/dns-manager-dnscrypt-query.log'" "$DNS_MANAGER_DNSCRYPT_CONFIG"
done
printf '%s\n' 'DNSCrypt tuning survives applying two different profiles'
