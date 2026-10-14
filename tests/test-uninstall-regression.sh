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
    fail "DNS restoration must be isolated in restore_dns_before_uninstall"
fi
grep -Fq 'restore_dns_before_uninstall' "$WORK/uninstall.sh" || fail "uninstall does not restore system DNS first"
grep -Fq 'package_owner_remove_owned' "$WORK/uninstall.sh" || fail "owned packages are not removed"
grep -Fq 'luci_companion_remove' "$WORK/uninstall.sh" || fail "LuCI companion is not removed"
grep -Fq 'watchdog_service_stop_disable' "$WORK/uninstall.sh" || fail "watchdog is not stopped"
grep -Fq 'watchdog_service_remove_files' "$WORK/uninstall.sh" || fail "watchdog files are not removed"
ok "Uninstall restores owned DNS state before removing Manager files"

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
restore_dns_before_uninstall() {
    printf 'restored\n' >> "$WORK/dns-restore-attempts"
    return 0
}

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
    _restore_count="$(wc -l < "$WORK/dns-restore-attempts" 2>/dev/null || printf 0)"
    [ "$_restore_count" -eq "$_attempt" ] || return 1
    [ "$_attempt" -ge 2 ]
}
if (uninstall_manager_impl >/dev/null 2>&1); then
    fail "uninstall must report a package-removal failure"
fi
[ "$(wc -l < "$WORK/dns-restore-attempts")" -eq 1 ] || fail "DNS restore was not attempted before package removal"
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
ok "Package-removal failure is retryable; DNS restore runs before every package-removal attempt"


