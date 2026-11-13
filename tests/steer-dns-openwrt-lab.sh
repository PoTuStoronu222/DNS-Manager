#!/bin/sh
# Only for a disposable OpenWrt lab in an isolated network namespace.
# Checks Steer dnsd forwarding; this does not apply or validate nftables rules.
set -eu
[ "${DNSCRYPT_DISPOSABLE_LAB:-0}" = 1 ] || { echo "Disposable lab required" >&2; exit 2; }
dir=$(mktemp -d /tmp/dnscrypt-steer.XXXXXX)
dns=''
steer=''
cleanup() { [ -z "$steer" ] || kill "$steer" 2>/dev/null || :; [ -z "$dns" ] || kill "$dns" 2>/dev/null || :; rm -rf "$dir"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir -p /var/run "$dir/state"
printf '%s\n' blocked.test > "$dir/blocked.dom"
cat > "$dir/spec.yaml" <<EOF
version: 2
lan: { devices: [br-lan] }
lists:
  blocked: { domains_file: $dir/blocked.dom }
outputs:
  vpn: { kind: interface, device: wg0, on_fail: drop }
rules:
  - { name: blocked, to: [blocked], out: vpn }
EOF
/usr/sbin/dnsmasq -k --conf-file=/dev/null --user=root --group=root --no-resolv --no-hosts --port=25664 --listen-address=127.0.0.1 --address=/plain.test/192.0.2.55 >"$dir/dnsmasq.log" 2>&1 &
dns=$!
/usr/sbin/steerd dnsd --spec "$dir/spec.yaml" --state-dir "$dir/state" --listen-port 15300 --upstream-port 25664 >"$dir/steer.log" 2>&1 &
steer=$!
sleep 2
if nslookup -type=A -port=15300 plain.test 127.0.0.1 >"$dir/answer" 2>&1 && grep -q 192.0.2.55 "$dir/answer"; then
    echo 'PASS: Steer forwards an ordinary DNS request to dnsmasq'
else
    cat "$dir/dnsmasq.log" "$dir/steer.log" "$dir/answer" >&2
    exit 1
fi
