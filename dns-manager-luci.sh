#!/bin/sh
# DNS Manager LuCI companion
# Version: 1.5.9
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
CONFIG_FILE="/etc/dns-manager/config/manager.conf"
STATE_FILE="/etc/dns-manager/config/luci-state.conf"
COMPANION_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager-luci.sh"
# Legacy update compatibility: admin/services/dns_manager
RUNTIME_UPDATE_STATE="$BACKUP_DIR/update.state"
VERSION_FILE="$BACKUP_DIR/version"
VERSION="1.5.9"

say() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

manager_version() {
    [ -r "$MANAGER" ] || return 1
    awk -F'"' '/^VERSION="/ { print $2; exit }' "$MANAGER" 2>/dev/null
}

manager_const_num() {
    _key="$1"
    _fallback="$2"
    case "$_key" in
        WATCHDOG_FAIL_THRESHOLD|WATCHDOG_REPAIR_COOLDOWN|WATCHDOG_GUARD_INTERVAL|WATCHDOG_MAX_REPAIRS|WATCHDOG_MAX_RESTARTS|WATCHDOG_MAX_CANDIDATES|WATCHDOG_RESTART_COOLDOWN) ;;
        *) printf "%s" "$_fallback"; return 0 ;;
    esac
    _v="$(sed -n "s/^${_key}=\\([0-9][0-9]*\\)$/\\1/p" "$MANAGER" 2>/dev/null | head -n1)"
    case "$_v" in
        ''|*[!0-9]*) printf "%s" "$_fallback" ;;
        *) printf "%s" "$_v" ;;
    esac
}

watchdog_service_running() {
    [ -x /etc/init.d/dns-watchdog ] && /etc/init.d/dns-watchdog running >/dev/null 2>&1
}
watchdog_service_enabled() {
    [ -x /etc/init.d/dns-watchdog ] && /etc/init.d/dns-watchdog enabled >/dev/null 2>&1
}
watchdog_loop_running() {
    for _p in /proc/[0-9]*; do
        [ -r "$_p/cmdline" ] || continue
        _cmd="$(tr '\000' ' ' < "$_p/cmdline" 2>/dev/null || true)"
        case "$_cmd" in
            *dns-manager*__watchdog-loop*) return 0 ;;
        esac
    done
    return 1
}

require_manager() {
    [ -x "$MANAGER" ] || { err "Не найден $MANAGER. Сначала установите DNS Manager."; return 1; }
    [ -n "$(manager_version 2>/dev/null || true)" ] || { err "Не удалось определить версию DNS Manager."; return 1; }
}

install_files() {
    require_manager || return 1

    command -v jsonfilter >/dev/null 2>&1 || say "ℹ jsonfilter не найден — используется встроенный обработчик RPC-параметров."
    mkdir -p "$VIEW_DIR" /usr/libexec/rpcd /usr/share/rpcd/acl.d /usr/share/luci/menu.d "$RUNTIME_DIR/checks" "$BACKUP_DIR" "$(dirname "$STATE_FILE")" || return 1
    rm -f "/etc/dns-manager/state/current-dns-test-summary.conf" 2>/dev/null || true

    cat > "$MENU_FILE" <<'EOF_MENU'
{
  "admin/services/dns-manager": {
    "title": "DNS Manager",
    "order": 71,
    "action": {
      "type": "alias",
      "path": "admin/services/dns-manager/dashboard"
    },
    "depends": {
      "acl": [ "luci-app-dns-manager" ]
    }
  },
  "admin/services/dns-manager/dashboard": {
    "title": "Дашборд",
    "order": 10,
    "action": { "type": "view", "path": "dns_manager/overview" }
  },
  "admin/services/dns-manager/doh": {
    "title": "DNS over HTTPS",
    "order": 20,
    "action": { "type": "view", "path": "dns_manager/overview" }
  },
  "admin/services/dns-manager/dns": {
    "title": "Текущие DNS",
    "order": 30,
    "action": { "type": "view", "path": "dns_manager/overview" }
  },
  "admin/services/dns-manager/profiles": {
    "title": "Профили",
    "order": 40,
    "action": { "type": "view", "path": "dns_manager/overview" }
  },
  "admin/services/dns-manager/settings": {
    "title": "Настройки",
    "order": 50,
    "action": { "type": "view", "path": "dns_manager/overview" }
  },
  "admin/services/dns-manager/catalog": {
    "title": "Каталог DNS",
    "order": 60,
    "action": { "type": "view", "path": "dns_manager/overview" }
  },
  "admin/services/dns-manager/test": {
    "title": "Проверка",
    "order": 70,
    "action": { "type": "view", "path": "dns_manager/overview" }
  },
  "admin/services/dns-manager/log": {
    "title": "Журнал",
    "order": 80,
    "action": { "type": "view", "path": "dns_manager/overview" }
  }
}
EOF_MENU

    cat > "$ACL_FILE" <<'EOF_ACL'
{
  "luci-app-dns-manager": {
    "description": "DNS Manager native LuCI interface",
    "read": {
      "ubus": {
        "dns_manager": [ "status", "catalog", "job", "log", "update_check", "update_check_job", "update_check_job_status" ]
      }
    },
    "write": {
      "ubus": {
        "dns_manager": [ "set_profile", "set_slot", "set_setting", "set_test_age", "test_all", "test_current", "test_one", "update", "update_manager", "update_hdp", "update_catalog", "update_all" ]
      }
    }
  }
}
EOF_ACL

    cat > "$RPC_PLUGIN" <<'EOF_RPC'
#!/bin/sh
# DNS Manager LuCI rpcd plugin
# Lightweight read path for dashboard; mutations and DNS tests use the
# authoritative /usr/bin/dns-manager backend through a strict allowlist.

MANAGER="/usr/bin/dns-manager"
MANAGER_PATH="$MANAGER"
CONFIG_FILE="/etc/dns-manager/config/manager.conf"
CATALOG_FILE="/etc/dns-manager/config/dns-catalog.conf"
STATE_DIR="/var/run/dns-manager"
PERSIST_STATE_DIR="/etc/dns-manager/state"
RUNTIME_DIR="/var/run/dns-manager-luci"
JOB_DIR="$RUNTIME_DIR/jobs"
CHECK_DIR="$RUNTIME_DIR/checks"
CURRENT_SLOT_RESULTS="$RUNTIME_DIR/current-slot-results.conf"
TMP_ROOT="$RUNTIME_DIR/tmp"
UPDATE_STATE="/etc/dns-manager-luci/update.state"
COMPANION_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager-luci.sh"
VERSION_FILE="/etc/dns-manager-luci/version"
VIEW_FILE="/www/luci-static/resources/view/dns_manager/overview.js"
SELF_VERSION="1.5.9"

umask 077
mkdir -p "$RUNTIME_DIR" "$JOB_DIR" "$CHECK_DIR" "$TMP_ROOT" 2>/dev/null || exit 1

json_quote() {
    _s="$1"
    _s=$(printf '%s' "$_s" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r/ /g; s/\t/\\t/g')
    printf '"%s"' "$_s"
}
json_error() { printf '{"ok":false,"error":'; json_quote "$1"; printf '}'; }
json_ok() { printf '{"ok":true}'; }

jget() {
    _key="$1"
    [ -n "${INPUT:-}" ] || return 0
    if command -v jsonfilter >/dev/null 2>&1; then
        printf %s "$INPUT" | jsonfilter -q -e "@.$_key" 2>/dev/null || true
        return 0
    fi
    # Minimal fallback for this RPC's controlled scalar arguments.
    # Allowed keys are fixed by the rpcd list/call dispatch below.
    printf '%s\n' "$INPUT" | sed -n \
        -e 's/.*"'"$_key"'"[[:space:]]*:[[:space:]]*"\([^"\\]*\)".*/\1/p' \
        -e 's/.*"'"$_key"'"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1
}

manager_version() {
    [ -r "$MANAGER" ] || return 1
    awk -F'"' '/^VERSION="/ { print $2; exit }' "$MANAGER" 2>/dev/null
}

manager_const_num() {
    _key="$1"
    _fallback="$2"
    case "$_key" in
        WATCHDOG_FAIL_THRESHOLD|WATCHDOG_REPAIR_COOLDOWN|WATCHDOG_GUARD_INTERVAL|WATCHDOG_MAX_REPAIRS|WATCHDOG_MAX_RESTARTS|WATCHDOG_MAX_CANDIDATES|WATCHDOG_RESTART_COOLDOWN) ;;
        *) printf '%s' "$_fallback"; return 0 ;;
    esac
    _v="$(sed -n "s/^${_key}=\([0-9][0-9]*\)$/\1/p" "$MANAGER" 2>/dev/null | head -n1)"
    case "$_v" in
        ''|*[!0-9]*) printf '%s' "$_fallback" ;;
        *) printf '%s' "$_v" ;;
    esac
}

watchdog_service_running() {
    [ -x /etc/init.d/dns-watchdog ] && /etc/init.d/dns-watchdog running >/dev/null 2>&1
}
watchdog_service_enabled() {
    [ -x /etc/init.d/dns-watchdog ] && /etc/init.d/dns-watchdog enabled >/dev/null 2>&1
}
watchdog_loop_running() {
    for _p in /proc/[0-9]*; do
        [ -r "$_p/cmdline" ] || continue
        _cmd="$(tr '\000' ' ' < "$_p/cmdline" 2>/dev/null || true)"
        case "$_cmd" in
            *dns-manager*__watchdog-loop*) return 0 ;;
        esac
    done
    return 1
}

cfg_get() {
    _key="$1"
    [ -r "$CONFIG_FILE" ] || return 0
    awk -v k="$_key" 'BEGIN { q=sprintf("%c",39) } index($0,k"=")==1 { v=substr($0,length(k)+2); sub(/^"/,"",v); sub(/"$/,"",v); sub("^" q,"",v); sub(q "$","",v); print v; exit }' "$CONFIG_FILE" 2>/dev/null
}

catalog_field() {
    _id="$1"; _n="$2"
    [ -r "$CATALOG_FILE" ] || return 1
    awk -F'|' -v id="$_id" -v n="$_n" '$1==id { if (n==2) print $2; else if (n==4) print $4; else if (n==5) print $5; exit }' "$CATALOG_FILE" 2>/dev/null
}

catalog_version() { sed -n 's/^# DNSCATVER=//p' "$CATALOG_FILE" 2>/dev/null | head -n1; }
catalog_revision() { sed -n 's/^# DNSCATREV=//p' "$CATALOG_FILE" 2>/dev/null | head -n1; }

read_installed_luci_version() {
    _v=""
    [ -r "$VERSION_FILE" ] && _v="$(sed -n 's/^version=//p' "$VERSION_FILE" 2>/dev/null | head -n1)"
    [ -n "$_v" ] || [ ! -r "/etc/dns-manager/config/luci-state.conf" ] || _v="$(sed -n 's/^version=//p' /etc/dns-manager/config/luci-state.conf 2>/dev/null | head -n1)"
    [ -n "$_v" ] || [ ! -r "$VIEW_FILE" ] || _v="$(sed -n 's|^// DNS Manager LuCI version: *||p' "$VIEW_FILE" 2>/dev/null | head -n1)"
    [ -n "$_v" ] || _v="$SELF_VERSION"
    printf '%s' "$_v"
}

version_gt() {
    _a="$1"; _b="$2"
    awk -F. -v a="$_a" -v b="$_b" 'BEGIN { split(a,A,"."); split(b,B,"."); for(i=1;i<=5;i++){ ai=(A[i]==""?0:A[i]+0); bi=(B[i]==""?0:B[i]+0); if(ai>bi){print 1;exit} if(ai<bi){print 0;exit} } print 0 }'
}

fetch_raw_url() {
    _out="$1"; _url="$2"
    rm -f "$_out" 2>/dev/null || true
    _cb="$(date +%s 2>/dev/null || printf 0)-$$"
    case "$_url" in
        *\?*) _fetch_url="$_url&_dmcb=$_cb" ;;
        *) _fetch_url="$_url?_dmcb=$_cb" ;;
    esac
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 4 --max-time 20 -o "$_out" "$_fetch_url" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 20 -O "$_out" "$_fetch_url" >/dev/null 2>&1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$_out" "$_fetch_url" >/dev/null 2>&1
    else
        return 1
    fi
    [ -s "$_out" ] || return 1
    [ "$(wc -c < "$_out" 2>/dev/null | tr -d ' ')" -le 600000 ] 2>/dev/null || return 1
    return 0
}

fetch_url() {
    _out="$1"
    rm -f "$_out" 2>/dev/null || true
    _api="https://api.github.com/repos/PoTuStoronu222/DNS-Manager/contents/dns-manager-luci.sh?ref=main"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 5 --max-time 30 -H 'Accept: application/vnd.github.raw+json' -H 'User-Agent: DNS-Manager-LuCI' -H 'Cache-Control: no-cache' -o "$_out" "$_api" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 30 --header='Accept: application/vnd.github.raw+json' --header='User-Agent: DNS-Manager-LuCI' --header='Cache-Control: no-cache' -O "$_out" "$_api" >/dev/null 2>&1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$_out" "${COMPANION_URL}?_dmcb=$(date +%s 2>/dev/null || printf 0)" >/dev/null 2>&1
    else
        return 1
    fi
    [ -s "$_out" ] || return 1
    [ "$(wc -c < "$_out" 2>/dev/null | tr -d ' ')" -le 250000 ] 2>/dev/null || return 1
    return 0
}

validate_candidate() {
    _f="$1"
    head -n1 "$_f" 2>/dev/null | grep -q '^#!/bin/sh$' || return 1
    grep -Fq '# DNS Manager LuCI companion' "$_f" 2>/dev/null || return 1
    grep -Fq '/usr/libexec/rpcd/dns_manager' "$_f" 2>/dev/null || return 1
    grep -Eq 'admin/services/dns-manager|admin/services/dns_manager' "$_f" 2>/dev/null || return 1
    grep -Fq '"update_check"' "$_f" 2>/dev/null || return 1
    grep -Fq 'Version:' "$_f" 2>/dev/null || return 1
    sh -n "$_f" >/dev/null 2>&1 || return 1
    return 0
}

update_check_json_luci() {
    _installed="$(read_installed_luci_version)"
    _tmp="$TMP_ROOT/companion-check.$$"
    if ! fetch_url "$_tmp"; then
        rm -f "$_tmp" 2>/dev/null || true
        _ts="$(date +%s 2>/dev/null || printf 0)"
        _state_tmp="$UPDATE_STATE.tmp.$$"
        if [ -r "$UPDATE_STATE" ]; then sed '/^installed=/d;/^latest=/d;/^available=/d;/^checked_at=/d;/^error=/d' "$UPDATE_STATE" > "$_state_tmp" 2>/dev/null || true; else : > "$_state_tmp"; fi
        printf 'installed=%s\nlatest=\navailable=0\nchecked_at=%s\nerror=%s\n' "$_installed" "$_ts" "Не удалось получить DNS Manager LuCI с GitHub" >> "$_state_tmp"
        mv "$_state_tmp" "$UPDATE_STATE" 2>/dev/null || rm -f "$_state_tmp" 2>/dev/null || true
        printf '{"ok":false,"installed_version":'; json_quote "$_installed"; printf ',"latest_version":"","available":false,"checked_at":%s,"error":' "$_ts"; json_quote "Не удалось получить DNS Manager LuCI с GitHub"; printf '}'
        return 0
    fi
    if ! validate_candidate "$_tmp"; then
        rm -f "$_tmp" 2>/dev/null || true
        _ts="$(date +%s 2>/dev/null || printf 0)"
        _state_tmp="$UPDATE_STATE.tmp.$$"
        if [ -r "$UPDATE_STATE" ]; then sed '/^installed=/d;/^latest=/d;/^available=/d;/^checked_at=/d;/^error=/d' "$UPDATE_STATE" > "$_state_tmp" 2>/dev/null || true; else : > "$_state_tmp"; fi
        printf 'installed=%s\nlatest=\navailable=0\nchecked_at=%s\nerror=%s\n' "$_installed" "$_ts" "Полученный файл DNS Manager LuCI не прошёл проверку" >> "$_state_tmp"
        mv "$_state_tmp" "$UPDATE_STATE" 2>/dev/null || rm -f "$_state_tmp" 2>/dev/null || true
        printf '{"ok":false,"installed_version":'; json_quote "$_installed"; printf ',"latest_version":"","available":false,"checked_at":%s,"error":' "$_ts"; json_quote "Полученный файл DNS Manager LuCI не прошёл проверку"; printf '}'
        return 0
    fi
    _latest="$(sed -n 's/^# Version:[[:space:]]*//p' "$_tmp" 2>/dev/null | head -n1)"
    _available=0
    [ -n "$_latest" ] && [ "$(version_gt "$_latest" "$_installed")" = 1 ] && _available=1
    _ts="$(date +%s 2>/dev/null || printf 0)"
    {
        printf 'installed=%s\n' "$_installed"
        printf 'latest=%s\n' "$_latest"
        printf 'available=%s\n' "$_available"
        printf 'checked_at=%s\n' "$_ts"
        printf 'error=\n'
    } > "${UPDATE_STATE}.tmp.$$" 2>/dev/null || true
    [ -s "${UPDATE_STATE}.tmp.$$" ] && mv "${UPDATE_STATE}.tmp.$$" "$UPDATE_STATE" 2>/dev/null || rm -f "${UPDATE_STATE}.tmp.$$" 2>/dev/null || true
    rm -f "$_tmp" 2>/dev/null || true
    printf '{"ok":true,"installed_version":'; json_quote "$_installed"; printf ',"latest_version":'; json_quote "$_latest"; printf ',"available":%s,"checked_at":%s}' "$_available" "$_ts"
}

component_update_check() {
    _ts="$(date +%s 2>/dev/null || printf 0)"
    _manager_installed="$(manager_version 2>/dev/null || true)"
    _manager_latest=""; _manager_available=0; _manager_ok=0
    _tmp="$TMP_ROOT/manager-check.$$"
    if [ -n "$_manager_installed" ] && fetch_raw_url "$_tmp" "https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager.sh?_dmcb=$_ts-$$"; then
        _manager_latest="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$_tmp" 2>/dev/null | head -n1)"
        [ -n "$_manager_latest" ] && _manager_ok=1
        [ -n "$_manager_latest" ] && [ "$(version_gt "$_manager_latest" "$_manager_installed")" = 1 ] && _manager_available=1
    fi
    rm -f "$_tmp" 2>/dev/null || true

    _catalog_latest=""; _catalog_latest_rev=""; _catalog_latest_total=0; _catalog_available=0; _catalog_ok=0
    _tmp="$TMP_ROOT/catalog-check.$$"
    if fetch_raw_url "$_tmp" "https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/catalogs/dns-8.5-RU-NOSOCIAL.conf?_dmcb=$_ts-$$"; then
        _catalog_latest="$(sed -n 's/^# DNSCATVER=//p' "$_tmp" 2>/dev/null | head -n1)"
        _catalog_latest_rev="$(sed -n 's/^# DNSCATREV=//p' "$_tmp" 2>/dev/null | head -n1)"
        _catalog_latest_total="$(grep -v '^#' "$_tmp" 2>/dev/null | grep -c '^[^|][^|]*|' 2>/dev/null || printf 0)"
        [ -n "$_catalog_latest" ] && _catalog_ok=1
        _local_rev="$(sed -n 's/^# DNSCATREV=//p' "$CATALOG_FILE" 2>/dev/null | head -n1)"
        _local_total="$(grep -v '^#' "$CATALOG_FILE" 2>/dev/null | grep -c '^[^|][^|]*|' 2>/dev/null || printf 0)"
        _catalog_same=0
        _remote_body="$TMP_ROOT/catalog-remote-body.$$"
        _local_body="$TMP_ROOT/catalog-local-body.$$"
        sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$_tmp" > "$_remote_body" 2>/dev/null || true
        if [ -r "$CATALOG_FILE" ]; then
            sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$CATALOG_FILE" > "$_local_body" 2>/dev/null || true
            if cmp -s "$_remote_body" "$_local_body" 2>/dev/null; then
                _catalog_same=1
            fi
        fi
        if [ "$_catalog_same" != 1 ]; then
            [ "$_catalog_latest" != "$(catalog_version)" ] && [ -n "$_catalog_latest" ] && _catalog_available=1
            [ -n "$_catalog_latest_rev" ] && [ "$_catalog_latest_rev" != "$_local_rev" ] && _catalog_available=1
            [ "$_catalog_latest_total" != "$_local_total" ] && _catalog_available=1
        else
            _catalog_available=0
        fi
        rm -f "$_remote_body" "$_local_body" 2>/dev/null || true
    fi
    rm -f "$_tmp" 2>/dev/null || true

    _hdp_installed="$(package_version https-dns-proxy 2>/dev/null || true)"
    _hdp_candidate="$(package_candidate_version https-dns-proxy 2>/dev/null || true)"
    _hdp_checked=0
    [ -n "$_hdp_installed" ] && _hdp_checked=1
    _hdp_available=0

    _state_tmp="$UPDATE_STATE.tmp.$$"
    if [ -r "$UPDATE_STATE" ]; then
        sed '/^manager_/d;/^catalog_/d;/^hdp_/d;/^components_checked_at=/d' "$UPDATE_STATE" > "$_state_tmp" 2>/dev/null || true
    else
        : > "$_state_tmp"
    fi
    printf 'manager_latest=%s\n' "$_manager_latest" >> "$_state_tmp"
    printf 'manager_available=%s\n' "$_manager_available" >> "$_state_tmp"
    printf 'manager_checked=%s\n' "$_manager_ok" >> "$_state_tmp"
    printf 'catalog_latest=%s\n' "$_catalog_latest" >> "$_state_tmp"
    printf 'catalog_latest_rev=%s\n' "$_catalog_latest_rev" >> "$_state_tmp"
    printf 'catalog_latest_total=%s\n' "$_catalog_latest_total" >> "$_state_tmp"
    printf 'catalog_available=%s\n' "$_catalog_available" >> "$_state_tmp"
    printf 'catalog_checked=%s\n' "$_catalog_ok" >> "$_state_tmp"
    printf 'hdp_latest=%s\n' "$_hdp_candidate" >> "$_state_tmp"
    printf 'hdp_available=%s\n' "$_hdp_available" >> "$_state_tmp"
    printf 'hdp_checked=%s\n' "$_hdp_checked" >> "$_state_tmp"
    printf 'components_checked_at=%s\n' "$_ts" >> "$_state_tmp"
    mv "$_state_tmp" "$UPDATE_STATE" 2>/dev/null || rm -f "$_state_tmp" 2>/dev/null || true
}