# DNS reset must restore the official package defaults, not leave zero DoH instances.
(
    extract_function restore_hdp_package_defaults "$WORK/restore-hdp-defaults.sh" || fail "cannot extract package-default DNS restore helper"
    . "$WORK/restore-hdp-defaults.sh"
    HDP_TEST_SECTIONS="$WORK/restore-hdp-sections.conf"
    HDP_TEST_MAIN="$WORK/restore-hdp-main.conf"
    HDP_TEST_EVENTS="$WORK/restore-hdp-events"
    HDP_TEST_ADDED=0
    cat > "$HDP_TEST_SECTIONS" <<'EOF_HDP_TEST_SECTIONS'
old1|5054|https://cloudflare-dns.com/dns-query|old-bootstrap|127.0.0.1|2
old2|5056|https://dns.aa.net.uk/dns-query|old-bootstrap|127.0.0.1|2
old3|5058|https://dns.belnet.be/dns-query|old-bootstrap|127.0.0.1|2
EOF_HDP_TEST_SECTIONS
    cat > "$HDP_TEST_MAIN" <<'EOF_HDP_TEST_MAIN'
type=main
force_dns=0
dnsmasq_config_update=-
notrack_dns=1
force_dns_port=53
force_dns_port=853
force_dns_src_interface=lan
EOF_HDP_TEST_MAIN
    : > "$HDP_TEST_EVENTS"
    uci() {
        [ "${1:-}" = "-q" ] && shift
        case "${1:-}" in
            show)
                [ "${2:-}" = https-dns-proxy ] || return 1
                [ -s "$HDP_TEST_MAIN" ] && printf 'https-dns-proxy.config=main\n'
                awk -F'|' '{ printf "https-dns-proxy.@https-dns-proxy[%d]=https-dns-proxy\n", NR-1 }' "$HDP_TEST_SECTIONS"
                ;;
            delete)
                UT_TARGET="${2:-}"
                case "$UT_TARGET" in
                    https-dns-proxy.config)
                        : > "$HDP_TEST_MAIN"
                        ;;
                    https-dns-proxy.config.*)
                        UT_KEY="${UT_TARGET#https-dns-proxy.config.}"
                        awk -F'=' -v k="$UT_KEY" '$1 != k {print}' "$HDP_TEST_MAIN" > "$HDP_TEST_MAIN.tmp" &&
                            mv "$HDP_TEST_MAIN.tmp" "$HDP_TEST_MAIN"
                        ;;
                    https-dns-proxy.@https-dns-proxy*)
                        UT_IDX="$(printf '%s\n' "$UT_TARGET" | sed -n 's/^https-dns-proxy\.@https-dns-proxy\[\([0-9][0-9]*\)\]$/\1/p')"
                        [ -n "$UT_IDX" ] || return 1
                        awk -F'|' -v n="$((UT_IDX + 1))" 'NR != n {print}' "$HDP_TEST_SECTIONS" > "$HDP_TEST_SECTIONS.tmp" &&
                            mv "$HDP_TEST_SECTIONS.tmp" "$HDP_TEST_SECTIONS"
                        ;;
                    *) return 1 ;;
                esac
                printf 'delete:%s\n' "$UT_TARGET" >> "$HDP_TEST_EVENTS"
                ;;
            set)
                UT_ASSIGN="${2:-}"
                UT_LEFT="${UT_ASSIGN%%=*}"
                UT_VALUE="${UT_ASSIGN#*=}"
                case "$UT_LEFT" in
                    https-dns-proxy.config)
                        : > "$HDP_TEST_MAIN"
                        printf 'type=%s\n' "$UT_VALUE" >> "$HDP_TEST_MAIN"
                        ;;
                    https-dns-proxy.config.*)
                        UT_KEY="${UT_LEFT#https-dns-proxy.config.}"
                        awk -F'=' -v k="$UT_KEY" '$1 != k {print}' "$HDP_TEST_MAIN" > "$HDP_TEST_MAIN.tmp" &&
                            mv "$HDP_TEST_MAIN.tmp" "$HDP_TEST_MAIN"
                        printf '%s=%s\n' "$UT_KEY" "$UT_VALUE" >> "$HDP_TEST_MAIN"
                        ;;
                    https-dns-proxy.cfg-default-*.bootstrap_dns)
                        UT_SEC="${UT_LEFT#https-dns-proxy.}"; UT_SEC="${UT_SEC%%.*}"
                        awk -F'|' -v OFS='|' -v id="$UT_SEC" -v v="$UT_VALUE" '$1==id {$4=v} {print}' "$HDP_TEST_SECTIONS" > "$HDP_TEST_SECTIONS.tmp" &&
                            mv "$HDP_TEST_SECTIONS.tmp" "$HDP_TEST_SECTIONS"
                        ;;
                    https-dns-proxy.cfg-default-*.resolver_url)
                        UT_SEC="${UT_LEFT#https-dns-proxy.}"; UT_SEC="${UT_SEC%%.*}"
                        awk -F'|' -v OFS='|' -v id="$UT_SEC" -v v="$UT_VALUE" '$1==id {$3=v} {print}' "$HDP_TEST_SECTIONS" > "$HDP_TEST_SECTIONS.tmp" &&
                            mv "$HDP_TEST_SECTIONS.tmp" "$HDP_TEST_SECTIONS"
                        ;;
                    https-dns-proxy.cfg-default-*.listen_port)
                        UT_SEC="${UT_LEFT#https-dns-proxy.}"; UT_SEC="${UT_SEC%%.*}"
                        awk -F'|' -v OFS='|' -v id="$UT_SEC" -v v="$UT_VALUE" '$1==id {$2=v} {print}' "$HDP_TEST_SECTIONS" > "$HDP_TEST_SECTIONS.tmp" &&
                            mv "$HDP_TEST_SECTIONS.tmp" "$HDP_TEST_SECTIONS"
                        ;;
                    *) return 1 ;;
                esac
                printf 'set:%s\n' "$UT_ASSIGN" >> "$HDP_TEST_EVENTS"
                ;;
            add)
                [ "${2:-}" = https-dns-proxy ] && [ "${3:-}" = https-dns-proxy ] || return 1
                HDP_TEST_ADDED=$((HDP_TEST_ADDED + 1))
                printf 'cfg-default-%s|||||\n' "$HDP_TEST_ADDED" >> "$HDP_TEST_SECTIONS"
                printf 'cfg-default-%s\n' "$HDP_TEST_ADDED"
                ;;
            add_list)
                UT_ASSIGN="${2:-}"
                UT_LEFT="${UT_ASSIGN%%=*}"
                UT_VALUE="${UT_ASSIGN#*=}"
                case "$UT_LEFT" in
                    https-dns-proxy.config.force_dns_port)
                        printf 'force_dns_port=%s\n' "$UT_VALUE" >> "$HDP_TEST_MAIN"
                        ;;
                    https-dns-proxy.config.force_dns_src_interface)
                        printf 'force_dns_src_interface=%s\n' "$UT_VALUE" >> "$HDP_TEST_MAIN"
                        ;;
                    *) return 1 ;;
                esac
                ;;
            commit)
                [ "${2:-}" = https-dns-proxy ] || return 1
                printf 'commit\n' >> "$HDP_TEST_EVENTS"
                ;;
            *) return 1 ;;
        esac
    }
    restore_hdp_package_defaults || exit 1
    [ "$(wc -l < "$HDP_TEST_SECTIONS" | tr -d ' ')" = 2 ] || {
        printf 'Expected exactly two stock DoH instances:\n' >&2
        cat "$HDP_TEST_SECTIONS" >&2
        exit 1
    }
    grep -Fq '|5053|https://cloudflare-dns.com/dns-query|1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001|127.0.0.1|' "$HDP_TEST_SECTIONS" || exit 1
    grep -Fq '|5054|https://dns.google/dns-query|8.8.8.8,8.8.4.4,2001:4860:4860::8888,2001:4860:4860::8844|127.0.0.1|' "$HDP_TEST_SECTIONS" || exit 1
    grep -qx 'force_dns=1' "$HDP_TEST_MAIN" || exit 1
    grep -qx 'dnsmasq_config_update=*' "$HDP_TEST_MAIN" || exit 1
    grep -qx 'notrack_dns=1' "$HDP_TEST_MAIN" || exit 1
    grep -qx 'force_dns_port=53' "$HDP_TEST_MAIN" || exit 1
    grep -qx 'force_dns_port=853' "$HDP_TEST_MAIN" || exit 1
    grep -qx 'force_dns_src_interface=lan' "$HDP_TEST_MAIN" || exit 1
    grep -qx 'commit' "$HDP_TEST_EVENTS" || exit 1
) || fail "DNS reset did not restore the official https-dns-proxy defaults"
ok "DNS reset restores package defaults: Cloudflare 5053 + Google 5054"

