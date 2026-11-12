#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
awk '/^dmd_ensure_profile\(\) \{/{p=1} /^dmd_build_and_install\(\) \{/{p=0} p{print}' "$ROOT/dns-manager-luci.sh" |
    sed 's|/usr/sbin/dnsmasq|mock_dnsmasq|' > "$tmp/profile.sh"
. "$tmp/profile.sh"
dmd_slot_id() { echo one; }
dmd_slot_port() { echo 5053; }
dmd_slot_domains() { printf '%s' "${SLOT_1_DOMAINS:-}"; }
dmd_upstream_port_exists() { return 0; }
dmd_port_busy() { return 1; }
dmd_mask_for_slots() { echo 1; }
dmd_log() { :; }
mock_dnsmasq() { return 0; }
DMD_LAN_DEV=br-lan
for REGIONAL_MODE in doh yandex isp legacy; do
    DMD_STAGE="$tmp/$REGIONAL_MODE"
    mkdir -p "$DMD_STAGE/profiles"
    : > "$DMD_STAGE/profiles.map"
    SLOT_RU='' PORT_RU='' REGIONAL_ISP_IPS='94.230.128.3 10.255.0.2'
    [ "$REGIONAL_MODE" != legacy ] || { SLOT_RU=regional; PORT_RU=5059; }
    SLOT_1_DOMAINS='Avito.St images.wbstatic.net'
    dmd_ensure_profile 1 device >/dev/null
    profile="$DMD_STAGE/profiles/profile_1.conf"
    grep -Fxq 'server=/avito.st/127.0.0.1#5053' "$profile"
    grep -Fxq 'server=/images.wbstatic.net/127.0.0.1#5053' "$profile"
    ! grep -Fq 'server=/avito.st/77.88.8.' "$profile"
    ! grep -Fq 'server=/avito.st/94.230.128.' "$profile"
    ! grep -Fq 'server=/avito.st/127.0.0.1#5059' "$profile"
    case "$REGIONAL_MODE" in
        doh) ! grep -q '^server=/wbstatic.net/' "$profile" ;;
        yandex) grep -Fxq 'server=/wbstatic.net/77.88.8.8' "$profile" ;;
        isp) grep -Fxq 'server=/wbstatic.net/94.230.128.3' "$profile" ;;
        legacy) grep -Fxq 'server=/wbstatic.net/127.0.0.1#5059' "$profile" ;;
    esac
done
echo 'OK: device DNS profiles preserve regional modes and explicit domain priority'
