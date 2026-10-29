#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"

fail() {
    printf '%s\n' "FAIL: $*" >&2
    exit 1
}
ok() {
    printf '%s\n' "OK: $*"
}

sh -n dns-manager.sh || fail "dns-manager.sh: sh -n"
sh -n dns-manager-luci.sh || fail "dns-manager-luci.sh: sh -n"
sh -n tests/openwrt-luci-smoke.sh || fail "tests/openwrt-luci-smoke.sh: sh -n"
ok "shell syntax"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

# The uninstall request starts a separate supervised process, so rpcd reload
# cannot stop the removal. Exercise the RPC helper without touching OpenWrt.
awk '/^uninstall_start_json\(\) \{/,/^run_action\(\) \{/' dns-manager-luci.sh | sed '$d' | sed -e "s|/var/run/dns-manager-uninstall|$tmp/uninstall-job|g" -e "s|/www/dns-manager-uninstall|$tmp/dns-manager-uninstall|g" > "$tmp/uninstall_start.sh"
cat > "$tmp/uninstall_start_runner.sh" <<'EOF_UNINSTALL_START_TEST'
#!/bin/sh
set -eu
MANAGER="$1/manager"
touch "$MANAGER"
chmod +x "$MANAGER"
. "$1/uninstall_start.sh"
json_error() { printf 'ERROR:%s\n' "$1"; }
json_quote() { node -e 'process.stdout.write(JSON.stringify(process.argv[1]))' "$1"; }
ubus() {
    case "$1:$2:$3" in
        call:service:list) printf '{}\n'; return 0 ;;
        call:service:set)
            case "$4" in *'"name":"dns-manager-uninstall"'*'SILENT_APPLY=1 /usr/bin/dns-manager --uninstall'*) printf '%s' "$4" > "$UNINSTALL_TEST_WORKER"; return 0;; esac
            return 1 ;;
        *) return 1 ;;
    esac
}
UNINSTALL_TEST_WORKER="$1/worker-started"
uninstall_start_json > "$1/uninstall-reply"
grep -q '"ok":true,"status_url":' "$1/uninstall-reply"
[ -f "$1/worker-started" ]
EOF_UNINSTALL_START_TEST
sh "$tmp/uninstall_start_runner.sh" "$tmp" || fail "LuCI uninstall worker did not start via procd"
node - "$tmp/worker-started" <<'EOF_UNINSTALL_JSON_TEST' || fail "uninstall procd request is not valid JSON"
const request = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
const command = request.instances.main.command;
if (request.name !== 'dns-manager-uninstall' || command[0] !== '/bin/sh' || command[1] !== '-c' ||
    !command[2].includes('SILENT_APPLY=1 /usr/bin/dns-manager --uninstall') ||
    !command[2].includes('ubus call service delete') || !command[4].includes('dns-manager-uninstall.')) process.exit(1);
EOF_UNINSTALL_JSON_TEST
ok "LuCI uninstall starts a separate procd worker"

# The generated per-device dnsmasq/firewall service is shell-checked independently of the installer heredoc.
awk '/cat > \/etc\/init.d\/dns-manager-device-dns <<'\''EOF_DEVICE_DNS_SERVICE'\''/ {capture=1; next} capture && /^EOF_DEVICE_DNS_SERVICE$/ {exit} capture {print}' dns-manager-luci.sh > "$tmp/device_dns_service.sh"
[ -s "$tmp/device_dns_service.sh" ] || fail "per-device DNS service heredoc missing"
sh -n "$tmp/device_dns_service.sh" || fail "per-device DNS service shell syntax"
grep -Fq 'DMD_CHAIN="dstnat_lan"' "$tmp/device_dns_service.sh" || fail "per-device DNS rules target the wrong fw4 chain"
grep -Fq 'START=99' "$tmp/device_dns_service.sh" || fail "per-device DNS service can start before https-dns-proxy at boot"
grep -Fq 'pid-file=/var/run/dns-manager-device-dns/profile_%s.pid' "$tmp/device_dns_service.sh" || fail "per-device dnsmasq instances do not have unique PID files"
grep -Fq 'position=chain-pre' "$tmp/device_dns_service.sh" || fail "per-device DNS rules are not inserted ahead of generic redirects"
grep -Fq 'Never overwrite' "$tmp/device_dns_service.sh" || fail "per-device DNS service does not document ownership preflight"
grep -Fq 'dmd_include_is_owned || {' "$tmp/device_dns_service.sh" || fail "per-device DNS service does not verify include ownership before writing"
grep -Fq 'fw4 print > "$DMD_FW4_CHECK"' "$tmp/device_dns_service.sh" || fail "per-device ruleset is not validated before reload"
grep -Fq 'nft -c -f "$DMD_FW4_CHECK"' "$tmp/device_dns_service.sh" || fail "per-device nft rules are not syntax-checked"
if grep -Fq 'type nat hook prerouting' "$tmp/device_dns_service.sh"; then fail "per-device service must not create a competing base NAT chain"; fi
grep -Fq 'ether saddr %s udp dport 53 redirect to :%s' "$tmp/device_dns_service.sh" || fail "per-device UDP DNS redirect missing"
grep -Fq 'ether saddr %s tcp dport 53 redirect to :%s' "$tmp/device_dns_service.sh" || fail "per-device TCP DNS redirect missing"
grep -Fq 'all-servers' "$tmp/device_dns_service.sh" || fail "multi-DoH device profiles do not query all selected upstreams"
grep -Fq 'dmd_slot_domains()' "$tmp/device_dns_service.sh" || fail "per-device profiles do not read slot-specific domain overrides"
grep -Fq 'server=/%s/127.0.0.1#%s' "$tmp/device_dns_service.sh" || fail "per-device profiles do not preserve slot domain overrides"
grep -Fq 'for _dmd_tld in /ru /su /xn--p1ai' "$tmp/device_dns_service.sh" || fail "per-device profiles do not preserve the regional DNS route"
grep -Fq 'server=/use-application-dns.net/' "$tmp/device_dns_service.sh" || fail "per-device profiles do not inherit encrypted-DNS canary protection"
grep -Fq 'iifname "%s" ether saddr %s udp dport 53 redirect to :%s' "$tmp/device_dns_service.sh" || fail "per-device redirect is not scoped to LAN"
grep -Fq 'dmd_fail_open()' "$tmp/device_dns_service.sh" || fail "per-device DNS service has no fail-open cleanup"
grep -Fq 'stop_service() {' "$tmp/device_dns_service.sh" || fail "stopping the per-device DNS service leaves redirects installed"
grep -Fq 'dmd_upstream_port_exists()' "$tmp/device_dns_service.sh" || fail "per-device DNS service does not check selected DoH listeners"
grep -Fq 'listener_port_exists "$DMD_RPC_PORT"' dns-manager-luci.sh || fail "RPC can save a device binding to a missing DoH listener"
grep -Fq 'gsub(/[[:space:]]/, ""); if ($0 !~ /^[1-6](,[1-6])*$/)' dns-manager-luci.sh || fail "RPC does not validate its comma-separated device DNS slot list"
grep -Fq "grep -q '[^1-6,[:space:]]'" "$tmp/device_dns_service.sh" || fail "device DNS service does not validate saved slot characters"
grep -Fq 'DMD_NFT_TMP="$(mktemp "$DMD_NFT.tmp.XXXXXX"' dns-manager-luci.sh || fail "per-device nft snippet update does not use a unique temporary file"
grep -Fq 'set_device_dns)' dns-manager-luci.sh || fail "set-device-DNS RPC dispatch missing"
grep -Fq '"set_device_dns":{"mac":"String","slots":"String"}' dns-manager-luci.sh || fail "set-device-DNS RPC schema missing"
grep -Fq '"dns_manager": [ "set_profile", "reset_dns", "set_slot", "set_slot_domains", "set_device_dns"' dns-manager-luci.sh || fail "set-device-DNS RPC is missing from the write ACL"
grep -Fq 'callSetDeviceDns' dns-manager-luci.sh || fail "LuCI has no client for set-device-DNS RPC"
grep -Fq 'card(' "dns-manager-luci.sh" >/dev/null || fail "LuCI card renderer missing"
ok "per-device DNS service, per-MAC nft redirects and multi-DoH assignment contract"

awk '/^dmd_normalize_slots\(\) \{/,/^}/' "$tmp/device_dns_service.sh" > "$tmp/device_dns_normalize.sh"
[ -s "$tmp/device_dns_normalize.sh" ] || fail "per-device slot normalizer missing"
(
    . "$tmp/device_dns_normalize.sh"
    [ "$(dmd_normalize_slots '2,1,2')" = '1,2' ] || fail "per-device multi-slot normalizer does not sort and deduplicate slot IDs"
    if dmd_normalize_slots '1,*' >/dev/null 2>&1; then fail "per-device slot normalizer accepts glob characters"; fi
) || fail "per-device multi-slot normalization"
awk '/^dmd_mask_for_slots\(\) \{/,/^}/' "$tmp/device_dns_service.sh" > "$tmp/device_dns_mask.sh"
[ -s "$tmp/device_dns_mask.sh" ] || fail "per-device slot mask helper missing"
(
    . "$tmp/device_dns_mask.sh"
    [ "$(dmd_mask_for_slots '1')" = '1' ] || fail "single DNS slot maps to the wrong listener profile"
    [ "$(dmd_mask_for_slots '1,2')" = '3' ] || fail "two DNS slots do not map to a shared listener profile"
    [ "$(dmd_mask_for_slots '1,2,6')" = '35' ] || fail "multi-slot DNS profile mask is not deterministic"
) || fail "per-device DNS listener profile mapping"
grep -Fq 'refresh_device_dns_runtime' dns-manager.sh || fail "main DNS Manager does not resync per-device listeners"
grep -Fq 'lan_devices":{}' dns-manager.sh || fail "manager-side LuCI health check omits the LAN device inventory RPC"
grep -Fq 'set_device_dns":{"mac":"String","slots":"String"}' dns-manager.sh || fail "manager-side LuCI health check omits the per-device DNS assignment RPC"
awk '/^luci_companion_remove_fallback\(\) \{/,/^}/' dns-manager.sh > "$tmp/luci_remove_fallback.sh"
[ -s "$tmp/luci_remove_fallback.sh" ] || fail "manager fallback uninstall helper extraction"
grep -Fq 'firewall.dns_manager_device_dns.path' "$tmp/luci_remove_fallback.sh" || fail "manager fallback uninstall does not check ownership of the fw4 include"
grep -Fq 'firewall.dns_manager_device_dns 2>/dev/null || true' "$tmp/luci_remove_fallback.sh" || fail "manager fallback cleanup does not validate the UCI section type"
awk '/^slot_domains_apply\(\) \{/,/^}/' dns-manager.sh > "$tmp/slot_domains_apply.sh"
grep -Fq 'refresh_device_dns_runtime' "$tmp/slot_domains_apply.sh" || fail "slot domain edits do not refresh per-device DNS listeners"
awk '/^_apply_extras_now_impl\(\) \{/,/^}/' dns-manager.sh > "$tmp/extras_apply.sh"
awk '/encrypted_dns\)/,/;;/' "$tmp/extras_apply.sh" > "$tmp/encrypted_dns_apply.sh"
grep -Fq 'refresh_device_dns_runtime' "$tmp/encrypted_dns_apply.sh" || fail "encrypted-DNS toggle does not refresh per-device canary profiles"
grep -Fq 'dns_manager_device_dns' dns-manager-luci.sh || fail "LuCI uninstall does not clean up the owned firewall include"
grep -Fq 'uci -q delete firewall.dns_manager_device_dns' dns-manager-luci.sh || fail "LuCI uninstall does not remove its owned UCI include"
grep -Fq '/etc/dns-manager/device-dns/redirects.nft' dns-manager-luci.sh || fail "per-device rules include path missing"
grep -Fq '90-dns-manager-device-dns.nft' "$tmp/luci_remove_fallback.sh" || fail "Manager fallback uninstall leaves legacy per-device rules"
grep -Fq "card('Устройства LAN — привязка к DoH'" dns-manager-luci.sh || fail "per-device DNS assignment UI missing"



# Per-slot DNS domain routing uses dnsmasq server=/domain/127.0.0.1#port rules.
awk '/^normalize_slot_domains\(\) \{/,/^slot_domains_get\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/normalize_slot_domains.sh"
[ -s "$tmp/normalize_slot_domains.sh" ] || fail "domain normalizer extraction"
cat > "$tmp/normalize_slot_domains_runner.sh" <<'EOF_DNS_DOMAINS'
#!/bin/sh
set -eu
. "$1"
got="$(normalize_slot_domains 'YouTube.COM.,example.org example.org')"
[ "$got" = 'youtube.com example.org' ] || { printf '%s\n' "unexpected normalized domains: $got" >&2; exit 51; }
if normalize_slot_domains 'https://example.com' >/dev/null 2>&1; then exit 52; fi
if normalize_slot_domains 'example..com' >/dev/null 2>&1; then exit 53; fi
if normalize_slot_domains '-bad.example' >/dev/null 2>&1; then exit 54; fi
if normalize_slot_domains 'plainword' >/dev/null 2>&1; then exit 55; fi
EOF_DNS_DOMAINS
chmod +x "$tmp/normalize_slot_domains_runner.sh"
"$tmp/normalize_slot_domains_runner.sh" "$tmp/normalize_slot_domains.sh" || fail "domain input validation and normalization"
ok "domain input validation rejects malformed hosts and normalizes duplicates"

awk '/^normalize_slot_domains\(\) \{/,/^slot_domains_set\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/slot_domains_get.sh"
awk '/^watchdog_expected_servers\(\) \{/,/^}/' dns-manager.sh > "$tmp/watchdog_expected_servers.sh"
[ -s "$tmp/slot_domains_get.sh" ] || fail "slot domain getter extraction"
[ -s "$tmp/watchdog_expected_servers.sh" ] || fail "Watchdog expected DNS extraction"
cat > "$tmp/watchdog_expected_domains_runner.sh" <<'EOF_WATCHDOG_DOMAIN_EXPECTED'
#!/bin/sh
set -eu
TMP_DIR="$1"
mkdir -p "$TMP_DIR"
SLOT_1=resolver1; PORT_1=5053; SLOT_1_DOMAINS='youtube.com googlevideo.com'
SLOT_2=resolver2; PORT_2=5054; SLOT_2_DOMAINS='netflix.com'
SLOT_3=; PORT_3=; SLOT_3_DOMAINS=
SLOT_4=; PORT_4=; SLOT_4_DOMAINS=
SLOT_5=; PORT_5=; SLOT_5_DOMAINS=
SLOT_6=; PORT_6=; SLOT_6_DOMAINS=
TLD_RU_ENABLED=1; SLOT_RU=regional; PORT_RU=5059
. "$2"
. "$3"
expected="$(watchdog_expected_servers)"
grep -Fqx '127.0.0.1#5053' "$expected" || exit 61
grep -Fqx '/youtube.com/127.0.0.1#5053' "$expected" || exit 62
grep -Fqx '/googlevideo.com/127.0.0.1#5053' "$expected" || exit 63
grep -Fqx '/netflix.com/127.0.0.1#5054' "$expected" || exit 64
grep -Fqx '/ru/127.0.0.1#5059' "$expected" || exit 65
if grep -Fqx '/youtube.com/127.0.0.1#5054' "$expected"; then exit 66; fi
EOF_WATCHDOG_DOMAIN_EXPECTED
chmod +x "$tmp/watchdog_expected_domains_runner.sh"
"$tmp/watchdog_expected_domains_runner.sh" "$tmp/watchdog-domain-state" "$tmp/slot_domains_get.sh" "$tmp/watchdog_expected_servers.sh" || fail "Watchdog expected-domain rules"
grep -Fq 'val="/$_domain/127.0.0.1#$p"' dns-manager.sh || fail "dnsmasq does not route configured domains to their slot port"
grep -Fq 'SLOT_1_DOMAINS=$(shell_quote "$SLOT_1_DOMAINS")' dns-manager.sh || fail "domain assignments are not persisted"
grep -Fq 'SLOT_6_DOMAINS=$(shell_quote "$SLOT_6_DOMAINS")' dns-manager.sh || fail "domain assignments are not persisted for every slot"
grep -Fq 'set_slot_domains)' dns-manager-luci.sh || fail "LuCI domain update RPC is missing"
grep -Fq "method:'set_slot_domains'" dns-manager-luci.sh || fail "LuCI domain save call is missing"
grep -Fq 'Домены только через ' dns-manager-luci.sh || fail "LuCI slot domain editor is missing"
ok "dnsmasq and Watchdog preserve per-slot domain routes"



# Uninstall must remove the empty, namespaced LuCI backend directory.
sed -n '/^luci_companion_remove(/,/^}/p' dns-manager.sh > "$tmp/luci_remove_fn.sh"
[ -s "$tmp/luci_remove_fn.sh" ] || fail "LuCI uninstall helper extraction"
grep -Fq 'rmdir /usr/lib/dns-manager-luci 2>/dev/null || true' "$tmp/luci_remove_fn.sh" || fail "LuCI uninstall leaves the empty backend directory"
ok "LuCI uninstall removes its empty backend directory"

# mktemp output must stay in place until the downloader opens it.
_catalog_download_block="$(sed -n '/^catalog_download() {/,/^}/p' dns-manager.sh)"
if printf '%s\n' "$_catalog_download_block" | grep -Fq 'rm -f "$_out"'; then
    fail "catalog downloader unlinks its unique output path before writing"
fi
_write_catalogs_block="$(sed -n '/^write_catalogs() {/,/^}/p' dns-manager.sh)"
printf '%s\n' "$_write_catalogs_block" | awk '
    /_catalog_tmp=.*mktemp/ { seen=1; next }
    seen && index($0, "rm -f \"$_catalog_tmp\"") && !download_started { bad=1 }
    seen && index($0, "catalog_download \"$_catalog_tmp\"") { download_started=1; exit }
    END { if (bad || !download_started) exit 1 }
' || fail "catalog temp file is removed before download starts"
ok "catalog downloader preserves its unique temporary file"


# Update-chain regression checks: temporary names must keep the PID suffix, and
# installed LuCI version detection must trust the code LuCI actually loads.
if grep -Fq '_actual="$TMP_DIR/steer-dns-actual-$"' dns-manager.sh; then
    fail "truncated PID suffix remains in Steer temporary file"
fi
if grep -Fq '_test_source="$TMP_DIR/test-source-$"' dns-manager.sh; then
    fail "truncated PID suffix remains in DNS test source"
fi
if grep -Fq '_cb="$(date +%s 2>/dev/null || printf 0)-$"' dns-manager-luci.sh; then
    fail "truncated PID suffix remains in LuCI cache-buster"
fi
awk '/^luci_installed_version\(\) \{/,/^}$/ { print }' dns-manager.sh > "$tmp/luci_version_fn.sh"
[ -s "$tmp/luci_version_fn.sh" ] || fail "LuCI installed-version helper extraction"
(
    set -eu
    . "$tmp/luci_version_fn.sh"
    LUCI_VIEW_FILE="$tmp/view"
    LUCI_STATE_FILE="$tmp/state"
    LUCI_COMPANION_CACHE="$tmp/cache"
    printf "%s\\n" "// DNS Manager LuCI version: 9.9.9" > "$LUCI_VIEW_FILE"
    printf "%s\\n" "version=8.8.8" > "$LUCI_STATE_FILE"
    printf "%s\\n" "# Version: 7.7.7" > "$LUCI_COMPANION_CACHE"
    [ "$(luci_installed_version)" = "9.9.9" ] || exit 1
    rm -f "$LUCI_VIEW_FILE"
    [ "$(luci_installed_version)" = "8.8.8" ] || exit 2
    rm -f "$LUCI_STATE_FILE"
    [ "$(luci_installed_version)" = "7.7.7" ] || exit 3
) || fail "LuCI installed-version source order"
ok "update-chain temporary names and LuCI version detection"

# Self-update must not lose the interactive terminal when replacing the running shell.
grep -Fq 'exec </dev/tty >/dev/tty 2>&1' dns-manager.sh || fail "self-update TTY recovery is missing"
grep -Fq '    DNS_MANAGER_SCHEDULED_UPDATE=1 auto_update_manager || true' dns-manager.sh || fail "startup update check is not using scheduled throttling"
grep -Fq 'uclient-fetch -q -T 15 -O "$_upd_tmp" "$_update_url"' dns-manager.sh || fail "Manager update uclient-fetch has no timeout"
grep -Fq 'uclient-fetch -q -T 30 -O "$_tmp" "$_fetch_url"' dns-manager.sh || fail "LuCI companion fetch uclient-fetch has no timeout"
ok "startup self-update output and fetch timeouts are bounded"


# LuCI update must not remove the current interface before the new installer
# has been successfully validated and installed.
awk '/^luci_companion_update\(\) \{/,/^luci_companion_install\(\) \{/ { print }' dns-manager.sh > "$tmp/luci_update_fn.sh"
[ -s "$tmp/luci_update_fn.sh" ] || fail "LuCI manager update function extraction"
if grep -Fq 'luci_companion_remove' "$tmp/luci_update_fn.sh"; then
    fail "Manager-side LuCI update still removes the current interface before installing the replacement"
fi
grep -Fq '_cache_stage=' dns-manager.sh || fail "Manager-side LuCI update has no staged installer cache"
grep -Fq '.new.$' dns-manager.sh || fail "Manager-side LuCI update stage is not PID-unique"
grep -Fq 'luci_component_runtime_valid' dns-manager.sh || fail "Manager-side LuCI update does not validate the installed runtime"
grep -Fq 'luci_component_files_present' dns-manager.sh || fail "Manager-side LuCI update does not validate installed files"
grep -Fq 'mv -f "$_cache_stage" "$_installed_cache"' dns-manager.sh || fail "Manager-side LuCI update does not promote the staged installer after success"
ok "LuCI update is non-destructive and staged"
awk '/^luci_component_state\(\) \{/,/^\}/ { print }' dns-manager.sh > "$tmp/luci_state_fn.sh"
grep -Fq 'LUCI_VIEW_DIR="/www/luci-static/resources/view/dns-manager"' dns-manager.sh || fail "manager-side LuCI view directory is stale"
grep -Fq 'LUCI_COMMON_FILE="/www/luci-static/resources/dns-manager/common.js"' dns-manager.sh || fail "manager-side LuCI common path is stale"
if grep -Fq '/www/luci-static/resources/view/dns_manager/overview.js' dns-manager.sh; then fail "legacy LuCI overview path remains"; fi
grep -Fq 'ubus -v list dns_manager' "$tmp/luci_state_fn.sh" || fail "manager-side LuCI state does not inspect RPC methods"
ok "LuCI runtime validation checks the current page layout and RPC contract"

# Keep DoH response acceptance aligned with the known-working main branch.
# The test verifies that an HTTP 200 response has a DNS-message content type
# and a non-empty payload at least as large as a DNS header; it does not parse
# every resolver's answer packet.
for _fn in validate_dns_message normalize_url; do
    awk -v fn="$_fn" '$0 ~ ("^" fn "\\(\\) \\{") { capture=1 } capture { print } capture && /^}$/ { exit }' dns-manager.sh > "$tmp/$_fn.sh"
    [ -s "$tmp/$_fn.sh" ] || fail "DNS helper extraction: $_fn"
    . "$tmp/$_fn.sh"
done

printf '\000\000\000\000\000\001\000\000\000\000\000' > "$tmp/dns-short"
if validate_dns_message "$tmp/dns-short"; then fail "short DNS body accepted"; fi
printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$tmp/dns-query"
validate_dns_message "$tmp/dns-query" || fail "DNS message with a complete header rejected"

[ "$(normalize_url 'https://doh.cleanbrowsing.org/doh/security-filter/')" = 'https://doh.cleanbrowsing.org/doh/security-filter/' ] || fail "DoH path trailing slash was stripped"
[ "$(normalize_url 'https://dns.example/')" = 'https://dns.example' ] || fail "origin-root slash normalization changed"

