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

# DNS response validation intentionally stays lightweight: HTTP 200 + DNS message body.
awk '
    /^validate_dns_message\(\) \{/ { capture=1 }
    capture { print }
    capture && /^}$/ { exit }
' dns-manager.sh > "$tmp/validate_dns.sh"
[ -s "$tmp/validate_dns.sh" ] || fail "DNS response validator extraction"
. "$tmp/validate_dns.sh"

printf '\000\000\000\000\000\001\000\000\000\000\000' > "$tmp/dns-short"
if validate_dns_message "$tmp/dns-short"; then
    fail "short DNS body accepted"
fi

printf '\000\000\000\000\000\001\000\000\000\000\000\000abcdefghijkl' > "$tmp/dns-body"
validate_dns_message "$tmp/dns-body" || fail "normal-sized DNS body rejected"

ok "DNS response validation remains lightweight"
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

grep -q '^restore_dns_core() {' dns-manager.sh || fail "DNS core restore helper missing"
awk '/^menu_slots() {/,/^menu_bogus() {/' dns-manager.sh > "$tmp/menu_slots.sh"
if grep -q 'hybrid_set_defaults\|CORE_ONLY=1; apply_settings\|CORE_ONLY=1' "$tmp/menu_slots.sh"; then
    fail "DNS menu restore still selects/applies a DNS profile"
fi
grep -q 'reset_dns)' "$tmp/backend.sh" || fail "LuCI DNS reset RPC missing"
grep -q 'reset_dns' "$tmp/overview.js" || fail "LuCI DNS reset action missing"
ok "DNS restore returns to standard resolver path"

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
grep -q 'Подготавливаю окружение' dns-manager.sh || fail "startup progress: environment marker missing"
grep -q 'Проверяю каталог DNS' dns-manager.sh || fail "startup progress: catalog marker missing"
grep -q 'Проверяю обновления' dns-manager.sh || fail "startup progress: update marker missing"
grep -q 'Проверяю состояние роутера' dns-manager.sh || fail "startup progress: discovery marker missing"
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

grep -q 'test_one_dns "\$_id"' "$tmp/backend.sh" || fail "LuCI selected DNS check does not use the manager test"
grep -q 'test_one_dns "\$_id" || true' "$tmp/backend.sh" || fail "LuCI single DNS check is not using the direct manager test"
if grep -q '\$MANAGER --test-one' "$tmp/backend.sh"; then
    fail "LuCI single DNS check still spawns a separate manager test process"
fi
grep -q 'result_for_id "\$_id"' "$tmp/backend.sh" || fail "selected DNS status does not use the authoritative result file"
if grep -q 'CURRENT_SLOT_RESULTS' "$tmp/backend.sh"; then
    fail "obsolete second DNS result store remains"
fi
if grep -q '^current_slot_result_for_id()' "$tmp/backend.sh"; then
    ok "selected DNS status has a single authoritative result helper"
fi
if grep -q '^assigned_port_for_id()' dns-manager-luci.sh; then
    fail "obsolete assigned-port helper remains"
fi
grep -Fq -- '--connect-timeout 1 --max-time 3 --resolve "$host:$port:$ipx"' dns-manager.sh || fail "direct DoH timeout was not reduced"
grep -q '(trap - EXIT; test_one_dns "\$_id") &' "$tmp/backend.sh" || fail "selected DNS checks are not parallelized"
ok "single and full DNS checks use the same test_one_dns path"

grep -q ',"ping":' "$tmp/backend.sh" || fail "LuCI DoH instances do not expose saved ping"
grep -q ',"status":' "$tmp/backend.sh" || fail "LuCI DoH instances do not expose saved test status"
grep -q "badge('dm-ok','работает')" "$tmp/overview.js" || fail "LuCI does not show DNS test state as работает"
grep -q "badge('dm-bad','не работает')" "$tmp/overview.js" || fail "LuCI does not show failed DNS test state as не работает"
grep -q "badge('dm-off','не проверено')" "$tmp/overview.js" || fail "LuCI does not distinguish an untested DNS"
if grep -q "dm-doh-state.*запущен" "$tmp/overview.js"; then
    fail "LuCI DoH rows still expose process state as пользовательский DNS status"
fi
if grep -q "dm-doh-state.*остановлен" "$tmp/overview.js"; then
    fail "LuCI DoH rows still expose process stop state instead of test state"
