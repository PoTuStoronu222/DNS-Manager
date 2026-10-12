#!/bin/sh
# Regression tests for DNS Manager uninstall without a baseline backup.
# Platform-facing UCI and init-service calls are replaced with isolated mocks.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; return 1; }
ok() { printf 'OK: %s\n' "$*"; }
extract_function() {
    _fn="$1"; _out="$2"
    awk -v fn="$_fn" '$0 == fn "() {" {capture=1} capture {print} capture && /^}$/ {exit}' "$ROOT/dns-manager.sh" > "$_out"
    [ -s "$_out" ]
}
mock_uci() {
    [ "${1:-}" = "-q" ] && shift
    _cmd="${1:-}"; [ "$#" -gt 0 ] && shift; _target="${1:-}"
    case "$_cmd" in
        get)
            _key="${_target##*.}"
            _value="$(awk -F= -v k="$_key" '$1==k {sub(/^[^=]*=/,""); print; found=1; exit} END {if (!found) exit 1}' "$MOCK_UCI_STATE")" || return 1
            [ -n "$_value" ] || return 1
            printf '%s\n' "$_value" | tr '|' ' '
            ;;
        set)
            _key="${_target%%=*}"; _key="${_key##*.}"; _value="${_target#*=}"
            awk -F= -v k="$_key" -v v="$_value" '$1!=k {print} END {print k "=" v}' "$MOCK_UCI_STATE" > "$MOCK_UCI_STATE.tmp"
            mv "$MOCK_UCI_STATE.tmp" "$MOCK_UCI_STATE"
            ;;
        delete|del)
            _key="${_target##*.}"
            awk -F= -v k="$_key" '$1!=k {print}' "$MOCK_UCI_STATE" > "$MOCK_UCI_STATE.tmp"
            mv "$MOCK_UCI_STATE.tmp" "$MOCK_UCI_STATE"
            ;;
        del_list|delete_list)
            _key="${_target%%=*}"; _key="${_key##*.}"; _remove="${_target#*=}"
            awk -F= -v k="$_key" -v r="$_remove" '$1==k {n=split($2,a,/\|/); out=""; for(i=1;i<=n;i++) if(a[i]!="" && a[i]!=r) out=out (out==""?"":"|") a[i]; print k "=" out; found=1; next} {print} END {if(!found) print k "="}' "$MOCK_UCI_STATE" > "$MOCK_UCI_STATE.tmp"
            mv "$MOCK_UCI_STATE.tmp" "$MOCK_UCI_STATE"
            ;;
        add_list)
            _key="${_target%%=*}"; _key="${_key##*.}"; _add="${_target#*=}"
            _old="$(awk -F= -v k="$_key" '$1==k {sub(/^[^=]*=/,""); print; exit}' "$MOCK_UCI_STATE")"
            case "|$_old|" in *"|$_add|"*) :;; *) _old="${_old:+$_old|}$_add";; esac
            awk -F= -v k="$_key" '$1!=k {print}' "$MOCK_UCI_STATE" > "$MOCK_UCI_STATE.tmp"
            printf '%s=%s\n' "$_key" "$_old" >> "$MOCK_UCI_STATE.tmp"
            mv "$MOCK_UCI_STATE.tmp" "$MOCK_UCI_STATE"
            ;;
        commit) return 0 ;;
        *) printf 'mock uci: unsupported command %s\n' "$_cmd" >&2; return 2 ;;
    esac
}
state_value() {
    awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/,""); print; found=1; exit} END {if(!found) exit 1}' "$MOCK_UCI_STATE"
}
test_dns_recovery_without_backup() (
    TEST_TMP="$WORK/dns-no-backup"; export TEST_TMP
    mkdir -p "$TEST_TMP/init.d"
    printf '#!/bin/sh\nexit 0\n' > "$TEST_TMP/init.d/dnsmasq"; chmod 755 "$TEST_TMP/init.d/dnsmasq"
    extract_function dnsmasq_manager_server_owned "$WORK/server-owned.sh" || return 1
    extract_function dnsmasq_external_confdir_has_files "$WORK/confdir-helper.sh" || return 1
    extract_function rollback_dnsmasq_targeted "$WORK/rollback.raw" || return 1
    sed 's|/etc/init.d/dnsmasq|"$TEST_TMP/init.d/dnsmasq"|g' "$WORK/rollback.raw" > "$WORK/rollback.sh"
    . "$WORK/server-owned.sh"
    . "$WORK/confdir-helper.sh"
    . "$WORK/rollback.sh"
    dnsmasq_external_confdir_has_files() { return 1; }
    uci() { mock_uci "$@"; }
    get_dnsmasq_section() { printf '%s' dnsmasq; }
    rollback_ownership_has() { [ -f "$OWNERSHIP" ] && grep -Fqx -- "$1|$2|$3" "$OWNERSHIP" 2>/dev/null; }
    warn_msg() { :; }
    MOCK_UCI_STATE="$TEST_TMP/uci-state"; OWNERSHIP="$TEST_TMP/missing-ownership"; export MOCK_UCI_STATE
    DNS_PROFILE=hybrid; DNS_SELECTION_MODE=hybrid
    SLOT_1=cloudflare; PORT_1=5053
    SLOT_2=; PORT_2=; SLOT_3=; PORT_3=; SLOT_4=; PORT_4=; SLOT_5=; PORT_5=; SLOT_6=; PORT_6=
    SLOT_RU=; PORT_RU=; BALANCER_ENABLED=0; TLD_RU_ENABLED=0; ROLLBACK_DNS_CORE_ONLY=0
    printf '%s\n' 'server=127.0.0.1#5053' 'noresolv=1' 'allservers=1' 'strictorder=0' 'confdir=/etc/dnsmasq.d' > "$MOCK_UCI_STATE"
    rollback_dnsmasq_targeted || { printf '%s\n' '  rollback failed'; return 1; }
    _server="$(state_value server 2>/dev/null || true)"; _noresolv="$(state_value noresolv 2>/dev/null || true)"
    case "$_server" in *'127.0.0.1#5053'*) printf '%s\n' '  dead Manager upstream was left in dnsmasq'; return 1;; esac
    [ "$_noresolv" != 1 ] || { printf '%s\n' '  noresolv=1 still blocks WAN DNS without a usable upstream'; return 1; }
    printf '%s\n' 'server=127.0.0.1#5053|192.0.2.53' 'noresolv=1' 'allservers=1' 'strictorder=0' 'confdir=/etc/dnsmasq.d' > "$MOCK_UCI_STATE"
    rollback_dnsmasq_targeted || { printf '%s\n' '  rollback failed for mixed upstreams'; return 1; }
    _server="$(state_value server 2>/dev/null || true)"; _noresolv="$(state_value noresolv 2>/dev/null || true)"
    case "$_server" in *'127.0.0.1#5053'*) printf '%s\n' '  dead Manager upstream remains alongside third-party DNS'; return 1;; esac
    case "$_server" in *'192.0.2.53'*) :;; *) printf '%s\n' '  unrelated DNS upstream was removed'; return 1;; esac
    [ "$_noresolv" = 1 ] || { printf '%s\n' '  noresolv was changed despite a preserved unrelated upstream'; return 1; }
)
test_external_hdp_sections_are_preserved() (
    extract_function clear_all_doh_for_apply "$WORK/clear-hdp.sh" || return 1
    extract_function rebuild_selected_hdp_sections "$WORK/rebuild-hdp.sh" || return 1
    grep -Fq 'dns_manager_hdp_section_owned "$_p" "$_u"' "$WORK/clear-hdp.sh" || {
        printf '%s\n' '  HDP apply cleanup does not verify Manager ownership'; return 1;
    }
    grep -Fq 'clear_all_doh_for_apply ||' "$WORK/rebuild-hdp.sh" || {
        printf '%s\n' '  HDP rebuild does not use selective cleanup'; return 1;
    }
    if grep -Fq 'uci -q delete "https-dns-proxy.@https-dns-proxy[0]"' "$WORK/rebuild-hdp.sh" ||
       grep -Fq 'uci -q delete "https-dns-proxy.@https-dns-proxy[0]"' "$WORK/clear-hdp.sh"; then
        printf '%s\n' '  applying a profile deletes all pre-existing https-dns-proxy sections without ownership checks'
        return 1
    fi
)
test_failed_uninstall_keeps_retry_state() (
    TEST_TMP="$WORK/uninstall-retry"; export TEST_TMP
    mkdir -p "$TEST_TMP/init.d" "$TEST_TMP/base/config" "$TEST_TMP/state" "$TEST_TMP/bin"
    for _service in dnsmasq https-dns-proxy; do
        cat > "$TEST_TMP/init.d/$_service" <<'EOS'
#!/bin/sh
if [ "${TEST_DNSMASQ_FAIL:-0}" = 1 ] && [ "$(basename "$0")" = dnsmasq ]; then exit 1; fi
exit 0
EOS
        chmod 755 "$TEST_TMP/init.d/$_service"
    done
    extract_function uninstall_manager_impl "$WORK/uninstall.raw" || return 1
    sed -e 's|/etc/init.d/dnsmasq|"$TEST_TMP/init.d/dnsmasq"|g' -e 's|/etc/init.d/https-dns-proxy|"$TEST_TMP/init.d/https-dns-proxy"|g' -e '/find \/tmp -maxdepth/c\    : # isolated test; do not clean global /tmp' -e '/rm -rf \/tmp\/luci-indexcache\*/c\    : # isolated test; do not clean global LuCI cache' "$WORK/uninstall.raw" > "$WORK/uninstall.sh"
    . "$WORK/uninstall.sh"
    clear_screen() { :; }; menu_header() { :; }; warn_msg() { :; }; err_msg() { :; }; info_msg() { :; }; pause() { :; }
    confirm_action() { return 0; }; acquire_mutation_lock() { return 0; }; release_mutation_lock() { :; }
    watchdog_service_stop_disable() { [ "${TEST_WATCHDOG_FAIL:-0}" != 1 ]; }; watchdog_cron_remove_owned_block() { return 0; }
    rollback_hdp_targeted() { return 0; }; rollback_dnsmasq_targeted() { return 0; }; rollback_firewall_targeted() { return 0; }
    manager_force_config_matches() { return 1; }; check_module_state() { printf '%s' 0; }; rollback_ownership_has() { return 1; }
    reload_fw() { [ "${TEST_FIREWALL_FAIL:-0}" != 1 ]; }; watchdog_service_remove_files() { return 0; }; luci_companion_remove() { return 0; }
    cleanup_stale_tmp_dirs() { return 0; }; find() { return 0; }
    package_owner_remove_owned() {
        _attempt="$(cat "$TEST_TMP/package-remove-attempts" 2>/dev/null || printf 0)"
        _attempt=$((_attempt + 1)); printf '%s\n' "$_attempt" > "$TEST_TMP/package-remove-attempts"
        [ "$_attempt" -ge 2 ]
    }
    BASE_DIR="$TEST_TMP/base"; STATE_DIR="$TEST_TMP/state"; LOG_FILE="$TEST_TMP/manager.log"; TX_LOG="$TEST_TMP/transaction.log"
    MANAGER_PATH="$TEST_TMP/bin/dns-manager"; PACKAGE_OWNERSHIP="$BASE_DIR/config/packages.owned"; OWNERSHIP="$BASE_DIR/config/ownership.log"
    : > "$PACKAGE_OWNERSHIP"; : > "$OWNERSHIP"; : > "$LOG_FILE"; : > "$TX_LOG"; : > "$STATE_DIR/state"; : > "$MANAGER_PATH"
    if (uninstall_manager_impl >/dev/null 2>&1); then printf '%s\n' '  first uninstall reported success despite package cleanup failure'; return 1; fi
    for _path in "$BASE_DIR" "$PACKAGE_OWNERSHIP" "$OWNERSHIP" "$STATE_DIR" "$LOG_FILE" "$TX_LOG" "$MANAGER_PATH"; do
        [ -e "$_path" ] || { printf '  retry state deleted after incomplete uninstall: %s\n' "$_path"; return 1; }
    done
    TEST_DNSMASQ_FAIL=1; export TEST_DNSMASQ_FAIL
    if (uninstall_manager_impl >/dev/null 2>&1); then printf '%s\n' '  uninstall reported success although dnsmasq restart failed'; return 1; fi
    for _path in "$BASE_DIR" "$PACKAGE_OWNERSHIP" "$OWNERSHIP" "$STATE_DIR" "$LOG_FILE" "$TX_LOG" "$MANAGER_PATH"; do
        [ -e "$_path" ] || { printf '  retry state deleted after DNS restart failure: %s\n' "$_path"; return 1; }
    done

    TEST_DNSMASQ_FAIL=0; TEST_FIREWALL_FAIL=1; export TEST_DNSMASQ_FAIL TEST_FIREWALL_FAIL
    if (uninstall_manager_impl >/dev/null 2>&1); then printf '%s\n' '  uninstall reported success although firewall reload failed'; return 1; fi
    for _path in "$BASE_DIR" "$PACKAGE_OWNERSHIP" "$OWNERSHIP" "$STATE_DIR" "$LOG_FILE" "$TX_LOG" "$MANAGER_PATH"; do
        [ -e "$_path" ] || { printf '  retry state deleted after firewall reload failure: %s\n' "$_path"; return 1; }
    done

    TEST_FIREWALL_FAIL=0; TEST_WATCHDOG_FAIL=1; export TEST_FIREWALL_FAIL TEST_WATCHDOG_FAIL
    if (uninstall_manager_impl >/dev/null 2>&1); then printf '%s\n' '  uninstall reported success although procd watchdog did not stop'; return 1; fi
    for _path in "$BASE_DIR" "$PACKAGE_OWNERSHIP" "$OWNERSHIP" "$STATE_DIR" "$LOG_FILE" "$TX_LOG" "$MANAGER_PATH"; do
        [ -e "$_path" ] || { printf '  retry state deleted after watchdog stop failure: %s\n' "$_path"; return 1; }
    done

    TEST_WATCHDOG_FAIL=0; export TEST_WATCHDOG_FAIL
    (uninstall_manager_impl >/dev/null 2>&1) || { printf '%s\n' '  final retry could not finish after transient failures'; return 1; }
    for _path in "$BASE_DIR" "$STATE_DIR" "$LOG_FILE" "$TX_LOG" "$MANAGER_PATH"; do
        [ ! -e "$_path" ] || { printf '  successful final pass left residual state: %s\n' "$_path"; return 1; }
    done
)
_failures=0
for _test in test_dns_recovery_without_backup test_external_hdp_sections_are_preserved test_failed_uninstall_keeps_retry_state; do
    if "$_test"; then ok "$_test"; else printf 'FAIL: %s\n' "$_test" >&2; _failures=$((_failures+1)); fi
done
[ "$_failures" -eq 0 ] || exit 1