ok "Main-compatible DNS response acceptance and URL path regression checks"
awk '
    /cat > "[^"]*BACKEND_STAGE[^"]*"[^<]*<<\x27EOF_RPC\x27/ { capture=1; next }
    capture && /^EOF_RPC$/ { exit }
    capture { print }
' dns-manager-luci.sh > "$tmp/backend.sh"
[ -s "$tmp/backend.sh" ] || fail "embedded backend extraction"
sh -n "$tmp/backend.sh" || fail "embedded backend: sh -n"
ok "embedded backend syntax"

# The dashboard and Network Tuning use different RPC read methods. Both must
# expose the saved auto-replacement flag; otherwise the tuning toggle renders
# a false "off" state even while manager.conf contains WATCHDOG_AUTOREPLACE=1.
awk '/^network_status_json\(\) \{/,/^time_status_json\(\) \{/' "$tmp/backend.sh" | sed '$d' > "$tmp/network_status_json.sh"
[ -s "$tmp/network_status_json.sh" ] || fail "network status JSON helper extraction"
grep -Fq 'watchdog_autoreplace":%s' "$tmp/network_status_json.sh" || fail "network status RPC omits Watchdog auto-replacement state"
ok "network tuning reports the saved Watchdog auto-replacement state"
grep -Fq "printf ',\"watchdog_autoreplace\":%s'" "$tmp/network_status_json.sh" || fail "network status auto-replacement JSON has invalid quote escaping"
ok "network tuning auto-replacement JSON uses valid quoting"



awk '
    /cat > "[^"]*COMMON_STAGE[^"]*"[^<]*<<\x27EOF_COMMON\x27/ { capture=1; next }
    capture && /^EOF_COMMON$/ { exit }
    capture { print }
' dns-manager-luci.sh > "$tmp/common.js"
[ -s "$tmp/common.js" ] || fail "embedded JS extraction"
node --check "$tmp/common.js" >/dev/null 2>&1 || fail "embedded JS: node --check"
ok "embedded LuCI JS syntax"
awk '/^function forceMode\(st\)/,/^function dateText\(v\)/' "$tmp/common.js" | sed '$d' > "$tmp/force_mode.js"
FORCE_MODE_JS="$tmp/force_mode.js" node <<'NODE' || fail "forced-DNS control must reflect the saved Manager setting"
const vm = require('vm'), fs = require('fs');
const s = {};
vm.createContext(s);
vm.runInContext(fs.readFileSync(process.env.FORCE_MODE_JS, 'utf8'), s);
for (const [state, expected] of [
  [{force:'0', force_owner:'steer', force_status:'other'}, 'off'],
  [{force:'1', force_owner:'steer', force_status:'steer'}, 'auto'],
  [{force:'1', force_owner:'external', force_status:'external'}, 'auto'],
  [{force:'0', force_owner:'external', force_status:'external'}, 'off']
]) if (s.forceMode(state) !== expected) throw Error(JSON.stringify(state));
NODE
ok "forced-DNS control follows the saved Manager setting with Steer and external interception"

# Dashboard must overlay authoritative forced-DNS ownership from doh_status;
# status_json intentionally stays lightweight and does not carry those fields.
sed -n '/^function routeStatusCall()/,/^}/p' "$tmp/common.js" > "$tmp/route_status_call.js"
grep -Fq "case 'dashboard':" "$tmp/route_status_call.js" || fail "dashboard status route missing"
grep -Fq 'callStatus(0),' "$tmp/route_status_call.js" || fail "dashboard status source missing"
grep -Fq 'callDohStatus()' "$tmp/route_status_call.js" || fail "dashboard does not fetch forced-DNS runtime state"
grep -Fq "'force','force_external','force_owner','force_manager','force_both'" "$tmp/route_status_call.js" || fail "dashboard does not merge forced-DNS ownership fields"
grep -Fq 'if(Object.prototype.hasOwnProperty.call(force,k))st[k]=force[k];' "$tmp/route_status_call.js" || fail "dashboard discards forced-DNS runtime state"
ok "dashboard uses authoritative forced-DNS runtime status"

# Dashboard must combine its detailed status with the runtime forced-DNS
# ownership result, otherwise its component can falsely say "disabled".
awk '/^function routeStatusCall\(\)/,/^function ensureStatusPromise\(\)/' "$tmp/common.js" | sed '$d' > "$tmp/route_status_call.js"
[ -s "$tmp/route_status_call.js" ] || fail "LuCI routeStatusCall extraction"
ROUTE_STATUS_JS="$tmp/route_status_call.js" node <<'NODE' || fail "dashboard forced-DNS runtime status regression"
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(process.env.ROUTE_STATUS_JS, 'utf8');
const sandbox = {
  currentRoute: () => 'dashboard',
  callStatus: () => Promise.resolve({ok: true, watchdog: '1', force_manager: 0}),
  callDohStatus: () => Promise.resolve({
    ok: true, force_manager: 1, force_owner: 'manager',
    force_status: 'manager', force_state: 1, force_both: 0
  })
};
vm.createContext(sandbox);
vm.runInContext(source, sandbox);
sandbox.routeStatusCall().then(st => {
  if (st.watchdog !== '1') throw new Error('dashboard detailed status was lost');
  if (st.force_manager !== 1 || st.force_owner !== 'manager' ||
      st.force_status !== 'manager' || st.force_state !== 1) {
    throw new Error('dashboard did not use runtime forced-DNS status');
  }
}).catch(err => { console.error(err); process.exitCode = 1; });
NODE
ok "dashboard merges runtime forced-DNS ownership state"

# Selected slot assignments must remain visible even when live DoH-instance
# detection cannot associate one of the running instances with its slot.
grep -Fq 'function displayDnsRows(st){' "$tmp/common.js" || fail "selected-DNS display normalizer is missing"
awk '/^function renderOverview\(root,st\)/,/^}/' "$tmp/common.js" > "$tmp/overview_dns.js"
grep -Fq 'displayDnsRows(st).forEach(function(d){' "$tmp/overview_dns.js" || fail "dashboard DNS list does not use saved slot assignments"
awk '/^function resolverRows\(st,root\)/,/^}/' "$tmp/common.js" > "$tmp/resolver_rows.js"
grep -Fq 'rows=displayDnsRows(st)' "$tmp/resolver_rows.js" || fail "DoH tab does not use saved slot assignments"
COMMON_JS="$tmp/common.js" node <<'NODE' || fail "selected DNS visibility regression"
const fs = require('fs');
const vm = require('vm');
const source = fs.readFileSync(process.env.COMMON_JS, 'utf8');
const match = source.match(/function displayDnsRows\(st\)\{[\s\S]*?\n\}/);
if (!match) throw new Error('displayDnsRows function could not be extracted');
const sandbox = {
  checkInfo: function (id, d) {
    return { status: String((d && d.status) || ''), ping: String((d && d.ping) || '') };
  }
};
vm.createContext(sandbox);
vm.runInContext(match[0], sandbox);
const rows = sandbox.displayDnsRows({
  slots: [
    { slot: '1', id: 'resolver-a', name: 'Resolver A', port: '5053', status: 'OK', ping: '12' },
    { slot: '2', id: 'resolver-b', name: 'Resolver B', port: '5054', status: 'OK', ping: '18' },
    { slot: '3', id: '', name: 'Не задан', port: '5055' }
  ],
  doh_instances: [
    { slot: '', id: 'legacy-id', name: 'Detected instance', port: '5053', status: 'OK', ping: '12' },
    { slot: '', id: 'system-id', name: 'System resolver', port: '5300', status: 'OK', ping: '10' }
  ]
});
if (rows.length !== 3) throw new Error('expected two selected slots and one unrelated system resolver; got ' + rows.length);
if (rows[0].slot !== '1' || rows[0].id !== 'resolver-a' || rows[0].name !== 'Resolver A') throw new Error('first selected DNS was not preserved');
if (rows[1].slot !== '2' || rows[1].id !== 'resolver-b' || rows[1].name !== 'Resolver B') throw new Error('selected DNS was lost when no live instance matched it');
if (rows[2].slot !== '' || rows[2].name !== 'System resolver') throw new Error('unassigned system resolver was lost or duplicated');
NODE
ok "selected DNS remains visible when live DoH mapping is incomplete"
# No saved DNS result is unknown, not proof that the resolver is unavailable.
awk '/^function stateBadge\(status,pingValue\)/,/^}/' "$tmp/common.js" > "$tmp/state_badge.js"
grep -Fq "if(!s)return badge('dm-off','нет данных');" "$tmp/state_badge.js" || fail "LuCI marks an untested DNS unavailable"
_guard_line="$(grep -nF "if(!s)return badge('dm-off','нет данных');" "$tmp/state_badge.js" | cut -d: -f1)"
_failure_line="$(grep -nF "||!hasPing(pingValue))return badge('dm-bad','недоступен');" "$tmp/state_badge.js" | cut -d: -f1)"
[ -n "$_guard_line" ] && [ -n "$_failure_line" ] && [ "$_guard_line" -lt "$_failure_line" ] || fail "LuCI empty-status guard is after the unavailable fallback"
ok "LuCI distinguishes untested DNS from unavailable DNS"
grep -Fq 'LUCI_VIEW_DIR="/www/luci-static/resources/view/dns-manager"' dns-manager.sh || fail "manager-side LuCI view directory is stale"
grep -Fq 'LUCI_COMMON_FILE="/www/luci-static/resources/dns-manager/common.js"' dns-manager.sh || fail "manager-side LuCI common path is stale"
if grep -Fq '/www/luci-static/resources/view/dns_manager/overview.js' dns-manager.sh; then fail "legacy LuCI overview path remains"; fi
grep -Fq 'ubus -v list dns_manager' dns-manager.sh || fail "manager-side LuCI state does not inspect RPC methods"
grep -Fq '// DNS Manager LuCI version:' dns-manager-luci.sh || fail "LuCI version marker is missing"
grep -Fq 'package_update_index() {' "$tmp/backend.sh" || fail "package index update helper missing"
awk '/^component_update_check\(\) \{/ { capture=1 }
     capture { print }
     /^update_hdp_json\(\) \{/ && capture { exit }' "$tmp/backend.sh" > "$tmp/component_update_check.sh"
grep -Fq 'package_candidate_version https-dns-proxy' "$tmp/component_update_check.sh" || fail "https-dns-proxy update check does not read the package candidate"
if grep -Fq 'package_update_index' "$tmp/component_update_check.sh"; then
    fail "https-dns-proxy version check must not refresh the package index"
fi
grep -Fq '_hdp_available=0' "$tmp/component_update_check.sh" || fail "https-dns-proxy update check availability initialization missing"
awk '/^update_hdp_json\(\) \{/ { capture=1 }
     capture { print }
     /^update_catalog_json\(\) \{/ && capture { exit }' "$tmp/backend.sh" > "$tmp/update_hdp.sh"
grep -Fq 'package_update_index ||' "$tmp/update_hdp.sh" || fail "https-dns-proxy update does not refresh package index before candidate lookup"
awk '/^update_json\(\) \{/ { capture=1 }
     capture { print }
     /^result_for_id\(\) \{/ && capture { exit }' "$tmp/backend.sh" > "$tmp/luci_self_update.sh"
if grep -Fq '/etc/init.d/rpcd restart' "$tmp/luci_self_update.sh"; then
    fail "current RPC self-update must not restart rpcd before returning its response"
fi
awk '/^    if \[ "\${DNS_MANAGER_LUCI_SKIP_RPC_RELOAD:-0}" = 1 \]; then$/,/^    elif \[ -x \/etc\/init.d\/rpcd \]; then$/ { print }' dns-manager-luci.sh > "$tmp/luci_legacy_restart.sh"
grep -Fq '/etc/init.d/rpcd restart' "$tmp/luci_legacy_restart.sh" || fail "LuCI installer does not schedule rpcd restart for legacy self-updates"
grep -Fq 'setTimeout(function(){location.reload();},3000);' "$tmp/common.js" || fail "LuCI reload delay is not aligned with rpcd restart"
ok "LuCI package update and legacy self-update rpcd checks are covered"
grep -q 'RESOURCE_DIR="/www/luci-static/resources/dns-manager"' dns-manager-luci.sh || fail "shared LuCI resource directory missing"
grep -q 'COMMON_FILE="$RESOURCE_DIR/common.js"' dns-manager-luci.sh || fail "shared LuCI common module path missing"
for _view in dashboard doh slots devices network time catalog log; do
    grep -q 'action": { "type": "view", "path": "dns-manager/'"$_view"'" }' dns-manager-luci.sh || fail "separate LuCI view route missing: $_view"
done
if grep -q 'path": "dns-manager/overview"' dns-manager-luci.sh; then
    fail "legacy shared overview route remains"
fi
grep -q 'for _page in dashboard doh slots devices network time catalog log; do' dns-manager-luci.sh || fail "separate LuCI page generation loop missing"
grep -q "'require baseclass';" "$tmp/common.js" || fail "LuCI common module does not use baseclass"
grep -q "return baseclass.extend({" "$tmp/common.js" || fail "LuCI common module does not return a baseclass constructor"
for _rpc in doh_status network_status lan_devices time_status page_meta; do
    grep -q "\"${_rpc}\":{}" dns-manager-luci.sh || fail "fast LuCI RPC is missing from rpcd list: $_rpc"
done
for _rpc in doh_status network_status lan_devices time_status page_meta; do
    grep -q "${_rpc})" "$tmp/backend.sh" || fail "fast LuCI RPC dispatch is missing: $_rpc"
done
grep -Fq "case 'doh':" "$tmp/common.js" || fail "LuCI DoH route is missing"
grep -Fq "case 'slots':" "$tmp/common.js" || fail "LuCI DNS slots route is missing"
grep -Fq "case 'devices':" "$tmp/common.js" || fail "LuCI LAN devices route is missing"
grep -Fq 'function renderSlots(root,st){' "$tmp/common.js" || fail "DNS slot/domain panel renderer missing"
grep -Fq 'function renderDeviceDns(root,st){' "$tmp/common.js" || fail "separate LAN device panel renderer missing"
grep -Fq "slots:['slots']" "$tmp/common.js" || fail "DNS slot page is not a separate tab"
grep -Fq "devices:['devices']" "$tmp/common.js" || fail "LAN device page is not a separate tab"
awk '/^function render\(root,st\)/,/^}/' "$tmp/common.js" > "$tmp/render_routes.js"
awk "/case 'doh':/,/case 'slots':/" "$tmp/render_routes.js" > "$tmp/doh_route.js"
if grep -Fq 'renderSlots(root,st);' "$tmp/doh_route.js"; then fail "DNS slots still render inside the DoH page"; fi
grep -Fq 'callLanDevices().catch(function(){return {ok:false,devices:[]};})' "$tmp/common.js" || fail "LAN device route does not load inventory"
grep -Fq '"dns_manager": [ "status", "runtime", "doh_status", "network_status", "lan_devices"' dns-manager-luci.sh || fail "LAN inventory RPC is missing from the read ACL"
grep -Fq 'lan_devices_json() {' "$tmp/backend.sh" || fail "LAN device inventory RPC implementation missing"
grep -Fq '/tmp/dhcp.leases' "$tmp/backend.sh" || fail "LAN inventory does not include DHCP leases"
grep -Fq '/proc/net/arp' "$tmp/backend.sh" || fail "LAN inventory does not include ARP neighbours"
grep -Fq 'ip -6 neigh show dev' "$tmp/backend.sh" || fail "LAN inventory does not include IPv6 neighbours"
grep -Fq 'Список объединяет DHCP-аренды, IPv4 ARP, IPv6 NDP и статические DHCP-записи.' "$tmp/common.js" || fail "LAN device inventory scope is not explained"
grep -Fq 'Индивидуальная привязка не задана; используется обычный DNS-маршрут роутера.' "$tmp/common.js" || fail "unassigned devices are not described as using normal router DNS"
grep -Fq "method:'set_device_dns', params:['mac','slots']" dns-manager-luci.sh || fail "per-device DNS RPC has unnecessary parameters"
if grep -Fq 'Общий выбор DNS применяется ко всем LAN-устройствам' "$tmp/common.js"; then fail "global DNS selector remains in LuCI"; fi
if grep -Fq 'Включить общий DoH для LAN' "$tmp/common.js"; then fail "global DoH switch remains in LuCI"; fi
ok "LuCI keeps only individual DNS binding and normal DNS for unassigned devices"
awk '/^function routeStatusCall\(\)/,/^}/' "$tmp/common.js" > "$tmp/route_status_call.js"
awk "/case 'catalog':/,/case 'log':/" "$tmp/route_status_call.js" > "$tmp/catalog_route_status.js"
grep -Fq 'callDohStatus()' "$tmp/catalog_route_status.js" || fail "LuCI catalog refresh does not reload live DNS slots"
grep -Fq 'callPageMeta()' "$tmp/catalog_route_status.js" || fail "LuCI catalog refresh dropped its page metadata"
grep -Fq 'Object.keys(meta).forEach(function(k){st[k]=meta[k];});' "$tmp/catalog_route_status.js" || fail "LuCI catalog refresh does not merge metadata into live slot state"
ok "catalog refresh reloads assigned DNS slots immediately"

# The regional slot has an independent dnsmasq route; explain the actual suffix
# behavior and that assigning general slots 1-6 manually does not enable it.
grep -Fq 'После применения настроек запросы к зонам .ru, .su и .рф направляются через назначенный здесь DNS.' "$tmp/common.js" || fail "LuCI does not explain active regional DNS routing"
grep -Fq 'Слот RU не назначен: отдельного маршрута для .ru, .su и .рф нет.' "$tmp/common.js" || fail "LuCI does not explain the disabled regional route"
grep -Fq 'RU — отдельный региональный слот: в него выбирается DNS из категории «Региональные DNS».' "$tmp/common.js" || fail "LuCI does not explain the separate regional slot"
ok "LuCI explains regional TLD routing and the separate RU slot"
grep -q "case 'network': return callNetworkStatus();" "$tmp/common.js" || fail "LuCI network page does not use targeted RPC"
grep -q "case 'time': return callTimeStatus();" "$tmp/common.js" || fail "LuCI time page does not use targeted RPC"
grep -q "case 'log':" "$tmp/common.js" || fail "LuCI log page route handling missing"
ok "LuCI uses page-specific RPC loading"
grep -q "'require dns-manager.common as DM';" dns-manager-luci.sh || fail "LuCI page wrapper does not use common module"
grep -q "return view.extend({" dns-manager-luci.sh || fail "LuCI page wrapper does not use native view constructor"
ok "LuCI uses separate native page views with one shared module"

grep -q "Проверить текущие DNS" "$tmp/common.js" || fail "LuCI common current-DNS check button missing"
if grep -q "Проверить DNS в слотах" "$tmp/common.js" || grep -q "Проверить системные DNS" "$tmp/common.js"; then
    fail "LuCI still exposes separate slot/system DNS check buttons"
fi
grep -q "var systems=targets.filter(function(d){return d&&!d.slot&&d.url&&d.port;});" "$tmp/common.js" || fail "LuCI current-DNS check does not classify unassigned system resolvers"
grep -q "callTestSystem().then" "$tmp/common.js" || fail "LuCI common current-DNS check does not include system DNS"
ok "LuCI current-DNS check covers slots and system resolvers with one button"

DOLLAR='$'
PID_LITERAL="${DOLLAR}${DOLLAR}"
grep -Fq 'BACKEND_STAGE="${BACKEND_FILE}.new.' dns-manager-luci.sh || fail "backend staging prefix missing"
grep -Fq "BACKEND_STAGE=\"\${BACKEND_FILE}.new.${PID_LITERAL}\"" dns-manager-luci.sh || fail "backend staging PID suffix missing"
grep -q 'mv -f "$BACKEND_STAGE" "$BACKEND_FILE"' dns-manager-luci.sh || fail "backend atomic swap missing"
grep -Fq 'RPC_STAGE="${RPC_PLUGIN}.new.' dns-manager-luci.sh || fail "RPC staging prefix missing"
grep -Fq "RPC_STAGE=\"\${RPC_PLUGIN}.new.${PID_LITERAL}\"" dns-manager-luci.sh || fail "RPC staging PID suffix missing"
grep -q 'mv -f "$RPC_STAGE" "$RPC_PLUGIN"' dns-manager-luci.sh || fail "RPC plugin atomic swap missing"
grep -Fq 'COMMON_STAGE="$COMMON_FILE.new.' dns-manager-luci.sh || fail "common module staging prefix missing"
grep -Fq "COMMON_STAGE=\"\$COMMON_FILE.new.${PID_LITERAL}\"" dns-manager-luci.sh || fail "common module staging PID suffix missing"
grep -q 'mv -f "$COMMON_STAGE" "$COMMON_FILE"' dns-manager-luci.sh || fail "view atomic swap missing"
grep -q 'function dmRpc(o)' "$tmp/common.js" || fail "RPC retry wrapper missing"
grep -q 'Object not found' "$tmp/common.js" || fail "RPC retry condition missing"
for legacy in \
  'eval "SLOT_$i=\"$_id\""' \
  'eval "SLOT_$i=\"\""' \
  'eval "SLOT_$_s=\"$_replacement\""' \
  'eval "SLOT_$slot=\\$id"' \
  'eval "SLOT_${_slot}=\"$_new_id\""' \
  'eval "SLOT_${_slot}=\"$_rid\""' \
  'eval "PORT_$slot=\"$target\""' \
  'eval "PORT_${_slot}=\"$_port\""' ; do
    if grep -Fq "$legacy" dns-manager.sh; then
        fail "unsafe dynamic assignment remains: $legacy"
    fi
done
grep -q '^slot_set() {' dns-manager.sh || fail "safe slot setter missing"
grep -q '^slot_cat_set() {' dns-manager.sh || fail "safe slot category setter missing"
grep -q '^port_set() {' dns-manager.sh || fail "safe port setter missing"
grep -q '^quick_pref_set() {' dns-manager.sh || fail "safe quick preference setter missing"
grep -Fq 'if ($1 !~ /^[A-Za-z0-9_-]+$/) bad=1' dns-manager.sh || fail "catalog ID validation missing"
grep -q 'bypass|clean|security|privacy|adblock|family|gaming|regional' dns-manager.sh || fail "catalog category validation missing"
grep -q 'acquire_runtime_lock() {' "$tmp/backend.sh" || fail "LuCI runtime lock helper missing"
grep -q 'json_update_state() {' "$tmp/backend.sh" || fail "structured update result helper missing"
grep -q 'updated) exit 0' dns-manager.sh || fail "manager update-check exit contract missing"
grep -q 'current|throttled) exit 2' dns-manager.sh || fail "manager current exit contract missing"
grep -q "xbox_dns|gaming|games+supercell|Xbox DNS|" catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "Xbox DNS is not in gaming catalog category"
grep -Fq '# DNSCATREV=7' catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "catalog revision not bumped"
grep -Fq '# ENTRIES=107' catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "catalog entry count header is incorrect"
grep -Fq 'astracat|bypass|geo+ads+services|AstraCat DNS|https://dns.commonnet.work/dns-query|ru/global|official-current' catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "AstraCat catalog endpoint is stale"
if grep -Eq '^astracat_(1498|8443)[|]' catalogs/dns-8.7-RU-NOSOCIAL.conf; then fail "obsolete AstraCat alternate-port entries remain"; fi
grep -Fq 'cubedns|privacy|privacy+no-logs|CubeDNS|https://cubedns.com/dns-query|' catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "CubeDNS DoH entry missing"
grep -Fq 'dagami|bypass|geo+services|Dagami DNS|https://dns.dagami.ru/dns-query|' catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "Dagami DNS entry missing"
grep -Fq 'webshift|bypass|geo+services|WebShift DNS|https://d.webshiftvpn.ru/dns-query|' catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "WebShift DNS entry missing"
grep -Fq 'libredns_clean|bypass|privacy+geo+services|LibreDNS|https://doh.libredns.gr/dns-query|' catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "LibreDNS category is incorrect"
grep -Fq 'shecan|bypass|geo+services|zapret.moe|https://dns.zapret.moe/dns-query|' catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "Shecan entry was not replaced by zapret.moe DoH"
grep -Fq '# ENTRIES=107' catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "catalog entry count was not updated"
grep -Fq 'bezmezhau|bypass|geo+services|Bezmezhau DNS|https://dns.bezmezhau.com/dns-query|' catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "Bezmezhau geo DNS entry missing"
grep -Fq 'dagami|bypass|geo+services|Dagami DNS|https://dns.dagami.ru/dns-query|' catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "Dagami geo DNS entry missing"
grep -Fq "function resolverAvailable(ci)" dns-manager-luci.sh || fail "DoH availability helper missing"
grep -Fq 'assignDirect(d.id,slot,root,name,d.url)' dns-manager-luci.sh || fail "catalog assignment does not pass the target URL"
grep -Fq 'normalizeUrl(activeUrl)===normalizeUrl(nextUrl)' dns-manager-luci.sh || fail "same-name assignment does not refresh a changed resolver URL"
awk '/var normalizeUrl=function\(u\)/ {print; found=1; exit} END {if (!found) exit 1}' dns-manager-luci.sh > "$tmp/normalize_url.js" || fail "LuCI URL normalizer is missing"
cat >> "$tmp/normalize_url.js" <<'EOF_NORMALIZE_URL'
if (normalizeUrl('https://example.com/path/') !== 'https://example.com/path/') process.exit(1);
if (normalizeUrl('https://example.com/') !== 'https://example.com') process.exit(1);
EOF_NORMALIZE_URL
node "$tmp/normalize_url.js" || fail "LuCI URL normalizer strips a significant DoH path slash"
grep -Fq '$1!="shecan" {print}' dns-manager-luci.sh || fail "LuCI does not invalidate the changed resolver test result"
grep -Fq '$1!="shecan" {print}' dns-manager.sh || fail "Manager does not invalidate the changed resolver test result"
grep -Fq 'DNSCAT_REVISION="7"' dns-manager.sh || fail "backend catalog revision is not synchronized"
grep -Fq '_old_astracat_url=' dns-manager.sh || fail "old AstraCat endpoint is not tracked during catalog update"
grep -Fq '_new_astracat_url=' dns-manager.sh || fail "new AstraCat endpoint is not tracked during catalog update"
grep -Fq '$1!="astracat" {print}' dns-manager.sh || fail "AstraCat cached test result is not invalidated after endpoint change"
grep -Fq '_old_astracat_url=' dns-manager-luci.sh || fail "LuCI does not track the old AstraCat endpoint"
grep -Fq '_new_astracat_url=' dns-manager-luci.sh || fail "LuCI does not track the new AstraCat endpoint"
grep -Fq '$1!="astracat" {print}' dns-manager-luci.sh || fail "LuCI persisted AstraCat result is not invalidated after endpoint change"
grep -Fq 'rm -f "$CHECK_DIR/astracat"' dns-manager-luci.sh || fail "LuCI AstraCat endpoint cache is not invalidated"
grep -Fq "disabled:!!state.busy||!!state.jobRunning||unavailable||checking" dns-manager-luci.sh || fail "catalog assignment is not disabled for unavailable DoH"
grep -q "'gaming','Игровые DNS'" dns-manager-luci.sh || fail "gaming catalog label missing in LuCI"
grep -q 'family|gaming|regional' "$tmp/backend.sh" || fail "LuCI catalog validation missing gaming category"
grep -q 'all|bypass|security|privacy|adblock|family|clean|gaming|regional' "$tmp/backend.sh" || fail "LuCI catalog JSON category validation missing gaming category"
grep -q 'VERSION="3.89"' dns-manager.sh || fail "manager version not bumped"
grep -q '# DNSCATVER=8.7-RU-NOSOCIAL' catalogs/dns-8.7-RU-NOSOCIAL.conf || fail "catalog version not bumped"
grep -q 'VERSION="1.125"' dns-manager-luci.sh || fail "LuCI version not bumped"
if grep -q '^main_menu$' dns-manager.sh; then fail "interactive console menu still starts"; fi
grep -Fq "btn('Удалить DNS Manager'" dns-manager-luci.sh || fail "LuCI uninstall button missing"
grep -Fq '"uninstall":{},"uninstall_status":{}' dns-manager-luci.sh || fail "LuCI uninstall RPC is not registered"
grep -Fq 'ubus call service set' dns-manager-luci.sh || fail "uninstall is not detached under procd"
awk '/^function renderOverview\(root,st\)/ {p=1} p && /^function / && !/^function renderOverview\(root,st\)/ {exit} p {print}' dns-manager-luci.sh > "$tmp/dashboard_watchdog.js"
grep -Fq "watchdogSlotResult(st,d.slot,d.id)" "$tmp/dashboard_watchdog.js" || fail "DNS rows do not show automatic DNS check results"
if grep -Fq "dm-watchdog-results" "$tmp/dashboard_watchdog.js"; then fail "duplicate automatic DNS results card remains"; fi
awk '/^function watchdogSlotResult\(st,slot,id\)/ {p=1} p && /^function / && !/^function watchdogSlotResult\(st,slot,id\)/ {exit} p {print}' dns-manager-luci.sh > "$tmp/watchdog_slot_result.js"
node - "$tmp/watchdog_slot_result.js" <<'EOF_WD_SLOT_RESULT' || fail "automatic results do not match the current DNS slot"
const fs = require('fs');
function badge(kind, label) { return {kind, label}; }
eval(fs.readFileSync(process.argv[2], 'utf8'));
const st = {watchdog_last_records:[{slot:'1',id:'dns-a',status:'OK'},{slot:'2',id:'dns-b',status:'NO_LISTENER'}]};
if (watchdogSlotResult(st,'1','dns-a').label !== 'Авто: доступен') process.exit(1);
if (watchdogSlotResult(st,'2','dns-b').label !== 'Авто: нет локального порта') process.exit(1);
if (watchdogSlotResult(st,'1','changed') !== null || watchdogSlotResult(st,'','dns-a') !== null) process.exit(1);
EOF_WD_SLOT_RESULT
awk '/^function watchdogCard\(root,st\)/,/^function renderTestAgeCommon\(/ {print}' dns-manager-luci.sh > "$tmp/network_watchdog.js"
if grep -Fq 'watchdogSlotResult(' "$tmp/network_watchdog.js"; then fail "network page still renders automatic DNS check results"; fi
grep -Fq "toggleRow('Проверка DNS'" "$tmp/network_watchdog.js" || fail "network page lost DNS check switch"
grep -Fq "toggleRow('Автозамена DNS'" "$tmp/network_watchdog.js" || fail "network page lost DNS replacement switch"
grep -Fq 'if(tick%30===0&&!watchdogPollBusy)' dns-manager-luci.sh || fail "dashboard DNS results are not refreshed"
grep -Fq 'html[data-darkmode="true"] .dm-wrap .dm-card' dns-manager-luci.sh || fail "Bootstrap dark mode styles missing"
grep -Fq 'bootstrap_install_dependencies() {' dns-manager.sh || fail "backend noninteractive dependency bootstrap missing"
grep -Fq 'install-dependencies|--install-dependencies)' dns-manager.sh || fail "backend dependency bootstrap command missing"
grep -Fq 'install_missing_dependencies || return 1' dns-manager.sh || fail "bootstrap does not install the backend runtime dependencies"
grep -Fq 'SOURCE_REF="${DNS_MANAGER_SOURCE_REF:-main}"' dns-manager-luci.sh || fail "installer cannot select an explicit source branch"
grep -Fq 'SOURCE_BASE="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/$SOURCE_REF"' dns-manager-luci.sh || fail "installer source URL base is missing"
grep -Fq 'BACKEND_URL="$SOURCE_BASE/dns-manager.sh"' dns-manager-luci.sh || fail "installer backend does not use its selected source branch"
source_base_line="$(grep -n '^SOURCE_BASE=' dns-manager-luci.sh | head -n1 | cut -d: -f1)"
companion_line="$(grep -n '^COMPANION_URL="\$SOURCE_BASE/' dns-manager-luci.sh | head -n1 | cut -d: -f1)"
[ -n "$source_base_line" ] && [ -n "$companion_line" ] && [ "$source_base_line" -lt "$companion_line" ] || fail "installer uses the LuCI source URL before initializing it"
grep -Fq 'ensure_luci_webui() {' dns-manager-luci.sh || fail "full installer does not ensure that system LuCI is installed"
grep -Fq 'install_runtime_packages luci' dns-manager-luci.sh || fail "full installer cannot install missing system LuCI"
grep -Fq 'if ! DNS_MANAGER_BOOTSTRAP_MARK_FIRST_RUN="$_mark_first_run" "$MANAGER" --install-dependencies; then' dns-manager-luci.sh || fail "full installer does not run the backend bootstrap without opening the menu"
grep -Fq 'install|bootstrap)' dns-manager-luci.sh || fail "default installer action does not install the full LuCI stack"
grep -Fq '    update)' dns-manager-luci.sh || fail "LuCI-only update action is not kept separate"
grep -Fq 'sh "$LUCI_COMPANION_CACHE" update >"$TMP_DIR/luci-install.log" 2>&1' dns-manager.sh || fail "manager-triggered LuCI install still invokes the full bootstrap installer"
grep -Fq 'Откройте веб-интерфейс роутера → LuCI → Службы → DNS Manager.' dns-manager-luci.sh || fail "installer does not direct the user to the LuCI menu"
grep -Fq 'DNS-профиль автоматически не применялся. Завершите настройку в панели.' dns-manager-luci.sh || fail "installer does not disclose that DNS settings remain unapplied"
ok "Native LuCI installer bootstraps backend and dependencies without opening the console menu"
main_luci_url='https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager-luci.sh'
[ "$(grep -Fc "$main_luci_url" dns-manager-luci.sh)" -eq 1 ] || fail "released LuCI updater URL does not target main"
grep -Fq 'LUCI_COMPANION_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager-luci.sh"' dns-manager.sh || fail "optional backend LuCI updates do not target main"
grep -Fq 'UPDATE_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager.sh"' dns-manager.sh || fail "optional backend updates do not target main"
grep -Fq 'fetch_raw_url "$_tmp" "https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager.sh"' dns-manager-luci.sh || fail "LuCI backend update does not target main"
grep -Fq 'DNS Manager LuCI on-device smoke test.' tests/openwrt-luci-smoke.sh || fail "OpenWrt LuCI smoke test is missing"
grep -Fq 'DNS_MANAGER_SOURCE_REF="$REF" sh "$TMP" install' tests/openwrt-luci-smoke.sh || fail "smoke test does not install from its selected branch"
grep -Fq 'rpc catalog' tests/openwrt-luci-smoke.sh || fail "smoke test does not verify the catalog RPC"
grep -Fq 'start_catalog_job "$_id"' tests/openwrt-luci-smoke.sh || fail "smoke test does not exercise a LuCI test job"
grep -Fq '.dm-wrap .dm-watchdog-record{display:grid;grid-template-columns:58px minmax(0,1fr) auto;align-items:center;gap:10px;padding:8px 9px;border:1px solid rgba(110,118,129,.12);border-radius:8px;background:var(--background-color-medium,#fff)' dns-manager-luci.sh || fail "Watchdog result rows do not use the LuCI theme background variable"
ok "Watchdog result rows follow the active LuCI theme"
grep -Fq 'WATCHDOG_CHECK_INTERVAL_DEFAULT=120' dns-manager.sh || fail "Watchdog default interval is not 120 seconds"
grep -Fq ': "${WATCHDOG_REPAIR_COOLDOWN:=300}"' dns-manager.sh || fail "Watchdog default repair cooldown is not 300 seconds"
grep -Fq 'проверка каждые ${WATCHDOG_INTERVAL:-120}с, восстановление после ${WATCHDOG_FAIL_THRESHOLD:-2} последовательных сбоев' dns-manager.sh || fail "Watchdog startup message does not match the fast recovery default"
grep -Fq 'При интервале 2 минуты и пороге 2 сбоя первая попытка восстановления начнётся примерно в течение 4 минут после отказа.' dns-manager-luci.sh || fail "LuCI does not explain the default failure detection time"
grep -Fq 'Пауза между попытками восстановления DNS' dns-manager-luci.sh || fail "LuCI cooldown label inaccurately describes recovery as replacement only"
ok "Watchdog uses a 2-minute check interval and 5-minute recovery cooldown by default"
ok "LuCI version and updater sources target the paired test branch"
grep -Fq 'return m ~ /^[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]$/' dns-manager-luci.sh || fail "LAN inventory merge rejects valid six-octet MAC addresses"
grep -Fq 'NF >= 2 && $2 ~ /^[1-6](,[1-6])*$/ &&' dns-manager-luci.sh || fail "saved LAN device assignments do not require valid DNS slot lists"
grep -Fq "state.lanDevicesMessage='Обновляю список устройств LAN… Пожалуйста, подождите.'" dns-manager-luci.sh || fail "LAN refresh does not display a waiting message"
grep -Fq "state.lanDevicesLoading?'Обновляю список…':'Обновить список устройств'" dns-manager-luci.sh || fail "LAN refresh button has no loading state"
grep -Fq "'Список обновлён. Найдено устройств: '+count+'.'" dns-manager-luci.sh || fail "LAN refresh does not report the result count"
grep -Fq "'Список обновлён, но устройства LAN не обнаружены. Проверьте DHCP-аренды и таблицу соседей роутера.'" dns-manager-luci.sh || fail "empty LAN scan has no explanatory result"
grep -Fq 'dmd_ensure_profile() {' dns-manager-luci.sh || fail "shared dnsmasq profile builder missing"
grep -Fq 'iifname "%s" ether saddr %s udp dport 53 redirect to :%s\n' dns-manager-luci.sh || fail "per-device UDP DNS redirect is missing"
grep -Fq 'iifname "%s" ether saddr %s tcp dport 53 redirect to :%s\n' dns-manager-luci.sh || fail "per-device TCP DNS redirect is missing"
if grep -Fq 'iifname "%s" udp dport 53 redirect to :%s\n' "$tmp/device_dns_service.sh"; then
    fail "unscoped LAN-wide DNS redirect remains"
fi
if grep -Fq 'ether saddr != {' "$tmp/device_dns_service.sh"; then fail "global rule still excludes per-device MACs"; fi
if grep -Fq 'set_device_dns_default' dns-manager-luci.sh; then fail "global default DNS RPC remains"; fi
if grep -Fq 'default_slots' dns-manager-luci.sh; then fail "LAN inventory still exposes a global DNS selection"; fi
if grep -Fq 'dns_mode' dns-manager-luci.sh; then fail "LAN inventory still exposes an unnecessary binding mode"; fi
if grep -Fq 'EXCLUDE)' "$tmp/device_dns_service.sh"; then fail "per-device binding still has global-default exclusion mode"; fi
grep -Fq "method:'set_device_dns', params:['mac','slots']" dns-manager-luci.sh || fail "per-device DNS RPC has parameters beyond MAC and selected slots"
grep -Fq "function saveDeviceDns(mac,controls,root)" dns-manager-luci.sh || fail "per-device DNS controls do not have a save action"
grep -Fq "callSetDeviceDns(String(mac||''),selected.join(','))" dns-manager-luci.sh || fail "per-device DNS save still depends on a global mode"
grep -Fq "Индивидуальная привязка не задана; используется обычный DNS-маршрут роутера." dns-manager-luci.sh || fail "unassigned devices are not described as using normal router DNS"
ok "DNS assignment is per-device only; unassigned devices use the normal router DNS path"

grep -Fq "var domainAttrs={'class':'dm-slot-domains-input'" dns-manager-luci.sh || fail "domain editor attributes are not assembled safely"
grep -Fq "if(!assigned)domainAttrs.disabled='';" dns-manager-luci.sh || fail "unassigned slots are not disabled without a false boolean attribute"
if grep -Fq "'disabled':!assigned" dns-manager-luci.sh; then fail "domain editor still sets disabled unconditionally"; fi
grep -Fq "if(selected)cbAttrs.checked='';" dns-manager-luci.sh || fail "LAN checkbox checked state is not added conditionally"
grep -Fq "if(!usable&&!selected)cbAttrs.disabled='';" dns-manager-luci.sh || fail "LAN checkbox disabled state is not added conditionally"
if grep -Fq "'checked':selected" dns-manager-luci.sh; then fail "LAN checkbox still sets checked unconditionally"; fi
if grep -Fq "'disabled':!usable&&!selected" dns-manager-luci.sh; then fail "LAN checkbox still sets disabled unconditionally"; fi
! sed -n '/function resolverRows/,/function renderDoH/p' dns-manager-luci.sh | grep -Eq "btn\('Выбрать'|btn\(running\?'Проверяю…':'Проверить'" || fail "current DoH summary must not duplicate slot actions"
grep -Fq "doh:['doh','profiles']" dns-manager-luci.sh || fail "DoH page still includes DNS slots or device bindings"
grep -Fq "slots:['slots']" dns-manager-luci.sh || fail "DNS slot/domain panel is not isolated to its own page"
grep -Fq "devices:['devices']" dns-manager-luci.sh || fail "LAN device binding is not isolated to its own page"
grep -Fq "if(!running&&detail==='Проверка запущена…')detail='';" dns-manager-luci.sh || fail "stale catalog running message is not hidden after completion"
grep -Fq "if(!detail&&running)detail='Проверка запущена…';" dns-manager-luci.sh || fail "catalog check status fallback is not limited to a running check"
grep -Fq "if(detail)method.push(E('div',{'class':'dm-inline-msg info'},detail));" dns-manager-luci.sh || fail "empty progress details are still displayed after completion"
grep -Fq 'width:60px!important;min-width:60px!important' dns-manager-luci.sh || fail "common freshness hours input remains too narrow"
grep -q "'bypass','Обход геоблока'" dns-manager-luci.sh || fail "bypass profile label not updated"
grep -q "'security','Защита от угроз'" dns-manager-luci.sh || fail "security profile label not updated"
grep -q "'privacy','Конфиденциальность'" dns-manager-luci.sh || fail "privacy profile label not updated"
grep -q "'family','Семейная фильтрация'" dns-manager-luci.sh || fail "family profile label not updated"
if awk '/var PROFILE = \[/,/^\];/' dns-manager-luci.sh | grep -q "'gaming'"; then
    fail "gaming must not be a ready-made profile"
fi
ok "LuCI atomic install, RPC retry, safe dynamic assignments and lock/result helpers"

grep -q '^        set_watchdog_setting)' "$tmp/backend.sh" || fail "watchdog setting dispatch missing"
grep -q 'WATCHDOG_INTERVAL' "$tmp/backend.sh" || fail "watchdog interval handling missing"
if awk '/^        set_setting\)/ { capture=1 } capture { print } capture && /^        set_watchdog_setting\)/ { exit }' "$tmp/backend.sh" | grep -q '_value'; then
    fail "set_setting still contains stale _value watchdog logic"
fi
grep -q 'watchdog_apply_toggle .*|| _rc=' "$tmp/backend.sh" || fail "watchdog toggle result is not checked"
grep -q '\[ "\$_rc" -eq 0 \] || { json_error "Настройку «\$_name» не удалось применить"; return; }' "$tmp/backend.sh" || fail "watchdog toggle error is not propagated"
grep -q 'apply_extras_now force .*|| _rc=' "$tmp/backend.sh" || fail "force apply result is not checked"
grep -q 'apply_extras_now dnsmasq_perf .*|| _rc=' "$tmp/backend.sh" || fail "dnsmasq_perf apply result is not checked"

cache_state_block="$(sed -n '/^        dnsmasq_perf)/,/^        watchdog)/p' dns-manager.sh)"
printf '%s\n' "$cache_state_block" | grep -Fq '_cur="$(uci_value_normalized "dhcp.$_sec.cachesize")"' || fail "dnsmasq_perf state does not read only cachesize"
printf '%s\n' "$cache_state_block" | grep -Fq '_desired_v="$DNSMASQ_CACHE_SIZE"' || fail "dnsmasq_perf state does not compare the target cache size"
printf '%s\n' "$cache_state_block" | grep -Fq 'stock_uci_value_normalized dhcp "dhcp.@dnsmasq[0].cachesize"' || fail "dnsmasq_perf state does not compare the stock cache size"
if printf '%s\n' "$cache_state_block" | grep -Eq 'dnsforwardmax|max_cache_ttl|boguspriv|domainneeded|quietdhcp|filter_aaaa'; then
    fail "dnsmasq_perf state still depends on unrelated dnsmasq options"
fi
ok "DNS cache tuning state depends only on cachesize"
if grep -q 'update_check_job' "$tmp/backend.sh"; then
    fail "stale update_check_job backend method remains"
fi
if grep -q 'update_check_job_status' "$tmp/backend.sh"; then
    fail "stale update_check_job_status backend method remains"
fi
# Action result strips must not resurrect the persistent last_job_* state on every LuCI page.
awk '/^function renderActionStatus\(\)\{/,/^}/ { print }' "$tmp/common.js" > "$tmp/render_action_status.js"
grep -q 'state.lastAction' "$tmp/render_action_status.js" || fail "action strip no longer uses current-page action state"
if grep -q 'last_job_status\|last_job_result\|last_job_message' "$tmp/render_action_status.js"; then
    fail "action strip still promotes persistent job history to a global banner"
fi
grep -q 'if(state.activeTab!==nextTab)state.lastAction=null;' "$tmp/common.js" || fail "tab navigation does not clear stale action strip"
ok "global action banner does not persist across pages"
ok "LuCI RPC dispatch contract"
# Every asynchronous DNS test must record the PID of the process it started.
# job_process_alive() relies on this PID; without it a valid job is immediately
# reported as having no working PID.
awk '/^job_start_test_all\(\) \{/,/^job_start_test_current\(\) \{/' "$tmp/backend.sh" | grep -q '_job_pid=\$!' || fail "test_all job PID is not recorded"
awk '/^job_start_test_all\(\) \{/,/^job_start_test_current\(\) \{/' "$tmp/backend.sh" | grep -q 'job_record_pid "\$_jid" "\$_job_pid"' || fail "test_all job PID is not registered"
awk '/^job_start_test_current\(\) \{/,/^job_start_test_one\(\) \{/' "$tmp/backend.sh" | grep -q '_job_pid=\$!' || fail "test_current job PID is not recorded"
awk '/^job_start_test_current\(\) \{/,/^job_start_test_one\(\) \{/' "$tmp/backend.sh" | grep -q 'job_record_pid "\$_jid" "\$_job_pid"' || fail "test_current job PID is not registered"
awk '/^job_start_test_one\(\) \{/,/^job_json\(\) \{/' "$tmp/backend.sh" | grep -q 'DNSMGR_SINGLE_TEST_PID=\$!' || fail "test_one job PID is not recorded"
awk '/^job_start_test_one\(\) \{/,/^job_json\(\) \{/' "$tmp/backend.sh" | grep -q 'job_record_pid "\$DNSMGR_SINGLE_TEST_JOB_ID" "\$DNSMGR_SINGLE_TEST_PID"' || fail "test_one job PID is not registered"
ok "all asynchronous DNS jobs register their working PID"
# NTP status must follow the real OpenWrt system.ntp.server list, not the manager preference.
grep -q '^ntp_current_preset() {' dns-manager.sh || fail "NTP actual-state detector missing"
awk '/^ntp_current_preset\(\) \{/,/^\}/' dns-manager.sh > "$tmp/ntp_current_preset.sh"
grep -q 'system.ntp.server' "$tmp/ntp_current_preset.sh" || fail "NTP detector does not read system.ntp.server"
grep -q '0.openwrt.pool.ntp.org 1.openwrt.pool.ntp.org 2.openwrt.pool.ntp.org 3.openwrt.pool.ntp.org' "$tmp/ntp_current_preset.sh" || fail "NTP detector does not recognize OpenWrt defaults"
grep -q 'ntp_current_preset' "$tmp/ntp_menu.sh" 2>/dev/null || true
awk '/^menu_ntp\(\) \{/,/^# ==========================================/' dns-manager.sh > "$tmp/ntp_menu.sh"
grep -q 'ntp_current_preset' "$tmp/ntp_menu.sh" || fail "DNS Manager NTP menu still uses only stored preference"
cat > "$tmp/ntp_current_preset_runner.sh" <<'EOF_NTP_STATE'
#!/bin/sh
set -eu
uci() {
    case "$NTP_FAKE" in
        default) printf '%s\n' '0.openwrt.pool.ntp.org 1.openwrt.pool.ntp.org 2.openwrt.pool.ntp.org 3.openwrt.pool.ntp.org' ;;
        vniiftri) printf '%s\n' '89.109.251.21 89.109.251.22 89.109.251.23 89.109.251.24 89.109.251.25' ;;
        other) printf '%s\n' '1.2.3.4 5.6.7.8' ;;
        none) return 1 ;;
    esac
}
ntp_servers_for_profile() {
    case "$1" in
        vniiftri_moscow) printf '%s\n' '89.109.251.21 89.109.251.22 89.109.251.23 89.109.251.24 89.109.251.25' ;;
        nist_ip) printf '%s\n' '129.6.15.28 129.6.15.29 129.6.15.30 129.6.15.27 129.6.15.26' ;;
        cf_ip) printf '%s\n' '162.159.200.1 162.159.200.123' ;;
        google_ip) printf '%s\n' '216.239.35.0 216.239.35.4 216.239.35.8 216.239.35.12' ;;
    esac
}
. "$1"
NTP_FAKE=default
[ "$(ntp_current_preset)" = openwrt_default ] || exit 41
NTP_FAKE=vniiftri
[ "$(ntp_current_preset)" = vniiftri_moscow ] || exit 42
NTP_FAKE=other
[ "$(ntp_current_preset)" = other ] || exit 43
NTP_FAKE=none
[ "$(ntp_current_preset)" = none ] || exit 44
EOF_NTP_STATE
chmod +x "$tmp/ntp_current_preset_runner.sh"
"$tmp/ntp_current_preset_runner.sh" "$tmp/ntp_current_preset.sh" || fail "NTP actual-state detection behavior"
grep -q 'function ntpActualPreset(servers)' "$tmp/common.js" || fail "LuCI NTP actual-state detector missing"
grep -q "preset=ntpActualPreset(servers)" "$tmp/common.js" || fail "LuCI NTP page still trusts stored preset instead of actual servers"
grep -q "openwrt_default:'Стандарт OpenWrt'" "$tmp/common.js" || fail "LuCI does not label OpenWrt default NTP servers"
grep -q "other:'ДРУГОЕ'" "$tmp/common.js" || fail "LuCI does not label unknown NTP servers as other"
grep -q "st.force_owner==='steer'&&st.force_status==='other'" "$tmp/common.js" || fail "LuCI components do not show Steer-owned forced-DNS state"
grep -q "ДРУГОЕ • Steer" "$tmp/common.js" || fail "LuCI components do not show Steer status label"
awk '/^function renderTime\(root,st\)\{/,/^function renderCatalog\(root\)/' "$tmp/common.js" > "$tmp/ntp_view.js"
if grep -q "row('Служба'" "$tmp/ntp_view.js"; then
    fail "LuCI NTP page still exposes service status"
