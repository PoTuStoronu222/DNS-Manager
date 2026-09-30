#!/bin/sh
# DNS Manager LuCI companion
# Version: 0.1
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
VERSION="0.2"

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
    write_catalogs >/dev/null 2>&1 || return 1
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

status_json() {
    load_manager || { json_error "DNS Manager недоступен"; return; }
    printf '{"ok":true,"manager_version":'; json_quote "$(manager_version)"
    printf ',"ipv4":'; json_quote "${IPV4_ROUTE:-unknown}"
    printf ',"ipv6":'; json_quote "${IPV6_ROUTE:-unknown}"
    printf ',"dnsmasq":'; json_quote "${DNSMASQ_RUN:-unknown}"
    printf ',"doh":'; json_quote "${HDP_RUNNING:-unknown}"
    printf ',"firewall":'; json_quote "${SYS_FW:-unknown}"
    printf ',"profile":'; json_quote "${DNS_PROFILE:-unknown}"
    printf ',"profile_mode":'; json_quote "${DNS_SELECTION_MODE:-unknown}"
    printf ',"watchdog":'; json_quote "${WATCHDOG_ENABLED:-0}"
    printf ',"force":'; json_quote "${FORCE_DOH:-0}"
    printf ',"mtu":'; json_quote "${MTU_FIX:-0}"
    printf ',"sysctl":'; json_quote "${SYSCTL_TUNING:-0}"
    printf ',"sysctl_ext":'; json_quote "${SYSCTL_EXTENDED:-0}"
    printf ',"ntp_clients":'; json_quote "${NTP_CLIENTS:-0}"
    printf ',"dnsmasq_perf":'; json_quote "${DNSMASQ_PERF:-0}"
    printf ',"client_fixes":'; json_quote "${CLIENT_FIXES:-0}"
    printf ',"watchdog_interval":'; json_quote "${WATCHDOG_INTERVAL:-90}"
    printf ',"doh_total":${DOH_TOTAL:-0},"doh_match":${DOH_MATCH:-0},"average_ping":'; json_quote "$(average_selected_ping)"
    printf ',"last_full_test":'; json_quote "$(sed -n 's/^timestamp=//p' "$TEST_RESULTS_META" 2>/dev/null | head -n1)"
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
    load_manager || { json_error "DNS Manager недоступен"; return; }
    printf '{"ok":true,"version":'; json_quote "$(dns_catalog_version)"; printf ',"servers":['
    _first=1
    while IFS='|' read -r _id _cat _prof _name _url _region _status; do
        case "$_id" in ''|\#*) continue;; esac
        [ "$_first" = 1 ] || printf ','
        _first=0
        _r="$(result_for_id "$_id" 2>/dev/null || true)"
        _ms="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $4;exit}')"
        _st="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"
        _last="$(last_check_for_id "$_id")"
        printf '{"id":'; json_quote "$_id"; printf ',"category":'; json_quote "$_cat"; printf ',"name":'; json_quote "$_name"; printf ',"url":'; json_quote "$_url"; printf ',"region":'; json_quote "$_region"; printf ',"catalog_status":'; json_quote "$_status"; printf ',"ping":'; json_quote "$_ms"; printf ',"status":'; json_quote "$_st"; printf ',"last_check":'; json_quote "$_last"; printf '}'
    done < "$DNS_CATALOG"
    printf ']}'
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
        printf '{"status":{},"catalog":{},"set_profile":{"profile":"String"},"set_slot":{"slot":"String","id":"String"},"set_setting":{"name":"String","enabled":0},"test_all":{},"test_one":{"id":"String"},"job":{"id":"String"},"log":{"lines":0}}\n'
        ;;
    call)
        case "${2:-}" in
            status) status_json;;
            catalog) catalog_json;;
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
var callCatalog = rpc.declare({ object: 'dns_manager', method: 'catalog', expect: {} });
var callProfile = rpc.declare({ object: 'dns_manager', method: 'set_profile', params: ['profile'], expect: {} });
var callSlot = rpc.declare({ object: 'dns_manager', method: 'set_slot', params: ['slot', 'id'], expect: {} });
var callSetting = rpc.declare({ object: 'dns_manager', method: 'set_setting', params: ['name', 'enabled'], expect: {} });
var callTestAll = rpc.declare({ object: 'dns_manager', method: 'test_all', expect: {} });
var callTestOne = rpc.declare({ object: 'dns_manager', method: 'test_one', params: ['id'], expect: {} });
var callJob = rpc.declare({ object: 'dns_manager', method: 'job', params: ['id'], expect: {} });
var callLog = rpc.declare({ object: 'dns_manager', method: 'log', params: ['lines'], expect: {} });

