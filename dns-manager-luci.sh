#!/bin/sh
# DNS Manager LuCI companion
# Version: 0.3
# Installs a native LuCI application for the existing /usr/bin/dns-manager.
# This file DOES NOT replace, patch or modify the DNS Manager backend.
# It does not install ttyd and does not open another HTTP port.

set -eu

APP="dns-manager-luci"
MANAGER="/usr/bin/dns-manager"
RPC_PLUGIN="/usr/libexec/rpcd/dns_manager"
ACL_FILE="/usr/share/rpcd/acl.d/luci-app-dns-manager.json"
MENU_FILE="/usr/share/luci/menu.d/luci-app-dns-manager.json"
VIEW_DIR="/www/luci-static/resources/view/dns_manager"
VIEW_FILE="$VIEW_DIR/overview.js"
RUNTIME_DIR="/var/run/dns-manager-luci"
BACKUP_DIR="/etc/dns-manager-luci"
VERSION="0.3"

say() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

manager_version() {
    [ -r "$MANAGER" ] || return 1
    sed -n 's/^VERSION="\([0-9][0-9.]*\)"$/\1/p' "$MANAGER" 2>/dev/null | head -n1
}

require_manager() {
    [ -x "$MANAGER" ] || { err "Не найден $MANAGER. Сначала установите DNS Manager."; return 1; }
    [ -n "$(manager_version 2>/dev/null || true)" ] || { err "Не удалось определить версию DNS Manager."; return 1; }
}