fi
grep -q "row('Выбранный набор'" "$tmp/ntp_view.js" || fail "LuCI NTP page lost selected preset"
ok "NTP status follows actual OpenWrt system.ntp.server configuration"
# Watchdog time controls are shown to users in minutes, while the RPC still receives seconds.
awk '/^function watchdogCard\(root,st\)\{/,/^function renderTestAgeCommon/' "$tmp/common.js" > "$tmp/watchdog_card.sh"
grep -q "Как часто проверять DNS" "$tmp/watchdog_card.sh" || fail "watchdog interval label is not user-friendly"
grep -q "Ошибок подряд до замены" "$tmp/watchdog_card.sh" || fail "watchdog failure threshold label is not user-friendly"
grep -q "Пауза между попытками восстановления DNS" "$tmp/watchdog_card.sh" || fail "watchdog repair cooldown label is not user-friendly"
grep -q "1,60,'мин'" "$tmp/watchdog_card.sh" || fail "watchdog interval range is not practical"
grep -q "5,120,'мин'" "$tmp/watchdog_card.sh" || fail "watchdog repair cooldown range is not practical"
grep -q "'step':'1'" "$tmp/watchdog_card.sh" || fail "watchdog fields must use whole-number steps"
grep -q "Math.round(n\*60)" "$tmp/watchdog_card.sh" || fail "watchdog minute values are not converted back to seconds"
grep -q "minuteValue(st\[name\],min)" "$tmp/watchdog_card.sh" || fail "watchdog stored seconds are not converted to displayed minutes"
if grep -q "Сколько DNS можно заменить за раз" "$tmp/watchdog_card.sh"; then
    fail "obsolete per-cycle watchdog repair-count setting is still exposed"
fi
if grep -q "Сколько DNS проверить при поиске замены" "$tmp/watchdog_card.sh"; then
    fail "watchdog candidate-count setting is still exposed"
fi
if grep -q "Сколько раз можно перезапустить DNS" "$tmp/watchdog_card.sh"; then
    fail "internal watchdog restart limit is still exposed in LuCI"
fi
grep -q "callWatchdogSettings(values\[0\],values\[1\],values\[2\],Math.round(restarts),Math.round(guard))" "$tmp/watchdog_card.sh" || fail "internal watchdog defaults are not preserved when saving"
if grep -q "Интервал проверки.*30.*600.*'с'" "$tmp/watchdog_card.sh"; then
    fail "watchdog interval still exposes seconds"
fi
if grep -q "Пауза между ремонтами.*30.*3600.*'с'" "$tmp/watchdog_card.sh"; then
    fail "watchdog repair cooldown still exposes seconds"
fi
if grep -q "Полная сверка.*300.*3600.*'с'" "$tmp/watchdog_card.sh"; then
    fail "watchdog full check still exposes seconds"
fi
ok "watchdog time controls use minutes in LuCI and seconds internally"
grep -q 'WATCHDOG_CHECK_INTERVAL_DEFAULT=120' dns-manager.sh || fail "watchdog default interval is not 2 minutes"
grep -q 'WATCHDOG_REPAIR_COOLDOWN=300' dns-manager.sh || fail "watchdog default repair cooldown is not 5 minutes"
grep -q 'WATCHDOG_GUARD_INTERVAL=3600' dns-manager.sh || fail "internal watchdog guard default is not 60 minutes"
grep -q '\[ "\$_ni" -ge 60 \].*\[ "\$_ni" -le 3600 \]' "$tmp/backend.sh" || fail "watchdog backend interval range is not 1-60 minutes"
grep -q '\[ "\$_nrc" -ge 300 \].*\[ "\$_nrc" -le 7200 \]' "$tmp/backend.sh" || fail "watchdog backend repair cooldown range is not 5-120 minutes"
ok "watchdog defaults and backend ranges match the practical minute-based UI"

grep -q '^restore_dns_core() {' dns-manager.sh || fail "DNS core restore helper missing"
grep -q '^restore_hdp_package_defaults() {' dns-manager.sh || fail "package-default DNS restore helper missing"
grep -Fq 'restore_hdp_package_defaults || _rc=1' dns-manager.sh || fail "DNS core restore does not rebuild package defaults"
grep -Fq 'https://cloudflare-dns.com/dns-query' dns-manager.sh || fail "Cloudflare package default missing"
grep -Fq 'https://dns.google/dns-query' dns-manager.sh || fail "Google package default missing"
awk '/^menu_slots() {/,/^firewall_dot_rule_matches() {/' dns-manager.sh > "$tmp/menu_slots.sh"
if grep -q 'hybrid_set_defaults\|CORE_ONLY=1; apply_settings\|CORE_ONLY=1' "$tmp/menu_slots.sh"; then
    fail "DNS menu restore still selects/applies a DNS profile"
fi
grep -q 'reset_dns)' "$tmp/backend.sh" || fail "LuCI DNS reset RPC missing"
grep -q 'reset_dns' "$tmp/common.js" || fail "LuCI DNS reset action missing"
grep -q 'rollback_hdp_targeted' dns-manager.sh || fail "Targeted DoH cleanup missing"
grep -q 'package_owner_remove_owned' dns-manager.sh || fail "Owned package cleanup missing"
if grep -q 'BASELINE_DIR\|BASELINE_MANIFEST\|BASELINE_LAST\|BASELINE_META\|baseline_restore_for_uninstall\|baseline_uninstall_validate\|baseline_capture_once\|baseline_mark_applied\|ensure_baseline_captured' dns-manager.sh; then fail "Obsolete persistent baseline logic remains"; fi
ok "DNS restore returns to standard resolver path"
if grep -q 'ttyd\|WEB_ACCESS\|web_access_\|third_party_running\|manager_running_under_ttyd\|defer_ttyd_action' dns-manager.sh; then
    fail "Obsolete terminal/external-service code remains in DNS Manager"
fi
awk '/^uninstall_manager_impl\(\) \{/,/^uninstall_manager\(\) \{/' dns-manager.sh > "$tmp/uninstall_manager.sh"
if grep -Eq 'rollback_hdp_targeted|rollback_dnsmasq_targeted|rollback_firewall_targeted|remove_dns_force|remove_dnsmasq_perf|remove_ntp_ip_fallback|manager_force_config_matches|uci[[:space:]]+(-q[[:space:]]+)?(set|delete|del|add_list|commit)|reload_fw|/etc/init.d/(https-dns-proxy|dnsmasq)' "$tmp/uninstall_manager.sh"; then
    fail "Uninstall still changes DNS/DoH/dnsmasq/firewall settings"