var PROFILE = [
  ['bypass', 'Максимальный обход', '6 DNS + региональный маршрут', 'var(--warn)'],
  ['clean', 'Максимальная скорость', 'чистый DNS без фильтрации', 'var(--ok)'],
  ['clean2', 'Чистый DNS', 'без специальных фильтров DNS', 'var(--ok)'],
  ['security', 'Максимальная безопасность', 'защита от угроз', 'var(--blue)'],
  ['privacy', 'Максимальная приватность', 'минимизация лишних фильтров', 'var(--violet)'],
  ['adblock', 'Блокировка рекламы', 'DNS-фильтрация рекламы', 'var(--red)'],
  ['family', 'Семейная фильтрация', 'фильтрация семейного профиля', 'var(--pink)'],
  ['all', 'Все категории', 'смешанный набор по категориям', 'var(--cyan)']
];

function esc(s) {
  s = s == null ? '' : String(s);
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
function humanTime(ts) {
  if (!ts) return '—';
  var n = Number(ts);
  if (!isFinite(n) || n <= 0) return '—';
  try { return new Date(n * 1000).toLocaleString(); } catch (e) { return '—'; }
}
function pingValue(v) {
  return v && /^\d+$/.test(String(v)) ? esc(v + ' мс') : '—';
}
function profileName(p) {
  var m = PROFILE.filter(function(x) { return x[0] === p; })[0];
  return m ? m[1] : (p || '—');
}
function catName(c) {
  return ({ bypass: 'Обход блокировок', security: 'Безопасность', privacy: 'Приватность', adblock: 'Реклама', family: 'Семейный', clean: 'Без фильтрации', regional: 'Региональные' })[c] || c || '—';
}
function stateBadge(v) {
  if (v === 'yes' || v === '1' || v === 'OK') return '<span class="badge ok">● Работает</span>';
  if (v === 'no' || v === '0') return '<span class="badge off">● Выкл.</span>';
  return '<span class="badge warn">● Нет данных</span>';
}
function toast(msg, type) {
  ui.addNotification(null, E('p', { 'class': 'dns-toast ' + (type || 'info') }, msg), 'info');
}
function el(tag, cls, html) {
  return E(tag, { 'class': cls }, html);
}

function renderStyle() {
  return '<style>' +
    ':root{--ok:#159957;--warn:#d89000;--blue:#2878d8;--violet:#7a55c7;--red:#c33b45;--pink:#c65386;--cyan:#198da2}' +
    '.dns-wrap{max-width:1400px}.dns-head{padding:20px 22px;margin-bottom:18px;border-radius:14px;background:linear-gradient(135deg,#1d2733,#111820);color:#fff;box-shadow:0 8px 20px rgba(0,0,0,.18)}' +
    '.dns-head h2{margin:0 0 6px}.dns-sub{opacity:.8}.dns-dashboard{display:grid;grid-template-columns:repeat(6,minmax(130px,1fr));gap:10px;margin:15px 0}.dns-stat{padding:13px;border-radius:12px;background:var(--background-color-high);border:1px solid var(--border-color-medium);box-shadow:inset 0 1px 0 rgba(255,255,255,.45),0 3px 8px rgba(0,0,0,.06)}.dns-stat b{display:block;font-size:18px;margin-top:4px}.dns-section{margin:20px 0}.dns-section h3{margin-bottom:10px}.dns-profiles{display:grid;grid-template-columns:repeat(3,minmax(220px,1fr));gap:12px}.dns-card,.dns-profile{position:relative;padding:16px;border:1px solid var(--border-color-medium);border-radius:14px;background:var(--background-color-high);box-shadow:0 5px 12px rgba(0,0,0,.08),inset 0 1px 0 rgba(255,255,255,.55);transition:.12s}.dns-card.clickable,.dns-profile{cursor:pointer}.dns-card.clickable:hover,.dns-profile:hover{transform:translateY(-1px);box-shadow:0 7px 15px rgba(0,0,0,.12),inset 0 1px 0 rgba(255,255,255,.55)}.dns-card.clickable:active,.dns-profile:active{transform:translateY(1px);box-shadow:inset 0 3px 7px rgba(0,0,0,.14)}.dns-profile-title{font-size:17px;font-weight:700;margin-bottom:5px}.dns-profile-desc{font-size:13px;opacity:.72}.dns-slots{display:grid;grid-template-columns:repeat(4,minmax(230px,1fr));gap:12px}.dns-slot-title{display:flex;justify-content:space-between;align-items:center;font-weight:700}.dns-slot-name{font-size:16px;margin:7px 0}.dns-meta{font-size:12px;opacity:.72;line-height:1.55}.dns-actions{display:flex;gap:7px;flex-wrap:wrap;margin-top:11px}.dns-actions button{cursor:pointer}.dns-catalog{display:grid;grid-template-columns:repeat(3,minmax(280px,1fr));gap:12px}.dns-dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;background:#888}.dns-dot.ok{background:var(--ok);box-shadow:0 0 0 3px rgba(21,153,87,.15)}.dns-dot.bad{background:var(--red)}.dns-dot.na{background:#888}.badge{display:inline-block;padding:3px 8px;border-radius:999px;font-size:11px}.badge.ok{background:rgba(21,153,87,.12);color:var(--ok)}.badge.off{background:rgba(195,59,69,.12);color:var(--red)}.badge.warn{background:rgba(216,144,0,.12);color:var(--warn)}.dns-tools{display:flex;gap:8px;align-items:center;flex-wrap:wrap}.dns-muted{opacity:.7}.dns-log{white-space:pre-wrap;max-height:420px;overflow:auto;font:12px/1.5 monospace;padding:12px;border-radius:10px;background:#0e1319;color:#dce6ee}.dns-job{margin-top:8px}.dns-small{font-size:12px}.dns-row{display:flex;align-items:center;justify-content:space-between;gap:10px}.dns-empty{padding:25px;text-align:center;opacity:.7;border:1px dashed var(--border-color-medium);border-radius:12px}.dns-advanced{display:grid;grid-template-columns:repeat(4,minmax(180px,1fr));gap:10px}.dns-toggle{min-height:74px;cursor:pointer}.dns-toggle strong{display:block}.dns-catalog-head{display:flex;justify-content:space-between;gap:10px;align-items:center;margin-bottom:10px}' +
    '@media(max-width:1100px){.dns-dashboard{grid-template-columns:repeat(3,1fr)}.dns-profiles,.dns-slots,.dns-catalog{grid-template-columns:repeat(2,minmax(220px,1fr))}.dns-advanced{grid-template-columns:repeat(2,1fr)}}' +
    '@media(max-width:700px){.dns-dashboard,.dns-profiles,.dns-slots,.dns-catalog,.dns-advanced{grid-template-columns:1fr}}' +
  '</style>';
}

return view.extend({
  load: function() { return Promise.all([callStatus(), callCatalog()]); },

  render: function(data) {
    var self = this;
    var st = data[0] || {};
    var cat = data[1] || {};
    var root = E('div', { 'class': 'dns-wrap' });
    root.appendChild(E('div', { 'class': 'dns-head' }, [
      E('h2', {}, _('DNS Manager')),
      E('div', { 'class': 'dns-sub' }, _('Нативный интерфейс LuCI • основной DNS Manager остаётся неизменным')),
      E('div', { 'class': 'dns-tools' }, [
        E('button', { 'class': 'cbi-button cbi-button-neutral', 'click': function(){ self.refresh(root); } }, _('Обновить')),
        E('button', { 'class': 'cbi-button cbi-button-apply', 'click': function(){ self.testAll(root); } }, _('Проверить все DNS'))
      ])
    ]));
    root.appendChild(E('div', { 'class': 'dns-dashboard', 'id': 'dns-dashboard' }));
    root.appendChild(E('div', { 'class': 'dns-section', 'id': 'dns-profiles-section' }));
    root.appendChild(E('div', { 'class': 'dns-section', 'id': 'dns-slots-section' }));
    root.appendChild(E('div', { 'class': 'dns-section', 'id': 'dns-catalog-section' }));
    root.appendChild(E('div', { 'class': 'dns-section', 'id': 'dns-advanced-section' }));
    root.appendChild(E('div', { 'class': 'dns-section', 'id': 'dns-job-section' }));
    root.appendChild(E('div', { 'class': 'dns-section', 'id': 'dns-log-section' }));
    root.appendChild(E('div', { 'class': 'dns-style-holder', 'html': renderStyle() }));

    self.paint(root, st, cat);
    return root;
  },

  paint: function(root, st, cat) {
    var self = this;
    var dash = root.querySelector('#dns-dashboard');
    dash.innerHTML = '';
    [
      ['Профиль', profileName(st.profile)],
      ['DoH', st.doh === 'yes' ? 'Работает' : (st.doh || '—')],
      ['DNS-серверов', String(st.doh_match || st.doh_total || 0)],
      ['Watchdog', st.watchdog === '1' ? ('ВКЛ · ' + (st.watchdog_interval || '90') + ' c') : 'ВЫКЛ'],
      ['Последняя полная проверка', humanTime(st.last_full_test)],
      ['Средний ping', st.average_ping ? st.average_ping + ' мс' : '—']
    ].forEach(function(x){ dash.appendChild(el('div','dns-stat',[E('div',{'class':'dns-small dns-muted'},_(x[0])),E('b',{},x[1])])); });

    var ps = root.querySelector('#dns-profiles-section');
    ps.innerHTML = '<h3>' + _('Профили DNS') + '</h3>';
    var pg = E('div', {'class':'dns-profiles'});
    PROFILE.forEach(function(p){
      var c = el('div','dns-profile clickable');
      c.style.borderTop = '4px solid ' + p[3];
      c.appendChild(el('div','dns-profile-title',p[1]));
      c.appendChild(el('div','dns-profile-desc',p[2]));
      c.addEventListener('click', function(){ self.profile(p[0], root); });
      pg.appendChild(c);
    });
    ps.appendChild(pg);

    var ss = root.querySelector('#dns-slots-section');
    ss.innerHTML = '<h3>' + _('Текущие DNS-слоты') + '</h3>';
    var sg = E('div', {'class':'dns-slots'});
    (st.slots || []).forEach(function(s){
      var c = el('div','dns-card');
      var ok = s.status === 'OK';
      var dot = E('span', {'class':'dns-dot ' + (ok?'ok':(s.status?'bad':'na'))});
      var tt = E('div', {'class':'dns-slot-title'}, [E('span',{},'SLOT ' + s.slot), E('span',{},[dot, stateBadge(s.status)])]);
      c.appendChild(tt);
      c.appendChild(el('div','dns-slot-name',s.name || 'Не выбран'));
      c.appendChild(el('div','dns-meta',
        _('Категория: ') + catName(s.category) + '<br>' +
        _('Ping: ') + pingValue(s.ping) + '<br>' +
        _('Последняя проверка: ') + humanTime(s.last_check)));
      var a = E('div', {'class':'dns-actions'});
      a.appendChild(E('button', {'class':'cbi-button cbi-button-action', 'click': function(){ self.openSlotPicker(s.slot, root); }}, _('Выбрать')));
      if (s.id) a.appendChild(E('button', {'class':'cbi-button cbi-button-neutral', 'click': function(){ self.testOne(s.id, root); }}, _('Проверить')));
      c.appendChild(a); sg.appendChild(c);
    });
    ss.appendChild(sg);

    var cs = root.querySelector('#dns-catalog-section');
    cs.innerHTML = '<div class="dns-catalog-head"><h3>' + _('Каталог DNS') + '</h3><span class="dns-small dns-muted">' + esc(cat.version || '') + '</span></div>';
    var cg = E('div', {'class':'dns-catalog'});
    (cat.servers || []).forEach(function(d){
      var c = el('div','dns-card');
      var dotClass = d.status === 'OK' ? 'ok' : (d.status ? 'bad' : 'na');
      c.appendChild(el('div','dns-row', [E('div',{},[E('span',{'class':'dns-dot ' + dotClass}),E('b',{},d.name)]), el('span','dns-small dns-muted',catName(d.category))]));
      c.appendChild(el('div','dns-meta',
        _('Ping: ') + pingValue(d.ping) + '<br>' +
        _('Статус: ') + (d.status || '—') + '<br>' +
        _('Последняя проверка: ') + humanTime(d.last_check)));
      var a = E('div', {'class':'dns-actions'});
      a.appendChild(E('button', {'class':'cbi-button cbi-button-neutral', 'click': function(){ self.testOne(d.id, root); }}, _('Проверить')));
      ['1','2','3','4','5','6'].forEach(function(slot){
        if (d.category !== 'regional') {
          a.appendChild(E('button', {'class':'cbi-button cbi-button-small', 'click': function(){ self.setSlot(slot, d.id, root); }}, _('S') + slot));
        }
      });
      if (d.category === 'regional') {
        a.appendChild(E('button', {'class':'cbi-button cbi-button-small', 'click': function(){ self.setSlot('RU', d.id, root); }}, _('RU')));
        a.appendChild(E('button', {'class':'cbi-button cbi-button-small', 'click': function(){ self.setSlot('RU_2', d.id, root); }}, _('RU-2')));
      }
      c.appendChild(a); cg.appendChild(c);
    });
    cs.appendChild(cg);

    var as = root.querySelector('#dns-advanced-section');
    as.innerHTML = '<h3>' + _('Дополнительные функции') + '</h3>';
    var ag = E('div', {'class':'dns-advanced'});
    [
      ['watchdog','Watchdog','Фоновая автопроверка DNS', st.watchdog === '1'],
      ['force','Принудительный DNS','Перехват DNS-запросов на роутер', st.force === '1'],
      ['mtu','MTU / MSS','Исправление сетевых параметров', st.mtu === '1'],
      ['sysctl','TCP / Conntrack','Общий тюнинг сети', st.sysctl === '1'],
      ['sysctl_ext','Расширенный sysctl','Дополнительные TCP-параметры', st.sysctl_ext === '1'],
      ['ntp_clients','NTP для клиентов','DHCP Option 42 без принудительного перехвата', st.ntp_clients === '1'],
      ['dnsmasq_perf','Производительность DNS','DNS-кэш и параметры dnsmasq', st.dnsmasq_perf === '1'],
      ['client_fixes','Клиентские фиксы','Исправления для отдельных клиентов', st.client_fixes === '1']
    ].forEach(function(x){
      var c = el('div','dns-card dns-toggle');
      c.appendChild(el('div','dns-profile-title',x[1]));
      c.appendChild(el('div','dns-profile-desc',x[2]));
      c.appendChild(E('div', {'class':'dns-actions'}, [E('button', {'class':'cbi-button ' + (x[3]?'cbi-button-remove':'cbi-button-add'), 'click': function(){ self.setting(x[0], x[3] ? 0 : 1, root); }}, x[3] ? _('Выключить') : _('Включить'))]));
      ag.appendChild(c);
    });
    as.appendChild(ag);

    root.querySelector('#dns-job-section').innerHTML = '';
    root.querySelector('#dns-log-section').innerHTML = '<h3>' + _('Журнал DNS Manager') + '</h3>' + '<button class="cbi-button cbi-button-neutral">' + _('Показать последние строки') + '</button>';
    root.querySelector('#dns-log-section').querySelector('button').addEventListener('click', function(){ self.showLog(root); });
  },

  refresh: function(root) {
    var self = this;
    Promise.all([callStatus(), callCatalog()]).then(function(d){ self.paint(root, d[0] || {}, d[1] || {}); });
  },
  confirm: function(msg) { return confirm(msg); },
  profile: function(name, root) {
    var self = this;
    if (!self.confirm(_('Применить профиль «') + profileName(name) + _('»?\n\nDNS Manager выполнит обычное безопасное применение своей конфигурации.'))) return;
    callProfile(name).then(function(r){
      if (r && r.ok) { toast(_('Профиль применён'), 'success'); self.refresh(root); }
      else toast((r && r.error) || _('Профиль не применён'), 'error');
    });
  },
  setting: function(name, enabled, root) {
    var self = this;
    if (!self.confirm((enabled ? _('Включить') : _('Выключить')) + '?')) return;
    callSetting(name, enabled).then(function(r){
      if (r && r.ok) { toast(_('Настройка изменена'), 'success'); self.refresh(root); }
      else toast((r && r.error) || _('Не удалось изменить настройку'), 'error');
    });
  },
  setSlot: function(slot, id, root) {
    var self = this;
    if (!self.confirm(_('Назначить «') + id + _('» в ') + slot + _(' и применить DNS?'))) return;
    callSlot(slot, id).then(function(r){
      if (r && r.ok) { toast(_('DNS применён в слоте ') + slot, 'success'); self.refresh(root); }
      else toast((r && r.error) || _('Не удалось применить DNS'), 'error');
    });
  },
  openSlotPicker: function(slot, root) {
    var self = this;
    Promise.all([callCatalog()]).then(function(d){
      var cat = d[0] || {}, regional = slot === 'RU' || slot === 'RU_2';
      var rows = (cat.servers || []).filter(function(x){ return regional ? x.category === 'regional' : x.category !== 'regional'; });
      var opts = rows.map(function(x){ return E('option', {value:x.id}, x.name + ' — ' + catName(x.category) + ' — ' + pingValue(x.ping)); });
      var sel = E('select', {'class':'cbi-input-select'}); opts.forEach(function(o){ sel.appendChild(o); });
      var box = E('div', {style:'padding:18px'}, [E('h3',{},_('Выбор DNS для ') + slot), sel]);
      var dlg = ui.showModal(_('DNS Manager'), [box, E('div', {'class':'right'}, [E('button', {'class':'cbi-button cbi-button-negative', 'click':ui.hideModal}, _('Отмена')), E('button', {'class':'cbi-button cbi-button-apply', 'click':function(){ var v=sel.value; ui.hideModal(); self.setSlot(slot,v,root); }}, _('Применить'))])]);
      return dlg;
    });
  },
  testAll: function(root) {
    var self = this;
    callTestAll().then(function(r){
      if (!(r && r.ok)) { toast((r && r.error)||_('Не удалось запустить проверку'),'error'); return; }
      self.watchJob(r.job, root);
    });
  },
  testOne: function(id, root) {
    var self = this;
    callTestOne(id).then(function(r){
      if (!(r && r.ok)) { toast((r && r.error)||_('Не удалось запустить проверку'),'error'); return; }
      self.watchJob(r.job, root);
    });
  },
  watchJob: function(job, root) {
    var self = this, box = root.querySelector('#dns-job-section');
    var ticks = 0;
    function poll(){
      callJob(job).then(function(r){
        box.innerHTML = '<h3>' + _('Проверка') + '</h3><div class="dns-job dns-card"><b>' + esc(r.status||'—') + '</b><div class="dns-meta">' + esc((r.output||'').slice(-2000)) + '</div></div>';
        if (r.status === 'done' || r.status === 'failed' || ticks++ > 120) { self.refresh(root); return; }
        setTimeout(poll, 1500);
      });
    }
    poll();
  },
  showLog: function(root) {
    var box = root.querySelector('#dns-log-section');
    callLog(120).then(function(r){
      box.innerHTML = '<h3>' + _('Журнал DNS Manager') + '</h3><div class="dns-log">' + esc(r.log || '') + '</div>';
    });
  }
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