update_hdp_json() {
    if ! mkdir "$RUNTIME_DIR/hdp-update.lock" 2>/dev/null; then
        json_error "Обновление https-dns-proxy уже выполняется"; return
    fi
    trap 'rm -rf "$RUNTIME_DIR/hdp-update.lock" 2>/dev/null || true' EXIT INT TERM
    _installed="$(package_version https-dns-proxy 2>/dev/null || true)"
    _candidate="$(package_candidate_version https-dns-proxy 2>/dev/null || true)"
    [ -n "$_installed" ] || { json_error "https-dns-proxy не установлен"; return; }
    [ -n "$_candidate" ] || { json_error "Новой версии https-dns-proxy не найдено"; return; }
    if ! package_version_cmp "$_candidate" "$_installed"; then
        _state_tmp="$UPDATE_STATE.tmp.$"
        if [ -r "$UPDATE_STATE" ]; then
            sed '/^hdp_latest=/d;/^hdp_available=/d;/^hdp_checked=/d;/^components_checked_at=/d' "$UPDATE_STATE" > "$_state_tmp" 2>/dev/null || true
        else
            : > "$_state_tmp"
        fi
        _ts="$(date +%s 2>/dev/null || printf 0)"
        printf 'hdp_latest=%s\nhdp_available=0\nhdp_checked=1\ncomponents_checked_at=%s\n' "$_installed" "$_ts" >> "$_state_tmp"
        mv "$_state_tmp" "$UPDATE_STATE" 2>/dev/null || rm -f "$_state_tmp" 2>/dev/null || true
        json_error "Новой версии https-dns-proxy не найдено"; return
    fi
    if ! package_update_hdp; then
        json_error "https-dns-proxy не удалось обновить"; return
    fi
    _after="$(package_version https-dns-proxy 2>/dev/null || true)"
    [ -n "$_after" ] || { json_error "Не удалось определить версию после обновления"; return; }
    _state_tmp="$UPDATE_STATE.tmp.$"
    if [ -r "$UPDATE_STATE" ]; then
        sed '/^hdp_latest=/d;/^hdp_available=/d;/^hdp_checked=/d;/^components_checked_at=/d' "$UPDATE_STATE" > "$_state_tmp" 2>/dev/null || true
    else
        : > "$_state_tmp"
    fi
    _ts="$(date +%s 2>/dev/null || printf 0)"
    printf 'hdp_latest=%s\nhdp_available=0\nhdp_checked=1\ncomponents_checked_at=%s\n' "$_after" "$_ts" >> "$_state_tmp"
    mv "$_state_tmp" "$UPDATE_STATE" 2>/dev/null || rm -f "$_state_tmp" 2>/dev/null || true
    printf '{"ok":true,"updated":true,"version":'; json_quote "$_after"; printf '}'
}

update_catalog_json() {
    if ! mkdir "$RUNTIME_DIR/catalog-update.lock" 2>/dev/null; then
        json_error "Обновление каталога DNS уже выполняется"
        return
    fi
    _old_v="$(catalog_version 2>/dev/null || true)"
    _old_r="$(catalog_revision 2>/dev/null || true)"
    update_catalog_direct
    _rc=$?
    _new_v="$(catalog_version 2>/dev/null || true)"
    _new_r="$(catalog_revision 2>/dev/null || true)"
    rm -rf "$RUNTIME_DIR/catalog-update.lock" 2>/dev/null || true
    case "$_rc" in
        0)
            printf "{\"ok\":true,\"updated\":true,\"version\":"
            json_quote "$_new_v"
            printf ",\"revision\":"
            json_quote "$_new_r"
            printf "}"
            ;;
        2)
            printf "{\"ok\":true,\"updated\":false,\"version\":"
            json_quote "$_old_v"
            printf ",\"revision\":"
            json_quote "$_old_r"
            printf ",\"message\":"
            json_quote "Каталог DNS уже актуален"
            printf "}"
            ;;
        *) json_error "Каталог DNS не удалось обновить" ;;
    esac
}
update_check_json() {
    update_check_json_luci >/dev/null 2>&1 || true
    component_update_check || true
    status_json
}

maybe_background_update_check() {
    [ -d "$RUNTIME_DIR" ] || return 0
    _now="$(date +%s 2>/dev/null || printf 0)"
    _last="$(sed -n 's/^components_checked_at=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    case "$_last" in ''|*[!0-9]*) _last=0;; esac
    [ "$_now" -gt 0 ] || return 0
    [ $((_now - _last)) -ge 43200 ] || return 0
    mkdir "$RUNTIME_DIR/update-check.lock" 2>/dev/null || return 0
    (
        trap 'rm -rf "$RUNTIME_DIR/update-check.lock" 2>/dev/null || true' EXIT INT TERM
        update_check_json >/dev/null 2>&1 || true
    ) </dev/null >/dev/null 2>&1 &
}


update_manager_direct() {
    _installed="$(manager_version 2>/dev/null || true)"
    _out="$TMP_ROOT/manager-update-all.log"
    rm -f "$_out" 2>/dev/null || true
    ( update_manager_json ) >"$_out" 2>&1 || true
    _after="$(manager_version 2>/dev/null || true)"
    if [ -n "$_installed" ] && [ -n "$_after" ] && [ "$_after" != "$_installed" ]; then
        rm -f "$_out" 2>/dev/null || true
        return 0
    fi
    if grep -Eq "Новой версии|актуальна|не новее|текущая версия" "$_out" 2>/dev/null; then
        rm -f "$_out" 2>/dev/null || true
        return 2
    fi
    rm -f "$_out" 2>/dev/null || true
    return 3
}

update_hdp_direct() {
    _installed="$(package_version https-dns-proxy 2>/dev/null || true)"
    _out="$TMP_ROOT/hdp-update-all.log"
    rm -f "$_out" 2>/dev/null || true
    ( update_hdp_json ) >"$_out" 2>&1 || true
    _after="$(package_version https-dns-proxy 2>/dev/null || true)"
    if [ -n "$_installed" ] && [ -n "$_after" ] && [ "$_after" != "$_installed" ]; then
        rm -f "$_out" 2>/dev/null || true
        return 0
    fi
    if grep -Eq "Новой версии|актуален|не найдено" "$_out" 2>/dev/null; then
        rm -f "$_out" 2>/dev/null || true
        return 2
    fi
    rm -f "$_out" 2>/dev/null || true
    return 3
}
update_catalog_direct() {
    _tmp="$TMP_ROOT/catalog-update-all.$$"
    fetch_raw_url "$_tmp" "https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/catalogs/dns-8.5-RU-NOSOCIAL.conf" || { rm -f "$_tmp" 2>/dev/null || true; return 3; }
    _remote_ver="$(sed -n 's/^# DNSCATVER=//p' "$_tmp" 2>/dev/null | head -n1)"
    _remote_rev="$(sed -n 's/^# DNSCATREV=//p' "$_tmp" 2>/dev/null | head -n1)"
    _decl="$(sed -n 's/^# ENTRIES=//p' "$_tmp" 2>/dev/null | head -n1)"
    _count="$(grep -v '^[[:space:]]*#' "$_tmp" 2>/dev/null | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')"
    case "$_count" in ''|*[!0-9]*) _count=0;; esac
    [ -n "$_remote_ver" ] && [ -n "$_remote_rev" ] && [ "$_decl" = "$_count" ] && [ "$_count" -gt 0 ] || { rm -f "$_tmp" 2>/dev/null || true; return 4; }
    awk -F'|' '/^[[:space:]]*#/ || /^[[:space:]]*$/ {next} {if(NF!=7 || $1=="" || $4=="" || $5 !~ /^https:\/\//) bad=1; ids[$1]++; if(ids[$1]>1) bad=1; n++} END{if(bad || n<1) exit 1}' "$_tmp" >/dev/null 2>&1 || { rm -f "$_tmp" 2>/dev/null || true; return 4; }
    _rb="$TMP_ROOT/catalog-remote-all.$$"
    _lb="$TMP_ROOT/catalog-local-all.$$"
    sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$_tmp" > "$_rb" 2>/dev/null || true
    sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$CATALOG_FILE" > "$_lb" 2>/dev/null || true
    if cmp -s "$_rb" "$_lb" 2>/dev/null; then rm -f "$_tmp" "$_rb" "$_lb" 2>/dev/null || true; return 2; fi
    mv -f "$_tmp" "$CATALOG_FILE" 2>/dev/null || { rm -f "$_rb" "$_lb" 2>/dev/null || true; return 5; }
    chmod 600 "$CATALOG_FILE" 2>/dev/null || true
    rm -f "$_rb" "$_lb" 2>/dev/null || true
    return 0
}

update_luci_direct() {
    _installed="$(read_installed_luci_version)"
    _out="$TMP_ROOT/luci-update-all.log"
    rm -f "$_out" 2>/dev/null || true
    ( update_json ) >"$_out" 2>&1 || true
    _after="$(read_installed_luci_version)"
    if [ -n "$_installed" ] && [ -n "$_after" ] && [ "$_after" != "$_installed" ]; then
        rm -f "$_out" 2>/dev/null || true
        return 0
    fi
    if grep -Eq "Новой версии нет|Новой версии не|актуальна" "$_out" 2>/dev/null; then
        rm -f "$_out" 2>/dev/null || true
        return 2
    fi
    rm -f "$_out" 2>/dev/null || true
    return 3
}
append_update_message() {
    if [ -n "$_message" ]; then _message="$_message; $1"; else _message="$1"; fi
}

append_failure_message() {
    if [ -n "$_failed" ]; then _failed="$_failed; $1"; else _failed="$1"; fi
}

update_all_json() {
    if ! mkdir "$RUNTIME_DIR/update-all.lock" 2>/dev/null; then
        json_error "Обновление уже выполняется"
        return
    fi
    _message=""
    _failed=""

    _old_m="$(manager_version 2>/dev/null || true)"
    _mr="$(update_manager_json 2>/dev/null || true)"
    _new_m="$(manager_version 2>/dev/null || true)"
    if [ -n "$_old_m" ] && [ -n "$_new_m" ] && [ "$_new_m" != "$_old_m" ]; then
        append_update_message "DNS Manager $_old_m → $_new_m"
    elif printf "%s\n" "$_mr" | grep -q "Новой\|актуал\|не новее" 2>/dev/null; then
        append_update_message "DNS Manager $_old_m · актуален"
    else
        append_failure_message "DNS Manager: не удалось обновить"
    fi

    _old_h="$(package_version https-dns-proxy 2>/dev/null || true)"
    _hr="$(update_hdp_json 2>/dev/null || true)"
    _new_h="$(package_version https-dns-proxy 2>/dev/null || true)"
    if [ -n "$_old_h" ] && [ -n "$_new_h" ] && [ "$_new_h" != "$_old_h" ]; then
        append_update_message "Защищённый DNS $_old_h → $_new_h"
    elif printf "%s\n" "$_hr" | grep -q "Новой\|актуал\|не найдено" 2>/dev/null; then
        append_update_message "Защищённый DNS $_old_h · актуален"
    else
        append_failure_message "Защищённый DNS: не удалось обновить"
    fi

    _old_cv="$(catalog_version 2>/dev/null || true)"
    _old_cr="$(catalog_revision 2>/dev/null || true)"
    update_catalog_direct
    _rc=$?
    _new_cv="$(catalog_version 2>/dev/null || true)"
    _new_cr="$(catalog_revision 2>/dev/null || true)"
    case "$_rc" in
        0) append_update_message "Каталог DNS $_old_cv rev.$_old_cr → $_new_cv rev.$_new_cr" ;;
        2) append_update_message "Каталог DNS $_old_cv rev.$_old_cr · актуален" ;;
        *) append_failure_message "Каталог DNS: не удалось обновить" ;;
    esac

    _old_l="$(read_installed_luci_version)"
    _lr="$(update_json 2>/dev/null || true)"
    _new_l="$(read_installed_luci_version)"
    if [ -n "$_old_l" ] && [ -n "$_new_l" ] && [ "$_new_l" != "$_old_l" ]; then
        append_update_message "LuCI $_old_l → $_new_l"
    elif printf "%s\n" "$_lr" | grep -q "Новой\|актуал\|не новее" 2>/dev/null; then
        append_update_message "LuCI $_old_l · актуальна"
    else
        append_failure_message "LuCI: не удалось обновить"
    fi

    rm -rf "$RUNTIME_DIR/update-all.lock" 2>/dev/null || true
    if [ -n "$_failed" ]; then
        [ -n "$_message" ] && _message="$_message; "
        _message="$_message""Ошибки: $_failed"
        printf '%s' '{"ok":false,"updated":false,"message":'
        json_quote "$_message"
        printf '%s' '}'
    else
        printf '%s' '{"ok":true,"updated":true,"message":'
        json_quote "${_message:-Обновление завершено.}"
        printf '%s' '}'
    fi
}
update_manager_json() {
    if ! mkdir "$RUNTIME_DIR/manager-update.lock" 2>/dev/null; then
        json_error "Обновление DNS Manager уже выполняется"; return
    fi
    trap 'rm -rf "$RUNTIME_DIR/manager-update.lock" 2>/dev/null || true' EXIT INT TERM
    _installed="$(manager_version 2>/dev/null || true)"
    [ -n "$_installed" ] || { json_error "DNS Manager не найден"; return; }
    _out="$TMP_ROOT/manager-update.log"
    rm -f "$_out" 2>/dev/null || true
    DNS_MANAGER_FORCE_UPDATE=1 DNS_MANAGER_UPDATE_NO_EXEC=1 "$MANAGER_PATH" update-check >"$_out" 2>&1 || true
    _after="$(manager_version 2>/dev/null || true)"
    if [ -n "$_after" ] && [ "$_after" != "$_installed" ]; then
        printf '{"ok":true,"updated":true,"version":'; json_quote "$_after"; printf '}'
        rm -f "$_out" 2>/dev/null || true
        return
    fi
    _detail="$(tail -n 8 "$_out" 2>/dev/null | awk 'BEGIN{ORS=" "} {print}' | cut -c1-700)"
    rm -f "$_out" 2>/dev/null || true
    [ -n "$_detail" ] || _detail="Новой версии DNS Manager не найдено."
    json_error "$_detail"
}

update_json() {
    if ! mkdir "$RUNTIME_DIR/update.lock" 2>/dev/null; then
        json_error "Обновление LuCI уже выполняется"; return
    fi
    trap 'rm -rf "$RUNTIME_DIR/update.lock" 2>/dev/null || true' EXIT INT TERM
    _installed="$(read_installed_luci_version)"
    _tmp="$TMP_ROOT/companion-update.$$"
    if ! fetch_url "$_tmp" || ! validate_candidate "$_tmp"; then
        rm -f "$_tmp" 2>/dev/null || true
        json_error "Новая версия не прошла проверку"; return
    fi
    _latest="$(sed -n 's/^# Version:[[:space:]]*//p' "$_tmp" 2>/dev/null | head -n1)"
    if [ -z "$_latest" ] || [ "$(version_gt "$_latest" "$_installed")" != 1 ]; then
        rm -f "$_tmp" 2>/dev/null || true
        json_error "Новой версии нет"; return
    fi
    _log="$TMP_ROOT/companion-update.log"
    rm -f "$_log" 2>/dev/null || true
    if ! DNS_MANAGER_LUCI_SKIP_RPC_RELOAD=1 sh "$_tmp" update >"$_log" 2>&1; then
        _detail="$(tail -n 12 "$_log" 2>/dev/null | awk 'BEGIN{ORS=" "} {print}' | cut -c1-900)"
        rm -f "$_tmp" "$_log" 2>/dev/null || true
        [ -n "$_detail" ] || _detail="Установщик завершился с ненулевым кодом."
        json_error "LuCI не обновлена: $_detail"; return
    fi
    rm -f "$_tmp" 2>/dev/null || true
    _after="$(read_installed_luci_version)"
    if [ "$_after" != "$_latest" ]; then
        _detail="$(tail -n 12 "$_log" 2>/dev/null | awk 'BEGIN{ORS=" "} {print}' | cut -c1-900)"
        rm -f "$_log" 2>/dev/null || true
        [ -n "$_detail" ] || _detail="Установленная версия не совпала с ожидаемой."
        json_error "LuCI обновление не подтверждено: $_detail"; return
    fi
    rm -f "$_log" 2>/dev/null || true
    _state_tmp="$UPDATE_STATE.tmp.$$"
    if [ -r "$UPDATE_STATE" ]; then
        sed '/^installed=/d;/^latest=/d;/^available=/d;/^checked_at=/d' "$UPDATE_STATE" > "$_state_tmp" 2>/dev/null || true
    else
        : > "$_state_tmp"
    fi
    _update_ts="$(date +%s 2>/dev/null || printf 0)"
    printf 'installed=%s\nlatest=%s\navailable=0\nchecked_at=%s\n' "$_after" "$_after" "$_update_ts" >> "$_state_tmp"
    mv "$_state_tmp" "$UPDATE_STATE" 2>/dev/null || rm -f "$_state_tmp" 2>/dev/null || true
    printf '{"ok":true,"updated":true,"version":'; json_quote "$_after"; printf '}'
    # Return the RPC response first. Reloading rpcd before writing the response can
    # terminate the current rpcd worker and make LuCI report a false update failure.
    if [ -x /etc/init.d/rpcd ]; then
        ( sleep 1; /etc/init.d/rpcd reload >/dev/null 2>&1 || true ) >/dev/null 2>&1 &
    fi
}

result_for_id() {
    _id="$1"
    [ -s "$STATE_DIR/dns-test-results.conf" ] || [ -s "$PERSIST_STATE_DIR/dns-test-results.conf" ] || return 1
    _f="$STATE_DIR/dns-test-results.conf"
    [ -s "$_f" ] || _f="$PERSIST_STATE_DIR/dns-test-results.conf"
    awk -F'|' -v id="$_id" '$1==id {print; exit}' "$_f" 2>/dev/null
}

last_check_for_id() {
    _id="$1"
    _f="$CHECK_DIR/$_id"
    if [ -r "$_f" ]; then cat "$_f" 2>/dev/null | head -n1; return 0; fi
    _meta="$STATE_DIR/dns-test-results.meta"
    [ -r "$_meta" ] || _meta="$PERSIST_STATE_DIR/dns-test-results.meta"
    _ts="$(sed -n 's/^timestamp=//p' "$_meta" 2>/dev/null | head -n1)"
    [ -n "$_ts" ] && result_for_id "$_id" >/dev/null 2>&1 && printf '%s' "$_ts"
}