# Anonymous https-dns-proxy UCI section indices shift after deletion.
# Remove several Manager-owned instances in reverse order, without touching an
# unrelated resolver that happens to sit between them.
(
    extract_function rollback_hdp_targeted "$WORK/rollback-hdp-source.sh" || fail "cannot extract DoH rollback helper"
    sed 's|^[[:space:]]*/etc/init.d/https-dns-proxy restart.*|    : # service restart mocked for this isolated test|' \
        "$WORK/rollback-hdp-source.sh" > "$WORK/rollback-hdp-targeted.sh"
    . "$WORK/rollback-hdp-targeted.sh"
    ROLLBACK_SECTIONS="$WORK/rollback-sections.conf"
    ROLLBACK_UCI_CALLS="$WORK/rollback-uci-calls"
    OWNERSHIP="$WORK/rollback-ownership.conf"
    : > "$OWNERSHIP"
    : > "$ROLLBACK_UCI_CALLS"
    cat > "$ROLLBACK_SECTIONS" <<'EOF_ROLLBACK_SECTIONS'
5054|https://cloudflare-dns.com/dns-query
5056|https://dns.aa.net.uk/dns-query
6000|https://manual.example/dns-query
5058|https://dns.belnet.be/dns-query
EOF_ROLLBACK_SECTIONS
    SLOT_1=cloudflare; PORT_1=5054
    SLOT_2=aa; PORT_2=5056
    SLOT_3=belnet; PORT_3=5058
    SLOT_4=; SLOT_5=; SLOT_6=; SLOT_RU=
    PORT_4=; PORT_5=; PORT_6=; PORT_RU=
    normalize_url() { printf '%s' "$1" | sed 's/[[:space:]]//g; s:/*$::'; }
    dns_url() {
        case "$1" in
            cloudflare) printf 'https://cloudflare-dns.com/dns-query' ;;
            aa) printf 'https://dns.aa.net.uk/dns-query' ;;
            belnet) printf 'https://dns.belnet.be/dns-query' ;;
            *) return 1 ;;
        esac
    }
    rollback_ownership_has() { return 1; }
    uci() {
        [ "$1" = "-q" ] && shift
        case "$1" in
            show)
                [ "$2" = "https-dns-proxy" ] || return 1
                awk -F'|' '{ printf "https-dns-proxy.@https-dns-proxy[%d]=https-dns-proxy\n", NR-1 }' "$ROLLBACK_SECTIONS"
                ;;
            get)
                _target="$2"
                _idx="$(printf '%s\n' "$_target" | sed -n 's/^https-dns-proxy\.@https-dns-proxy\[\([0-9][0-9]*\)\].*/\1/p')"
                [ -n "$_idx" ] || return 1
                _row="$(sed -n "$((_idx + 1))p" "$ROLLBACK_SECTIONS")"
                [ -n "$_row" ] || return 1
                _port="$(printf '%s\n' "$_row" | cut -d'|' -f1)"
                _url="$(printf '%s\n' "$_row" | cut -d'|' -f2-)"
                case "$_target" in
                    *.resolver_url) printf '%s' "$_url" ;;
                    *.listen_port) printf '%s' "$_port" ;;
                    *) printf 'https-dns-proxy' ;;
                esac
                ;;
            delete)
                _target="$2"
                _idx="$(printf '%s\n' "$_target" | sed -n 's/^https-dns-proxy\.@https-dns-proxy\[\([0-9][0-9]*\)\]$/\1/p')"
                [ -n "$_idx" ] || return 1
                awk -F'|' -v n="$((_idx + 1))" 'NR != n { print }' "$ROLLBACK_SECTIONS" > "$ROLLBACK_SECTIONS.tmp" &&
                    mv "$ROLLBACK_SECTIONS.tmp" "$ROLLBACK_SECTIONS"
                printf 'delete:%s\n' "$_idx" >> "$ROLLBACK_UCI_CALLS"
                ;;
            commit)
                [ "$2" = "https-dns-proxy" ] || return 1
                printf 'commit\n' >> "$ROLLBACK_UCI_CALLS"
                ;;
            *) return 1 ;;
        esac
    }
    rollback_hdp_targeted || exit 1
    if grep -qE '^(5054|5056|5058)\|' "$ROLLBACK_SECTIONS"; then
        printf 'Remaining Manager DoH sections:\n' >&2
        cat "$ROLLBACK_SECTIONS" >&2
        exit 1
    fi
    grep -q '^6000|https://manual.example/dns-query$' "$ROLLBACK_SECTIONS" ||
        { printf 'Unrelated DoH section was removed\n' >&2; exit 1; }
    [ "$(wc -l < "$ROLLBACK_SECTIONS" | tr -d ' ')" = 1 ] || exit 1
) || fail "DoH rollback skipped sections after anonymous UCI indices shifted"
ok "multiple Manager DoH sections removed; unrelated resolver preserved"