install_files() {
    require_manager || return 1

    command -v jsonfilter >/dev/null 2>&1 || { err "Не найден jsonfilter, требуемый штатным rpcd-адаптером LuCI."; return 1; }
    mkdir -p "$VIEW_DIR" /usr/libexec/rpcd /usr/share/rpcd/acl.d /usr/share/luci/menu.d "$RUNTIME_DIR/checks" || return 1

    cat > "$MENU_FILE" <<'EOF_MENU'
{
  "admin/services/dns_manager": {
    "title": "DNS Manager",
    "order": 71,
    "action": {
      "type": "view",
      "path": "dns_manager/overview"
    },
    "depends": {
      "acl": [ "luci-app-dns-manager" ]
    }
  }
}
EOF_MENU

    cat > "$ACL_FILE" <<'EOF_ACL'
{
  "luci-app-dns-manager": {
    "description": "DNS Manager native LuCI interface",
    "read": {
      "ubus": {
        "dns_manager": [ "status", "catalog", "job", "log" ]
      }
    },
    "write": {
      "ubus": {
        "dns_manager": [ "set_profile", "set_slot", "set_setting", "test_all", "test_one" ]
      }
    }
  }
}
EOF_ACL

    cat > "$RPC_PLUGIN" <<'EOF_RPC'
#!/bin/sh
# DNS Manager LuCI rpcd plugin
# This adapter dynamically loads only the function/definition part of the
# existing DNS Manager and exposes a strict allowlist of operations.

MANAGER="/usr/bin/dns-manager"
RUNTIME_DIR="/var/run/dns-manager-luci"
JOB_DIR="$RUNTIME_DIR/jobs"
CHECK_DIR="$RUNTIME_DIR/checks"
TMP_ROOT="$RUNTIME_DIR/tmp"

umask 077
mkdir -p "$RUNTIME_DIR" "$JOB_DIR" "$CHECK_DIR" "$TMP_ROOT" 2>/dev/null || exit 1

json_quote() {
    _s="$1"
    _s=$(printf '%s' "$_s" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r/ /g; s/\t/\\t/g; s/$//')
    printf '"%s"' "$_s"
}

INPUT=""
jget() {
    _key="$1"
    [ -n "${INPUT:-}" ] || return 0
    printf %s "$INPUT" | jsonfilter -q -e "@.$_key" 2>/dev/null || true
}

json_ok() { printf '{"ok":true}'; }
json_error() {
    printf '{"ok":false,"error":'; json_quote "$1"; printf '}';
}

manager_version() {
    [ -r "$MANAGER" ] || return 1
    sed -n 's/^VERSION="\([0-9][0-9.]*\)"$/\1/p' "$MANAGER" 2>/dev/null | head -n1
}

load_manager() {
    [ -x "$MANAGER" ] || return 1
    _mv="$(manager_version 2>/dev/null || true)"
    [ -n "$_mv" ] || return 1
    _src="$TMP_ROOT/manager-functions.$$"
    # Keep the authoritative manager untouched. Only copy the definition/setup
    # portion before its interactive CLI dispatch at the end.
    sed '/^case "${1:-}" in$/,$d' "$MANAGER" > "$_src" 2>/dev/null || { rm -f "$_src"; return 1; }
    # shellcheck disable=SC1090
    . "$_src" || { rm -f "$_src"; return 1; }
    rm -f "$_src"
    preflight_readonly >/dev/null 2>&1 || return 1
    init_dirs >/dev/null 2>&1 || return 1
    load_config >/dev/null 2>&1 || return 1
    restore_persistent_test_results >/dev/null 2>&1 || true
    refresh_runtime_capabilities >/dev/null 2>&1 || true
    return 0
}

result_for_id() {
    _id="$1"
    [ -s "$TEST_RESULTS" ] || return 1
    awk -F'|' -v id="$_id" '$1==id {print; exit}' "$TEST_RESULTS" 2>/dev/null
}

last_check_for_id() {
    _id="$1"
    _f="$CHECK_DIR/$_id"
    if [ -r "$_f" ]; then
        cat "$_f" 2>/dev/null | head -n1
        return 0
    fi
    _ts="$(sed -n 's/^timestamp=//p' "$TEST_RESULTS_META" 2>/dev/null | head -n1)"
    [ -n "$_ts" ] || return 0
    result_for_id "$_id" >/dev/null 2>&1 && printf '%s' "$_ts"
}

average_selected_ping() {
    _sum=0; _n=0
    for _s in 1 2 3 4 5 6 RU RU_2; do
        eval "_id=\${SLOT_${_s}:-}"
        [ -n "$_id" ] || continue
        _ms="$(result_for_id "$_id" 2>/dev/null | awk -F'|' '$5=="OK" && $4 ~ /^[0-9]+$/ {print $4; exit}')"
        case "$_ms" in ''|*[!0-9]*) continue;; esac
        _sum=$((_sum + _ms)); _n=$((_n + 1))
    done
    [ "$_n" -gt 0 ] && printf '%s' "$((_sum / _n))" || printf ''
}


package_version() {
    _pkg="$1"
    [ -n "$_pkg" ] || return 0
    if command -v apk >/dev/null 2>&1; then
        apk list -I "$_pkg" 2>/dev/null | sed -n 's/^[^ ]*\-\([0-9][^ ]*\)$/\1/p' | head -n1
    elif command -v opkg >/dev/null 2>&1; then
        opkg status "$_pkg" 2>/dev/null | sed -n 's/^Version:[[:space:]]*//p' | head -n1
    fi
}

status_json() {
    load_manager || { json_error "DNS Manager недоступен"; return; }
    [ -s "$DNS_CATALOG" ] || write_catalogs >/dev/null 2>&1 || true
    printf '{"ok":true,"manager_version":'; json_quote "$(manager_version)"
    printf ',"ipv4":'; json_quote "${IPV4_ROUTE:-unknown}"
    printf ',"ipv6":'; json_quote "${IPV6_ROUTE:-unknown}"
    printf ',"dnsmasq":'; json_quote "${DNSMASQ_RUN:-unknown}"
    printf ',"doh":'; json_quote "${HDP_RUNNING:-unknown}"
    printf ',"firewall":'; json_quote "${SYS_FW:-unknown}"
    printf ',"openwrt":'; json_quote "${SYS_OWRT:-unknown}"
    printf ',"lan":'; json_quote "${LAN_IP:-unknown}"
    printf ',"profile":'; json_quote "${DNS_PROFILE:-unknown}"
    printf ',"profile_mode":'; json_quote "${DNS_SELECTION_MODE:-unknown}"
    printf ',"watchdog":'; json_quote "${WATCHDOG_ENABLED:-0}"
    _force_cfg="$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null || true)"
    _force_external=0
    [ "$_force_cfg" = 1 ] && [ "${FORCE_DOH:-0}" != 1 ] && _force_external=1
    printf ',"force":'; json_quote "${FORCE_DOH:-0}"
    printf ',"force_external":'; json_quote "$_force_external"
    printf ',"mtu":'; json_quote "${MTU_FIX:-0}"
    printf ',"sysctl":'; json_quote "${SYSCTL_TUNING:-0}"
    printf ',"sysctl_ext":'; json_quote "${SYSCTL_EXTENDED:-0}"
    printf ',"ntp_clients":'; json_quote "${NTP_CLIENTS:-0}"
    printf ',"dnsmasq_perf":'; json_quote "${DNSMASQ_PERF:-0}"
    printf ',"client_fixes":'; json_quote "${CLIENT_FIXES:-0}"
    printf ',"watchdog_interval":'; json_quote "${WATCHDOG_INTERVAL:-90}"
    printf ',"doh_total":${DOH_TOTAL:-0},"doh_match":${DOH_MATCH:-0},"average_ping":'; json_quote "$(average_selected_ping)"
    printf ',"last_full_test":'; json_quote "$(sed -n 's/^timestamp=//p' "$TEST_RESULTS_META" 2>/dev/null | head -n1)"
    printf ',"hostname":'; json_quote "$(uci -q get system.@system[0].hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || true)"
    printf ',"uptime":'; json_quote "$(awk '{printf "%s",int($1)}' /proc/uptime 2>/dev/null)"
    printf ',"load1":'; json_quote "$(awk '{printf "%s",$1}' /proc/loadavg 2>/dev/null)"
    printf ',"memory_total_kb":'; printf '%s' "$(awk '/MemTotal:/ {print $2;exit}' /proc/meminfo 2>/dev/null)"
    printf ',"memory_available_kb":'; printf '%s' "$(awk '/MemAvailable:/ {print $2;exit}' /proc/meminfo 2>/dev/null)"
    _catalog_total="$(grep -v '^#' "$DNS_CATALOG" 2>/dev/null | grep -c '^[^|][^|]*|' 2>/dev/null || printf 0)"
    printf ',"catalog_total":%s' "$_catalog_total"
    printf ',"hdp_version":'; json_quote "$(package_version https-dns-proxy)"
    printf ',"catalog_version":'; json_quote "$(dns_catalog_version 2>/dev/null || true)"
    printf ',"slots":['
    _first=1
    for _s in 1 2 3 4 5 6 RU RU_2; do
        eval "_id=\${SLOT_${_s}:-}"
        eval "_cat=\${SLOT_${_s}_CAT:-}"
        [ "$_first" = 1 ] || printf ','
        _first=0
        _name="$(dns_name "$_id" 2>/dev/null || true)"
        _r="$(result_for_id "$_id" 2>/dev/null || true)"
        _ms="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $4;exit}')"
        _st="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"
        printf '{"slot":'; json_quote "$_s"; printf ',"id":'; json_quote "$_id"; printf ',"name":'; json_quote "$_name"; printf ',"category":'; json_quote "$_cat"; printf ',"ping":'; json_quote "$_ms"; printf ',"status":'; json_quote "$_st"; printf ',"last_check":'; json_quote "$(last_check_for_id "$_id")"; printf '}'
    done
    printf ']}'
}

catalog_json() {
    INPUT="${INPUT:-}"
    load_manager || { json_error "DNS Manager недоступен"; return; }
    [ -s "$DNS_CATALOG" ] || write_catalogs >/dev/null 2>&1 || true
    [ -s "$DNS_CATALOG" ] || { json_error "Каталог DNS недоступен"; return; }

    _category="$(jget category)"
    _offset="$(jget offset)"
    _limit="$(jget limit)"
    _only_ok="$(jget only_ok)"
    case "$_offset" in ''|*[!0-9]*) _offset=0;; esac
    case "$_limit" in ''|*[!0-9]*) _limit=18;; esac
    [ "$_limit" -gt 48 ] && _limit=48
    [ -n "$_category" ] || _category="all"
    case "$_category" in
        all|bypass|security|privacy|adblock|family|clean|regional) ;;
        *) json_error "Неверная категория DNS"; return;;
    esac
    case "$_only_ok" in 1|0) ;; *) _only_ok=0;; esac

    _filtered="$TMP_ROOT/catalog-filtered.$$"
    _paged="$TMP_ROOT/catalog-page.$$"
    : > "$_filtered"
    : > "$_paged"
    while IFS='|' read -r _id _cat _prof _name _url _region _status; do
        case "$_id" in ''|\#*) continue;; esac
        if [ "$_category" != all ] && [ "$_cat" != "$_category" ]; then
            continue
        fi
        if [ "$_only_ok" = 1 ]; then
            _r="$(result_for_id "$_id" 2>/dev/null || true)"
            _st="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"
            [ "$_st" = OK ] || continue
        fi
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$_id" "$_cat" "$_prof" "$_name" "$_url" "$_region" "$_status" >> "$_filtered"
    done < "$DNS_CATALOG"

    _total="$(wc -l < "$_filtered" 2>/dev/null | tr -d ' ')"
    case "$_total" in ''|*[!0-9]*) _total=0;; esac
    if [ "$_total" -gt "$_offset" ]; then
        sed -n "$((_offset+1)),$((_offset+_limit))p" "$_filtered" > "$_paged" 2>/dev/null || true
    fi

    printf '{"ok":true,"version":'; json_quote "$(dns_catalog_version)"
    printf ',"category":'; json_quote "$_category"
    printf ',"offset":%s,"limit":%s,"total":%s,"servers":[' "$_offset" "$_limit" "$_total"
    _first=1
    while IFS='|' read -r _id _cat _prof _name _url _region _status; do
        [ -n "$_id" ] || continue
        [ "$_first" = 1 ] || printf ','
        _first=0
        _r="$(result_for_id "$_id" 2>/dev/null || true)"
        _ms="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $4;exit}')"
        _st="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"
        _last="$(last_check_for_id "$_id")"
        printf '{"id":'; json_quote "$_id"; printf ',"category":'; json_quote "$_cat"; printf ',"name":'; json_quote "$_name"; printf ',"url":'; json_quote "$_url"; printf ',"region":'; json_quote "$_region"; printf ',"catalog_status":'; json_quote "$_status"; printf ',"ping":'; json_quote "$_ms"; printf ',"status":'; json_quote "$_st"; printf ',"last_check":'; json_quote "$_last"; printf '}'
    done < "$_paged"
    printf ']}'
    rm -f "$_filtered" "$_paged" 2>/dev/null || true
}

