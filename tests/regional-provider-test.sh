#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
awk '/^regional_provider_addresses\(\) \{/,/^}/' "$ROOT/dns-manager.sh" > "$tmp/provider.sh"
. "$tmp/provider.sh"
cat > "$tmp/resolv" <<'EOF'
# Interface wan
nameserver 127.0.0.1
nameserver 0.0.0.0
nameserver 169.254.1.2
nameserver 999.1.2.3
nameserver ::1
nameserver 0:0:0:0:0:0:0:1
nameserver fe80::1
nameserver :2001::1
nameserver 2001:::1
nameserver 94.230.128.3
nameserver 94.230.128.3
nameserver 10.255.0.2
nameserver 2001:db8::1
nameserver 94.230.129.3
nameserver 8.8.8.8
EOF
expected='94.230.128.3
10.255.0.2
2001:db8::1
94.230.129.3'
[ "$(regional_provider_addresses "$tmp/resolv")" = "$expected" ] || {
    printf '%s\n' 'FAIL: provider DNS parsing' >&2
    exit 1
}
[ -z "$(regional_provider_addresses "$tmp/missing")" ] || exit 1
printf '%s\n' 'nameserver 2001:db8:1:2:3:4:5::' > "$tmp/resolv"
[ "$(regional_provider_addresses "$tmp/resolv")" = '2001:db8:1:2:3:4:5::' ] || exit 1
printf '%s\n' 'OK: provider DNS parsing'
