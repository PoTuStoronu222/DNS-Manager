#!/bin/sh
# Standalone development test: pass a local checkout of official OpenWrt UCI.
# It builds UCI with a temporary default save directory; it never touches
# /etc/config or /tmp/.uci on the host. Not part of the router test suite.
set -eu
[ "$#" = 1 ] && [ -f "$1/uci.h" ] || { echo "Usage: $0 /path/to/openwrt-uci-source" >&2; exit 2; }
src="$(cd "$1" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/src" "$tmp/config" "$tmp/override" "$tmp/shared" "$tmp/private"
cp "$src"/*.c "$src"/*.h "$tmp/src/"
sed "s|^#define UCI_SAVEDIR .*|#define UCI_SAVEDIR \"$tmp/shared\"|" "$src/uci.h" > "$tmp/src/uci.h"
: > "$tmp/src/uci_config.h"
(cd "$tmp/src" && gcc -std=gnu99 -DUCI_PREFIX='"/tmp/uci-lab"' -o "$tmp/uci" \
    cli.c libuci.c file.c util.c delta.c parse.c)
cat > "$tmp/config/dhcp" <<'EOF_DHCP'
config dnsmasq 'dns'
        list server '127.0.0.1#5053'
config host 'device'
        option name 'original'
EOF_DHCP
real_uci() { "$tmp/uci" -c "$tmp/config" -C "$tmp/override" "$@"; }
real_uci -t "$tmp/private" delete dhcp.dns.server
real_uci -t "$tmp/private" add_list dhcp.dns.server=8.8.8.8
# A different process stages this edit after a last-changes check and before
# the fallback's commit. It must not be saved by the fallback.
real_uci set dhcp.device.name=unsaved
real_uci -t "$tmp/private" commit dhcp
if grep -q "option name 'unsaved'" "$tmp/config/dhcp"; then
    echo 'FAIL: private UCI commit saved an unrelated pending change' >&2
    exit 1
fi
echo 'OK: private UCI commit did not save an unrelated pending change'