set_check_stamp() {
    _id="$1"
    _ts="$2"
    case "$_id" in ''|*[!A-Za-z0-9_-]*) return 1;; esac
    printf '%s\n' "$_ts" > "$CHECK_DIR/$_id" 2>/dev/null
}

new_job_id() {
    printf '%s-%s' "$(date +%s)" "$$"
}

job_write() {
    _id="$1"; _key="$2"; _value="$3"
    mkdir -p "$JOB_DIR/$_id" 2>/dev/null || return 1
    printf '%s=%s\n' "$_key" "$_value" >> "$JOB_DIR/$_id/state" 2>/dev/null
}

job_start_test_all() {
    _jid="$(new_job_id)"
    mkdir -p "$JOB_DIR/$_jid" 2>/dev/null || { json_error "Не удалось создать задачу"; return; }
    : > "$JOB_DIR/$_jid/state"
    printf 'status=running\nstarted=%s\n' "$(date +%s)" > "$JOB_DIR/$_jid/state"
    (
        exec >>"$JOB_DIR/$_jid/output" 2>&1
        trap 'job_write "$_jid" status failed; job_write "$_jid" finished "$(date +%s)"; exit 1' INT TERM
        if load_manager && SILENT_APPLY=1 test_dns_catalog; then
            now="$(date +%s)"
            while IFS='|' read -r _id _cat _name _ms _st; do
                [ -n "$_id" ] && set_check_stamp "$_id" "$now"
            done < "$TEST_RESULTS"
            job_write "$_jid" status done
            job_write "$_jid" result ok
            job_write "$_jid" finished "$now"
        else
            job_write "$_jid" status failed
            job_write "$_jid" result fail
            job_write "$_jid" finished "$(date +%s)"
        fi
    ) &
    printf '{"ok":true,"job":'; json_quote "$_jid"; printf '}'
}

job_start_test_one() {
    _id="$1"
    case "$_id" in ''|*[!A-Za-z0-9_-]*) json_error "Неверный ID DNS"; return;; esac
    _jid="$(new_job_id)"
    mkdir -p "$JOB_DIR/$_jid" 2>/dev/null || { json_error "Не удалось создать задачу"; return; }
    : > "$JOB_DIR/$_jid/state"
    printf 'status=running\nstarted=%s\n' "$(date +%s)" > "$JOB_DIR/$_jid/state"
    (
        exec >>"$JOB_DIR/$_jid/output" 2>&1
        if load_manager; then
            q="$TMP_ROOT/dns_query.bin"
            if [ ! -s "$q" ]; then
                printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$q"
            fi
            _lock=0
            if acquire_test_lock; then
                _lock=1
                if test_one_dns "$_id"; then
                    _tmp="$TMP_ROOT/results.$$"
                    _stamp="$(date +%s)"
                    : > "$_tmp"
                    if [ -s "$TEST_RESULTS" ]; then
                        awk -F'|' -v id="$_id" '$1!=id {print}' "$TEST_RESULTS" > "$_tmp" 2>/dev/null || true
                    fi
                    cat "$TMP_DIR/t.$_id" >> "$_tmp" 2>/dev/null || true
                    mv "$_tmp" "$TEST_RESULTS" 2>/dev/null || true
                    save_persistent_test_results >/dev/null 2>&1 || true
                    set_check_stamp "$_id" "$_stamp"
                    release_test_lock || true
                    _lock=0
                    job_write "$_jid" status done
                job_write "$_jid" result ok
                    job_write "$_jid" finished "$_stamp"
                    exit 0
                fi
                release_test_lock || true
                _lock=0
            fi
        fi
        job_write "$_jid" status failed
        job_write "$_jid" result fail
        job_write "$_jid" finished "$(date +%s)"
    ) &
    printf '{"ok":true,"job":'; json_quote "$_jid"; printf '}'
}

job_json() {
    _jid="$1"
    case "$_jid" in ''|*[!A-Za-z0-9_-]*) json_error "Неверный job ID"; return;; esac
    _d="$JOB_DIR/$_jid"
    [ -d "$_d" ] || { json_error "Задача не найдена"; return; }
    _status="$(sed -n 's/^status=//p' "$_d/state" 2>/dev/null | tail -n1)"
    _started="$(sed -n 's/^started=//p' "$_d/state" 2>/dev/null | head -n1)"
    _finished="$(sed -n 's/^finished=//p' "$_d/state" 2>/dev/null | tail -n1)"
    _result="$(sed -n 's/^result=//p' "$_d/state" 2>/dev/null | tail -n1)"
    printf '{"ok":true,"job":'; json_quote "$_jid"; printf ',"status":'; json_quote "$_status"; printf ',"result":'; json_quote "$_result"; printf ',"started":'; json_quote "$_started"; printf ',"finished":'; json_quote "$_finished"
    printf ',"output":'; json_quote "$(tail -n 80 "$_d/output" 2>/dev/null || true)"; printf '}'
}

log_json() {
    _n="$1"
    case "$_n" in ''|*[!0-9]*) _n=80;; esac
    [ "$_n" -gt 300 ] && _n=300
    printf '{"ok":true,"log":'; json_quote "$(tail -n "$_n" /var/log/dns-manager.log 2>/dev/null || true)"; printf '}'
}