package_version() {
    _pkg="$1"
    [ -n "$_pkg" ] || return 0
    if command -v apk >/dev/null 2>&1; then
        _v="$(apk info -e -v "$_pkg" 2>/dev/null | head -n1)"
        [ -n "$_v" ] && {
            case "$_v" in
                "$_pkg"-*) printf '%s' "${_v#$_pkg-}"; return 0 ;;
            esac
        }
        _v="$(apk list --installed --manifest 2>/dev/null | awk -v p="$_pkg" 'index($1,p"-")==1 || $1==p {print $2; exit}')"
        [ -n "$_v" ] && printf '%s' "$_v"
    elif command -v opkg >/dev/null 2>&1; then
        opkg status "$_pkg" 2>/dev/null | sed -n 's/^Version:[[:space:]]*//p' | head -n1
    fi
}
package_candidate_version() {
    _pkg="$1"
    [ -n "$_pkg" ] || return 0
    if command -v apk >/dev/null 2>&1; then        _v="$(apk list --upgradeable "$_pkg" 2>/dev/null | awk -v p="$_pkg" '$1 ~ "^"p"-" {sub("^"p"-","",$1); print $1; exit}')"
        printf '%s' "$_v"
    elif command -v opkg >/dev/null 2>&1; then
        opkg list-upgradable 2>/dev/null | awk -v p="$_pkg" '$1==p {print $3; exit}'
    fi
}
package_version_cmp() {
    _a="$1"; _b="$2"
    [ -n "$_a" ] && [ -n "$_b" ] || return 2
    if command -v apk >/dev/null 2>&1 && apk version -t "$_a" "$_b" >/dev/null 2>&1; then
        apk version -t "$_a" "$_b" 2>/dev/null | grep -q '^>' && return 0 || return 1
    fi
    awk -F'[^0-9]+' -v a="$_a" -v b="$_b" 'BEGIN{split(a,A);split(b,B);for(i=1;i<=8;i++){x=A[i]+0;y=B[i]+0;if(x>y){exit 0}if(x<y){exit 1}}exit 1}'
}
package_update_hdp() {
    if command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1 || return 1
        apk upgrade https-dns-proxy >/dev/null 2>&1 || return 1
    elif command -v opkg >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1 || return 1
        opkg upgrade https-dns-proxy >/dev/null 2>&1 || return 1
    else
        return 1
    fi
    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || return 1
    return 0
}

runtime_lan_input_match() {
    _ref="$1"
    [ -n "$_ref" ] || return 1
    case "$_ref" in
        lan) return 0 ;;
        @zone\[*\]) _nets="$(uci -q get "firewall.$_ref.network" 2>/dev/null || true)" ;;
        *) _nets="$(uci -q get "firewall.$_ref.network" 2>/dev/null || true)" ;;
    esac
    printf '%s\n' "$_nets" | tr ' ' '\n' | grep -qxF lan 2>/dev/null
}
runtime_zapret_running() {
    ps w 2>/dev/null | grep -Eq '[z]ms([[:space:]]|/)|[z]apret([[:space:]]|/)|[z]apret2([[:space:]]|/)|[z]aproxy2([[:space:]]|/)'
}
detect_runtime_force_state() {
    FORCE_RUNTIME_ACTIVE=0
    FORCE_RUNTIME_EXTERNAL=0
    FORCE_RUNTIME_SOURCE="none"
    FORCE_RUNTIME_TARGETS=""
    _manager_force=0
    _cfg_force="$(cfg_get FORCE_DOH)"
    [ "$_cfg_force" = 1 ] && [ "$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null || true)" = 1 ] && [ "$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null || true)" = 1 ] && _manager_force=1
    _external=0
    _lan_dev="$(uci -q get network.lan.device 2>/dev/null || true)"
    _lan_if="$(uci -q get network.lan.ifname 2>/dev/null || true)"
    _secs="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=redirect$/\1/p')"
    for _sec in $_secs; do
        [ "$(uci -q get "firewall.$_sec.disabled" 2>/dev/null)" = 1 ] && continue
        runtime_lan_input_match "$(uci -q get "firewall.$_sec.src" 2>/dev/null || true)" || continue
        _sd="$(uci -q get "firewall.$_sec.src_dport" 2>/dev/null || true)"
        printf '%s\n' "$_sd" | tr ' ' '\n' | grep -qxF 53 2>/dev/null || continue
        _target="$(uci -q get "firewall.$_sec.target" 2>/dev/null || true)"
        case "$_target" in DNAT|dnat|REDIRECT|redirect) ;; *) continue ;; esac
        _dp="$(uci -q get "firewall.$_sec.dest_port" 2>/dev/null || true)"
        [ -n "$_dp" ] || continue
        case "$_dp" in 53|53-53) continue ;; esac
        FORCE_RUNTIME_ACTIVE=1
        FORCE_RUNTIME_TARGETS="$FORCE_RUNTIME_TARGETS $_dp"
        [ "$_manager_force" = 1 ] || _external=1
    done
    if command -v nft >/dev/null 2>&1 && nft list table inet fw4 >/dev/null 2>&1; then
        _rt="$(nft -a list ruleset 2>/dev/null || true)"
        _nft_ports="$(printf '%s\n' "$_rt" | awk -v ld="$_lan_dev" -v li="$_lan_if" '
            /iifname[[:space:]]+"[^"]+"/ && /dport[[:space:]]+53/ && /(redirect[[:space:]]+to[[:space:]]+:[0-9]+|dnat[[:space:]]+to[[:space:]]+[^[:space:]]+:[0-9]+)/ {
                ok=0
                if ($0 ~ /iifname[[:space:]]+"br-lan"/) ok=1
                if (ld != "" && index($0,"iifname \"" ld "\"")>0) ok=1
                if (li != "" && index($0,"iifname \"" li "\"")>0) ok=1
                if (!ok) next
                line=$0
                if ($0 ~ /redirect[[:space:]]+to[[:space:]]+:[0-9]+/) sub(/^.*redirect[[:space:]]+to[[:space:]]+:/,"",line)
                else sub(/^.*dnat[[:space:]]+to[[:space:]]+[^:[:space:]]+:/,"",line)
                sub(/[^0-9].*$/,"",line)
                if (line != "" && line != 53) print line
            }' | sort -n -u)"
        if [ -n "$_nft_ports" ]; then
            FORCE_RUNTIME_ACTIVE=1
            for _p in $_nft_ports; do FORCE_RUNTIME_TARGETS="$FORCE_RUNTIME_TARGETS $_p"; done
            [ "$_manager_force" = 1 ] || _external=1
        fi
    elif command -v iptables-save >/dev/null 2>&1; then
        _rt="$(iptables-save -t nat 2>/dev/null || true)"
        _ipt_ports="$(printf '%s\n' "$_rt" | awk -v ld="$_lan_dev" -v li="$_lan_if" '
            function has_input_dev(    i) {
                for(i=1;i<NF;i++) if($i=="-i" && $(i+1)!="") {
                    if($(i+1)=="br-lan" || (ld!="" && $(i+1)==ld) || (li!="" && $(i+1)==li)) return 1
                }
                return 0
            }
            /-A PREROUTING / {
                if(!has_input_dev() || $0 !~ /--dport 53([[:space:]]|$)/) next
                if($0 ~ / -j REDIRECT([[:space:]]|$)/ && $0 ~ /--to-ports[[:space:]]+[0-9]+/ && $0 !~ /--to-ports[[:space:]]+53([[:space:]]|$)/) {
                    line=$0; sub(/^.*--to-ports[[:space:]]+/,"",line); sub(/[^0-9].*$/,"",line); print line; next
                }
                if($0 ~ / -j DNAT([[:space:]]|$)/ && $0 ~ /--to-destination[[:space:]]+[^[:space:]]+:[0-9]+/ && $0 !~ /--to-destination[[:space:]]+[^[:space:]]+:53([[:space:]]|$)/) {
                    line=$0; sub(/^.*:/,"",line); sub(/[^0-9].*$/,"",line); if(line ~ /^[0-9]+$/) print line
                }
            }' | sort -n -u)"
        if [ -n "$_ipt_ports" ]; then
            FORCE_RUNTIME_ACTIVE=1
            for _p in $_ipt_ports; do FORCE_RUNTIME_TARGETS="$FORCE_RUNTIME_TARGETS $_p"; done
            [ "$_manager_force" = 1 ] || _external=1
        fi
    fi
    if [ "$_external" = 1 ]; then
        FORCE_RUNTIME_EXTERNAL=1
        if runtime_zapret_running; then FORCE_RUNTIME_SOURCE="Zapret / внешний"; else FORCE_RUNTIME_SOURCE="внешний сервис"; fi
    elif [ "$_manager_force" = 1 ]; then
        FORCE_RUNTIME_ACTIVE=1
        FORCE_RUNTIME_SOURCE="DNS Manager"
    fi
    FORCE_RUNTIME_TARGETS="$(printf '%s\n' "$FORCE_RUNTIME_TARGETS" | tr ' ' '\n' | sed '/^$/d' | sort -n -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
}

openwrt_release() { sed -n "s/^DISTRIB_RELEASE='\([^']*\)'.*/\1/p" /etc/openwrt_release 2>/dev/null | head -n1; }

status_json() {
    maybe_background_update_check
    _mv="$(manager_version 2>/dev/null || true)"
    _profile="$(cfg_get DNS_PROFILE)"; [ -n "$_profile" ] || _profile="hybrid"
    _mode="$(cfg_get DNS_SELECTION_MODE)"; [ -n "$_mode" ] || _mode="quick"
    _watchdog="$(cfg_get WATCHDOG_ENABLED)"; [ -n "$_watchdog" ] || _watchdog=0
    _watchdog_interval="$(cfg_get WATCHDOG_INTERVAL)"; [ -n "$_watchdog_interval" ] || _watchdog_interval=90
    _watchdog_backend="$(cfg_get WATCHDOG_BACKEND)"; [ -n "$_watchdog_backend" ] || _watchdog_backend=procd
    _watchdog_fail_threshold="$(manager_const_num WATCHDOG_FAIL_THRESHOLD 2)"
    _watchdog_repair_cooldown="$(manager_const_num WATCHDOG_REPAIR_COOLDOWN 300)"
    _watchdog_guard_interval="$(manager_const_num WATCHDOG_GUARD_INTERVAL 900)"
    _watchdog_max_repairs="$(manager_const_num WATCHDOG_MAX_REPAIRS 1)"
    _watchdog_max_restarts="$(manager_const_num WATCHDOG_MAX_RESTARTS 2)"
    _watchdog_max_candidates="$(manager_const_num WATCHDOG_MAX_CANDIDATES 3)"
    _watchdog_restart_cooldown="$(manager_const_num WATCHDOG_RESTART_COOLDOWN 300)"
    _watchdog_service_enabled=0; watchdog_service_enabled && _watchdog_service_enabled=1 || true
    _watchdog_service_running=0; watchdog_service_running && _watchdog_service_running=1 || true
    _watchdog_loop_running=0; watchdog_loop_running && _watchdog_loop_running=1 || true
    _force="$(cfg_get FORCE_DOH)"; [ -n "$_force" ] || _force=0
    _mtu="$(cfg_get MTU_FIX)"; [ -n "$_mtu" ] || _mtu=0
    _sysctl="$(cfg_get SYSCTL_TUNING)"; [ -n "$_sysctl" ] || _sysctl=0
    _sysctl_ext="$(cfg_get SYSCTL_EXTENDED)"; [ -n "$_sysctl_ext" ] || _sysctl_ext=0
    _ntp="$(cfg_get NTP_CLIENTS)"; [ -n "$_ntp" ] || _ntp=0
    _perf="$(cfg_get DNSMASQ_PERF)"; [ -n "$_perf" ] || _perf=0
    _fix="$(cfg_get CLIENT_FIXES)"; [ -n "$_fix" ] || _fix=0

    _doh_total=0; _doh_running=0
    _i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$_i]" >/dev/null 2>&1; do
        _doh_total=$((_doh_total + 1)); _p="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].listen_port" 2>/dev/null || true)"
        [ -n "$_p" ] && { ss -lnt 2>/dev/null | grep -qE "(:|\])$_p([[:space:]]|$)" || netstat -lnt 2>/dev/null | grep -qE "(:|\])$_p([[:space:]]|$)"; } && _doh_running=$((_doh_running + 1)) || true
        _i=$((_i + 1))
    done
    _doh="no"; [ "$_doh_running" -gt 0 ] && _doh="yes"

    _expected=0
    for _s in 1 2 3 4 5 6 RU RU_2; do [ -n "$(cfg_get "SLOT_$_s")" ] && _expected=$((_expected + 1)); done
    _match=0
    for _s in 1 2 3 4 5 6 RU RU_2; do
        _id="$(cfg_get "SLOT_$_s")"; _port="$(cfg_get "PORT_$_s")"
        [ -n "$_id" ] || continue
        [ -n "$_port" ] || continue
        _url="$(catalog_field "$_id" 5 2>/dev/null || true)"
        [ -n "$_url" ] || continue
        _j=0; while uci -q get "https-dns-proxy.@https-dns-proxy[$_j]" >/dev/null 2>&1; do
            _up="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_j].listen_port" 2>/dev/null || true)"
            _uu="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_j].resolver_url" 2>/dev/null | sed 's:/*$::')"
            if [ "$_up" = "$_port" ] && [ "$_uu" = "${_url%/}" ]; then _match=$((_match + 1)); break; fi
            _j=$((_j + 1))
        done
    done
    detect_runtime_force_state
    _force_cfg="$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null || true)"; _external="$FORCE_RUNTIME_EXTERNAL"
    _force_notrack="$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null || true)"
    _force_update="$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null || true)"
    _force_family="$(uci -q get https-dns-proxy.config.force_ip_family 2>/dev/null || true)"
    _force_ports="$(uci -q get https-dns-proxy.config.force_dns_port 2>/dev/null || true)"
    _force_src="$(uci -q get https-dns-proxy.config.force_dns_src_interface 2>/dev/null || true)"
    _force_source="none"
    if [ "$_external" = 1 ]; then
        if ps w 2>/dev/null | grep -Eq '[z]apret([[:space:]]|/)|[z]apret2([[:space:]]|/)'; then _force_source="Zapret / внешний"; else _force_source="внешний сервис"; fi
    elif [ "$_force" = 1 ]; then
        _force_source="DNS Manager"
    fi
    _force_canary_i="$(uci -q get https-dns-proxy.config.canary_domains_icloud 2>/dev/null || true)"
    _force_canary_m="$(uci -q get https-dns-proxy.config.canary_domains_mozilla 2>/dev/null || true)"
    _force_procd="$(uci -q get https-dns-proxy.config.procd_trigger_wan6 2>/dev/null || true)"
    _force_heartbeat_domain="$(uci -q get https-dns-proxy.config.heartbeat_domain 2>/dev/null || true)"
    _force_heartbeat_sleep="$(uci -q get https-dns-proxy.config.heartbeat_sleep_timeout 2>/dev/null || true)"
    _force_heartbeat_wait="$(uci -q get https-dns-proxy.config.heartbeat_wait_timeout 2>/dev/null || true)"
    _force_user="$(uci -q get https-dns-proxy.config.user 2>/dev/null || true)"
    _force_group="$(uci -q get https-dns-proxy.config.group 2>/dev/null || true)"
    _force_listen="$(uci -q get https-dns-proxy.config.listen_addr 2>/dev/null || true)"
    _force_ports_norm="$(printf '%s\n' "$_force_ports" | awk '{gsub(/["\047,]/," "); for(i=1;i<=NF;i++) print $i}' | sort -n | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    _force_src_norm="$(printf '%s\n' "$_force_src" | awk '{gsub(/["\047,]/," "); for(i=1;i<=NF;i++) print $i}' | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    _force_src_expected="lan"
    _fz="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=zone$/\1/p')"
    for _z in $_fz; do
        _nets="$(uci -q get "firewall.$_z.network" 2>/dev/null || true)"
        printf '%s\n' $_nets | grep -qx lan && { _force_src_expected="$_nets"; break; }
    done
    _force_src_expected_norm="$(printf '%s\n' "$_force_src_expected" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    _force_consistent=0
    _force_common=0
    [ "$_force_notrack" = 1 ] && [ "$_force_update" = - ] && [ "$_force_family" = auto ] && [ "$_force_ports_norm" = '53 853' ] && [ "$_force_src_norm" = "$_force_src_expected_norm" ] && [ "$_force_procd" = 0 ] && [ "$_force_heartbeat_domain" = heartbeat.mossdef.org ] && [ "$_force_heartbeat_sleep" = 10 ] && [ "$_force_heartbeat_wait" = 10 ] && [ "$_force_user" = nobody ] && [ "$_force_group" = nogroup ] && [ "$_force_listen" = 127.0.0.1 ] && _force_common=1
    if [ "$_force" = 1 ] && [ "$_force_cfg" = 1 ] && [ "$_force_canary_i" = 1 ] && [ "$_force_canary_m" = 1 ] && [ "$_force_common" = 1 ]; then _force_consistent=1; fi
    if [ "$_force" = 0 ] && [ "$_force_cfg" != 1 ] && [ "$_force_common" = 1 ]; then _force_consistent=1; fi

    _dnsmasq="no"; /etc/init.d/dnsmasq status >/dev/null 2>&1 && _dnsmasq="yes"; pgrep -x dnsmasq >/dev/null 2>&1 && _dnsmasq="yes"
    _fw="unknown"; command -v fw4 >/dev/null 2>&1 && _fw="fw4"; command -v fw3 >/dev/null 2>&1 && [ "$_fw" = unknown ] && _fw="fw3"
    _lan="$(uci -q get network.lan.ipaddr 2>/dev/null | cut -d/ -f1 | head -n1)"
    [ -n "$_lan" ] || _lan="—"
    _host="$(uci -q get system.@system[0].hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || true)"
    _uptime="$(awk '{printf "%s",int($1)}' /proc/uptime 2>/dev/null || true)"
    _load="$(awk '{printf "%s",$1}' /proc/loadavg 2>/dev/null || true)"
    _mem_t="$(awk '/MemTotal:/ {print $2;exit}' /proc/meminfo 2>/dev/null || true)"
    _mem_a="$(awk '/MemAvailable:/ {print $2;exit}' /proc/meminfo 2>/dev/null || true)"
    _cpu_count="$(awk '/^processor[[:space:]]*:/ {n++} END {print n+0}' /proc/cpuinfo 2>/dev/null)"
    case "$_cpu_count" in ''|*[!0-9]*|0) _cpu_count=1;; esac
    _ipv4="no"; ip -4 route show default 2>/dev/null | grep -q . && _ipv4="yes"
    _ipv6="no"; ip -6 route show default 2>/dev/null | grep -q . && _ipv6="yes"
    _last=""; _meta="$STATE_DIR/dns-test-results.meta"; [ -r "$_meta" ] || _meta="$PERSIST_STATE_DIR/dns-test-results.meta"; _last="$(sed -n 's/^timestamp=//p' "$_meta" 2>/dev/null | head -n1)"
    _cat_total="$(grep -v '^#' "$CATALOG_FILE" 2>/dev/null | grep -c '^[^|][^|]*|' 2>/dev/null || printf 0)"
    _luciv="$(read_installed_luci_version)"
    _luci_latest="$(sed -n 's/^latest=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _hdp_installed="$(package_version https-dns-proxy 2>/dev/null || true)"
    _hdp_candidate="$(package_candidate_version https-dns-proxy 2>/dev/null || true)"
    _hdp_update=0
    if [ -n "$_hdp_installed" ] && [ -n "$_hdp_candidate" ] && package_version_cmp "$_hdp_candidate" "$_hdp_installed"; then
        _hdp_update=1
    fi
    _force_manager=0
    [ "$_force" = 1 ] && [ "$_force_cfg" = 1 ] && _force_manager=1
    _zapret_running=0
    ps w 2>/dev/null | grep -Eq '[z]ms([[:space:]]|/)|[z]apret([[:space:]]|/)|[z]apret2([[:space:]]|/)|[z]aproxy2([[:space:]]|/)' && _zapret_running=1
    _force_both=0
    [ "$_force_manager" = 1 ] && [ "$_external" = 1 ] && _force_both=1
    _luci_avail="$(sed -n 's/^available=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_luci_avail" ] || _luci_avail=0
    _luci_checked_at="$(sed -n 's/^checked_at=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _luci_error="$(sed -n 's/^error=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _luci_checked=0
    case "$_luci_checked_at" in
        ''|*[!0-9]*) ;;
        *) [ "$_luci_checked_at" -gt 0 ] 2>/dev/null && _luci_checked=1 || true ;;
    esac
    _manager_latest_state="$(sed -n 's/^manager_latest=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _manager_avail_state="$(sed -n 's/^manager_available=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_manager_avail_state" ] || _manager_avail_state=0
    _manager_check_state="$(sed -n 's/^manager_checked=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_manager_check_state" ] || _manager_check_state=0
    _catalog_latest_state="$(sed -n 's/^catalog_latest=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _catalog_rev_state="$(sed -n 's/^catalog_latest_rev=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _catalog_total_state="$(sed -n 's/^catalog_latest_total=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_catalog_total_state" ] || _catalog_total_state=0
    _catalog_avail_state="$(sed -n 's/^catalog_available=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_catalog_avail_state" ] || _catalog_avail_state=0
    _catalog_check_state="$(sed -n 's/^catalog_checked=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_catalog_check_state" ] || _catalog_check_state=0
    _hdp_check_state="$(sed -n 's/^hdp_checked=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_hdp_check_state" ] || _hdp_check_state=0
    _components_checked_at="$(sed -n 's/^components_checked_at=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"

    printf '{"ok":true,"manager_version":'; json_quote "$_mv"; printf ',"luci_version":'; json_quote "$_luciv"; printf ',"luci_latest_version":'; json_quote "$_luci_latest"; printf ',"luci_update_available":%s,"luci_update_checked":%s,"luci_update_checked_at":%s' "$_luci_avail" "$_luci_checked" "${_luci_checked_at:-0}"
    printf ',"luci_update_error":'; json_quote "$_luci_error"
    printf ',"manager_latest_version":'; json_quote "$_manager_latest_state"; printf ',"manager_update_available":%s,"manager_check_ok":%s' "$_manager_avail_state" "$_manager_check_state"
    printf ',"catalog_latest_version":'; json_quote "$_catalog_latest_state"; printf ',"catalog_latest_rev":'; json_quote "$_catalog_rev_state"; printf ',"catalog_latest_total":%s,"catalog_update_available":%s,"catalog_check_ok":%s' "$_catalog_total_state" "$_catalog_avail_state" "$_catalog_check_state"
    printf ',"ipv4":'; json_quote "$_ipv4"; printf ',"ipv6":'; json_quote "$_ipv6"; printf ',"dnsmasq":'; json_quote "$_dnsmasq"; printf ',"doh":'; json_quote "$_doh"; printf ',"firewall":'; json_quote "$_fw"; printf ',"openwrt":'; json_quote "$(openwrt_release)"; printf ',"lan":'; json_quote "$_lan"
    printf ',"profile":'; json_quote "$_profile"; printf ',"profile_mode":'; json_quote "$_mode"; printf ',"watchdog":'; json_quote "$_watchdog"
    printf ',"watchdog_backend":'; json_quote "$_watchdog_backend"; printf ',"watchdog_service":%s,"watchdog_service_enabled":%s,"watchdog_loop":%s' "$_watchdog_service_running" "$_watchdog_service_enabled" "$_watchdog_loop_running"
    printf ',"watchdog_interval":'; json_quote "$_watchdog_interval"; printf ',"watchdog_fail_threshold":%s' "$_watchdog_fail_threshold"
    printf ',"watchdog_repair_cooldown":%s,"watchdog_guard_interval":%s' "$_watchdog_repair_cooldown" "$_watchdog_guard_interval"
    printf ',"watchdog_max_repairs":%s,"watchdog_max_restarts":%s,"watchdog_max_candidates":%s,"watchdog_restart_cooldown":%s' "$_watchdog_max_repairs" "$_watchdog_max_restarts" "$_watchdog_max_candidates" "$_watchdog_restart_cooldown"
    for _age_cat in bypass clean security privacy adblock family regional; do
        _age_v="$(cfg_get "TEST_RESULTS_MAX_AGE_$(printf '%s' "$_age_cat" | tr '[:lower:]' '[:upper:]')")"
        case "$_age_v" in ''|*[!0-9]*) _age_h=6;; *) _age_h=$((_age_v/3600)); [ "$_age_h" -ge 1 ] || _age_h=1;; esac
        eval "_test_age_$_age_cat=\"$_age_h\""
    done
    printf ',"test_age_bypass":%s,"test_age_clean":%s,"test_age_security":%s,"test_age_privacy":%s,"test_age_adblock":%s,"test_age_family":%s,"test_age_regional":%s'         "$_test_age_bypass" "$_test_age_clean" "$_test_age_security" "$_test_age_privacy" "$_test_age_adblock" "$_test_age_family" "$_test_age_regional"
    _force_owner="none"
    [ "$_external" = 1 ] && _force_owner="external"
    [ "$_external" != 1 ] && [ "$_force_manager" = 1 ] && _force_owner="manager"
    printf ',"force":'; json_quote "$_force"; printf ',"force_external":'; json_quote "$_external"; printf ',"force_owner":'; json_quote "$_force_owner"; printf ',"force_manager":%s,"force_both":%s,"zapret_running":%s' "$_force_manager" "$_force_both" "$_zapret_running"; printf ',"force_source":'; json_quote "$FORCE_RUNTIME_SOURCE"; printf ',"force_targets":'; json_quote "$FORCE_RUNTIME_TARGETS"; printf ',"force_notrack":'; json_quote "$_force_notrack"; printf ',"force_update":'; json_quote "$_force_update"; printf ',"force_family":'; json_quote "$_force_family"; printf ',"force_ports":'; json_quote "$_force_ports"; printf ',"force_src":'; json_quote "$_force_src"; printf ',"force_canary_icloud":'; json_quote "$_force_canary_i"; printf ',"force_canary_mozilla":'; json_quote "$_force_canary_m"; printf ',"force_procd_trigger_wan6":'; json_quote "$_force_procd"; printf ',"force_heartbeat_domain":'; json_quote "$_force_heartbeat_domain"; printf ',"force_heartbeat_sleep":'; json_quote "$_force_heartbeat_sleep"; printf ',"force_heartbeat_wait":'; json_quote "$_force_heartbeat_wait"; printf ',"force_user":'; json_quote "$_force_user"; printf ',"force_group":'; json_quote "$_force_group"; printf ',"force_listen":'; json_quote "$_force_listen"; printf ',"force_consistent":%s' "$_force_consistent"; printf ',"mtu":'; json_quote "$_mtu"; printf ',"sysctl":'; json_quote "$_sysctl"; printf ',"sysctl_ext":'; json_quote "$_sysctl_ext"; printf ',"ntp_clients":'; json_quote "$_ntp"; printf ',"dnsmasq_perf":'; json_quote "$_perf"; printf ',"client_fixes":'; json_quote "$_fix"
    printf ',"doh_total":%s,"doh_match":%s,"configured_dns":%s' "$_doh_total" "$_match" "$_expected"; printf ',"last_full_test":'; json_quote "$_last"; printf ',"components_checked_at":'; json_quote "$_components_checked_at"
    printf ',"hostname":'; json_quote "$_host"; printf ',"uptime":'; json_quote "$_uptime"; printf ',"load1":'; json_quote "$_load"; printf ',"cpu_count":%s,"memory_total_kb":%s,"memory_available_kb":%s' "$_cpu_count" "${_mem_t:-0}" "${_mem_a:-0}"
    printf ',"catalog_total":%s,"catalog_version":' "$_cat_total"; json_quote "$(catalog_version)"; printf ',"catalog_revision":'; json_quote "$(catalog_revision)"; printf ',"hdp_version":'; json_quote "$_hdp_installed"; printf ',"hdp_latest_version":'; json_quote "$_hdp_candidate"; printf ',"hdp_update_available":%s,"hdp_check_ok":%s' "$_hdp_update" "$_hdp_check_state"
    _force_status="off"; _force_owner_label="нет"
    [ "$_force_manager" = 1 ] && _force_status="manager" && _force_owner_label="DNS Manager"
    [ "$_external" = 1 ] && _force_status="external" && _force_owner_label="внешний"
    printf ',"force_status":'; json_quote "$_force_status"; printf ',"force_owner_label":'; json_quote "$_force_owner_label"
    printf ',"slots":['
    _first=1
    for _s in 1 2 3 4 5 6 RU RU_2; do
        _id="$(cfg_get "SLOT_$_s")"; _cat="$(cfg_get "SLOT_${_s}_CAT")"; _port="$(cfg_get "PORT_$_s")"
        [ -n "$_cat" ] || [ -z "$_id" ] || _cat="$(catalog_field "$_id" 2 2>/dev/null || true)"
        _name="$(catalog_field "$_id" 4 2>/dev/null || true)"; [ -n "$_name" ] || _name="Не задан"
        _r="$(current_slot_result_for_id "$_id" 2>/dev/null || true)"
        _ms="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $4;exit}')"; _rawst="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"; _st=""
        case "$_rawst" in
            OK) case "$_ms" in ''|*[!0-9]*) _st=FAIL;; *) _st=OK;; esac ;;
            RUNNING) _st=RUNNING ;;
            '') _st="" ;;
            *) _st=FAIL ;;
        esac
        [ "$_first" = 1 ] || printf ','; _first=0
        printf '{"slot":'; json_quote "$_s"; printf ',"id":'; json_quote "$_id"; printf ',"name":'; json_quote "$_name"; printf ',"category":'; json_quote "$_cat"; printf ',"port":'; json_quote "$_port"; printf ',"ping":'; json_quote "$_ms"; printf ',"status":'; json_quote "$_st"; printf ',"last_check":'; json_quote "$(last_check_for_id "$_id")"; printf '}'
    done
    printf ']}'
}

