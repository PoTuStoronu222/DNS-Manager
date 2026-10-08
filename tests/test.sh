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
grep -Fq '    auto_update_manager || true' dns-manager.sh || fail "startup update check still redirects self-reexec output"
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

grep -q "Проверить текущие DNS" "$tmp/overview.js" || fail "LuCI common current-DNS check button missing"
if grep -q "Проверить DNS в слотах" "$tmp/overview.js" || grep -q "Проверить системные DNS" "$tmp/overview.js"; then
    fail "LuCI still exposes separate slot/system DNS check buttons"
fi
grep -q "var systems=targets.filter(function(d){return d&&!d.slot&&d.url&&d.port;});" "$tmp/overview.js" || fail "LuCI current-DNS check does not classify unassigned system resolvers"
grep -q "callTestSystem().then" "$tmp/overview.js" || fail "LuCI common current-DNS check does not include system DNS"
ok "LuCI current-DNS check covers slots and system resolvers with one button"

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
awk '/^function renderActionStatus\(\)\{/,/^}/ { print }' "$tmp/overview.js" > "$tmp/render_action_status.js"
grep -q 'state.lastAction' "$tmp/render_action_status.js" || fail "action strip no longer uses current-page action state"
if grep -q 'last_job_status\|last_job_result\|last_job_message' "$tmp/render_action_status.js"; then
    fail "action strip still promotes persistent job history to a global banner"
fi
grep -q 'if(state.activeTab!==nextTab)state.lastAction=null;' "$tmp/overview.js" || fail "tab navigation does not clear stale action strip"
ok "global action banner does not persist across pages"
ok "LuCI RPC dispatch contract"
# Every asynchronous DNS test must record the PID of the process it started.
# job_process_alive() relies on this PID; without it a valid job is immediately
# reported as having no working PID.
awk '/^job_start_test_all\(\) \{/,/^job_start_test_current\(\) \{/' "$tmp/backend.sh" | grep -q '_job_pid=\$!' || fail "test_all job PID is not recorded"
awk '/^job_start_test_all\(\) \{/,/^job_start_test_current\(\) \{/' "$tmp/backend.sh" | grep -q 'job_record_pid "\$_jid" "\$_job_pid"' || fail "test_all job PID is not registered"
awk '/^job_start_test_current\(\) \{/,/^job_start_test_one\(\) \{/' "$tmp/backend.sh" | grep -q '_job_pid=\$!' || fail "test_current job PID is not recorded"
awk '/^job_start_test_current\(\) \{/,/^job_start_test_one\(\) \{/' "$tmp/backend.sh" | grep -q 'job_record_pid "\$_jid" "\$_job_pid"' || fail "test_current job PID is not registered"
awk '/^job_start_test_one\(\) \{/,/^job_json\(\) \{/' "$tmp/backend.sh" | grep -q '_job_pid=\$!' || fail "test_one job PID is not recorded"
awk '/^job_start_test_one\(\) \{/,/^job_json\(\) \{/' "$tmp/backend.sh" | grep -q 'job_record_pid "\$_jid" "\$_job_pid"' || fail "test_one job PID is not registered"
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
grep -q 'function ntpActualPreset(servers)' "$tmp/overview.js" || fail "LuCI NTP actual-state detector missing"
grep -q "preset=ntpActualPreset(servers)" "$tmp/overview.js" || fail "LuCI NTP page still trusts stored preset instead of actual servers"
grep -q "openwrt_default:'Стандарт OpenWrt'" "$tmp/overview.js" || fail "LuCI does not label OpenWrt default NTP servers"
grep -q "other:'ДРУГОЕ'" "$tmp/overview.js" || fail "LuCI does not label unknown NTP servers as other"
grep -q "st.force_owner==='steer'&&st.force_status==='other'" "$tmp/overview.js" || fail "LuCI components do not show Steer-owned forced-DNS state"
grep -q "ДРУГОЕ • Steer" "$tmp/overview.js" || fail "LuCI components do not show Steer status label"
awk '/^function renderTime\(root,st\)\{/,/^function renderCatalog\(root\)/' "$tmp/overview.js" > "$tmp/ntp_view.js"
if grep -q "row('Служба'" "$tmp/ntp_view.js"; then
    fail "LuCI NTP page still exposes service status"
