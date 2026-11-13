#!/bin/sh
# Optional real-network lab: DNSCRYPT_BIN and DNSCRYPT_BOOTSTRAP are required.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
: "${DNSCRYPT_BIN:?Set DNSCRYPT_BIN to dnscrypt-proxy 2.1.x}"
: "${DNSCRYPT_BOOTSTRAP:?Set DNSCRYPT_BOOTSTRAP to a reachable DNS IP}"
TMP_DIR=$(mktemp -d /tmp/dnscrypt-profile-live.XXXXXX)
cleanup() {
    [ ! -s "$TMP_DIR/pid" ] || kill "$(cat "$TMP_DIR/pid")" 2>/dev/null || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
export TMP_DIR
tr -d '\r' < "$ROOT/dns-manager.sh" | awk '/^select_slot\(\) \{/{exit} /^auto_fill_slots\(\) \{/{copy=1} copy{print}' > "$TMP_DIR/auto-fill.sh"
. "$TMP_DIR/auto-fill.sh"
. "$ROOT/libexec/dns-manager-dnscrypt-profile.sh"
. "$ROOT/libexec/dns-manager-dnscrypt-profile-apply.sh"

TEST_RESULTS="$TMP_DIR/results"
printf 'cf|clean|Cloudflare|20|OK\ngg|clean|Google|30|OK\n' > "$TEST_RESULTS"
profile_apply_begin() { :; }
profile_apply_end() { :; }
ensure_test_results_fresh() { :; }
warn_msg() { :; }
pause() { :; }
slot_cat_set() { :; }
slot_set() { case "$1" in 1) SLOT_1=$2;; 2) SLOT_2=$2;; 3) SLOT_3=$2;; 4) SLOT_4=$2;; 5) SLOT_5=$2;; 6) SLOT_6=$2;; *) return 1;; esac; }
dns_url() { case "$1" in cf) printf 'https://cloudflare-dns.com/dns-query';; gg) printf 'https://dns.google/dns-query';; *) return 1;; esac; }
normalize_url() { printf '%s' "$1"; }

PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')
DNS_MANAGER_DNSCRYPT_BIN="$DNSCRYPT_BIN"
DNS_MANAGER_DNSCRYPT_INIT="$TMP_DIR/init"
DNS_MANAGER_DNSCRYPT_CONFIG="$TMP_DIR/pool.toml"
DNS_MANAGER_DNSCRYPT_POOL_APPLY="$ROOT/libexec/dns-manager-dnscrypt-pool-apply.sh"
DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY="$TMP_DIR/no-dnsmasq-change"
DNS_MANAGER_DNSCRYPT_UCI_GUARD="$TMP_DIR/guard"
printf '#!/bin/sh\nexit 0\n' > "$DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY"
: > "$DNS_MANAGER_DNSCRYPT_UCI_GUARD"
export DNS_MANAGER_DNSCRYPT_BIN DNS_MANAGER_DNSCRYPT_INIT DNS_MANAGER_DNSCRYPT_CONFIG DNS_MANAGER_DNSCRYPT_POOL_APPLY DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY DNS_MANAGER_DNSCRYPT_UCI_GUARD
printf 'https://cloudflare-dns.com/dns-query\n' | sh "$ROOT/libexec/dns-manager-dnscrypt-pool.sh" "$PORT" "$DNSCRYPT_BOOTSTRAP" > "$DNS_MANAGER_DNSCRYPT_CONFIG"
cat > "$DNS_MANAGER_DNSCRYPT_INIT" <<'EOF_INIT'
#!/bin/sh
case "$1" in
  restart)
    if [ -s "$TMP_DIR/pid" ]; then kill "$(cat "$TMP_DIR/pid")" 2>/dev/null || true; sleep 1; fi
    "$DNS_MANAGER_DNSCRYPT_BIN" -config "$DNS_MANAGER_DNSCRYPT_CONFIG" > "$TMP_DIR/proxy.log" 2>&1 &
    echo "$!" > "$TMP_DIR/pid" ;;
  running) [ -s "$TMP_DIR/pid" ] && kill -0 "$(cat "$TMP_DIR/pid")" 2>/dev/null ;;
  *) exit 1;;
esac
EOF_INIT
chmod 0755 "$DNS_MANAGER_DNSCRYPT_INIT"
# This laboratory client sends a real DNS query to the local proxy and emits a
# test address only when the DNS header confirms a successful answer.
cat > "$TMP_DIR/dig" <<'EOF_DIG'
#!/usr/bin/python3
import socket, struct, sys
port = int(sys.argv[sys.argv.index('-p') + 1])
query = struct.pack('!HHHHHH', 0x2917, 0x100, 1, 0, 0, 0) + b'\x07example\x03com\x00' + struct.pack('!HH', 1, 1)
try:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(2)
        sock.sendto(query, ('127.0.0.1', port))
        response = sock.recv(4096)
    ident, flags, qd, answers, _, _ = struct.unpack('!HHHHHH', response[:12])
    assert ident == 0x2917 and flags & 0x800f == 0x8000 and qd == 1 and answers > 0
    print('192.0.2.1')
except Exception:
    sys.exit(1)
EOF_DIG
chmod 0755 "$TMP_DIR/dig"
PATH="$TMP_DIR:$PATH"; export PATH
dnscrypt_apply_profile_pool clean "$PORT" "$DNSCRYPT_BOOTSTRAP" > "$TMP_DIR/applied"
printf 'cf|https://cloudflare-dns.com/dns-query\ngg|https://dns.google/dns-query\n' > "$TMP_DIR/expected"
cmp "$TMP_DIR/applied" "$TMP_DIR/expected"
grep -Fxq "server_names = ['manager-1', 'manager-2']" "$DNS_MANAGER_DNSCRYPT_CONFIG"
printf '%s\n' 'Selected profile applied to one real DNSCrypt process and returned a real DNS answer'