# When no explicit upstream remains, disable noresolv so system resolvfile is used.
extract_function uninstall_dnsmasq_resolv_fallback "$WORK/resolv-fallback.sh" || fail "cannot extract DNS resolvfile fallback"
. "$WORK/resolv-fallback.sh"
DNS_TEST_SERVER=""
DNS_TEST_NORESOLV=1
DNS_TEST_COMMITS=0
DNS_TEST_DEL_CALLS=""
get_dnsmasq_section() { printf 'lan'; }
uci() {
    [ "${1:-}" = "-q" ] && shift
    case "${1:-}" in
        get)
            case "${2:-}" in
                dhcp.lan) return 0 ;;
                dhcp.lan.server)
                    [ -n "$DNS_TEST_SERVER" ] || return 1
                    printf '%s' "$DNS_TEST_SERVER"
                    ;;
                dhcp.lan.noresolv)
                    [ -n "$DNS_TEST_NORESOLV" ] || return 1
                    printf '%s' "$DNS_TEST_NORESOLV"
                    ;;
                *) return 1 ;;
            esac
            ;;
        del_list)
            _entry="${2#dhcp.lan.server=}"
            DNS_TEST_DEL_CALLS="${DNS_TEST_DEL_CALLS}|$_entry"
            DNS_TEST_SERVER="$(printf '%s' "$DNS_TEST_SERVER" | tr ' ' '\n' | grep -vxF "$_entry" | tr '\n' ' ' | sed 's/ *$//')"
            ;;
        delete)
            [ "${2:-}" = dhcp.lan.noresolv ] || return 1
            DNS_TEST_NORESOLV=""
            ;;
        commit)
            [ "${2:-}" = dhcp ] || return 1
            DNS_TEST_COMMITS=$((DNS_TEST_COMMITS + 1))
            ;;
        *) return 1
    esac
}
# Reproduce the actual failure mode: domain-only entries coexist with three
# stale Manager loopback ports. Those ports must go, and the system resolvfile
# must be enabled even though domain-only rules remain.
DNS_TEST_SERVER="/mask.icloud.com/ /mask-h2.icloud.com/ /use-application-dns.net/ /unrelated.example/ 127.0.0.1#5054 127.0.0.1#5056 127.0.0.1#5058"
DNS_TEST_NORESOLV=1
DNS_TEST_COMMITS=0
DNS_TEST_DEL_CALLS=""
uninstall_dnsmasq_resolv_fallback || fail "failed to enable the default resolvfile path"
case " $DNS_TEST_SERVER " in *"127.0.0.1#5054"*|*"127.0.0.1#5056"*|*"127.0.0.1#5058"*) fail "Manager loopback upstreams remain" ;; esac
[ -z "$DNS_TEST_NORESOLV" ] || fail "noresolv remained enabled without a general upstream"
case "$DNS_TEST_SERVER" in *"/unrelated.example/"*) ;; *) fail "unrelated domain-only entry was not preserved" ;; esac
case "$DNS_TEST_SERVER" in *"/mask.icloud.com/"*|*"/mask-h2.icloud.com/"*|*"/use-application-dns.net/"*) fail "https-dns-proxy canary entries remain" ;; esac
ok "stale Manager ports and proxy canaries removed; unrelated domain rule preserved; system resolvfile enabled"

