#!/bin/sh
# Focused regression checks for DNS Manager uninstall.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'OK: %s\n' "$*"; }
extract_function() {
    awk -v fn="$1" '$0 == fn "() {" {capture=1} capture {print} capture && /^}$/ {exit}' "$ROOT/dns-manager.sh" > "$2"
    [ -s "$2" ]
}

# Minimal UCI mock. List values are stored with | separators in the fixture.
mock_uci() {
    [ "${1:-}" = -q ] && shift
    _cmd="${1:-}"; [ "$#" -gt 0 ] && shift
    _target="${1:-}"
    case "$_cmd" in
        get)
            _key="${_target##*.}"
            _value="$(awk -F= -v k="$_key" '$1==k {sub(/^[^=]*=/,""); print; found=1; exit} END {if(!found) exit 1}' "$MOCK_UCI_STATE")" || return 1
            [ -n "$_value" ] || return 1
            printf '%s\n' "$_value" | tr '|' ' '
            ;;
        del_list|delete_list)
            _key="${_target%%=*}"; _key="${_key##*.}"; _remove="${_target#*=}"
            awk -F= -v k="$_key" -v r="$_remove" '
                $1==k {n=split($2,a,/\|/); out=""; for(i=1;i<=n;i++) if(a[i]!="" && a[i]!=r) out=out (out==""?"":"|") a[i]; print k "=" out; found=1; next}
                {print}
                END {if(!found) print k "="}
            ' "$MOCK_UCI_STATE" > "$MOCK_UCI_STATE.tmp"
            mv "$MOCK_UCI_STATE.tmp" "$MOCK_UCI_STATE"
            ;;
        delete|del)
            _key="${_target##*.}"
            awk -F= -v k="$_key" '$1!=k {print}' "$MOCK_UCI_STATE" > "$MOCK_UCI_STATE.tmp"
            mv "$MOCK_UCI_STATE.tmp" "$MOCK_UCI_STATE"
            ;;
        commit) return 0 ;;
        *) printf 'Unsupported mock UCI command: %s\n' "$_cmd" >&2; return 2 ;;
    esac
}
state_value() {
    awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/,""); print; found=1; exit} END {if(!found) exit 1}' "$MOCK_UCI_STATE"
}
setup_dnsmasq_test() {
    mkdir -p "$WORK/confdir"
    extract_function dnsmasq_manager_server_owned "$WORK/owned.sh" || return 1
    extract_function dnsmasq_external_confdir_has_servers "$WORK/confdir.sh" || return 1
    extract_function rollback_dnsmasq_targeted "$WORK/rollback.sh" || return 1
    . "$WORK/owned.sh"
    . "$WORK/confdir.sh"
    . "$WORK/rollback.sh"
    uci() { mock_uci "$@"; }
    get_dnsmasq_section() { printf dnsmasq; }
    rollback_ownership_has() { [ -f "$OWNERSHIP" ] && grep -Fqx -- "$1|$2|$3" "$OWNERSHIP" 2>/dev/null; }
    warn_msg() { :; }
    OWNERSHIP="$WORK/no-ownership-journal"
    MOCK_UCI_STATE="$WORK/uci-state"
    DNS_MANAGER_UNINSTALLING=1
    ROLLBACK_DNS_CORE_ONLY=0
    SLOT_1=cloudflare; PORT_1=5053
    SLOT_2=; PORT_2=; SLOT_3=; PORT_3=; SLOT_4=; PORT_4=; SLOT_5=; PORT_5=; SLOT_6=; PORT_6=
    SLOT_RU=; PORT_RU=
}
# No ownership log: remove the active Manager upstream and restore WAN DNS.
setup_dnsmasq_test
printf 'server=127.0.0.1#5053\nnoresolv=1\nconfdir=%s\n' "$WORK/confdir" > "$MOCK_UCI_STATE"
rollback_dnsmasq_targeted || fail "rollback failed without the ownership journal"
_server="$(state_value server 2>/dev/null || true)"
_noresolv="$(state_value noresolv 2>/dev/null || true)"
case "$_server" in *'127.0.0.1#5053'*) fail "dead Manager upstream remains without the ownership journal";; esac
[ "$_noresolv" != 1 ] || fail "noresolv=1 still blocks WAN resolver fallback"
ok "DNS rollback without ownership journal"

# Keep a third-party UCI upstream and its noresolv behaviour.
setup_dnsmasq_test
printf 'server=127.0.0.1#5053|192.0.2.53\nnoresolv=1\nconfdir=%s\n' "$WORK/confdir" > "$MOCK_UCI_STATE"
rollback_dnsmasq_targeted || fail "rollback failed with an external upstream"
_server="$(state_value server)"
case "$_server" in *'192.0.2.53'*) :;; *) fail "external upstream was removed";; esac
case "$_server" in *'127.0.0.1#5053'*) fail "Manager upstream was not removed";; esac
[ "$(state_value noresolv)" = 1 ] || fail "noresolv was changed while external upstream remains"
ok "External DNS upstream is preserved"

# An upstream in a configured confdir also prevents unsafe noresolv removal.
setup_dnsmasq_test
printf 'server=127.0.0.1#5053\nnoresolv=1\nconfdir=%s\n' "$WORK/confdir" > "$MOCK_UCI_STATE"
printf 'server=192.0.2.54\n' > "$WORK/confdir/50-external.conf"
rollback_dnsmasq_targeted || fail "rollback failed with confdir upstream"
[ "$(state_value noresolv)" = 1 ] || fail "noresolv was removed despite a confdir upstream"
ok "Confdir upstream is preserved"

