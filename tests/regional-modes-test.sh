#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM
awk '/^normalize_slot_domains\(\) \{/,/^slot_domains_set\(\) \{/' "$ROOT/dns-manager.sh" | sed '$d' > "$tmp/functions"
awk '/^reconcile_dnsmasq\(\) \{/,/^}/' "$ROOT/dns-manager.sh" >> "$tmp/functions"
awk '/^watchdog_expected_servers\(\) \{/,/^}/' "$ROOT/dns-manager.sh" >> "$tmp/functions"
. "$tmp/functions"
TMP_DIR="$tmp"
SLOT_1=one PORT_1=5053 SLOT_1_DOMAINS=example.com
SLOT_2= PORT_2= SLOT_3= PORT_3= SLOT_4= PORT_4= SLOT_5= PORT_5= SLOT_6= PORT_6=
SLOT_RU= PORT_RU= TLD_RU_ENABLED=0 BALANCER_ENABLED=1
state="$tmp/server"
uci() {
    [ "$1" != -q ] || shift
    case "$1:$2" in
        get:dhcp.main) return 0 ;;
        get:dhcp.main.server) tr '\n' ' ' < "$state" ;;
        get:*) return 1 ;;
        delete:dhcp.main.server) : > "$state" ;;
        delete:*|set:*|commit:*) : ;;
        add_list:dhcp.main.server=*) printf '%s\n' "${2#*=}" >> "$state" ;;
        add_list:*) : ;;
        *) return 1 ;;
    esac
}
get_dnsmasq_section() { echo main; }
exact_list_has() { [ "$1" = dhcp.main.server ] && grep -Fxq "$2" "$state"; }
record_own() { :; }
for REGIONAL_MODE in doh yandex isp legacy; do
    SLOT_RU= PORT_RU= TLD_RU_ENABLED=0
    REGIONAL_ISP_IPS='94.230.128.3 10.255.0.2'
    [ "$REGIONAL_MODE" != legacy ] || { SLOT_RU=regional; PORT_RU=5059; TLD_RU_ENABLED=1; }
    reconcile_dnsmasq
    expected="$(watchdog_expected_servers)"
    sort -u "$state" > "$tmp/actual"
    cmp -s "$tmp/actual" "$expected" || { echo "FAIL: inconsistent expected routes for $REGIONAL_MODE" >&2; exit 1; }
    grep -Fxq '127.0.0.1#5053' "$state"
    grep -Fxq '/example.com/127.0.0.1#5053' "$state"
    case "$REGIONAL_MODE" in
        doh) ! grep -q '^/ru/' "$state" ;;
        yandex) grep -Fxq '/ru/77.88.8.8' "$state"; grep -Fxq '/xn--p1ai/77.88.8.1' "$state" ;;
        isp) grep -Fxq '/ru/94.230.128.3' "$state"; grep -Fxq '/su/10.255.0.2' "$state" ;;
        legacy) grep -Fxq '/ru/127.0.0.1#5059' "$state"; ! grep -Fxq '127.0.0.1#5059' "$state" ;;
    esac
done
echo 'OK: regional modes and watchdog routes'
awk '/^regional_reconcile_with_canaries\(\) \{/,/^}/' "$ROOT/dns-manager.sh" > "$tmp/canaries"
(
    . "$tmp/canaries"
    REGIONAL_MODE=isp REGIONAL_ISP_IPS=94.230.128.3
    regional_reconcile_with_canaries '/mask.icloud.com/ /use-application-dns.net/'
    grep -Fxq '/mask.icloud.com/' "$state"
    grep -Fxq '/use-application-dns.net/' "$state"
    grep -Fxq '/ru/94.230.128.3' "$state"
)
echo 'OK: updating provider routes preserves existing dnsmasq canaries'
awk '/^steer_dns_upstream_ready\(\) \{/,/^}/' "$ROOT/dns-manager.sh" > "$tmp/steer-ready"
(
    . "$tmp/steer-ready"
    for REGIONAL_MODE in doh yandex isp legacy; do
        SLOT_RU= PORT_RU= TLD_RU_ENABLED=0
        REGIONAL_ISP_IPS='94.230.128.3 10.255.0.2'
        [ "$REGIONAL_MODE" != legacy ] || { SLOT_RU=regional; PORT_RU=5059; TLD_RU_ENABLED=1; }
        reconcile_dnsmasq
        printf '%s\n' '/mask.icloud.com/' '/use-application-dns.net/' >> "$state"
        steer_dns_upstream_ready || { echo "FAIL: Steer rejected valid $REGIONAL_MODE routes" >&2; exit 1; }
        printf '%s\n' '127.0.0.1#5059' >> "$state"
        if steer_dns_upstream_ready; then echo "FAIL: Steer accepted extra general DNS" >&2; exit 1; fi
    done
)
echo 'OK: Steer status accepts expected regional routes and rejects unexpected general DNS'