DNS_TEST_SERVER="9.9.9.9"
DNS_TEST_NORESOLV=1
DNS_TEST_COMMITS=0
DNS_TEST_DEL_CALLS=""
uninstall_dnsmasq_resolv_fallback || fail "fallback failed with a custom upstream"
[ "$DNS_TEST_NORESOLV" = 1 ] || fail "fallback disabled noresolv despite custom DNS upstream"
case "$DNS_TEST_SERVER" in 9.9.9.9) ;; *) fail "custom DNS upstream was changed" ;; esac
ok "custom upstreams are preserved and keep noresolv enabled"

# Ensure https-dns-proxy is stopped before detachment, its dnsmasq auto-update
# is disabled, and package-private restore journals are removed for future stop/removal.
extract_function uninstall_detach_https_dns_proxy "$WORK/detach-hdp.sh" || fail "cannot extract proxy detachment helper"
. "$WORK/detach-hdp.sh"
HD_TEST_DIR="$WORK/hdp-detach"
mkdir -p "$HD_TEST_DIR"
HD_TEST_EVENTS="$HD_TEST_DIR/events"
HD_TEST_CONFIG_UPDATE="*"
HD_TEST_FORCE_DNS=1
HD_TEST_META="doh_server
doh_backup_server
doh_backup_noresolv"
HD_TEST_COMMITS=0
# Reproduce the user's exact case: Manager had FORCE_DOH=0 while the proxy
# config still had force_dns=1. Uninstall must disable the package interception.
FORCE_DOH=0
HTTPS_DNS_PROXY_INIT="$HD_TEST_DIR/init"
export HD_TEST_EVENTS
cat > "$HTTPS_DNS_PROXY_INIT" <<'EOF_HDP_INIT'
#!/bin/sh
printf 'stop\n' >> "$HD_TEST_EVENTS"
[ "${1:-}" = stop ]
EOF_HDP_INIT
chmod +x "$HTTPS_DNS_PROXY_INIT"
uci() {
    [ "${1:-}" = "-q" ] && shift
    case "${1:-}" in
        get)
            case "${2:-}" in
                https-dns-proxy.config) printf 'config' ;;
                https-dns-proxy.config.force_dns) printf '%s' "$HD_TEST_FORCE_DNS" ;;
                dhcp.cfg01411c.doh_server|dhcp.cfg01411c.doh_backup_server|dhcp.cfg01411c.doh_backup_noresolv)
                    _opt="${2##*.}"
                    printf '%s\n' "$HD_TEST_META" | grep -qxF "$_opt" && printf 'present' || return 1
                    ;;
                *) return 1 ;;
            esac
            ;;
        show)
            [ "${2:-}" = dhcp ] || return 1
            printf 'dhcp.cfg01411c=dnsmasq\n'
            ;;
        set)
            case "${2:-}" in
                https-dns-proxy.config.force_dns=0) HD_TEST_FORCE_DNS=0; printf 'force-off\n' >> "$HD_TEST_EVENTS" ;;
                https-dns-proxy.config.dnsmasq_config_update=-) HD_TEST_CONFIG_UPDATE=-; printf 'update-off\n' >> "$HD_TEST_EVENTS" ;;
                *) return 1 ;;
            esac
            ;;
        commit)
            case "${2:-}" in
                https-dns-proxy) HD_TEST_COMMITS=$((HD_TEST_COMMITS+1)); printf 'commit-hdp\n' >> "$HD_TEST_EVENTS" ;;
                dhcp) printf 'commit-dhcp\n' >> "$HD_TEST_EVENTS" ;;
                *) return 1 ;;
            esac
            ;;
        delete)
            _opt="${2##*.}"
            HD_TEST_META="$(printf '%s\n' "$HD_TEST_META" | grep -vxF "$_opt" || true)"
            printf 'delete:%s\n' "$_opt" >> "$HD_TEST_EVENTS"
            ;;
        *) return 1 ;;
    esac
}
: > "$HD_TEST_EVENTS"
uninstall_detach_https_dns_proxy || fail "proxy detachment failed"
[ "$HD_TEST_CONFIG_UPDATE" = "-" ] || fail "https-dns-proxy auto dnsmasq updates remain enabled"
[ "$HD_TEST_FORCE_DNS" = 0 ] || fail "https-dns-proxy forced-DNS interception remains enabled despite saved FORCE_DOH=0"
grep -qxF 'stop' "$HD_TEST_EVENTS" || fail "proxy stop hook did not run"
grep -qxF 'commit-hdp' "$HD_TEST_EVENTS" || fail "proxy config was not committed"
[ "$HD_TEST_COMMITS" -eq 1 ] || fail "proxy config commit count unexpected"
[ -z "$HD_TEST_META" ] || fail "https-dns-proxy restore metadata remains"
[ "$(sed -n '1p' "$HD_TEST_EVENTS")" = stop ] || fail "proxy wasn't stopped before changing integration"
ok "https-dns-proxy stop journal cleared, auto dnsmasq update disabled, package retained"