fi
grep -q "row('Выбранный набор'" "$tmp/ntp_view.js" || fail "LuCI NTP page lost selected preset"
ok "NTP status follows actual OpenWrt system.ntp.server configuration"
# Watchdog time controls are shown to users in minutes, while the RPC still receives seconds.
awk '/^function watchdogCard\(root,st\)\{/,/^function renderTestAgeCommon/' "$tmp/overview.js" > "$tmp/watchdog_card.sh"
grep -q "Как часто проверять DNS" "$tmp/watchdog_card.sh" || fail "watchdog interval label is not user-friendly"
grep -q "Сколько проверок подряд считать сбоем" "$tmp/watchdog_card.sh" || fail "watchdog failure threshold label is not user-friendly"
grep -q "Пауза между заменами DNS" "$tmp/watchdog_card.sh" || fail "watchdog repair cooldown label is not user-friendly"
grep -q "1,60,'мин'" "$tmp/watchdog_card.sh" || fail "watchdog interval range is not practical"
grep -q "5,120,'мин'" "$tmp/watchdog_card.sh" || fail "watchdog repair cooldown range is not practical"
grep -q "'step':minutes?'1':'1'" "$tmp/watchdog_card.sh" || fail "watchdog minute fields must use whole minutes"
grep -q "Math.round(n\*60)" "$tmp/watchdog_card.sh" || fail "watchdog minute values are not converted back to seconds"
grep -q "minuteValue(st\[name\],min)" "$tmp/watchdog_card.sh" || fail "watchdog stored seconds are not converted to displayed minutes"
grep -q "Сколько DNS можно заменить за раз" "$tmp/watchdog_card.sh" || fail "watchdog repair-count label is not user-friendly"
grep -q "Сколько DNS проверить при поиске замены" "$tmp/watchdog_card.sh" || fail "watchdog candidate-count label is not user-friendly"
if grep -q "Сколько раз можно перезапустить DNS" "$tmp/watchdog_card.sh"; then
    fail "internal watchdog restart limit is still exposed in LuCI"
fi
grep -q "values.splice(4,0,Math.round(internalMaxRestarts))" "$tmp/watchdog_card.sh" || fail "internal watchdog restart limit is not preserved when saving"
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
grep -q 'WATCHDOG_CHECK_INTERVAL_DEFAULT=600' dns-manager.sh || fail "watchdog default interval is not 10 minutes"
grep -q 'WATCHDOG_REPAIR_COOLDOWN=1800' dns-manager.sh || fail "watchdog default repair cooldown is not 30 minutes"
grep -q 'WATCHDOG_GUARD_INTERVAL=3600' dns-manager.sh || fail "internal watchdog guard default is not 60 minutes"
grep -q '\[ "\$_ni" -ge 60 \].*\[ "\$_ni" -le 3600 \]' "$tmp/backend.sh" || fail "watchdog backend interval range is not 1-60 minutes"
grep -q '\[ "\$_nrc" -ge 300 \].*\[ "\$_nrc" -le 7200 \]' "$tmp/backend.sh" || fail "watchdog backend repair cooldown range is not 5-120 minutes"
ok "watchdog defaults and backend ranges match the practical minute-based UI"

grep -q '^restore_dns_core() {' dns-manager.sh || fail "DNS core restore helper missing"
awk '/^menu_slots() {/,/^menu_bogus() {/' dns-manager.sh > "$tmp/menu_slots.sh"
if grep -q 'hybrid_set_defaults\|CORE_ONLY=1; apply_settings\|CORE_ONLY=1' "$tmp/menu_slots.sh"; then
    fail "DNS menu restore still selects/applies a DNS profile"
fi
grep -q 'reset_dns)' "$tmp/backend.sh" || fail "LuCI DNS reset RPC missing"
grep -q 'reset_dns' "$tmp/overview.js" || fail "LuCI DNS reset action missing"
grep -q 'rollback_hdp_targeted' dns-manager.sh || fail "Targeted DoH cleanup missing"
grep -q 'package_owner_remove_owned' dns-manager.sh || fail "Owned package cleanup missing"
if grep -q 'BASELINE_DIR\|BASELINE_MANIFEST\|BASELINE_LAST\|BASELINE_META\|baseline_restore_for_uninstall\|baseline_uninstall_validate\|baseline_capture_once\|baseline_mark_applied\|ensure_baseline_captured' dns-manager.sh; then fail "Obsolete persistent baseline logic remains"; fi
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
ok "single and full DNS checks use the same test_one_dns path"
awk '/^function checkInfo\(id,d\)/,/^}/' "$tmp/overview.js" > "$tmp/check_info.js"
grep -q "String(x.status||'').toUpperCase()==='RUNNING'" "$tmp/check_info.js" || fail "LuCI transient check state is not limited to RUNNING"
grep -q "d&&d.status" "$tmp/check_info.js" || fail "LuCI finished DNS status does not come from RPC data"
if grep -q "state.checking\[meta.dns_id\]={" "$tmp/overview.js"; then
    fail "LuCI stores a finished single-test result in transient state"