run_action() {
    _profile="$(jget profile)"
    case "${RPC_METHOD:-}" in
        set_profile)
            case "$_profile" in clean2) _profile=clean ;; bypass|clean|security|privacy|adblock|family|all) ;; *) json_error "Неверный профиль"; return;; esac
            load_manager || { json_error "DNS Manager недоступен"; return; }
            DNS_MANAGER_NO_UPDATE=1 SILENT_APPLY=1 HYBRID_SELECTION_QUIET=1 apply_profile_now "$_profile" >/dev/null 2>&1 && json_ok || json_error "Профиль не удалось применить"
            ;;
        set_slot)
            _slot="$(jget slot)"; _id="$(jget id)"
            case "$_slot" in 1|2|3|4|5|6|RU|RU_2) ;; *) json_error "Неверный слот"; return;; esac
            case "$_id" in ''|*[!A-Za-z0-9_-]*) json_error "Неверный DNS ID"; return;; esac
            load_manager || { json_error "DNS Manager недоступен"; return; }
            _cat="$(dns_cat "$_id" 2>/dev/null || true)"
            [ -n "$_cat" ] || { json_error "DNS не найден в каталоге"; return; }
            case "$_slot" in
              RU|RU_2) [ "$_cat" = regional ] || { json_error "Этот DNS нельзя поставить в региональный слот"; return; } ;;
              *) [ "$_cat" != regional ] || { json_error "Региональный DNS нельзя поставить в общий слот"; return; } ;;
            esac
            DNS_PROFILE=custom DNS_SELECTION_MODE=manual DNS_SELECTION_CATEGORY="$_cat"
            eval "SLOT_$_slot=\"$_id\""
            eval "SLOT_${_slot}_CAT=\"$_cat\""
            if [ "$_slot" = RU ] || [ "$_slot" = RU_2 ]; then DNS_SELECTION_CATEGORY=regional; fi
            sync_regional_dns_state >/dev/null 2>&1 || true
            SILENT_APPLY=1 CORE_ONLY=1 DNS_MANAGER_NO_UPDATE=1 apply_settings >/dev/null 2>&1 && json_ok || json_error "DNS не удалось применить"
            ;;
        set_setting)
            _name="$(jget name)"; _enabled="$(jget enabled)"
            case "$_enabled" in 0|1) ;; *) json_error "Неверное значение enabled"; return;; esac
            case "$_name" in watchdog|force|mtu|sysctl|sysctl_ext|ntp_clients|dnsmasq_perf|client_fixes) ;; *) json_error "Недопустимая настройка"; return;; esac
            load_manager || { json_error "DNS Manager недоступен"; return; }
            case "$_name" in
                watchdog) WATCHDOG_ENABLED="$_enabled"; SILENT_APPLY=1 apply_watchdog >/dev/null 2>&1 ;;
                force) FORCE_DOH="$_enabled"; SILENT_APPLY=1 apply_extras_now force >/dev/null 2>&1 ;;
                mtu) MTU_FIX="$_enabled"; SILENT_APPLY=1 apply_extras_now mtu >/dev/null 2>&1 ;;
                sysctl) SYSCTL_TUNING="$_enabled"; [ "$_enabled" = 1 ] && SYSCTL_EXTENDED=1 || SYSCTL_EXTENDED=0; SILENT_APPLY=1 apply_extras_now sysctl >/dev/null 2>&1 ;;
                sysctl_ext) SYSCTL_EXTENDED="$_enabled"; SILENT_APPLY=1 apply_extras_now sysctl_ext >/dev/null 2>&1 ;;
                ntp_clients) NTP_CLIENTS="$_enabled"; SILENT_APPLY=1 apply_extras_now ntp_clients >/dev/null 2>&1 ;;
                dnsmasq_perf) DNSMASQ_PERF="$_enabled"; SILENT_APPLY=1 apply_extras_now dnsmasq_perf >/dev/null 2>&1 ;;
                client_fixes) CLIENT_FIXES="$_enabled"; SILENT_APPLY=1 apply_extras_now client_fixes >/dev/null 2>&1 ;;
            esac
            [ "$?" -eq 0 ] && json_ok || json_error "Настройку не удалось изменить"
            ;;
        *) json_error "Недопустимый метод";;
    esac
}

action_json() {
    run_action
}

test_json() {
    case "${RPC_METHOD:-}" in
        test_all) job_start_test_all;;
        test_one) _id="$(jget id)"; job_start_test_one "$_id";;
        *) json_error "Недопустимый метод проверки";;
    esac
}

case "${1:-}" in
    list)
        printf '{"status":{},"catalog":{"category":"String","offset":0,"limit":0,"only_ok":0},"set_profile":{"profile":"String"},"set_slot":{"slot":"String","id":"String"},"set_setting":{"name":"String","enabled":0},"test_all":{},"test_one":{"id":"String"},"job":{"id":"String"},"log":{"lines":0}}\n'
        ;;
    call)
        case "${2:-}" in
            status) status_json;;
            catalog) INPUT="$(cat 2>/dev/null || true)"; catalog_json;;
            set_profile|set_slot|set_setting) INPUT="$(cat 2>/dev/null || true)"; RPC_METHOD="$2"; run_action;;
            test_all|test_one) INPUT="$(cat 2>/dev/null || true)"; RPC_METHOD="$2"; test_json;;
            job) INPUT="$(cat 2>/dev/null || true)"; job_json "$(jget id)";;
            log) INPUT="$(cat 2>/dev/null || true)"; log_json "$(jget lines)";;
            *) json_error "Недопустимый метод";;
        esac
        ;;
    *) exit 1;;
esac
EOF_RPC
    chmod 0755 "$RPC_PLUGIN"

    cat > "$VIEW_FILE" <<'EOF_JS'
'use strict';
'require view';
'require rpc';
'require ui';
'require dom';

var callStatus = rpc.declare({ object: 'dns_manager', method: 'status', expect: {} });
var callCatalog = rpc.declare({ object: 'dns_manager', method: 'catalog', params: ['category','offset','limit','only_ok'], expect: {} });
var callProfile = rpc.declare({ object: 'dns_manager', method: 'set_profile', params: ['profile'], expect: {} });
var callSlot = rpc.declare({ object: 'dns_manager', method: 'set_slot', params: ['slot', 'id'], expect: {} });
var callSetting = rpc.declare({ object: 'dns_manager', method: 'set_setting', params: ['name', 'enabled'], expect: {} });
var callTestAll = rpc.declare({ object: 'dns_manager', method: 'test_all', expect: {} });
var callTestOne = rpc.declare({ object: 'dns_manager', method: 'test_one', params: ['id'], expect: {} });
var callJob = rpc.declare({ object: 'dns_manager', method: 'job', params: ['id'], expect: {} });
var callLog = rpc.declare({ object: 'dns_manager', method: 'log', params: ['lines'], expect: {} });

