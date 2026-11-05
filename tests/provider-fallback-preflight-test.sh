#!/bin/sh
# Read-only preflight for the future provider-DNS fallback.
set -eu
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '/^regional_provider_addresses\(\) \{/,/^}/' dns-manager.sh > "$tmp/functions"
awk '/^provider_fallback_candidates\(\) \(/,/^\)/' dns-manager.sh >> "$tmp/functions"
awk '/^provider_fallback_verified_candidates\(\) \(/,/^\)/' dns-manager.sh >> "$tmp/functions"
awk '/^provider_fallback_plan_servers\(\) \(/,/^\)/' dns-manager.sh >> "$tmp/functions"
awk '/^provider_fallback_journal_create\(\) \(/,/^\)/' dns-manager.sh >> "$tmp/functions"
awk '/^provider_fallback_journal_classify\(\) \(/,/^\)/' dns-manager.sh >> "$tmp/functions"
. "$tmp/functions"
ip() {
    printf '%s\n' '1: lo    inet 127.0.0.1/8 scope host lo' \
        '2: br-lan    inet 192.168.1.1/24 scope global br-lan' \
        '2: br-lan    inet6 2001:db8::1/64 scope global'
}
cat > "$tmp/resolv" <<'EOF_RESOLV'
nameserver 192.168.1.1
nameserver 127.0.0.1
nameserver 8.8.8.8
nameserver 224.0.0.1
EOF_RESOLV
actual="$(provider_fallback_candidates "$tmp/resolv")"
[ "$actual" = 8.8.8.8 ] || { echo "FAIL: unsafe IPv4 candidate: $actual" >&2; exit 1; }
cat > "$tmp/resolv" <<'EOF_RESOLV'
nameserver 192.168.1.1
nameserver 224.0.0.1
nameserver 225.0.0.1
nameserver 239.0.0.1
nameserver 9.9.9.9
EOF_RESOLV
actual="$(provider_fallback_candidates "$tmp/resolv")"
[ "$actual" = 9.9.9.9 ] || { echo "FAIL: later valid upstream was skipped: $actual" >&2; exit 1; }
cat > "$tmp/resolv" <<'EOF_RESOLV'
nameserver 2001:0db8:0:0:0:0:0:1
nameserver 2001:4860:4860::8888
nameserver ff02::1
EOF_RESOLV
actual="$(provider_fallback_candidates "$tmp/resolv")"
[ "$actual" = 2001:4860:4860::8888 ] || { echo "FAIL: unsafe IPv6 candidate: $actual" >&2; exit 1; }
ip() { return 1; }
if provider_fallback_candidates "$tmp/resolv" >/dev/null; then
    echo 'FAIL: candidates accepted without local interface addresses' >&2
    exit 1
fi
dig() {
    case "$1" in
        @8.8.8.8) printf '%s\n' ';; ->>HEADER<<- opcode: QUERY, status: NXDOMAIN, id: 1' ';; flags: qr rd ra; QUERY: 1' ;;
        @1.1.1.1) printf '%s\n' ';; ->>HEADER<<- opcode: QUERY, status: SERVFAIL, id: 1' ';; flags: qr rd ra; QUERY: 1' ;;
        @9.9.9.9) printf '%s\n' ';; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 1' ';; flags: rd; QUERY: 1' ;;
        *) return 1 ;;
    esac
}
printf '%s\n' 8.8.8.8 1.1.1.1 9.9.9.9 > "$tmp/probe"
actual="$(provider_fallback_verified_candidates "$tmp/probe")"
[ "$actual" = 8.8.8.8 ] || { echo "FAIL: invalid DNS probe response accepted: $actual" >&2; exit 1; }
printf '%s\n' 1.1.1.1 > "$tmp/probe"
if provider_fallback_verified_candidates "$tmp/probe" >/dev/null; then
    echo 'FAIL: unusable provider accepted' >&2
    exit 1
fi
cat > "$tmp/original" <<'EOF_ORIGINAL'
127.0.0.1#5053
127.0.0.1#5054
/example.org/127.0.0.1#5053
/ru/127.0.0.1#5059
/use-application-dns.net/
/internal/192.168.9.1
/foreign/127.0.0.1#5053
127.0.0.1#9999
EOF_ORIGINAL
printf '%s\n' 5053 5054 5059 > "$tmp/ports"
printf '%s\n' 8.8.8.8 1.1.1.1 > "$tmp/providers"
printf '%s\n' '127.0.0.1#5053' '127.0.0.1#5054' '/example.org/127.0.0.1#5053' '/ru/127.0.0.1#5059' > "$tmp/owned"
provider_fallback_plan_servers "$tmp/original" "$tmp/ports" "$tmp/providers" "$tmp/owned" > "$tmp/planned"
for line in '8.8.8.8' '1.1.1.1' '/example.org/8.8.8.8' '/example.org/1.1.1.1' \
    '/ru/8.8.8.8' '/ru/1.1.1.1' '/use-application-dns.net/' '/internal/192.168.9.1' '/foreign/127.0.0.1#5053' '127.0.0.1#9999'; do
    grep -Fxq "$line" "$tmp/planned" || { echo "FAIL: missing planned route $line" >&2; exit 1; }
done
[ "$(grep -Fxc '8.8.8.8' "$tmp/planned")" = 1 ] || exit 1
if grep -Fxq '127.0.0.1#5053' "$tmp/planned"; then echo 'FAIL: managed DoH route left in fallback' >&2; exit 1; fi
printf '/internal/192.168.9.1\n' > "$tmp/no-general"
if provider_fallback_plan_servers "$tmp/no-general" "$tmp/ports" "$tmp/providers" "$tmp/owned" > /dev/null; then
    echo 'FAIL: accepted a configuration with no managed general DNS' >&2
    exit 1
fi
printf '%s\n' '/missing.example/127.0.0.1#5053' >> "$tmp/owned"
if provider_fallback_plan_servers "$tmp/original" "$tmp/ports" "$tmp/providers" "$tmp/owned" > /dev/null; then
    echo 'FAIL: missing managed route was silently ignored' >&2
    exit 1
fi
printf 'SLOT_1=one\n' > "$tmp/config"
provider_fallback_journal_create "$tmp/journal" cfg123 "$tmp/original" "$tmp/planned" "$tmp/config"
[ "$(provider_fallback_journal_classify "$tmp/journal" "$tmp/original")" = before ] || exit 1
[ "$(provider_fallback_journal_classify "$tmp/journal" "$tmp/planned")" = after ] || exit 1
printf '/new-third-party/192.168.7.1\n' >> "$tmp/planned"
[ "$(provider_fallback_journal_classify "$tmp/journal" "$tmp/planned")" = changed ] || exit 1
if provider_fallback_journal_create "$tmp/journal" cfg123 "$tmp/original" "$tmp/planned" "$tmp/config"; then
    echo 'FAIL: replaced an existing recovery journal' >&2
    exit 1
fi
printf '%s\n' 'bad;section' > "$tmp/journal/section"
if provider_fallback_journal_classify "$tmp/journal" "$tmp/original" > /dev/null; then
    echo 'FAIL: accepted a damaged recovery journal' >&2
    exit 1
fi
printf '%s\n' cfg123 > "$tmp/journal/section"
rm "$tmp/journal/ready"
if provider_fallback_journal_classify "$tmp/journal" "$tmp/original" > /dev/null; then
    echo 'FAIL: accepted an incomplete recovery journal' >&2
    exit 1
fi
echo 'OK: fallback candidate, route and recovery-journal preflight'