# ---------- Heavy/authoritative path below ----------
INPUT=""
load_manager() {
    [ -x "$MANAGER" ] || return 1
    _src="$TMP_ROOT/manager-functions.$$"
    sed '/^case "${1:-}" in$/,$d' "$MANAGER" > "$_src" 2>/dev/null || { rm -f "$_src"; return 1; }
    . "$_src" || { rm -f "$_src"; return 1; }
    rm -f "$_src"
    preflight_readonly >/dev/null 2>&1 || return 1
    init_dirs >/dev/null 2>&1 || return 1
    load_config >/dev/null 2>&1 || return 1
    restore_persistent_test_results >/dev/null 2>&1 || true
    refresh_runtime_capabilities >/dev/null 2>&1 || true
    return 0
}

set_check_stamp() {
    _id="$1"; _ts="$2"
    case "$_id" in ''|*[!A-Za-z0-9_-]*) return 1;; esac
    printf '%s\n' "$_ts" > "$CHECK_DIR/$_id" 2>/dev/null
}
write_current_slot_results() {
    _results="$1"
    [ -s "$_results" ] || return 1
    cat "$_results" > "${CURRENT_SLOT_RESULTS}.tmp.$$" 2>/dev/null || return 1
    mv -f "${CURRENT_SLOT_RESULTS}.tmp.$$" "$CURRENT_SLOT_RESULTS" 2>/dev/null || {
        rm -f "${CURRENT_SLOT_RESULTS}.tmp.$$" 2>/dev/null || true
        return 1
    }
    chmod 600 "$CURRENT_SLOT_RESULTS" 2>/dev/null || true
}
current_slot_result_for_id() {
    _id="$1"
    [ -r "$CURRENT_SLOT_RESULTS" ] || return 1
    awk -F'|' -v id="$_id" '$1==id {print; exit}' "$CURRENT_SLOT_RESULTS" 2>/dev/null
}
new_job_id() { printf '%s-%s' "$(date +%s)" "$$"; }
job_write() { _id="$1"; _key="$2"; _value="$3"; mkdir -p "$JOB_DIR/$_id" 2>/dev/null || return 1; printf '%s=%s\n' "$_key" "$_value" >> "$JOB_DIR/$_id/state" 2>/dev/null; }

job_start_test_all() {
    _jid="$(new_job_id)"; mkdir -p "$JOB_DIR/$_jid" 2>/dev/null || { json_error "Не удалось создать задачу"; return; }
    : > "$JOB_DIR/$_jid/state"; printf 'status=running\nstarted=%s\nmode=all\n' "$(date +%s)" > "$JOB_DIR/$_jid/state"
    (
        exec >>"$JOB_DIR/$_jid/output" 2>&1
        trap 'job_write "$_jid" status failed; job_write "$_jid" finished "$(date +%s)"; exit 1' INT TERM
        if load_manager && SILENT_APPLY=1 test_dns_catalog; then
            now="$(date +%s)"; while IFS='|' read -r _id _rest; do [ -n "$_id" ] && set_check_stamp "$_id" "$now"; done < "$TEST_RESULTS"
            job_write "$_jid" status done; job_write "$_jid" result ok; job_write "$_jid" finished "$now"
        else
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"
        fi
    ) &
    printf '{"ok":true,"job":'; json_quote "$_jid"; printf '}'
}

job_start_test_current() {
    _jid="$(new_job_id)"
    mkdir -p "$JOB_DIR/$_jid" 2>/dev/null || { json_error "Не удалось создать задачу"; return; }
    : > "$JOB_DIR/$_jid/state"
    printf 'status=running\nstarted=%s\nmode=current\n' "$(date +%s)" > "$JOB_DIR/$_jid/state"
    (
        exec >>"$JOB_DIR/$_jid/output" 2>&1
        if ! load_manager; then
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"; exit 1
        fi
        _ids="$TMP_ROOT/current-dns-ids.$$"
        _cat="$TMP_ROOT/current-dns-catalog.$$"
        _results="$TMP_ROOT/current-test-results.$$"
        _meta="$TMP_ROOT/current-test-results-meta.$$"
        : > "$_ids"; : > "$_cat"
        sed -n '/^# DNSCATVER=/p;/^# DNSCATREV=/p' "$DNS_CATALOG" >> "$_cat" 2>/dev/null || true
        for _s in 1 2 3 4 5 6 RU RU_2; do
            _id="$(cfg_get "SLOT_$_s")"
            [ -n "$_id" ] || continue
            grep -qxF "$_id" "$_ids" 2>/dev/null && continue
            printf '%s\n' "$_id" >> "$_ids"
            awk -F"|" -v id="$_id" '$1==id {print; exit}' "$DNS_CATALOG" >> "$_cat" 2>/dev/null || true
        done
        _total="$(wc -l < "$_ids" 2>/dev/null | tr -d ' ')"
        case "$_total" in ''|*[!0-9]*) _total=0;; esac
        [ "$_total" -gt 0 ] || {
            rm -f "$_ids" "$_cat" "$_results" "$_meta"
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"; exit 1
        }
        _old_catalog="$DNS_CATALOG"
        _old_results="$TEST_RESULTS"
        _old_meta="$TEST_RESULTS_META"
        DNS_CATALOG="$_cat"
        TEST_RESULTS="$_results"
        TEST_RESULTS_META="$_meta"
        if ! test_dns_catalog; then
            DNS_CATALOG="$_old_catalog"; TEST_RESULTS="$_old_results"; TEST_RESULTS_META="$_old_meta"
            rm -f "$_ids" "$_cat" "$_results" "$_meta"
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"; exit 1
        fi
        DNS_CATALOG="$_old_catalog"; TEST_RESULTS="$_old_results"; TEST_RESULTS_META="$_old_meta"
        _merged="$TMP_ROOT/current-merged.$$"
        : > "$_merged"
        if [ -s "$TEST_RESULTS" ]; then
            awk -F"|" -v ids_file="$_ids" 'BEGIN { while ((getline x < ids_file)>0) ids[x]=1 } !($1 in ids) { print }' "$TEST_RESULTS" > "$_merged" 2>/dev/null || true
        fi
        [ -s "$_results" ] && cat "$_results" >> "$_merged"
        mv "$_merged" "$TEST_RESULTS" 2>/dev/null || {
            rm -f "$_ids" "$_cat" "$_results" "$_meta"
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"; exit 1
        }
        save_persistent_test_results >/dev/null 2>&1 || true
        _stamp="$(date +%s)"
        while IFS='|' read -r _id _rest; do [ -n "$_id" ] && set_check_stamp "$_id" "$_stamp"; done < "$_results"
        write_current_slot_results "$_results" || true
        rm -f "$_ids" "$_cat" "$_results" "$_meta"
        job_write "$_jid" status done; job_write "$_jid" result ok; job_write "$_jid" finished "$_stamp"
    ) &
    printf '{"ok":true,"job":'; json_quote "$_jid"; printf '}'
}

job_start_test_one() {
    _id="$1"; case "$_id" in ''|*[!A-Za-z0-9_-]*) json_error "Неверный ID DNS"; return;; esac
    _jid="$(new_job_id)"; mkdir -p "$JOB_DIR/$_jid" 2>/dev/null || { json_error "Не удалось создать задачу"; return; }
    : > "$JOB_DIR/$_jid/state"; printf 'status=running\nstarted=%s\nmode=one\n' "$(date +%s)" > "$JOB_DIR/$_jid/state"
    job_write "$_jid" dns_id "$_id"
    (
        exec >>"$JOB_DIR/$_jid/output" 2>&1
        if load_manager; then
            q="$TMP_ROOT/dns_query.bin"; [ -s "$q" ] || printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$q"
            if acquire_test_lock; then
                if test_one_dns "$_id"; then
                    _tmp="$TMP_ROOT/results.$$"; _stamp="$(date +%s)"; : > "$_tmp"
                    [ -s "$TEST_RESULTS" ] && awk -F'|' -v id="$_id" '$1!=id {print}' "$TEST_RESULTS" > "$_tmp" 2>/dev/null || true
                    cat "$TMP_DIR/t.$_id" >> "$_tmp" 2>/dev/null || true; mv "$_tmp" "$TEST_RESULTS" 2>/dev/null || true
                    save_persistent_test_results >/dev/null 2>&1 || true; set_check_stamp "$_id" "$_stamp" "$(cat "$TMP_DIR/t.$_id" 2>/dev/null || true)"; release_test_lock || true
                    job_write "$_jid" status done; job_write "$_jid" result ok; job_write "$_jid" finished "$_stamp"; exit 0
                fi
                release_test_lock || true
            fi
        fi
        job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"
    ) &
    printf '{"ok":true,"job":'; json_quote "$_jid"; printf '}'
}

job_json() {
    _jid="$1"; case "$_jid" in ''|*[!A-Za-z0-9_-]*) json_error "Неверный job ID"; return;; esac
    _d="$JOB_DIR/$_jid"; [ -d "$_d" ] || { json_error "Задача не найдена"; return; }
    printf '{"ok":true,"job":'; json_quote "$_jid"
    printf ',"status":'; json_quote "$(sed -n 's/^status=//p' "$_d/state" 2>/dev/null | tail -n1)"
    printf ',"result":'; json_quote "$(sed -n 's/^result=//p' "$_d/state" 2>/dev/null | tail -n1)"
    printf ',"mode":'; json_quote "$(sed -n 's/^mode=//p' "$_d/state" 2>/dev/null | head -n1)"
    printf ',"dns_id":'; json_quote "$(sed -n 's/^dns_id=//p' "$_d/state" 2>/dev/null | head -n1)"
    printf ',"started":'; json_quote "$(sed -n 's/^started=//p' "$_d/state" 2>/dev/null | head -n1)"
    printf ',"finished":'; json_quote "$(sed -n 's/^finished=//p' "$_d/state" 2>/dev/null | tail -n1)"
    printf ',"output":'; json_quote "$(tail -n 80 "$_d/output" 2>/dev/null || true)"
    printf '}' 
}
log_json() { _n="$1"; case "$_n" in ''|*[!0-9]*) _n=80;; esac; [ "$_n" -gt 300 ] && _n=300; printf '{"ok":true,"log":'; json_quote "$(tail -n "$_n" /var/log/dns-manager.log 2>/dev/null || true)"; printf '}'; }