fi
grep -Fq 'package_owner_remove_owned' "$tmp/uninstall_manager.sh" || fail "Uninstall does not remove Manager-owned packages"
grep -Fq 'luci_companion_remove' "$tmp/uninstall_manager.sh" || fail "Uninstall does not remove the LuCI companion"
grep -q '^package_owner_remove_owned() {' dns-manager.sh || fail "Generic package cleanup helper missing"
if grep -Eq '^(menu_item_state|firewall_lan_zone_require|firewall_wan_zone_require|firewall_find_exact_redirect|dns_redirect_conflict_uci|prepare_dns_path|ntp_name|ntp_ipv4|ntp_leap|show_best_category|hybrid_set_defaults|hybrid_prepare_selection|show_hybrid_profile|find_doh_by_port|uci_list_normalized|uci_list_current_normalized|stock_uci_list_normalized|stock_effective_uci_value|repair_duplicate_own_doh_ports|firewall_owner_has|firewall_owner_add|firewall_ownership_sync|settings_file_normalized|apply_ntp_if_needed|verify_doh_endpoint|stage_port_used|stage_free_port|stage_cleanup|stage_bootstrap|stage_start_one|stage_process_alive|stage_local_ok|stage_try_candidate|stage_stop_last|stage_drop_by_url|candidate_already_used|next_hybrid_candidate|show_doh|show_best|menu_bogus|apply_bogus|dependency_preflight|watchdog_candidate_categories|watchdog_test_candidate|watchdog_apply_restore_previous_state|restore_persistent_test_results|save_persistent_test_results|startup_self_repair|normalize_hybrid_ports)\(\) \{' dns-manager.sh; then
    fail "Verified dead DNS Manager functions remain"
fi
if grep -Eq 'disc_clients\(\)|OTHER_ZAPRET|OTHER_ZAPRET2|OTHER_NETSHIFT|OTHER_SPLIFY|OTHER_MIXOMO|OTHER_MAGI|OTHER_HEV|OTHER_AWG|OTHER_TGGO|OTHER_TGRS|OTHER_TGMT|OTHER_BYEDPI|DNS_SMARTDNS|DNS_UNBOUND|DNS_ADGUARD|DNS_MOSDNS|DNS_SINGBOX' dns-manager.sh; then
    fail "Unrelated third-party service discovery remains in DNS Manager"
fi
awk '/^function (memoryBar|loadBar|forceModeLabel|renderPageNav|openForceDetails|testAgeRow|saveTestAges|testPanel|renderJobResult|renderJob|toast|updateManager|updateHdp|doUpdate|setTestAge|testSystem|routeUrl)\\(/' dns-manager-luci.sh >/dev/null 2>&1 && fail "Dead legacy LuCI JS functions remain"

top_luci="$(sed -n 's/^# Version:[[:space:]]*//p' dns-manager-luci.sh | head -n1)"
installer_luci="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' dns-manager-luci.sh | head -n1)"
self_luci="$(sed -n 's/^SELF_VERSION="\([^"]*\)"$/\1/p' dns-manager-luci.sh | head -n1)"
view_luci="$(sed -n 's|^// DNS Manager LuCI common module version:[[:space:]]*||p' "$tmp/common.js" | head -n1)"
[ -n "$top_luci" ] || fail "LuCI top version missing"
[ "$top_luci" = "$installer_luci" ] || fail "LuCI VERSION mismatch"
[ "$top_luci" = "$self_luci" ] || fail "LuCI SELF_VERSION mismatch"
[ "$top_luci" = "$view_luci" ] || fail "embedded JS version mismatch"
dashboard_view_luci="$(sed -n 's|^// DNS Manager LuCI version: *||p' dns-manager-luci.sh | head -n1)"
[ "$top_luci" = "$dashboard_view_luci" ] || fail "dashboard view version marker is stale"
ok "LuCI version markers synchronized ($top_luci)"
grep -Fq 'VERSION="3.89"' dns-manager.sh || fail "DNS Manager version marker is not 3.89"
ok "DNS Manager version marker synchronized (3.89)"
grep -Fq "assignment.appendChild(btn('Удалить'" dns-manager-luci.sh || fail "Custom DNS delete button is not aligned with the assignment action"
grep -Fq ".dm-catalog-item-custom{grid-column:auto}" dns-manager-luci.sh || fail "Custom DNS card is wider than a stock catalog card"
grep -Fq ".dm-catalog-controls-custom .dm-assign-inline select{height:30px;min-width:0;width:auto;max-width:100%;flex:1 1 160px" dns-manager-luci.sh || fail "Custom DNS actions do not have a responsive inline layout"
ok "Custom DNS assignment and delete actions share a responsive horizontal row"

# Regression: the sourced manager backend uses generic `_url` temporaries while
# load_manager() refreshes runtime capability data. Custom DNS input must survive
# that call and be saved to catalog field 5.
awk '/^add_custom_dns_json\(\) \{/,/^}/' dns-manager-luci.sh > "$tmp/add_custom_dns_json_fn.sh"
[ -s "$tmp/add_custom_dns_json_fn.sh" ] || fail "Custom DNS save function extraction"
cat > "$tmp/add_custom_dns_runner.sh" <<'EOF_CUSTOM_DNS_SAVE'
#!/bin/sh
set -eu
CUSTOM_CATALOG_FILE="$2/dns-custom-catalog.conf"
RUNTIME_DIR="$2/runtime"
mkdir -p "$RUNTIME_DIR"
TEST_NAME='CleanBrowsing Security TEST'
TEST_URL='https://doh.cleanbrowsing.org/doh/security-filter/'
jget() {
    case "$1" in
        name) printf '%s' "$TEST_NAME" ;;
        url) printf '%s' "$TEST_URL" ;;
        *) return 1 ;;
    esac
}
catalog_url_normalize() { printf '%s' "$1"; }
acquire_runtime_lock() { return 0; }
release_runtime_lock() { :; }
json_error() { printf 'ERROR: %s\n' "$1" >&2; return 1; }
json_quote() { printf '"%s"' "$1"; }
load_manager() { _url=""; return 0; }
catalog_id_for_url() { printf '%s' "$1" > "$RUNTIME_DIR/lookup-url"; return 1; }
dns_cat() {
    awk -F'|' -v id="$1" '$1==id {print $2;found=1} END {if(!found) exit 1}' "$CUSTOM_CATALOG_FILE" 2>/dev/null
}
catalog_field() { return 1; }
. "$1"
add_custom_dns_json > "$RUNTIME_DIR/response.json"
[ "$(cat "$RUNTIME_DIR/lookup-url")" = "$TEST_URL" ] || exit 21
awk -F'|' -v expected="$TEST_URL" '$1=="custom_001" {found=1; if($5!=expected) exit 22} END {if(!found) exit 23}' "$CUSTOM_CATALOG_FILE" || exit 24
EOF_CUSTOM_DNS_SAVE
chmod +x "$tmp/add_custom_dns_runner.sh"
"$tmp/add_custom_dns_runner.sh" "$tmp/add_custom_dns_json_fn.sh" "$tmp/custom-dns-save" || fail "Custom DNS URL was lost when the manager backend reused _url"
ok "Custom DNS URL survives backend loading and is written to catalog field 5"

if awk '
    /function startAutoStatus\(root\)/ { capture=1 }
    capture { print }
    capture && /^}/ { exit }
' "$tmp/common.js" | grep -q 'refreshDashboard'; then
    fail "startAutoStatus still performs a full dashboard refresh"
fi
if grep -q 'function refreshDashboard' "$tmp/common.js"; then
    fail "obsolete refreshDashboard function remains"
fi
ok "dashboard timer is lightweight"
grep -Fq 'управление через LuCI → Службы → DNS Manager' dns-manager.sh || fail "CLI does not direct the user to LuCI"
ok "CLI startup shows visible progress before potentially slow stages"

grep -q 'UPDATE_CHECK_CACHE="$RUNTIME_DIR/update-check.cache"' dns-manager-luci.sh || fail "version cache path missing"
grep -q 'UPDATE_CHECK_LOCK="$RUNTIME_DIR/update-check.lock"' dns-manager-luci.sh || fail "version cache lock missing"
grep -q 'find "$UPDATE_CHECK_CACHE" -mmin +30' "$tmp/backend.sh" || fail "30-minute version cache check missing"
grep -q '\[ "$_force" != 1 \]' "$tmp/backend.sh" || fail "force update-check bypass missing"
ok "version-check cache contract"

awk '
    /^json_update_state\(\) \{/ { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
' "$tmp/backend.sh" > "$tmp/update_state.sh"
[ -s "$tmp/update_state.sh" ] || fail "structured update result extraction"
. "$tmp/update_state.sh"

awk '
    /^version_gt\(\)/ { capture=1 }
    capture { print }
    capture && /^}/ { exit }
' "$tmp/backend.sh" > "$tmp/version_gt.sh"
. "$tmp/version_gt.sh"
[ "$(version_gt 1.6.7 1.6.6)" = 1 ] || fail "version_gt newer"
[ "$(version_gt 1.6.6 1.6.7)" = 0 ] || fail "version_gt older"
[ "$(version_gt 1.6.7 1.6.7)" = 0 ] || fail "version_gt equal"
[ "$(json_update_state '{"ok":true,"updated":true,"version":"1.0"}')" = updated ] || fail "structured updated result"
[ "$(json_update_state '{"ok":true,"updated":false,"version":"1.0"}')" = current ] || fail "structured current result"
[ "$(json_update_state '{"ok":false,"error":"x"}')" = error ] || fail "structured error result"
ok "version comparison and structured update results"

STEER_INIT="$tmp/etc/init.d/steer"
NFT_FIXTURE="$tmp/nft.txt"
export NFT_FIXTURE
mkdir -p "$(dirname "$STEER_INIT")" "$tmp/bin"

cat > "$STEER_INIT" <<'EOF_STEER'
#!/bin/sh
[ "${1:-}" = running ] && [ "${STEER_TEST_RUNNING:-0}" = 1 ]
EOF_STEER
chmod 0755 "$STEER_INIT"

cat > "$tmp/bin/nft" <<'EOF_NFT'
#!/bin/sh
case "$*" in
    *"list chain inet steer prerouting_dns"*) grep -q 'table inet steer' "$NFT_FIXTURE" || exit 1 ;;
esac
cat "$NFT_FIXTURE"
EOF_NFT
chmod 0755 "$tmp/bin/nft"

cat > "$tmp/bin/pgrep" <<'EOF_PGREP'
#!/bin/sh
exit 1
EOF_PGREP
chmod 0755 "$tmp/bin/pgrep"

awk '
    /^detect_steer_dns_path\(\) \{/ { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
' dns-manager.sh > "$tmp/steer_fn.sh"
[ -s "$tmp/steer_fn.sh" ] || fail "Steer detector extraction"
sed 's#/etc/init.d/steer#"$STEER_INIT"#g' "$tmp/steer_fn.sh" > "$tmp/steer_fn_test.sh"
. "$tmp/steer_fn_test.sh"

SYS_FW=fw4
PATH="$tmp/bin:$PATH"

steer_case() {
    fixture="$1"
    running="$2"
    expected="$3"
    expected_source="$4"
    printf '%s\n' "$fixture" > "$NFT_FIXTURE"
    STEER_TEST_RUNNING="$running"
    export STEER_TEST_RUNNING
    STEER_DNS_ACTIVE=0
    STEER_DNS_SOURCE=none
    detect_steer_dns_path || fail "Steer detector returned error"
    [ "$STEER_DNS_ACTIVE" = "$expected" ] || fail "Steer detection mismatch for fixture: $fixture"
    [ "$STEER_DNS_SOURCE" = "$expected_source" ] || fail "Steer source mismatch for fixture: $fixture"
}

steer_case 'table inet test { chain prerouting { iifname "br-lan" udp dport 53 counter redirect to :5300 } }' 1 1 Steer
steer_case 'table ip test { chain prerouting { iifname "br-lan" tcp dport 53 dnat to 127.0.0.1:5300 } }' 1 1 Steer
steer_case 'table inet test { chain prerouting { iifname "br-lan" udp dport 53 counter redirect to :5053 } }' 1 0 none
steer_case 'table inet test { chain prerouting { iifname "eth0" udp dport 53 counter redirect to :5300 } }' 1 0 none
steer_case 'table inet steer {
 chain prerouting_dns {
  ip saddr 192.168.1.0/24 udp dport 53 counter redirect to :5300
 }
}' 1 1 Steer
steer_case 'table inet test { chain prerouting { iifname "br-lan" udp dport 53 counter redirect to :5300 } }' 0 0 none
# The legacy fw3 path must still recognize a real LAN redirect.
cat > "$tmp/bin/iptables-save" <<'EOF_IPTABLES'
#!/bin/sh
cat "$IPTABLES_FIXTURE"
EOF_IPTABLES
chmod 0755 "$tmp/bin/iptables-save"
IPTABLES_FIXTURE="$tmp/iptables.txt"
export IPTABLES_FIXTURE
printf '%s\n' '-A PREROUTING -i br-lan -p udp -m udp --dport 53 -j REDIRECT --to-ports 5300' > "$IPTABLES_FIXTURE"
SYS_FW=fw3
STEER_TEST_RUNNING=1
export STEER_TEST_RUNNING
STEER_DNS_ACTIVE=0
STEER_DNS_SOURCE=none
detect_steer_dns_path || fail "fw3 Steer detector returned error"
[ "$STEER_DNS_ACTIVE" = 1 ] || fail "fw3 Steer redirect was not detected"
[ "$STEER_DNS_SOURCE" = Steer ] || fail "fw3 Steer source mismatch"
ok "Steer runtime/dns-path detection"

awk '
    /^detect_steer_dns_runtime\(\) \{/ { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
' "$tmp/backend.sh" > "$tmp/luci_steer_fn.sh"
[ -s "$tmp/luci_steer_fn.sh" ] || fail "LuCI Steer detector extraction"
sed 's#/etc/init.d/steer#"$STEER_INIT"#g' "$tmp/luci_steer_fn.sh" > "$tmp/luci_steer_fn_test.sh"
(
    . "$tmp/luci_steer_fn_test.sh"
    SYS_FW=fw4
    : > "$IPTABLES_FIXTURE"
    PATH="$tmp/bin:$PATH"
    steer_luci_case() {
        fixture="$1"
        running="$2"
        expected="$3"
        printf '%s\n' "$fixture" > "$NFT_FIXTURE"
        STEER_TEST_RUNNING="$running"
        export STEER_TEST_RUNNING
        STEER_DNS_ACTIVE=0
        STEER_DNS_SOURCE=none
        detect_steer_dns_runtime || fail "LuCI Steer detector returned error"
        [ "$STEER_DNS_ACTIVE" = "$expected" ] || fail "LuCI Steer detection mismatch for fixture: $fixture"
    }
    steer_luci_case 'table inet test { chain prerouting { iifname "br-lan" udp dport 53 counter redirect to :5300 } }' 1 1
    steer_luci_case 'table inet test { chain prerouting { iifname "eth0" udp dport 53 counter redirect to :5300 } }' 1 0
    steer_luci_case 'table inet steer {
 chain prerouting_dns {
  ip saddr 192.168.1.0/24 udp dport 53 counter redirect to :5300
 }
}' 1 1
    steer_luci_case 'table inet test { chain prerouting { iifname "br-lan" udp dport 53 counter redirect to :5300 } }' 0 0
)
ok "LuCI Steer detection matches LAN/runtime contract"

# https-dns-proxy defaults force_dns to 1 when the option is absent.
# Steer already redirects LAN:53 to :5300, so DNS Manager must keep force_dns explicitly at 0.
awk '/^sync_hdp_force_contract\(\) \{/,/^configure_hdp_manager_control\(\) \{/' dns-manager.sh > "$tmp/force_sync_fn.sh"
[ -s "$tmp/force_sync_fn.sh" ] || fail "forced-DNS synchronization function extraction"
awk '
    /STEER_DNS_ACTIVE.*= 1/ { capture=1 }
    capture { print }
    capture && /^[[:space:]]*return 0$/ { exit }
' "$tmp/force_sync_fn.sh" > "$tmp/force_sync_steer.sh"
grep -Fq 'uci set https-dns-proxy.config.force_dns="0"' "$tmp/force_sync_steer.sh" || fail "Steer forced-DNS branch does not explicitly disable package interception"
if grep -Fq 'uci -q delete "https-dns-proxy.config.force_dns"' "$tmp/force_sync_steer.sh"; then
    fail "Steer forced-DNS branch deletes force_dns and falls back to package default 1"
fi
awk '/^watchdog_enforce_hdp_control\(\) \{/,/^watchdog_enforce_doh_authority\(\) \{/' dns-manager.sh > "$tmp/force_watchdog_fn.sh"
grep -Fq 'uci set https-dns-proxy.config.force_dns="0"' "$tmp/force_watchdog_fn.sh" || fail "Steer watchdog does not preserve explicit force_dns=0"
grep -Fq 'FORCED_DNS_ACTIVE' "$tmp/force_watchdog_fn.sh" || fail "watchdog does not verify live forced-DNS state"
grep -Fq '[ "${FORCED_DNS_EXTERNAL:-0}" = 0 ]' "$tmp/force_watchdog_fn.sh" || fail "watchdog accepts an external DNS redirect as DNS Manager success"
awk '/^watchdog_enforce_hdp_control\(\) \{/ { capture=1 } capture { print } capture && /^}$/ { exit }' dns-manager.sh > "$tmp/force_enforce_source.sh"
_guard_off_line="$(grep -nF '[ "${FORCE_DOH:-0}" = 1 ] || return 0' "$tmp/force_enforce_source.sh" | head -n1 | cut -d: -f1)"
_detect_external_line="$(grep -nF 'detect_forced_dns_path' "$tmp/force_enforce_source.sh" | head -n1 | cut -d: -f1)"
[ -n "$_guard_off_line" ] && [ -n "$_detect_external_line" ] && [ "$_guard_off_line" -lt "$_detect_external_line" ] || fail "forced-DNS OFF guard is not before detection or mutation"
awk '/^[[:space:]]*force\)/,/^[[:space:]]*dnsmasq_perf\)/' dns-manager.sh > "$tmp/force_state.sh"
grep -Fq '[ "$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)" = "0" ] || _ok=0' "$tmp/force_state.sh" || fail "Steer force-state check does not expect explicit force_dns=0"
ok "Steer forced-DNS avoids the package default interception"

# Exercise both force-toggle paths without touching the host's OpenWrt config.
awk '/^sync_hdp_force_contract\(\) \{/,/^configure_hdp_manager_control\(\) \{/' dns-manager.sh | sed '$d' | sed "s|/etc/config/https-dns-proxy|$tmp/force-config|g; s|/etc/init.d/https-dns-proxy|$tmp/no-proxy-service|g" > "$tmp/force_sync_mock.sh"
awk '/^apply_dns_force\(\) \{/,/^}/' dns-manager.sh >> "$tmp/force_sync_mock.sh"
awk '/^remove_dns_force\(\) \{/,/^}/' dns-manager.sh | sed "s|/etc/config/https-dns-proxy|$tmp/force-config|g; s|/etc/init.d/https-dns-proxy|$tmp/no-proxy-service|g" >> "$tmp/force_sync_mock.sh"
touch "$tmp/force-config"
(
    set -eu
    . "$tmp/force_sync_mock.sh"
    UCI_LOG="$tmp/force-toggle-uci.log"
    firewall_resolve_zones() { :; }
    detect_steer_dns_path() { STEER_DNS_ACTIVE="$MOCK_STEER"; }
    steer_dns_upstream_ready() { _want=overwritten; [ "$MOCK_READY" = 1 ]; }
    force_dns_expected_src_interfaces() { printf '%s\n' lan; }
    uci() { printf '%s\n' "$*" >> "$UCI_LOG"; return 0; }
    BLOCK_EXTERNAL_DNS=0
    FORCE_DOH=1
    MOCK_STEER=1
    MOCK_READY=0
    : > "$UCI_LOG"
    if apply_dns_force; then exit 1; fi
    [ ! -s "$UCI_LOG" ] || exit 2
    MOCK_READY=1
    apply_dns_force
    grep -Fq 'set https-dns-proxy.config.force_dns=0' "$UCI_LOG" || exit 3
    grep -Fq 'set https-dns-proxy.config.dnsmasq_config_update=-' "$UCI_LOG" || exit 4
    : > "$UCI_LOG"
    remove_dns_force
    grep -Fq 'set https-dns-proxy.config.dnsmasq_config_update=-' "$UCI_LOG" || exit 5
    if grep -Fq 'delete https-dns-proxy.config.dnsmasq_config_update' "$UCI_LOG"; then exit 6; fi
    MOCK_STEER=0
    : > "$UCI_LOG"
    sync_hdp_force_contract 1
    grep -Fq 'set https-dns-proxy.config.force_dns=1' "$UCI_LOG" || exit 7
    if grep -Fq 'delete https-dns-proxy.config.heartbeat' "$UCI_LOG"; then exit 8; fi
    : > "$UCI_LOG"
    remove_dns_force
    grep -Fq 'set https-dns-proxy.config.force_dns=0' "$UCI_LOG" || exit 9
    if grep -Fq 'dnsmasq_config_update' "$UCI_LOG"; then exit 10; fi
) || fail "force toggle changed the wrong settings with or without Steer"
if grep -Fq 'reconcile_dnsmasq' "$tmp/force_sync_fn.sh"; then fail "force toggle rebuilds dnsmasq behind Steer"; fi
ok "force toggle preserves Steer and avoids unrelated dnsmasq changes"

# Runtime controller must be a no-op when forced-DNS is OFF and when an
# unrelated active redirect owns the path. This tests behavior, not only text.
awk '/^watchdog_enforce_hdp_control\(\) \{/ { capture=1 } capture { print } capture && /^}$/ { exit }' dns-manager.sh > "$tmp/force_enforce_fn.sh"
[ -s "$tmp/force_enforce_fn.sh" ] || fail "forced-DNS enforcer extraction"
(
    set -e
    . "$tmp/force_enforce_fn.sh"
    DETECT_CALLS=0
    UCI_WRITES=0
    RESTARTS=0
    DETECT_EXTERNAL=0
    detect_forced_dns_path() {
        DETECT_CALLS=$((DETECT_CALLS+1))
        FORCED_DNS_EXTERNAL="$DETECT_EXTERNAL"
        STEER_DNS_ACTIVE=0
        return 0
    }
    log_msg() { :; }
    uci() {
        case "$1" in
            set|commit|add|delete) UCI_WRITES=$((UCI_WRITES+1));;
        esac
        return 0
    }
    watchdog_restart_hdp() { RESTARTS=$((RESTARTS+1)); return 0; }
    FORCE_DOH=0
    watchdog_enforce_hdp_control
    [ "$DETECT_CALLS" = 0 ] || exit 1
    [ "$UCI_WRITES" = 0 ] || exit 2
    [ "$RESTARTS" = 0 ] || exit 3
    FORCE_DOH=1
    DETECT_EXTERNAL=1
    watchdog_enforce_hdp_control
    [ "$DETECT_CALLS" = 1 ] || exit 4
    [ "$UCI_WRITES" = 0 ] || exit 5
    [ "$RESTARTS" = 0 ] || exit 6
) || fail "forced-DNS enforcer mutates disabled or externally-owned DNS path"
ok "forced-DNS OFF and external interception are no-mutation states"

# Forced-DNS ownership must be reconciled through a lock on every background
# check cycle, and a failed reconciliation must still release the lock.
awk '/^watchdog_forced_dns_runtime_guard/ { capture=1 } capture { print } capture && /^}$/ { exit }' dns-manager.sh > "$tmp/force_runtime_guard_fn.sh"
[ -s "$tmp/force_runtime_guard_fn.sh" ] || fail "forced-DNS runtime guard extraction"
(
    set -eu
    . "$tmp/force_runtime_guard_fn.sh"
    LOCK_OK=1
    LOCK_RELEASES=0
    ENFORCE_CALLS=0
    ENFORCE_RC=0
    acquire_mutation_lock() { [ "$LOCK_OK" = 1 ]; }
    release_mutation_lock() { LOCK_RELEASES=$((LOCK_RELEASES+1)); }
    watchdog_enforce_hdp_control() { ENFORCE_CALLS=$((ENFORCE_CALLS+1)); return "$ENFORCE_RC"; }
    watchdog_forced_dns_runtime_guard || exit 1
    [ "$ENFORCE_CALLS" = 1 ] || exit 2
    [ "$LOCK_RELEASES" = 1 ] || exit 3
    ENFORCE_RC=7
    if watchdog_forced_dns_runtime_guard; then exit 4; else [ "$?" = 7 ] || exit 5; fi
    [ "$ENFORCE_CALLS" = 2 ] || exit 6
    [ "$LOCK_RELEASES" = 2 ] || exit 7
    LOCK_OK=0
    watchdog_forced_dns_runtime_guard || exit 8
    [ "$ENFORCE_CALLS" = 2 ] || exit 9
    [ "$LOCK_RELEASES" = 2 ] || exit 10
) || fail "forced-DNS runtime guard lock/error handling"
awk '/^watchdog_embedded_loop/ { capture=1 } capture { print } capture && /^run_watchdog/ { exit }' dns-manager.sh > "$tmp/watchdog_embedded_loop.sh"
grep -Fq 'if ! watchdog_forced_dns_runtime_guard; then' "$tmp/watchdog_embedded_loop.sh" || fail "background loop does not reconcile forced-DNS runtime"
_guard_line="$(grep -n 'watchdog_forced_dns_runtime_guard' "$tmp/watchdog_embedded_loop.sh" | head -n1 | cut -d: -f1)"
_slot_check_line="$(grep -n 'watchdog_refresh_listener_snapshot' "$tmp/watchdog_embedded_loop.sh" | head -n1 | cut -d: -f1)"
[ -n "$_guard_line" ] && [ -n "$_slot_check_line" ] && [ "$_guard_line" -lt "$_slot_check_line" ] || fail "forced-DNS runtime reconciliation is skipped by DNS-loop guards"
if grep -Fq '_selection_kind=' "$tmp/watchdog_embedded_loop.sh"; then
    fail "background DNS checks still depend on a selected profile"
fi
ok "forced-DNS Steer transitions are reconciled on each background-check cycle"

# Forced-DNS Auto must keep the lightweight runtime service active even when
# DNS testing/replacement is disabled; the watchdog menu state remains OFF.
grep -Fq '[ "${WATCHDOG_ENABLED:-0}" = 1 ] || [ "${FORCE_DOH:-0}" = 1 ] || return 0' "$tmp/watchdog_embedded_loop.sh" || fail "runtime loop exits while forced-DNS Auto is enabled"
grep -Fq 'if [ "${WATCHDOG_ENABLED:-0}" != 1 ]; then' "$tmp/watchdog_embedded_loop.sh" || fail "forced-DNS-only loop lacks monitor-only branch"
grep -Fq 'sleep 60' "$tmp/watchdog_embedded_loop.sh" || fail "forced-DNS-only loop has no bounded polling interval"
awk '/^watchdog_state_word_procd\(\) \{/ { capture=1 } capture { print } capture && /^}/ { exit }' dns-manager.sh > "$tmp/watchdog_state_fn.sh"
grep -Fq '[ "${WATCHDOG_ENABLED:-0}" = 1 ] || { printf '\''0'\''; return 0; }' "$tmp/watchdog_state_fn.sh" || fail "runtime-only service falsely reports DNS replacement watchdog as enabled"
grep -Fq '_force_enabled="${FORCE_DOH:-0}"' dns-manager.sh || fail "procd service does not read the forced-DNS setting"
if grep -Fq 'watchdog_runtime_service_sync' dns-manager.sh; then
    fail "separate forced-DNS service lifecycle helper remains"