# The proxy-detachment test above also verifies that Manager forced-DNS is
# disabled only when the saved Manager setting says it was enabled.

# Verify package removal always preserves https-dns-proxy regardless of ownership.
extract_function package_owner_remove_owned "$WORK/package-remove-owned.sh" || fail "cannot extract package owner removal"
. "$WORK/package-remove-owned.sh"
PACKAGE_OWNERSHIP="$WORK/package-ownership-test.conf"
APK_CALLS="$WORK/apk-calls"
PKG_MGR=apk
printf 'https-dns-proxy\ncurl\n' > "$PACKAGE_OWNERSHIP"
apk() {
    printf '%s\n' "$*" >> "$APK_CALLS"
    case "$*" in
        "info -e https-dns-proxy"|"info -e curl") return 0 ;;
        "del curl") return 0 ;;
        "del https-dns-proxy") return 99 ;;
        *) return 1 ;;
    esac
}
: > "$APK_CALLS"
package_owner_remove_owned || fail "owned package removal failed"
grep -Fq 'del curl' "$APK_CALLS" || fail "other owned packages were not removed"
if grep -Fq 'del https-dns-proxy' "$APK_CALLS"; then
    fail "https-dns-proxy must never be removed by DNS Manager uninstall"
fi
ok "https-dns-proxy remains installed even if ownership file lists it"