fi
grep -q "hasPing(ci.ping)" "$tmp/overview.js" || fail "LuCI does not render DNS test ping"
grep -q "'dm-doh-ping'" "$tmp/overview.js" || fail "LuCI DoH page does not render DNS test ping"
ok "LuCI DoH rows use test result status and ping"

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
grep -A12 -F 'watchdog_pick_replacement() {' dns-manager.sh | grep -q 'watchdog_scope_category' || fail "watchdog replacement does not use intended profile category"
grep -A18 -F 'watchdog_pick_replacement() {' dns-manager.sh | grep -q '_passcats="\$_desired_for_pick clean"' || fail "watchdog clean fallback is missing for non-clean profiles"
grep -A16 -F 'watchdog_slot_target_run() {' dns-manager.sh | grep -q 'watchdog_scope_category' || fail "watchdog slot repair does not use intended profile category"
grep -q 'смешанные или пользовательские категории DNS' dns-manager.sh || fail "watchdog custom/mixed skip message missing"
ok "manual same-category DNS changes preserve profile; mixed/custom selections disable DNS watchdog scope"

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
grep -A22 -F 'watchdog_pick_replacement() {' dns-manager.sh | grep -q '_passcats="$_desired_for_pick clean"' || fail "clean fallback is not available for every non-clean profile"
grep -A18 -F 'watchdog_pick_replacement() {' dns-manager.sh | grep -q 'watchdog_scope_category' || fail "watchdog replacement does not use intended profile category"
grep -q '_fallback_slots=""' dns-manager.sh || fail "watchdog fallback slots are not tracked"
grep -q '_empty_slots=""' dns-manager.sh || fail "watchdog empty slots are not tracked"
grep -q 'Watchdog: проверяю целевую категорию для восстановления/дозаполнения' dns-manager.sh || fail "watchdog gradual target restore/fill path missing"
grep -A8 '^auto_fill_slots() {' dns-manager.sh | grep -q 'ensure_test_results_fresh' || fail "profile selection does not use fresh full results"
if grep -q 'profile_fill_slots' dns-manager.sh; then
    fail "obsolete bounded profile picker remains"
fi
if grep -q 'PROFILE_FRESH_OK_IDS' dns-manager.sh; then
    fail "obsolete per-profile fresh DNS list remains"
fi

awk '/^quick_max_bypass\(\)/,/^dependency_preflight\(\)/' dns-manager.sh > "$tmp/quick_profile_block.sh"
grep -Fq 'if [ "${PROFILE_FULL_TEST:-0}" = 1 ]; then' "$tmp/quick_profile_block.sh" || fail "quick bypass profile does not reuse the fresh full test"
grep -Fq 'Использую только что завершённую полную проверку DNS.' "$tmp/quick_profile_block.sh" || fail "quick bypass profile does not report the fresh full test"
ok "ready-made profiles always refresh the complete DNS catalog before selection"

# Profile application validation must use the fresh full-catalog results.
awk '/^validate_selected_slots\(\)/,/^ensure_dnsmasq_balancer\(\)/' dns-manager.sh > "$tmp/validate_selected_slots.sh"
grep -q 'ensure_test_results_fresh || return 1' "$tmp/validate_selected_slots.sh" || fail "profile validation does not require fresh full results"
grep -q 'последнюю полную проверку' "$tmp/validate_selected_slots.sh" || fail "profile validation message does not refer to full test results"
if grep -q 'PROFILE_FRESH_OK_IDS' "$tmp/validate_selected_slots.sh"; then
    fail "profile validation still uses temporary candidate list"
fi
grep -q 'PROFILE_FULL_TEST=0' dns-manager.sh || fail "profile full-test flag cleanup missing"
grep -q 'Проверяю весь список DNS — проверено' "$tmp/overview.js" || fail "LuCI profile progress does not show full catalog checking"
grep -q 'Выбираю DNS из свежих результатов' "$tmp/overview.js" || fail "LuCI profile progress does not label fresh-result selection"
grep -q 'localProfileRunning=!!(state.busy&&state.profileProgress)' "$tmp/overview.js" || fail "LuCI does not suppress stale profile result while retrying"
ok "profile apply validates only against the fresh full-catalog results"
 
# Completed profile jobs survive a LuCI page reload and expose the actual reason for failure.
grep -q 'profile_job_status' "$tmp/backend.sh" || fail "persistent profile job status missing"
grep -q 'profile_job_result' "$tmp/backend.sh" || fail "persistent profile job result missing"
grep -q 'profile_job_message' "$tmp/backend.sh" || fail "persistent profile job message missing"
grep -q '"profile_job_status"' "$tmp/backend.sh" || fail "profile job status is not returned by status JSON"
grep -q '"profile_job_message"' "$tmp/backend.sh" || fail "profile job message is not returned by status JSON"
grep -q 'Последняя операция: профиль' "$tmp/overview.js" || fail "LuCI does not show the last profile operation after reopen"
grep -q 'Причина:' "$tmp/overview.js" || fail "LuCI does not show the profile failure reason"
grep -q 'Закрытие LuCI не останавливает операцию' "$tmp/overview.js" || fail "LuCI does not explain persistent running profile jobs"
grep -Fq "setAction(true,p?'Профиль «'+profileName(p)+'» уже применяется. Связь восстановлена.':'Применение профиля уже выполняется. Связь восстановлена.','running')" "$tmp/overview.js" || fail "running profile resume is not labeled as running"
ok "LuCI persists profile operation state across page reloads"