fi
awk '/^apply_watchdog\(\) \{/,/^menu_dns\(\) \{/' dns-manager.sh > "$tmp/apply_watchdog_fn.sh"
grep -Fq 'if [ "${WATCHDOG_ENABLED:-0}" = 1 ] || [ "${FORCE_DOH:-0}" = 1 ]; then' "$tmp/apply_watchdog_fn.sh" || fail "one procd service is not shared by DNS checks and forced-DNS tracking"
grep -Fq 'WATCHDOG_SERVICE_VERSION_MARKER="# DNS_MANAGER_WATCHDOG_SERVICE_VERSION=3.11.9"' dns-manager.sh || fail "watchdog service marker not bumped"
grep -Fq 'DNS_MANAGER_WATCHDOG_SERVICE_VERSION=3.11.9' dns-manager.sh || fail "generated procd service marker not bumped"
grep -Fq '[ "${WATCHDOG_ENABLED:-0}" = 1 ] || [ "${FORCE_DOH:-0}" = 1 ] || return 0' dns-manager.sh || fail "forced-DNS-only runtime is not a service start condition"
grep -Fq '[ "${FORCE_DOH:-0}" = 1 ] || return 0' dns-manager.sh || fail "forced-DNS service migration does not check its own enable flag"
ok "forced-DNS Auto tracks Steer without enabling DNS tests or rotation"

# Service migration must remove legacy ownership before starting the one procd service.
awk '/^watchdog_service_start_enable\(\) \{/,/^}/' dns-manager.sh > "$tmp/watchdog_service_start_enable.sh"
[ -s "$tmp/watchdog_service_start_enable.sh" ] || fail "watchdog start helper extraction"
(
    set -eu
    . "$tmp/watchdog_service_start_enable.sh"
    CALL_LOG="$tmp/watchdog-service-calls"
    export CALL_LOG
    WATCHDOG_SERVICE_PATH="$tmp/fake-dns-watchdog"
    export WATCHDOG_SERVICE_PATH
    cat > "$WATCHDOG_SERVICE_PATH" <<'EOF_FAKE_SERVICE'
#!/bin/sh
printf 'service %s\n' "$1" >> "$CALL_LOG"
exit 0
EOF_FAKE_SERVICE
    chmod 755 "$WATCHDOG_SERVICE_PATH"
    CRON_PRESENT=1
    watchdog_remove_legacy_daemon() { printf 'legacy\n' >> "$CALL_LOG"; return "${LEGACY_RC:-0}"; }
    watchdog_cron_marker_exists() { [ "$CRON_PRESENT" = 1 ]; }
    watchdog_cron_remove_owned_block() { printf 'cron-remove\n' >> "$CALL_LOG"; CRON_PRESENT=0; return 0; }
    watchdog_service_install_files() { printf 'install\n' >> "$CALL_LOG"; return 0; }
    watchdog_service_running() { printf 'running\n' >> "$CALL_LOG"; return 0; }
    sleep() { :; }
    watchdog_service_start_enable
    awk 'NR==1 { if ($0!="legacy") exit 1 } NR==2 { if ($0!="cron-remove") exit 1 } NR==3 { if ($0!="install") exit 1 } NR==4 { if ($0!="service enable") exit 1 } NR==5 { if ($0!="service start") exit 1 } NR==6 { if ($0!="running") exit 1 } END { if (NR!=6) exit 1 }' "$CALL_LOG"
    : > "$CALL_LOG"
    LEGACY_RC=1
    if watchdog_service_start_enable; then exit 2; fi
    if grep -q '^service start$' "$CALL_LOG"; then exit 3; fi
) || fail "watchdog service starts before legacy ownership is cleared"
awk '/^watchdog_service_start_enable\(\) \{/,/^}/' dns-manager.sh > "$tmp/watchdog_service_start_enable.sh"
awk '/^watchdog_service_migrate_legacy\(\) \{/,/^}/' dns-manager.sh > "$tmp/watchdog_service_migrate_legacy.sh"
_legacy_line="$(grep -nF 'watchdog_remove_legacy_daemon || return 1' "$tmp/watchdog_service_start_enable.sh" | head -n1 | cut -d: -f1)"
_start_line="$(grep -nF '"$WATCHDOG_SERVICE_PATH" start' "$tmp/watchdog_service_start_enable.sh" | head -n1 | cut -d: -f1)"
[ -n "$_legacy_line" ] && [ -n "$_start_line" ] && [ "$_legacy_line" -lt "$_start_line" ] || fail "procd starts before legacy daemon is removed"
_migrate_legacy_line="$(grep -nF 'watchdog_remove_legacy_daemon || return 1' "$tmp/watchdog_service_migrate_legacy.sh" | head -n1 | cut -d: -f1)"
_migrate_start_line="$(grep -nF '"$WATCHDOG_SERVICE_PATH" start' "$tmp/watchdog_service_migrate_legacy.sh" | head -n1 | cut -d: -f1)"
[ -n "$_migrate_legacy_line" ] && [ -n "$_migrate_start_line" ] && [ "$_migrate_legacy_line" -lt "$_migrate_start_line" ] || fail "legacy migration starts procd before legacy daemon preflight"
ok "watchdog migration checks legacy ownership before starting the single procd service"
grep -Fq 'if [ "${WATCHDOG_ENABLED:-0}" = 1 ] || [ "${FORCE_DOH:-0}" = 1 ]; then' "$tmp/apply_watchdog_fn.sh" || fail "forced-DNS-only Apply does not use the shared service"
grep -Fq 'if [ "${WATCHDOG_ENABLED:-0}" = 1 ] || [ "${FORCE_DOH:-0}" = 1 ]; then' dns-manager.sh || fail "post-Apply does not start service for forced-DNS-only mode"
ok "forced-DNS-only Apply starts the same procd service after transaction commit"

# Runtime detection must not trust config alone; it must parse both redirect and DNAT rules.
(
    set -eu
    FORCE_FN="$tmp/forced_dns_runtime_fn.sh"
    : > "$FORCE_FN"
    for _fn in dns_path_conflict_nft dns_path_conflict_iptables detect_steer_dns_path dns_manager_force_port detect_forced_dns_path; do
        awk -v f="$_fn" '$0 ~ ("^" f "\\(\\) \\{") { capture=1 } capture { print } capture && /^}$/ { exit }' dns-manager.sh >> "$FORCE_FN"
    done
    sed 's#/etc/init.d/steer#"$STEER_INIT"#g' "$FORCE_FN" > "$tmp/forced_dns_runtime_source.sh"
    . "$tmp/forced_dns_runtime_source.sh"
    TMP_DIR="$tmp/forced-dns-runtime"
    mkdir -p "$TMP_DIR"
    SYS_FW=fw4
    FIREWALL_LAN_ZONE=lan
    FIREWALL_WAN_ZONE=wan
    PORT_1=5053
    STEER_TEST_RUNNING=0
    export STEER_TEST_RUNNING
    firewall_resolve_zones() { FIREWALL_LAN_ZONE=lan; FIREWALL_WAN_ZONE=wan; return 0; }
    firewall_ref_matches_zone() { [ "$1" = "$2" ]; }
    uci() {
        case "$*" in
            "show firewall") [ "${DNS_TEST_REDIRECT:-0}" = 1 ] && printf '%s\n' 'firewall.ext_dns=redirect' ;;
            "-q get network.lan.device") printf '%s' br-lan ;;
            "-q get network.lan.ifname") printf '%s' br-lan ;;
            "-q get https-dns-proxy.config.force_dns") printf '%s' "${DNS_TEST_FORCE:-}" ;;
            "-q get https-dns-proxy.config.notrack_dns") printf '%s' "${DNS_TEST_NOTRACK:-}" ;;
            "-q get firewall.ext_dns.disabled") printf '' ;;
            "-q get firewall.ext_dns.src") printf '%s' lan ;;
            "-q get firewall.ext_dns.src_dport") printf '%s' 53 ;;
            "-q get firewall.ext_dns.target") printf '%s' DNAT ;;
            "-q get firewall.ext_dns.dest_port") printf '%s' "${DNS_TEST_REDIRECT_PORT:-5300}" ;;
            *) return 1 ;;
        esac
    }
    force_case() {
        printf '%s\n' "$1" > "$NFT_FIXTURE"
        FORCE_DOH="${2:-1}"
        DNS_TEST_FORCE="${3:-1}"
        DNS_TEST_NOTRACK="${4:-1}"
        DNS_TEST_REDIRECT="${5:-0}"
        DNS_TEST_REDIRECT_PORT="${6:-5300}"
        export FORCE_DOH DNS_TEST_FORCE DNS_TEST_NOTRACK DNS_TEST_REDIRECT DNS_TEST_REDIRECT_PORT
        FORCED_DNS_ACTIVE=0
        FORCED_DNS_EXTERNAL=0
        FORCED_DNS_SOURCE=none
        detect_forced_dns_path || fail "forced-DNS detector returned an error"
    }
    : > "$NFT_FIXTURE"
    force_case '' 1 1 1 0
    [ "$FORCED_DNS_ACTIVE" = 0 ] || fail "valid UCI options without a live rule were reported active"
    [ "$FORCED_DNS_EXTERNAL" = 0 ] || fail "missing live rule was misclassified as external"
    force_case 'table inet fw4 {
 chain dstnat {
  type nat hook prerouting priority dstnat; policy accept;
  iifname "br-lan" jump dstnat_lan comment "!fw4: Handle lan IPv4/IPv6 dstnat traffic" # handle 19
 }
 chain dstnat_lan {
  tcp dport 53 counter redirect to :53 comment "!fw4: ubus:https-dns-proxy[instance1] redirect 0" # handle 41
  udp dport 53 counter redirect to :53 comment "!fw4: ubus:https-dns-proxy[instance1] redirect 0" # handle 42
 }
}' 1 1 1 0
    [ "$FORCED_DNS_ACTIVE" = 1 ] || fail "https-dns-proxy runtime redirect was not detected"
    [ "$FORCED_DNS_EXTERNAL" = 0 ] || fail "https-dns-proxy runtime redirect was misclassified as external"
    force_case 'table ip fw4 {
 chain dstnat_lan {
  iifname "br-lan" udp dport 53 dnat to 198.51.100.10:5300 comment "external-rule" # handle 42
 }
}' 0 '' '' 0
    [ "$FORCED_DNS_ACTIVE" = 1 ] || fail "runtime DNAT interception was not detected"
    [ "$FORCED_DNS_EXTERNAL" = 1 ] || fail "runtime DNAT interception was not detected as external"
)
ok "Forced-DNS runtime detection distinguishes UCI config from live fw4 rules"

grep -q '"steer_installed"' "$tmp/backend.sh" || fail "Steer installed status missing from RPC"
grep -q '"steer_running"' "$tmp/backend.sh" || fail "Steer running status missing from RPC"
grep -q '"steer_dns_active"' "$tmp/backend.sh" || fail "Steer DNS runtime status missing from RPC"
ok "Steer status fields exposed"

grep -q 'test_one_dns "\$_id"' "$tmp/backend.sh" || fail "LuCI selected DNS check does not use the manager test"
if grep -q '\$MANAGER --test-one' "$tmp/backend.sh"; then
    fail "LuCI single DNS check still spawns a separate manager test process"
fi
grep -q 'result_for_id "\$_id"' "$tmp/backend.sh" || fail "selected DNS status does not use the authoritative result file"
if grep -q 'CURRENT_SLOT_RESULTS' "$tmp/backend.sh"; then
    fail "obsolete second DNS result store remains"
fi
if grep -q '^current_slot_result_for_id()' "$tmp/backend.sh"; then
    fail "obsolete result wrapper remains"
fi
if grep -q '^assigned_port_for_id()' dns-manager-luci.sh; then
    fail "obsolete assigned-port helper remains"
fi
grep -Fq -- '--connect-timeout 1 --max-time 3 --resolve "$host:$port:$ipx"' dns-manager.sh || fail "direct DoH timeout was not reduced"
grep -q '(trap - EXIT; test_one_dns "\$_id") &' "$tmp/backend.sh" || fail "selected DNS checks are not parallelized"
awk '
    /^job_start_test_current\(\) \{/ { capture=1 }
    capture && /q="\$TMP_DIR\/dns_query\.bin"/ { query_line=NR }
    capture && /if ! printf .*example.*com/ { create_line=NR }
    capture && /\(trap - EXIT; test_one_dns/ { worker_line=NR; exit }
    END { if (!query_line || !create_line || !worker_line || query_line >= create_line || create_line >= worker_line) exit 1 }
' dns-manager-luci.sh || fail "selected DNS workers do not receive a pre-created immutable query"
ok "single and selected DNS checks initialize the shared query safely"
awk '/^function checkInfo\(id,d\)/,/^}/' "$tmp/common.js" > "$tmp/check_info.js"
grep -q "String(x.status||'').toUpperCase()==='RUNNING'" "$tmp/check_info.js" || fail "LuCI transient check state is not limited to RUNNING"
grep -q "d&&d.status" "$tmp/check_info.js" || fail "LuCI finished DNS status does not come from RPC data"
if grep -q "state.checking\[meta.dns_id\]={" "$tmp/common.js"; then
    fail "LuCI stores a finished single-test result in transient state"
fi
grep -q "delete state.checking\[meta.dns_id\]" "$tmp/common.js" || fail "LuCI does not clear the transient single-test state"
ok "LuCI uses the RPC result for every finished single DNS check"

awk '/^function finish\(j\) \{/,/^  function poll\(\)\{/' "$tmp/common.js" > "$tmp/poll_finish.js"
if grep -q "callTestCurrent().then" "$tmp/poll_finish.js"; then
    fail "LuCI still launches a second DNS test after profile apply"
fi
if grep -q "afterProfile" "$tmp/common.js"; then
    fail "obsolete after-profile DNS verification path remains"
fi
grep -q "Профиль применён.','" "$tmp/common.js" || true
ok "profile apply does not rerun the selected DNS test"



grep -q ',"ping":' "$tmp/backend.sh" || fail "LuCI DoH instances do not expose saved ping"
grep -q ',"status":' "$tmp/backend.sh" || fail "LuCI DoH instances do not expose saved test status"
grep -q "badge('dm-ok','работает')" "$tmp/common.js" || fail "LuCI does not show DNS test state as работает"
grep -q "badge('dm-bad','не работает')" "$tmp/common.js" || fail "LuCI does not show failed DNS test state as не работает"
grep -q "badge('dm-off','не проверено')" "$tmp/common.js" || fail "LuCI does not distinguish an untested DNS"
if grep -q "dm-doh-state.*запущен" "$tmp/common.js"; then
    fail "LuCI DoH rows still expose process state as пользовательский DNS status"
fi
if grep -q "dm-doh-state.*остановлен" "$tmp/common.js"; then
    fail "LuCI DoH rows still expose process stop state instead of test state"
fi
grep -q "stateBadge(status,ci.ping||d.ping)" "$tmp/common.js" || fail "LuCI does not render DNS test ping in the status badge"
grep -Fq "E('span',{'class':'dm-doh-state'},statusNode)" "$tmp/common.js" || fail "LuCI DoH page does not render the DNS test status badge"
ok "LuCI DoH rows use test result status and ping"
awk '/^function forceComponentItem\(st\)\{/,/^function watchdogComponentItem/' "$tmp/common.js" > "$tmp/force_component.js"
if grep -q "setSetting('force'" "$tmp/force_component.js"; then
    fail "LuCI forced-DNS component must remain state-only"
fi
if grep -q "actionText\|actionButton\|dm-seg" "$tmp/force_component.js"; then
    fail "LuCI forced-DNS component exposes action controls"
fi
grep -q "owner==='steer'&&mode==='other'" "$tmp/force_component.js" || fail "LuCI forced-DNS component does not handle Steer-owned state"
grep -q "ДРУГОЕ • Steer" "$tmp/force_component.js" || fail "LuCI forced-DNS component lost Steer status label"
grep -q "componentItem('Принудительный DNS для устройств'" "$tmp/force_component.js" || fail "LuCI overview does not render dedicated forced-DNS component"
awk '/^function renderDoH\(root,st\)\{/,/^function slotLabel/' "$tmp/common.js" > "$tmp/doh_panel.js"
grep -q "setForceMode('auto',root)" "$tmp/doh_panel.js" || fail "LuCI DoH page has no force-DNS auto action"
grep -q "setForceMode('off',root)" "$tmp/doh_panel.js" || fail "LuCI DoH page has no force-DNS disable action"
grep -q "Авто (рекомендуется)" "$tmp/doh_panel.js" || fail "LuCI DoH page lost force-DNS auto label"
grep -q "Выключить в DNS Manager" "$tmp/doh_panel.js" || fail "LuCI DoH page lost force-DNS disable label"
ok "LuCI forced-DNS component is state-only; controls live in the DoH page"

# Encrypted-DNS bypass protection is an independent setting; force DNS must not
# turn its DoT firewall rule or browser auto-DoH canaries on/off by itself.
grep -Fq 'BLOCK_EXTERNAL_DNS=$(shell_quote "$BLOCK_EXTERNAL_DNS")' dns-manager.sh || fail "independent encrypted-DNS setting is not persisted"
grep -Fq 'apply_encrypted_dns_block() {' dns-manager.sh || fail "independent encrypted-DNS apply helper missing"
grep -Fq 'encrypted_dns)' dns-manager.sh || fail "encrypted-DNS setting has no apply action"
awk '/^sync_hdp_force_contract\(\) \{/,/^configure_hdp_manager_control\(\) \{/' dns-manager.sh > "$tmp/force_sync_independence.sh"
if grep -Eq 'ensure_dns_dot_block|remove_dns_dot_block' "$tmp/force_sync_independence.sh"; then
    fail "forced-DNS contract still adds/removes the independent DoT rule"
fi
grep -Fq '_canary_enabled="${BLOCK_EXTERNAL_DNS:-0}"' "$tmp/force_sync_independence.sh" || fail "forced-DNS sync does not preserve the independent canary state"
grep -Fq 'uci set "https-dns-proxy.config.canary_domains_icloud=$_canary_enabled"' "$tmp/force_sync_independence.sh" || fail "forced-DNS sync does not apply the current independent iCloud canary state"
grep -Fq 'uci set "https-dns-proxy.config.canary_domains_mozilla=$_canary_enabled"' "$tmp/force_sync_independence.sh" || fail "forced-DNS sync does not apply the current independent Mozilla canary state"
awk '/^apply_encrypted_dns_block\(\) \{/,/^}/' dns-manager.sh > "$tmp/encrypted_dns_apply.sh"
grep -Fq 'ensure_dns_dot_block || return 1' "$tmp/encrypted_dns_apply.sh" || fail "encrypted-DNS protection does not add its DoT rule"
grep -Fq 'remove_dns_dot_block || return 1' "$tmp/encrypted_dns_apply.sh" || fail "encrypted-DNS protection does not remove its DoT rule"
grep -Fq 'for _opt in canary_domains_icloud canary_domains_mozilla; do' "$tmp/encrypted_dns_apply.sh" || fail "encrypted-DNS protection does not configure both independent browser DoH canary states"
grep -Fq 'uci set "https-dns-proxy.config.$_opt=$_want"' "$tmp/encrypted_dns_apply.sh" || fail "encrypted-DNS protection does not set canary values idempotently"

# The background Watchdog calls this helper every cycle. Matching canary values
# must not commit package config or restart every DoH instance repeatedly.
_mock_hdp_config="$tmp/mock-https-dns-proxy-config"
_mock_hdp_init="$tmp/mock-https-dns-proxy-init"
touch "$_mock_hdp_config"
sed \
    -e "s|/etc/config/https-dns-proxy|$_mock_hdp_config|g" \
    -e "s|/etc/init.d/https-dns-proxy|$_mock_hdp_init|g" \
    "$tmp/encrypted_dns_apply.sh" > "$tmp/encrypted_dns_apply_mock.sh"
cat > "$_mock_hdp_init" <<'EOF_MOCK_HDP_INIT'
#!/bin/sh
case "$1" in
    running) exit 0 ;;
    restart) printf '%s\n' restart >> "$MOCK_LOG"; exit 0 ;;
esac
exit 1
EOF_MOCK_HDP_INIT
chmod +x "$_mock_hdp_init"
cat > "$tmp/encrypted_dns_idempotence_runner.sh" <<'EOF_ENCRYPTED_DNS_IDEMPOTENCE'
#!/bin/sh
set -eu
BLOCK_EXTERNAL_DNS=1
MOCK_ICLOUD=1
MOCK_MOZILLA=1
MOCK_LOG="$2"
export MOCK_LOG
: > "$MOCK_LOG"

ensure_dns_dot_block() { return 0; }
remove_dns_dot_block() { return 0; }
uci() {
    [ "${1:-}" = -q ] && shift
    case "${1:-}" in
        get)
            case "${2:-}" in
                https-dns-proxy.config) return 0 ;;
                https-dns-proxy.config.canary_domains_icloud) printf '%s\n' "$MOCK_ICLOUD" ;;
                https-dns-proxy.config.canary_domains_mozilla) printf '%s\n' "$MOCK_MOZILLA" ;;
                *) return 1 ;;
            esac
            ;;
        set)
            case "${2%%=*}" in
                https-dns-proxy.config.canary_domains_icloud) MOCK_ICLOUD="${2#*=}" ;;
                https-dns-proxy.config.canary_domains_mozilla) MOCK_MOZILLA="${2#*=}" ;;
                *) return 1 ;;
            esac
            printf 'set %s\n' "$2" >> "$MOCK_LOG"
            ;;
        commit)
            printf 'commit %s\n' "$2" >> "$MOCK_LOG"
            ;;
        *) return 1 ;;
    esac
}
. "$1"

apply_encrypted_dns_block || exit 61
apply_encrypted_dns_block || exit 62
[ ! -s "$MOCK_LOG" ] || { cat "$MOCK_LOG" >&2; exit 63; }

# One changed canary option should cause exactly one commit and one restart.
MOCK_MOZILLA=0
apply_encrypted_dns_block || exit 64
[ "$MOCK_MOZILLA" = 1 ] || exit 65
[ "$(grep -c '^commit ' "$MOCK_LOG")" -eq 1 ] || exit 66
[ "$(grep -c '^restart' "$MOCK_LOG")" -eq 1 ] || exit 67
[ "$(grep -c 'canary_domains_mozilla=1' "$MOCK_LOG")" -eq 1 ] || exit 68
EOF_ENCRYPTED_DNS_IDEMPOTENCE
chmod +x "$tmp/encrypted_dns_idempotence_runner.sh"
"$tmp/encrypted_dns_idempotence_runner.sh" "$tmp/encrypted_dns_apply_mock.sh" "$tmp/encrypted_dns_mock.log" || fail "Watchdog repeatedly commits/restarts https-dns-proxy when encrypted-DNS canaries already match"
ok "encrypted-DNS Watchdog sync is idempotent and restarts only after a canary changes"

awk '/^remove_dns_dot_block\(\) \{/,/^}/' dns-manager.sh > "$tmp/remove_dot_block.sh"
if grep -Fq 'firewall_find_exact_rule_signature' "$tmp/remove_dot_block.sh"; then
    fail "encrypted-DNS OFF can delete a matching firewall rule owned by another component"
fi
grep -Fq 'firewall.$FW_DOT_SECTION' "$tmp/remove_dot_block.sh" || fail "encrypted-DNS OFF does not target its own DoT rule"
ok "encrypted-DNS OFF removes only the exact DNS Manager-owned DoT rule"
grep -Fq 'canary_domains_icloud 2>/dev/null)" = "${BLOCK_EXTERNAL_DNS:-0}" ] || _ok=0' dns-manager.sh || fail "forced-DNS state still assumes browser DoH canaries must be on"
grep -Fq 'canary_domains_mozilla 2>/dev/null)" = "${BLOCK_EXTERNAL_DNS:-0}" ] || _ok=0' dns-manager.sh || fail "forced-DNS state does not follow independent protection setting"
grep -Fq 'canary_domains_icloud 2>/dev/null)" = "${BLOCK_EXTERNAL_DNS:-0}" ] || _changed=1' dns-manager.sh || fail "forced-DNS watchdog will treat protection OFF as drift"
grep -Fq 'canary_domains_mozilla 2>/dev/null)" = "${BLOCK_EXTERNAL_DNS:-0}" ] || _changed=1' dns-manager.sh || fail "forced-DNS watchdog Mozilla canary check is not independent"
grep -Fq 'watchdog|watchdog_autoreplace|force|encrypted_dns|dnsmasq_perf)' dns-manager-luci.sh || fail "LuCI RPC does not allow the independent encrypted-DNS setting"
grep -Fq "setSetting('encrypted_dns',1,root)" dns-manager-luci.sh || fail "LuCI has no enable action for encrypted-DNS protection"
grep -Fq "setSetting('encrypted_dns',0,root)" dns-manager-luci.sh || fail "LuCI has no disable action for encrypted-DNS protection"
grep -Fq 'Направляет обычные DNS-запросы устройств на DNS роутера.' dns-manager-luci.sh || fail "LuCI is missing the forced-DNS explanation"
grep -Fq 'Дополнительно ограничивает использование сторонних зашифрованных DNS-сервисов' dns-manager-luci.sh || fail "LuCI is missing the encrypted-DNS protection explanation"
ok "Forced DNS and encrypted-DNS bypass protection are independently controlled"

awk '/^check_module_state\(\) \{/,/^}/' dns-manager.sh > "$tmp/check_force_state.sh"
cat > "$tmp/check_steer_independent.sh" <<'EOF_STEER_INDEPENDENT'
#!/bin/sh
set -eu
. "$1"
disc_network() { :; }
get_dnsmasq_section() { printf lan; }
firewall_resolve_zones() { :; }
detect_forced_dns_path() { :; }
detect_steer_dns_path() { STEER_DNS_ACTIVE=1; }
steer_dns_upstream_ready() { return 0; }
dns_dot_block_ready() { return 1; }
uci() {
    case "$*" in
        *https-dns-proxy.config.dnsmasq_config_update) printf '%s' '-' ;;
        *https-dns-proxy.config.force_ip_family) printf auto ;;
        *https-dns-proxy.config.force_dns) printf 0 ;;
        *) return 1 ;;
    esac
}
FORCE_DOH=1
for BLOCK_EXTERNAL_DNS in 0 1; do
    [ "$(check_module_state force)" = 1 ] || exit 1
done
EOF_STEER_INDEPENDENT
sh "$tmp/check_steer_independent.sh" "$tmp/check_force_state.sh" || fail "Steer forced DNS incorrectly depends on independent DoT block"
ok "Steer forced-DNS state is independent of the DoT block"

awk '
    /^test_dns_catalog\(\) \(/ { capture=1 }
    capture { print }
    capture && /^\)$/ { exit }
' dns-manager.sh > "$tmp/catalog_test.sh"
[ -s "$tmp/catalog_test.sh" ] || fail "catalog test extraction"
grep -Fq 'if [ $((n % TEST_PROGRESS_EVERY)) -eq 0 ]; then' "$tmp/catalog_test.sh" || fail "catalog progress is not interval-based"
if grep -Fq 'if [ $((n % TEST_PROGRESS_EVERY)) -eq 0 ] || [ "$n" -eq "$total" ]; then' "$tmp/catalog_test.sh"; then
    fail "catalog progress still prints a duplicate final intermediate result"
fi
_progress_calls="$(grep -c 'test_progress$' "$tmp/catalog_test.sh" 2>/dev/null || printf 0)"
[ "$_progress_calls" = 1 ] || fail "catalog progress has an unexpected final call"
if grep -A2 -F '    wait' "$tmp/catalog_test.sh" | grep -q '^    test_progress$'; then
    fail "catalog test still has a separate final test_progress call"
fi
ok "catalog progress omits the duplicate final intermediate result"