catalog_json() {
    _category="$(jget category)"; _offset="$(jget offset)"; _limit="$(jget limit)"; _only_ok="$(jget only_ok)"
    case "$_offset" in ''|*[!0-9]*) _offset=0;; esac; case "$_limit" in ''|*[!0-9]*) _limit=18;; esac; [ "$_limit" -gt 48 ] && _limit=48; [ -n "$_category" ] || _category=all
    case "$_category" in all|bypass|security|privacy|adblock|family|clean|regional) ;; *) json_error "Неверная категория DNS"; return;; esac
    case "$_only_ok" in 1|0) ;; *) _only_ok=0;; esac
    [ -s "$CATALOG_FILE" ] || { json_error "Каталог DNS недоступен"; return; }
    _filtered="$TMP_ROOT/catalog-filtered.$$"; _paged="$TMP_ROOT/catalog-page.$$"; : > "$_filtered"; : > "$_paged"
    while IFS='|' read -r _id _cat _prof _name _url _region _status; do
        case "$_id" in ''|\#*) continue;; esac
        [ "$_category" = all ] || [ "$_cat" = "$_category" ] || continue
        if [ "$_only_ok" = 1 ]; then _r="$(result_for_id "$_id" 2>/dev/null || true)"; _st="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"; [ "$_st" = OK ] || continue; fi
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$_id" "$_cat" "$_prof" "$_name" "$_url" "$_region" "$_status" >> "$_filtered"
    done < "$CATALOG_FILE"
    _total="$(wc -l < "$_filtered" 2>/dev/null | tr -d ' ')"; case "$_total" in ''|*[!0-9]*) _total=0;; esac
    [ "$_total" -gt "$_offset" ] && sed -n "$((_offset+1)),$((_offset+_limit))p" "$_filtered" > "$_paged" 2>/dev/null || true
    printf '{"ok":true,"version":'; json_quote "$(catalog_version)"; printf ',"category":'; json_quote "$_category"; printf ',"offset":%s,"limit":%s,"total":%s,"servers":[' "$_offset" "$_limit" "$_total"
    _first=1
    while IFS='|' read -r _id _cat _prof _name _url _region _status; do
        [ -n "$_id" ] || continue; [ "$_first" = 1 ] || printf ','; _first=0; _r="$(result_for_id "$_id" 2>/dev/null || true)"; _ms="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $4;exit}')"; _st="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"
        printf '{"id":'; json_quote "$_id"; printf ',"category":'; json_quote "$_cat"; printf ',"name":'; json_quote "$_name"; printf ',"url":'; json_quote "$_url"; printf ',"region":'; json_quote "$_region"; printf ',"catalog_status":'; json_quote "$_status"; printf ',"ping":'; json_quote "$_ms"; printf ',"status":'; json_quote "$_st"; printf ',"last_check":'; json_quote "$(last_check_for_id "$_id")"; printf '}'
    done < "$_paged"
    printf ']}'; rm -f "$_filtered" "$_paged" 2>/dev/null || true
}

run_action() {
    _profile="$(jget profile)"
    case "${RPC_METHOD:-}" in
        set_profile)
            case "$_profile" in clean2) _profile=clean;; bypass|clean|security|privacy|adblock|family|all) ;; *) json_error "Неверный профиль"; return;; esac
            load_manager || { json_error "DNS Manager недоступен"; return; }
            DNS_MANAGER_NO_UPDATE=1 SILENT_APPLY=1 HYBRID_SELECTION_QUIET=1 apply_profile_now "$_profile" >/dev/null 2>&1 && json_ok || json_error "Профиль не удалось применить"
            ;;
        set_slot)
            _slot="$(jget slot)"; _id="$(jget id)"
            case "$_slot" in 1|2|3|4|5|6|RU|RU_2) ;; *) json_error "Неверный слот"; return;; esac
            case "$_id" in ''|*[!A-Za-z0-9_-]*) json_error "Неверный DNS ID"; return;; esac
            load_manager || { json_error "DNS Manager недоступен"; return; }
            _cat="$(dns_cat "$_id" 2>/dev/null || true)"; [ -n "$_cat" ] || { json_error "DNS не найден в каталоге"; return; }
            case "$_slot" in RU|RU_2) [ "$_cat" = regional ] || { json_error "Этот DNS нельзя поставить в региональный слот"; return; } ;; *) [ "$_cat" != regional ] || { json_error "Региональный DNS нельзя поставить в общий слот"; return; } ;; esac
            DNS_PROFILE=custom DNS_SELECTION_MODE=manual DNS_SELECTION_CATEGORY="$_cat"; eval "SLOT_$_slot=\"$_id\""; eval "SLOT_${_slot}_CAT=\"$_cat\""; [ "$_slot" = RU ] || [ "$_slot" = RU_2 ] && DNS_SELECTION_CATEGORY=regional || true
            sync_regional_dns_state >/dev/null 2>&1 || true; SILENT_APPLY=1 CORE_ONLY=1 DNS_MANAGER_NO_UPDATE=1 apply_settings >/dev/null 2>&1 && json_ok || json_error "DNS не удалось применить"
            ;;
        set_test_age)
            _category="$(jget category)"; _hours="$(jget hours)"
            case "$_category" in bypass|clean|security|privacy|adblock|family|regional) ;; *) json_error "Неверная категория DNS"; return;; esac
            case "$_hours" in ''|*[!0-9]*) json_error "Неверный срок проверки"; return;; esac
            [ "$_hours" -ge 1 ] 2>/dev/null && [ "$_hours" -le 168 ] 2>/dev/null || { json_error "Срок проверки должен быть от 1 до 168 часов"; return; }
            load_manager || { json_error "DNS Manager недоступен"; return; }
            _var="TEST_RESULTS_MAX_AGE_$(printf '%s' "$_category" | tr '[:lower:]' '[:upper:]')"
            eval "$_var=$((_hours*3600))"
            save_config >/dev/null 2>&1 && json_ok || json_error "Срок проверки не удалось сохранить"
            ;;
        set_setting)
            _name="$(jget name)"; _enabled="$(jget enabled)"; case "$_enabled" in 0|1) ;; *) json_error "Неверное значение enabled"; return;; esac; case "$_name" in watchdog|force|mtu|sysctl|sysctl_ext|ntp_clients|dnsmasq_perf|client_fixes) ;; *) json_error "Недопустимая настройка"; return;; esac
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

test_json() { case "${RPC_METHOD:-}" in test_all) job_start_test_all;; test_current) job_start_test_current;; test_one) job_start_test_one "$(jget id)";; *) json_error "Недопустимый метод проверки";; esac; }

case "${1:-}" in
    list)
        printf '{"status":{},"catalog":{"category":"String","offset":0,"limit":0,"only_ok":0},"update_check":{},"update":{},"update_manager":{},"update_hdp":{},"update_catalog":{},"update_all":{},"set_profile":{"profile":"String"},"set_slot":{"slot":"String","id":"String"},"set_setting":{"name":"String","enabled":0},"set_test_age":{"category":"String","hours":0},"test_all":{},"test_current":{},"test_one":{"id":"String"},"job":{"id":"String"},"log":{"lines":0}}\n'
        ;;
    call)
        case "${2:-}" in
            status) status_json;;
            catalog) INPUT="$(cat 2>/dev/null || true)"; catalog_json;;
            update_check) update_check_json;;            update_catalog) update_catalog_json;;            update_all) update_all_json;;            update) update_json;;            update_manager) update_manager_json;;            update_hdp) update_hdp_json;;
            set_profile|set_slot|set_setting) INPUT="$(cat 2>/dev/null || true)"; RPC_METHOD="$2"; run_action;;
            test_all|test_current|test_one) INPUT="$(cat 2>/dev/null || true)"; RPC_METHOD="$2"; test_json;;
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

// DNS Manager LuCI version: 1.3.6
var callStatus = rpc.declare({ object:'dns_manager', method:'status', expect:{} });
var callCatalog = rpc.declare({ object:'dns_manager', method:'catalog', params:['category','offset','limit','only_ok'], expect:{} });
var callUpdateCheck = rpc.declare({ object:'dns_manager', method:'update_check', expect:{} });
var callUpdate = rpc.declare({ object:'dns_manager', method:'update', expect:{} });
var callManagerUpdate = rpc.declare({ object:'dns_manager', method:'update_manager', expect:{} });
var callHdpUpdate = rpc.declare({ object:'dns_manager', method:'update_hdp', expect:{} });
var callUpdateCatalog = rpc.declare({ object:'dns_manager', method:'update_catalog', expect:{} });
var callProfile = rpc.declare({ object:'dns_manager', method:'set_profile', params:['profile'], expect:{} });
var callSlot = rpc.declare({ object:'dns_manager', method:'set_slot', params:['slot','id'], expect:{} });
var callSetting = rpc.declare({ object:'dns_manager', method:'set_setting', params:['name','enabled'], expect:{} });
var callTestAge = rpc.declare({ object:'dns_manager', method:'set_test_age', params:['category','hours'], expect:{} });
var callTestAll = rpc.declare({ object:'dns_manager', method:'test_all', expect:{} });
var callTestCurrent = rpc.declare({ object:'dns_manager', method:'test_current', expect:{} });
var callTestOne = rpc.declare({ object:'dns_manager', method:'test_one', params:['id'], expect:{} });
var callJob = rpc.declare({ object:'dns_manager', method:'job', params:['id'], expect:{} });
var callLog = rpc.declare({ object:'dns_manager', method:'log', params:['lines'], expect:{} });

var PROFILE = [
  ['bypass','Максимальный обход'], ['clean','Максимальная скорость'],
  ['security','Максимальная безопасность'], ['privacy','Максимальная приватность'],
  ['adblock','Блокировка рекламы'], ['family','Семейный'], ['all','Выбор по категориям']
];
var CATEGORY = [
  ['all','Все DNS'], ['bypass','Обход блокировок'], ['security','Безопасность'], ['privacy','Приватность'],
  ['adblock','Блокировка рекламы'], ['family','Семейный'], ['clean','Без фильтрации'], ['regional','Региональные']
];
var state = { hdpUpdating:false, managerUpdating:false, updatingAll:false, category:'all', offset:0, limit:18, catalogLoaded:false, catalogLoading:false, advanced:true, logLoaded:false, logLoading:false, busy:false, busySetting:'', settingMessage:'', settingMessageType:'', pageNotice:{}, statusError:'', updateKick:false, activeTab:'dashboard', jobRunning:false, lastJob:null, checking:{}, fullTest:null, versionCheck:null, autoRefreshRoot:null, lastAction:null };