# Check HDP rollback source: deletion must be scoped to a section identified
# by the ownership journal or the exact selected Manager slot, not all sections.
extract_function rollback_hdp_targeted "$WORK/rollback-hdp.sh" || fail "cannot extract HDP rollback"
grep -Fq 'rollback_ownership_has doh "$_port" "$_url"' "$WORK/rollback-hdp.sh" || fail "HDP cleanup has no ownership check"
grep -Fq 'uci -q delete "https-dns-proxy.$_sec" || return 1' "$WORK/rollback-hdp.sh" || fail "HDP deletion failure is ignored"
if grep -Fq 'uci -q delete "https-dns-proxy.@https-dns-proxy[0]"' "$WORK/rollback-hdp.sh"; then
    fail "HDP cleanup deletes anonymous sections wholesale"
fi
ok "HDP cleanup is targeted and reports deletion errors"

# A failed package-removal attempt must leave state and executable for retry.
mkdir -p "$WORK/init.d" "$WORK/config" "$WORK/base/config" "$WORK/state" "$WORK/bin"
for _service in dnsmasq https-dns-proxy; do
    printf '#!/bin/sh\nexit 0\n' > "$WORK/init.d/$_service"
    chmod 755 "$WORK/init.d/$_service"
done
extract_function uninstall_manager_impl "$WORK/uninstall.raw" || fail "cannot extract uninstall function"
sed \
    -e 's|/etc/init.d/dnsmasq|"$TEST_TMP/init.d/dnsmasq"|g' \
    -e 's|/etc/init.d/https-dns-proxy|"$TEST_TMP/init.d/https-dns-proxy"|g' \
    -e 's|/etc/config/https-dns-proxy|"$TEST_TMP/config/https-dns-proxy"|g' \
    -e '/find \/tmp -maxdepth/c\    : # isolated test; do not scan global /tmp' \
    -e '/rm -rf \/tmp\/luci-indexcache\*/c\    : # isolated test; do not clear global LuCI cache' \
    "$WORK/uninstall.raw" > "$WORK/uninstall.sh"
. "$WORK/uninstall.sh"
TEST_TMP="$WORK"; export TEST_TMP
clear_screen() { :; }; menu_header() { :; }; warn_msg() { :; }; err_msg() { :; }; info_msg() { :; }; pause() { :; }
confirm_action() { return 0; }; acquire_mutation_lock() { return 0; }; release_mutation_lock() { :; }
watchdog_service_stop_disable() { return 0; }; watchdog_cron_remove_owned_block() { return 0; }
rollback_hdp_targeted() { return 0; }; rollback_dnsmasq_targeted() { return 0; }; rollback_firewall_targeted() { return 0; }
manager_force_config_matches() { return 1; }; check_module_state() { printf 0; }; rollback_ownership_has() { return 1; }
remove_dnsmasq_perf() { return 0; }; remove_ntp_ip_fallback() { return 0; }
reload_fw() { return 0; }; watchdog_service_remove_files() { return 0; }; luci_companion_remove() { return 0; }
cleanup_stale_tmp_dirs() { return 0; }
uci() { return 1; }
PACKAGE_OWNERSHIP="$WORK/base/config/packages.owned"; OWNERSHIP="$WORK/base/config/ownership.log"
BASE_DIR="$WORK/base"; STATE_DIR="$WORK/state"; LOG_FILE="$WORK/manager.log"; TX_LOG="$WORK/transaction.log"
MANAGER_PATH="$WORK/bin/dns-manager"
printf 'https-dns-proxy\n' > "$PACKAGE_OWNERSHIP"
: > "$OWNERSHIP"; : > "$LOG_FILE"; : > "$TX_LOG"; : > "$STATE_DIR/state"; : > "$MANAGER_PATH"; : > "$WORK/config/https-dns-proxy"
package_owner_remove_owned() {
    _attempt="$(cat "$WORK/remove-attempts" 2>/dev/null || printf 0)"
    _attempt=$((_attempt+1)); printf '%s\n' "$_attempt" > "$WORK/remove-attempts"
    [ "$_attempt" -ge 2 ]
}
if (uninstall_manager_impl >/dev/null 2>&1); then fail "uninstall reported success after package removal failure"; fi
[ -f "$PACKAGE_OWNERSHIP" ] && [ -f "$OWNERSHIP" ] && [ -f "$MANAGER_PATH" ] && [ -d "$BASE_DIR" ] || fail "retry state was deleted after package removal failure"
if ! (uninstall_manager_impl >"$WORK/final-uninstall.log" 2>&1); then
    printf '%s\n' 'Final uninstall log:' >&2
    cat "$WORK/final-uninstall.log" >&2
    printf 'Package removal attempts: %s\n' "$(cat "$WORK/remove-attempts" 2>/dev/null || printf 0)" >&2
    fail "retry could not finish after transient package removal failure"
fi
[ ! -e "$MANAGER_PATH" ] && [ ! -e "$BASE_DIR" ] && [ ! -e "$STATE_DIR" ] || fail "successful retry left Manager files"
ok "Failed uninstall keeps state for a safe retry"