# Ready-made profiles must not fall through into the generic Hybrid/Max
# Bypass selector after auto_fill_slots().
awk '
    /^apply_profile_now\(\) \{/ { capture=1 }
    capture { print }
    capture && /^\}/ { exit }
' dns-manager.sh > "$tmp/apply_profile_now.sh"
[ -s "$tmp/apply_profile_now.sh" ] || fail "apply_profile_now extraction"
grep -q 'if auto_fill_slots "\$goal"; then' "$tmp/apply_profile_now.sh" || fail "profile auto-selection path missing"
grep -q 'HYBRID_STAGE_SKIP=1' "$tmp/apply_profile_now.sh" || fail "profile application does not skip generic Hybrid reselection"
grep -q 'DNS_SELECTION_MODE="profile"' "$tmp/apply_profile_now.sh" || fail "profile mode assignment missing"
grep -q 'DNS_SELECTION_CATEGORY="\$goal"' "$tmp/apply_profile_now.sh" || fail "profile category assignment missing"
if grep -q 'HYBRID_STAGE_SKIP=0 apply_profile_now' dns-manager-luci.sh; then
    fail "LuCI still overrides profile Hybrid-stage behavior"
fi
ok "ready-made DNS profiles preserve their selected category"

# Manual DNS changes must retain a category profile while all general slots stay
# inside one catalog category, and must become custom as soon as categories mix.
awk '
    /^selected_general_category\(\) \{/ { capture=1 }
    capture { print }
    capture && /^\}/ { exit }
' dns-manager.sh > "$tmp/selected_category.sh"
[ -s "$tmp/selected_category.sh" ] || fail "selected category classifier extraction"
cat > "$tmp/selected_category_runner.sh" <<'EOF_SELECTED_CATEGORY'
#!/bin/sh
set -eu
dns_cat() {
    case "$1" in
        b1|b2|b3) printf '%s\n' bypass ;;
        c1|c2|c3) printf '%s\n' clean ;;
        s1) printf '%s\n' security ;;
        unknown) return 1 ;;
        *) return 1 ;;
    esac
}
SLOT_1=b1; SLOT_2=b2; SLOT_3=b3; SLOT_4=; SLOT_5=; SLOT_6=
. "$1"
[ "$(selected_general_category)" = bypass ] || exit 11
SLOT_3=c1
[ "$(selected_general_category)" = custom ] || exit 12
SLOT_3=
SLOT_4=c2
[ "$(selected_general_category)" = custom ] || exit 13
SLOT_4=
SLOT_1=unknown
[ "$(selected_general_category)" = custom ] || exit 14
SLOT_1=
SLOT_2=
SLOT_3=
SLOT_4=
SLOT_5=
SLOT_6=
[ "$(selected_general_category)" = none ] || exit 15
EOF_SELECTED_CATEGORY
chmod +x "$tmp/selected_category_runner.sh"
"$tmp/selected_category_runner.sh" "$tmp/selected_category.sh" || fail "selected category classifier behavior"
grep -q '^sync_profile_from_selected_categories() {' dns-manager.sh || fail "profile sync helper missing"
grep -q 'DNS_PROFILE="hybrid"' dns-manager.sh || fail "uniform category does not map to Hybrid profile"
grep -q 'DNS_SELECTION_MODE="profile"' dns-manager.sh || fail "uniform category does not map to profile mode"
grep -q 'DNS_SELECTION_CATEGORY="$_spc"' dns-manager.sh || fail "uniform category is not stored as selection category"
grep -q 'DNS_PROFILE="custom"' dns-manager.sh || fail "mixed category does not map to custom profile"
awk '/^        set_slot\)/,/^        set_ntp\)/' dns-manager-luci.sh > "$tmp/luci_set_slot.sh"
if grep -q 'DNS_PROFILE=custom DNS_SELECTION_MODE=manual' "$tmp/luci_set_slot.sh"; then
    fail "LuCI slot change still forces custom/manual profile"
fi
awk '/^select_slot\(\) \{/,/^# ==========================================/' dns-manager.sh > "$tmp/cli_select_slot.sh"
if grep -q 'DNS_PROFILE="custom"' "$tmp/cli_select_slot.sh"; then
    fail "CLI slot change still forces custom profile"
fi
# Background repair follows each selected DNS resolver's own category.
# The checker and auto-replace toggles are independent; candidate discovery has no fixed cap.
awk '/^watchdog_embedded_loop\(\) \{/,/^run_watchdog\(\) \{/' dns-manager.sh > "$tmp/watchdog_embedded_loop.sh"
grep -Fq 'elif [ "${WATCHDOG_AUTOREPLACE:-0}" = 1 ]; then' "$tmp/watchdog_embedded_loop.sh" || fail "periodic replacement is not gated by auto-replace toggle"
grep -Fq ': "${WATCHDOG_AUTOREPLACE:=${WATCHDOG_ENABLED:-0}}"' dns-manager.sh || fail "legacy config has no compatible auto-replace default"
if grep -Fq 'WATCHDOG_MAX_CANDIDATES' dns-manager.sh dns-manager-luci.sh; then
    fail "DNS replacement retains a fixed candidate cap"
fi
if grep -Fq '_max_attempts' dns-manager.sh; then
    fail "per-slot DNS replacement retains a fixed attempt cap"
fi

awk '/^watchdog_slot_target_run\(\) \{/,/^watchdog_service_recover_run\(\) \{/' dns-manager.sh > "$tmp/watchdog_slot_target_run.sh"
grep -Fq 'watchdog_pick_replacement "$_slot" "$_used" "$_tried" 0 "$_target_cat"' "$tmp/watchdog_slot_target_run.sh" || fail "watchdog does not choose a replacement from the current DNS category"
if grep -Fq 'watchdog_scope_category' "$tmp/watchdog_slot_target_run.sh"; then
    fail "watchdog per-slot repair still requires a selected profile"
fi
grep -Fq '[ -n "$_target_id" ] || return 0' "$tmp/watchdog_slot_target_run.sh" || fail "watchdog does not skip empty slots"
awk '/^watchdog_embedded_loop\(\) \{/,/^run_watchdog\(\) \{/' dns-manager.sh > "$tmp/watchdog_embedded_loop.sh"
grep -Fq 'for _trigger in $_threshold_slots; do' "$tmp/watchdog_embedded_loop.sh" || fail "watchdog does not process every failed configured slot"
grep -Fq 'if [ -z "$_id" ]; then' "$tmp/watchdog_embedded_loop.sh" || fail "watchdog probes an unconfigured slot"
if grep -Fq 'WATCHDOG_MAX_REPAIRS' "$tmp/watchdog_embedded_loop.sh"; then
    fail "watchdog still limits how many slots it may repair in one cycle"
fi
ok "watchdog checks configured slots independently and replaces DNS only within its category"

# The one-shot CLI Watchdog must share the same locked repair helper as the background loop.
awk '/^run_watchdog\(\) \{/,/^watchdog_cron_scheduler_detect_pid\(\) \{/' dns-manager.sh > "$tmp/run_watchdog.sh"
grep -Fq 'if ! watchdog_slot_target_run "$_slot"; then' "$tmp/run_watchdog.sh" || fail "one-shot Watchdog bypasses the shared per-slot repair helper"
grep -Fq 'watchdog_listener_snapshot_has_port "$_port"' "$tmp/run_watchdog.sh" || fail "one-shot Watchdog may rotate DNS when the local listener is missing"
if grep -Fq 'watchdog_pick_replacement' "$tmp/run_watchdog.sh"; then
    fail "one-shot Watchdog still duplicates candidate selection"
fi
if grep -Fq 'watchdog_scope_category' "$tmp/run_watchdog.sh"; then
    fail "one-shot Watchdog still requires a DNS profile"
fi
ok "one-shot and background Watchdog share the same safe per-slot repair path"
# Mutation-lock/resource refusal must never be returned as an apparent DNS-replacement success.
awk '/^watchdog_slot_target_run\(\) \{/,/^watchdog_service_recover_run\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/watchdog_slot_target_run_only.sh"
cat > "$tmp/watchdog_lock_refusal_runner.sh" <<'EOF_WATCHDOG_LOCK_REFUSAL'
#!/bin/sh
set -eu
. "$1"
WATCHDOG_ENABLED=1
SLOT_1=resolver-a
PORT_1=5053
dns_cat() { printf 'privacy\n'; }
hybrid_desired_port() { printf '5053\n'; }
watchdog_resource_guard() { return 0; }
acquire_mutation_lock() { return 1; }
if watchdog_slot_target_run 1; then
    printf '%s\n' 'lock refusal was reported as successful replacement' >&2
    exit 31
fi
EOF_WATCHDOG_LOCK_REFUSAL
chmod +x "$tmp/watchdog_lock_refusal_runner.sh"
"$tmp/watchdog_lock_refusal_runner.sh" "$tmp/watchdog_slot_target_run_only.sh" || fail "Watchdog reports success when mutation lock acquisition fails"
ok "Watchdog fails closed when mutation lock acquisition is refused"

# The auto-replacement toggle must also be enforced by the shared repair helper
# used by the one-shot CLI command: when OFF, only restart the failed slot's
# existing instance, without choosing or applying another resolver.
awk '/^watchdog_slot_target_run\(\) \{/,/^watchdog_service_recover_run\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/watchdog_slot_target_run_only.sh"
cat > "$tmp/watchdog_autoreplace_off_runner.sh" <<'EOF_WATCHDOG_AUTOREPLACE_OFF'
#!/bin/sh
set -eu
TMP_DIR="$1"
MODE="${3:-isolated}"
mkdir -p "$TMP_DIR"
. "$2"
WATCHDOG_ENABLED=1
WATCHDOG_AUTOREPLACE=0
[ "$MODE" = stale ] && WATCHDOG_AUTOREPLACE=1
SLOT_1=resolver-a
PORT_1=5053
dns_cat() { printf 'clean\n'; }
hybrid_desired_port() { printf '5053\n'; }
watchdog_resource_guard() { return 0; }
acquire_mutation_lock() { return 0; }
release_mutation_lock() { return 0; }
load_config() { [ "$MODE" = stale ] && WATCHDOG_AUTOREPLACE=0; return 0; }
watchdog_slot_config_matches() { [ "$1" = 1 ] && [ "$2" = "$SLOT_1" ] && [ "$3" = "$PORT_1" ]; }
watchdog_check_slot() { return 1; }
watchdog_restart_slot_instance() {
    [ "$1" = 1 ] && [ "$2" = resolver-a ] && [ "$3" = 5053 ] || exit 42
    : > "$TMP_DIR/restarted-slot"
    return 0
}
watchdog_common_dns_outage() {
    : > "$TMP_DIR/common-outage-called"
    [ "$MODE" = outage ] && return 0
    return 1
}
watchdog_pick_replacement() { : > "$TMP_DIR/candidate-picked"; return 1; }
watchdog_apply_slot_candidate() { : > "$TMP_DIR/candidate-applied"; return 1; }
log_msg() { printf '%s\n' "$*" >> "$TMP_DIR/log"; }
if [ "$MODE" = outage ]; then
    if watchdog_slot_target_run 1; then
        echo "slot recovery should be skipped during a common DNS/WAN outage" >&2
        exit 49
    fi
    [ -f "$TMP_DIR/common-outage-called" ] || { echo "common-outage guard was not used" >&2; exit 50; }
    [ ! -e "$TMP_DIR/restarted-slot" ] || { echo "slot was restarted during a common DNS/WAN outage" >&2; exit 51; }
    [ ! -e "$TMP_DIR/candidate-picked" ] || { echo "replacement candidate was picked during a common outage" >&2; exit 52; }
    grep -q 'общий сбой WAN/upstream' "$TMP_DIR/log" || { echo "common-outage reason was not logged" >&2; exit 53; }
else
    watchdog_slot_target_run 1 || {
        echo "one-shot helper did not report successful local slot recovery" >&2
        exit 43
    }
    [ -f "$TMP_DIR/restarted-slot" ] || { echo "failed slot instance was not restarted" >&2; exit 44; }
    [ -f "$TMP_DIR/common-outage-called" ] || { echo "common-outage guard was not used" >&2; exit 45; }
    [ ! -e "$TMP_DIR/candidate-picked" ] || { echo "replacement candidate was picked with auto-replacement OFF" >&2; exit 46; }
    [ ! -e "$TMP_DIR/candidate-applied" ] || { echo "replacement candidate was applied with auto-replacement OFF" >&2; exit 47; }
    grep -q 'автозамена выключена' "$TMP_DIR/log" || { echo "auto-replacement OFF status was not logged" >&2; exit 48; }
fi
EOF_WATCHDOG_AUTOREPLACE_OFF
chmod +x "$tmp/watchdog_autoreplace_off_runner.sh"
"$tmp/watchdog_autoreplace_off_runner.sh" "$tmp/watchdog-off-test" "$tmp/watchdog_slot_target_run_only.sh" isolated || fail "one-shot Watchdog bypasses the auto-replacement OFF toggle"
"$tmp/watchdog_autoreplace_off_runner.sh" "$tmp/watchdog-off-outage-test" "$tmp/watchdog_slot_target_run_only.sh" outage || fail "one-shot Watchdog mutates a slot during a common DNS/WAN outage"
"$tmp/watchdog_autoreplace_off_runner.sh" "$tmp/watchdog-off-stale-test" "$tmp/watchdog_slot_target_run_only.sh" stale || fail "Watchdog ignores a disabled auto-replacement setting after lock acquisition"
ok "auto-replacement OFF permits isolated instance recovery but never DNS replacement, and skips mutations during a common outage"

# A failing upstream on a listening slot must not trigger whole-service recovery.
# Missing listeners may still use the existing service-level recovery path.
awk '/^watchdog_service_recover\(\) \{/,/^process_matches_doh_slot\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/watchdog_service_recover.sh"
[ -s "$tmp/watchdog_service_recover.sh" ] || fail "service recovery helper extraction"
cat > "$tmp/watchdog_service_recover_runner.sh" <<'EOF_WATCHDOG_SERVICE_RECOVER'
#!/bin/sh
set -eu
TMP_DIR="$1"
MODE="$2"
mkdir -p "$TMP_DIR"
. "$3"
SLOT_1=resolver-a
PORT_1=5053
SLOT_2=resolver-b
PORT_2=5054
listener_port_exists() {
    [ "$MODE" != missing ] || [ "$1" != 5054 ]
}
local_dns_query_ok() { : > "$TMP_DIR/dns-query-called"; return 1; }
watchdog_restart_hdp() { : > "$TMP_DIR/global-restart"; return 0; }
log_msg() { printf '%s\n' "$*" >> "$TMP_DIR/log"; }
watchdog_service_recover
if [ "$MODE" = upstream-fail ]; then
    [ ! -e "$TMP_DIR/global-restart" ] || { echo "a failed upstream with a live listener triggered whole-service restart" >&2; exit 61; }
    [ ! -e "$TMP_DIR/dns-query-called" ] || { echo "whole-service recovery probes upstream DNS instead of checking listeners" >&2; exit 62; }
else
    [ -e "$TMP_DIR/global-restart" ] || { echo "a missing listener did not trigger service recovery" >&2; exit 63; }
fi
EOF_WATCHDOG_SERVICE_RECOVER
chmod +x "$tmp/watchdog_service_recover_runner.sh"
"$tmp/watchdog_service_recover_runner.sh" "$tmp/watchdog-service-upstream" upstream-fail "$tmp/watchdog_service_recover.sh" || fail "one failed DoH upstream unnecessarily restarts all resolver instances"
"$tmp/watchdog_service_recover_runner.sh" "$tmp/watchdog-service-missing" missing "$tmp/watchdog_service_recover.sh" || fail "missing DNS listener no longer triggers service recovery"
ok "whole-service recovery is reserved for missing listeners; upstream failures use isolated slot recovery"

awk '/^watchdog_common_dns_outage\(\) \{/,/^watchdog_slot_target_run\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/watchdog_common_dns_outage.sh"
[ -s "$tmp/watchdog_common_dns_outage.sh" ] || fail "common DNS outage guard missing"
cat > "$tmp/watchdog_common_outage_runner.sh" <<'EOF_WATCHDOG_COMMON_OUTAGE'
#!/bin/sh
set -eu
. "$1"
SLOT_1=resolver-a
SLOT_2=resolver-b
SLOT_3=
SLOT_4=
SLOT_5=
SLOT_6=
SLOT_RU=
PORT_1=5053
PORT_2=5054
watchdog_refresh_listener_snapshot() { return 0; }
watchdog_listener_snapshot_has_port() { return 0; }
hybrid_desired_port() { case "$1" in 1) printf '5053\n';; 2) printf '5054\n';; *) return 1;; esac; }
local_dns_query_ok() { return 1; }
if ! watchdog_common_dns_outage; then
    printf '%s\n' 'all selected DNS failures were not detected as a common outage' >&2
    exit 32
fi
local_dns_query_ok() { [ "$1" = 5053 ]; }
if watchdog_common_dns_outage; then
    printf '%s\n' 'a healthy selected DNS was mistaken for a common outage' >&2
    exit 33
fi
watchdog_listener_snapshot_has_port() { [ "$1" = 5053 ]; }
local_dns_query_ok() { return 1; }
if watchdog_common_dns_outage; then
    printf '%s\n' 'a missing listener was mistaken for a confirmed common outage' >&2
    exit 34
else
    rc=$?
    [ "$rc" -eq 2 ] || { printf '%s\n' 'missing listener was not treated as uncertain state' >&2; exit 35; }
fi
EOF_WATCHDOG_COMMON_OUTAGE
chmod +x "$tmp/watchdog_common_outage_runner.sh"
"$tmp/watchdog_common_outage_runner.sh" "$tmp/watchdog_common_dns_outage.sh" || fail "common DNS outage detection"
ok "common DNS outage and uncertain listener state both suppress automatic rotation"

awk '/^watchdog_embedded_loop\(\) \{/,/^run_watchdog\(\) \{/' dns-manager.sh > "$tmp/watchdog_embedded_loop.sh"
grep -Fq '_global_dns_failure=1' "$tmp/watchdog_embedded_loop.sh" || fail "background Watchdog does not detect common DNS failure"
grep -Fq 'if [ "$_slot_recovered" = 1 ]; then' "$tmp/watchdog_embedded_loop.sh" || fail "Watchdog recovery bookkeeping is not conditional on verified recovery"
grep -Fq 'if [ "$_global_dns_failure" != 0 ]; then' "$tmp/watchdog_embedded_loop.sh" || fail "Watchdog still restarts per-slot proxies during a common/uncertain DNS outage"
grep -Fq 'общий или неопределённый DNS-сбой; перезапуск отдельных proxy и ротацию откладываю' "$tmp/watchdog_embedded_loop.sh" || fail "Watchdog does not document why slot recovery is paused during a common outage"
ok "Watchdog pauses both per-slot restarts and DNS rotation during common/uncertain outages"
grep -Fq 'eval "WD_FAIL_${_trigger}=0"' "$tmp/watchdog_embedded_loop.sh" || fail "Watchdog does not reset a recovered slot counter"
ok "Watchdog preserves failure counters until slot recovery is verified"
grep -Fq 'eval "_guard_id=\${SLOT_${_guard_slot}:-}"' dns-manager.sh || fail "integrity guard uses invalid nested slot expansion"
ok "integrity guard uses BusyBox ash-safe slot expansion"

# A stalled local proxy is restarted by its slot port before optional DNS replacement.
awk '/^watchdog_slot_instance_pid\(\) \{/,/^watchdog_embedded_integrity_guard\(\) \{/' dns-manager.sh > "$tmp/watchdog_slot_restart.sh"
grep -Fq 'kill -TERM "$_pid"' "$tmp/watchdog_slot_restart.sh" || fail "stalled slot recovery does not terminate only the matching proxy process"
grep -Fq '*" -p $_port "*)' "$tmp/watchdog_slot_restart.sh" || fail "stalled slot recovery does not match the selected slot port"
grep -Fq '[ -n "$_port" ] || _port="$(hybrid_desired_port "$1")"' "$tmp/watchdog_slot_restart.sh" || fail "stalled slot recovery does not resolve the effective slot port"
grep -Fq 'watchdog_slot_config_matches "$1" "$2" "$3"' "$tmp/watchdog_slot_restart.sh" || fail "stalled slot recovery does not revalidate using stable positional arguments"
grep -Fq '1) [ "${SLOT_1:-}" = "$2" ] && [ "${PORT_1:-$(hybrid_desired_port 1)}" = "$3" ];;' "$tmp/watchdog_slot_restart.sh" || fail "slot revalidation is vulnerable to load_config scratch-variable collisions"
grep -Fq 'watchdog_slot_instance_pid "$3"' "$tmp/watchdog_slot_restart.sh" || fail "stalled slot recovery does not use the revalidated port"
grep -Fq 'local_dns_query_ok "$3" "$_domain"' "$tmp/watchdog_slot_restart.sh" || fail "stalled slot recovery does not verify DNS after respawn on the expected port"
if grep -Fq '/etc/init.d/https-dns-proxy restart' "$tmp/watchdog_slot_restart.sh"; then
    fail "stalled slot recovery restarts every DoH slot instead of the affected instance"
fi
grep -Fq 'if watchdog_restart_slot_instance "$_trigger" "$_trigger_id" "$_trigger_port"; then' "$tmp/watchdog_embedded_loop.sh" || fail "background watchdog does not try local slot recovery first"
grep -Fq 'replace DNS only if recovery fails and a common outage is excluded' "$tmp/watchdog_embedded_loop.sh" || fail "DNS replacement is not gated by failed slot recovery and the common-outage guard"
grep -Fq '$6 == "FAIL" { $6 = "OK" }' "$tmp/watchdog_embedded_loop.sh" || fail "successful slot recovery does not clear the recorded false failure"
ok "stalled DoH slot is restarted in isolation before optional DNS replacement"

# All watchdog paths must use the same DNS health checks as the verified Manager paths.
awk '/^watchdog_embedded_loop\(\) \{/,/^# ==========================================/' dns-manager.sh > "$tmp/watchdog_embedded_loop.sh"
grep -q 'local_dns_query_ok "\$_port" "\$_domain"' "$tmp/watchdog_embedded_loop.sh" || fail "procd watchdog does not use the canonical local DNS check"
if grep -q 'watchdog_light_probe' dns-manager.sh; then
    fail "obsolete simplified watchdog DNS probe remains"
fi
if grep -q '^watchdog_probe_catalog_candidate() {' dns-manager.sh; then
    fail "obsolete separate watchdog candidate probe remains"
fi
awk '/^watchdog_apply_slot_candidate\(\) \{/,/^WATCHDOG_RESTART_COUNT=/' dns-manager.sh > "$tmp/watchdog_candidate_apply.sh"
grep -q 'watchdog_check_slot "\$_slot"' "$tmp/watchdog_candidate_apply.sh" || fail "watchdog replacement is not accepted through the canonical local DNS check"
grep -A2 -F 'watchdog_check_slot() {' dns-manager.sh | grep -q '^    local _slot' || fail "watchdog_check_slot does not isolate _slot"
grep -A2 -F 'watchdog_apply_slot_candidate() {' dns-manager.sh | grep -q '^    local _slot' || fail "watchdog_apply_slot_candidate does not isolate _slot"
grep -A2 -F 'watchdog_slot_target_run() {' dns-manager.sh | grep -q '^    local _slot' || fail "watchdog_slot_target_run does not isolate _slot"
grep -q 'dig @127\.0\.0\.1' dns-manager.sh || fail "canonical local DNS check does not use dig"
ok "watchdog candidate acceptance uses the canonical local DNS response check"
awk '/^watchdog_service_install_files\(\) \{/,/^watchdog_service_running\(\) \{/' dns-manager.sh > "$tmp/watchdog_service.sh"
grep -q 'USE_PROCD=1' "$tmp/watchdog_service.sh" || fail "watchdog service is not managed by procd"
grep -Fq '. /etc/dns-manager/config/manager.conf' "$tmp/watchdog_service.sh" || fail "watchdog service does not load shell-quoted manager settings"
grep -Fq '_wd_enabled="${WATCHDOG_ENABLED:-0}"' "$tmp/watchdog_service.sh" || fail "watchdog service does not read the saved watchdog setting"
grep -Fq '_force_enabled="${FORCE_DOH:-0}"' "$tmp/watchdog_service.sh" || fail "watchdog service does not read the saved forced-DNS setting"
grep -q 'procd_set_param command /bin/sh "\$PROG" "\$CMD"' "$tmp/watchdog_service.sh" || fail "watchdog procd command is missing"
grep -q 'procd_set_param respawn 3600 5 5' "$tmp/watchdog_service.sh" || fail "watchdog procd respawn is missing"
grep -q 'procd_add_interface_trigger "interface.*.up" "\$wan" /etc/init.d/dns-watchdog restart' "$tmp/watchdog_service.sh" || fail "watchdog WAN-up trigger is missing"
if grep -Eq '^(watchdog_cron_scheduler_require|watchdog_cron_scheduler_start|watchdog_cron_write_state|watchdog_cron_file_prepare|watchdog_cron_desired_line|watchdog_cron_line_exists|watchdog_cron_owned_block_status)\(\) \{' dns-manager.sh; then
    fail "obsolete watchdog cron mutation helpers remain"
fi
ok "watchdog uses procd as the active scheduler; obsolete cron mutation helpers are removed"

# Watchdog keeps the intended profile category while using clean as a temporary fallback.
awk '
    /^watchdog_scope_category\(\) \{/ { capture=1 }
    capture { print }
    capture && /^\}/ { exit }
