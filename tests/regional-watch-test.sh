#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$tmp/bin"
awk '/<<'\''EOF_REGIONAL_WATCH'\''/ {capture=1; next} capture && /^EOF_REGIONAL_WATCH$/ {exit} capture {print}' "$ROOT/dns-manager-luci.sh" |
    sed -e "s|/etc/dns-manager/config/manager.conf|$tmp/config|g" \
        -e "s|/tmp/resolv.conf.d/resolv.conf.auto|$tmp/resolv|g" \
        -e "s|/tmp/resolv.conf.auto|$tmp/fallback|g" \
        -e "s|/usr/bin/dns-manager|$tmp/manager|g" > "$tmp/watch"
[ -s "$tmp/watch" ] && sh -n "$tmp/watch"
printf "%s\n" "REGIONAL_MODE='isp'" > "$tmp/config"
printf 'nameserver 192.0.2.1\n' > "$tmp/resolv"
cat > "$tmp/manager" <<'EOF'
#!/bin/sh
printf 'call\n' >> "$REGIONAL_TEST_DIR/calls"
n=$(wc -l < "$REGIONAL_TEST_DIR/calls")
[ "$n" != 2 ]
EOF
cat > "$tmp/bin/sleep" <<'EOF'
#!/bin/sh
n=$(cat "$REGIONAL_TEST_DIR/count" 2>/dev/null || echo 0)
n=$((n+1)); echo "$n" > "$REGIONAL_TEST_DIR/count"
[ "$n" != 2 ] || printf 'nameserver 192.0.2.2\n' > "$REGIONAL_TEST_DIR/resolv"
[ "$n" != 4 ] || printf "REGIONAL_MODE='doh'\n" > "$REGIONAL_TEST_DIR/config"
EOF
chmod +x "$tmp/manager" "$tmp/bin/sleep"
REGIONAL_TEST_DIR="$tmp" PATH="$tmp/bin:$PATH" sh "$tmp/watch"
[ "$(wc -l < "$tmp/calls" | tr -d ' ')" = 3 ] || { echo 'FAIL: provider watcher did not retry a DNS-only change' >&2; exit 1; }
echo 'OK: watcher detects DNS-only changes, retries failure, and stops when mode changes'