function profileName(p){
  var x=PROFILE.filter(function(v){return v[0]===p;})[0];
  return x?x[1]:(p==='hybrid'?'Максимальный обход':p==='custom'?'Собственный выбор':(p||'—'));
}
function catName(c){ var x=CATEGORY.filter(function(v){return v[0]===c;})[0]; return x?x[1]:(c||'—'); }
function ping(v){ return v && /^\d+$/.test(String(v)) ? v+' мс' : '—'; }
function uptime(sec){ var n=Number(sec||0); if(!isFinite(n)||n<0)return '—'; var d=Math.floor(n/86400); n%=86400; var h=Math.floor(n/3600); n%=3600; var m=Math.floor(n/60); var s=Math.floor(n%60); return (d?d+' дн ':'')+(d||h?h+' ч ':'')+m+' мин '+s+' с';}
function memory(total,avail){ var t=Number(total||0),a=Number(avail||0); if(!t)return '—'; return Math.max(0,Math.round((t-a)/1024))+' / '+Math.round(t/1024)+' МБ'; }
function memoryPercent(total,avail){
  var t=Number(total||0),a=Number(avail||0);
  if(!isFinite(t)||t<=0||!isFinite(a))return null;
  var p=Math.round(((t-Math.max(0,a))/t)*100);
  return Math.max(0,Math.min(100,p));
}
function memoryBar(total,avail){
  var p=memoryPercent(total,avail);
  if(p===null)return E('span',{},'—');
  return E('div',{'class':'dm-mem-wrap'},[
    E('div',{'class':'dm-mem-line'},[
      E('div',{'class':'dm-mem-track'},[E('div',{'class':'dm-mem-fill','style':'width:'+p+'%'})]),
      E('span',{'class':'dm-mem-value'},memory(total,avail))
    ]),
    E('div',{'class':'dm-mem-meta'},p+'% занято')
  ]);
}
function loadPercent(load1,cores){
  var n=Number(load1),c=Number(cores||1);
  if(!isFinite(n)||n<0||!isFinite(c)||c<1)return null;
  var p=Math.round((n/c)*100);
  return Math.max(0,Math.min(100,p));
}
function loadBar(load1,cores){
  var p=loadPercent(load1,cores);
  if(p===null)return E('span',{},'—');
  return E('div',{'class':'dm-load-wrap'},[
    E('div',{'class':'dm-load-line'},[
      E('div',{'class':'dm-load-track'},[E('div',{'class':'dm-load-fill','style':'width:'+p+'%'})]),
      E('span',{'class':'dm-load-value'},p+'%')
    ]),
    E('div',{'class':'dm-load-meta'},'load '+shortVal(load1)+' · '+String(cores||1)+' '+(Number(cores||1)===1?'ядро':'ядра'))
  ]);
}
function badge(kind,text){ return E('span',{'class':'dm-badge '+kind},[E('span',{'class':'dm-dot'}),text]); }
function btn(label,cls,fn,extra){ var a={'class':'cbi-button '+(cls||''),'type':'button','click':function(ev){ if(ev&&ev.preventDefault)ev.preventDefault(); return fn?fn.call(this,ev):undefined; }}; Object.keys(extra||{}).forEach(function(k){ if(k==='disabled'){ if(extra[k]) a.disabled=true; } else { a[k]=extra[k]; } }); return E('button',a,label); }
function row(label,node){ return E('div',{'class':'dm-row'},[E('span',{'class':'dm-label'},label),E('span',{'class':'dm-row-value'},node)]); }
function card(title,children,cls){ return E('div',{'class':'dm-card '+(cls||'')},[E('h3',{},title)].concat(children||[])); }
function forceMode(st){ return st.force==='1' ? 'auto' : 'off'; }
function forceModeLabel(m){ return m==='auto' ? 'Авто (рекомендуется)' : 'Не перехватывать'; }
function yes(v){ return v===1 || v==='1' || v===true; }
function dateText(v){ if(!v || !/^\d+$/.test(String(v))) return '—'; try { return new Date(Number(v)*1000).toLocaleString(); } catch(e){ return '—'; } }
function shortVal(v){ return (v===undefined || v===null || v==='') ? '—' : String(v); }
function confirmAction(title, rows, onConfirm){
  var body=[];
  (rows||[]).forEach(function(x){ body.push(row(x[0],E('span',{},String(x[1])))); });
  ui.showModal(title,[E('div',{'class':'dm-confirm-body'},body),E('div',{'class':'right'},[
    btn('Отмена','cbi-button-negative',ui.hideModal),
    btn('Применить','cbi-button-apply',function(){ui.hideModal();onConfirm();})
  ])]);
}
function setAction(ok,text){state.lastAction={ok:!!ok,text:String(text||'')};}
function renderActionStatus(){
  if(!state.lastAction||!state.lastAction.text)return null;
  return E('div',{'class':'dm-applied '+(state.lastAction.ok?'ok':'error')},[
    E('strong',{},state.lastAction.ok?'Применено':'Ошибка'),
    E('span',{},state.lastAction.text)
  ]);
}
function stripAnsi(s){
  return String(s||'')
    .replace(/\x1B\[[0-?]*[ -\/]*[@-~]/g,'')
    .replace(/\[[0-9;?]*[ -\/]*[@-~]/g,'')
    .replace(/[0-9]+(?:;[0-9]+)*m/g,'')
    .replace(/\r/g,'');
}
function hasPing(v){ return /^\d+$/.test(String(v===undefined||v===null?'':v)); }
function stateBadge(status,pingValue){
  var s=String(status||'').toUpperCase();
  if(s==='RUNNING')return badge('dm-warn','проверяется');
  if(s==='OK'&&hasPing(pingValue))return badge('dm-ok','доступен');
  if(s==='OK'||s==='FAIL'||s==='FAILED'||s.indexOf('_FAIL')>0||s.indexOf('TIMEOUT')>=0||s.indexOf('ERROR')>=0||s.indexOf('HTTP_')===0||!hasPing(pingValue))return badge('dm-bad','недоступен');
  return badge('dm-off','нет данных');
}
function settingName(n){ var m={watchdog:'Автопроверка и замена DNS',mtu:'Исправление MTU и MSS для WAN',sysctl:'Оптимизация TCP и таблицы соединений',sysctl_ext:'Расширенные параметры TCP и сетевых буферов',ntp_clients:'Время для устройств в локальной сети',dnsmasq_perf:'Увеличенный кэш DNS',client_fixes:'DNS для проверки подключения и совместимости устройств'}; return m[n]||n; }
function versionState(v,available,latest,checked,okWord,pending){
  if(pending)return badge('dm-warn','проверяется…');
  if(!v)return badge('dm-bad','не установлена');
  if(yes(available))return badge('dm-warn',shortVal(v)+' → '+shortVal(latest||'новая версия')+' · неактуальна');
  if(latest&&String(v)===String(latest))return badge('dm-ok',shortVal(v)+' · '+okWord);
  if(yes(checked))return badge('dm-ok',shortVal(v)+' · '+okWord);
  return badge('dm-off',shortVal(v)+' · проверка не выполнена');
}
function catalogVersionState(v,rev,total,available,latest,latestRev,checked,pending){
  if(pending)return badge('dm-warn','проверяется…');
  if(!v)return badge('dm-bad','не установлен');
  var local=shortVal(v)+(rev?' rev.'+shortVal(rev):'');
  if(yes(available)){
    var tail=latest?shortVal(latest):'новая версия';
    if(latestRev)tail+=' rev.'+shortVal(latestRev);
    return badge('dm-warn',local+' → '+tail+' · неактуален');
  }
  if(yes(checked)&&latest)return badge('dm-ok',local+' · актуален');
  return badge('dm-off',local+' · проверка не выполнена');
}

function injectStyle(root){
  var css = ''+
  '.dm-wrap{display:flex;flex-direction:column;gap:12px;width:100%;max-width:none;box-sizing:border-box;padding-bottom:28px}'+
  '.dm-header{display:flex;align-items:center;gap:9px;flex-wrap:wrap}.dm-header h2{margin:0;font-size:22px;font-weight:700}.dm-header-by{font-size:13px;opacity:.60}.dm-header-actions{display:flex;gap:7px;margin-left:auto;flex-wrap:wrap}.dm-header-actions .cbi-button{padding:5px 11px;font-size:12.5px}'+
  '.dm-load-wrap{min-width:220px;max-width:430px;width:100%}.dm-load-line{display:flex;align-items:center;gap:9px}.dm-load-track{height:8px;flex:1;min-width:120px;border-radius:999px;background:rgba(110,118,129,.16);overflow:hidden}.dm-load-fill{height:100%;border-radius:999px;background:#1a7f37;transition:width .25s ease}.dm-load-value{min-width:38px;font-size:12px;font-weight:700;text-align:right}.dm-load-meta{font-size:10.5px;opacity:.58;margin-top:3px}'+
  '.dm-mem-wrap{min-width:220px;max-width:430px;width:100%}.dm-mem-line{display:flex;align-items:center;gap:9px}.dm-mem-track{height:8px;flex:1;min-width:120px;border-radius:999px;background:rgba(110,118,129,.16);overflow:hidden}.dm-mem-fill{height:100%;border-radius:999px;background:#1a7f37;transition:width .25s ease}.dm-mem-value{font-size:12px;font-weight:700;white-space:nowrap}.dm-mem-meta{font-size:10.5px;opacity:.58;margin-top:3px}'+
  '.dm-card{min-width:0;box-sizing:border-box;background:var(--background-color-medium,#fff);border:1px solid rgba(0,0,0,.08);border-radius:11px;padding:15px 18px;box-shadow:0 1px 3px rgba(0,0,0,.04),0 1px 2px rgba(0,0,0,.03);overflow-wrap:break-word}.dm-card:hover{box-shadow:0 2px 7px rgba(0,0,0,.06)}'+
  'html.dm-theme-dark .dm-card{background:#1c2128;border-color:rgba(255,255,255,.10);box-shadow:0 1px 3px rgba(0,0,0,.22)}'+
  '.dm-version-action{display:flex;align-items:center;gap:7px;flex-wrap:wrap}.dm-version-action .cbi-button{padding:4px 9px;font-size:12px}.dm-version-line{display:flex;align-items:center;gap:9px;margin:7px 0;flex-wrap:wrap}.dm-version-name{font-size:13px;font-weight:600;flex:0 1 160px;min-width:135px}.dm-version-state{min-width:0;flex:1 1 auto}.dm-card h3{margin:0 0 10px;font-size:15px;font-weight:600;display:flex;align-items:center;gap:7px}.dm-row{display:flex;align-items:center;gap:10px;margin:6px 0;font-size:13px;flex-wrap:wrap}.dm-label{opacity:.65;flex-shrink:0}.dm-row-value{overflow-wrap:anywhere}'+
  '.dm-badge{display:inline-flex;align-items:center;gap:6px;padding:3px 10px;border-radius:999px;font-size:12px;font-weight:600;white-space:nowrap}.dm-dot{width:8px;height:8px;border-radius:50%;display:inline-block;flex-shrink:0}'+
  '.dm-ok{background:rgba(46,160,67,.12);color:#1a7f37}.dm-ok .dm-dot{background:#1a7f37}.dm-bad{background:rgba(207,34,46,.10);color:#cf222e}.dm-bad .dm-dot{background:#cf222e}.dm-warn{background:rgba(191,135,0,.12);color:#9a6700}.dm-warn .dm-dot{background:#9a6700}.dm-off{background:rgba(110,118,129,.12);color:#57606a}.dm-off .dm-dot{background:#57606a}'+
  '.dm-grid2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.dm-grid3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}.dm-grid4{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}'+
  '.dm-actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:11px}.dm-component-item{padding:8px 0;border-bottom:1px solid rgba(110,118,129,.14)}.dm-component-group{padding:8px 0;border-bottom:1px solid rgba(110,118,129,.14)}.dm-component-dns-list{margin-top:6px;display:flex;flex-direction:column;gap:5px}.dm-component-dns{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:6px 0;border-top:1px solid rgba(110,118,129,.08);flex-wrap:wrap}.dm-component-dns:first-child{border-top:0}.dm-component-dns-main{display:flex;align-items:center;gap:8px;min-width:0;flex:1 1 260px}.dm-component-dns-slot{font-size:11.5px;font-weight:700;opacity:.62;min-width:118px}.dm-component-dns-name{font-size:12.5px;font-weight:600;overflow-wrap:anywhere}.dm-component-dns-meta{display:flex;align-items:center;gap:9px;font-size:11.5px;opacity:.78;flex:0 0 auto}.dm-component-dns-ping{font-size:12px;white-space:nowrap;opacity:.8}.dm-component-item:last-of-type{border-bottom:0}.dm-component-head{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap}.dm-component-title{font-size:13px;font-weight:600}.dm-component-details{font-size:11.5px;line-height:1.45;opacity:.66;margin-top:3px;overflow-wrap:anywhere}.dm-component-date{font-size:12.5px;opacity:.82}.dm-actions .cbi-button{margin:0;padding:5px 11px;font-size:12.5px}'+
  '.dm-hint{font-size:12.5px;opacity:.68;line-height:1.5;margin:0 0 8px}.dm-mini{font-size:11px;opacity:.62}.dm-meta{font-size:11px;line-height:1.45;opacity:.66}.dm-update{padding:8px 10px;border-radius:8px;background:rgba(26,127,55,.08);border:1px solid rgba(26,127,55,.18);font-size:12.5px;display:flex;gap:8px;align-items:center;flex-wrap:wrap}'+
  '.dm-seg{display:flex;flex-wrap:wrap;gap:6px;margin:5px 0}.dm-seg .cbi-button{padding:5px 11px;border-radius:7px;font-size:12.5px;font-weight:600}.dm-seg .active{background:#1a7f37;color:#fff;border-color:#1a7f37}'+
  '.dm-force-note{font-size:12px;line-height:1.55;opacity:.72}.dm-inline-msg{display:block;margin:8px 0 0;padding:7px 10px;border-radius:7px;font-size:12px;line-height:1.4}.dm-inline-msg.info{background:rgba(9,105,218,.08);border:1px solid rgba(9,105,218,.16)}.dm-inline-msg.ok{background:rgba(26,127,55,.08);border:1px solid rgba(26,127,55,.16)}.dm-inline-msg.error{background:rgba(207,34,46,.08);border:1px solid rgba(207,34,46,.16)}.dm-applied{display:flex;align-items:center;gap:9px;padding:9px 11px;border-radius:8px;font-size:12.5px;line-height:1.45}.dm-applied.ok{background:rgba(26,127,55,.08);border:1px solid rgba(26,127,55,.18)}.dm-applied.error{background:rgba(207,34,46,.08);border:1px solid rgba(207,34,46,.18)}.dm-applied strong{font-weight:700}.dm-confirm-body{min-width:min(440px,calc(100vw - 70px))}.dm-setting{padding:11px 12px}.dm-setting-title{font-size:13px;font-weight:600}.dm-setting-desc{font-size:11.5px;line-height:1.45;opacity:.68;margin-top:3px}.dm-setting-line{display:flex;align-items:center;justify-content:space-between;gap:10px}.dm-setting-actions{display:flex;align-items:center;gap:7px;flex-shrink:0}.dm-setting-actions .cbi-button{padding:4px 9px;font-size:12px}.dm-setting-saving{opacity:.7}.dm-force-external{padding:8px 10px;border-radius:8px;background:rgba(191,135,0,.10);border:1px solid rgba(191,135,0,.22);font-size:12.5px;line-height:1.5;margin-top:8px}'+
  '.dm-doh-list{display:flex;flex-direction:column}.dm-doh-row{display:grid;grid-template-columns:140px minmax(180px,1fr) 80px 100px;gap:10px;align-items:center;padding:7px 0;border-top:1px solid rgba(0,0,0,.07);font-size:13px}.dm-doh-row:first-child{border-top:0}.dm-doh-name{font-weight:600}.dm-doh-url{overflow-wrap:anywhere;opacity:.88}.dm-doh-port,.dm-doh-ping{font-size:12px;opacity:.7;white-space:nowrap}'+
  '.dm-slot-table{display:flex;flex-direction:column}.dm-slot-row{display:grid;grid-template-columns:55px 135px minmax(180px,1fr) 85px 115px minmax(175px,auto);gap:14px;align-items:center;padding:7px 0;border-top:1px solid rgba(0,0,0,.07);font-size:13px}.dm-slot-row:first-child{border-top:0}.dm-slot-id{font-weight:700;opacity:.62}.dm-slot-name{font-weight:600;overflow-wrap:anywhere}.dm-slot-endpoint,.dm-slot-ping{font-size:12px;opacity:.72;white-space:nowrap}.dm-inline{display:flex;gap:6px;justify-content:flex-end}.dm-inline .cbi-button{padding:4px 9px;font-size:12px}.dm-assign-list{display:flex;flex-direction:column;gap:7px;min-width:min(430px,calc(100vw - 70px))}.dm-assign-item{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:9px 10px;border:1px solid rgba(0,0,0,.08);border-radius:8px}.dm-assign-info{min-width:0;flex:1}.dm-assign-slot{font-weight:700}.dm-assign-current{font-size:12px;opacity:.7;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}'+
  '.dm-catalog{display:grid;grid-template-columns:repeat(3,minmax(210px,1fr));gap:8px;margin-top:8px}.dm-catalog-item{padding:10px 11px}.dm-catalog-item h4{margin:0 0 4px;font-size:13px}.dm-page{display:flex;justify-content:center;align-items:center;gap:7px;margin-top:9px}.dm-log{white-space:pre-wrap;max-height:360px;overflow:auto;font:11px/1.45 monospace;padding:10px;background:#111820;color:#dbe4ec;border-radius:8px;margin-top:8px}'+
  '.dm-page-nav{position:sticky;top:0;z-index:20;padding:7px 0;background:var(--background-color-base,#fff);border-bottom:1px solid rgba(0,0,0,.08)}.dm-page-nav::before,.dm-page-nav::after{content:"";position:absolute;left:0;right:0;height:7px;background:var(--background-color-base,#fff);pointer-events:none}.dm-page-nav::before{top:-7px}.dm-page-nav::after{bottom:-7px}.dm-page-tabs{display:flex;align-items:stretch;gap:4px;overflow-x:auto;scrollbar-width:none;padding:0 2px}.dm-page-tabs::-webkit-scrollbar{display:none}.dm-page-tab{flex:0 0 auto;padding:7px 12px!important;border-radius:8px 8px 0 0!important;font-size:12.5px!important;font-weight:600!important;border:1px solid transparent!important;background:transparent!important;box-shadow:none!important}.dm-page-tab:hover{background:rgba(0,0,0,.05)!important}.dm-page-tab.active{background:var(--background-color-medium,#fff)!important;border-color:rgba(0,0,0,.12)!important;border-bottom-color:var(--background-color-medium,#fff)!important}.dm-page-nav-title{display:none}.dm-wrap>section{scroll-margin-top:58px}'+
  '.dm-section-title{font-size:12px;letter-spacing:.02em;text-transform:none;opacity:.62;margin:3px 0 0;padding:0 2px}'+
  '@media(max-width:850px){.dm-grid2{grid-template-columns:1fr}.dm-grid4{grid-template-columns:repeat(2,minmax(0,1fr))}.dm-doh-row{grid-template-columns:120px minmax(140px,1fr) 70px}.dm-doh-ping{display:none}.dm-slot-row{grid-template-columns:48px 115px minmax(130px,1fr) 85px 105px auto}.dm-slot-ping{display:none}.dm-catalog{grid-template-columns:repeat(2,minmax(0,1fr))}}'+
  '@media(max-width:560px){.dm-grid3,.dm-grid4,.dm-catalog{grid-template-columns:1fr}.dm-header-actions{margin-left:0}.dm-doh-row{grid-template-columns:1fr auto}.dm-doh-url{grid-column:1/3}.dm-doh-port{grid-column:1}.dm-slot-row{grid-template-columns:40px minmax(0,1fr) auto}.dm-slot-endpoint{display:none}.dm-slot-state{display:none}.dm-inline{grid-column:2/4;justify-content:flex-start}}';
  root.appendChild(E('style',{},css));
}

function rootAlive(root){return !!root&&!!document&&!!document.documentElement&&document.documentElement.contains(root);}
function globalUpdateNotice(msg,type){var id='dm-global-update-notice',old=document.getElementById(id);if(old)old.remove();if(!msg)return;var n=E('div',{'id':id,'class':'dm-inline-msg '+(type||'info')},msg);n.style.position='fixed';n.style.left='50%';n.style.top='18px';n.style.transform='translateX(-50%)';n.style.zIndex='99999';n.style.maxWidth='min(760px,calc(100vw - 32px))';n.style.boxShadow='0 6px 24px rgba(0,0,0,.18)';document.body.appendChild(n);}
function renderHeader(root,st){
  var e=root.querySelector('#dm-header');if(!e)return;e.innerHTML='';
  var lastTest=dateText(st.last_full_test);
  var testText=lastTest==='—'?'Последняя полная проверка DNS: не выполнялась':'Последняя полная проверка DNS: '+lastTest;
  e.appendChild(E('div',{'class':'dm-header'},[
    E('h2',{},'DNS Manager by PoTuStoronu222'),
    E('span',{'class':'dm-header-by'},'v'+shortVal(st.luci_version)),
    E('span',{'class':'dm-header-by'},'· '+testText)
  ]));
}
function setActiveTab(root,name){
  var groups={
    dashboard:['overview','test-inline'],
    doh:['doh'],
    dns:['slots'],
    profiles:['profiles'],
    settings:['settings'],
    catalog:['catalog'],
    test:['job','test-inline'],
    log:['log']
  };
  state.activeTab=groups[name]?name:'dashboard';
  ['overview','doh','slots','profiles','settings','job','catalog','log','test-inline'].forEach(function(id){
    var panel=root.querySelector('#dm-'+id);
    if(panel) panel.style.display='none';
  });
  (groups[state.activeTab]||groups.dashboard).forEach(function(id){
    var panel=root.querySelector('#dm-'+id);
    if(panel) panel.style.display='block';
  });
  if(state.activeTab==='catalog'&&!window.dmCatalog&&!state.catalogLoading)loadCatalog(root);
  if(state.activeTab==='log'&&!state.logLoaded&&!state.logLoading)showLog(root);
}
function routeUrl(name){return '/cgi-bin/luci/admin/services/dns-manager/'+name;}
function currentRoute(){
  var p=String((window.location&&window.location.pathname)||'');
  var m=p.match(/\/admin\/services\/dns-manager\/([^/?#]+)/);
  return m&&m[1]?m[1]:'dashboard';
}
function renderPageNav(root){
  var e=root.querySelector('#dm-page-nav');if(!e)return;e.innerHTML='';
  var tabs=[['dashboard','Дашборд'],['doh','DNS over HTTPS'],['dns','Текущие DNS'],['profiles','Профили'],['settings','Настройки'],['catalog','Каталог DNS'],['test','Проверка'],['log','Журнал']];
  var route=currentRoute();
  var nav=E('nav',{'class':'dm-page-nav'});
  var bar=E('div',{'class':'dm-page-tabs'});
  tabs.forEach(function(x){
    bar.appendChild(E('a',{'class':'dm-page-tab '+(route===x[0]?'active':''),'href':routeUrl(x[0])},x[1]));
  });
  nav.appendChild(bar);
  e.appendChild(nav);
}
function checkInfo(id,d){
  var x=state.checking&&state.checking[id];
  var r=x&&x.status?{status:x.status,ping:x.ping||''}:{status:d&&d.status?d.status:'',ping:d&&d.ping?d.ping:''};
  if(String(r.status||'').toUpperCase()==='OK'&&!hasPing(r.ping))r.status='FAIL';
  return r;
}
function componentItem(title,statusNode,details){
  return E('div',{'class':'dm-component-item'},[
    E('div',{'class':'dm-component-head'},[
      E('span',{'class':'dm-component-title'},title),
      statusNode
    ]),
    details?E('div',{'class':'dm-component-details'},details):E('span',{})
  ]);
}
function componentSettingItem(title,key){
  var en=yes((window.dmState||{})[key]);
  return componentItem(title,badge(en?'dm-ok':'dm-off',en?'включено':'выключено'));
}
function renderOverview(root,st){
  var e=root.querySelector('#dm-overview');if(!e)return;e.innerHTML='';
  var applied=renderActionStatus();if(applied)e.appendChild(applied);
  if(state.statusError)e.appendChild(E('div',{'class':'dm-inline-msg error'},state.statusError+' Проверьте: ubus call dns_manager status.'));

  var doh=st.doh==='yes'?badge('dm-ok','запущен'):Number(st.doh_total||0)>0?badge('dm-bad','остановлен'):badge('dm-off','не установлен');

  var force=yes(st.force_both)?badge('dm-warn','DNS Manager + внешний'):st.force_owner==='external'?badge('dm-warn','внешний сервис'):yes(st.force_manager)?badge('dm-ok','DNS Manager'):badge('dm-off','выключен');
  var forceDetails=st.force_owner==='external'?'Источник: '+shortVal(st.force_source||'внешний сервис'):st.force_both?'Одновременно DNS Manager и внешний перехват':yes(st.force_manager)?'DNS Manager':'выключен';

  var wd=yes(st.watchdog)?(st.watchdog_backend==='procd'?(Number(st.watchdog_loop||0)===1?badge('dm-ok','работает'):Number(st.watchdog_service||0)===1?badge('dm-warn','служба запущена, цикл не найден'):badge('dm-bad','служба не запущена')):badge('dm-warn','неизвестный механизм')):badge('dm-off','выключена');
  var wdDetails=yes(st.watchdog)?'интервал '+shortVal(st.watchdog_interval)+' с · порог '+shortVal(st.watchdog_fail_threshold)+' цикла':'автопроверка отключена';

  var profile=badge('dm-ok',profileName(st.profile));


  var dnsItems=[];
  (st.slots||[]).forEach(function(d){
    if(!d||!d.id)return;
    var slot=d.slot||'—';
    var name=d.name||d.id;
    var ci=checkInfo(d.id,d);
    var sn=String(ci.status||d.status||'').toUpperCase();
    var statusNode=sn==='RUNNING'?badge('dm-warn','проверяется'):sn==='OK'&&hasPing(ci.ping||d.ping)?badge('dm-ok','доступен'):sn==='OK'?badge('dm-off','есть, но без пинга'):sn?badge('dm-bad','недоступен'):badge('dm-off','нет данных');
    dnsItems.push(E('div',{'class':'dm-component-dns'},[
      E('div',{'class':'dm-component-dns-main'},[
        E('span',{'class':'dm-component-dns-slot'},slotLabel(slot)),
        E('span',{'class':'dm-component-dns-name'},name)
      ]),
      E('div',{'class':'dm-component-dns-meta'},[
        E('span',{'class':'dm-component-dns-ping'},ping(ci.ping||d.ping)),
        statusNode
      ])
    ]));
  });
  if(!dnsItems.length)dnsItems.push(E('div',{'class':'dm-hint'},'DNS в слоты не назначены.'));

  var components=card('Компоненты',[
    componentItem('Профиль DNS',profile),
    componentItem('Автопроверка и замена DNS',wd,wdDetails),
    componentItem('Принудительный DNS для устройств',force,forceDetails),
    componentSettingItem('Исправление MTU и MSS для WAN','mtu'),
    componentSettingItem('Оптимизация TCP и таблицы соединений','sysctl'),
    componentSettingItem('Расширенные параметры TCP и сетевых буферов','sysctl_ext'),
    componentSettingItem('Увеличенный кэш DNS','dnsmasq_perf'),
    componentSettingItem('Время для устройств в локальной сети','ntp_clients'),
    componentSettingItem('DNS для проверки подключения и совместимости устройств','client_fixes')
  ]);

  var dnsSlotsCard=E('div',{'class':'dm-card'},[
    E('h3',{},[
      E('span',{},'DNS over HTTPS'),
      doh
    ]),
    E('div',{'class':'dm-component-dns-list'},dnsItems),
    E('div',{'class':'dm-actions'},[
      btn('Проверить DNS в слотах','cbi-button-action',function(){testCurrent(root);},{disabled:!!state.busy||state.jobRunning})
    ])
  ]);

  var ipv4=st.ipv4==='yes'?badge('dm-ok','есть'):badge('dm-bad','нет');
  var ipv6=st.ipv6==='yes'?badge('dm-ok','есть'):badge('dm-off','выключен');

  var sysCard=card('Система',[
    row('Модель',shortVal(st.hostname)),
    row('OpenWrt',shortVal(st.openwrt)),
    row('Время работы',E('span',{'class':'dm-uptime'},uptime(st.uptime))),
    row('IPv4',ipv4),
    row('IPv6',ipv6),
    row('Нагрузка',loadBar(st.load1,st.cpu_count)),
    row('RAM',memoryBar(st.memory_total_kb,st.memory_available_kb)),
    row('LAN',shortVal(st.lan))
  ]);

  var verCard=card('Версии',[
    E('div',{'class':'dm-version-line'},[
      E('span',{'class':'dm-version-name'},'DNS Manager'),
      E('span',{'class':'dm-version-state'},versionState(st.manager_version,st.manager_update_available,st.manager_latest_version,st.manager_check_ok,'актуальна',state.versionCheck&&state.versionCheck.manager==='running'))
    ]),
    E('div',{'class':'dm-version-line'},[
      E('span',{'class':'dm-version-name'},'LuCI'),
      E('span',{'class':'dm-version-state'},versionState(st.luci_version,st.luci_update_available,st.luci_latest_version,st.luci_update_checked,'актуальна',state.versionCheck&&state.versionCheck.luci==='running'))
    ]),
    E('div',{'class':'dm-version-line'},[
      E('span',{'class':'dm-version-name'},'Защищённый DNS'),
      E('span',{'class':'dm-version-state'},versionState(st.hdp_version,st.hdp_update_available,st.hdp_latest_version,true,'актуальна',state.versionCheck&&state.versionCheck.hdp==='running'))
    ]),
    E('div',{'class':'dm-version-line'},[
      E('span',{'class':'dm-version-name'},'Каталог DNS'),
      E('span',{'class':'dm-version-state'},catalogVersionState(st.catalog_version,st.catalog_revision,st.catalog_total,st.catalog_update_available,st.catalog_latest_version,st.catalog_latest_rev,st.catalog_check_ok,state.versionCheck&&state.versionCheck.catalog==='running'))
    ]),
    row('Проверено',dateText(st.components_checked_at)),
    E('div',{'class':'dm-actions'},[
      btn('Проверить актуальность','cbi-button-neutral',function(){checkUpdate(root);}),
      (yes(st.manager_update_available)||yes(st.luci_update_available)||yes(st.hdp_update_available)||yes(st.catalog_update_available)) ?
        btn(state.updatingAll?'Обновляю…':'Обновить','cbi-button-positive',function(){updateAll(root);},{disabled:!!state.updatingAll||!!state.busy}) :
        null
    ].filter(Boolean))
  ]);

  e.appendChild(E('div',{'class':'dm-grid2'},[sysCard,verCard]));
  e.appendChild(dnsSlotsCard);
  e.appendChild(components);

  var fullState='';
  if(state.fullTest&&state.fullTest.status==='RUNNING')fullState=E('div',{'class':'dm-inline-msg info'},'Полная проверка DNS выполняется. Интерфейс обновляется автоматически.');
  else if(state.fullTest&&state.fullTest.status==='DONE')fullState=E('div',{'class':'dm-inline-msg ok'},'Полная проверка DNS завершена.');
  else if(state.fullTest&&state.fullTest.status==='FAILED')fullState=E('div',{'class':'dm-inline-msg error'},'Полная проверка DNS завершилась с ошибкой.');
  if(fullState)e.appendChild(fullState);
}
function resolverRows(st){
  var out=[],seen=0;
  (st.slots||[]).forEach(function(d){if(!d.id)return;seen++;out.push(E('div',{'class':'dm-doh-row'},[
    E('span',{'class':'dm-doh-slot'},d.slot||'—'),E('span',{'class':'dm-doh-name'},d.name||d.id),E('span',{'class':'dm-doh-url'},d.url||'—'),
    E('span',{'class':'dm-doh-port'},d.port?'порт '+d.port:'—'),E('span',{'class':'dm-doh-ping'},ping(d.ping)),E('span',{'class':'dm-doh-state'},stateBadge(d.status,d.ping))
  ]));});
  return [out,seen];
}

function renderDoH(root,st){
  var e=root.querySelector('#dm-doh');if(!e)return;e.innerHTML='';
  var rr=resolverRows(st), rows=rr[0], count=rr[1];
  var ch=[];
  ch.push(E('p',{'class':'dm-hint'},'Шифрованный DNS для всей сети: запросы устройств уходят к выбранным резолверам по HTTPS.'));
  ch.push(row('Пакет',st.doh_total>0?badge('dm-ok','установлен'):badge('dm-off','не установлен')));
  ch.push(row('Служба',st.doh==='yes'?badge('dm-ok','включена'):st.doh_total>0?badge('dm-bad','остановлена'):badge('dm-off','не установлена')));
  if(count){
    ch.push(E('div',{'class':'dm-row'},[E('span',{'class':'dm-label'},count>1?'Сейчас используются':'Сейчас используется')]));
    ch.push(E('div',{'class':'dm-doh-list'},rows));
  } else ch.push(row('Сейчас используется',E('span',{},'резолверы не настроены')));

  var fm=forceMode(st);
  var external=st.force_owner==='external';
  var forceButtons=E('div',{'class':'dm-seg'},[
    btn('Перехватывать DNS',fm==='auto'?'active cbi-button':'cbi-button',function(){setForceMode('auto',root);},{disabled:external||state.busy}),
    btn('Не перехватывать',fm==='off'?'active cbi-button':'cbi-button',function(){setForceMode('off',root);},{disabled:external||state.busy})
  ]);
  ch.push(E('div',{'style':'margin-top:9px'},[E('div',{'class':'dm-row'},[E('span',{'class':'dm-label'},'Перехват DNS устройств'),badge(st.force_owner==='external'?'dm-warn':yes(st.force)?'dm-ok':'dm-off',st.force_owner==='external'?'внешний':yes(st.force)?'включён':'выключен')]),forceButtons]));

  if(st.force_both){
    ch.push(E('div',{'class':'dm-force-external'},'Принудительный DNS активен одновременно в DNS Manager и во внешнем перехвате. Источник внешнего перехвата: '+shortVal(st.force_source)+'. DNS Manager не отключает и не переназначает внешний путь.'));
  } else if(st.force_owner==='external'){
    ch.push(E('div',{'class':'dm-force-external'},'Обнаружен '+shortVal(st.force_source)+'. DNS Manager не изменяет внешний forced-DNS и не создаёт второй перехват.'));
  }
  if(state.pageNotice.doh)ch.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.doh));
  e.appendChild(card('DNS over HTTPS',ch));
}

function slotLabel(slot){var m={'1':'DNS 1','2':'DNS 2','3':'DNS 3','4':'DNS 4','5':'DNS 5','6':'DNS 6','RU':'Региональный DNS 1','RU_2':'Региональный DNS 2'};return m[slot]||('DNS '+slot);}
function slotCurrentName(slot){var st=window.dmState||{};for(var i=0;i<(st.slots||[]).length;i++){if(String(st.slots[i].slot)===String(slot))return st.slots[i].name||st.slots[i].id||'не назначен';}return 'не назначен';}
function assign(id,slot,root,nextName){
  if(state.busy)return;
  var current=slotCurrentName(slot),next=nextName||id;
  if(current===next)return;
  confirmAction('Подтвердить назначение DNS',[['Слот',slotLabel(slot)],['Сейчас',current],['Новый DNS',next]],function(){
    state.busy=true;state.pageNotice.slots='Назначаю «'+slotLabel(slot)+'»…';renderSlots(root,window.dmState||{});
    callSlot(slot,id).then(function(r){
      state.busy=false;
      if(r&&r.ok){setAction(true,slotLabel(slot)+': «'+next+'».');state.pageNotice.slots='DNS назначен в '+slotLabel(slot)+'.';}
      else{setAction(false,(r&&r.error)||'DNS не удалось применить.');state.pageNotice.slots=(r&&r.error)||'DNS не удалось применить.';}
      refresh(root,true);
    }).catch(function(){state.busy=false;setAction(false,'DNS не удалось применить.');state.pageNotice.slots='DNS не удалось применить.';refresh(root,true);});
  });
}
function openAssign(id,cat,root){var slots=cat==='regional'?['RU','RU_2']:['1','2','3','4','5','6'];var targetName=((window.dmCatalog&&window.dmCatalog.servers)||[]).filter(function(x){return x.id===id;})[0];var box=E('div',{'class':'dm-assign-list'});slots.forEach(function(slot){box.appendChild(E('div',{'class':'dm-assign-item'},[E('div',{'class':'dm-assign-info'},[E('div',{'class':'dm-assign-slot'},slotLabel(slot)),E('div',{'class':'dm-assign-current'},'Сейчас: '+slotCurrentName(slot))]),btn('Далее','cbi-button-neutral',function(){ui.hideModal();assign(id,slot,root,targetName&&targetName.name);})]));});ui.showModal('Назначить DNS «'+(targetName&&targetName.name?targetName.name:id)+'»',[box,E('div',{'class':'right'},[btn('Отмена','cbi-button-negative',ui.hideModal)])]);}
function openSlotPicker(slot,root){if(state.busy)return;var regional=slot==='RU'||slot==='RU_2';callCatalog(regional?'regional':'all',0,48,0).then(function(d){var rows=(d.servers||[]).filter(function(x){return regional?x.category==='regional':x.category!=='regional';});var cur=slotCurrentName(slot);var sel=E('select',{'class':'cbi-input-select'});rows.forEach(function(x){sel.appendChild(E('option',{value:x.id},x.name+' — '+catName(x.category)+(x.name===cur?' · сейчас':'')));});ui.showModal('Выбор DNS для '+slotLabel(slot)+' · сейчас: '+cur,[sel,E('div',{'class':'right'},[btn('Отмена','cbi-button-negative',ui.hideModal),btn('Далее','cbi-button-apply',function(){var picked=sel.value,pickedName=sel.options[sel.selectedIndex]?sel.options[sel.selectedIndex].text.split(' — ')[0]:picked;ui.hideModal();assign(picked,slot,root,pickedName);})])]);}).catch(function(){state.pageNotice.slots='Не удалось открыть список DNS.';renderSlots(root,window.dmState||{});});}

function openForceDetails(root,st){
  var vals=[
    ['force_dns',shortVal(st.force)],['notrack_dns',shortVal(st.force_notrack)],['dnsmasq_config_update',shortVal(st.force_update)],
    ['force_dns_port',shortVal(st.force_ports)],['force_dns_src_interface',shortVal(st.force_src)],['force_ip_family',shortVal(st.force_family)],
    ['procd_trigger_wan6',shortVal(st.force_procd_trigger_wan6)],['heartbeat_domain',shortVal(st.force_heartbeat_domain)],
    ['heartbeat_sleep_timeout',shortVal(st.force_heartbeat_sleep)],['heartbeat_wait_timeout',shortVal(st.force_heartbeat_wait)],
    ['user / group',shortVal(st.force_user)+' / '+shortVal(st.force_group)],['listen_addr',shortVal(st.force_listen)],
    ['canary iCloud / Mozilla',shortVal(st.force_canary_icloud)+' / '+shortVal(st.force_canary_mozilla)],
    ['Согласованность',st.force_consistent===1||st.force_consistent==='1'?badge('dm-ok','соответствует'):badge('dm-warn','отличается')]
  ];
  var body=E('div',{}); vals.forEach(function(x){body.appendChild(row(x[0],E('span',{},x[1])));});
  ui.showModal('Параметры forced-DNS',[body,E('div',{'class':'right'},[btn('Закрыть','cbi-button-negative',ui.hideModal)])]);
}

function renderProfiles(root,st){
  var e=root.querySelector('#dm-profiles');if(!e)return;e.innerHTML='';
  var g=E('div',{'class':'dm-seg'});
  PROFILE.forEach(function(p){g.appendChild(btn(p[1],st.profile===p[0]?'active cbi-button':'cbi-button',function(){applyProfile(p[0],root);},{disabled:!!state.busy}));});
  var pch=[g,E('div',{'class':'dm-mini'},'Профиль задаёт схему выбора DNS.')];if(state.pageNotice.profiles)pch.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.profiles));e.appendChild(card('Профили DNS',pch));
}

function renderSlots(root,st){
  var e=root.querySelector('#dm-slots');if(!e)return;e.innerHTML='';var rows=[];
  (st.slots||[]).forEach(function(d){if(!d.id)return;rows.push(E('div',{'class':'dm-slot-row'},[
    E('span',{'class':'dm-slot-id'},d.slot),E('span',{'class':'dm-slot-name'},d.name||d.id),
    E('span',{'class':'dm-slot-endpoint'},d.port?'127.0.0.1:'+d.port:'—'),E('span',{'class':'dm-slot-ping'},ping(d.ping)),E('span',{'class':'dm-slot-state'},stateBadge(d.status,d.ping)),
    E('span',{'class':'dm-inline'},[btn('Выбрать','cbi-button-neutral',function(){openSlotPicker(d.slot,root);}),btn('Проверить','cbi-button-neutral',function(){testOne(d.id,root);})])
  ]));});
  if(!rows.length)rows.push(E('div',{'class':'dm-hint'},'DNS пока не настроены.'));
  var sch=[E('div',{'class':'dm-slot-table'},rows)];if(state.pageNotice.slots)sch.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.slots));e.appendChild(card('Выбранные DNS',sch));
}