var PROFILE = [
  ['bypass', 'Максимальный обход', '6 рабочих DNS + региональные слоты'],
  ['clean', 'Максимальная скорость', 'минимум фильтрации и лишних правил'],
  ['security', 'Максимальная безопасность', 'DNS с защитой от угроз'],
  ['privacy', 'Максимальная приватность', 'DNS с акцентом на приватность'],
  ['adblock', 'Блокировка рекламы', 'фильтрация рекламы и трекеров'],
  ['all', 'Выбор по категориям', 'смешанный набор из каталога']
];
var CATEGORY = [
  ['all','Все DNS'], ['bypass','Обход блокировок'], ['security','Безопасность'],
  ['privacy','Приватность'], ['adblock','Блокировка рекламы'], ['family','Семейный'],
  ['clean','Без фильтрации'], ['regional','Региональные']
];
var state = { category:'all', offset:0, limit:18, total:0, catalogLoaded:false };

function esc(s) {
  s = s == null ? '' : String(s);
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function humanTime(ts) {
  if (!ts) return '—';
  var n = Number(ts);
  if (!isFinite(n) || n <= 0) return '—';
  try { return new Date(n * 1000).toLocaleString(); } catch (e) { return '—'; }
}
function uptimeText(sec) {
  var n = Number(sec || 0);
  if (!isFinite(n) || n <= 0) return '—';
  var d = Math.floor(n / 86400); n %= 86400;
  var h = Math.floor(n / 3600); n %= 3600;
  var m = Math.floor(n / 60);
  return (d ? d + ' д ' : '') + h + ' ч ' + m + ' мин';
}
function profileName(p) {
  var x = PROFILE.filter(function(v){ return v[0] === p; })[0];
  return x ? x[1] : (p || '—');
}
function catName(c) {
  var x = CATEGORY.filter(function(v){ return v[0] === c; })[0];
  return x ? x[1] : (c || '—');
}
function ping(v) { return v && /^\d+$/.test(String(v)) ? esc(v + ' мс') : '—'; }
function stateText(v) {
  if (v === 'yes' || v === '1' || v === 'OK') return 'Работает';
  if (v === 'no' || v === '0') return 'ВЫКЛ';
  return v || '—';
}
function stateClass(v) {
  return (v === 'yes' || v === '1' || v === 'OK') ? 'ok' : (v === 'no' || v === '0' ? 'off' : 'warn');
}
function E2(tag, cls, text) { return E(tag, {'class':cls}, text == null ? '' : text); }
function btn(label, cls, fn) {
  var b = E('button', {'class':'cbi-button ' + (cls || 'cbi-button-neutral'), 'click':fn}, label);
  return b;
}
function card(title, value, sub, cls) {
  var c = E('div', {'class':'dm-card dm-stat ' + (cls || '')});
  c.appendChild(E2('div','dm-label',title));
  c.appendChild(E2('div','dm-value',value));
  if (sub) c.appendChild(E2('div','dm-sub',sub));
  return c;
}
function toast(msg, type) { ui.addNotification(null, E2('p','dm-toast ' + (type || 'info'),msg), 'info'); }
function memoryText(total, avail) {
  var t=Number(total||0), a=Number(avail||0);
  if (!t) return '—';
  var used=t-a;
  return Math.round(used/1024) + ' / ' + Math.round(t/1024) + ' МБ';
}
function insertStyle(root) {
  var css = '' +
  '.dm-wrap{max-width:1450px}.dm-hero{padding:22px 24px;border-radius:14px;margin-bottom:18px;background:linear-gradient(135deg,var(--background-color-high),var(--background-color-medium));border:1px solid var(--border-color-medium);box-shadow:0 6px 18px rgba(0,0,0,.08)}' +
  '.dm-hero h2{margin:0 0 5px;font-size:25px}.dm-muted{opacity:.68}.dm-toolbar{display:flex;gap:8px;flex-wrap:wrap;margin-top:14px}' +
  '.dm-section{margin:22px 0}.dm-section h3{margin:0 0 11px;font-size:19px}.dm-grid6{display:grid;grid-template-columns:repeat(6,minmax(130px,1fr));gap:10px}.dm-grid4{display:grid;grid-template-columns:repeat(4,minmax(200px,1fr));gap:12px}.dm-grid3{display:grid;grid-template-columns:repeat(3,minmax(230px,1fr));gap:12px}' +
  '.dm-card{background:var(--background-color-high);border:1px solid var(--border-color-medium);border-radius:13px;padding:15px;box-shadow:0 3px 10px rgba(0,0,0,.06);transition:transform .12s,box-shadow .12s}.dm-click{cursor:pointer}.dm-click:hover{transform:translateY(-1px);box-shadow:0 6px 15px rgba(0,0,0,.10)}.dm-click:active{transform:translateY(1px);box-shadow:inset 0 2px 6px rgba(0,0,0,.12)}' +
  '.dm-stat{min-height:76px}.dm-label{font-size:12px;opacity:.68}.dm-value{font-size:18px;font-weight:700;margin-top:5px}.dm-sub{font-size:12px;opacity:.68;margin-top:4px}.dm-component{min-height:100px}.dm-component-title{font-size:17px;font-weight:700}.dm-status{margin-top:7px;font-size:13px}.dm-status.ok{color:#16884b}.dm-status.warn{color:#b56b00}.dm-status.off{color:#b52f3c}' +
  '.dm-profile{min-height:105px}.dm-profile.active{outline:2px solid #2d7dd2;box-shadow:0 0 0 4px rgba(45,125,210,.11)}.dm-profile-title{font-size:17px;font-weight:700}.dm-profile-sub{font-size:13px;opacity:.7;margin-top:7px}.dm-slot{min-height:150px}.dm-slot-top{display:flex;justify-content:space-between;gap:8px;align-items:center}.dm-slot-num{font-size:15px;font-weight:700}.dm-slot-name{font-size:16px;font-weight:700;margin:10px 0 6px}.dm-meta{font-size:12px;line-height:1.6;opacity:.74}.dm-actions{display:flex;gap:7px;flex-wrap:wrap;margin-top:11px}' +
  '.dm-dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px;background:#999}.dm-dot.ok{background:#1a9850}.dm-dot.warn{background:#d48b00}.dm-dot.bad{background:#c83d4c}.dm-section-head{display:flex;justify-content:space-between;gap:10px;align-items:center;flex-wrap:wrap}.dm-filters{display:flex;gap:7px;flex-wrap:wrap}.dm-filter.active{box-shadow:0 0 0 2px #2d7dd2 inset}.dm-catalog-tools{display:flex;gap:8px;flex-wrap:wrap;align-items:center}.dm-catalog{display:grid;grid-template-columns:repeat(3,minmax(280px,1fr));gap:11px;margin-top:12px}.dm-dns-title{font-weight:700;font-size:16px}.dm-dns-cat{font-size:12px;opacity:.67;margin-top:4px}.dm-page{display:flex;justify-content:center;align-items:center;gap:8px;margin-top:13px}.dm-settings{display:grid;grid-template-columns:repeat(4,minmax(190px,1fr));gap:10px}.dm-setting{min-height:86px}.dm-setting-title{font-weight:700}.dm-log{white-space:pre-wrap;font:12px/1.5 monospace;max-height:390px;overflow:auto;background:#0e141a;color:#dbe4ec;border-radius:10px;padding:12px}.dm-job{white-space:pre-wrap;max-height:280px;overflow:auto;font:12px/1.5 monospace}.dm-empty{padding:22px;border:1px dashed var(--border-color-medium);border-radius:12px;text-align:center;opacity:.7}.dm-legend{display:flex;gap:14px;flex-wrap:wrap;font-size:12px;opacity:.73}.dm-inline{display:inline-flex;align-items:center;gap:6px}' +
  '@media(max-width:1100px){.dm-grid6{grid-template-columns:repeat(3,1fr)}.dm-grid4,.dm-settings{grid-template-columns:repeat(2,1fr)}.dm-grid3,.dm-catalog{grid-template-columns:repeat(2,minmax(230px,1fr))}}' +
  '@media(max-width:700px){.dm-grid6,.dm-grid4,.dm-grid3,.dm-catalog,.dm-settings{grid-template-columns:1fr}}';
  root.appendChild(E('style', {}, css));
}

function renderDashboard(root, st) {
  var d = root.querySelector('#dm-dashboard'); d.innerHTML='';
  d.appendChild(card('Профиль',profileName(st.profile),'текущая схема'));
  d.appendChild(card('DoH',stateText(st.doh),st.doh_total + ' секций'));
  d.appendChild(card('DNS',String(st.doh_match || st.doh_total || 0),'активных в схеме'));
  d.appendChild(card('Watchdog',st.watchdog === '1' ? 'Работает' : 'ВЫКЛ',(st.watchdog_interval || '90') + ' сек'));
  d.appendChild(card('Последняя проверка',humanTime(st.last_full_test),'полный каталог'));
  d.appendChild(card('Средний ping',st.average_ping ? st.average_ping + ' мс' : '—','выбранные DNS'));
}
function renderComponents(root, st) {
  var s=root.querySelector('#dm-components'); s.innerHTML='<h3>Компоненты</h3>';
  var g=E('div',{'class':'dm-grid4'});
  [
    ['dnsmasq','DNSMasq',stateText(st.dnsmasq)],
    ['doh','Защищённый DNS',stateText(st.doh)],
    ['watchdog','Watchdog',st.watchdog==='1'?'procd':'ВЫКЛ'],
    ['force','Принудительный DNS',st.force==='1'?'DNS Manager':((st.force_external==='1'||st.force_external===1)?'Внешний':'ВЫКЛ')],
    ['mtu','MTU / MSS',st.mtu==='1'?'ВКЛ':'ВЫКЛ'],
    ['cache','Кэш DNS',st.dnsmasq_perf==='1'?'ВКЛ':'ВЫКЛ'],
    ['ntp','NTP для клиентов',st.ntp_clients==='1'?'ВКЛ':'ВЫКЛ'],
    ['fix','Клиентские фиксы',st.client_fixes==='1'?'ВКЛ':'ВЫКЛ']
  ].forEach(function(x){
    var cls=(x[2]==='Работает'||x[2]==='procd'||x[2]==='DNS Manager'||x[2]==='ВКЛ')?'ok':(x[2]==='ВЫКЛ'?'off':'warn');
    var c=E2('div','dm-card dm-component');
    c.appendChild(E2('div','dm-component-title',x[1]));
    c.appendChild(E2('div','dm-status '+cls,'● '+x[2]));
    g.appendChild(c);
  });
  s.appendChild(g);
}
function renderSystem(root, st) {
  var s=root.querySelector('#dm-system'); s.innerHTML='<h3>Система</h3>';
  var g=E('div',{'class':'dm-grid6'});
  [
    ['Устройство',st.hostname || 'AX3000T'],
    ['OpenWrt',st.openwrt || '—'],
    ['Uptime',uptimeText(st.uptime)],
    ['Нагрузка',st.load1 || '—'],
    ['RAM',memoryText(st.memory_total_kb,st.memory_available_kb)],
    ['LAN',st.lan || '—']
  ].forEach(function(x){ g.appendChild(card(x[0],x[1])); });
  s.appendChild(g);
}

function renderVersions(root, st) {
  var s=root.querySelector('#dm-versions'); s.innerHTML='<h3>Версии</h3>';
  var g=E('div',{'class':'dm-grid3'});
  [['DNS Manager',st.manager_version||'—'],['https-dns-proxy',st.hdp_version||'—'],['Каталог DNS',st.catalog_version||'—']].forEach(function(x){g.appendChild(card(x[0],x[1],''));});
  s.appendChild(g);
}
function renderProfiles(root, st) {
  var s=root.querySelector('#dm-profiles'); s.innerHTML='<h3>Профили DNS</h3>';
  var g=E('div',{'class':'dm-grid3'});
  PROFILE.forEach(function(p){
    var c=E2('div','dm-card dm-click dm-profile'+(st.profile===p[0]?' active':''));
    c.appendChild(E2('div','dm-profile-title',p[1]));
    c.appendChild(E2('div','dm-profile-sub',p[2]));
    c.addEventListener('click',function(){ applyProfile(p[0],root); });
    g.appendChild(c);
  });
  s.appendChild(g);
}
function renderSlots(root, st) {
  var s=root.querySelector('#dm-slots'); s.innerHTML='';
  var head=E('div',{'class':'dm-section-head'},[E('h3',{},'Текущие DNS'),E('div',{'class':'dm-legend'},'Ping и время берутся из последней проверки; обновление страницы не запускает новый тест.')]);
  s.appendChild(head);
  var g=E('div',{'class':'dm-grid4'});
  (st.slots||[]).forEach(function(x){
    var ok=x.status==='OK';
    var c=E2('div','dm-card dm-slot');
    c.appendChild(E('div',{'class':'dm-slot-top'},[E2('span','dm-slot-num','SLOT '+x.slot),E2('span','dm-inline',''+(ok?'● Работает':(x.status||'Нет данных')))]));
    c.appendChild(E2('div','dm-slot-name',x.name||'Не выбран'));
    c.appendChild(E2('div','dm-meta','Категория: '+catName(x.category)+'\nPing: '+(x.ping ? x.ping+' мс':'—')+'\nПоследняя проверка: '+humanTime(x.last_check)));
    var a=E('div',{'class':'dm-actions'});
    a.appendChild(btn('Выбрать','cbi-button-action',function(){openSlotPicker(x.slot,root);}));
    if(x.id)a.appendChild(btn('Проверить','cbi-button-neutral',function(){testOne(x.id,root);}));
    c.appendChild(a);g.appendChild(c);
  });
  s.appendChild(g);
}
function renderCatalog(root, data) {
  var s=root.querySelector('#dm-catalog');
  s.innerHTML='';
  var head=E('div',{'class':'dm-section-head'});
  head.appendChild(E('h3',{},'Каталог DNS'));
  if(!state.catalogLoaded){
    head.appendChild(btn('Открыть каталог','cbi-button-neutral',function(){loadCatalog(root,true);}));
    s.appendChild(head);
    s.appendChild(E2('div','dm-empty','Каталог из 111 DNS загружается только после открытия, чтобы LuCI запускалась быстро.'));
    return;
  }
  var tools=E('div',{'class':'dm-catalog-tools'});
  CATEGORY.forEach(function(cat){
    var b=btn(cat[1],'cbi-button-neutral dm-filter'+(state.category===cat[0]?' active':''),function(){state.category=cat[0];state.offset=0;loadCatalog(root,false);});
    tools.appendChild(b);
  });
  head.appendChild(tools);
  s.appendChild(head);
  var count=E2('div','dm-muted','Показано '+((data.servers||[]).length)+' из '+(data.total||0)); s.appendChild(count);
  var g=E('div',{'class':'dm-catalog'});
  (data.servers||[]).forEach(function(d){
    var c=E2('div','dm-card');
    var dot=d.status==='OK'?'ok':(d.status?'bad':'warn');
    c.appendChild(E2('div','dm-dns-title','● '+d.name));
    c.appendChild(E2('div','dm-dns-cat',catName(d.category)));
    c.appendChild(E2('div','dm-meta','Ping: '+ping(d.ping)+'\nСтатус: '+(d.status||'—')+'\nПоследняя проверка: '+humanTime(d.last_check)));
    var a=E('div',{'class':'dm-actions'});
    a.appendChild(btn('Проверить','cbi-button-neutral',function(){testOne(d.id,root);}));
    a.appendChild(btn('Назначить','cbi-button-action',function(){openAssign(d.id,d.category,root);}));
    c.appendChild(a);g.appendChild(c);
  });
  s.appendChild(g);
  var page=E('div',{'class':'dm-page'});
  page.appendChild(btn('←','cbi-button-neutral',function(){if(state.offset>0){state.offset=Math.max(0,state.offset-state.limit);loadCatalog(root,false);}}));
  page.appendChild(E2('span','dm-muted',(Math.floor(state.offset/state.limit)+1)+' / '+Math.max(1,Math.ceil((data.total||0)/state.limit))));
  page.appendChild(btn('→','cbi-button-neutral',function(){if(state.offset+state.limit<(data.total||0)){state.offset+=state.limit;loadCatalog(root,false);}}));
  s.appendChild(page);
}
function renderSettings(root, st) {
  var s=root.querySelector('#dm-settings'); s.innerHTML='<h3>Настройки</h3>';
  var g=E('div',{'class':'dm-settings'});
  [
    ['watchdog','Watchdog','Фоновая проверка DNS',st.watchdog==='1'],
    ['force','Принудительный DNS','Перехват 53/DoT',st.force==='1'],
    ['mtu','MTU / MSS','Исправление сетевых параметров',st.mtu==='1'],
    ['sysctl','TCP / Conntrack','Системный тюнинг',st.sysctl==='1'],
    ['sysctl_ext','Расширенный sysctl','Дополнительный тюнинг',st.sysctl_ext==='1'],
    ['ntp_clients','NTP для клиентов','DHCP Option 42',st.ntp_clients==='1'],
    ['dnsmasq_perf','Кэш DNS','Параметры dnsmasq',st.dnsmasq_perf==='1'],
    ['client_fixes','Клиентские фиксы','Телеметрия / connectivity',st.client_fixes==='1']
  ].forEach(function(x){
    var c=E2('div','dm-card dm-setting');
    c.appendChild(E2('div','dm-setting-title',x[1]));
    c.appendChild(E2('div','dm-muted',x[2]));
    c.appendChild(btn(x[3]?'Выключить':'Включить',x[3]?'cbi-button-remove':'cbi-button-add',function(){setSetting(x[0],x[3]?0:1,root);}));
    g.appendChild(c);
  });
  s.appendChild(g);
}
function renderLog(root){
  var s=root.querySelector('#dm-log'); s.innerHTML='';
  var h=E('div',{'class':'dm-section-head'},[E('h3',{},'Журнал'),btn('Показать','cbi-button-neutral',function(){showLog(root);})]);
  s.appendChild(h);
  s.appendChild(E2('div','dm-empty','Журнал загружается только по запросу.'));
}

function paint(root,st,cat){
  renderDashboard(root,st);renderComponents(root,st);renderSystem(root,st);renderVersions(root,st);renderProfiles(root,st);renderSlots(root,st);renderCatalog(root,cat||{});renderSettings(root,st);renderLog(root);
}
function baseRoot(){
  var root=E('div',{'class':'dm-wrap'});
  root.appendChild(E('div',{'class':'dm-hero'},[
    E('h2',{},_('DNS Manager')),
    E2('div','dm-muted','Нативный интерфейс LuCI · основной /usr/bin/dns-manager остаётся авторитетным backend.'),
    E('div',{'class':'dm-toolbar'},[
      btn('Обновить','cbi-button-neutral',function(){refresh(root);}),
      btn('Проверить все DNS','cbi-button-apply',function(){testAll(root);})
    ])
  ]));
  root.appendChild(E('div',{'class':'dm-grid6','id':'dm-dashboard'}));
  ['dm-components','dm-system','dm-versions','dm-profiles','dm-slots','dm-catalog','dm-settings','dm-job','dm-log'].forEach(function(id){root.appendChild(E('section',{'class':'dm-section','id':id}));});
  insertStyle(root);
  return root;
}
function refresh(root){
  return callStatus().then(function(st){
    paint(root,st||{},state.catalogLoaded ? window.dmCatalog : null);
    if(state.catalogLoaded) loadCatalog(root,false);
  }).catch(function(e){toast('Не удалось обновить DNS Manager','error');});
}
function loadCatalog(root,first){
  if(first){state.catalogLoaded=true;state.offset=0;}
  return callCatalog(state.category,state.offset,state.limit,0).then(function(data){window.dmCatalog=data||{};renderCatalog(root,window.dmCatalog);}).catch(function(){toast('Не удалось загрузить каталог DNS','error');});
}
function applyProfile(name,root){
  if(!confirm('Применить профиль «'+profileName(name)+'»?'))return;
  callProfile(name).then(function(r){if(r&&r.ok){toast('Профиль применён','success');refresh(root);}else toast((r&&r.error)||'Профиль не применён','error');});
}
function setSetting(name,enabled,root){
  if(!confirm((enabled?'Включить ':'Выключить ')+name+'?'))return;
  callSetting(name,enabled).then(function(r){if(r&&r.ok){toast('Настройка изменена','success');refresh(root);}else toast((r&&r.error)||'Настройку изменить не удалось','error');});
}
function assign(id,slot,root){
  if(!confirm('Назначить DNS «'+id+'» в '+slot+' и применить?'))return;
  callSlot(slot,id).then(function(r){if(r&&r.ok){toast('DNS назначен в '+slot,'success');refresh(root);}else toast((r&&r.error)||'DNS не удалось применить','error');});
}
function openAssign(id,cat,root){
  var slots=cat==='regional'?['RU','RU_2']:['1','2','3','4','5','6'];
  var modal=E('div',{},[E('h3',{},'Назначить DNS')]);
  slots.forEach(function(slot){modal.appendChild(btn(slot,'cbi-button-neutral',function(){ui.hideModal();assign(id,slot,root);}));});
  ui.showModal('DNS Manager',[modal,E('div',{'class':'right'},[btn('Отмена','cbi-button-negative',ui.hideModal)])]);
}
function openSlotPicker(slot,root){
  var regional=slot==='RU'||slot==='RU_2';
  callCatalog(regional?'regional':'all',0,48,0).then(function(data){
    var rows=(data.servers||[]).filter(function(x){return regional?x.category==='regional':x.category!=='regional';});
    var sel=E('select',{'class':'cbi-input-select'});
    rows.forEach(function(x){sel.appendChild(E('option',{value:x.id},x.name+' — '+catName(x.category)+(x.ping?' — '+x.ping+' мс':'')));});
    ui.showModal('DNS Manager',[E('div',{},[E('h3',{},'Выбор DNS для '+slot),sel]),E('div',{'class':'right'},[btn('Отмена','cbi-button-negative',ui.hideModal),btn('Применить','cbi-button-apply',function(){var id=sel.value;ui.hideModal();assign(id,slot,root);})])]);
  });
}
function testAll(root){
  callTestAll().then(function(r){if(r&&r.ok)watchJob(r.job,root);else toast((r&&r.error)||'Не удалось запустить проверку','error');});
}
function testOne(id,root){
  callTestOne(id).then(function(r){if(r&&r.ok)watchJob(r.job,root);else toast((r&&r.error)||'Не удалось запустить проверку','error');});
}
function watchJob(job,root){
  var box=root.querySelector('#dm-job');var ticks=0;
  box.innerHTML='<h3>Проверка</h3>';
  var out=E2('div','dm-card dm-job','Запущено…');box.appendChild(out);
  function poll(){
    callJob(job).then(function(r){out.textContent=(r.output||'')+'\n\nСтатус: '+(r.status||'—');if(r.status==='done'||r.status==='failed'||ticks++>120){refresh(root);return;}setTimeout(poll,1200);});
  }
  poll();
}
function showLog(root){
  callLog(160).then(function(r){var s=root.querySelector('#dm-log');s.innerHTML='<h3>Журнал DNS Manager</h3>';s.appendChild(E2('div','dm-log',r.log||''));});
}

return view.extend({
  load:function(){ return callStatus().then(function(st){return [st||{},null];}); },
  render:function(data){ var root=baseRoot(); var st=data[0]||{}; window.dmCatalog=null; paint(root,st,null); return root; }
});
EOF_JS
    chmod 0644 "$MENU_FILE" "$ACL_FILE" "$VIEW_FILE"

    # Remove remnants of the former DNS Manager ttyd launcher only when that
    # exact old controller belongs to DNS Manager. The ttyd package/config is
    # never touched by this companion installer.
    if [ -f /usr/lib/lua/luci/controller/dns_manager.lua ] && grep -q 'module("luci.controller.dns_manager"' /usr/lib/lua/luci/controller/dns_manager.lua 2>/dev/null && grep -q 'redirect_to_ttyd' /usr/lib/lua/luci/controller/dns_manager.lua 2>/dev/null; then
        rm -f /usr/lib/lua/luci/controller/dns_manager.lua
    fi
    rm -rf /tmp/luci-* /tmp/luci-indexcache* /tmp/luci-modulecache* 2>/dev/null || true

    [ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload >/dev/null 2>&1 || true
    say "DNS Manager LuCI $VERSION установлен."
    say "Меню: LuCI → Службы → DNS Manager"
}

uninstall_files() {
    rm -f "$RPC_PLUGIN" "$ACL_FILE" "$MENU_FILE" "$VIEW_FILE" 2>/dev/null || true
    rm -rf "$VIEW_DIR" "$RUNTIME_DIR" "$BACKUP_DIR" 2>/dev/null || true
    if [ -f /usr/lib/lua/luci/controller/dns_manager.lua ] && grep -q 'module("luci.controller.dns_manager"' /usr/lib/lua/luci/controller/dns_manager.lua 2>/dev/null && grep -q 'redirect_to_ttyd' /usr/lib/lua/luci/controller/dns_manager.lua 2>/dev/null; then
        rm -f /usr/lib/lua/luci/controller/dns_manager.lua
    fi
    rm -rf /tmp/luci-* /tmp/luci-indexcache* /tmp/luci-modulecache* 2>/dev/null || true
    [ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload >/dev/null 2>&1 || true
    say "DNS Manager LuCI удалён. Основной /usr/bin/dns-manager не изменён."
}

case "${1:-install}" in
    install|update)
        install_files
        ;;
    remove|uninstall)
        uninstall_files
        ;;
    version)
        say "$VERSION"
        ;;
    *)
        err "Использование: $0 [install|update|remove|version]"
        exit 2
        ;;
esac