' dns-manager.sh > "$tmp/watchdog_scope.sh"
[ -s "$tmp/watchdog_scope.sh" ] || fail "watchdog scope classifier extraction"
cat > "$tmp/watchdog_scope_runner.sh" <<'EOF_WATCHDOG_SCOPE'
#!/bin/sh
set -eu
DNS_SELECTION_MODE=profile
DNS_SELECTION_CATEGORY=bypass
. "$1"
[ "$(watchdog_scope_category)" = bypass ] || exit 21
DNS_SELECTION_CATEGORY=clean
[ "$(watchdog_scope_category)" = clean ] || exit 22
DNS_SELECTION_CATEGORY=security
[ "$(watchdog_scope_category)" = security ] || exit 23
DNS_SELECTION_CATEGORY=all
if watchdog_scope_category >/dev/null 2>&1; then exit 24; fi
DNS_SELECTION_MODE=manual
DNS_SELECTION_CATEGORY=bypass
if watchdog_scope_category >/dev/null 2>&1; then exit 25; fi
EOF_WATCHDOG_SCOPE
chmod +x "$tmp/watchdog_scope_runner.sh"
"$tmp/watchdog_scope_runner.sh" "$tmp/watchdog_scope.sh" || fail "watchdog intended-profile classifier behavior"
# Exact-category mode lets Watchdog repair a manually selected DNS without requiring a profile.
awk '
    /^watchdog_pick_replacement\(\) \{/ { capture=1 }
    capture { print }
    capture && /^watchdog_apply_slot_candidate\(\) \{/ { exit }
' dns-manager.sh > "$tmp/watchdog_pick_function.sh"
grep -Fq '_explicit_cat="${5:-}"' "$tmp/watchdog_pick_function.sh" || fail "watchdog picker has no explicit per-slot category mode"
grep -Fq '_desired_for_pick="$_explicit_cat"' "$tmp/watchdog_pick_function.sh" || fail "watchdog picker ignores the current DNS category"
grep -Fq 'if [ -z "$_explicit_cat" ]; then' "$tmp/watchdog_pick_function.sh" || fail "profile fallback behavior is not isolated from runtime replacement"
ok "watchdog category selection is independent of profile selection"

awk '/^job_start_test_all\(\) \{/,/^\}/' "$tmp/backend.sh" > "$tmp/test_all_job.sh"
grep -Fq 'job_write "$_jid" progress_done "$_final_total"' "$tmp/test_all_job.sh" || fail "LuCI full catalog job does not publish final progress_done"
grep -Fq 'job_write "$_jid" progress_total "$_final_total"' "$tmp/test_all_job.sh" || fail "LuCI full catalog job does not publish final progress_total"
grep -Fq 'job_write "$_jid" progress_ok "$_final_ok"' "$tmp/test_all_job.sh" || fail "LuCI full catalog job does not publish final progress_ok"
grep -Fq 'job_write "$_jid" progress_fail "$_final_fail"' "$tmp/test_all_job.sh" || fail "LuCI full catalog job does not publish final progress_fail"
ok "LuCI full catalog job publishes final progress before DONE"

awk '/^job_json\(\) \{/,/^}/' "$tmp/backend.sh" > "$tmp/job_json.sh"
for _field in progress_done progress_total progress_ok progress_fail; do
    grep -Fq "$_field" "$tmp/job_json.sh" || fail "LuCI job RPC does not expose final $_field"
done
ok "LuCI job RPC exposes final progress counts"

grep -q "profileSelected=String(st.profile||'none')!=='none'" "$tmp/common.js" || fail "LuCI does not detect missing DNS Manager profile"
grep -q "Сначала выберите профиль DNS Manager" "$tmp/common.js" || fail "LuCI missing no-profile reason"
grep -q "function watchdogComponentItem" "$tmp/common.js" || fail "LuCI watchdog component state helper missing"
awk '/^function watchdogComponentItem\(/,/^}/' "$tmp/common.js" | grep -qE 'btn\(|setSetting\(' && fail "LuCI components block still contains a watchdog action button"
grep -q "function forceComponentItem" "$tmp/common.js" || fail "LuCI forced-DNS component state helper missing"
awk '/^function forceComponentItem\(/,/^}/' "$tmp/common.js" | grep -qE 'btn\(|setSetting\(' && fail "LuCI components block still contains a forced-DNS action button"
grep -Fq "watchdogComponentItem(st,wd,wdDetails)" "$tmp/common.js" || fail "LuCI watchdog component helper is not used as a state-only item"
grep -q "function watchdogReplacementComponentItem" "$tmp/common.js" || fail "LuCI auto-replacement component state helper missing"
awk '/^function watchdogReplacementComponentItem\(/,/^}/' "$tmp/common.js" | grep -qE 'btn\(|setSetting\(' && fail "LuCI auto-replacement component must remain a state-only item"
grep -Fq "watchdogReplacementComponentItem(wdAuto,wdAutoDetails)" "$tmp/common.js" || fail "LuCI auto-replacement component is not shown separately"
grep -Fq "var wdDetails='Интервал: каждые '" "$tmp/common.js" || fail "LuCI check component details must describe interval only"
grep -Fq "var wdAutoDetails='Замена после '" "$tmp/common.js" || fail "LuCI replacement component details must describe failure threshold separately"
grep -Fq "var watchdogAutoReplace=yes(st.watchdog_autoreplace)" "$tmp/common.js" || fail "LuCI replacement state does not use the independent auto-replace setting"
grep -Fq "forceComponentItem(st)" "$tmp/common.js" || fail "LuCI forced-DNS component helper is not used as a state-only item"
grep -Fq 'if [ "$_module" = watchdog ] && [ "$_new" = 1 ]; then' dns-manager.sh || fail "CLI watchdog no-profile guard missing"
grep -Fq 'if [ "$DNSMGR_WD_REQUEST_VALUE" = 1 ] && [ -z "$SLOT_1$SLOT_2$SLOT_3$SLOT_4$SLOT_5$SLOT_6$SLOT_RU" ]; then' "$tmp/backend.sh" || fail "RPC watchdog no-profile guard missing"
grep -q "Проверить текущие DNS','cbi-button-action'" "$tmp/common.js" || fail "Current DNS check button disappeared"
if grep -q "canTestCurrent=profileSelected" "$tmp/common.js"; then fail "Current DNS check is incorrectly blocked without profile"; fi
if grep -q "_profile_slots.*Проверить текущие DNS" "$tmp/backend.sh"; then fail "Current DNS check is incorrectly guarded by profile"; fi
awk '/^function watchdogCard\(root,st\)\{/,/^function renderTestAgeCommon/' "$tmp/common.js" > "$tmp/watchdog_card.js"
if grep -Fq 'profileSelected' "$tmp/watchdog_card.js"; then
    fail "LuCI Watchdog toggle is still blocked when no profile is selected"
fi
if grep -Fq 'Сначала выберите профиль DNS Manager' "$tmp/watchdog_card.js"; then
    fail "LuCI Watchdog still asks for a profile"
fi
if grep -Fq 'Сколько DNS можно заменить за раз' "$tmp/watchdog_card.js"; then
    fail "LuCI still exposes the obsolete per-cycle repair count"
fi
grep -Fq 'Профиль не требуется.' "$tmp/watchdog_card.js" || fail "LuCI does not describe profile-independent Watchdog"
grep -Fq "toggleRow('Автозамена DNS'" "$tmp/watchdog_card.js" || fail "LuCI auto-replace control is missing"
grep -Fq "watchdogReplacementComponentItem(wdAuto,wdAutoDetails)" "$tmp/dashboard_watchdog.js" || fail "dashboard auto-replace status is missing"
ok "LuCI Watchdog is available for manually configured DNS without a profile"

ok "forced-DNS controls and current-DNS checks retain their existing behavior"

grep -q 'test_dns_catalog "\$1"' dns-manager.sh || fail "profile apply does not pass its category to the DNS test"
grep -q 'test_scope=' dns-manager.sh || fail "DNS test scope is not persisted"
grep -q 'ensure_test_results_fresh "\$_cat"' dns-manager.sh || fail "category selector does not request category-scoped freshness"
grep -q 'test_dns_catalog "$1"' dns-manager.sh || fail "profile apply does not start a category-scoped DNS test"
grep -q '($2==c || $2=="regional")' dns-manager.sh || fail "category-scoped test does not include the regional DNS set"
grep -Fq '_test_scope="${1:-all}"' dns-manager.sh || fail "DNS test scope argument missing"
grep -q 'last_full_test_scope' "$tmp/backend.sh" || fail "LuCI status does not expose DNS test scope"
grep -q 'last_full_test_scope' "$tmp/common.js" || fail "LuCI header does not show DNS test scope"
ok "ready-made profiles test only their own DNS category"

# Replacement candidates must come from the fresh profile result set, not the
# first few catalog entries. A working candidate later in the tested set must
# still be selected.
awk '
    /^watchdog_pick_replacement\(\) \{/ { capture=1 }
    capture { print }
    capture && /^watchdog_apply_slot_candidate\(\) \{/ { exit }
' dns-manager.sh | sed '$d' > "$tmp/watchdog_pick_replacement.sh"
[ -s "$tmp/watchdog_pick_replacement.sh" ] || fail "watchdog replacement extraction"
cat > "$tmp/watchdog_pick_runner.sh" <<'EOF_WATCHDOG_PICK'
#!/bin/sh
set -eu
TMP_DIR="$1"
DNS_CATALOG="$TMP_DIR/catalog"
TEST_RESULTS="$TMP_DIR/results"
REPAIR_BAD_IDS="$TMP_DIR/bad"
WATCHDOG_MAX_CANDIDATES=3
DNS_SELECTION_MODE=profile
DNS_SELECTION_CATEGORY=bypass
SLOT_1=c1
SLOT_2=
SLOT_3=
SLOT_4=
SLOT_5=
SLOT_6=
SLOT_RU=ru1

watchdog_scope_category() { printf '%s\n' "$DNS_SELECTION_CATEGORY"; }
watchdog_desired_cat() { [ "$1" = RU ] && printf '%s\n' regional || printf '%s\n' "$DNS_SELECTION_CATEGORY"; }
dns_cat() {
    case "$1" in
        c1|c2|c3|c4|c5) printf '%s\n' bypass ;;
        *) printf '%s\n' regional ;;
    esac
}
dns_url() { printf 'https://%s.example/dns-query\n' "$1"; }
dns_name() { printf '%s\n' "$1"; }
normalize_url() { printf '%s\n' "$1"; }
watchdog_test_results_fresh() { [ "$1" = bypass ]; }
watchdog_probe_catalog_candidate() { return 1; }
watchdog_preferred_quick_candidate() { return 1; }

mkdir -p "$TMP_DIR"
cat > "$DNS_CATALOG" <<'EOF_CATALOG'
c1|bypass|C1|https://c1.example/dns-query|ru/global|verified
c2|bypass|C2|https://c2.example/dns-query|ru/global|verified
c3|bypass|C3|https://c3.example/dns-query|ru/global|verified
c4|bypass|C4|https://c4.example/dns-query|ru/global|verified
c5|bypass|C5|https://c5.example/dns-query|ru/global|verified
EOF_CATALOG
cat > "$TEST_RESULTS" <<'EOF_RESULTS'
c1|bypass|C1|10|FAIL
c2|bypass|C2|20|FAIL
c3|bypass|C3|30|FAIL
c4|bypass|C4|90|OK
c5|bypass|C5|40|OK
EOF_RESULTS
: > "$REPAIR_BAD_IDS"
: > "$TMP_DIR/used"
: > "$TMP_DIR/tried"

. "$2"
got="$(watchdog_pick_replacement 1 "$TMP_DIR/used" "$TMP_DIR/tried" 0)"
[ "$got" = "c5|bypass" ] || {
    printf '%s\n' "unexpected replacement: $got" >&2
    exit 31
}

# Runtime watchdog fallback must not reject a candidate before applying it just
# because the separate bootstrap/HTTPS probe failed. The real accept/reject
# decision is made by watchdog_apply_slot_candidate() after local DNS response.
watchdog_test_results_fresh() { return 1; }
printf '%s\n' 'https://c1.example/dns-query' > "$TMP_DIR/used"
: > "$TMP_DIR/tried"
got="$(watchdog_pick_replacement 1 "$TMP_DIR/used" "$TMP_DIR/tried" 0)"
[ "$got" = "c2|bypass" ] || {
    printf '%s\n' "unexpected runtime fallback candidate: $got" >&2
    exit 33
}

# "Все категории" is a special profile mode: the background watchdog still
# rejects it, but an explicit profile repair must use the fresh all-catalog set.
DNS_SELECTION_CATEGORY=all
watchdog_test_results_fresh() { [ "$1" = all ]; }
cat > "$DNS_CATALOG" <<'EOF_ALL_CATALOG'
c1|bypass|C1|https://c1.example/dns-query|ru/global|verified
c5|bypass|C5|https://c5.example/dns-query|ru/global|verified
ru1|regional|RU1|https://ru1.example/dns-query|ru|verified
EOF_ALL_CATALOG
cat > "$TEST_RESULTS" <<'EOF_ALL_RESULTS'
c1|bypass|C1|10|FAIL
c5|bypass|C5|40|OK
ru1|regional|RU1|1|OK
EOF_ALL_RESULTS
: > "$TMP_DIR/used"
: > "$TMP_DIR/tried"
got="$(watchdog_pick_replacement 1 "$TMP_DIR/used" "$TMP_DIR/tried" 0)"
[ "$got" = "c5|bypass" ] || {
    printf '%s\n' "unexpected all-category replacement: $got" >&2
    exit 32
}
# A manually selected clean resolver is replaced by another clean resolver without a profile.
DNS_SELECTION_MODE=manual
DNS_SELECTION_CATEGORY=
watchdog_test_results_fresh() { return 1; }
cat > "$DNS_CATALOG" <<'EOF_MANUAL_CATALOG'
clean1|clean|Clean1|https://clean1.example/dns-query|ru/global|verified
clean2|clean|Clean2|https://clean2.example/dns-query|ru/global|verified
bypass1|bypass|Bypass1|https://bypass1.example/dns-query|ru/global|verified
EOF_MANUAL_CATALOG
: > "$TMP_DIR/used"
: > "$TMP_DIR/tried"
got="$(watchdog_pick_replacement 1 "$TMP_DIR/used" "$TMP_DIR/tried" 0 clean)"
[ "$got" = "clean1|clean" ] || {
    printf '%s\n' "unexpected manual same-category replacement: $got" >&2
    exit 34
}
EOF_WATCHDOG_PICK

chmod +x "$tmp/watchdog_pick_runner.sh"
"$tmp/watchdog_pick_runner.sh" "$tmp" "$tmp/watchdog_pick_replacement.sh" || fail "fresh DNS replacement candidate selection"
ok "profile repair selects from all fresh tested candidates, not the first catalog entries"

# Profile application validation must use the fresh category-scoped results.
awk '/^validate_selected_slots\(\)/,/^ensure_dnsmasq_balancer\(\)/' dns-manager.sh > "$tmp/validate_selected_slots.sh"
grep -q 'ensure_test_results_fresh "$_validate_scope" || return 1' "$tmp/validate_selected_slots.sh" || fail "profile validation does not use the selected test scope"
grep -q 'последнюю полную проверку' "$tmp/validate_selected_slots.sh" || fail "profile validation message does not refer to full test results"
grep -q '_validate_scope=all' "$tmp/validate_selected_slots.sh" || fail "profile validation default scope missing"
grep -q '_validate_scope="${DNS_SELECTION_CATEGORY:-all}"' "$tmp/validate_selected_slots.sh" || fail "profile validation does not follow selected profile category"
grep -q '_validate_scope=bypass' "$tmp/validate_selected_slots.sh" || fail "quick bypass validation scope missing"
if grep -q 'PROFILE_FRESH_OK_IDS' "$tmp/validate_selected_slots.sh"; then
    fail "profile validation still uses temporary candidate list"
fi
grep -q 'PROFILE_FULL_TEST=0' dns-manager.sh || fail "profile full-test flag cleanup missing"
grep -q 'Проверяю DNS выбранного профиля — проверено' "$tmp/common.js" || fail "LuCI profile progress does not show category-scoped DNS checking progress"
grep -q 'Выбираю DNS из свежих результатов' "$tmp/common.js" || fail "LuCI profile progress does not label fresh-result selection"
grep -q 'localProfileRunning=!!(state.busy&&state.profileProgress)' "$tmp/common.js" || fail "LuCI does not suppress stale profile result while retrying"
ok "profile apply validates only against the fresh full-catalog results"

# Profiles accept fewer than six tested DNS servers and leave unused slots empty.
awk '/^auto_fill_slots\(\) \{/,/^# ==========================================$/' dns-manager.sh > "$tmp/auto_fill_slots.sh"
[ -s "$tmp/auto_fill_slots.sh" ] || fail "auto_fill_slots extraction"
cat > "$tmp/auto_fill_slots_runner.sh" <<'EOF_AUTO_FILL_FEWER'
#!/bin/sh
set -eu
TMP_DIR="$1"
TEST_RESULTS="$TMP_DIR/results"
DNS_CATALOG="$TMP_DIR/catalog"
normalize_url() { printf "%s" "$1"; }
dns_url() { printf "https://%s.example/dns-query" "$1"; }
dns_name() { printf "%s" "$1"; }
ensure_test_results_fresh() { return 0; }
warn_msg() { :; }
slot_set() { case "$1" in 1) SLOT_1="$2";; 2) SLOT_2="$2";; 3) SLOT_3="$2";; 4) SLOT_4="$2";; 5) SLOT_5="$2";; 6) SLOT_6="$2";; RU) SLOT_RU="$2";; esac; }
slot_cat_set() { case "$1" in 1) SLOT_1_CAT="$2";; 2) SLOT_2_CAT="$2";; 3) SLOT_3_CAT="$2";; 4) SLOT_4_CAT="$2";; 5) SLOT_5_CAT="$2";; 6) SLOT_6_CAT="$2";; RU) SLOT_RU_CAT="$2";; esac; }
cat > "$TEST_RESULTS" <<'EOF_AUTO_RESULTS'
d1|bypass|D1|10|OK
d2|bypass|D2|20|OK
d3|bypass|D3|30|OK
d4|bypass|D4|40|OK
d5|bypass|D5|50|OK
EOF_AUTO_RESULTS
SLOT_1= SLOT_2= SLOT_3= SLOT_4= SLOT_5= SLOT_6= SLOT_RU=
. "$2"
auto_fill_slots bypass
[ "$SLOT_1" = d1 ] && [ "$SLOT_2" = d2 ] && [ "$SLOT_3" = d3 ] &&
[ "$SLOT_4" = d4 ] && [ "$SLOT_5" = d5 ] && [ -z "$SLOT_6" ] || exit 41
EOF_AUTO_FILL_FEWER
chmod +x "$tmp/auto_fill_slots_runner.sh"
"$tmp/auto_fill_slots_runner.sh" "$tmp" "$tmp/auto_fill_slots.sh" || fail "profile selection does not accept fewer than six DNS servers"
ok "profiles accept fewer than six available DNS servers"

# Profile post-apply verification must prune failed DNS only for a slot-specific failure.
awk '/^profile_prune_failed_slots\(\) \{/,/^verify_after_apply_with_repair\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/profile_prune.sh"
[ -s "$tmp/profile_prune.sh" ] || fail "profile prune helper extraction"
grep -q '_live_n=$((_live_n+1))' "$tmp/profile_prune.sh" || fail "profile prune does not count live DNS servers"
grep -q '_bad_n=$((_bad_n+1))' "$tmp/profile_prune.sh" || fail "profile prune does not collect failed DNS servers"
grep -q 'slot_set "$_slot" ""' "$tmp/profile_prune.sh" || fail "profile prune does not clear failed slots"
grep -q 'rebuild_selected_hdp_sections' "$tmp/profile_prune.sh" || fail "profile prune does not rebuild DoH sections"
grep -q 'reconcile_dnsmasq' "$tmp/profile_prune.sh" || fail "profile prune does not rebuild dnsmasq upstreams"
awk '/^verify_after_apply_with_repair\(\) \{/,/^verify_after_apply\(\) \{/' dns-manager.sh > "$tmp/profile_verify.sh"
grep -q '\[ "$PROFILE_APPLY" = 1 \]' "$tmp/profile_verify.sh" || fail "profile verification reduced-set path missing"
grep -q 'profile_prune_failed_slots' "$tmp/profile_verify.sh" || fail "profile verification does not prune failed DNS"
grep -Fq '[ -n "${FAILED_SLOT:-}" ] || return 1' "$tmp/profile_verify.sh" || fail "profile verification may prune DNS after a non-slot failure"
grep -Fq 'dnsmasq --test --conf-file="$_dnsmasq_conf"' dns-manager.sh || fail "dnsmasq failure path does not test OpenWrt's generated runtime configuration"
grep -Fq 'logread -e dnsmasq' dns-manager.sh || fail "dnsmasq failure path does not use OpenWrt's documented journal filter"
grep -Fq 'dnsmasq_restart_checked || { tx_restore_on_failure; return 1; }' dns-manager.sh || fail "profile apply still ignores dnsmasq restart failure"
grep -Fq 'dnsmasq_restart_checked || return 1' dns-manager.sh || fail "profile repair still hides dnsmasq restart output"
grep -Fq 'Последние системные сообщения dnsmasq:' dns-manager.sh || fail "dnsmasq startup diagnostics missing"
awk '/^verify_after_apply_with_repair\(\) \{/,/^verify_after_apply\(\) \{/{if ($0 !~ /^verify_after_apply\(\) \{$/) print}' dns-manager.sh > "$tmp/profile_verify_function.sh"
cat > "$tmp/profile_verify_runner.sh" <<'EOF_PROFILE_RUNNER'
#!/bin/sh
set -eu
PROFILE_APPLY=1
FAILED_SLOT=""
MODE=infra
VERIFY_CALL=0
MARKER="$2"
verify_after_apply() {
    VERIFY_CALL=$((VERIFY_CALL+1))
    if [ "$VERIFY_CALL" -eq 1 ]; then
        if [ "$MODE" = slot ]; then FAILED_SLOT=2; else FAILED_SLOT=""; fi
        return 1
    fi
    return 0
}
profile_prune_failed_slots() { : > "$MARKER"; return 0; }
tx_snapshot_after_apply() { :; }
. "$1"
if verify_after_apply_with_repair; then exit 41; fi
[ ! -e "$MARKER" ] || exit 42
MODE=slot
VERIFY_CALL=0
verify_after_apply_with_repair || exit 43
[ -f "$MARKER" ] || exit 44
EOF_PROFILE_RUNNER
chmod +x "$tmp/profile_verify_runner.sh"
"$tmp/profile_verify_runner.sh" "$tmp/profile_verify_function.sh" "$tmp/profile-pruned" || fail "profile verification prunes slots for service errors or skips slot-specific repair"
ok "profile apply preserves slots on service errors and prunes only failed resolvers"

awk '/^dnsmasq_failure_diagnostics\(\) \{/,/^}$/ { print }' dns-manager.sh > "$tmp/dnsmasq_diagnostics.sh"
awk '/^dnsmasq_restart_checked\(\) \{/,/^}$/ { print }' dns-manager.sh > "$tmp/dnsmasq_restart_checked.sh"
[ -s "$tmp/dnsmasq_diagnostics.sh" ] || fail "dnsmasq diagnostics helper extraction"
[ -s "$tmp/dnsmasq_restart_checked.sh" ] || fail "dnsmasq restart helper extraction"
sh -n "$tmp/dnsmasq_diagnostics.sh" || fail "dnsmasq diagnostics helper syntax"
sh -n "$tmp/dnsmasq_restart_checked.sh" || fail "dnsmasq restart helper syntax"
ok "dnsmasq failure diagnostics and checked restart helpers"
 
# Completed profile jobs survive a LuCI page reload and expose the actual reason for failure.
grep -q 'profile_job_status' "$tmp/backend.sh" || fail "persistent profile job status missing"
grep -q 'profile_job_result' "$tmp/backend.sh" || fail "persistent profile job result missing"
grep -q 'profile_job_message' "$tmp/backend.sh" || fail "persistent profile job message missing"
grep -q '"profile_job_status"' "$tmp/backend.sh" || fail "profile job status is not returned by status JSON"
grep -q '"profile_job_message"' "$tmp/backend.sh" || fail "profile job message is not returned by status JSON"
grep -q 'Последняя операция: профиль' "$tmp/common.js" || fail "LuCI does not show the last profile operation after reopen"
grep -q 'Причина:' "$tmp/common.js" || fail "LuCI does not show the profile failure reason"
grep -q 'Закрытие LuCI не останавливает операцию' "$tmp/common.js" || fail "LuCI does not explain persistent running profile jobs"
grep -Fq "setAction(true,p?'Профиль «'+profileName(p)+'» уже применяется. Связь восстановлена.':'Применение профиля уже выполняется. Связь восстановлена.','running')" "$tmp/common.js" || fail "running profile resume is not labeled as running"
ok "LuCI persists profile operation state across page reloads"

# The global action banner is transient; persisted job history is not promoted into that banner.
# Detailed operation state remains available through the dedicated job/profile paths.
ok "LuCI does not require persisted DNS job history for global status banners"

# Watchdog tuning is persisted and exposed as one atomic LuCI save operation.
for _wd_key in WATCHDOG_INTERVAL WATCHDOG_FAIL_THRESHOLD WATCHDOG_REPAIR_COOLDOWN WATCHDOG_MAX_RESTARTS WATCHDOG_GUARD_INTERVAL WATCHDOG_AUTOREPLACE; do
    grep -q "^${_wd_key}=" dns-manager.sh || fail "watchdog config variable missing: $_wd_key"
done
grep -Fq 'WATCHDOG_FAIL_THRESHOLD=$(shell_quote "$WATCHDOG_FAIL_THRESHOLD")' dns-manager.sh || fail "watchdog threshold is not persisted"
grep -Fq 'WATCHDOG_REPAIR_COOLDOWN=$(shell_quote "$WATCHDOG_REPAIR_COOLDOWN")' dns-manager.sh || fail "watchdog repair cooldown is not persisted"
grep -Fq 'WATCHDOG_MAX_RESTARTS=$(shell_quote "$WATCHDOG_MAX_RESTARTS")' dns-manager.sh || fail "watchdog max restarts is not persisted"
grep -Fq 'WATCHDOG_GUARD_INTERVAL=$(shell_quote "$WATCHDOG_GUARD_INTERVAL")' dns-manager.sh || fail "watchdog guard interval is not persisted"
grep -Fq 'WATCHDOG_AUTOREPLACE=$(shell_quote "$WATCHDOG_AUTOREPLACE")' dns-manager.sh || fail "watchdog autoreplace is not persisted"

# Saved config values must round-trip as literal data, including shell metacharacters.
_quote_func="$(sed -n '/^shell_quote() {/,/^}/p' dns-manager.sh)"
[ -n "$_quote_func" ] || fail "shell_quote helper missing"
eval "$_quote_func"
_quote_marker="$tmp/config-quote-injection-marker"
_quote_input="value with 'quotes'; \$(touch '$_quote_marker')"
_quote_encoded="$(shell_quote "$_quote_input")"
eval "_quote_roundtrip=$_quote_encoded"
[ "$_quote_roundtrip" = "$_quote_input" ] || fail "shell_quote did not round-trip a special value"
[ ! -e "$_quote_marker" ] || fail "shell_quote evaluated embedded shell syntax"
ok "config serialization keeps shell metacharacters as literal data"

# Lock recovery must reject PID 0 and must not reuse an existing quarantine path.
[ "$(grep -Fc '|0|*[!0-9]*' dns-manager.sh)" -ge 3 ] || fail "lock recovery accepts PID zero"
[ "$(grep -Fc 'if [ -e "$_stale_lock" ] || [ -L "$_stale_lock" ]; then return 1; fi' dns-manager.sh)" = 3 ] || fail "stale-lock quarantine path is not collision-checked for all lock types"
ok "lock recovery validates PID and checks stale quarantine paths"

grep -Fq 'if [ -e "$MUTATION_LOCK_DIR" ] || [ -L "$MUTATION_LOCK_DIR" ]; then' dns-manager.sh || fail "mutation lock restore can move into an occupied path"
grep -Fq 'if [ -e "$TEST_LOCK_DIR" ] || [ -L "$TEST_LOCK_DIR" ]; then return 1; fi' dns-manager.sh || fail "test lock restore can move into an occupied path"
grep -Fq 'if [ -e "$AUTO_UPDATE_LOCK_DIR" ] || [ -L "$AUTO_UPDATE_LOCK_DIR" ]; then return 1; fi' dns-manager.sh || fail "auto-update lock restore can move into an occupied path"
ok "lock recovery refuses to restore into an occupied path"

# Exercise the mutation lock in an isolated temporary directory.
_lock_funcs="$(sed -n -e '/^acquire_mutation_lock() {/,/^}/p' -e '/^release_mutation_lock() {/,/^}/p' dns-manager.sh)"
[ -n "$_lock_funcs" ] || fail "mutation lock functions missing"
eval "$_lock_funcs"
log_msg() { :; }
STATE_DIR="$tmp/lock-state"
MUTATION_LOCK_DIR="$STATE_DIR/mutation.lock"
MUTATION_LOCK_HELD=0
mkdir -p "$STATE_DIR" || fail "cannot create lock-test directory"
acquire_mutation_lock || fail "fresh mutation lock could not be acquired"
[ "$(cat "$MUTATION_LOCK_DIR/pid")" = "$$" ] || fail "mutation lock owner PID mismatch"
release_mutation_lock
[ ! -d "$MUTATION_LOCK_DIR" ] || fail "mutation lock was not released"