# If the cached companion installer is missing, uninstall the known LuCI
# namespace from its installed marker and fixed paths. Repeating removal is safe.
for _fn in luci_companion_remove_fallback luci_companion_remove; do
    awk -v fn="$_fn" '$0 == fn "() {" {capture=1} capture {print} capture && /^}$/ {exit}' "$ROOT/dns-manager.sh" >> "$WORK/luci-remove-functions.sh"
done
[ -s "$WORK/luci-remove-functions.sh" ] || fail "cannot extract LuCI removal helpers"
sh -n "$WORK/luci-remove-functions.sh" || fail "syntax: LuCI removal helpers"
cat > "$WORK/luci-remove-runner.sh" <<'EOF_LUCI_REMOVE'
#!/bin/sh
set -eu
W="$1"
LUCI_STATE_FILE="$W/etc/dns-manager/config/luci-state.conf"
LUCI_COMPANION_CACHE="$W/etc/dns-manager/dns-manager-luci.sh"
LUCI_RPC_PLUGIN="$W/usr/libexec/rpcd/dns_manager"
LUCI_BACKEND_FILE="$W/usr/lib/dns-manager-luci/backend.sh"
LUCI_ACL_FILE="$W/usr/share/rpcd/acl.d/luci-app-dns-manager.json"
LUCI_MENU_FILE="$W/usr/share/luci/menu.d/luci-app-dns-manager.json"
LUCI_VIEW_DIR="$W/www/luci-static/resources/view/dns-manager"
LUCI_RESOURCE_DIR="$W/www/luci-static/resources/dns-manager"
LUCI_COMMON_FILE="$LUCI_RESOURCE_DIR/common.js"
LUCI_VIEW_FILE="$LUCI_VIEW_DIR/dashboard.js"
LUCI_RUNTIME_DIR="$W/var/run/dns-manager-luci"
LUCI_BACKUP_DIR="$W/etc/dns-manager-luci"
LUCI_CACHE_DIR="$W/tmp"
LUCI_LEGACY_CONTROLLER_FILE="$W/usr/lib/lua/luci/controller/dns_manager.lua"
CLEANUP_EVENTS="$W/cleanup-events"

mkdir -p "$W/etc/dns-manager/config" "$W/etc/config" \
    "$(dirname "$LUCI_RPC_PLUGIN")" "$(dirname "$LUCI_BACKEND_FILE")" \
    "$(dirname "$LUCI_ACL_FILE")" "$(dirname "$LUCI_MENU_FILE")" \
    "$LUCI_VIEW_DIR" "$LUCI_RESOURCE_DIR" "$LUCI_RUNTIME_DIR" "$LUCI_BACKUP_DIR" \
    "$(dirname "$LUCI_LEGACY_CONTROLLER_FILE")" "$W/usr/lib/lua/luci/controller" \
    "$W/www/luci-static/resources/view/unrelated" "$LUCI_CACHE_DIR"