awk '/^regional_apply_toggle\(\) \{/,/^}/' "$ROOT/dns-manager.sh" > "$tmp/toggle"
awk '/^regional_refresh_provider\(\) \{/,/^}/' "$ROOT/dns-manager.sh" > "$tmp/refresh"
printf '%s\n' '#!/bin/sh' '# DNS_MANAGER_REGIONAL_SERVICE=1' 'exit 0' > "$tmp/regional-service"
chmod +x "$tmp/regional-service"
(
    . "$tmp/toggle"
    acquire_mutation_lock() { :; }; release_mutation_lock() { :; }; load_config() { :; }
    sync_regional_dns_state() { :; }; err_msg() { :; }
    regional_provider_addresses() { printf '%s\n' "${MOCK_PROVIDER:-}"; }
    dns_cat() { echo regional; }
    _apply_settings_impl() { [ "$SLOT_1" = one ]; }
    REGIONAL_SERVICE_INIT="$tmp/regional-service"
    SLOT_RU=old PORT_RU=5059 REGIONAL_SAVED_ID=old
    regional_apply_toggle 2
    [ "$REGIONAL_MODE" = yandex ] && [ -z "$SLOT_RU" ] && [ "$REGIONAL_SAVED_ID" = old ]
    MOCK_PROVIDER=94.230.128.3
    REGIONAL_SERVICE_INIT="$tmp/missing-service"
    if regional_apply_toggle 3; then exit 1; fi
    [ "$REGIONAL_MODE" = yandex ]
    REGIONAL_SERVICE_INIT="$tmp/regional-service"
    regional_apply_toggle 3
    [ "$REGIONAL_MODE" = isp ] && [ "$REGIONAL_ISP_IPS" = "$MOCK_PROVIDER" ]
    MOCK_PROVIDER=''
    if regional_apply_toggle 3; then exit 1; fi
    [ "$REGIONAL_MODE" = isp ] && [ "$REGIONAL_ISP_IPS" = 94.230.128.3 ]
    regional_apply_toggle 0
    [ "$REGIONAL_MODE" = doh ] && [ -z "$SLOT_RU" ]
    regional_apply_toggle 1
    [ "$REGIONAL_MODE" = legacy ] && [ "$SLOT_RU" = old ]
)
echo 'OK: regional selection and missing provider addresses'
(
    . "$tmp/refresh"
    acquire_mutation_lock() { :; }; release_mutation_lock() { :; }; load_config() { :; }
    regional_provider_addresses() { [ -z "$MOCK_PROVIDER" ] || printf '%s\n' "$MOCK_PROVIDER"; }
    get_dnsmasq_section() { echo main; }
    watchdog_expected_servers() { printf '%s\n' '127.0.0.1#5053' '/ru/94.230.128.3' | sort > "$tmp/expected"; echo "$tmp/expected"; }
    uci() { [ "$1" != -q ] || shift; case "$1:$2" in changes:dhcp) printf '%s' "${MOCK_PENDING:-}";; get:dhcp.main.server) printf '%s\n' "${MOCK_ACTUAL:-127.0.0.1#5053 /ru/94.230.128.3}";; *) return 1;; esac; }
    reconcile_dnsmasq() { printf 'reconcile\n' >> "$tmp/actions"; }
    regional_reconcile_with_canaries() { reconcile_dnsmasq; }
    dnsmasq_restart_checked() { [ "${MOCK_FAIL:-0}" != 1 ]; }
    save_config() { printf 'save:%s\n' "$REGIONAL_ISP_IPS" >> "$tmp/actions"; }
    refresh_device_dns_runtime() { :; }; log_msg() { :; }
    REGIONAL_MODE=isp REGIONAL_ISP_IPS=94.230.128.3 MOCK_PROVIDER=''
    : > "$tmp/actions"
    regional_refresh_provider
    [ ! -s "$tmp/actions" ] && [ "$REGIONAL_ISP_IPS" = 94.230.128.3 ]
    MOCK_PROVIDER=94.230.129.3 MOCK_PENDING='pending'
    if regional_refresh_provider; then exit 1; fi
    [ ! -s "$tmp/actions" ] && [ "$REGIONAL_ISP_IPS" = 94.230.128.3 ]
    MOCK_PENDING='' MOCK_ACTUAL='127.0.0.1#5053 /ru/94.230.128.3 /foreign.example/8.8.8.8'
    if regional_refresh_provider; then exit 2; fi
    [ ! -s "$tmp/actions" ] && [ "$REGIONAL_ISP_IPS" = 94.230.128.3 ]
    MOCK_ACTUAL='' MOCK_FAIL=1
    if regional_refresh_provider; then exit 3; fi
    [ "$REGIONAL_ISP_IPS" = 94.230.128.3 ]
    grep -Fxq 'save:94.230.128.3' "$tmp/actions"
    MOCK_FAIL=0
    regional_refresh_provider
    [ "$REGIONAL_ISP_IPS" = 94.230.129.3 ]
    grep -Fxq 'save:94.230.129.3' "$tmp/actions"
)
echo 'OK: provider change, empty WAN, external settings and rollback'
awk '/^clear_dns_core_runtime_state\(\) \{/,/^}/' "$ROOT/dns-manager.sh" > "$tmp/reset"
(
    . "$tmp/reset"
    save_config() { [ "$REGIONAL_MODE" = doh ] && [ -z "$REGIONAL_ISP_IPS" ] && [ -z "$SLOT_RU" ]; }
    REGIONAL_MODE=isp REGIONAL_ISP_IPS=94.230.128.3 SLOT_RU=old
    clear_dns_core_runtime_state
    [ "$REGIONAL_MODE" = doh ] && [ -z "$REGIONAL_ISP_IPS" ] && [ -z "$SLOT_RU" ]
)
echo 'OK: DNS reset clears the regional mode'

awk '/^normalize_ownership_snapshot\(\) \{/,/^}/' "$ROOT/dns-manager.sh" > "$tmp/ownership-fns"
awk '/^dnsmasq_manager_server_owned\(\) \{/,/^}/' "$ROOT/dns-manager.sh" >> "$tmp/ownership-fns"
(
    . "$tmp/ownership-fns"
    OWNERSHIP="$tmp/owned"
    REGIONAL_MODE=isp REGIONAL_ISP_IPS=94.230.128.3 PORT_RU=
    printf '%s\n' 'dnsmasq|server|/ru/94.230.128.3|section=main' 'dnsmasq|server|/ru/192.0.2.123|section=main' > "$OWNERSHIP"
    normalize_ownership_snapshot
    grep -Fxq 'dnsmasq|server|/ru/94.230.128.3|section=main' "$OWNERSHIP"
    ! grep -Fq '/ru/192.0.2.123' "$OWNERSHIP"
    UNINSTALL_STRICT_OWNERSHIP=1
    if dnsmasq_manager_server_owned /ru/94.230.128.3; then exit 1; fi
)
echo 'OK: regional ownership survives cleanup without inferring ownership during uninstall'