function settingCard(root,x,st){
  var en=yes(st[x[0]]),busy=state.busySetting===x[0];
  return E('div',{'class':'dm-card dm-setting '+(busy?'dm-setting-saving':'')},[
    E('div',{'class':'dm-setting-line'},[
      E('div',{},[E('div',{'class':'dm-setting-title'},x[1]),E('div',{'class':'dm-setting-desc'},x[2])]),
      E('div',{'class':'dm-setting-actions'},[badge(busy?'dm-warn':(en?'dm-ok':'dm-off'),busy?'изменение':(en?'включено':'выключено')),btn(busy?'Сохраняю…':(en?'Выключить':'Включить'),busy?'cbi-button-neutral':(en?'cbi-button-remove':'cbi-button-add'),function(){setSetting(x[0],en?0:1,root);},{disabled:!!state.busy})])
    ])
  ]);
}
function testAgeCard(root,st,category,label){
  var key='test_age_'+category, busy=state.busySetting===key;
  var value=String(st[key]||6);
  var input=E('input',{'type':'number','min':'1','max':'168','step':'1','value':value,'class':'dm-input','style':'width:90px'});
  var save=btn(busy?'Сохраняю…':'Сохранить','cbi-button-neutral',function(){setTestAge(category,input.value,root);},{disabled:!!state.busy});
  return E('div',{'class':'dm-card dm-setting '+(busy?'dm-setting-saving':'')},[
    E('div',{'class':'dm-setting-line'},[
      E('div',{},[E('div',{'class':'dm-setting-title'},label),E('div',{'class':'dm-setting-desc'},'Результаты полной проверки считаются устаревшими после этого срока.')]),
      E('div',{'class':'dm-setting-actions'},[input,E('span',{'class':'dm-inline'},'ч'),save])
    ])
  ]);
}
function watchdogCard(root,st){
  var en=yes(st.watchdog), busy=state.busySetting==='watchdog';
  var service=Number(st.watchdog_service||0)===1, enabled=Number(st.watchdog_service_enabled||0)===1, loop=Number(st.watchdog_loop||0)===1;
  var detail=[
    row('Механизм',badge(st.watchdog_backend==='procd'?'dm-ok':'dm-warn',shortVal(st.watchdog_backend||'—'))),
    row('Служба',badge(service?'dm-ok':'dm-warn',service?'запущена':'не запущена')),
    row('Embedded loop',badge(loop?'dm-ok':service?'dm-warn':'dm-off',loop?'активен':service?'ожидает запуска':'не запущен')),
    row('Автозапуск',badge(enabled?'dm-ok':'dm-warn',enabled?'включён':'выключен')),
    row('Интервал',shortVal(st.watchdog_interval)+' с'),
    row('Порог сбоя',shortVal(st.watchdog_fail_threshold)+' цикла'),
    row('Cooldown замены',shortVal(st.watchdog_repair_cooldown)+' с'),
    row('Контроль конфигурации',shortVal(st.watchdog_guard_interval)+' с'),
    row('Замены за проход',shortVal(st.watchdog_max_repairs)),
    row('Кандидаты на замену',shortVal(st.watchdog_max_candidates)),
    row('Перезапуски HDP за операцию',shortVal(st.watchdog_max_restarts))
  ];
  var action=E('div',{'class':'dm-setting '+(busy?'dm-setting-saving':'')},[
    E('div',{'class':'dm-setting-line'},[
      E('div',{},[
        E('div',{'class':'dm-setting-title'},'Автопроверка DNS'),
        E('div',{'class':'dm-setting-desc'},'Фоновый watchdog DNS Manager работает через procd и встроенный цикл /usr/bin/dns-manager __watchdog-loop.')
      ]),
      E('div',{'class':'dm-setting-actions'},[
        badge(busy?'dm-warn':(en?'dm-ok':'dm-off'),busy?'изменение':(en?'включено':'выключено')),
        btn(busy?'Сохраняю…':(en?'Выключить':'Включить'),busy?'cbi-button-neutral':(en?'cbi-button-remove':'cbi-button-add'),function(){setSetting('watchdog',en?0:1,root);},{disabled:!!state.busy})
      ])
    ])
  ]);
  var body=[action,E('div',{'class':'dm-hint'},'После двух последовательных сбоев конкретного DNS выполняется точечная замена. При одновременном сбое всех DNS ротация не запускается; сначала проверяется восстановление сервиса. Ограничения по RAM и нагрузке применяются самим backend.'),E('div',{'class':'dm-grid2'},detail)];
  return E('div',{},body);
}
function renderSettings(root,st){
  var e=root.querySelector('#dm-settings');if(!e)return;e.innerHTML='';
  var body=[];
  if(state.settingMessage)body.push(E('div',{'class':'dm-inline-msg '+(state.settingMessageType||'info')},state.settingMessage));
  body.push(E('div',{'class':'dm-hint'},'Каждый пункт меняет одну настройку. Результат показывается здесь, без всплывающих сообщений.'));
  body.push(E('div',{'class':'dm-section-title'},'Фоновая проверка DNS'));
  body.push(watchdogCard(root,st));
  var groups=[
    ['Сеть',[['mtu','Исправление MTU и MSS для WAN','Исправляет размеры пакетов и TCP-сегментов для WAN-соединения.'],['sysctl','Оптимизация TCP и таблицы соединений','Настраивает TCP Fast Open, таймаут TCP и очередь соединений.'],['sysctl_ext','Расширенные параметры TCP и сетевых буферов','Настраивает таблицу соединений, keepalive и сетевые буферы.']]],
    ['Производительность',[['dnsmasq_perf','Увеличенный кэш DNS','Увеличивает кэш dnsmasq до 1000 записей и настраивает связанные параметры.']]],
    ['Устройства сети',[['ntp_clients','Время для устройств в локальной сети','Выдаёт устройствам локальной сети адрес роутера как сервер времени по DHCP.'],['client_fixes','DNS для проверки подключения и совместимости устройств','Настраивает DNS для системных проверок подключения и совместимости устройств.']]]
  ];
  groups.forEach(function(g){
    body.push(E('div',{'class':'dm-section-title'},g[0]));
    var grid=E('div',{'class':'dm-grid2'});
    g[1].forEach(function(x){grid.appendChild(settingCard(root,x,st));});
    body.push(grid);
  });
  body.push(E('div',{'class':'dm-section-title'},'Срок результатов проверки'));
  var ages=E('div',{'class':'dm-grid2'});
  [['bypass','Обход'],['clean','Чистый'],['security','Безопасность'],['privacy','Приватность'],['adblock','Блокировка рекламы'],['family','Семейный'],['regional','Региональный']].forEach(function(x){ages.appendChild(testAgeCard(root,st,x[0],x[1]));});
  body.push(ages);
  e.appendChild(card('Настройки',body));
}

function renderCatalog(root){
  var e=root.querySelector('#dm-catalog');if(!e)return;e.innerHTML='';
  var body=E('div',{'id':'dm-cat-body'});
  if(!window.dmCatalog)body.appendChild(E('div',{'class':'dm-hint'},'Загрузка каталога DNS…'));
  var ch=[E('div',{'class':'dm-mini'},'Каталог DNS отображается постоянно. Выбор категории и назначение доступны ниже.'),body];
  if(state.pageNotice.catalog)ch.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.catalog));e.appendChild(card('Каталог DNS',ch));
  if(window.dmCatalog)renderCatalogBody(root,window.dmCatalog);
}

function renderCatalogBody(root,data){
  var b=root.querySelector('#dm-cat-body');if(!b)return;b.innerHTML='';
  var f=E('div',{'class':'dm-seg'});
  CATEGORY.forEach(function(c){f.appendChild(btn(c[1],c[0]===state.category?'active cbi-button':'cbi-button',function(){state.category=c[0];state.offset=0;loadCatalog(root);}));});
  b.appendChild(f);
  b.appendChild(E('div',{'class':'dm-mini'},'Показано '+(data.servers||[]).length+' из '+(data.total||0)));
  var g=E('div',{'class':'dm-catalog'});
  (data.servers||[]).forEach(function(d){
    var ci=checkInfo(d.id,d);
    g.appendChild(E('div',{'class':'dm-card dm-catalog-item'},[
      E('h4',{},d.name||d.id),
      E('div',{'class':'dm-meta'},catName(d.category)),
      E('div',{'class':'dm-row'},[
        E('span',{'class':'dm-slot-ping'},ci.status==='RUNNING'?badge('dm-warn','проверяется'):ping(ci.ping)),
        E('span',{'class':'dm-slot-state'},ci.status==='RUNNING'?badge('dm-warn','проверяется'):stateBadge(ci.status,ci.ping)),
        E('span',{'class':'dm-inline'},[
          btn(ci.status==='RUNNING'?'Проверяется':'Проверить','cbi-button-neutral',function(){testOne(d.id,root,'profiles');},{disabled:ci.status==='RUNNING'})
        ])
      ]),
      E('div',{'class':'dm-actions'},[
        btn('Назначить','cbi-button-action',function(){openAssign(d.id,d.category,root);})
      ])
    ]));
  });
  b.appendChild(g);
  b.appendChild(E('div',{'class':'dm-page'},[
    btn('←','cbi-button-neutral',function(){if(state.offset>0){state.offset=Math.max(0,state.offset-state.limit);loadCatalog(root);}}),
    E('span',{'class':'dm-mini'},(Math.floor(state.offset/state.limit)+1)+' / '+Math.max(1,Math.ceil((data.total||0)/state.limit))),
    btn('→','cbi-button-neutral',function(){if(state.offset+state.limit<(data.total||0)){state.offset+=state.limit;loadCatalog(root);}})
  ]));
}