printf 'installed=1\nversion=1.50\n' > "$LUCI_STATE_FILE"
printf 'manager configuration must survive LuCI cleanup\n' > "$W/etc/dns-manager/config/manager.conf"
printf 'third-party DHCP configuration\n' > "$W/etc/config/dhcp"
cp "$W/etc/config/dhcp" "$W/dhcp.expected"
printf 'menu admin/services/dns-manager\n' > "$LUCI_MENU_FILE"
printf 'ACL luci-app-dns-manager\n' > "$LUCI_ACL_FILE"
printf '# DNS Manager LuCI rpcd plugin\n' > "$LUCI_RPC_PLUGIN"
printf '# DNS Manager LuCI backend\n' > "$LUCI_BACKEND_FILE"
printf '// DNS Manager LuCI common module version: 1.50\n' > "$LUCI_COMMON_FILE"
for _view in dashboard doh network time catalog log; do
    printf '// DNS Manager LuCI version: 1.50\n' > "$LUCI_VIEW_DIR/$_view.js"
done
printf 'module("luci.controller.dns_manager", package.seeall)\n' > "$LUCI_LEGACY_CONTROLLER_FILE"
printf 'third-party controller must survive\n' > "$W/usr/lib/lua/luci/controller/thirdparty.lua"
printf 'unrelated LuCI view must survive\n' > "$W/www/luci-static/resources/view/unrelated/index.js"
printf 'LuCI cache\n' > "$LUCI_CACHE_DIR/luci-indexcache-test"
printf 'LuCI module cache\n' > "$LUCI_CACHE_DIR/luci-modulecache-test"
: > "$CLEANUP_EVENTS"
# LUCI_COMPANION_CACHE intentionally does not exist.
warn_msg() { printf 'WARN:%s\n' "$*" >> "$CLEANUP_EVENTS"; }
err_msg() { printf 'ERR:%s\n' "$*" >> "$CLEANUP_EVENTS"; }
luci_component_files_present() {
    [ -f "$LUCI_MENU_FILE" ] || return 1
    [ -f "$LUCI_ACL_FILE" ] || return 1
    [ -x "$LUCI_RPC_PLUGIN" ] || return 1
    [ -f "$LUCI_BACKEND_FILE" ] || return 1
    [ -f "$LUCI_COMMON_FILE" ] || return 1
    for _view in dashboard doh network time catalog log; do
        [ -f "$LUCI_VIEW_DIR/${_view}.js" ] || return 1
    done
    return 0
}
. "$2"
luci_companion_remove || exit 51
[ ! -e "$LUCI_STATE_FILE" ] || exit 52
[ ! -e "$LUCI_COMPANION_CACHE" ] || exit 53
for _path in "$LUCI_RPC_PLUGIN" "$LUCI_BACKEND_FILE" "$LUCI_ACL_FILE" "$LUCI_MENU_FILE" "$LUCI_VIEW_DIR" "$LUCI_RESOURCE_DIR" "$LUCI_RUNTIME_DIR" "$LUCI_BACKUP_DIR" "$LUCI_LEGACY_CONTROLLER_FILE"; do
    [ ! -e "$_path" ] || { printf 'leftover: %s\n' "$_path" >&2; exit 54; }
done
[ -f "$W/usr/lib/lua/luci/controller/thirdparty.lua" ] || exit 55
[ -f "$W/www/luci-static/resources/view/unrelated/index.js" ] || exit 56
[ -f "$W/etc/dns-manager/config/manager.conf" ] || exit 57
cmp -s "$W/etc/config/dhcp" "$W/dhcp.expected" || exit 58
[ ! -e "$LUCI_CACHE_DIR/luci-indexcache-test" ] && [ ! -e "$LUCI_CACHE_DIR/luci-modulecache-test" ] || exit 59
# A second call is a no-op once the installed marker has been removed.
luci_companion_remove || exit 60
[ -f "$W/etc/dns-manager/config/manager.conf" ] || exit 61
cmp -s "$W/etc/config/dhcp" "$W/dhcp.expected" || exit 62
EOF_LUCI_REMOVE
chmod +x "$WORK/luci-remove-runner.sh"
"$WORK/luci-remove-runner.sh" "$WORK/luci-fixture" "$WORK/luci-remove-functions.sh" || fail "missing-cache LuCI removal or idempotent retry"
ok "missing cached installer: owned LuCI files removed, unrelated files/config preserved, retry is safe"

