#!/bin/sh
# Minimal regression checks for DNS Manager uninstall.
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

sh -n "$ROOT/dns-manager.sh" || fail "syntax: dns-manager.sh"
sh -n "$ROOT/dns-manager-luci.sh" || fail "syntax: dns-manager-luci.sh"
sh -n "$ROOT/tests/test.sh" || fail "syntax: tests/test.sh"
sh -n "$0" || fail "syntax: test-uninstall-regression.sh"
extract_function uninstall_manager_impl "$WORK/uninstall.sh" || fail "cannot extract uninstall function"
sh -n "$WORK/uninstall.sh" || fail "syntax: uninstall_manager_impl"
ok "Shell syntax checks"

if grep -Eq 'rollback_hdp_targeted|rollback_dnsmasq_targeted|rollback_firewall_targeted|remove_dns_force|remove_dnsmasq_perf|remove_ntp_ip_fallback|manager_force_config_matches|uci[[:space:]]+(-q[[:space:]]+)?(set|delete|del|add_list|commit)|reload_fw|/etc/init.d/(https-dns-proxy|dnsmasq)' "$WORK/uninstall.sh"; then
    fail "uninstall contains DNS/DoH/dnsmasq/firewall cleanup"
fi
grep -Fq 'package_owner_remove_owned' "$WORK/uninstall.sh" || fail "owned packages are not removed"
grep -Fq 'luci_companion_remove' "$WORK/uninstall.sh" || fail "LuCI companion is not removed"
grep -Fq 'watchdog_service_stop_disable' "$WORK/uninstall.sh" || fail "watchdog is not stopped"
grep -Fq 'watchdog_service_remove_files' "$WORK/uninstall.sh" || fail "watchdog files are not removed"
ok "Uninstall is limited to Manager, owned packages, LuCI, and watchdog"

# Exercise retry behavior with temporary paths; no router paths are touched.
. "$WORK/uninstall.sh"
C_YELLOW= C_NC= C_GREEN= C_BOLD=
clear_screen() { :; }
menu_header() { :; }
warn_msg() { :; }
err_msg() { :; }
info_msg() { :; }
pause() { :; }
confirm_action() { return 0; }
acquire_mutation_lock() { return 0; }
release_mutation_lock() { :; }
watchdog_service_stop_disable() { return 0; }
watchdog_cron_remove_owned_block() { return 0; }
watchdog_service_remove_files() { return 0; }
luci_companion_remove() { : > "$WORK/luci-removed"; return 0; }

DNS_STATE="$WORK/dns-state"
printf 'dnsmasq=server=127.0.0.1#5053;noresolv=1\nhttps-dns-proxy.force_dns=1\nfirewall=manager-redirect\n' > "$DNS_STATE"
cp "$DNS_STATE" "$WORK/dns-state.expected"
UCI_CALLS="$WORK/uci-calls"
uci() { printf 'called\n' >> "$UCI_CALLS"; return 1; }
rollback_hdp_targeted() { : > "$WORK/forbidden-dns-call"; return 1; }
rollback_dnsmasq_targeted() { : > "$WORK/forbidden-dns-call"; return 1; }
rollback_firewall_targeted() { : > "$WORK/forbidden-dns-call"; return 1; }
remove_dns_force() { : > "$WORK/forbidden-dns-call"; return 1; }
remove_dnsmasq_perf() { : > "$WORK/forbidden-dns-call"; return 1; }
remove_ntp_ip_fallback() { : > "$WORK/forbidden-dns-call"; return 1; }
reload_fw() { : > "$WORK/forbidden-dns-call"; return 1; }

BASE_DIR="$WORK/base"
STATE_DIR="$WORK/state"
MUTATION_LOCK_DIR="$STATE_DIR/mutation.lock"
LOG_FILE="$WORK/manager.log"
TX_LOG="$WORK/manager.tx"
MANAGER_PATH="$WORK/bin/dns-manager"
PACKAGE_OWNERSHIP="$BASE_DIR/config/package-ownership.conf"
mkdir -p "$BASE_DIR/config" "$STATE_DIR" "$WORK/bin"
printf 'https-dns-proxy\ncurl\n' > "$PACKAGE_OWNERSHIP"
printf 'state\n' > "$STATE_DIR/dns-test-results.conf"
: > "$LOG_FILE"; : > "$TX_LOG"; : > "$MANAGER_PATH"
package_owner_remove_owned() {
    _attempt="$(cat "$WORK/package-remove-attempts" 2>/dev/null || printf 0)"
    _attempt=$((_attempt + 1))
    printf '%s\n' "$_attempt" > "$WORK/package-remove-attempts"
    [ "$_attempt" -ge 2 ]
}
if (uninstall_manager_impl >/dev/null 2>&1); then
    fail "uninstall must report a package-removal failure"
fi
[ -f "$PACKAGE_OWNERSHIP" ] && [ -f "$MANAGER_PATH" ] && [ -d "$BASE_DIR" ] || fail "manager retry files were deleted after a package-removal failure"
[ ! -e "$WORK/luci-removed" ] || fail "LuCI was removed before package removal succeeded"

if ! (uninstall_manager_impl >"$WORK/uninstall.log" 2>&1); then
    cat "$WORK/uninstall.log" >&2
    fail "uninstall retry did not complete"
fi
[ ! -e "$MANAGER_PATH" ] && [ ! -e "$BASE_DIR" ] || fail "successful retry left Manager files"
[ -e "$WORK/luci-removed" ] || fail "successful uninstall did not remove LuCI"
cmp -s "$DNS_STATE" "$WORK/dns-state.expected" || fail "uninstall changed DNS/DoH/firewall state"
[ ! -s "$UCI_CALLS" ] || fail "uninstall called UCI"
[ ! -e "$WORK/forbidden-dns-call" ] || fail "uninstall called a DNS cleanup helper"
ok "Package-removal failure is retryable; DNS/DoH/firewall state stays untouched"