function renderLog(root){
  var e=root.querySelector('#dm-log');if(!e)return;e.innerHTML='';
  var ch=[];if(state.pageNotice.log)ch.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.log));
  if(state.logLoaded)ch.push(E('pre',{'class':'dm-log'},stripAnsi(state.logText||'')));
  else ch.push(E('div',{'class':'dm-hint'},'Журнал загружается автоматически при открытии этой вкладки.'));
  e.appendChild(card('Журнал',ch));
}

function testPanel(root){return root.querySelector('#dm-test-inline');}
function renderJobResult(root,j,st){return;}
function renderJob(root,job,meta){return;}
function renderJobIdle(root,st){
  var e=root.querySelector('#dm-job');if(!e)return;e.innerHTML='';
  var n=(window.dmState&&window.dmState.slots||[]).filter(function(d){return d&&d.id;}).length;
  var ch=[
    E('p',{'class':'dm-hint'},'Здесь проверяются только DNS, которые сейчас назначены в текущие слоты. Полный каталог из 111 DNS не запускается.'),
    E('div',{'class':'dm-actions'},[
      btn(state.jobRunning?'Проверка выполняется…':'Проверить текущие DNS','cbi-button-action',function(){testCurrent(root);},{disabled:!!state.busy||state.jobRunning})
    ]),
    E('div',{'class':'dm-mini'},'Текущих DNS: '+n)
  ];
  if(state.currentTest&&state.currentTest.status==='RUNNING')ch.push(E('div',{'class':'dm-inline-msg info'},'Проверено '+String(Math.max(0,(state.currentTest.index||1)-1))+' из '+String(state.currentTest.total||0)+'.'));
  if(state.currentTest&&state.currentTest.status==='DONE')ch.push(E('div',{'class':'dm-inline-msg ok'},'Проверка текущих DNS завершена.'));
  if(state.currentTest&&state.currentTest.status==='FAILED')ch.push(E('div',{'class':'dm-inline-msg error'},'Проверка текущих DNS завершилась с ошибкой.'));
  e.appendChild(card('Проверка текущих DNS',ch));
}
function render(root,st){
  renderHeader(root,st);
  renderOverview(root,st);
  renderDoH(root,st);
  renderSlots(root,st);
  renderProfiles(root,st);
  renderSettings(root,st);
  renderCatalog(root);
  renderLog(root);
  renderJobIdle(root,st);
  state.activeTab=currentRoute();
  setActiveTab(root,state.activeTab);
  if(!state.updateKick && Number(st.components_checked_at||0)===0){state.updateKick=true;setTimeout(function(){refresh(root,true);},2200);}
}
function refresh(root,keepPosition){
  if(!rootAlive(root))return Promise.resolve();
  return callStatus().then(function(st){
    if(!rootAlive(root))return;
    state.statusError='';
    window.dmState=st||{};
    render(root,st||{});
  }).catch(function(err){
    if(!rootAlive(root))return;
    state.statusError='Не удалось получить состояние DNS Manager через RPC (status).';
    window.dmState=window.dmState||{};
    render(root,window.dmState||{});
  });
}
function startAutoRefresh(root){
  if(state.autoRefreshRoot)clearInterval(state.autoRefreshRoot);
  state.autoRefreshRoot=setInterval(function(){
    if(!rootAlive(root)){clearInterval(state.autoRefreshRoot);state.autoRefreshRoot=null;return;}
    if(state.refreshBusy)return;
    if(state.busy||state.updatingAll||(state.versionCheck&&state.versionCheck.running))return;
    state.refreshBusy=true;
    refresh(root,true).then(function(){state.refreshBusy=false;},function(){state.refreshBusy=false;});
  },3000);
}
function toast(msg,type){}
function checkUpdate(root){
  if(state.versionCheck&&state.versionCheck.running)return;
  state.versionCheck={running:true,manager:'running',luci:'running',hdp:'running',catalog:'running',started:Date.now(),job:''};
  state.pageNotice.overview='Проверяю актуальность…';
  globalUpdateNotice('Проверяю актуальность…','info');
  renderOverview(root,window.dmState||{});
  callUpdateCheck().then(function(r){
    state.versionCheck.manager='done';
    state.versionCheck.luci='done';
    state.versionCheck.hdp='done';
    state.versionCheck.catalog='done';
    state.versionCheck.running=false;
    state.versionCheck.error=!(r&&r.ok);
    if(r&&r.ok){
      window.dmState=r;
      state.pageNotice.overview='';
      globalUpdateNotice('', '');
      renderOverview(root,r);
    }else{
      state.pageNotice.overview=(r&&r.error)||'Проверка актуальности не выполнена.';
      globalUpdateNotice(state.pageNotice.overview,'error');
      renderOverview(root,window.dmState||{});
    }
  }).catch(function(){
    state.versionCheck.manager='done';
    state.versionCheck.luci='done';
    state.versionCheck.hdp='done';
    state.versionCheck.catalog='done';
    state.versionCheck.running=false;
    state.versionCheck.error=true;
    state.pageNotice.overview='Проверка актуальности не выполнена.';
    globalUpdateNotice('Проверка актуальности не выполнена.','error');
    renderOverview(root,window.dmState||{});
  });
}

function updateManager(root){
  if(state.managerUpdating||state.busy)return;
  state.managerUpdating=true;
  renderOverview(root,window.dmState||{});
  callManagerUpdate().then(function(r){
    state.managerUpdating=false;
    if(r&&r.ok&&r.updated)state.pageNotice.overview='DNS Manager обновлён до '+r.version+'.';
    else state.pageNotice.overview=(r&&r.error)||'DNS Manager не удалось обновить.';
    refresh(root,true);
  }).catch(function(){
    state.managerUpdating=false;
    state.pageNotice.overview='Не удалось выполнить обновление DNS Manager.';
    refresh(root,true);
  });
}

function updateAll(root){
  if(state.updatingAll||state.busy)return;
  state.updatingAll=true;
  globalUpdateNotice('Обновляю доступные компоненты…','info');
  renderOverview(root,window.dmState||{});

  var results=[];
  var anyUpdate=false;
  var luciUpdated=false;

  function textOf(r){return r&&String(r.message||r.error||'')||'';}
  function isCurrent(r){var t=textOf(r);return /Новой версии|актуал|не новее|уже актуален/.test(t);}
  function add(name,r){
    if(r&&r.ok&&r.updated){
      anyUpdate=true;
      results.push(name+' обновлён');
      if(name==='LuCI')luciUpdated=true;
    }else if(isCurrent(r)){
      results.push(name+' уже актуален');
    }else{
      results.push(name+': '+(textOf(r)||'не удалось обновить'));
    }
  }

  return callManagerUpdate().then(function(r){
    add('DNS Manager',r);
    return callHdpUpdate();
  }).then(function(r){
    add('Защищённый DNS',r);
    return callUpdateCatalog();
  }).then(function(r){
    add('Каталог DNS',r);
    return callUpdate();
  }).then(function(r){
    add('LuCI',r);
    state.updatingAll=false;
    var msg=results.join('; ');
    globalUpdateNotice(msg,anyUpdate?'ok':'info');
    if(luciUpdated){
      setTimeout(function(){location.reload();},1200);
    }else{
      refresh(root,true);
    }
  }).catch(function(){
    state.updatingAll=false;
    globalUpdateNotice('Обновление не выполнено.','error');
    refresh(root,true);
  });
}
function updateHdp(root){
  if(state.hdpUpdating||state.busy)return;
  var v=(window.dmState&&window.dmState.hdp_latest_version)||'новой версии';
  state.hdpUpdating=true;
  renderOverview(root,window.dmState||{});
  callHdpUpdate().then(function(r){
    state.hdpUpdating=false;
    if(r&&r.ok&&r.updated)state.pageNotice.overview='https-dns-proxy обновлён до '+r.version+'.';
    else state.pageNotice.overview=(r&&r.error)||'https-dns-proxy не удалось обновить.';
    refresh(root,true);
  }).catch(function(){
    state.hdpUpdating=false;
    state.pageNotice.overview='Не удалось выполнить обновление https-dns-proxy.';
    refresh(root,true);
  });
}
function doUpdate(root){if(state.busy)return;var v=(window.dmState&&window.dmState.luci_latest_version)||'новой версии';state.busy=true;state.pageNotice.overview='Обновляю LuCI…';globalUpdateNotice('Обновляю LuCI до v'+v+'…','info');if(rootAlive(root))renderOverview(root,window.dmState||{});callUpdate().then(function(r){state.busy=false;if(r&&r.ok&&r.updated){var msg='LuCI обновлена до v'+r.version+'. Перезагружаю страницу…';state.pageNotice.overview=msg;globalUpdateNotice(msg,'ok');if(rootAlive(root))renderOverview(root,window.dmState||{});setTimeout(function(){location.reload();},1600);}else{var msg=(r&&r.error)||'LuCI не удалось обновить.';state.pageNotice.overview=msg;globalUpdateNotice(msg,'error');if(rootAlive(root))renderOverview(root,window.dmState||{});}}).catch(function(){state.busy=false;var msg='Не удалось выполнить RPC-обновление LuCI. Попробуйте ещё раз; причина будет показана в сообщении RPC.';state.pageNotice.overview=msg;globalUpdateNotice(msg,'error');if(rootAlive(root))renderOverview(root,window.dmState||{});});}
function applyProfile(name,root){
  if(state.busy)return;
  var current=profileName((window.dmState||{}).profile),next=profileName(name);
  if(current===next)return;
  confirmAction('Подтвердить изменение профиля',[['Сейчас',current],['Новый профиль',next]],function(){
    state.busy=true;state.pageNotice.profiles='Применяю профиль «'+next+'»…';renderProfiles(root,window.dmState||{});
    callProfile(name).then(function(r){
      state.busy=false;
      if(r&&r.ok){setAction(true,'Профиль: «'+next+'».');state.pageNotice.profiles='Профиль «'+next+'» применён.';}
      else{setAction(false,(r&&r.error)||'Профиль не удалось применить.');state.pageNotice.profiles=(r&&r.error)||'Профиль не удалось применить.';}
      refresh(root,true);
    }).catch(function(){state.busy=false;setAction(false,'Профиль не удалось применить.');state.pageNotice.profiles='Профиль не удалось применить.';refresh(root,true);});
  });
}
function setTestAge(category,hours,root){
  if(state.busy)return;
  var n=String(hours||'').trim();
  if(!/^\d+$/.test(n)||Number(n)<1||Number(n)>168){state.settingMessage='Срок должен быть от 1 до 168 часов.';state.settingMessageType='error';renderSettings(root,window.dmState||{});return;}
  state.busy=true;state.busySetting='testage_'+category;state.settingMessage='Сохраняю срок проверки…';state.settingMessageType='info';renderSettings(root,window.dmState||{});
  callTestAge(category,Number(n)).then(function(r){
    state.busy=false;state.busySetting='';state.settingMessage=(r&&r.ok)?'Срок проверки сохранён.':((r&&r.error)||'Срок проверки не удалось сохранить.');state.settingMessageType=(r&&r.ok)?'ok':'error';refresh(root,true);
  }).catch(function(){state.busy=false;state.busySetting='';state.settingMessage='Срок проверки не удалось сохранить.';state.settingMessageType='error';refresh(root,true);});
}
function setSetting(name,en,root){if(state.busy)return;state.busy=true;state.busySetting=name;state.settingMessage='Изменение «'+settingName(name)+'»…';state.settingMessageType='info';renderSettings(root,window.dmState||{});callSetting(name,en).then(function(r){state.busy=false;state.busySetting='';state.settingMessage=(r&&r.ok)?('Настройка «'+settingName(name)+'»: '+(en?'включена.':'выключена.')):((r&&r.error)||'Настройку не удалось изменить.');state.settingMessageType=(r&&r.ok)?'ok':'error';refresh(root,true);}).catch(function(){state.busy=false;state.busySetting='';state.settingMessage='Настройку не удалось изменить.';state.settingMessageType='error';refresh(root,true);});}
function setForceMode(mode,root){
  if(state.busy)return;
  if(window.dmState&&window.dmState.force_owner==='external'){
    state.pageNotice.doh='Внешний forced-DNS обнаружен. DNS Manager его не изменяет.';
    renderOverview(root,window.dmState);
    return;
  }
  var en=mode==='auto'?1:0;
  state.busy=true;
  state.busySetting='force';
  state.pageNotice.doh='Изменение перехвата DNS…';
  renderOverview(root,window.dmState||{});
  callSetting('force',en).then(function(r){
    state.busy=false;state.busySetting='';
    state.pageNotice.doh=(r&&r.ok)?(en?'Перехват DNS включён.':'Перехват DNS выключен.'):(r&&r.error)||'Не удалось изменить перехват DNS.';
    refresh(root,true);
  }).catch(function(){
    state.busy=false;state.busySetting='';
    state.pageNotice.doh='Не удалось изменить перехват DNS.';
    refresh(root,true);
  });
}
function testAll(root,origin){
  if(state.jobRunning||state.busy)return;
  state.jobRunning=true;
  state.fullTest={status:'RUNNING',origin:origin||state.activeTab||'overview',started:Date.now()};
  renderOverview(root,window.dmState||{});
  callTestAll().then(function(r){
    if(r&&r.ok)pollJob(root,r.job,{mode:'all'});
    else{state.fullTest={status:'FAILED'};state.jobRunning=false;refresh(root,true);}
  }).catch(function(){state.fullTest={status:'FAILED'};state.jobRunning=false;refresh(root,true);});
}
function testOne(id,root,origin,done){
  if(state.jobRunning||state.busy||!id)return;
  state.lastJob=null;state.jobRunning=true;
  state.checking[id]={status:'RUNNING',ping:'',started:Date.now()};
  render(root,window.dmState||{});
  callTestOne(id).then(function(r){
    if(r&&r.ok)pollJob(root,r.job,{mode:'one',dns_id:id},done);
    else{
      state.checking[id]={status:'FAIL',ping:''};state.jobRunning=false;render(root,window.dmState||{});
      if(done)done(window.dmState||{});
    }
  }).catch(function(){
    state.checking[id]={status:'FAIL',ping:''};state.jobRunning=false;render(root,window.dmState||{});
    if(done)done(window.dmState||{});
  });
}

function testCurrent(root){
  if(state.jobRunning||state.busy)return;
  var total=(window.dmState&&window.dmState.slots||[]).filter(function(d){return d&&d.id;}).length;
  if(!total){state.currentTest={status:'FAILED',total:0};state.checking={};render(root,window.dmState||{});return;}
  state.currentTest={status:'RUNNING',total:total,started:Date.now()};
  state.jobRunning=true;
  (window.dmState&&window.dmState.slots||[]).forEach(function(d){if(d&&d.id)state.checking[d.id]={status:'RUNNING',ping:'',started:Date.now()};});
  render(root,window.dmState||{});
  callTestCurrent().then(function(r){
    if(r&&r.ok)pollJob(root,r.job,{mode:'current'},null);
    else{state.currentTest={status:'FAILED',total:total};state.checking={};state.jobRunning=false;refresh(root,true);}
  }).catch(function(){state.currentTest={status:'FAILED',total:total};state.checking={};state.jobRunning=false;refresh(root,true);});
}
function pollJob(root,job,meta,done){
  var jobId=(typeof job==='string')?job:(job&&job.id)||'';var ticks=0;
  function finish(j){
    callStatus().then(function(ns){
      ns=ns||{};window.dmState=ns;
      if(meta&&meta.mode==='one'&&meta.dns_id){
        var d=null;(ns.slots||[]).forEach(function(x){if(x.id===meta.dns_id)d=x;});
        state.checking[meta.dns_id]={status:d&&d.status?d.status:(j.result==='ok'?'OK':'FAIL'),ping:d&&d.ping?d.ping:''};
      }
      if(meta&&meta.mode==='current')state.checking={};
      if(done)done(ns);
      else{state.jobRunning=false;if(meta&&meta.mode==='all')state.fullTest={status:String(j.status||'').toUpperCase()==='DONE'?'DONE':'FAILED',result:j.result||'fail',finished:Date.now()};if(meta&&meta.mode==='current')state.currentTest={status:String(j.status||'').toUpperCase()==='DONE'?'DONE':'FAILED',result:j.result||'fail',finished:Date.now()};render(root,ns);}
    }).catch(function(){
      if(meta&&meta.mode==='one'&&meta.dns_id)state.checking[meta.dns_id]={status:j.result==='ok'?'OK':'FAIL',ping:''};
      if(meta&&meta.mode==='current')state.checking={};
      if(done)done(window.dmState||{});
      else{state.jobRunning=false;if(meta&&meta.mode==='all')state.fullTest={status:'FAILED',result:'fail'};if(meta&&meta.mode==='current')state.currentTest={status:'FAILED',result:'fail'};render(root,window.dmState||{});}
    });
  }
  function poll(){
    callJob(jobId).then(function(j){j=j||{};var s=String(j.status||'running').toUpperCase();if(s==='DONE'||s==='FAILED'){finish(j);return;}if(ticks++>180){finish({status:'FAILED',result:'fail'});return;}setTimeout(poll,700);}).catch(function(){if(ticks++>8){finish({status:'FAILED',result:'fail'});return;}setTimeout(poll,1000);});
  }
  poll();
}

function loadCatalog(root){
  if(state.catalogLoading)return Promise.resolve();
  state.catalogLoading=true;
  return callCatalog(state.category,state.offset,state.limit,0).then(function(d){
    state.catalogLoading=false;state.catalogLoaded=true;window.dmCatalog=d||{};renderCatalog(root);renderCatalogBody(root,window.dmCatalog);
  }).catch(function(){
    state.catalogLoading=false;state.pageNotice.catalog='Не удалось загрузить каталог DNS.';renderCatalog(root);
  });
}
function showLog(root){
  if(state.logLoading)return Promise.resolve();
  state.logLoading=true;
  return callLog(160).then(function(r){state.logLoading=false;state.logLoaded=true;state.logText=stripAnsi(r.log||'');renderLog(root);}).catch(function(){state.logLoading=false;state.pageNotice.log='Не удалось загрузить журнал.';renderLog(root);});
}

return view.extend({
  load:function(){return callStatus().then(function(st){return st||{};});},
  render:function(st){var root=E('div',{'class':'dm-wrap'});['dm-header','dm-overview','dm-doh','dm-slots','dm-profiles','dm-settings','dm-job','dm-catalog','dm-log'].forEach(function(id){root.appendChild(E('section',{'id':id}));});injectStyle(root);window.dmState=st||{};state.activeTab=currentRoute();render(root,st||{});startAutoRefresh(root);return root;}
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

    {
        printf 'installed=1\nversion=%s\ninstalled_at=%s\nsource=%s\n' "$VERSION" "$(date +%s 2>/dev/null || printf 0)" "$COMPANION_URL"
    } > "${BACKUP_DIR}/version" 2>/dev/null || true
    chmod 600 "${BACKUP_DIR}/version" 2>/dev/null || true
    {
        printf 'installed=1\nversion=%s\ninstalled_at=%s\nsource=%s\n' "$VERSION" "$(date +%s 2>/dev/null || printf 0)" "$COMPANION_URL"
    } > "${STATE_FILE}.tmp.$$" 2>/dev/null || true
    [ -s "${STATE_FILE}.tmp.$$" ] && chmod 600 "${STATE_FILE}.tmp.$$" 2>/dev/null || true
    [ -s "${STATE_FILE}.tmp.$$" ] && mv "${STATE_FILE}.tmp.$$" "$STATE_FILE" 2>/dev/null || rm -f "${STATE_FILE}.tmp.$$" 2>/dev/null || true
    if [ "${DNS_MANAGER_LUCI_SKIP_RPC_RELOAD:-0}" != 1 ]; then
        [ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload >/dev/null 2>&1 || true
    fi
    say "DNS Manager LuCI $VERSION обновлён/установлен."
    say "Меню: LuCI → Службы → DNS Manager"
}

uninstall_files() {
    rm -f "$RPC_PLUGIN" "$ACL_FILE" "$MENU_FILE" "$VIEW_FILE" 2>/dev/null || true
    rm -rf "$VIEW_DIR" "$RUNTIME_DIR" "$BACKUP_DIR" 2>/dev/null || true
    rm -f "$STATE_FILE" 2>/dev/null || true
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
