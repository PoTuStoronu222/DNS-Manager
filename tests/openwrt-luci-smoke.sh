#!/bin/sh
# DNS Manager LuCI on-device smoke test.
# Run this on a disposable OpenWrt router through SSH. It installs from the
# selected Git branch and reports every checked installer/RPC step.
set -u

REPO="PoTuStoronu222/DNS-Manager"
REF="${DNS_MANAGER_SOURCE_REF:-test/low-ram-dns-workers}"
RUN_NETWORK=0
KEEP_INSTALLER=0
TMP="/tmp/dns-manager-luci-smoke-$$.sh"

say() { printf '\n==> %s\n' "$*"; }
ok() { printf '    OK  %s\n' "$*"; }
warn() { printf '    !!  %s\n' "$*" >&2; }
fail() { printf '    FAIL %s\n' "$*" >&2; exit 1; }
cleanup() { [ "$KEEP_INSTALLER" = 1 ] || rm -f "$TMP" 2>/dev/null || true; }
trap cleanup EXIT HUP INT TERM

usage() {
    cat <<EOF
Usage: DNS_MANAGER_SOURCE_REF=<branch> sh $0 [--network] [--keep-installer]

  --network         Run one catalog DNS test through the same RPC job used
                    by the LuCI "Проверить" button. It needs Internet access.
  --keep-installer  Keep the downloaded installer in /tmp for investigation.

The default checks installation, generated LuCI files and read-only RPC calls.
It does not apply a DNS profile, enable the watchdog or change DNS routing.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --network) RUN_NETWORK=1 ;;
        --keep-installer) KEEP_INSTALLER=1 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown option: $1" ;;
    esac
    shift
done

[ "$(id -u 2>/dev/null || printf x)" = 0 ] || fail "Run this test as root."
[ -f /etc/openwrt_release ] || fail "This smoke test is for OpenWrt."
case "$REF" in ''|/*|*//*|*..*|*[!A-Za-z0-9._/-]*) fail "Invalid DNS_MANAGER_SOURCE_REF: $REF" ;; esac

fetch() {
    _url="$1"
    _out="$2"
    rm -f "$_out" 2>/dev/null || true
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 120 -o "$_out" "$_url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 120 -O "$_out" "$_url"
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -T 120 -O "$_out" "$_url"
    else
        return 1
    fi
    [ -s "$_out" ] && ! head -c 512 "$_out" | grep -qiE '<(!doctype|html|head|body)' 
}

assert_file() {
    [ -e "$1" ] || fail "Missing: $1"
    ok "$1"
}

rpc() {
    _method="$1"
    _body="${2:-{}}"
    _reply="$(ubus call dns_manager "$_method" "$_body" 2>&1)" || {
        printf '%s\n' "$_reply"
        fail "RPC $_method failed"
    }
    printf '%s\n' "$_reply"
    printf '%s' "$_reply" | grep -q '"error"' && fail "RPC $_method returned an error"
    ok "RPC $_method"
}

wait_for_rpcd() {
    _left=20
    while [ "$_left" -gt 0 ]; do
        ubus list dns_manager >/dev/null 2>&1 && return 0
        sleep 1
        _left=$((_left - 1))
    done
    return 1
}

start_catalog_job() {
    _id="$1"
    _reply="$(ubus call dns_manager test_one "{\"id\":\"$_id\"}" 2>&1)" || {
        printf '%s\n' "$_reply"
        return 1
    }
    printf '%s\n' "$_reply"
    _job="$(printf '%s' "$_reply" | sed -n 's/.*"job":"\([^"]*\)".*/\1/p')"
    case "$_job" in ''|*[!A-Za-z0-9_-]*) return 1;; esac

    _left=40
    while [ "$_left" -gt 0 ]; do
        _state="$(ubus call dns_manager job "{\"id\":\"$_job\"}" 2>&1)" || return 1
        printf '%s\n' "$_state"
        _status="$(printf '%s' "$_state" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
        case "$_status" in
            done|failed)
                printf '%s' "$_state" | grep -q '"output":' || return 1
                return 0
                ;;
        esac
        sleep 2
        _left=$((_left - 1))
    done
    return 1
}

say "Download test-branch installer"
URL="https://raw.githubusercontent.com/$REPO/$REF/dns-manager-luci.sh"
fetch "$URL" "$TMP" || fail "Could not download $URL"
sh -n "$TMP" || fail "Downloaded installer has invalid shell syntax"
ok "Downloaded installer from $REF"

say "Install DNS Manager LuCI"
DNS_MANAGER_SOURCE_REF="$REF" sh "$TMP" install || fail "Installer returned a non-zero status"
ok "Installer completed"

say "Verify installed files"
assert_file /usr/bin/dns-manager
assert_file /usr/libexec/rpcd/dns_manager
assert_file /usr/lib/dns-manager-luci/backend.sh
assert_file /usr/share/rpcd/acl.d/luci-app-dns-manager.json
assert_file /usr/share/luci/menu.d/luci-app-dns-manager.json
assert_file /www/luci-static/resources/dns-manager/common.js
for view in dashboard doh slots devices network time catalog log; do
    assert_file "/www/luci-static/resources/view/dns-manager/$view.js"
done
sh -n /usr/bin/dns-manager || fail "Installed DNS backend has invalid shell syntax"
sh -n /usr/lib/dns-manager-luci/backend.sh || fail "Installed LuCI backend has invalid shell syntax"
ok "Installed shell files pass syntax validation"

say "Verify rpcd and read-only LuCI actions"
wait_for_rpcd || fail "rpcd did not publish dns_manager within 20 seconds"
ok "rpcd published dns_manager"
rpc status '{}'
rpc runtime '{}'
rpc doh_status '{}'
rpc network_status '{}'
rpc time_status '{}'
rpc page_meta '{}'
rpc catalog '{"category":"all","offset":0,"limit":1,"only_ok":0}'

if [ "$RUN_NETWORK" = 1 ]; then
    say "Exercise LuCI DNS test button through its background job"
    _catalog="/etc/dns-manager/config/dns-catalog.conf"
    _id="$(awk -F'|' 'NF>=5 && $1 !~ /^#/ {print $1; exit}' "$_catalog" 2>/dev/null || true)"
    [ -n "$_id" ] || fail "No catalog entry available for test_one"
    start_catalog_job "$_id" || fail "LuCI test_one job did not finish cleanly"
    ok "LuCI DNS test job completed; its result and output are printed above"
fi

say "Smoke test completed"
printf 'Branch: %s\nNetwork button test: %s\n' "$REF" "$RUN_NETWORK"