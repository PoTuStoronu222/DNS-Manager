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
ok "shell syntax"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

awk '
    /cat > "[^"]*BACKEND_STAGE[^"]*"[^<]*<<\x27EOF_RPC\x27/ { capture=1; next }
    capture && /^EOF_RPC$/ { exit }
    capture { print }
' dns-manager-luci.sh > "$tmp/backend.sh"
[ -s "$tmp/backend.sh" ] || fail "embedded backend extraction"
sh -n "$tmp/backend.sh" || fail "embedded backend: sh -n"
ok "embedded backend syntax"

awk '
    /cat > "[^"]*VIEW_STAGE[^"]*"[^<]*<<\x27EOF_JS\x27/ { capture=1; next }
    capture && /^EOF_JS$/ { exit }
    capture { print }
' dns-manager-luci.sh > "$tmp/overview.js"
[ -s "$tmp/overview.js" ] || fail "embedded JS extraction"
node --check "$tmp/overview.js" >/dev/null 2>&1 || fail "embedded JS: node --check"
ok "embedded LuCI JS syntax"

DOLLAR='$'
PID_LITERAL="${DOLLAR}${DOLLAR}"
grep -Fq 'BACKEND_STAGE="${BACKEND_FILE}.new.' dns-manager-luci.sh || fail "backend staging prefix missing"
grep -Fq "BACKEND_STAGE=\"\${BACKEND_FILE}.new.${PID_LITERAL}\"" dns-manager-luci.sh || fail "backend staging PID suffix missing"
grep -q 'mv -f "$BACKEND_STAGE" "$BACKEND_FILE"' dns-manager-luci.sh || fail "backend atomic swap missing"
grep -Fq 'RPC_STAGE="${RPC_PLUGIN}.new.' dns-manager-luci.sh || fail "RPC staging prefix missing"
grep -Fq "RPC_STAGE=\"\${RPC_PLUGIN}.new.${PID_LITERAL}\"" dns-manager-luci.sh || fail "RPC staging PID suffix missing"
grep -q 'mv -f "$RPC_STAGE" "$RPC_PLUGIN"' dns-manager-luci.sh || fail "RPC plugin atomic swap missing"
grep -Fq 'VIEW_STAGE="${VIEW_FILE}.new.' dns-manager-luci.sh || fail "view staging prefix missing"
grep -Fq "VIEW_STAGE=\"\${VIEW_FILE}.new.${PID_LITERAL}\"" dns-manager-luci.sh || fail "view staging PID suffix missing"
grep -q 'mv -f "$VIEW_STAGE" "$VIEW_FILE"' dns-manager-luci.sh || fail "view atomic swap missing"
grep -q 'function dmRpc(o)' "$tmp/overview.js" || fail "RPC retry wrapper missing"
grep -q 'Object not found' "$tmp/overview.js" || fail "RPC retry condition missing"
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
grep -q 'bypass|clean|security|privacy|adblock|family|regional' dns-manager.sh || fail "catalog category validation missing"
grep -q 'acquire_runtime_lock() {' "$tmp/backend.sh" || fail "LuCI runtime lock helper missing"
grep -q 'json_update_state() {' "$tmp/backend.sh" || fail "structured update result helper missing"
grep -q 'updated) exit 0' dns-manager.sh || fail "manager update-check exit contract missing"
grep -q 'current|throttled) exit 2' dns-manager.sh || fail "manager current exit contract missing"
ok "LuCI atomic install, RPC retry, safe dynamic assignments and lock/result helpers"

grep -q '^        set_watchdog_setting)' "$tmp/backend.sh" || fail "watchdog setting dispatch missing"
grep -q 'WATCHDOG_INTERVAL' "$tmp/backend.sh" || fail "watchdog interval handling missing"
if awk '/^        set_setting\)/ { capture=1 } capture { print } capture && /^        set_watchdog_setting\)/ { exit }' "$tmp/backend.sh" | grep -q '_value'; then
    fail "set_setting still contains stale _value watchdog logic"
fi
grep -q 'apply_watchdog .*|| _rc=' "$tmp/backend.sh" || fail "watchdog apply result is not checked"
grep -q 'apply_extras_now force .*|| _rc=' "$tmp/backend.sh" || fail "force apply result is not checked"
grep -q 'apply_extras_now dnsmasq_perf .*|| _rc=' "$tmp/backend.sh" || fail "dnsmasq_perf apply result is not checked"
if grep -q 'update_check_job' "$tmp/backend.sh"; then
    fail "stale update_check_job backend method remains"
fi
if grep -q 'update_check_job_status' "$tmp/backend.sh"; then
    fail "stale update_check_job_status backend method remains"
fi
ok "LuCI RPC dispatch contract"

top_luci="$(sed -n 's/^# Version:[[:space:]]*//p' dns-manager-luci.sh | head -n1)"
installer_luci="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' dns-manager-luci.sh | head -n1)"
self_luci="$(sed -n 's/^SELF_VERSION="\([^"]*\)"$/\1/p' dns-manager-luci.sh | head -n1)"
view_luci="$(sed -n 's|^// DNS Manager LuCI version:[[:space:]]*||p' "$tmp/overview.js" | head -n1)"
[ -n "$top_luci" ] || fail "LuCI top version missing"
[ "$top_luci" = "$installer_luci" ] || fail "LuCI VERSION mismatch"
[ "$top_luci" = "$self_luci" ] || fail "LuCI SELF_VERSION mismatch"
[ "$top_luci" = "$view_luci" ] || fail "embedded JS version mismatch"
ok "LuCI version markers synchronized ($top_luci)"

if awk '
    /function startAutoStatus\(root\)/ { capture=1 }
    capture { print }
    capture && /^}/ { exit }
' "$tmp/overview.js" | grep -q 'refreshDashboard'; then
    fail "startAutoStatus still performs a full dashboard refresh"
fi
if grep -q 'function refreshDashboard' "$tmp/overview.js"; then
    fail "obsolete refreshDashboard function remains"
fi
ok "dashboard timer is lightweight"

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
    steer_luci_case 'table inet test { chain prerouting { iifname "br-lan" udp dport 53 counter redirect to :5300 } }' 0 0
)
ok "LuCI Steer detection matches LAN/runtime contract"

grep -q '"steer_installed"' "$tmp/backend.sh" || fail "Steer installed status missing from RPC"
grep -q '"steer_running"' "$tmp/backend.sh" || fail "Steer running status missing from RPC"
grep -q '"steer_dns_active"' "$tmp/backend.sh" || fail "Steer DNS runtime status missing from RPC"
ok "Steer status fields exposed"

awk '
    /^local_slot_test_one\(\) \{/ { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
' dns-manager-luci.sh > "$tmp/local_slot_test_fn.sh"
[ -s "$tmp/local_slot_test_fn.sh" ] || fail "local slot test extraction"
grep -q 'command -v nslookup' "$tmp/local_slot_test_fn.sh" || fail "nslookup primary checker missing"
grep -Fq 'nslookup -port="$_port" "$_domain" 127.0.0.1' "$tmp/local_slot_test_fn.sh" || fail "local slot nslookup port/host contract missing"
grep -q '_answer="$(awk' "$tmp/local_slot_test_fn.sh" || fail "real DNS answer parser missing"
grep -Fq '/^Name:[[:space:]]/' "$tmp/local_slot_test_fn.sh" || fail "DNS answer parser does not require Name section"
grep -q 'LOCAL_DNS_NO_ANSWER' "$tmp/local_slot_test_fn.sh" || fail "empty-answer classification missing"
grep -q 'LOCAL_DNS_SERVFAIL' "$tmp/local_slot_test_fn.sh" || fail "SERVFAIL classification missing"
grep -q 'LOCAL_DNS_NXDOMAIN' "$tmp/local_slot_test_fn.sh" || fail "NXDOMAIN classification missing"
if grep -Fq 'grep -Eq "(^|[[:space:]])Name:[[:space:]]|^Address[[:space:]]|^Server:"' "$tmp/local_slot_test_fn.sh"; then
    fail "local slot test still accepts generic Server/Address lines"
fi
ok "LuCI local slot checks require a real DNS A answer"

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
printf '%s\n' "All DNS Manager regression checks passed."