mkdir -p "$MUTATION_LOCK_DIR" || fail "cannot prepare live-lock test"
printf '%s\n' "$$" > "$MUTATION_LOCK_DIR/pid"
if acquire_mutation_lock; then
    fail "mutation lock allowed a second acquisition by the same live PID"
fi
[ -d "$MUTATION_LOCK_DIR" ] || fail "live mutation lock was removed"
rm -rf "$MUTATION_LOCK_DIR"

_test_stale_pid=999999
while kill -0 "$_test_stale_pid" 2>/dev/null; do _test_stale_pid=$((_test_stale_pid + 1)); done
mkdir -p "$MUTATION_LOCK_DIR" || fail "cannot prepare stale-lock test"
printf '%s\n' "$_test_stale_pid" > "$MUTATION_LOCK_DIR/pid"
acquire_mutation_lock || fail "stale mutation lock was not recovered"
[ "$(cat "$MUTATION_LOCK_DIR/pid")" = "$$" ] || fail "recovered lock has the wrong owner"
release_mutation_lock

mkdir -p "$MUTATION_LOCK_DIR" "$MUTATION_LOCK_DIR.stale.$$" || fail "cannot prepare quarantine collision test"
printf '%s\n' "$_test_stale_pid" > "$MUTATION_LOCK_DIR/pid"
: > "$MUTATION_LOCK_DIR.stale.$$/marker"
if acquire_mutation_lock; then
    fail "mutation lock ignored an existing stale-quarantine path"
fi
[ -d "$MUTATION_LOCK_DIR" ] || fail "quarantine collision removed the original lock"
[ -f "$MUTATION_LOCK_DIR.stale.$$/marker" ] || fail "quarantine collision altered the existing path"
rm -rf "$MUTATION_LOCK_DIR" "$MUTATION_LOCK_DIR.stale.$$"

# Corrupt PID data must fail closed without deleting the existing lock.
mkdir -p "$MUTATION_LOCK_DIR" || fail "cannot prepare malformed-PID lock"
printf '%s\n' 'not-a-pid' > "$MUTATION_LOCK_DIR/pid"
if acquire_mutation_lock; then
    fail "mutation lock accepted a malformed PID"
fi
[ -d "$MUTATION_LOCK_DIR" ] || fail "malformed mutation lock was deleted"
rm -rf "$MUTATION_LOCK_DIR"
ok "mutation lock rejects malformed PID without deleting the lock"

# Exercise the test lock dynamically: PID 0 and a pre-existing quarantine path.
_test_lock_funcs="$(sed -n -e '/^acquire_test_lock() {/,/^}/p' -e '/^release_test_lock() {/,/^}/p' dns-manager.sh)"
[ -n "$_test_lock_funcs" ] || fail "test lock functions missing"
eval "$_test_lock_funcs"
STATE_DIR="$tmp/test-lock-state"
TEST_LOCK_DIR="$STATE_DIR/test.lock"
TEST_LOCK_HELD=0
mkdir -p "$STATE_DIR" "$TEST_LOCK_DIR" || fail "cannot prepare test-lock PID test"
printf '%s\n' 0 > "$TEST_LOCK_DIR/pid"
if acquire_test_lock; then fail "test lock accepted PID zero"; fi
[ -d "$TEST_LOCK_DIR" ] || fail "invalid test lock was deleted"
rm -rf "$TEST_LOCK_DIR"
mkdir -p "$TEST_LOCK_DIR" "$TEST_LOCK_DIR.stale.$$" || fail "cannot prepare test-lock quarantine test"
printf '%s\n' "$_test_stale_pid" > "$TEST_LOCK_DIR/pid"
: > "$TEST_LOCK_DIR.stale.$$/marker"
if acquire_test_lock; then fail "test lock ignored an existing quarantine path"; fi
[ -d "$TEST_LOCK_DIR" ] || fail "test-lock collision removed original lock"
[ -f "$TEST_LOCK_DIR.stale.$$/marker" ] || fail "test-lock collision altered quarantine path"
rm -rf "$TEST_LOCK_DIR" "$TEST_LOCK_DIR.stale.$$"
ok "test lock rejects invalid PID and preserves quarantine collisions"

# Exercise the auto-update lock dynamically with the same failure cases.
_auto_lock_funcs="$(sed -n '/^acquire_auto_update_lock() {/,/^}/p' dns-manager.sh)"
[ -n "$_auto_lock_funcs" ] || fail "auto-update lock function missing"
eval "$_auto_lock_funcs"
STATE_DIR="$tmp/auto-lock-state"
AUTO_UPDATE_LOCK_DIR="$STATE_DIR/auto-update.lock"
AUTO_UPDATE_LOCK_HELD=0
mkdir -p "$STATE_DIR" "$AUTO_UPDATE_LOCK_DIR" || fail "cannot prepare auto-update PID test"
printf '%s\n' 0 > "$AUTO_UPDATE_LOCK_DIR/pid"
if acquire_auto_update_lock; then fail "auto-update lock accepted PID zero"; fi
[ -d "$AUTO_UPDATE_LOCK_DIR" ] || fail "invalid auto-update lock was deleted"
rm -rf "$AUTO_UPDATE_LOCK_DIR"
mkdir -p "$AUTO_UPDATE_LOCK_DIR" "$AUTO_UPDATE_LOCK_DIR.stale.$$" || fail "cannot prepare auto-update quarantine test"
printf '%s\n' "$_test_stale_pid" > "$AUTO_UPDATE_LOCK_DIR/pid"
: > "$AUTO_UPDATE_LOCK_DIR.stale.$$/marker"
if acquire_auto_update_lock; then fail "auto-update lock ignored an existing quarantine path"; fi
[ -d "$AUTO_UPDATE_LOCK_DIR" ] || fail "auto-update collision removed original lock"
[ -f "$AUTO_UPDATE_LOCK_DIR.stale.$$/marker" ] || fail "auto-update collision altered quarantine path"
rm -rf "$AUTO_UPDATE_LOCK_DIR" "$AUTO_UPDATE_LOCK_DIR.stale.$$"
ok "auto-update lock rejects invalid PID and preserves quarantine collisions"

ok "mutation lock acquisition, release and stale-lock recovery are exercised"

# Round-trip the real config writer with shell syntax embedded as data.
_save_funcs="$(sed -n -e '/^shell_quote() {/,/^}/p' -e '/^save_config() {/,/^}/p' dns-manager.sh)"
[ -n "$_save_funcs" ] || fail "config save functions missing"
eval "$_save_funcs"
sync_regional_dns_state() { :; }
CFG_DIR="$tmp/config-save"
CONFIG_FILE="$CFG_DIR/manager.conf"
TX_ACTIVE=0
DEFER_CONFIG_SAVE=0
_quote_marker="$tmp/config-save-injection-marker"
_expected_config_value="value with 'quotes'; \$(touch '$_quote_marker')"
SLOT_1="$_expected_config_value"
BOOTSTRAP_DNS_ALL="$_expected_config_value"
save_config || fail "save_config failed for a value with shell metacharacters"
SLOT_1=""
BOOTSTRAP_DNS=""
. "$CONFIG_FILE" || fail "saved manager.conf could not be sourced"
[ "$SLOT_1" = "$_expected_config_value" ] || fail "SLOT_1 did not round-trip from manager.conf"
[ "$BOOTSTRAP_DNS" = "$_expected_config_value" ] || fail "bootstrap DNS did not round-trip from manager.conf"
[ ! -e "$_quote_marker" ] || fail "sourcing manager.conf executed embedded shell syntax"
ok "manager.conf safely saves and reloads special characters"

# Exercise concurrent lock acquisition in two independent shell processes.
STATE_DIR="$tmp/lock-concurrent"
MUTATION_LOCK_DIR="$STATE_DIR/mutation.lock"
MUTATION_LOCK_HELD=0
mkdir -p "$STATE_DIR" || fail "cannot create concurrent lock-test directory"
{
    sed -n -e '/^acquire_mutation_lock() {/,/^}/p' -e '/^release_mutation_lock() {/,/^}/p' dns-manager.sh
    cat <<'EOF_LOCK_HOLDER'
log_msg() { :; }
STATE_DIR="$1"
MUTATION_LOCK_DIR="$STATE_DIR/mutation.lock"
MUTATION_LOCK_HELD=0
mkdir -p "$STATE_DIR" || exit 3
acquire_mutation_lock || exit 4
: > "$STATE_DIR/ready"
sleep 1
release_mutation_lock
EOF_LOCK_HOLDER
} > "$tmp/lock-holder.sh"
sh "$tmp/lock-holder.sh" "$STATE_DIR" &
_holder_pid=$!
_wait=0
while [ ! -f "$STATE_DIR/ready" ] && [ "$_wait" -lt 50 ]; do
    sleep 0.1
    _wait=$((_wait + 1))
done
if [ ! -f "$STATE_DIR/ready" ]; then
    kill "$_holder_pid" 2>/dev/null || true
    wait "$_holder_pid" 2>/dev/null || true
    fail "concurrent lock holder did not become ready"
fi
if acquire_mutation_lock; then
    release_mutation_lock
    wait "$_holder_pid" 2>/dev/null || true
    fail "second process acquired an active mutation lock"
fi
[ -d "$MUTATION_LOCK_DIR" ] || fail "active lock disappeared during concurrent contention"
wait "$_holder_pid" || fail "concurrent lock holder failed"
[ ! -d "$MUTATION_LOCK_DIR" ] || fail "concurrent lock holder did not release its lock"
ok "mutation lock rejects a concurrent process and releases cleanly"
grep -q 'watchdog_interval":%s,"watchdog_service' "$tmp/backend.sh" || fail "LuCI status does not expose saved watchdog interval"
if sed -n '/watchdog_interval/p' "$tmp/backend.sh" | grep -Fq '\'; then fail "LuCI status JSON has literal backslashes in keys"; fi
if sed -n '/watchdog_fail_threshold/p' "$tmp/backend.sh" | grep -Fq '\'; then fail "LuCI network status JSON has literal backslashes in keys"; fi

grep -q '^        set_watchdog_setting)' "$tmp/backend.sh" || fail "legacy watchdog setting dispatch missing"
grep -q '^        set_watchdog_settings)' "$tmp/backend.sh" || fail "atomic watchdog settings dispatch missing"
grep -q '"set_watchdog_settings"' "$tmp/backend.sh" || fail "atomic watchdog settings RPC schema missing"
grep -q 'watchdog_apply_values() {' "$tmp/backend.sh" || fail "shared watchdog apply helper missing"
grep -q 'watchdog_apply_single() {' "$tmp/backend.sh" || fail "legacy watchdog helper missing"
grep -q 'watchdog_apply_batch() {' "$tmp/backend.sh" || fail "batch watchdog helper missing"
grep -q 'watchdog_service_stop_disable' "$tmp/backend.sh" || fail "watchdog batch setter does not stop supervisor first"
grep -q 'save_config' "$tmp/backend.sh" || fail "watchdog batch setter save path missing"
grep -q 'watchdog_service_start_enable' "$tmp/backend.sh" || fail "watchdog batch setter does not restart procd after apply"
grep -q 'watchdog_cron_remove_owned_block' "$tmp/backend.sh" || fail "watchdog setter does not handle manager-owned cron watchdog"
grep -q 'watchdog_restore_service_state' "$tmp/backend.sh" || fail "watchdog rollback helper missing"
grep -Fq 'watchdog_apply_values "$_interval" "$_threshold" "$_repair_cooldown" "$_max_restarts" "$_guard_interval"' "$tmp/backend.sh" || fail "batch watchdog values are not forwarded together"

grep -q "method:'set_watchdog_settings'" "$tmp/common.js" || fail "LuCI does not use the atomic watchdog RPC"
grep -Fq "params:['interval','threshold','repair_cooldown','max_restarts','guard_interval']" "$tmp/common.js" || fail "atomic watchdog RPC parameter order mismatch"
if grep -q 'var callWatchdogSetting = ' "$tmp/common.js"; then
    fail "LuCI still defines the per-setting watchdog RPC"
fi
awk '/^function watchdogCard\(root,st\)\{/,/^function renderTestAgeCommon/' "$tmp/common.js" > "$tmp/watchdog_card.js"
save_count="$(grep -o 'Сохранить' "$tmp/watchdog_card.js" | wc -l | tr -d ' ')"
[ "$save_count" = 1 ] || fail "watchdog must have exactly one Save label"
grep -q 'Сохранить настройки' "$tmp/watchdog_card.js" || fail "common watchdog save button missing"
grep -q 'Дополнительные параметры' "$tmp/watchdog_card.js" || fail "advanced watchdog section missing"
grep -q 'Контроль текущих DNS' "$tmp/watchdog_card.js" || fail "watchdog settings section title missing"
for _wd_label in 'Как часто проверять DNS' 'Ошибок подряд до замены' 'Пауза между попытками восстановления DNS' 'Проверка DNS' 'Автозамена DNS'; do
    grep -q "$_wd_label" "$tmp/watchdog_card.js" || fail "LuCI watchdog control missing: $_wd_label"
done
if grep -q 'Проверить сейчас' "$tmp/watchdog_card.js"; then
    fail "Watchdog panel must not duplicate the full current-DNS test action"
fi
grep -q 'локальный порт назначенного DoH' "$tmp/watchdog_card.js" || fail "Watchdog probe is not explained in LuCI"
grep -q 'Полный разовый тест текущих DoH' "$tmp/watchdog_card.js" || fail "LuCI does not direct users to the distinct full DNS test"

# The Network tab uses network_status_json rather than the dashboard status RPC.
# It must expose the latest saved watchdog results as well as the service flags.
awk '/^network_status_json\(\) \{/,/^}/' dns-manager-luci.sh > "$tmp/network_status_json.sh"
[ -s "$tmp/network_status_json.sh" ] || fail "network status function extraction"
for _wd_field in watchdog_last_check watchdog_last_checked watchdog_last_failed watchdog_last_category watchdog_last_records; do
    grep -Fq "$_wd_field" "$tmp/network_status_json.sh" || fail "network status omits saved watchdog field: $_wd_field"
done
grep -Fq 'dns-watchdog-check-results.conf' "$tmp/network_status_json.sh" || fail "network status does not read saved watchdog results"
grep -Fq 'while IFS=' "$tmp/network_status_json.sh" || fail "network status does not serialize watchdog result records"
ok "network status exposes saved watchdog results"
if grep -q 'Сколько DNS можно заменить за раз' "$tmp/watchdog_card.js"; then
    fail "LuCI still shows the removed per-cycle repair-count setting"
fi
if grep -q 'Рестартов https-dns-proxy\|Тяжёлая сверка' "$tmp/watchdog_card.js"; then
    fail "technical watchdog labels still exposed in LuCI"
fi
# Numeric watchdog fields must use a single-escaped digit regex; double-escaped \\d rejects normal values.
grep -Fq '(x[6]||/^\d+$/.test(raw))' "$tmp/watchdog_card.js" || fail "watchdog numeric validation regex is missing"
if grep -Fq '(x[6]||/^\\d+$/.test(raw))' "$tmp/watchdog_card.js"; then
    fail "watchdog numeric validation regex is double-escaped"
fi
ok "watchdog numeric field validation accepts normal integer values"

wd_stop_block="$(sed -n '/^watchdog_service_stop_disable() {/,/^}/p' dns-manager.sh)"
printf '%s\\n' "$wd_stop_block" | grep -Fq 'while watchdog_service_running && [ "$_wd_wait" -lt 5 ]' || fail "watchdog stop path has no bounded procd grace wait"
printf '%s\\n' "$wd_stop_block" | grep -Fq 'sleep 1' || fail "watchdog stop grace wait has no sleep"
ok "watchdog settings save tolerates asynchronous procd stop"

ok "watchdog tuning is persisted through one atomic RPC and exposed as a compact LuCI form"

# The legacy single-setting RPC remains available for older clients, but shares the same apply path.
grep -q 'watchdog_apply_single' "$tmp/backend.sh" || fail "legacy watchdog setter does not use shared apply logic"
grep -q 'watchdog_apply_batch' "$tmp/backend.sh" || fail "batch watchdog setter helper missing"
ok "legacy watchdog RPC compatibility is preserved"
# NTP RPC must be explicitly allowed by the LuCI ACL; the backend alone is not enough.
grep -Fq '"set_ntp", "set_test_age"' dns-manager-luci.sh || fail "LuCI write ACL does not allow set_ntp"
if grep -Fq '192.168.1.1' dns-manager.sh; then
    fail "DNS Manager contains a fixed LAN IP fallback"
fi
if grep -Fq '192.168.1.1' dns-manager-luci.sh; then
    fail "DNS Manager LuCI contains a fixed LAN IP binding"
fi
ok "NTP RPC is allowed by ACL and no fixed router LAN IP is used"



# Refreshing a category-scoped DNS test must validate that same scope afterwards.
awk '/^ensure_test_results_fresh\(\) \{/,/^watchdog_scope_category\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/ensure_test_results_fresh.sh"
[ -s "$tmp/ensure_test_results_fresh.sh" ] || fail "category freshness helper extraction"
cat > "$tmp/ensure_test_results_fresh_runner.sh" <<'EOF_FRESH_SCOPE'
#!/bin/sh
set -eu
HAS_CURL=yes
CALLS=0
watchdog_test_results_usable() {
    CALLS=$((CALLS+1))
    [ "${1:-}" = security ] && [ "$CALLS" -eq 2 ]
}
test_dns_catalog() { [ "$1" = security ]; }
info_msg() { :; }
. "$1"
ensure_test_results_fresh security || exit 41
[ "$CALLS" -eq 2 ] || exit 42
EOF_FRESH_SCOPE
chmod +x "$tmp/ensure_test_results_fresh_runner.sh"
"$tmp/ensure_test_results_fresh_runner.sh" "$tmp/ensure_test_results_fresh.sh" || fail "category test refresh validates the wrong scope"
ok "category-scoped DNS test refresh preserves its scope"
# A category-specific freshness setting must override the common fallback.
awk '/^test_results_max_age_for_category\(\) \{/,/^}/' dns-manager.sh > "$tmp/test_results_max_age.sh"
[ -s "$tmp/test_results_max_age.sh" ] || fail "category freshness helper extraction"
cat > "$tmp/test_results_max_age_runner.sh" <<'EOF_TEST_AGE'
#!/bin/sh
set -eu
TEST_RESULTS_MAX_AGE=21600
TEST_RESULTS_MAX_AGE_BYPASS=3600
TEST_RESULTS_MAX_AGE_CLEAN=7200
. "$1"
[ "$(test_results_max_age_for_category bypass)" = 3600 ] || exit 41
[ "$(test_results_max_age_for_category clean)" = 7200 ] || exit 42
[ "$(test_results_max_age_for_category all)" = 21600 ] || exit 43
[ "$(test_results_max_age_for_category unknown)" = 21600 ] || exit 44
EOF_TEST_AGE
chmod +x "$tmp/test_results_max_age_runner.sh"
"$tmp/test_results_max_age_runner.sh" "$tmp/test_results_max_age.sh" || fail "category-specific DNS freshness is overridden by the common value"
ok "category-specific DNS result freshness settings take precedence"

awk '/^show_tests\(\) \{/,/^profile_apply_begin\(\) \{/' dns-manager.sh > "$tmp/show_tests.sh"
grep -Fq 'watchdog_test_results_fresh "$_test_scope"' "$tmp/show_tests.sh" || fail "DNS results screen does not check freshness"
grep -Fq 'Сохранённые результаты устарели' "$tmp/show_tests.sh" || fail "DNS results screen does not label stale results"
awk '/^quick_max_bypass\(\) \{/,/^test_results_max_age_for_category\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/quick_max_bypass.sh"
grep -Fq 'watchdog_test_results_usable bypass' "$tmp/quick_max_bypass.sh" || fail "bypass flow reuses results without checking working DNS"
grep -Fq 'test_dns_catalog bypass' "$tmp/quick_max_bypass.sh" || fail "bypass flow tests the entire catalog instead of its category"
grep -Fq '_catalog_hash_start="$(file_hash "$DNS_CATALOG")"' dns-manager.sh || fail "DNS test does not snapshot the starting catalog hash"
grep -Fq 'Каталог DNS изменился во время проверки. Результат отброшен' dns-manager.sh || fail "DNS test does not discard results when catalog changes during testing"
ok "DNS result freshness display and category-scoped tests"
# A successful regional resolver cannot make a failing general category usable.
awk '/^watchdog_test_results_usable\(\) \{/,/^}/' dns-manager.sh > "$tmp/watchdog_test_results_usable.sh"
[ -s "$tmp/watchdog_test_results_usable.sh" ] || fail "usable DNS result helper extraction"
cat > "$tmp/watchdog_test_results_usable_runner.sh" <<'EOF_USABLE_RESULTS'
#!/bin/sh
set -eu
TEST_RESULTS="$2"
watchdog_test_results_fresh() { return 0; }
. "$1"
printf 'yandex_ru|regional|Yandex RU|10|OK\n' > "$TEST_RESULTS"
if watchdog_test_results_usable bypass; then exit 41; fi
if watchdog_test_results_usable all; then exit 42; fi
printf 'yandex_ru|regional|Yandex RU|10|OK\ncomss_bypass|bypass|Comss|20|OK\n' > "$TEST_RESULTS"
watchdog_test_results_usable bypass || exit 43
printf 'adguard_default|adblock|AdGuard|20|OK\n' > "$TEST_RESULTS"
if watchdog_test_results_usable bypass; then exit 44; fi
EOF_USABLE_RESULTS
chmod +x "$tmp/watchdog_test_results_usable_runner.sh"
"$tmp/watchdog_test_results_usable_runner.sh" "$tmp/watchdog_test_results_usable.sh" "$tmp/usable-results" || fail "regional or unrelated DNS result satisfies selected category"
ok "cached DNS usability requires a working resolver in the requested category"

# Preserve an existing RU DNS only when it passed the fresh regional test.
awk '/^apply_profile_now\(\) \{/,/^menu_category_select\(\)/' dns-manager.sh | sed '$d' > "$tmp/apply_profile_now_ru.sh"
[ -s "$tmp/apply_profile_now_ru.sh" ] || fail "profile application helper extraction"
cat > "$tmp/apply_profile_now_ru_runner.sh" <<'EOF_PROFILE_RU'
#!/bin/sh
set -eu
TMP_DIR="$1"
TEST_RESULTS="$TMP_DIR/ru-results"
case "$2" in
    keep_old)
        cat > "$TEST_RESULTS" <<'EOF_RU_OK'
ru_old|regional|Old RU|10|OK
ru_candidate|regional|Candidate RU|20|OK
EOF_RU_OK
        _expected=ru_old
        ;;
    replace_old)
        cat > "$TEST_RESULTS" <<'EOF_RU_BAD'
ru_old|regional|Old RU|-1|TIMEOUT
ru_candidate|regional|Candidate RU|20|OK
EOF_RU_BAD
        _expected=ru_candidate
        ;;
    *) exit 40 ;;
esac
SLOT_RU=ru_old
SLOT_RU_CAT=regional
DNS_PROFILE=hybrid
DNS_SELECTION_MODE=profile
DNS_SELECTION_CATEGORY=clean
TLD_RU_ENABLED=1
TLD_SPLIT=1
BALANCER_ENABLED=1
HYBRID_STAGE_SKIP=0
HYBRID_PORT_1=5053
HYBRID_PORT_2=5054
HYBRID_PORT_3=5055
HYBRID_PORT_4=5056
HYBRID_PORT_5=5057
HYBRID_PORT_6=5058
HYBRID_PORT_RU=5059
NTP_IP_FALLBACK=0
FORCE_DOH=0
DNSMASQ_PERF=0
WATCHDOG_ENABLED=0
profile_apply_begin() { return 0; }
profile_apply_end() { :; }
auto_fill_slots() { SLOT_RU=ru_candidate; SLOT_RU_CAT=regional; return 0; }
apply_settings() { return 0; }
. "$3"
apply_profile_now clean || exit 41
[ "$SLOT_RU" = "$_expected" ] || exit 42
EOF_PROFILE_RU
chmod +x "$tmp/apply_profile_now_ru_runner.sh"
"$tmp/apply_profile_now_ru_runner.sh" "$tmp" keep_old "$tmp/apply_profile_now_ru.sh" || fail "working previous RU DNS was not preserved"
"$tmp/apply_profile_now_ru_runner.sh" "$tmp" replace_old "$tmp/apply_profile_now_ru.sh" || fail "unhealthy previous RU DNS replaced the working candidate"
ok "profile keeps the previous RU DNS only when its fresh test passed"

# A failed transaction must reload the just-restored manager configuration into memory.
awk '/^tx_restore_on_failure\(\) \{/,/^tx_commit\(\) \{/' dns-manager.sh | sed '$d' > "$tmp/tx_restore_on_failure.sh"
[ -s "$tmp/tx_restore_on_failure.sh" ] || fail "transaction rollback helper extraction"
cat > "$tmp/tx_restore_on_failure_runner.sh" <<'EOF_ROLLBACK_STATE'
#!/bin/sh
set -eu
WORK="$2"
CONFIG_FILE="$WORK/manager.conf"
TX_DIR="$WORK/tx-rollback"
mkdir -p "$TX_DIR/files"
printf 'SLOT_1="old_dns"\nSLOT_RU="ru_old"\nDNS_PROFILE="hybrid"\n' > "$TX_DIR/files/manager.conf"
printf 'SLOT_1="new_dns"\nSLOT_RU="ru_new"\nDNS_PROFILE="custom"\n' > "$CONFIG_FILE"
printf '%s|manager.conf|1\n' "$CONFIG_FILE" > "$TX_DIR/manifest"
TX_ACTIVE=1
DEFER_CONFIG_SAVE=1
SLOT_1=new_dns
SLOT_RU=ru_new
DNS_PROFILE=custom
LOAD_CONFIG_CALLED=0
watchdog_cron_remove_owned_block() { :; }
tx_restore_watchdog_state() { :; }
reload_fw() { :; }
warn_msg() { :; }
log_msg() { :; }
log_tx() { :; }
load_config() {
    LOAD_CONFIG_CALLED=1
    . "$CONFIG_FILE"
}
. "$1"
tx_restore_on_failure
[ "$LOAD_CONFIG_CALLED" -eq 1 ] || exit 41
[ "$SLOT_1" = old_dns ] && [ "$SLOT_RU" = ru_old ] && [ "$DNS_PROFILE" = hybrid ] || exit 42
[ "$TX_ACTIVE" -eq 0 ] && [ "$DEFER_CONFIG_SAVE" -eq 0 ] || exit 43
EOF_ROLLBACK_STATE
chmod +x "$tmp/tx_restore_on_failure_runner.sh"
"$tmp/tx_restore_on_failure_runner.sh" "$tmp/tx_restore_on_failure.sh" "$tmp" || fail "transaction rollback left stale profile variables in memory"
ok "transaction rollback restores the in-memory manager profile"

sh tests/test-uninstall-regression.sh || fail "uninstall regression tests"

printf '%s\n' "All DNS Manager regression checks passed."