fi
grep -q "delete state.checking\[meta.dns_id\]" "$tmp/overview.js" || fail "LuCI does not clear the transient single-test state"
ok "LuCI uses the RPC result for every finished single DNS check"

awk '/^function finish\(j\) \{/,/^  function poll\(\)\{/' "$tmp/overview.js" > "$tmp/poll_finish.js"
if grep -q "callTestCurrent().then" "$tmp/poll_finish.js"; then
    fail "LuCI still launches a second DNS test after profile apply"
fi
if grep -q "afterProfile" "$tmp/overview.js"; then
    fail "obsolete after-profile DNS verification path remains"
fi
grep -q "Профиль применён.','" "$tmp/overview.js" || true
ok "profile apply does not rerun the selected DNS test"



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
awk '/^function forceComponentItem\(st\)\{/,/^function watchdogComponentItem/' "$tmp/overview.js" > "$tmp/force_component.js"
if grep -q "setSetting('force'" "$tmp/force_component.js"; then
    fail "LuCI forced-DNS component must remain state-only"
fi
if grep -q "actionText\|actionButton\|dm-seg" "$tmp/force_component.js"; then
    fail "LuCI forced-DNS component exposes action controls"
fi
grep -q "owner==='steer'&&mode==='other'" "$tmp/force_component.js" || fail "LuCI forced-DNS component does not handle Steer-owned state"
grep -q "ДРУГОЕ • Steer" "$tmp/force_component.js" || fail "LuCI forced-DNS component lost Steer status label"
grep -q "componentItem('Принудительный DNS для устройств'" "$tmp/force_component.js" || fail "LuCI overview does not render dedicated forced-DNS component"
awk '/^function renderDoH\(root,st\)\{/,/^function slotLabel/' "$tmp/overview.js" > "$tmp/doh_panel.js"
grep -q "setForceMode('auto',root)" "$tmp/doh_panel.js" || fail "LuCI DoH page has no force-DNS auto action"
grep -q "setForceMode('off',root)" "$tmp/doh_panel.js" || fail "LuCI DoH page has no force-DNS disable action"
grep -q "Авто (рекомендуется)" "$tmp/doh_panel.js" || fail "LuCI DoH page lost force-DNS auto label"
grep -q "Не перехватывать" "$tmp/doh_panel.js" || fail "LuCI DoH page lost force-DNS disable label"
ok "LuCI forced-DNS component is state-only; controls live in the DoH page"

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
awk '
    /^watchdog_pick_replacement\(\) \{/ { capture=1 }
    capture { print }
    capture && /^watchdog_apply_slot_candidate\(\) \{/ { exit }
' dns-manager.sh | sed '$d' > "$tmp/watchdog_pick_function.sh"
grep -q 'watchdog_scope_category' "$tmp/watchdog_pick_function.sh" || fail "watchdog replacement does not use intended profile category"
grep -q '_passcats="\$_desired_for_pick clean"' "$tmp/watchdog_pick_function.sh" || fail "watchdog clean fallback is missing for non-clean profiles"
grep -A16 -F 'watchdog_slot_target_run() {' dns-manager.sh | grep -q 'watchdog_scope_category' || fail "watchdog slot repair does not use intended profile category"
grep -q 'смешанные или пользовательские категории DNS' dns-manager.sh || fail "watchdog custom/mixed skip message missing"
ok "manual same-category DNS changes preserve profile; mixed/custom selections disable DNS watchdog scope"
# All watchdog paths must use the same DNS health checks as the verified Manager paths.
awk '/^watchdog_embedded_loop\(\) \{/,/^# ==========================================/' dns-manager.sh > "$tmp/watchdog_embedded_loop.sh"
grep -q 'local_dns_query_ok "\$_port" "\$_domain"' "$tmp/watchdog_embedded_loop.sh" || fail "procd watchdog does not use the canonical local DNS check"
if grep -q 'watchdog_light_probe' dns-manager.sh; then
    fail "obsolete simplified watchdog DNS probe remains"
fi
awk '/^watchdog_probe_catalog_candidate\(\) \{/,/^watchdog_pick_replacement\(\) \{/' dns-manager.sh > "$tmp/watchdog_candidate_probe.sh"
grep -q 'test_one_dns "\$_id"' "$tmp/watchdog_candidate_probe.sh" || fail "watchdog candidate probe does not use canonical DoH test"
if grep -q 'curl ' "$tmp/watchdog_candidate_probe.sh"; then
    fail "watchdog candidate probe duplicates the canonical curl test"
fi
awk '/^watchdog_service_install_files\(\) \{/,/^watchdog_service_running\(\) \{/' dns-manager.sh > "$tmp/watchdog_service.sh"
grep -q 'USE_PROCD=1' "$tmp/watchdog_service.sh" || fail "watchdog service is not managed by procd"
grep -q 'procd_set_param command /bin/sh "\$PROG" "\$CMD"' "$tmp/watchdog_service.sh" || fail "watchdog procd command is missing"
grep -q 'procd_set_param respawn 3600 5 5' "$tmp/watchdog_service.sh" || fail "watchdog procd respawn is missing"
grep -q 'procd_add_interface_trigger "interface.*.up" "\$wan" /etc/init.d/dns-watchdog restart' "$tmp/watchdog_service.sh" || fail "watchdog WAN-up trigger is missing"
if [ "$(grep -c 'watchdog_cron_desired_line' dns-manager.sh)" -ne 1 ]; then
    fail "legacy watchdog cron scheduler is still referenced outside its unused definition"
fi
ok "watchdog uses the same DNS check logic; procd is the active scheduler and cron is legacy-only"

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
awk '
    /^watchdog_pick_replacement\(\) \{/ { capture=1 }
    capture { print }
    capture && /^watchdog_apply_slot_candidate\(\) \{/ { exit }
' dns-manager.sh > "$tmp/watchdog_pick_function.sh"
grep -q '_passcats="$_desired_for_pick clean"' "$tmp/watchdog_pick_function.sh" || fail "clean fallback is not available for every non-clean profile"
grep -A18 -F 'watchdog_pick_replacement() {' dns-manager.sh | grep -q 'watchdog_scope_category' || fail "watchdog replacement does not use intended profile category"
grep -q '_fallback_slots=""' dns-manager.sh || fail "watchdog fallback slots are not tracked"
grep -q '_empty_slots=""' dns-manager.sh || fail "watchdog empty slots are not tracked"
grep -q 'Watchdog: проверяю целевую категорию для восстановления/дозаполнения' dns-manager.sh || fail "watchdog gradual target restore/fill path missing"
grep -q '^auto_fill_slots() {' dns-manager.sh || fail "automatic profile DNS selection helper missing"
if grep -q 'profile_fill_slots' dns-manager.sh; then
    fail "obsolete bounded profile picker remains"
fi
if grep -q 'PROFILE_FRESH_OK_IDS' dns-manager.sh; then
    fail "obsolete per-profile fresh DNS list remains"
fi
awk '/^job_start_test_all\(\) \{/,/^\}/' "$tmp/backend.sh" > "$tmp/test_all_job.sh"
grep -Fq 'job_write "$_jid" progress_done "$_final_total"' "$tmp/test_all_job.sh" || fail "LuCI full catalog job does not publish final progress_done"
grep -Fq 'job_write "$_jid" progress_total "$_final_total"' "$tmp/test_all_job.sh" || fail "LuCI full catalog job does not publish final progress_total"
grep -Fq 'job_write "$_jid" progress_ok "$_final_ok"' "$tmp/test_all_job.sh" || fail "LuCI full catalog job does not publish final progress_ok"
grep -Fq 'job_write "$_jid" progress_fail "$_final_fail"' "$tmp/test_all_job.sh" || fail "LuCI full catalog job does not publish final progress_fail"
ok "LuCI full catalog job publishes final progress before DONE"

grep -q "profileSelected=String(st.profile||'none')!=='none'" "$tmp/overview.js" || fail "LuCI does not detect missing DNS Manager profile"
grep -q "Сначала выберите профиль DNS Manager" "$tmp/overview.js" || fail "LuCI missing no-profile reason"
grep -q "function watchdogComponentItem" "$tmp/overview.js" || fail "LuCI watchdog component state helper missing"
awk '/^function watchdogComponentItem\(/,/^}/' "$tmp/overview.js" | grep -qE 'btn\(|setSetting\(' && fail "LuCI components block still contains a watchdog action button"
grep -q "function forceComponentItem" "$tmp/overview.js" || fail "LuCI forced-DNS component state helper missing"
awk '/^function forceComponentItem\(/,/^}/' "$tmp/overview.js" | grep -qE 'btn\(|setSetting\(' && fail "LuCI components block still contains a forced-DNS action button"
grep -Fq "watchdogComponentItem(st,wd,wdDetails)" "$tmp/overview.js" || fail "LuCI watchdog component helper is not used as a state-only item"
grep -Fq "forceComponentItem(st)" "$tmp/overview.js" || fail "LuCI forced-DNS component helper is not used as a state-only item"
grep -Fq 'if [ "$_module" = watchdog ] && [ "$_new" = 1 ]; then' dns-manager.sh || fail "CLI watchdog no-profile guard missing"
grep -Fq 'if [ "$_enabled" = 1 ] && [ -z "$SLOT_1$SLOT_2$SLOT_3$SLOT_4$SLOT_5$SLOT_6$SLOT_RU" ]; then' "$tmp/backend.sh" || fail "RPC watchdog no-profile guard missing"
grep -q "Проверить текущие DNS','cbi-button-action'" "$tmp/overview.js" || fail "Current DNS check button disappeared"
if grep -q "canTestCurrent=profileSelected" "$tmp/overview.js"; then fail "Current DNS check is incorrectly blocked without profile"; fi
if grep -q "_profile_slots.*Проверить текущие DNS" "$tmp/backend.sh"; then fail "Current DNS check is incorrectly guarded by profile"; fi
ok "DNS control is blocked without profile; current DNS checks remain available"

grep -q 'test_dns_catalog "\$1"' dns-manager.sh || fail "profile apply does not pass its category to the DNS test"
grep -q 'test_scope=' dns-manager.sh || fail "DNS test scope is not persisted"
grep -q 'ensure_test_results_fresh "\$_cat"' dns-manager.sh || fail "category selector does not request category-scoped freshness"
grep -q 'test_dns_catalog "$1"' dns-manager.sh || fail "profile apply does not start a category-scoped DNS test"
grep -q '($2==c || $2=="regional")' dns-manager.sh || fail "category-scoped test does not include the regional DNS set"
grep -Fq '_test_scope="${1:-all}"' dns-manager.sh || fail "DNS test scope argument missing"
grep -q 'last_full_test_scope' "$tmp/backend.sh" || fail "LuCI status does not expose DNS test scope"
grep -q 'last_full_test_scope' "$tmp/overview.js" || fail "LuCI header does not show DNS test scope"
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
grep -q 'Проверяю DNS выбранного профиля — проверено' "$tmp/overview.js" || fail "LuCI profile progress does not show category-scoped DNS checking progress"
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

# The global action banner is transient; persisted job history is not promoted into that banner.
# Detailed operation state remains available through the dedicated job/profile paths.
ok "LuCI does not require persisted DNS job history for global status banners"

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
grep -q 'watchdog_interval":%s,"watchdog_service' "$tmp/backend.sh" || fail "LuCI status does not expose saved watchdog interval"

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
for _wd_label in 'Как часто проверять DNS' 'Сколько проверок подряд считать сбоем' 'Пауза между заменами DNS' 'Сколько DNS можно заменить за раз' 'Сколько DNS проверить при поиске замены'; do
    grep -q "$_wd_label" "$tmp/watchdog_card.js" || fail "LuCI watchdog control missing: $_wd_label"
done
if grep -q 'Рестартов https-dns-proxy\|Тяжёлая сверка' "$tmp/watchdog_card.js"; then
    fail "technical watchdog labels still exposed in LuCI"
fi
# Numeric watchdog fields must use a single-escaped digit regex; double-escaped \\d rejects normal values.
grep -Fq '(x[6]?true:/^\d+$/.test(raw))' "$tmp/watchdog_card.js" || fail "watchdog numeric validation regex is missing"
if grep -Fq '(x[6]?true:/^\\d+$/.test(raw))' "$tmp/watchdog_card.js"; then
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


printf '%s\n' "All DNS Manager regression checks passed."