# LuCI must also expose the most recent long-running DNS check after a page reload.
grep -q 'last_job_status' "$tmp/backend.sh" || fail "generic last job status missing"
grep -q '"last_job_status"' "$tmp/backend.sh" || fail "generic last job status is not returned by status JSON"
grep -q '"last_job_mode"' "$tmp/backend.sh" || fail "generic last job mode is not returned by status JSON"
grep -q 'Полная проверка каталога DNS' "$tmp/overview.js" || fail "LuCI does not label persisted full DNS checks"
grep -q 'Проверка DNS в слотах' "$tmp/overview.js" || fail "LuCI does not label persisted selected-DNS checks"
grep -q 'Проверка DNS «' "$tmp/overview.js" || fail "LuCI does not label persisted single-DNS checks"
grep -q 'Фоновая задача DNS Manager' "$tmp/overview.js" || fail "LuCI does not have generic persisted operation fallback"
ok "LuCI shows the latest DNS background operation after reload"

# Watchdog tuning is persisted and exposed as one atomic LuCI save operation.
for _wd_key in WATCHDOG_INTERVAL WATCHDOG_FAIL_THRESHOLD WATCHDOG_REPAIR_COOLDOWN WATCHDOG_MAX_REPAIRS WATCHDOG_MAX_RESTARTS WATCHDOG_MAX_CANDIDATES WATCHDOG_GUARD_INTERVAL; do
    grep -q "^${_wd_key}=" dns-manager.sh || fail "watchdog config variable missing: $_wd_key"
done
grep -q 'WATCHDOG_FAIL_THRESHOLD="$WATCHDOG_FAIL_THRESHOLD"' dns-manager.sh || fail "watchdog threshold is not persisted"
grep -q 'WATCHDOG_REPAIR_COOLDOWN="$WATCHDOG_REPAIR_COOLDOWN"' dns-manager.sh || fail "watchdog repair cooldown is not persisted"
grep -q 'WATCHDOG_MAX_REPAIRS="$WATCHDOG_MAX_REPAIRS"' dns-manager.sh || fail "watchdog max repairs is not persisted"
grep -q 'WATCHDOG_MAX_RESTARTS="$WATCHDOG_MAX_RESTARTS"' dns-manager.sh || fail "watchdog max restarts is not persisted"
grep -q 'WATCHDOG_MAX_CANDIDATES="$WATCHDOG_MAX_CANDIDATES"' dns-manager.sh || fail "watchdog max candidates is not persisted"
grep -q 'WATCHDOG_GUARD_INTERVAL="$WATCHDOG_GUARD_INTERVAL"' dns-manager.sh || fail "watchdog guard interval is not persisted"

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
grep -Fq 'watchdog_apply_values "$_interval" "$_threshold" "$_repair_cooldown" "$_max_repairs" "$_max_restarts" "$_max_candidates" "$_guard_interval"' "$tmp/backend.sh" || fail "batch watchdog values are not forwarded together"

grep -q "method:'set_watchdog_settings'" "$tmp/overview.js" || fail "LuCI does not use the atomic watchdog RPC"
grep -Fq "params:['interval','threshold','repair_cooldown','max_repairs','max_restarts','max_candidates','guard_interval']" "$tmp/overview.js" || fail "atomic watchdog RPC parameter order mismatch"
if grep -q 'var callWatchdogSetting = ' "$tmp/overview.js"; then
    fail "LuCI still defines the per-setting watchdog RPC"
fi
awk '/^function watchdogCard\(root,st\)\{/,/^function renderTestAgeCommon/' "$tmp/overview.js" > "$tmp/watchdog_card.js"
save_count="$(grep -o 'Сохранить' "$tmp/watchdog_card.js" | wc -l | tr -d ' ')"
[ "$save_count" = 1 ] || fail "watchdog must have exactly one Save label"
grep -q 'Сохранить настройки' "$tmp/watchdog_card.js" || fail "common watchdog save button missing"
grep -q 'Дополнительные параметры' "$tmp/watchdog_card.js" || fail "advanced watchdog section missing"
grep -q 'Настройки контроля' "$tmp/watchdog_card.js" || fail "watchdog settings section title missing"
for _wd_label in 'Интервал проверки' 'Порог сбоя' 'Пауза между ремонтами' 'Ремонтов за цикл' 'Кандидатов за выбор' 'Перезапусков DNS' 'Полная сверка'; do
    grep -q "$_wd_label" "$tmp/watchdog_card.js" || fail "LuCI watchdog control missing: $_wd_label"
done
if grep -q 'Рестартов https-dns-proxy\|Тяжёлая сверка' "$tmp/watchdog_card.js"; then
    fail "technical watchdog labels still exposed in LuCI"
fi
ok "watchdog tuning is persisted through one atomic RPC and exposed as a compact LuCI form"

# The legacy single-setting RPC remains available for older clients, but shares the same apply path.
grep -q 'watchdog_apply_single' "$tmp/backend.sh" || fail "legacy watchdog setter does not use shared apply logic"
grep -q 'watchdog_apply_batch' "$tmp/backend.sh" || fail "batch watchdog setter helper missing"
ok "legacy watchdog RPC compatibility is preserved"
printf '%s\n' "All DNS Manager regression checks passed."
