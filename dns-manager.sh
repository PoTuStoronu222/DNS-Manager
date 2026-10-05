#!/bin/sh
MANAGER_PATH="/usr/bin/dns-manager"
VERSION="3.35.12"
BASE_DIR="/etc/dns-manager"
CFG_DIR="$BASE_DIR/config"
STATE_DIR="/var/run/dns-manager"
LOG_FILE="/var/log/dns-manager.log"
TX_LOG="/var/log/dns-manager.tx"
CONFIG_FILE="$CFG_DIR/manager.conf"
DNS_CATALOG="$CFG_DIR/dns-catalog.conf"
NTP_CATALOG="$CFG_DIR/ntp-catalog.conf"
BOOTSTRAP_CATALOG="$CFG_DIR/bootstrap-catalog.conf"
BOGUS_CATALOG="$CFG_DIR/bogus-catalog.conf"
BOOTSTRAP_DNS_ALL="77.88.8.8,77.88.8.1,94.140.14.14,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112,208.67.222.222,208.67.220.220,149.112.121.10,149.112.122.10,76.76.2.0,76.76.10.0,194.242.2.2,194.242.2.3,2606:4700:4700::1111,2606:4700:4700::1001,2001:4860:4860::8888,2001:4860:4860::8844,2620:fe::fe,2620:fe::9"
DNSCAT_VERSION="8.6-RU-NOSOCIAL"
DNSCAT_REVISION="2"
DNSCAT_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/catalogs/dns-8.5-RU-NOSOCIAL.conf"
WATCHDOG_SPEC_VERSION="22"
WATCHDOG_RESTART_COOLDOWN=300
WATCHDOG_BACKEND="procd"
WATCHDOG_CHECK_INTERVAL_DEFAULT=90
WATCHDOG_FAIL_THRESHOLD=2
WATCHDOG_REPAIR_COOLDOWN=300
WATCHDOG_GUARD_INTERVAL=900
DNSMASQ_CACHE_SIZE=4096
WATCHDOG_SERVICE_PATH="/etc/init.d/dns-watchdog"
WATCHDOG_SERVICE_MARKER="# DNS_MANAGER_WATCHDOG_SERVICE=2"
WATCHDOG_SERVICE_VERSION_MARKER="# DNS_MANAGER_WATCHDOG_SERVICE_VERSION=3.11.6"
WATCHDOG_LEGACY_DAEMON_PATH="/usr/bin/dns-watchdog-daemon.sh"
WATCHDOG_LEGACY_DAEMON_MARKER="# DNS_MANAGER_WATCHDOG_DAEMON=1"
WATCHDOG_LEGACY_RUNTIME_DIR="/var/run/dns-watchdog"
WATCHDOG_LAST_RESTART_TS=0
AUTO_UPDATE_LAST_CHECK_FILE="$STATE_DIR/auto-update-last-check"
AUTO_UPDATE_CHECK_MAX_AGE=43200
AUTO_UPDATE_LOCK_DIR="$STATE_DIR/auto-update.lock"
TEST_RESULTS_META="$STATE_DIR/dns-test-results.meta"
TEST_RESULTS_MAX_AGE=21600
# Freshness window for DNS test results, by catalog category.
# Values are stored in seconds and exposed in LuCI as hours.
TEST_RESULTS_MAX_AGE_BYPASS=21600
TEST_RESULTS_MAX_AGE_CLEAN=21600
TEST_RESULTS_MAX_AGE_SECURITY=21600
TEST_RESULTS_MAX_AGE_PRIVACY=21600
TEST_RESULTS_MAX_AGE_ADBLOCK=21600
TEST_RESULTS_MAX_AGE_FAMILY=21600
TEST_RESULTS_MAX_AGE_REGIONAL=21600
TEST_DEPENDENCY_WARNING_FILE="$STATE_DIR/dns-test-dependency-warning"
TEST_DEPENDENCY_WARNING_MAX_AGE=3600
TEST_PROGRESS_EVERY=20
# Resource-safety defaults for small OpenWrt routers.
TEST_BATCH_DEFAULT=4
WATCHDOG_MAX_REPAIRS=1
WATCHDOG_MAX_RESTARTS=2
WATCHDOG_MAX_CANDIDATES=3
LOG_MAX_BYTES=65536
TX_LOG_MAX_BYTES=65536
OWNERSHIP_MAX_BYTES=32768
TX_KEEP_MINUTES=15
BASELINE_DIR="$BASE_DIR/baseline"
BASELINE_MANIFEST="$BASELINE_DIR/manifest"
BASELINE_LAST="$BASELINE_DIR/last-applied.manifest"
BASELINE_META="$BASELINE_DIR/meta"
OWNERSHIP="$CFG_DIR/ownership.conf"
PACKAGE_OWNERSHIP="$CFG_DIR/package-ownership.conf"
TEST_RESULTS="$STATE_DIR/dns-test-results.conf"
TEST_LOCK_DIR="$STATE_DIR/dns-test.lock"
TEST_LOCK_HELD=0
WEB_ACCESS_PORT="7682"
WEB_ACCESS_ENABLED=0
TTYD_CONFIG="/etc/config/ttyd"
WEB_SERVICE_CONFIG="/etc/init.d/ttyd"
FIREWALL_OWNERSHIP="$CFG_DIR/firewall-ownership.conf"
FW_NTP_SECTION="dns_manager_ntp_client"
FW_DNS_REDIRECT_SECTION="dns_manager_dns_redirect"
FW_DOT_SECTION="dns_manager_dot_block"
STEER_DNS_ACTIVE=0
STEER_DNS_SOURCE="none"
FIREWALL_LAN_ZONE=""
FIREWALL_WAN_ZONE=""
FIREWALL_LAN_NAME=""
FIREWALL_WAN_NAME=""
FIREWALL_WAN_NETWORK=""
WATCHDOG_CRON_STATE="$STATE_DIR/watchdog-cron.state"
WATCHDOG_CRON_MARKER="# DNS_MANAGER_MANAGED_WATCHDOG=1"
WATCHDOG_CRON_FILE=""
WATCHDOG_CRON_DIR=""
WATCHDOG_CRON_INIT=""
WATCHDOG_CRON_DAEMON=""
WATCHDOG_CRON_PID=""
WATCHDOG_CRON_AVAILABLE="no"
WATCHDOG_CRON_RUNNING="no"
WATCHDOG_CRON_AMBIGUOUS="no"
WATCHDOG_CRON_PID_COUNT=0
WATCHDOG_CRON_BOOT_ENABLED="unknown"
WATCHDOG_CRON_DETECT_SOURCE="none"
WATCHDOG_CRON_SCHEDULER_STATE="$STATE_DIR/watchdog-scheduler.state"
LUCI_CONTROLLER="/usr/lib/lua/luci/controller/dns_manager.lua"
LUCI_COMPANION_URL="https://api.github.com/repos/PoTuStoronu222/DNS-Manager/contents/dns-manager-luci.sh?ref=main"
LUCI_COMPANION_CACHE="$BASE_DIR/dns-manager-luci.sh"
LUCI_STATE_FILE="$CFG_DIR/luci-state.conf"
LUCI_MENU_FILE="/usr/share/luci/menu.d/luci-app-dns-manager.json"
LUCI_ACL_FILE="/usr/share/rpcd/acl.d/luci-app-dns-manager.json"
LUCI_RPC_PLUGIN="/usr/libexec/rpcd/dns_manager"
LUCI_BACKEND_FILE="/usr/lib/dns-manager-luci/backend.sh"
LUCI_VIEW_FILE="/www/luci-static/resources/view/dns_manager/overview.js"
LUCI_REMOTE_VERSION=""
LUCI_UPDATE_AVAILABLE=0
# Persistent marker: /var/run is tmpfs, so the first-run decision must survive reboot.
FIRST_RUN_MARKER="$CFG_DIR/.first-run.done"
FIRST_RUN=0
[ -f "$FIRST_RUN_MARKER" ] || FIRST_RUN=1
FIRST_RUN_INITIAL="$FIRST_RUN"
MUTATION_LOCK_DIR="$STATE_DIR/mutation.lock"
MUTATION_LOCK_HELD=0
rotate_small_file() {
    _rf="$1"
    _max="$2"
    [ -n "$_rf" ] && [ -f "$_rf" ] || return 0
    _sz="$(wc -c < "$_rf" 2>/dev/null | tr -d ' ')"
    case "$_sz" in ''|*[!0-9]*) return 0;; esac
    [ "$_sz" -gt "$_max" ] || return 0
    _tmp="${_rf}.tmp.$$"
    tail -n 1200 "$_rf" > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 0; }
    mv "$_tmp" "$_rf" 2>/dev/null || { rm -f "$_tmp"; }
}
rotate_runtime_logs() {
    rotate_small_file "$LOG_FILE" "$LOG_MAX_BYTES"
    rotate_small_file "$TX_LOG" "$TX_LOG_MAX_BYTES"
    if [ -f "$OWNERSHIP" ]; then
        _sz="$(wc -c < "$OWNERSHIP" 2>/dev/null | tr -d ' ')"
        case "$_sz" in ''|*[!0-9]*) ;; *)
            if [ "$_sz" -gt "$OWNERSHIP_MAX_BYTES" ]; then
                _tmp="${OWNERSHIP}.tmp.$$"
                tail -n 1800 "$OWNERSHIP" > "$_tmp" 2>/dev/null && mv "$_tmp" "$OWNERSHIP" 2>/dev/null || rm -f "$_tmp"
            fi
            ;;
        esac
    fi
}
cleanup_transaction_history() {
    [ -d "$STATE_DIR" ] || return 0
    for _txd in "$STATE_DIR"/tx-*; do
        [ -d "$_txd" ] || continue
        [ "$_txd" = "${TX_DIR:-}" ] && continue
        find "$_txd" -maxdepth 0 -mmin +"$TX_KEEP_MINUTES" -exec rm -rf {} \; 2>/dev/null || true
    done
}

acquire_mutation_lock() {
    mkdir -p "$STATE_DIR" 2>/dev/null || return 1
    if mkdir "$MUTATION_LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$MUTATION_LOCK_DIR/pid" 2>/dev/null || true
        MUTATION_LOCK_HELD=1
        return 0
    fi
    _mpid="$(cat "$MUTATION_LOCK_DIR/pid" 2>/dev/null)"
    if [ -z "$_mpid" ]; then
        for _try in 1 2 3 4 5; do
            sleep 1
            _mpid="$(cat "$MUTATION_LOCK_DIR/pid" 2>/dev/null)"
            [ -n "$_mpid" ] && break
        done
    fi
    if [ -n "$_mpid" ] && kill -0 "$_mpid" 2>/dev/null; then
        log_msg "Операция пропущена: другой процесс DNS Manager уже изменяет конфигурацию (PID $_mpid)."
        return 1
    fi
    rm -rf "$MUTATION_LOCK_DIR" 2>/dev/null || true
    mkdir "$MUTATION_LOCK_DIR" 2>/dev/null || return 1
    printf '%s\n' "$$" > "$MUTATION_LOCK_DIR/pid" 2>/dev/null || true
    MUTATION_LOCK_HELD=1
    return 0
}
release_mutation_lock() {
    [ "${MUTATION_LOCK_HELD:-0}" = 1 ] || return 0
    rm -rf "$MUTATION_LOCK_DIR" 2>/dev/null || true
    MUTATION_LOCK_HELD=0
}

cleanup_stale_tmp_dirs() {
    _self_tmp="${TMP_DIR:-}"

    find /tmp -maxdepth 1 -type d -name 'dnsmgr.*' -print 2>/dev/null | while IFS= read -r _old_dir; do
        [ -n "$_old_dir" ] || continue
        [ "$_old_dir" = "$_self_tmp" ] && continue

        case "$_old_dir" in
            /tmp/dnsmgr.[A-Za-z0-9._-]*) ;;
            *) continue ;;
        esac

        _base="${_old_dir##*/}"
        _pid="${_base#dnsmgr.}"
        _pid="${_pid%%-*}"

        if printf '%s' "$_pid" | grep -Eq '^[0-9]+$'; then
            if kill -0 "$_pid" 2>/dev/null; then
                _cmd=""

                if [ -r "/proc/$_pid/cmdline" ]; then
                    _cmd="$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null)"
                fi

                if [ -n "$_cmd" ]; then
                    case "$_cmd" in
                        *dns-manager*) continue ;;
                    esac
                fi

                # PID жив: каталог не трогаем. Это безопаснее при переиспользовании PID.
                continue
            fi

            rm -rf "$_old_dir" 2>/dev/null || true
        else
            find "$_old_dir" -maxdepth 0 -mmin +30 -exec rm -rf {} \; 2>/dev/null || true
        fi
    done
}
TMP_DIR="$(mktemp -d "/tmp/dnsmgr.$$-XXXXXX" 2>/dev/null || { d="/tmp/dnsmgr.$$"; n=0; while ! mkdir "$d" 2>/dev/null; do n=$((n+1)); d="/tmp/dnsmgr.$$-$n"; [ "$n" -lt 20 ] || break; done; [ -d "$d" ] || exit 1; printf "%s" "$d"; })"
cleanup_stale_tmp_dirs
cleanup_transaction_history
rotate_runtime_logs
TX_ID="$(date +%Y%m%d-%H%M%S)-$$"
TX_DIR="$STATE_DIR/tx-$TX_ID"
TX_ACTIVE=0
DEFER_CONFIG_SAVE=0
TX_RESERVED_PORTS=""
TX_PRE_SLOTS=""
CORE_ONLY=0
CRON_TMP_FILE=""
UPDATE_TMP_FILE=""
acquire_test_lock() {
    mkdir -p "$STATE_DIR" 2>/dev/null || return 1
    if mkdir "$TEST_LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$TEST_LOCK_DIR/pid" 2>/dev/null || true
        TEST_LOCK_HELD=1
        return 0
    fi
    _tpid="$(cat "$TEST_LOCK_DIR/pid" 2>/dev/null)"
    if [ -z "$_tpid" ]; then
        for _try in 1 2 3 4 5; do
            sleep 1
            _tpid="$(cat "$TEST_LOCK_DIR/pid" 2>/dev/null)"
            [ -n "$_tpid" ] && break
        done
    fi
    if [ -n "$_tpid" ] && kill -0 "$_tpid" 2>/dev/null; then
        return 1
    fi
    rm -rf "$TEST_LOCK_DIR" 2>/dev/null || true
    mkdir "$TEST_LOCK_DIR" 2>/dev/null || return 1
    printf '%s\n' "$$" > "$TEST_LOCK_DIR/pid" 2>/dev/null || true
    TEST_LOCK_HELD=1
    return 0
}
release_test_lock() {
    [ "${TEST_LOCK_HELD:-0}" = 1 ] || return 0
    rm -rf "$TEST_LOCK_DIR" 2>/dev/null || true
    TEST_LOCK_HELD=0
}
aligned_label_width() {
    _label="$1"
    _bytes="$(printf '%s' "$_label" | wc -c 2>/dev/null | tr -d ' ')"
    _multibyte="$(printf '%s' "$_label" | LC_ALL=C od -An -t x1 2>/dev/null | awk 'BEGIN{n=0} {for(i=1;i<=NF;i++) if ($i ~ /^(c[2-9a-f]|d[0-9a-f]|e[0-9a-f]|f[0-4])$/) n++} END{print n+0}')"
    case "$_bytes" in ''|*[!0-9]*) _bytes=0;; esac
    case "$_multibyte" in ''|*[!0-9]*) _multibyte=0;; esac
    _width=$((42+_multibyte))
    printf '%s' "$_width"
}
printf_state_row() {
    _label="$1"
    _value="$2"
    _width="$(aligned_label_width "$_label")"
    printf "  ${C_YELLOW}${C_BOLD}%-${_width}s${C_NC}  %b\n" "$_label" "$_value"
}
printf_plain_row() {
    _label="$1"
    _value="$2"
    _width="$(aligned_label_width "$_label")"
    printf "  %-${_width}s  %b\n" "$_label" "$_value"
}
cleanup_runtime() {
    if [ -n "${STAGE_PIDS:-}" ]; then
        for _pid in ${STAGE_PIDS:-}; do
            [ -n "$_pid" ] || continue
            kill "$_pid" 2>/dev/null || true
        done

        sleep 1 2>/dev/null || true

        for _pid in ${STAGE_PIDS:-}; do
            [ -n "$_pid" ] || continue
            kill -9 "$_pid" 2>/dev/null || true
        done
    fi

    # Добить все дочерние процессы текущего скрипта,
    # чтобы не оставались висеть curl / test_one_dns / фоновые проверки.
    _children="$(pgrep -P $$ 2>/dev/null || true)"
    if [ -n "$_children" ]; then
        for _pid in $_children; do
            [ "$_pid" = "$$" ] && continue
            kill "$_pid" 2>/dev/null || true
        done

        sleep 1 2>/dev/null || true

        for _pid in $_children; do
            [ "$_pid" = "$$" ] && continue
            kill -9 "$_pid" 2>/dev/null || true
        done
    fi

    [ -n "${CRON_TMP_FILE:-}" ] && rm -f "$CRON_TMP_FILE" 2>/dev/null || true
    [ -n "${UPDATE_TMP_FILE:-}" ] && rm -f "$UPDATE_TMP_FILE" 2>/dev/null || true

    release_mutation_lock 2>/dev/null || true
    release_test_lock 2>/dev/null || true

    [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR" 2>/dev/null || true
}
trap cleanup_runtime EXIT
trap 'exit 130' INT TERM
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'
C_CYAN='\033[1;36m'
C_YELLOW='\033[1;33m'
C_MAGENTA='\033[1;35m'
C_BLUE='\033[0;34m'
C_NC='\033[0m'
C_BOLD='\033[1m'
C_WHITE='\033[1;37m'
C_PINK='\033[1;35m'
C_DGRAY='\033[1;37m'
C_TITLE='\033[0;34m'
C_SECTION='\033[1;33m'
# ==========================================
# ==========================================
UPDATE_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager.sh"
_ver_newer() {
    awk -v a="$1" -v b="$2" 'BEGIN{
        na=split(a,x,"\\."); nb=split(b,y,"\\."); n=(na>nb?na:nb);
        for(i=1;i<=n;i++){
            va=(x[i]==""?0:x[i]+0); vb=(y[i]==""?0:y[i]+0);
            if(va>vb) exit 0; if(va<vb) exit 1;
        }
        exit 1;
    }'
}
acquire_auto_update_lock() {
    mkdir -p "$STATE_DIR" 2>/dev/null || return 1
    if mkdir "$AUTO_UPDATE_LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$AUTO_UPDATE_LOCK_DIR/pid" 2>/dev/null || true
        return 0
    fi
    _au_pid="$(cat "$AUTO_UPDATE_LOCK_DIR/pid" 2>/dev/null)"
    if [ -n "$_au_pid" ] && kill -0 "$_au_pid" 2>/dev/null; then
        return 1
    fi
    rm -rf "$AUTO_UPDATE_LOCK_DIR" 2>/dev/null || true
    mkdir "$AUTO_UPDATE_LOCK_DIR" 2>/dev/null || return 1
    printf '%s\n' "$$" > "$AUTO_UPDATE_LOCK_DIR/pid" 2>/dev/null || true
    return 0
}
release_auto_update_lock() {
    rm -rf "$AUTO_UPDATE_LOCK_DIR" 2>/dev/null || true
}
auto_update_manager() {
    AUTO_UPDATE_RESULT="disabled"
    if [ "${DNS_MANAGER_NO_UPDATE:-0}" = "1" ] && [ "${DNS_MANAGER_FORCE_UPDATE:-0}" != 1 ]; then
        return 0
    fi
    AUTO_UPDATE_RESULT="started"

    [ -n "${AUTO_UPDATE_LOCK_DIR:-}" ] || AUTO_UPDATE_LOCK_DIR="$STATE_DIR/auto-update.lock"
    if ! acquire_auto_update_lock; then
        AUTO_UPDATE_RESULT="busy"
        return 0
    fi

    _scheduled=0
    [ "${DNS_MANAGER_SCHEDULED_UPDATE:-0}" = "1" ] && _scheduled=1

    # Interactive startup and explicit update-check must perform a real GitHub
    # check. The 12-hour throttle is reserved for scheduled/background updates.
    if [ "$_scheduled" = 1 ] && [ "${DNS_MANAGER_FORCE_UPDATE:-0}" != 1 ]; then
        _upd_now="$(date +%s 2>/dev/null)"
        _upd_last="$(cat "$AUTO_UPDATE_LAST_CHECK_FILE" 2>/dev/null)"
        case "$_upd_now" in ''|*[!0-9]*) _upd_now="";; esac
        case "$_upd_last" in ''|*[!0-9]*) _upd_last="";; esac
        if [ -n "$_upd_now" ] && [ -n "$_upd_last" ]; then
            _upd_age=$((_upd_now-_upd_last))
            if [ "$_upd_age" -ge 0 ] 2>/dev/null && [ "$_upd_age" -lt "$AUTO_UPDATE_CHECK_MAX_AGE" ] 2>/dev/null; then
                AUTO_UPDATE_RESULT="throttled"
                release_auto_update_lock
                return 0
            fi
        fi
    fi

    case "$0" in
        "$MANAGER_PATH"|*/dns-manager|dns-manager) ;;
        *)
            AUTO_UPDATE_RESULT="skipped"
            log_msg "Автообновление: запуск не из $MANAGER_PATH (0=$0), проверка пропущена."
            release_auto_update_lock
            return 0
            ;;
    esac

    [ -f "$MANAGER_PATH" ] || {
        log_msg "Автообновление: файл $MANAGER_PATH не найден."
        AUTO_UPDATE_RESULT="skipped"
        release_auto_update_lock
        return 0
    }

    [ -w "${MANAGER_PATH%/*}" ] || {
        log_msg "Автообновление: каталог ${MANAGER_PATH%/*} недоступен для записи."
        AUTO_UPDATE_RESULT="skipped"
        release_auto_update_lock
        return 0
    }

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v uclient-fetch >/dev/null 2>&1; then
        AUTO_UPDATE_RESULT="skipped"
        log_msg "Автообновление: нет curl, wget или uclient-fetch, проверка пропущена."
        release_auto_update_lock
        return 0
    fi

    _upd_tmp="/tmp/dns-manager-update-$$"
    UPDATE_TMP_FILE="$_upd_tmp"
    rm -f "$_upd_tmp" 2>/dev/null

    _update_url="${UPDATE_URL}?_dmcb=$(date +%s 2>/dev/null || printf 0)-$$"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 4 --max-time 20 -o "$_upd_tmp" "$_update_url" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 20 -O "$_upd_tmp" "$_update_url" >/dev/null 2>&1
    else
        uclient-fetch -q -O "$_upd_tmp" "$_update_url" >/dev/null 2>&1
    fi

    if [ ! -s "$_upd_tmp" ]; then
        log_msg "Автообновление: файл не получен. Нет связи, блокировка, нет curl/wget или сервер недоступен. Продолжаю работу без обновления."
        AUTO_UPDATE_RESULT="failed"
        rm -f "$_upd_tmp" 2>/dev/null
        UPDATE_TMP_FILE=""
        release_auto_update_lock
        return 0
    fi

    head -n 1 "$_upd_tmp" 2>/dev/null | grep -q '^#!/bin/sh' || {
        log_msg "Автообновление: загруженный файл не является sh-скриптом."
        AUTO_UPDATE_RESULT="failed"
        rm -f "$_upd_tmp" 2>/dev/null
        UPDATE_TMP_FILE=""
        release_auto_update_lock
        return 0
    }

    _new_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$_upd_tmp" 2>/dev/null | head -n1)"
    [ -n "$_new_version" ] || {
        AUTO_UPDATE_RESULT="failed"
        log_msg "Автообновление: в загруженном файле не найдена строка VERSION."
        rm -f "$_upd_tmp" 2>/dev/null
        UPDATE_TMP_FILE=""
        release_auto_update_lock
        return 0
    }

    if ! sh -n "$_upd_tmp" 2>/dev/null; then
        log_msg "Автообновление: синтаксическая проверка загруженного файла не пройдена."
        AUTO_UPDATE_RESULT="failed"
        rm -f "$_upd_tmp" 2>/dev/null
        UPDATE_TMP_FILE=""
        release_auto_update_lock
        return 0
    fi

    # A network fetch + shell/version validation completed successfully; only now
    # advance the throttle timestamp. Failed/blocked checks must be retryable.
    [ -n "$_upd_now" ] && printf '%s\n' "$_upd_now" > "$AUTO_UPDATE_LAST_CHECK_FILE" 2>/dev/null || true

    _new_hash="$(file_hash "$_upd_tmp")"
    _old_hash="$(file_hash "$MANAGER_PATH")"

    if [ "$_new_version" = "$VERSION" ]; then
        if [ -z "$_new_hash" ] || [ -z "$_old_hash" ] || [ "$_new_hash" = "$_old_hash" ]; then
            AUTO_UPDATE_RESULT="current"
            rm -f "$_upd_tmp" 2>/dev/null
            UPDATE_TMP_FILE=""
            release_auto_update_lock
            return 0
        fi
    else
        if ! _ver_newer "$_new_version" "$VERSION"; then
            AUTO_UPDATE_RESULT="current"
            rm -f "$_upd_tmp" 2>/dev/null
            UPDATE_TMP_FILE=""
            release_auto_update_lock
            return 0
        fi
    fi

    log_msg "Автообновление: найдено обновление $VERSION → $_new_version. Устанавливаю."

    if cp -f "$_upd_tmp" "$MANAGER_PATH" 2>/dev/null && chmod 755 "$MANAGER_PATH" 2>/dev/null; then
        sync 2>/dev/null || true
        rm -f "$_upd_tmp" 2>/dev/null
        UPDATE_TMP_FILE=""
        AUTO_UPDATE_RESULT="updated"
        log_msg "Автообновление: файл заменён на версию $_new_version."

        if [ "${DNS_MANAGER_UPDATE_NO_EXEC:-0}" = 1 ]; then
            release_auto_update_lock
            return 0
        fi

        [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR" 2>/dev/null || true
        TMP_DIR=""
        release_auto_update_lock
        if [ "${DNS_MANAGER_UPDATE_REEXEC_COMMAND:-}" = "watchdog" ]; then
            DNS_MANAGER_NO_UPDATE=1 exec "$MANAGER_PATH" watchdog
        else
            DNS_MANAGER_NO_UPDATE=1 exec "$MANAGER_PATH"
        fi
    fi

    AUTO_UPDATE_RESULT="failed"
    log_msg "Автообновление: не удалось заменить $MANAGER_PATH."
    rm -f "$_upd_tmp" 2>/dev/null
    UPDATE_TMP_FILE=""
    release_auto_update_lock
    return 0
}
# ==========================================
# ==========================================
log_msg() {
    if [ "${DNS_MANAGER_RAM_LOG:-0}" = 1 ] || [ "${DNS_TEST_RAM_ONLY:-0}" = 1 ]; then
        if command -v logger >/dev/null 2>&1; then
            logger -t dns-manager "$*"
        fi
        return 0
    fi
    mkdir -p "$BASE_DIR" "$STATE_DIR" 2>/dev/null
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null
    LOG_MSG_COUNT=$(( ${LOG_MSG_COUNT:-0} + 1 ))
    if [ $((LOG_MSG_COUNT % 32)) -eq 0 ]; then rotate_runtime_logs; fi
}
log_tx() {
    if [ "${DNS_MANAGER_RAM_LOG:-0}" = 1 ] || [ "${DNS_TEST_RAM_ONLY:-0}" = 1 ]; then
        if command -v logger >/dev/null 2>&1; then
            logger -t dns-manager "TX|$TX_ID|$(date +%s)|$1|$2|$3|$4|$5"
        fi
        return 0
    fi
    printf 'TX|%s|%s|%s|%s|%s|%s\n' "$TX_ID" "$(date +%s)" "$1" "$2" "$3" "$4" "$5" >> "$TX_LOG" 2>/dev/null
    LOG_TX_COUNT=$(( ${LOG_TX_COUNT:-0} + 1 ))
    if [ $((LOG_TX_COUNT % 32)) -eq 0 ]; then rotate_runtime_logs; fi
}
ok_msg() { log_msg "Готово: $*"; printf "${C_GREEN}[✓] %s${C_NC}\n" "$*"; }
info_msg() { log_msg "Информация: $*"; printf "${C_CYAN}[ℹ] %s${C_NC}\n" "$*"; }
warn_msg() { log_msg "Внимание: $*"; printf "${C_YELLOW}[!] %s${C_NC}\n" "$*"; }
err_msg() { log_msg "Ошибка: $*"; printf "${C_RED}[✗] %s${C_NC}\n" "$*"; }
apply_progress() {
    log_msg "$*"
    [ "${APPLY_OUTPUT_QUIET:-0}" = 1 ] || printf "  ${C_CYAN}↻${C_NC} %s\n" "$*"
}
apply_progress_ok() {
    log_msg "$*"
    [ "${APPLY_OUTPUT_QUIET:-0}" = 1 ] || printf "  ${C_GREEN}✓${C_NC} %s\n" "$*"
}
safe_read() {
    if [ -t 0 ]; then
        read -r "$@"
    elif [ -r /dev/tty ]; then
        read -r "$@" < /dev/tty
    else
        read -r "$@"
    fi
}
confirm_action() {
    _prompt="$1"
    if [ "${SILENT_APPLY:-0}" = 1 ]; then
        log_msg "Автоматическое подтверждение: $_prompt"
        return 0
    fi
    printf "\n${C_WHITE}%s${C_NC}\n" "$_prompt"
    printf "  ${C_GREEN}[Y / Н] — Да, выполнить${C_NC}\n"
    printf "  ${C_RED}[N / Т / Enter] — Нет, отменить${C_NC}\n"
    menu_prompt
    safe_read _ans
    case "$_ans" in
        y|Y|н|Н) return 0 ;;
        n|N|т|Т|"") return 1 ;;
        *) warn_msg "Используйте Y/Н — Да или N/Т/Enter — Нет."; return 1 ;;
    esac
}
pause() { [ "${SILENT_APPLY:-0}" = 1 ] && return 0; printf "\n${C_WHITE}Нажмите Enter...${C_NC}"; safe_read _dummy; }
clear_screen() { command -v clear >/dev/null 2>&1 && clear || printf '\033[2J\033[H'; printf '\033[1;37m'; }
menu_header() {
clear_screen
_title="$1"
_full_title="$_title — by PoTuStoronu222"
printf "\n${C_TITLE}╔══════════════════════════════════════════════════════════════════════╗${C_NC}\n"
printf "${C_TITLE}║${C_NC} ${C_BOLD}${C_YELLOW}%-68s${C_NC} ${C_TITLE}║${C_NC}\n" "$_full_title"
printf "${C_TITLE}╚══════════════════════════════════════════════════════════════════════╝${C_NC}\n"
}
menu_section() {
printf "\n${C_YELLOW}${C_BOLD}%s${C_NC}\n" "$1"
}
menu_item() {
printf "  ${C_CYAN}${C_BOLD}%-5s${C_NC} ${C_YELLOW}${C_BOLD}%s${C_NC}\n" "$1" "$2"
}
menu_item_state() {
printf "  ${C_CYAN}${C_BOLD}%-5s${C_NC} ${C_YELLOW}${C_BOLD}%-42s${C_NC} %b\n" "$1" "$2" "$3"
}
menu_item_action() {
    _key="$1"
    _title="$2"
    _module="$3"
    _state="$4"
    [ -n "$_state" ] || _state="$(check_module_state "$_module")"

    case "$_module" in
        luci)
            case "$_state" in
                0) _action="Установить" ;;
                1) _action="Удалить" ;;
                2) _action="Восстановить" ;;
                *) _action="Изменить" ;;
            esac
            ;;
        *)
            case "$_state" in
                0) _action="Включить" ;;
                1) _action="Выключить" ;;
                2) _action="Исправить" ;;
                *) _action="Изменить" ;;
            esac
            ;;
    esac

    printf "  ${C_CYAN}${C_BOLD}%-5s${C_NC} ${C_YELLOW}${C_BOLD}%-13s${C_NC} %s\n" "$_key" "$_action" "$_title"
}

menu_back() {
printf "\n${C_GREEN}${C_BOLD}[Enter]${C_NC} ${C_CYAN}Назад${C_NC}\n\n"
}
menu_prompt() {
printf "${C_YELLOW}${C_BOLD}Выберите пункт: ${C_NC}"
}
# ==========================================
# ==========================================
preflight_readonly() {
    [ "$(id -u 2>/dev/null)" = 0 ] || { err_msg "Нужны права root."; exit 1; }
    [ -f /etc/openwrt_release ] || { err_msg "Это не OpenWrt."; exit 1; }
    command -v timeout >/dev/null 2>&1 && HAVE_TIMEOUT=yes || HAVE_TIMEOUT=no
    SYS_OWRT="$(sed -n "s/^DISTRIB_RELEASE='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"
    SYS_REV="$(sed -n "s/^DISTRIB_REVISION='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"
    SYS_TARGET="$(sed -n "s/^DISTRIB_TARGET='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"
    SYS_ARCH="$(sed -n "s/^DISTRIB_ARCH='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"

    # OpenWrt 24.10 and older use opkg; 25.12+ uses apk. Prefer the
    # release-native manager when a custom image contains both tools.
    case "$SYS_OWRT" in
        25.*|26.*|27.*|[3-9][0-9].*)
            if command -v apk >/dev/null 2>&1; then
                PKG_MGR="apk"
            elif command -v opkg >/dev/null 2>&1; then
                PKG_MGR="opkg"
                log_msg "Предупреждение: OpenWrt $SYS_OWRT ожидает apk, но найден только opkg; использую доступный менеджер пакетов."
            else
                PKG_MGR="unknown"
            fi
            ;;
        *)
            if command -v opkg >/dev/null 2>&1; then
                PKG_MGR="opkg"
            elif command -v apk >/dev/null 2>&1; then
                PKG_MGR="apk"
                log_msg "Предупреждение: OpenWrt $SYS_OWRT ожидает opkg, но найден только apk; использую доступный менеджер пакетов."
            else
                PKG_MGR="unknown"
            fi
            ;;
    esac
    [ "$PKG_MGR" != unknown ] || { err_msg "Не найден менеджер пакетов opkg/apk."; exit 1; }
}

# ==========================================
# ==========================================
init_dirs() {
    mkdir -p "$CFG_DIR" "$STATE_DIR" "$BASELINE_DIR" 2>/dev/null || return 1
    if [ -n "${TMP_DIR:-}" ]; then
        mkdir -p "$TMP_DIR" 2>/dev/null || return 1
    fi
    [ -f "$OWNERSHIP" ] || { (umask 077; : > "$OWNERSHIP") 2>/dev/null || return 1; }
    chmod 600 "$OWNERSHIP" 2>/dev/null || true
}
# ==========================================
# ==========================================
baseline_files() {
printf '%s\n'  /etc/config/dhcp  /etc/config/https-dns-proxy  /etc/config/firewall  /etc/config/system  /etc/config/ttyd     /etc/dnsmasq.d/90-dns-manager-bogus.conf    
}
sanitize_baseline_shared_files() {
    [ -s "$BASELINE_MANIFEST" ] && {
        _bf_tmp="${BASELINE_MANIFEST}.tmp.$$"
        sed '\|^/etc/crontabs/root|d' "$BASELINE_MANIFEST" > "$_bf_tmp" 2>/dev/null && mv "$_bf_tmp" "$BASELINE_MANIFEST" 2>/dev/null || rm -f "$_bf_tmp" 2>/dev/null
    }
    [ -s "$BASELINE_LAST" ] && {
        _bl_tmp="${BASELINE_LAST}.tmp.$$"
        sed '\|^/etc/crontabs/root|d' "$BASELINE_LAST" > "$_bl_tmp" 2>/dev/null && mv "$_bl_tmp" "$BASELINE_LAST" 2>/dev/null || rm -f "$_bl_tmp" 2>/dev/null
    }
    rm -f "$BASELINE_DIR/files/etc_crontabs_root" 2>/dev/null || true
}
baseline_key() {
printf '%s' "$1" | sed 's#^/##; s#[/ ]#_#g'
}
ensure_baseline_captured() {
    [ -s "$BASELINE_MANIFEST" ] && return 0
    if [ "${MUTATION_LOCK_HELD:-0}" = 1 ]; then
        baseline_capture_once
        return $?
    fi
    acquire_mutation_lock || return 1
    baseline_capture_once
    _rc=$?
    release_mutation_lock
    return "$_rc"
}
baseline_capture_once() {
    sanitize_baseline_shared_files 2>/dev/null || true
    [ -s "$BASELINE_MANIFEST" ] && return 0
    mkdir -p "$BASELINE_DIR/files" || return 1
    : > "$BASELINE_MANIFEST"
    while IFS= read -r _f; do
        [ -n "$_f" ] || continue
        _k="$(baseline_key "$_f")"
        if [ -f "$_f" ]; then
            cp -p "$_f" "$BASELINE_DIR/files/$_k" 2>/dev/null || return 1
            _h="$(file_hash "$_f")"
            printf '%s|%s|1|%s\n' "$_f" "$_k" "$_h" >> "$BASELINE_MANIFEST"
        else
            printf '%s|%s|0|NONE\n' "$_f" "$_k" >> "$BASELINE_MANIFEST"
        fi
    done <<EOF_BASELINE
$(baseline_files)
EOF_BASELINE
    printf 'created_at=%s\n' "$(date +%s)" > "$BASELINE_META"
    printf 'manager_version=%s\n' "$VERSION" >> "$BASELINE_META"
    printf 'clean_profile=1\n' >> "$BASELINE_META"
    printf 'openwrt_release=%s\n' "$SYS_OWRT" >> "$BASELINE_META"
    printf 'firewall=%s\n' "$SYS_FW" >> "$BASELINE_META"
    # Snapshot relevant service/package state before the first manager mutation.
    for _svc in https-dns-proxy dnsmasq sysntpd ttyd; do
        if [ -x "/etc/init.d/$_svc" ]; then
            "/etc/init.d/$_svc" enabled >/dev/null 2>&1 && _en=yes || _en=no
        else
            _en=unknown
        fi
        case "$_svc" in
            https-dns-proxy) pidof https-dns-proxy >/dev/null 2>&1 && _run=yes || _run=no ;;
            dnsmasq) pidof dnsmasq >/dev/null 2>&1 && _run=yes || _run=no ;;
            sysntpd) [ -x /etc/init.d/sysntpd ] && /etc/init.d/sysntpd status >/dev/null 2>&1 && _run=yes || _run=no ;;
            ttyd) pidof ttyd >/dev/null 2>&1 && _run=yes || _run=no ;;
        esac
        printf 'service_%s_enabled=%s\n' "$_svc" "$_en" >> "$BASELINE_META"
        printf 'service_%s_running=%s\n' "$_svc" "$_run" >> "$BASELINE_META"
    done
    for _pkg in curl https-dns-proxy ca-bundle dnsmasq bind-dig knot-dig ttyd luci-app-https-dns-proxy; do
        package_is_installed "$_pkg" && _pst=1 || _pst=0
        printf 'package_%s=%s\n' "$_pkg" "$_pst" >> "$BASELINE_META"
    done
    info_msg "Исходная конфигурация до первого изменения DNS Manager сохранена."
    log_tx "BASELINE" "router" "CAPTURE" "OK" "dir=$BASELINE_DIR;clean_profile=1"
}
baseline_mark_applied() {
    [ -s "$BASELINE_MANIFEST" ] || return 1
    : > "$BASELINE_LAST"
    while IFS='|' read -r _f _k _existed _basehash; do
        [ -n "$_f" ] || continue
        if [ -f "$_f" ]; then
            _curh="$(file_hash "$_f")"
            printf '%s|%s|1|%s\n' "$_f" "$_k" "$_curh" >> "$BASELINE_LAST"
        else
            printf '%s|%s|0|NONE\n' "$_f" "$_k" >> "$BASELINE_LAST"
        fi
    done < "$BASELINE_MANIFEST"
    return 0
}
baseline_restore_path() {
    case "$1" in
        /etc/sysctl.d/90-dns-manager.conf|/etc/sysctl.d/91-dns-manager-extended.conf|/etc/dnsmasq.d/91-dns-manager-client-fixes.conf)
            rm -f "$1" >/dev/null 2>&1 || true
            return 0
            ;;
    esac
    _path="$1"
    [ -n "$_path" ] || return 3
    [ -s "$BASELINE_MANIFEST" ] || return 3
    _base_line="$(awk -F"|" -v f="$_path" '$1==f{print;exit}' "$BASELINE_MANIFEST" 2>/dev/null)"
    [ -n "$_base_line" ] || return 3
    IFS="|" read -r _bf _bk _base_existed _base_hash <<EOF_RB_BASE
$_base_line
EOF_RB_BASE
    if [ "$_base_existed" = 1 ]; then
        [ -f "$BASELINE_DIR/files/$_bk" ] || return 3
        cp -p "$BASELINE_DIR/files/$_bk" "$_path" 2>/dev/null || return 1
    else
        rm -f "$_path" 2>/dev/null || return 1
    fi
    return 0
}
baseline_restore() {
    BASELINE_RESTORED_DHCP=0
    BASELINE_RESTORED_HDP=0
    BASELINE_RESTORED_FIREWALL=0
    BASELINE_RESTORED_SYSTEM=0
    BASELINE_RESTORED_BOGUS=0
    BASELINE_RESTORE_COUNT=0

    [ -s "$BASELINE_MANIFEST" ] || return 2
    [ -s "$BASELINE_LAST" ] || return 2
    grep -q '^clean_profile=1$' "$BASELINE_META" 2>/dev/null || return 2

    for _f in $(baseline_files); do
        [ -n "$_f" ] || continue
        _r=3
        baseline_restore_path "$_f" && _r=0 || _r=$?
        [ "$_r" -eq 0 ] || continue
        BASELINE_RESTORE_COUNT=$((BASELINE_RESTORE_COUNT+1))
        case "$_f" in
            /etc/config/dhcp) BASELINE_RESTORED_DHCP=1;;
            /etc/config/https-dns-proxy) BASELINE_RESTORED_HDP=1;;
            /etc/config/firewall) BASELINE_RESTORED_FIREWALL=1;;
            /etc/config/system) BASELINE_RESTORED_SYSTEM=1;;
            /etc/dnsmasq.d/90-dns-manager-bogus.conf) BASELINE_RESTORED_BOGUS=1;;
        esac
    done

    [ "$BASELINE_RESTORE_COUNT" -gt 0 ] || return 2
    log_tx "BASELINE" "router" "RESTORE" "OK" "files=$BASELINE_RESTORE_COUNT;per_file=yes"
    return 0
}

clear_baseline_for_reacquire() {
    rm -rf "$BASELINE_DIR" 2>/dev/null
    mkdir -p "$BASELINE_DIR/files" 2>/dev/null || return 1
    rm -f "$BASELINE_MANIFEST" "$BASELINE_LAST" "$BASELINE_META" 2>/dev/null
    info_msg "Исходная копия удалена. При следующем применении будет создана новая."
}
baseline_uninstall_validate() {
    [ -s "$BASELINE_MANIFEST" ] || return 1
    [ -d "$BASELINE_DIR/files" ] || return 1
    grep -q '^clean_profile=1$' "$BASELINE_META" 2>/dev/null || return 1

    _valid=0
    while IFS='|' read -r _f _k _existed _hash; do
        [ -n "$_f" ] || continue
        case "$_f" in
            /etc/sysctl.d/90-dns-manager.conf|/etc/sysctl.d/91-dns-manager-extended.conf|/etc/dnsmasq.d/91-dns-manager-client-fixes.conf)
                continue
                ;;
            /etc/config/dhcp|/etc/config/https-dns-proxy|/etc/config/firewall|/etc/config/system|/etc/config/ttyd|/etc/dnsmasq.d/90-dns-manager-bogus.conf)
                ;;
            *) return 1 ;;
        esac
        [ "$_k" = "$(baseline_key "$_f")" ] || return 1
        case "$_existed" in
            0) [ "$_hash" = NONE ] || return 1 ;;
            1)
                [ -f "$BASELINE_DIR/files/$_k" ] || return 1
                _saved_hash="$(file_hash "$BASELINE_DIR/files/$_k" 2>/dev/null)"
                [ -n "$_saved_hash" ] && [ "$_saved_hash" = "$_hash" ] || return 1
                ;;
            *) return 1 ;;
        esac
        _valid=$((_valid+1))
    done < "$BASELINE_MANIFEST"
    [ "$_valid" -gt 0 ] || return 1
    return 0
}
manager_state_requires_original_restore() {
    # A baseline is required only when DNS Manager changed the core DNS path.
    # Standalone additional modules are reverted directly to their stock state.
    [ -s "$OWNERSHIP" ] && grep -Eq '^(doh|dnsmasq)\|' "$OWNERSHIP" 2>/dev/null && return 0
    [ -s "$CONFIG_FILE" ] && {
        for _v in SLOT_1 SLOT_2 SLOT_3 SLOT_4 SLOT_5 SLOT_6 SLOT_RU PORT_1 PORT_2 PORT_3 PORT_4 PORT_5 PORT_6 PORT_RU; do
            eval "_mv=\${$_v:-}"
            [ -n "$_mv" ] && return 0
        done
    }
    return 1
}
baseline_restore_for_uninstall() {
    baseline_uninstall_validate || {
        warn_msg "Исходная копия DNS Manager отсутствует или повреждена. Без неё удаление остановлено, чтобы не угадывать исходные настройки."
        return 1
    }
    [ -s "$BASELINE_LAST" ] || {
        warn_msg "Контрольный снимок последнего применения отсутствует. Без него удаление общих UCI-файлов не выполняю."
        return 1
    }

    UNINSTALL_RESTORED_DHCP=0
    UNINSTALL_RESTORED_HDP=0
    UNINSTALL_RESTORED_FIREWALL=0
    UNINSTALL_RESTORED_SYSTEM=0
    UNINSTALL_RESTORED_TTYD=0
    UNINSTALL_RESTORED_BOGUS=0
    UNINSTALL_RESTORE_COUNT=0
    UNINSTALL_SKIPPED_COUNT=0

    # Restore the original file only when it still matches the state recorded
    # after the last successful DNS Manager Apply. Otherwise preserve the file
    # and let the targeted cleanup remove only manager-owned artifacts.
    while IFS='|' read -r _f _k _existed _base_hash; do
        [ -n "$_f" ] || continue
        if baseline_restore_path "$_f"; then
            UNINSTALL_RESTORE_COUNT=$((UNINSTALL_RESTORE_COUNT+1))
            case "$_f" in
                /etc/config/dhcp) UNINSTALL_RESTORED_DHCP=1 ;;
                /etc/config/https-dns-proxy) UNINSTALL_RESTORED_HDP=1 ;;
                /etc/config/firewall) UNINSTALL_RESTORED_FIREWALL=1 ;;
                /etc/config/system) UNINSTALL_RESTORED_SYSTEM=1 ;;
                /etc/config/ttyd) UNINSTALL_RESTORED_TTYD=1 ;;
                /etc/dnsmasq.d/90-dns-manager-bogus.conf) UNINSTALL_RESTORED_BOGUS=1 ;;
            esac
        else
            _r=$?
            UNINSTALL_SKIPPED_COUNT=$((UNINSTALL_SKIPPED_COUNT+1))
            [ "$_r" = 2 ] || return 1
        fi
    done < "$BASELINE_MANIFEST"

    [ "$UNINSTALL_RESTORE_COUNT" -gt 0 ] || [ "$UNINSTALL_SKIPPED_COUNT" -gt 0 ] || return 1
    log_tx "UNINSTALL" "baseline" "RESTORE" "OK" "restored=$UNINSTALL_RESTORE_COUNT;skipped=$UNINSTALL_SKIPPED_COUNT;guard=enabled"
    return 0
}
catalog_download() {
    _out="$1"
    _url="${DNSCAT_URL}?_dmcb=$(date +%s 2>/dev/null || printf 0)-$$"
    rm -f "$_out" 2>/dev/null || true
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 5 --max-time 30 -o "$_out" "$_url" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 30 -O "$_out" "$_url" >/dev/null 2>&1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$_out" "$_url" >/dev/null 2>&1
    else
        return 1
    fi
    [ -s "$_out" ] || return 1
    [ "$(wc -c < "$_out" 2>/dev/null | tr -d " ")" -le 30000 ] 2>/dev/null || return 1
    return 0
}
catalog_validate_file() {
    _f="$1"
    _mode="${2:-strict}"
    [ -s "$_f" ] || return 1
    _ver="$(sed -n "s/^# DNSCATVER=//p" "$_f" 2>/dev/null | head -n1)"
    [ "$_ver" = "$DNSCAT_VERSION" ] || return 1
    if [ "$_mode" != "legacy" ]; then
        grep -Fqx "# DNSCATREV=$DNSCAT_REVISION" "$_f" 2>/dev/null || return 1
        grep -Fqx "# ENTRIES=105" "$_f" 2>/dev/null || return 1
    fi
    awk -F'|' '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
            count++
            if (NF != 7 || $1 == "" || $4 == "" || $5 !~ /^https:\/\//) bad=1
            if ($1 !~ /^[A-Za-z0-9_-]+$/) bad=1
            if ($2 !~ /^(bypass|clean|security|privacy|adblock|family|regional)$/) bad=1
            ids[$1]++
            if (ids[$1] > 1) bad=1
        }
        END { if (bad || count != 105) exit 1 }
    ' "$_f" >/dev/null 2>&1 || return 1
    return 0
}
write_catalogs() {
    if catalog_validate_file "$DNS_CATALOG"; then
        return 0
    fi
    _catalog_tmp="/tmp/dns-manager-catalog-$$"
    rm -f "$_catalog_tmp" 2>/dev/null || true
    if catalog_download "$_catalog_tmp" && catalog_validate_file "$_catalog_tmp"; then
        mkdir -p "$CFG_DIR" 2>/dev/null || true
        if mv -f "$_catalog_tmp" "$DNS_CATALOG" 2>/dev/null; then
            chmod 600 "$DNS_CATALOG" 2>/dev/null || true
            log_msg "Каталог DNS: загружен внешний $DNSCAT_VERSION (revision $DNSCAT_REVISION, 105 записей)."
            return 0
        fi
    fi
    rm -f "$_catalog_tmp" 2>/dev/null || true
    if catalog_validate_file "$DNS_CATALOG" legacy; then
        log_msg "Каталог DNS: внешний источник недоступен; использую локальную совместимую копию $DNSCAT_VERSION."
        return 0
    fi
    err_msg "Каталог DNS $DNSCAT_VERSION не удалось получить и локальная копия отсутствует/повреждена."
    return 1
}
sync_regional_dns_state() {
    if [ -n "${SLOT_RU:-}" ]; then
        TLD_RU_ENABLED=1
        TLD_SPLIT=1
    else
        TLD_RU_ENABLED=0
        TLD_SPLIT=0
    fi
}
load_config() {
_had_dns_profile=0
[ -f "$CONFIG_FILE" ] && grep -q '^DNS_PROFILE=' "$CONFIG_FILE" 2>/dev/null && _had_dns_profile=1
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE" 2>/dev/null
# Deprecated tuning flags from older releases are ignored by the active manager.
BOOTSTRAP_DNS="$BOOTSTRAP_DNS_ALL"
# procd watchdog: only the operator-facing interval is configurable.
# All repair/guard limits are fixed internal safeguards.
WATCHDOG_BACKEND="procd"
: "${WATCHDOG_INTERVAL:=${WATCHDOG_CHECK_INTERVAL_DEFAULT:-90}}"
case "$WATCHDOG_INTERVAL" in
    ''|*[!0-9]*) WATCHDOG_INTERVAL="${WATCHDOG_CHECK_INTERVAL_DEFAULT:-90}" ;;
    *)
        [ "$WATCHDOG_INTERVAL" -ge 30 ] 2>/dev/null || WATCHDOG_INTERVAL="${WATCHDOG_CHECK_INTERVAL_DEFAULT:-90}"
        [ "$WATCHDOG_INTERVAL" -le 600 ] 2>/dev/null || WATCHDOG_INTERVAL="${WATCHDOG_CHECK_INTERVAL_DEFAULT:-90}"
        ;;
esac
WATCHDOG_FAIL_THRESHOLD=2
WATCHDOG_REPAIR_COOLDOWN=300
WATCHDOG_GUARD_INTERVAL=900
WATCHDOG_MAX_REPAIRS=1
WATCHDOG_MAX_RESTARTS=2
WATCHDOG_MAX_CANDIDATES=3
: "${SLOT_1:=}"; : "${SLOT_2:=}"; : "${SLOT_3:=}"; : "${SLOT_4:=}"; : "${SLOT_5:=}"; : "${SLOT_6:=}"
: "${SLOT_RU:=}"
: "${SLOT_1_CAT:=}"; : "${SLOT_2_CAT:=}"; : "${SLOT_3_CAT:=}"; : "${SLOT_4_CAT:=}"; : "${SLOT_5_CAT:=}"; : "${SLOT_6_CAT:=}"
: "${SLOT_RU_CAT:=}"
: "${PORT_1:=}"; : "${PORT_2:=}"; : "${PORT_3:=}"; : "${PORT_4:=}"; : "${PORT_5:=}"; : "${PORT_6:=}"
: "${PORT_RU:=}"
: "${BOOTSTRAP_DNS:=$BOOTSTRAP_DNS_ALL}"
: "${TLD_RU_ENABLED:=1}"; : "${FORCE_DOH:=0}"
: "${NTP_IP_FALLBACK:=1}"; : "${DNSMASQ_PERF:=0}"
: "${BALANCER_ENABLED:=1}"; : "${NTP_PRESET:=vniiftri_moscow}"; : "${NTP_PRESET_USER_SET:=0}"; : "${DNS_PROFILE:=hybrid}"; : "${DNS_SELECTION_MODE:=quick}"; : "${DNS_SELECTION_CATEGORY:=bypass}"
: "${QUICK_PREF_1:=}"; : "${QUICK_PREF_2:=}"; : "${QUICK_PREF_3:=}"; : "${QUICK_PREF_4:=}"; : "${QUICK_PREF_5:=}"; : "${QUICK_PREF_6:=}"
: "${WATCHDOG_ENABLED:=0}"; : "${WATCHDOG_INTERVAL:=90}"; : "${WATCHDOG_BACKEND:=procd}"
: "${TEST_RESULTS_MAX_AGE_BYPASS:=21600}"; : "${TEST_RESULTS_MAX_AGE_CLEAN:=21600}"
: "${TEST_RESULTS_MAX_AGE_SECURITY:=21600}"; : "${TEST_RESULTS_MAX_AGE_PRIVACY:=21600}"
: "${TEST_RESULTS_MAX_AGE_ADBLOCK:=21600}"; : "${TEST_RESULTS_MAX_AGE_FAMILY:=21600}"
: "${TEST_RESULTS_MAX_AGE_REGIONAL:=21600}"
: "${WEB_ACCESS_ENABLED:=0}"; : "${WEB_ACCESS_PORT:=7682}"
TLD_SPLIT="$TLD_RU_ENABLED"
if [ "$_had_dns_profile" = 0 ] && [ -z "$DNS_PROFILE" ]; then
DNS_PROFILE="hybrid"
fi
if [ "$DNS_PROFILE" = "hybrid" ]; then
    for _slot in 1 2 3 4 5 6 RU; do
        eval "_sid=\${SLOT_${_slot}:-}"
        eval "_scat=\${SLOT_${_slot}_CAT:-}"
        if [ -n "$_sid" ] && [ -z "$_scat" ]; then
            _scat="$(dns_cat "$_sid")"
            case "$_slot" in RU) [ -n "$_scat" ] || _scat="regional" ;; esac
            slot_cat_set "$_slot" "$_scat" || return 1
        fi
    done
fi
# Старые версии имели Cloudflare как неявный NTP-профиль по умолчанию.
# Если пользователь явно не выбирал профиль, переводим старый неявный default на ВНИИФТРИ.
if [ "${NTP_PRESET_USER_SET:-0}" != 1 ] && [ "${NTP_PRESET:-}" = "cf_ip" ]; then
    NTP_PRESET="vniiftri_moscow"
fi
repair_catalog_category_state
sync_regional_dns_state
}
repair_catalog_category_state() {
    _id="doh_lacontrevoie"
    _cat="$(dns_cat "$_id" 2>/dev/null || true)"
    [ "$_cat" = "clean" ] || return 0

    _changed=0
    for _slot in 1 2 3 4 5 6 RU RU_2; do
        eval "_sid=\${SLOT_${_slot}:-}"
        [ "$_sid" = "$_id" ] || continue
        eval "_scat=\${SLOT_${_slot}_CAT:-}"
        if [ "$_scat" != "clean" ]; then
            eval "SLOT_${_slot}_CAT=\"clean\""
            _changed=1
        fi
    done

    if [ -s "$TEST_RESULTS" ]; then
        _results_tmp="$TMP_DIR/catalog-category-repair.${PPID}"
        awk -F'|' -v OFS='|' '
            $1=="doh_lacontrevoie" { $2="clean" }
            { print }
        ' "$TEST_RESULTS" > "$_results_tmp" 2>/dev/null && mv -f "$_results_tmp" "$TEST_RESULTS" 2>/dev/null || rm -f "$_results_tmp" 2>/dev/null || true
    fi

    [ "$_changed" = 1 ] && save_config >/dev/null 2>&1 || true
    return 0
}

save_config() {
    [ "${TX_ACTIVE:-0}" = 1 ] && [ "${DEFER_CONFIG_SAVE:-0}" = 1 ] && return 0
sync_regional_dns_state
mkdir -p "$CFG_DIR" 2>/dev/null || return 1
_cfg_tmp="${CONFIG_FILE}.tmp.$$"
( umask 077
cat > "$_cfg_tmp" <<EOF_CFG
SLOT_1="$SLOT_1"
SLOT_2="$SLOT_2"
SLOT_3="$SLOT_3"
SLOT_4="$SLOT_4"
SLOT_5="$SLOT_5"
SLOT_6="$SLOT_6"
SLOT_RU="$SLOT_RU"
SLOT_1_CAT="$SLOT_1_CAT"
SLOT_2_CAT="$SLOT_2_CAT"
SLOT_3_CAT="$SLOT_3_CAT"
SLOT_4_CAT="$SLOT_4_CAT"
SLOT_5_CAT="$SLOT_5_CAT"
SLOT_6_CAT="$SLOT_6_CAT"
SLOT_RU_CAT="$SLOT_RU_CAT"
PORT_1="$PORT_1"
PORT_2="$PORT_2"
PORT_3="$PORT_3"
PORT_4="$PORT_4"
PORT_5="$PORT_5"
PORT_6="$PORT_6"
PORT_RU="$PORT_RU"
BOOTSTRAP_DNS="$BOOTSTRAP_DNS_ALL"
TLD_RU_ENABLED="$TLD_RU_ENABLED"
NTP_IP_FALLBACK="$NTP_IP_FALLBACK"
FORCE_DOH="$FORCE_DOH"
DNSMASQ_PERF="$DNSMASQ_PERF"
BALANCER_ENABLED="$BALANCER_ENABLED"
NTP_PRESET="$NTP_PRESET"
NTP_PRESET_USER_SET="$NTP_PRESET_USER_SET"
DNS_PROFILE="$DNS_PROFILE"
DNS_SELECTION_MODE="$DNS_SELECTION_MODE"
DNS_SELECTION_CATEGORY="$DNS_SELECTION_CATEGORY"
QUICK_PREF_1="$QUICK_PREF_1"
QUICK_PREF_2="$QUICK_PREF_2"
QUICK_PREF_3="$QUICK_PREF_3"
QUICK_PREF_4="$QUICK_PREF_4"
QUICK_PREF_5="$QUICK_PREF_5"
QUICK_PREF_6="$QUICK_PREF_6"
WATCHDOG_ENABLED="$WATCHDOG_ENABLED"
WATCHDOG_INTERVAL="$WATCHDOG_INTERVAL"
WATCHDOG_BACKEND="$WATCHDOG_BACKEND"
TEST_RESULTS_MAX_AGE="$TEST_RESULTS_MAX_AGE"
TEST_RESULTS_MAX_AGE_BYPASS="$TEST_RESULTS_MAX_AGE_BYPASS"
TEST_RESULTS_MAX_AGE_CLEAN="$TEST_RESULTS_MAX_AGE_CLEAN"
TEST_RESULTS_MAX_AGE_SECURITY="$TEST_RESULTS_MAX_AGE_SECURITY"
TEST_RESULTS_MAX_AGE_PRIVACY="$TEST_RESULTS_MAX_AGE_PRIVACY"
TEST_RESULTS_MAX_AGE_ADBLOCK="$TEST_RESULTS_MAX_AGE_ADBLOCK"
TEST_RESULTS_MAX_AGE_FAMILY="$TEST_RESULTS_MAX_AGE_FAMILY"
TEST_RESULTS_MAX_AGE_REGIONAL="$TEST_RESULTS_MAX_AGE_REGIONAL"
WEB_ACCESS_ENABLED="$WEB_ACCESS_ENABLED"
WEB_ACCESS_PORT="$WEB_ACCESS_PORT"
EOF_CFG
) || { rm -f "$_cfg_tmp"; return 1; }
chmod 600 "$_cfg_tmp" 2>/dev/null || true
mv "$_cfg_tmp" "$CONFIG_FILE" || { rm -f "$_cfg_tmp"; return 1; }
}
# ==========================================
# ==========================================
firewall_resolve_zones() {
    FIREWALL_LAN_ZONE=""
    FIREWALL_WAN_ZONE=""
    FIREWALL_LAN_NAME=""
    FIREWALL_WAN_NAME=""
    FIREWALL_WAN_NETWORK=""

    _lan_zone=""
    _lan_name=""
    _lan_count=0
    _wan_zone=""
    _wan_name=""
    _wan_net=""

    _zones="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=zone$/\1/p')"

    # LAN: exactly the zone containing network=lan.
    for _z in $_zones; do
        _nets="$(uci -q get "firewall.$_z.network" 2>/dev/null)"
        if printf '%s\n' "$_nets" | tr ' ' '\n' | grep -qxF lan 2>/dev/null; then
            _lan_count=$((_lan_count + 1))
            _lan_zone="$_z"
            _lan_name="$(uci -q get "firewall.$_z.name" 2>/dev/null)"
        fi
    done

    # WAN resolution is deliberately deterministic:
    # 1) a zone containing network=wan wins;
    # 2) otherwise a zone literally named wan wins;
    # 3) otherwise use the zone whose network/device carries the active default route;
    # 4) finally use a single preferred WAN-like network as a last resort.
    _wan_exact_count=0
    _wan_exact_zone=""
    _wan_exact_name=""
    _wan_exact_net=""
    for _z in $_zones; do
        _nets="$(uci -q get "firewall.$_z.network" 2>/dev/null)"
        if printf '%s\n' "$_nets" | tr ' ' '\n' | grep -qxF wan 2>/dev/null; then
            _wan_exact_count=$((_wan_exact_count + 1))
            _wan_exact_zone="$_z"
            _wan_exact_name="$(uci -q get "firewall.$_z.name" 2>/dev/null)"
            _wan_exact_net="wan"
        fi
    done
    if [ "$_wan_exact_count" = 1 ]; then
        _wan_zone="$_wan_exact_zone"
        _wan_name="$_wan_exact_name"
        _wan_net="$_wan_exact_net"
    else
        _wan_named_count=0
        _wan_named_zone=""
        _wan_named_name=""
        _wan_named_net=""
        for _z in $_zones; do
            _zname="$(uci -q get "firewall.$_z.name" 2>/dev/null)"
            case "$_z|$_zname" in
                wan|wan\|wan)
                    _wan_named_count=$((_wan_named_count + 1))
                    _wan_named_zone="$_z"
                    _wan_named_name="$_zname"
                    _wn="$(uci -q get "firewall.$_z.network" 2>/dev/null)"
                    _wan_named_net="$(printf '%s\n' "$_wn" | tr ' ' '\n' | head -n1)"
                    ;;
            esac
        done
        if [ "$_wan_named_count" = 1 ]; then
            _wan_zone="$_wan_named_zone"
            _wan_name="$_wan_named_name"
            _wan_net="$_wan_named_net"
        fi
    fi

    if [ -z "$_wan_zone" ]; then
        _default_devs="$(ip -4 route show default 2>/dev/null | sed -n 's/.*[[:space:]]dev[[:space:]]\([^[:space:]]*\).*/\1/p' | sort -u)"
        [ -n "$_default_devs" ] || _default_devs="$(ip -4 route show 0.0.0.0/0 2>/dev/null | sed -n 's/.*[[:space:]]dev[[:space:]]\([^[:space:]]*\).*/\1/p' | sort -u)"
        _route_count=0
        _route_zone=""
        _route_name=""
        _route_net=""
        for _z in $_zones; do
            _zname="$(uci -q get "firewall.$_z.name" 2>/dev/null)"
            _nets="$(uci -q get "firewall.$_z.network" 2>/dev/null)"
            for _n in $_nets; do
                [ -n "$_n" ] || continue
                case "$_n|$_z|$_zname" in
                    *'|zmvpn|'*|*'|zmvpn|zmvpn'*) continue ;;
                esac
                _udev="$(uci -q get "network.$_n.device" 2>/dev/null)"
                [ -n "$_udev" ] || _udev="$(uci -q get "network.$_n.ifname" 2>/dev/null)"
                [ -n "$_udev" ] || continue
                for _d in $_default_devs; do
                    [ -n "$_d" ] || continue
                    if printf '%s\n' "$_udev" | tr ' ' '\n' | grep -qxF "$_d" 2>/dev/null; then
                        _route_count=$((_route_count + 1))
                        _route_zone="$_z"
                        _route_name="$_zname"
                        _route_net="$_n"
                        break
                    fi
                done
            done
        done
        if [ "$_route_count" = 1 ]; then
            _wan_zone="$_route_zone"
            _wan_name="$_route_name"
            _wan_net="$_route_net"
        fi
    fi

    if [ -z "$_wan_zone" ]; then
        _preferred_wan_nets="wwan wwan0 cellular mobile lte lte0 5g 5g0 modem usbwan"
        _fallback_count=0
        _fallback_zone=""
        _fallback_name=""
        _fallback_net=""
        for _z in $_zones; do
            _zname="$(uci -q get "firewall.$_z.name" 2>/dev/null)"
            case "$_z|$_zname" in
                *'zmvpn|'*|*'|zmvpn'*) continue ;;
            esac
            _nets="$(uci -q get "firewall.$_z.network" 2>/dev/null)"
            for _n in $_preferred_wan_nets; do
                if printf '%s\n' "$_nets" | tr ' ' '\n' | grep -qxF "$_n" 2>/dev/null; then
                    _fallback_count=$((_fallback_count + 1))
                    _fallback_zone="$_z"
                    _fallback_name="$_zname"
                    _fallback_net="$_n"
                    break
                fi
            done
        done
        if [ "$_fallback_count" = 1 ]; then
            _wan_zone="$_fallback_zone"
            _wan_name="$_fallback_name"
            _wan_net="$_fallback_net"
        fi
    fi

    [ "$_lan_count" = 1 ] && {
        FIREWALL_LAN_ZONE="$_lan_zone"
        FIREWALL_LAN_NAME="$_lan_name"
    }
    [ -n "$_wan_zone" ] && {
        FIREWALL_WAN_ZONE="$_wan_zone"
        FIREWALL_WAN_NAME="$_wan_name"
        FIREWALL_WAN_NETWORK="$_wan_net"
    }
    return 0
}
firewall_zone_name() {
    _ref="$1"
    [ -n "$_ref" ] || return 1
    case "$_ref" in
        @zone\[*\]) uci -q get "firewall.$_ref.name" 2>/dev/null ;;
        *)
            if [ "$(uci -q get "firewall.$_ref" 2>/dev/null)" = zone ]; then
                uci -q get "firewall.$_ref.name" 2>/dev/null
            else
                printf '%s\n' "$_ref"
            fi
            ;;
    esac
}
firewall_ref_matches_zone() {
    _actual="$1"
    _expected="$2"
    [ -n "$_actual" ] && [ -n "$_expected" ] || return 1
    [ "$_actual" = "$_expected" ] && return 0
    _aname="$(firewall_zone_name "$_actual" 2>/dev/null)"
    _ename="$(firewall_zone_name "$_expected" 2>/dev/null)"
    [ -n "$_aname" ] && [ -n "$_ename" ] && [ "$_aname" = "$_ename" ]
}
firewall_lan_zone_require() {
    firewall_resolve_zones
    [ -n "$FIREWALL_LAN_ZONE" ] && [ -n "$FIREWALL_LAN_NAME" ] || {
        err_msg "Не удалось однозначно определить firewall-зону LAN. Настройка LAN-зависимого модуля не применена."
        return 1
    }
    printf '%s\n' "$FIREWALL_LAN_ZONE"
}
firewall_wan_zone_require() {
    firewall_resolve_zones
    [ -n "$FIREWALL_WAN_ZONE" ] && [ -n "$FIREWALL_WAN_NAME" ] || {
        err_msg "Не удалось однозначно определить firewall-зону WAN. Настройка WAN-зависимого модуля не применена."
        return 1
    }
    printf '%s\n' "$FIREWALL_WAN_ZONE"
}
detect_firewall_backend() {
    SYS_FW="unknown"
    FIREWALL_BACKEND="unknown"
    FIREWALL_DETECT_SOURCE="none"

    _has_fw4=0
    _has_fw3=0
    command -v fw4 >/dev/null 2>&1 && _has_fw4=1
    command -v fw3 >/dev/null 2>&1 && _has_fw3=1
    if [ -x /sbin/fw4 ] || [ -x /usr/sbin/fw4 ]; then _has_fw4=1; fi
    if [ -x /sbin/fw3 ] || [ -x /usr/sbin/fw3 ]; then _has_fw3=1; fi

    # Detect the backend that is actually loaded before falling back to which
    # binary is installed. This avoids preferring fw4 merely because a helper
    # binary happens to exist on a customized image.
    if [ "$_has_fw4" = 1 ] && command -v nft >/dev/null 2>&1 && nft list table inet fw4 >/dev/null 2>&1; then
        SYS_FW="fw4"
        FIREWALL_BACKEND="fw4"
        FIREWALL_DETECT_SOURCE="runtime"
    elif [ "$_has_fw3" = 1 ] && [ -f /var/run/fw3.state ]; then
        SYS_FW="fw3"
        FIREWALL_BACKEND="fw3"
        FIREWALL_DETECT_SOURCE="runtime"
    fi

    if [ "$SYS_FW" = unknown ]; then
        _fw_init="/etc/init.d/firewall"
        if [ -x "$_fw_init" ]; then
            if [ "$_has_fw4" = 1 ] && grep -q 'fw4' "$_fw_init" 2>/dev/null; then
                SYS_FW="fw4"
                FIREWALL_BACKEND="fw4"
                FIREWALL_DETECT_SOURCE="init"
            elif [ "$_has_fw3" = 1 ] && grep -q 'fw3' "$_fw_init" 2>/dev/null; then
                SYS_FW="fw3"
                FIREWALL_BACKEND="fw3"
                FIREWALL_DETECT_SOURCE="init"
            fi
        fi
    fi

    if [ "$SYS_FW" = unknown ]; then
        if [ "$_has_fw4" = 1 ] && [ "$_has_fw3" = 0 ]; then
            SYS_FW="fw4"
            FIREWALL_BACKEND="fw4"
            FIREWALL_DETECT_SOURCE="single-binary"
        elif [ "$_has_fw4" = 0 ] && [ "$_has_fw3" = 1 ]; then
            SYS_FW="fw3"
            FIREWALL_BACKEND="fw3"
            FIREWALL_DETECT_SOURCE="single-binary"
        fi
    fi
    return 0
}
disc_system() {
HAS_DNSMASQ="no"; command -v dnsmasq >/dev/null 2>&1 && HAS_DNSMASQ="yes"
detect_firewall_backend
HAS_CURL="no"; command -v curl >/dev/null 2>&1 && HAS_CURL="yes"
HAS_DIG="no"; command -v dig >/dev/null 2>&1 && HAS_DIG="yes"
HAS_NTPD="no"; command -v ntpd >/dev/null 2>&1 && HAS_NTPD="yes"
HAS_NTPQ="no"; command -v ntpq >/dev/null 2>&1 && HAS_NTPQ="yes"
HAS_HDP="no"; command -v https-dns-proxy >/dev/null 2>&1 && HAS_HDP="yes"
HDP_RUNNING="no"; pgrep -f '[h]ttps-dns-proxy' >/dev/null 2>&1 && HDP_RUNNING="yes"
IPV4_ROUTE="no"; ip -4 route show default 2>/dev/null | grep -q . && IPV4_ROUTE="yes"
IPV6_ROUTE="no"; ip -6 route show default 2>/dev/null | grep -q . && IPV6_ROUTE="yes"
FREE_OVERLAY="$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4}')"
}
disc_network() {
LAN_IP="$(uci -q get network.lan.ipaddr 2>/dev/null | cut -d/ -f1 | head -n1)"
if [ -z "$LAN_IP" ]; then
    _lan_dev="$(uci -q get network.lan.device 2>/dev/null)"
    _lan_if="$(uci -q get network.lan.ifname 2>/dev/null)"
    if [ -n "$_lan_dev" ]; then
        LAN_IP="$(ip -4 addr show dev "$_lan_dev" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
    fi
    if [ -z "$LAN_IP" ] && [ -n "$_lan_if" ]; then
        LAN_IP="$(ip -4 addr show dev "$_lan_if" 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
    fi
fi
[ -n "$LAN_IP" ] || LAN_IP="192.168.1.1"
WAN_PROTO="$(uci -q get network.wan.proto 2>/dev/null)"
[ -n "$WAN_PROTO" ] || {
    firewall_resolve_zones >/dev/null 2>&1 || true
    [ -n "${FIREWALL_WAN_NETWORK:-}" ] && WAN_PROTO="$(uci -q get "network.$FIREWALL_WAN_NETWORK.proto" 2>/dev/null)"
}
IP_RULES="$(ip rule show 2>/dev/null | wc -l)"
IP6_RULES="$(ip -6 rule show 2>/dev/null | wc -l)"
}
disc_listeners() {
LISTENERS="$TMP_DIR/listeners"
: > "$LISTENERS"
if command -v ss >/dev/null 2>&1; then
ss -lntup 2>/dev/null >> "$LISTENERS"
elif command -v netstat >/dev/null 2>&1; then
netstat -lntup 2>/dev/null >> "$LISTENERS"
fi
}
doh_slot_matches_current() {
    _slot="$1"
    _port="$2"
    _url="$3"

    [ -n "$_url" ] || return 1

    case "$_slot" in
        1|2|3|4|5|6|RU) ;;
        *) return 1 ;;
    esac

    eval "_sid=\${SLOT_${_slot}:-}"
    [ -n "$_sid" ] || return 1

    _expected_url="$(normalize_url "$(dns_url "$_sid")")"
    [ "$_url" = "$_expected_url" ] || return 1

    eval "_expected_port=\${PORT_${_slot}:-}"

    if [ -z "$_expected_port" ] && [ "$DNS_PROFILE" = hybrid ]; then
        _expected_port="$(hybrid_desired_port "$_slot")"
    fi

    [ -n "$_expected_port" ] || return 1
    [ "$_port" = "$_expected_port" ] || return 1

    return 0
}
refresh_doh_scheme_counts() {
    DOH_MATCH=0
    DOH_OTHER=0
    [ -s "${DOH_INV:-}" ] || return 0
    _used_slots="$TMP_DIR/doh-matched-slots"
    : > "$_used_slots"
    while IFS='|' read -r _idx _port _addr _running _url; do
        _matched=0
        for _slot in 1 2 3 4 5 6 RU; do
            grep -qxF "$_slot" "$_used_slots" 2>/dev/null && continue
            if doh_slot_matches_current "$_slot" "$_port" "$_url"; then
                _matched=1
                printf '%s\n' "$_slot" >> "$_used_slots"
                break
            fi
        done
        if [ "$_matched" = 1 ]; then DOH_MATCH=$((DOH_MATCH+1)); else DOH_OTHER=$((DOH_OTHER+1)); fi
    done < "$DOH_INV"
    rm -f "$_used_slots" 2>/dev/null
}
doh_selected_config_current() {
    # Idempotent Apply guard: do not stop/recreate https-dns-proxy when every
    # selected slot already points to the exact expected URL and local port.
    # A complete rebuild is still performed whenever the current UCI scheme
    # differs from the selected manager scheme.
    _expected="$(expected_managed_slots 2>/dev/null || printf 0)"
    case "$_expected" in ''|*[!0-9]*) _expected=0;; esac
    refresh_doh_scheme_counts
    [ "${DOH_TOTAL:-0}" -eq "$_expected" ] 2>/dev/null || return 1
    [ "${DOH_MATCH:-0}" -eq "$_expected" ] 2>/dev/null || return 1
    [ "${DOH_OTHER:-0}" -eq 0 ] 2>/dev/null || return 1
    return 0
}
disc_dns() {
    DNSMASQ_RUN="no"
    if /etc/init.d/dnsmasq status >/dev/null 2>&1; then
        DNSMASQ_RUN="yes"
    elif pgrep -x dnsmasq >/dev/null 2>&1; then
        DNSMASQ_RUN="yes"
    fi

    DOH_INV="$TMP_DIR/doh_inventory"
    : > "$DOH_INV"
    DOH_TOTAL=0
    DOH_MATCH=0
    DOH_OTHER=0
    
    FORCE_DNS="$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)"
    
    i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$i]" >/dev/null 2>&1; do
        p="$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].listen_port" 2>/dev/null)"
        a="$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].listen_addr" 2>/dev/null)"
        u="$(normalize_url "$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].resolver_url" 2>/dev/null)")"
        
        running="no"
        if listener_port_exists "$p"; then
            running="yes"
        elif [ -n "$p" ] && [ -s "$LISTENERS" ] && grep -qE "(:|\])$p([[:space:]]|$)" "$LISTENERS" 2>/dev/null; then
            running="yes"
        fi
        
        printf '%s|%s|%s|%s|%s\n' "$i" "$p" "$a" "$running" "$u" >> "$DOH_INV"
        i=$((i+1))
        DOH_TOTAL=$((DOH_TOTAL+1))
    done
    
    refresh_doh_scheme_counts
    
    DNS_SMARTDNS="no"; [ -x /etc/init.d/smartdns ] && DNS_SMARTDNS="yes"
    DNS_UNBOUND="no"; [ -x /etc/init.d/unbound ] && DNS_UNBOUND="yes"
    DNS_ADGUARD="no"; [ -x /etc/init.d/adguardhome ] && DNS_ADGUARD="yes"
    DNS_MOSDNS="no"; [ -x /etc/init.d/mosdns ] && DNS_MOSDNS="yes"
    DNS_SINGBOX="no"; [ -x /etc/init.d/sing-box ] && DNS_SINGBOX="yes"
}
disc_clients() {
OTHER_ZAPRET="no"; { [ -f /etc/init.d/zapret ] || [ -f /usr/bin/zms ]; } && OTHER_ZAPRET="yes"
OTHER_ZAPRET2="no"; [ -f /etc/init.d/zapret2 ] && OTHER_ZAPRET2="yes"
OTHER_NETSHIFT="no"; command -v netshift >/dev/null 2>&1 && OTHER_NETSHIFT="yes"
OTHER_SPLIFY="no"; [ -x /etc/init.d/splify ] && OTHER_SPLIFY="yes"
OTHER_MIXOMO="no"; [ -x /etc/init.d/mihomo ] && OTHER_MIXOMO="yes"
OTHER_MAGI="no"; pgrep -f magitrickle >/dev/null 2>&1 && OTHER_MAGI="yes"
OTHER_HEV="no"; pgrep -f hev-socks5-tunnel >/dev/null 2>&1 && OTHER_HEV="yes"
OTHER_AWG="no"; pgrep -f 'awg|amneziawg|wireguard' >/dev/null 2>&1 && OTHER_AWG="yes"
OTHER_TGGO="no"; pgrep -f tg-ws-proxy-go >/dev/null 2>&1 && OTHER_TGGO="yes"
OTHER_TGRS="no"; pgrep -f tg-ws-proxy-rs >/dev/null 2>&1 && OTHER_TGRS="yes"
OTHER_TGMT="no"; pgrep -f tg-ws-proxy-mtproto >/dev/null 2>&1 && OTHER_TGMT="yes"
OTHER_BYEDPI="no"; { [ -x /etc/init.d/byedpi ] || pgrep -f byedpi >/dev/null 2>&1; } && OTHER_BYEDPI="yes"
HAS_ZAPRET="$OTHER_ZAPRET"
HAS_ZAPRET2="$OTHER_ZAPRET2"
HAS_NETSHIFT="$OTHER_NETSHIFT"
HAS_SPLIFY="$OTHER_SPLIFY"
HAS_MIXOMO="$OTHER_MIXOMO"
HAS_MAGI="$OTHER_MAGI"
HAS_HEV="$OTHER_HEV"
HAS_AWG="$OTHER_AWG"
HAS_TGGO="$OTHER_TGGO"
HAS_TGRUST="$OTHER_TGRS"
HAS_TGMT="$OTHER_TGMT"
HAS_BYEDPI="$OTHER_BYEDPI"
}
# ==========================================
# ==========================================
dns_redirect_rule_matches() {
    _sec="$1"
    _src="$2"
    _proto="$3"
    _src_dport="$4"
    _dest_ip="$5"
    _dest_port="$6"
    _target="$7"
    firewall_ref_matches_zone "$(uci -q get "firewall.$_sec.src" 2>/dev/null)" "$_src" || return 1
    [ "$(uci -q get "firewall.$_sec.proto" 2>/dev/null)" = "$_proto" ] || return 1
    [ "$(uci -q get "firewall.$_sec.src_dport" 2>/dev/null)" = "$_src_dport" ] || return 1
    [ "$(uci -q get "firewall.$_sec.dest_ip" 2>/dev/null)" = "$_dest_ip" ] || return 1
    [ "$(uci -q get "firewall.$_sec.dest_port" 2>/dev/null)" = "$_dest_port" ] || return 1
    [ "$(uci -q get "firewall.$_sec.target" 2>/dev/null)" = "$_target" ] || return 1
    return 0
}
firewall_find_exact_redirect() {
    _src="$1"; _proto="$2"; _src_dport="$3"; _dest_ip="$4"; _dest_port="$5"; _target="$6"; _skip="$7"
    _secs="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=redirect$/\1/p')"
    for _sec in $_secs; do
        [ "$_sec" = "$_skip" ] && continue
        if dns_redirect_rule_matches "$_sec" "$_src" "$_proto" "$_src_dport" "$_dest_ip" "$_dest_port" "$_target"; then
            printf '%s\n' "$_sec"
            return 0
        fi
    done
    return 1
}
firewall_section_owned_redirect() {
    _sec="$1"
    _src="$2"; _proto="$3"; _src_dport="$4"; _dest_ip="$5"; _dest_port="$6"; _target="$7"
    uci -q get "firewall.$_sec" >/dev/null 2>&1 || return 1
    dns_redirect_rule_matches "$_sec" "$_src" "$_proto" "$_src_dport" "$_dest_ip" "$_dest_port" "$_target"
}
dns_redirect_conflict_uci() {
    _conflict=0
    firewall_resolve_zones >/dev/null 2>&1 || true
    [ -n "${FIREWALL_LAN_ZONE:-}" ] || { printf '0\n'; return 0; }
    _secs="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=redirect$/\1/p')"
    for _sec in $_secs; do
        [ "$(uci -q get "firewall.$_sec.disabled" 2>/dev/null)" = 1 ] && continue
        firewall_ref_matches_zone "$(uci -q get "firewall.$_sec.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" || continue
        _sd="$(uci -q get "firewall.$_sec.src_dport" 2>/dev/null)"
        printf '%s' "$_sd" | tr ' ' '\n' | grep -qxF '53' || continue
        _target="$(uci -q get "firewall.$_sec.target" 2>/dev/null)"
        case "$_target" in DNAT|dnat|REDIRECT|redirect) ;; *) continue ;; esac
        _dp="$(uci -q get "firewall.$_sec.dest_port" 2>/dev/null)"
        [ -n "$_dp" ] || continue
        case "$_dp" in 53|53-53) continue ;; esac
        # Read-only detection. Never disable or delete another package's redirect.
        _conflict=1
    done
    printf '%s\n' "$_conflict"
}

dns_path_conflict_nft() {
    [ "$SYS_FW" = fw4 ] || return 1
    command -v nft >/dev/null 2>&1 || return 1
    _out="$TMP_DIR/dns-path-conflicts-$$"
    : > "$_out" || return 1
    _lan_dev="$(uci -q get network.lan.device 2>/dev/null)"
    _lan_if="$(uci -q get network.lan.ifname 2>/dev/null)"
    nft -a list ruleset 2>/dev/null | awk -v ld="$_lan_dev" -v li="$_lan_if" '
        /^[[:space:]]*chain[[:space:]][^ {]+[[:space:]]*\{/ { c=$2; gsub(/[^A-Za-z0-9_.-]/,"",c); next }
        /iifname[[:space:]]+"[^"]+"/ && /dport[[:space:]]+53/ && /#[[:space:]]*handle[[:space:]]+[0-9]+/ {
            ok=0; if ($0 ~ /iifname[[:space:]]+"br-lan"/) ok=1
            if (ld != "" && index($0,"iifname \"" ld "\"")>0) ok=1
            if (li != "" && index($0,"iifname \"" li "\"")>0) ok=1
            if (!ok) next
            port=""
            if ($0 ~ /redirect[[:space:]]+to[[:space:]]+:[0-9]+/) {
                line=$0; sub(/^.*redirect[[:space:]]+to[[:space:]]+:/,"",line); port=line; sub(/[^0-9].*$/,"",port)
            } else if ($0 ~ /dnat[[:space:]]+to[[:space:]]+[^[:space:]]+:[0-9]+/) {
                line=$0; sub(/^.*dnat[[:space:]]+to[[:space:]]+[^:[:space:]]*:/,"",line); port=line; sub(/[^0-9].*$/,"",port)
            }
            if (port == "53" || port == "") next
            h=$0; sub(/^.*#[[:space:]]*handle[[:space:]]+/,"",h); sub(/[^0-9].*$/,"",h)
            if (c != "" && h != "") print c "|" h "|" $0
        }
    ' > "$_out"
    if [ -s "$_out" ]; then
        cat "$_out"
        rm -f "$_out"
        return 0
    fi
    rm -f "$_out"
    return 1
}
dns_path_conflict_iptables() {
    [ "$SYS_FW" = fw3 ] || return 1
    _rules=""
    if command -v iptables-save >/dev/null 2>&1; then
        _rules="$(iptables-save -t nat 2>/dev/null)" || return 1
    elif command -v iptables >/dev/null 2>&1; then
        _rules="$(iptables -t nat -S PREROUTING 2>/dev/null)" || return 1
    elif command -v fw3 >/dev/null 2>&1 || [ -x /sbin/fw3 ] || [ -x /usr/sbin/fw3 ]; then
        _rules="$(fw3 -4 -q print 2>/dev/null)" || return 1
        if [ -f /etc/firewall.user ]; then
            _rules="$_rules\n$(cat /etc/firewall.user 2>/dev/null)"
        fi
    else
        return 1
    fi
    [ -n "$_rules" ] || return 1
    _lan_dev="$(uci -q get network.lan.device 2>/dev/null)"
    _lan_if="$(uci -q get network.lan.ifname 2>/dev/null)"
    printf '%s\n' "$_rules" | awk -v ld="$_lan_dev" -v li="$_lan_if" '
        function has_input_dev(    i) {
            for (i=1; i<NF; i++) {
                if ($i=="-i" && $(i+1)!="") {
                    if ($(i+1)=="br-lan" || (ld!="" && $(i+1)==ld) || (li!="" && $(i+1)==li)) return 1
                }
            }
            return 0
        }
        /-A PREROUTING / {
            if (!has_input_dev() || $0 !~ /--dport 53([[:space:]]|$)/) next
            if ($0 ~ / -j REDIRECT([[:space:]]|$)/ && $0 ~ /--to-ports[[:space:]]+[0-9]+/) {
                if ($0 ~ /--to-ports[[:space:]]+53([[:space:]]|$)/) next
                print; found=1; next
            }
            if ($0 ~ / -j DNAT([[:space:]]|$)/ && $0 ~ /--to-destination[[:space:]]+[^[:space:]]+:[0-9]+/) {
                if ($0 ~ /--to-destination[[:space:]]+[^[:space:]]+:53([[:space:]]|$)/) next
                print; found=1
            }
        }
        END { exit(found ? 0 : 1) }
    '
}
detect_steer_dns_path() {
    STEER_DNS_ACTIVE=0
    STEER_DNS_SOURCE="none"

    # Steer is optional. If neither its init script nor its process exists,
    # the manager immediately uses its normal standalone DNS path.
    if [ -x /etc/init.d/steer ] && /etc/init.d/steer running >/dev/null 2>&1; then
        :
    elif command -v pgrep >/dev/null 2>&1 && pgrep -x steer >/dev/null 2>&1; then
        :
    else
        return 0
    fi

    _lan_dev="$(uci -q get network.lan.device 2>/dev/null)"
    _lan_if="$(uci -q get network.lan.ifname 2>/dev/null)"
    case "$SYS_FW" in
        fw4)
            # Only accept an actual LAN ingress rule. A random WAN/other-zone
            # 53 -> 5300 redirect must never make DNS Manager treat Steer as
            # the active DNS owner.
            nft -a list ruleset 2>/dev/null | awk -v ld="$_lan_dev" -v li="$_lan_if" '
                /dport[[:space:]]+53/ && /5300/ && /(redirect[[:space:]]+to|dnat[[:space:]]+to)/ {
                    ok=0
                    if ($0 ~ /iifname[[:space:]]+"br-lan"/) ok=1
                    if (ld != "" && index($0,"iifname \"" ld "\"")>0) ok=1
                    if (li != "" && index($0,"iifname \"" li "\"")>0) ok=1
                    if (ok) found=1
                }
                END { exit(found ? 0 : 1) }
            ' >/dev/null 2>&1 && {
                STEER_DNS_ACTIVE=1
                STEER_DNS_SOURCE="Steer"
            }
            ;;
        fw3)
            _rules=""
            if command -v iptables-save >/dev/null 2>&1; then
                _rules="$(iptables-save -t nat 2>/dev/null || true)"
            elif command -v iptables >/dev/null 2>&1; then
                _rules="$(iptables -t nat -S PREROUTING 2>/dev/null || true)"
            fi
            if [ -n "$_rules" ] && printf '%s\n' "$_rules" | awk -v ld="$_lan_dev" -v li="$_lan_if" '
                function has_input_dev(    i) {
                    for (i=1; i<NF; i++) {
                        if ($i=="-i" && $(i+1)!="") {
                            if ($(i+1)=="br-lan" || (ld!="" && $(i+1)==ld) || (li!="" && $(i+1)==li)) return 1
                        }
                    }
                    return 0
                }
                /-A PREROUTING / && has_input_dev() && /--dport[[:space:]]+53/ &&
                (/(REDIRECT.*--to-ports[[:space:]]+5300([[:space:]]|$))/ ||
                 /(DNAT.*:[[:space:]]*5300([[:space:]]|$))/) { found=1 }
                END { exit(found ? 0 : 1) }
            ' >/dev/null 2>&1; then
                STEER_DNS_ACTIVE=1
                STEER_DNS_SOURCE="Steer"
            fi
            ;;
    esac
    return 0
}
reload_fw() {
    if [ -x /etc/init.d/firewall ]; then
        /etc/init.d/firewall reload >/dev/null 2>&1 && return 0
        /etc/init.d/firewall restart >/dev/null 2>&1 && return 0
    fi
    case "$SYS_FW" in
        fw4)
            command -v fw4 >/dev/null 2>&1 || [ -x /sbin/fw4 ] || [ -x /usr/sbin/fw4 ] || return 1
            fw4 reload >/dev/null 2>&1 && return 0
            fw4 restart >/dev/null 2>&1 && return 0
            ;;
        fw3)
            command -v fw3 >/dev/null 2>&1 || [ -x /sbin/fw3 ] || [ -x /usr/sbin/fw3 ] || return 1
            fw3 reload >/dev/null 2>&1 && return 0
            fw3 restart >/dev/null 2>&1 && return 0
            ;;
        *)
            return 1
            ;;
    esac
    return 1
}
dns_manager_force_port() {
    _fp="$1"
    [ -n "$_fp" ] || return 1
    for _fs in 1 2 3 4 5 6 RU; do
        eval "_fport=\${PORT_${_fs}:-}"
        [ -n "$_fport" ] || continue
        [ "$_fport" = "$_fp" ] && return 0
    done
    return 1
}
force_dns_expected_src_interfaces() {
    firewall_resolve_zones >/dev/null 2>&1 || true
    _nets="$(uci -q get "firewall.${FIREWALL_LAN_ZONE}.network" 2>/dev/null || true)"
    [ -n "$_nets" ] || _nets="lan"
    printf '%s\n' $_nets
}
force_dns_list_normalize() {
    printf '%s\n' "${1:-}" | awk '{gsub(/["\047,]/," "); for(i=1;i<=NF;i++) print $i}' |
        sed '/^$/d' | sort -u | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}
force_dns_src_matches_expected() {
    _exp="$(force_dns_expected_src_interfaces | force_dns_list_normalize)"
    _cur="$(uci -q get https-dns-proxy.config.force_dns_src_interface 2>/dev/null | force_dns_list_normalize)"
    [ -n "$_exp" ] && [ "$_cur" = "$_exp" ]
}
force_dns_ports_match_expected() {
    _cur="$(uci -q get https-dns-proxy.config.force_dns_port 2>/dev/null | force_dns_list_normalize)"
    [ "$_cur" = "53 853" ]
}
steer_dns_upstream_ready() {
    [ "${STEER_DNS_ACTIVE:-0}" = 1 ] || return 1
    _sec="$(get_dnsmasq_section)"
    [ -n "$_sec" ] || return 1
    _expected="$(watchdog_expected_servers 2>/dev/null || true)"
    [ -n "$_expected" ] || return 1
    _actual="$TMP_DIR/steer-dns-actual-$"
    printf "%s\n" "$(uci -q get "dhcp.$_sec.server" 2>/dev/null)" | tr " " "\n" | sed "/^$/d" | sort -u > "$_actual"
    _want="$(sort -u "$_expected" 2>/dev/null)"
    _ok=0
    [ "$_want" = "$(cat "$_actual" 2>/dev/null)" ] && _ok=1
    rm -f "$_actual" "$_expected" 2>/dev/null || true
    [ "$_ok" = 1 ]
}
dns_dot_block_ready() {
    firewall_resolve_zones >/dev/null 2>&1 || true
    if [ "$(uci -q get "firewall.$FW_DOT_SECTION" 2>/dev/null)" = rule ] && firewall_dot_rule_matches "$FW_DOT_SECTION"; then
        return 0
    fi
    firewall_find_exact_rule_signature dot "$FW_DOT_SECTION" 853 >/dev/null 2>&1
}
ensure_dns_dot_block() {
    firewall_resolve_zones >/dev/null 2>&1 || return 1
    [ -n "${FIREWALL_LAN_ZONE:-}" ] && [ -n "${FIREWALL_WAN_ZONE:-}" ] || return 1
    if dns_dot_block_ready; then return 0; fi
    if [ "$(uci -q get "firewall.$FW_DOT_SECTION" 2>/dev/null)" = rule ]; then
        firewall_dot_rule_matches "$FW_DOT_SECTION" || return 1
        return 0
    fi
    uci set "firewall.$FW_DOT_SECTION=rule" || return 1
    uci set "firewall.$FW_DOT_SECTION.name=DNS Manager: block DoT" || return 1
    uci set "firewall.$FW_DOT_SECTION.src=$FIREWALL_LAN_ZONE" || return 1
    uci set "firewall.$FW_DOT_SECTION.dest=$FIREWALL_WAN_ZONE" || return 1
    uci set "firewall.$FW_DOT_SECTION.proto=tcp udp" || return 1
    uci set "firewall.$FW_DOT_SECTION.dest_port=853" || return 1
    uci set "firewall.$FW_DOT_SECTION.target=REJECT" || return 1
    uci commit firewall || return 1
    reload_fw || return 1
    return 0
}
remove_dns_dot_block() {
    firewall_resolve_zones >/dev/null 2>&1 || true
    _sec=""
    if [ "$(uci -q get "firewall.$FW_DOT_SECTION" 2>/dev/null)" = rule ] && firewall_dot_rule_matches "$FW_DOT_SECTION"; then
        _sec="$FW_DOT_SECTION"
    else
        _sec="$(firewall_find_exact_rule_signature dot "$FW_DOT_SECTION" 853 2>/dev/null || true)"
    fi
    if [ -n "$_sec" ]; then
        uci -q delete "firewall.$_sec" || return 1
        uci commit firewall || return 1
        reload_fw || return 1
    fi
    return 0
}
# Read-only discovery of the actual LAN DNS interception path. This is used
# to separate DNS Manager from Zapret/other external forced-DNS without
# consulting ownership files.
detect_forced_dns_path() {
    FORCED_DNS_ACTIVE=0
    FORCED_DNS_EXTERNAL=0
    FORCED_DNS_SOURCE="none"
    FORCED_DNS_TARGETS=""
    _manager_force_cfg=0
    _external=0
    _zapret=0
    _steer=0
    detect_steer_dns_path >/dev/null 2>&1 || true
    [ "${STEER_DNS_ACTIVE:-0}" = 1 ] && _steer=1

    [ "${FORCE_DOH:-0}" = 1 ] &&
        [ "$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)" = 1 ] &&
        [ "$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null)" = 1 ] &&
        _manager_force_cfg=1

    # UCI redirect/DNAT rules. We inspect every real rule; section names and
    # ownership registries are deliberately ignored as authority.
    firewall_resolve_zones >/dev/null 2>&1 || true
    _secs="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=redirect$/\1/p')"
    for _sec in $_secs; do
        [ "$(uci -q get "firewall.$_sec.disabled" 2>/dev/null)" = 1 ] && continue
        firewall_ref_matches_zone "$(uci -q get "firewall.$_sec.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" || continue
        _sd="$(uci -q get "firewall.$_sec.src_dport" 2>/dev/null)"
        printf '%s\n' "$_sd" | tr ' ' '\n' | grep -qxF '53' || continue
        _target="$(uci -q get "firewall.$_sec.target" 2>/dev/null)"
        case "$_target" in DNAT|dnat|REDIRECT|redirect) ;; *) continue ;; esac
        _dp="$(uci -q get "firewall.$_sec.dest_port" 2>/dev/null)"
        [ -n "$_dp" ] || continue
        case "$_dp" in 53|53-53) continue ;; esac
        FORCED_DNS_ACTIVE=1
        case "$FORCED_DNS_TARGETS" in *"|$_dp|"*|"$_dp"|*) ;; esac
        FORCED_DNS_TARGETS="${FORCED_DNS_TARGETS}${_dp} "
        if [ "$_steer" = 1 ] && [ "$_dp" = 5300 ]; then
            :
        elif dns_manager_force_port "$_dp" && [ "$_manager_force_cfg" = 1 ]; then
            :
        else
            _external=1
        fi
    done

    # Runtime fw4/fw3 rules catch generated rules that do not exist as UCI
    # sections. Existing helpers return only LAN:53 interceptions to another
    # local port.
    case "$SYS_FW" in
        fw4)
            _rt="$(dns_path_conflict_nft 2>/dev/null || true)"
            while IFS='|' read -r _chain _handle _line; do
                [ -n "$_line" ] || continue
                _rp="$(printf '%s\n' "$_line" | sed -n 's/.*redirect[[:space:]]\+to[[:space:]]\+:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
                [ -n "$_rp" ] || continue
                FORCED_DNS_ACTIVE=1
                FORCED_DNS_TARGETS="${FORCED_DNS_TARGETS}${_rp} "
                if [ "$_steer" = 1 ] && [ "$_rp" = 5300 ]; then
                    :
                elif dns_manager_force_port "$_rp" && [ "$_manager_force_cfg" = 1 ]; then
                    :
                else
                    _external=1
                fi
            done <<EOF_FORCE_NFT
$_rt
EOF_FORCE_NFT
            ;;
        fw3)
            _rt="$(dns_path_conflict_iptables 2>/dev/null || true)"
            while IFS= read -r _line; do
                [ -n "$_line" ] || continue
                _rp="$(printf '%s\n' "$_line" | sed -n 's/.*--to-ports[[:space:]]\+\([0-9][0-9]*\).*/\1/p; s/.*--to-destination[[:space:]]\+[^[:space:]]*:\([0-9][0-9]*\).*/\1/p' | head -n1)"
                [ -n "$_rp" ] || continue
                FORCED_DNS_ACTIVE=1
                FORCED_DNS_TARGETS="${FORCED_DNS_TARGETS}${_rp} "
                if [ "$_steer" = 1 ] && [ "$_rp" = 5300 ]; then
                    :
                elif dns_manager_force_port "$_rp" && [ "$_manager_force_cfg" = 1 ]; then
                    :
                else
                    _external=1
                fi
            done <<EOF_FORCE_IPT
$_rt
EOF_FORCE_IPT
            ;;
    esac

    # Attribute an already detected external path to Zapret only from the
    # actual running Zapret process, never from a firewall section/chain name.
    # This keeps source reporting fact-based and independent of ownership files.
    if [ "$_external" = 1 ] && type third_party_running >/dev/null 2>&1; then
        third_party_running zapret >/dev/null 2>&1 && _zapret=1
        third_party_running zapret2 >/dev/null 2>&1 && _zapret=1
    fi


    if [ "$_external" = 1 ]; then
        FORCED_DNS_EXTERNAL=1
        if [ "$_zapret" = 1 ]; then
            FORCED_DNS_SOURCE="Zapret / внешний"
        else
            FORCED_DNS_SOURCE="внешний сервис"
        fi
    elif [ "$_steer" = 1 ]; then
        FORCED_DNS_ACTIVE=1
        if [ "$_manager_force_cfg" = 1 ]; then
            FORCED_DNS_SOURCE="Steer + DNS Manager"
        else
            FORCED_DNS_SOURCE="Steer"
        fi
    elif [ "$_manager_force_cfg" = 1 ]; then
        FORCED_DNS_ACTIVE=1
        FORCED_DNS_SOURCE="DNS Manager"
    fi

    FORCED_DNS_TARGETS="$(printf '%s\n' "$FORCED_DNS_TARGETS" | tr ' ' '\n' | sed '/^$/d' | sort -n -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    return 0
}

prepare_dns_path() {
    firewall_resolve_zones >/dev/null 2>&1 || true
    return 0
}
disc_firewall() {
    [ "$(uci -q get firewall.@defaults[0].flow_offloading 2>/dev/null)" = 1 ] && FLOW_OFFLOAD="yes" || FLOW_OFFLOAD="no"
    NFT_ACTIVE="no"
    IPTABLES_ACTIVE="no"
    if [ "$SYS_FW" = fw4 ] && command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then
        NFT_ACTIVE="yes"
    elif [ "$SYS_FW" = fw3 ]; then
        IPTABLES_ACTIVE="yes"
    fi
    DNS_PATH_CONFLICT="no"
    detect_forced_dns_path >/dev/null 2>&1 || true
    [ "${FORCED_DNS_EXTERNAL:-0}" = 1 ] && DNS_PATH_CONFLICT="yes"
}
run_discovery() {
init_dirs
disc_system
disc_network
disc_listeners
disc_dns
disc_clients
firewall_resolve_zones
disc_firewall
log_tx "DISCOVER" "router" "READ" "OK" "OpenWrt=$SYS_OWRT;fw=$SYS_FW;fw_source=$FIREWALL_DETECT_SOURCE;dns=$DNSMASQ_RUN;doh=$DOH_TOTAL;watchdog_backend=${WATCHDOG_BACKEND:-procd};legacy_cron=$WATCHDOG_CRON_AVAILABLE;crond=$WATCHDOG_CRON_RUNNING;cron_ambiguous=$WATCHDOG_CRON_AMBIGUOUS"
}
refresh_runtime_capabilities() {
    disc_system
    disc_network
    disc_listeners
    disc_dns
}
# ==========================================
# ==========================================
dns_field() {
    _target_id="$1"
    _f_idx="$2"
    while IFS='|' read -r _c1 _c2 _c3 _c4 _c5 _c6 _c7; do
        case "$_c1" in ''|\#*) continue ;; esac
        [ "$_c1" = "$_target_id" ] || continue
        case "$_f_idx" in
            2) printf '%s' "$_c2" ;;
            4) printf '%s' "$_c4" ;;
            5) printf '%s' "$_c5" ;;
            *) return 1 ;;
        esac
        return 0
    done < "$DNS_CATALOG"
    return 1
}
dns_name() { dns_field "$1" 4 | sed 's/\\\\\././g'; }
dns_url() { dns_field "$1" 5; }
dns_cat() { dns_field "$1" 2; }
count_dns() { grep -v '^#' "$DNS_CATALOG" 2>/dev/null | grep -c '|'; }
dns_catalog_version() { sed -n 's/^# DNSCATVER=//p' "$DNS_CATALOG" 2>/dev/null | head -n1; }
ntp_name() { awk -F'|' -v id="$1" '$1==id{print $3;exit}' "$NTP_CATALOG"; }
ntp_ipv4() { awk -F'|' -v id="$1" '$1==id{print $4;exit}' "$NTP_CATALOG"; }
ntp_leap() { awk -F'|' -v id="$1" '$1==id{print $7;exit}' "$NTP_CATALOG"; }
# ==========================================
# ==========================================
# ==========================================
normalize_url() {
_u="$1"
_u="$(printf '%s' "$_u" | sed 's/[[:space:]]//g; s:/*$::')"
printf '%s' "$_u"
}
slot_set() {
    case "$1" in
        1) SLOT_1="$2" ;;
        2) SLOT_2="$2" ;;
        3) SLOT_3="$2" ;;
        4) SLOT_4="$2" ;;
        5) SLOT_5="$2" ;;
        6) SLOT_6="$2" ;;
        RU) SLOT_RU="$2" ;;
        *) return 1 ;;
    esac
}
slot_cat_set() {
    case "$1" in
        1) SLOT_1_CAT="$2" ;;
        2) SLOT_2_CAT="$2" ;;
        3) SLOT_3_CAT="$2" ;;
        4) SLOT_4_CAT="$2" ;;
        5) SLOT_5_CAT="$2" ;;
        6) SLOT_6_CAT="$2" ;;
        RU) SLOT_RU_CAT="$2" ;;
        *) return 1 ;;
    esac
}
port_set() {
    case "$1" in
        1) PORT_1="$2" ;;
        2) PORT_2="$2" ;;
        3) PORT_3="$2" ;;
        4) PORT_4="$2" ;;
        5) PORT_5="$2" ;;
        6) PORT_6="$2" ;;
        RU) PORT_RU="$2" ;;
        *) return 1 ;;
    esac
}
quick_pref_set() {
    case "$1" in
        1) QUICK_PREF_1="$2" ;;
        2) QUICK_PREF_2="$2" ;;
        3) QUICK_PREF_3="$2" ;;
        4) QUICK_PREF_4="$2" ;;
        5) QUICK_PREF_5="$2" ;;
        6) QUICK_PREF_6="$2" ;;
        *) return 1 ;;
    esac
}
file_hash() {
if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" 2>/dev/null | awk '{print $1}'
elif command -v md5sum >/dev/null 2>&1; then md5sum "$1" 2>/dev/null | awk '{print $1}'
elif command -v cksum >/dev/null 2>&1; then cksum "$1" 2>/dev/null | awk '{print $1":"$2}'
else printf ''
fi
}
# ==========================================
# ==========================================
resolve_host() {
host="$1"
for bs in $(printf '%s' "$BOOTSTRAP_DNS" | tr ',' ' '); do
if [ "$HAS_DIG" = yes ]; then
ipx="$(dig +short "@$bs" "$host" A +time=2 +tries=1 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print;exit}')"
elif command -v nslookup >/dev/null 2>&1; then
ipx="$(nslookup "$host" "$bs" 2>/dev/null | awk '/^Address[ 0-9]*: / {print $NF}' | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print;exit}')"
else
ipx=""
fi
[ -n "$ipx" ] && { echo "$ipx"; return 0; }
done
return 1
}
resolve_host_fallback() {
host="$1"
ipx=""
if [ "$HAS_DIG" = yes ]; then
    ipx="$(dig +short "$host" A +time=3 +tries=1 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print;exit}')"
    [ -n "$ipx" ] || ipx="$(dig +short "$host" A +tcp +time=3 +tries=1 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print;exit}')"
fi
if [ -z "$ipx" ] && command -v nslookup >/dev/null 2>&1; then
    ipx="$(nslookup "$host" 2>/dev/null | awk '/^Address[ 0-9]*: / {print $NF}' | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print;exit}')"
fi
[ -n "$ipx" ] && { echo "$ipx"; return 0; }
return 1
}
# ==========================================
# ==========================================
# ==========================================
validate_dns_message() {
    _file="$1"
    [ -s "$_file" ] || return 1
    _n="$(wc -c < "$_file" 2>/dev/null | tr -d " ")"
    case "$_n" in ''|*[!0-9]*) return 1;; esac
    [ "$_n" -ge 12 ] || return 1
    return 0
}
test_one_dns() {
id="$1"; url="$(normalize_url "$(dns_url "$id")")"; name="$(dns_name "$id")"; cat="$(dns_cat "$id")"
host="$(url_host "$url")"
port="$(url_port "$url")"
q="$TMP_DIR/dns_query.bin"; body="$TMP_DIR/body.$id"; hdr="$TMP_DIR/h.$id"
: > "$body"; : > "$hdr"
# dns_query.bin is a single shared immutable payload created by test_dns_catalog
# before workers are forked. A worker must never create or remove it.
[ -s "$q" ] || { printf '%s\n' "$id|$cat|$name|-1|INTERNAL_TEST_QUERY_MISSING" > "$TMP_DIR/t.$id"; rm -f "$body" "$hdr"; return; }
_ips=""
# Resolve the DoH endpoint through the trusted bootstrap DNS set first.
# Local/system DNS is only a fallback so a poisoned provider resolver cannot
# make a valid DoH endpoint fail the TLS/HTTP test.
_one="$(resolve_host "$host")"
[ -n "$_one" ] && _ips="$_one"
if [ -z "$_ips" ] && [ "$HAS_DIG" = yes ]; then
    _chunk="$(dig +short +time=3 +tries=1 "$host" A 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print}' | head -n 4)"
    [ -n "$_chunk" ] && _ips="$_chunk"
fi
[ -n "$_ips" ] || { _one="$(resolve_host_fallback "$host")"; [ -n "$_one" ] && _ips="$_one"; }
[ -n "$_ips" ] || { printf '%s|%s|%s|-1|BOOTSTRAP_FAIL\n' "$id" "$cat" "$name" > "$TMP_DIR/t.$id"; rm -f "$body" "$hdr"; return; }
_best_ms=-1; st=CONNECTION_ERROR
while IFS= read -r ipx; do
    [ -n "$ipx" ] || continue
    : > "$body"; : > "$hdr"
    result="$(curl -sS -o "$body" -D "$hdr" -w '%{http_code}|%{time_total}|%{errormsg}'  --connect-timeout 3 --max-time 6 --resolve "$host:$port:$ipx"  -H 'Content-Type: application/dns-message' -H 'Accept: application/dns-message'  --data-binary "@$q" "$url" 2>/dev/null)"
    code="${result%%|*}"; rest="${result#*|}"; tim="${rest%%|*}"; err="${rest#*|}"
    [ -z "$code" ] && code="000"
    bytes="$(wc -c < "$body" 2>/dev/null | tr -d ' ')"; [ -n "$bytes" ] || bytes=0
    ctype="$(awk -F': *' 'tolower($1)=="content-type"{print tolower($2)}' "$hdr" 2>/dev/null | tail -n1 | tr -d '\r')"
    case "$tim" in ''|0) ms=-1;; *) ms="$(awk -v t="$tim" 'BEGIN{v=t*1000; if(v<1)v=1; printf "%.0f", v}')";; esac
    case "$code" in
    200)
        case "$ctype" in *application/dns-message*) ct_ok=yes;; *) ct_ok=no;; esac
        if [ "$ct_ok" = yes ] && validate_dns_message "$body"; then
            if [ "$_best_ms" -lt 0 ] || { [ "$ms" -ge 0 ] && [ "$ms" -lt "$_best_ms" ]; }; then _best_ms="$ms"; fi
            st=OK
        else st=BAD_DOH_RESPONSE; fi ;;
    000)
        elc="$(printf '%s' "$err" | tr '[:upper:]' '[:lower:]')"
        case "$elc" in
        *timed*|*timeout*) st=CURL_TIMEOUT;;
        *ssl*|*tls*|*certificate*|*schannel*) st=TLS_ERROR;;
        *could\ not\ resolve*|*resolve\ host*|*name\ or\ service*) st=DNS_ERROR;;
        *connection\ refused*|*failed\ to\ connect*|*connection\ reset*|*could\ not\ connect*) st=CONNECTION_ERROR;;
        *) st=CURL_ERROR;; esac ;;
    4??|5??) st="HTTP_$code" ;;
    *) st="HTTP_$code" ;;
    esac
    [ "$st" = OK ] && break
done <<EOF_IPS
$_ips
EOF_IPS
[ "$st" = OK ] && ms="$_best_ms" || ms=-1
printf '%s|%s|%s|%s|%s\n' "$id" "$cat" "$name" "$ms" "$st" > "$TMP_DIR/t.$id"
rm -f "$body" "$hdr"
[ "$st" = OK ] && return 0
return 1
}
# ==========================================
# ==========================================
test_dns_catalog() (
    # Full catalog results live only in /var/run (tmpfs). This subshell also
    # keeps the RAM-only logging mode local to the catalog test operation.
    DNS_TEST_RAM_ONLY=1
    [ "$HAS_CURL" = yes ] || { warn_msg "Полную проверку DNS нельзя выполнить: curl не установлен."; return 1; }
    acquire_test_lock || { warn_msg "Полная проверка DNS уже выполняется другим процессом. Текущая проверка отменена."; return 1; }
    rm -f "$TMP_DIR/t."* "$TMP_DIR/q."* "$TMP_DIR/dns_query.bin" "$TMP_DIR/body."* "$TMP_DIR/h."* 2>/dev/null
    # Create the immutable shared DNS wire query before launching any parallel
    # test workers. This removes the worker-to-worker race on dns_query.bin.
    q="$TMP_DIR/dns_query.bin"
    printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$q" 2>/dev/null || {
        release_test_lock
        warn_msg "Не удалось создать общий DNS-тестовый пакет."
        return 1
    }
    total="$(count_dns)"
    [ "$total" -gt 0 ] || { release_test_lock; warn_msg "Каталог DNS пуст."; return 1; }
    printf "${C_WHITE}Проверяю %s DNS-серверов. Это может занять до 5 минут...${C_NC}\n" "$total"
    test_progress() {
        _done=0
        _ok=0
        for _f in "$TMP_DIR"/t.*; do
            [ -f "$_f" ] || continue
            _done=$((_done+1))
            grep -q '|OK$' "$_f" 2>/dev/null && _ok=$((_ok+1))
        done
        _bad=$((_done-_ok))
        printf "  ${C_CYAN}Промежуточный результат:${C_NC} проверено %s из %s | работают %s | ошибки %s\n" "$_done" "$total" "$_ok" "$_bad"
    }
    n=0
    batch="${TEST_BATCH:-$TEST_BATCH_DEFAULT}"
    case "$batch" in ''|*[!0-9]*) batch="$TEST_BATCH_DEFAULT";; esac
    [ "$batch" -ge 1 ] 2>/dev/null || batch=1
    [ "$batch" -le 6 ] 2>/dev/null || batch=6
    if [ -r /proc/meminfo ]; then
        _mem_avail="$(awk '/^MemAvailable:/{print $2; exit}' /proc/meminfo 2>/dev/null)"
        case "$_mem_avail" in ''|*[!0-9]*) ;; *)
            [ "$_mem_avail" -lt 16384 ] && batch=1
            [ "$_mem_avail" -ge 16384 ] && [ "$_mem_avail" -lt 32768 ] && [ "$batch" -gt 2 ] && batch=2
            ;;
        esac
    fi
    _load="$(awk '{print $1; exit}' /proc/loadavg 2>/dev/null)"
    _cpu="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
    case "$_cpu" in ''|*[!0-9]*) _cpu=1;; esac
    _load10="$(awk -v x="$_load" 'BEGIN{printf "%.0f", x*10}' 2>/dev/null)"
    case "$_load10" in ''|*[!0-9]*) ;; *) [ "$_load10" -gt $((_cpu*20)) ] && batch=1;; esac
    while IFS='|' read -r id _rest; do
        case "$id" in ''|\#*) continue;; esac
        (trap - EXIT; test_one_dns "$id") &
        n=$((n+1))
        if [ $((n % batch)) -eq 0 ]; then
            wait
            if [ $((n % TEST_PROGRESS_EVERY)) -eq 0 ] || [ "$n" -eq "$total" ]; then
                test_progress
            fi
        fi
    done < "$DNS_CATALOG"
    wait
    test_progress

    _result_tmp="$TMP_DIR/test-results-$$"
    _meta_tmp="$TMP_DIR/test-results-meta-$$"
    rm -f "$_result_tmp" "$_meta_tmp" 2>/dev/null
    cat "$TMP_DIR"/t.* > "$_result_tmp" 2>/dev/null || {
        release_test_lock
        warn_msg "Не удалось собрать результаты полной проверки DNS."
        return 1
    }
    _result_count="$(wc -l < "$_result_tmp" 2>/dev/null | tr -d ' ')"
    case "$_result_count" in ''|*[!0-9]*) _result_count=0;; esac
    [ "$_result_count" -eq "$total" ] || {
        rm -f "$_result_tmp" "$_meta_tmp" 2>/dev/null
        release_test_lock
        warn_msg "Полная проверка завершилась с неполным набором результатов: $_result_count из $total."
        return 1
    }
    _catalog_version="$(dns_catalog_version)"
    [ -n "$_catalog_version" ] || {
        rm -f "$_result_tmp" "$_meta_tmp" 2>/dev/null
        release_test_lock
        warn_msg "Каталог DNS не содержит версии DNSCATVER. Результат не принят watchdog."
        return 1
    }
    _catalog_hash="$(file_hash "$DNS_CATALOG")"
    [ -n "$_catalog_hash" ] || {
        rm -f "$_result_tmp" "$_meta_tmp" 2>/dev/null
        release_test_lock
        warn_msg "Не удалось вычислить хеш каталога DNS. Результат не сохранён."
        return 1
    }
    {
        printf 'timestamp=%s\n' "$(date +%s)"
        printf 'catalog_version=%s\n' "$_catalog_version"
        printf 'catalog_count=%s\n' "$total"
        printf 'catalog_hash=%s\n' "$_catalog_hash"
    } > "$_meta_tmp" 2>/dev/null || {
        rm -f "$_result_tmp" "$_meta_tmp" 2>/dev/null
        release_test_lock
        warn_msg "Не удалось создать метаданные полной проверки DNS."
        return 1
    }
    [ -s "$_meta_tmp" ] || {
        rm -f "$_result_tmp" "$_meta_tmp" 2>/dev/null
        release_test_lock
        warn_msg "Метаданные полной проверки DNS пусты."
        return 1
    }
    mv "$_result_tmp" "$TEST_RESULTS" 2>/dev/null || {
        rm -f "$_result_tmp" "$_meta_tmp" 2>/dev/null
        release_test_lock
        warn_msg "Не удалось сохранить результаты полной проверки DNS."
        return 1
    }
    mv "$_meta_tmp" "$TEST_RESULTS_META" 2>/dev/null || {
        rm -f "$_meta_tmp" 2>/dev/null
        rm -f "$TEST_RESULTS" 2>/dev/null
        release_test_lock
        warn_msg "Не удалось сохранить метаданные полной проверки DNS."
        return 1
    }
    okn="$(awk -F'|' 'NF>=5 && $5=="OK"{n++} END{print n+0}' "$TEST_RESULTS" 2>/dev/null)"
    failn=$((total-okn))
    printf "${C_GREEN}✓ Успешно: %s${C_NC} | ${C_YELLOW}Проблемные: %s${C_NC} | Всего: %s\n" "$okn" "$failn" "$total"
    printf "${C_CYAN}Время ответа — сколько занял полный запрос к DNS. Чем меньше число, тем быстрее сервер. Знак «—» означает, что ответ не получен.${C_NC}\n"
    if [ "$okn" -eq 0 ]; then
        warn_msg "Не удалось проверить ни одного DNS-сервера. Настройки не изменены."
        log_tx "TEST" "dns-catalog" "RUN" "FAIL" "ok=$okn,total=$total"
        release_test_lock
        return 1
    fi
    log_tx "TEST" "dns-catalog" "RUN" "OK" "ok=$okn,total=$total"
    rm -f "$TMP_DIR"/t.* "$TMP_DIR"/q.* "$TMP_DIR"/body.* "$TMP_DIR"/h.* 2>/dev/null || true
release_test_lock
return 0
)

# ==========================================
# ==========================================
show_best_category() {
cat="$1"; limit="$2"
awk -F'|' -v c="$cat" '$2==c && $5=="OK"{print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n | head -n "$limit"
}
# ==========================================
# ==========================================
HYBRID_PORT_1=5053
HYBRID_PORT_2=5054
HYBRID_PORT_3=5055
HYBRID_PORT_4=5056
HYBRID_PORT_5=5057
HYBRID_PORT_6=5058
HYBRID_PORT_RU=5059
# ==========================================
# ==========================================
hybrid_set_defaults() {
SLOT_1="mafioznik"
SLOT_2="comss_bypass"
SLOT_3="astracat"
SLOT_4="malw_link"
SLOT_5="comss_ru"
SLOT_6="vppay"
SLOT_RU="yandex_ru"
SLOT_1_CAT="bypass"
SLOT_2_CAT="bypass"
SLOT_3_CAT="bypass"
SLOT_4_CAT="bypass"
SLOT_5_CAT="bypass"
SLOT_6_CAT="bypass"
SLOT_RU_CAT="regional"
PORT_1="$HYBRID_PORT_1"
PORT_2="$HYBRID_PORT_2"
PORT_3="$HYBRID_PORT_3"
PORT_4="$HYBRID_PORT_4"
PORT_5="$HYBRID_PORT_5"
PORT_6="$HYBRID_PORT_6"
PORT_RU="$HYBRID_PORT_RU"
DNS_PROFILE="hybrid"
TLD_RU_ENABLED=1
BALANCER_ENABLED=1
TLD_SPLIT=1
}
hybrid_desired_port() {
    case "$1" in
        1) printf '%s' "$HYBRID_PORT_1";;
        2) printf '%s' "$HYBRID_PORT_2";;
        3) printf '%s' "$HYBRID_PORT_3";;
        4) printf '%s' "$HYBRID_PORT_4";;
        5) printf '%s' "$HYBRID_PORT_5";;
        6) printf '%s' "$HYBRID_PORT_6";;
        RU) printf '%s' "$HYBRID_PORT_RU";;
        *) printf '';;
    esac
}
hybrid_prepare_selection() {
if [ -z "$SLOT_1$SLOT_2$SLOT_3$SLOT_4$SLOT_5$SLOT_6$SLOT_RU" ]; then
hybrid_set_defaults
else
DNS_PROFILE="hybrid"
TLD_RU_ENABLED=1
BALANCER_ENABLED=1
PORT_1="$HYBRID_PORT_1"; PORT_2="$HYBRID_PORT_2"; PORT_3="$HYBRID_PORT_3"
PORT_4="$HYBRID_PORT_4"; PORT_5="$HYBRID_PORT_5"; PORT_6="$HYBRID_PORT_6"
[ -n "$SLOT_RU" ] && PORT_RU="$HYBRID_PORT_RU"
fi
if [ "${HYBRID_AUTO_REPAIR:-0}" = 1 ]; then
ensure_test_results_fresh || return 1
: > "$TMP_DIR/hybrid-used"
for _s in 1 2 3 4 5 6; do
eval "_id=\${SLOT_$_s}"
_ok="$(awk -F'|' -v id="$_id" '$1==id && $5=="OK"{print "yes";exit}' "$TEST_RESULTS" 2>/dev/null)"
if [ "$_ok" != yes ]; then
_replacement=""
while IFS='|' read -r _rid _rcat _rname _rms _rst; do
[ "$_rst" = OK ] || continue
[ "$_rcat" = bypass ] || continue
grep -qxF "$_rid" "$TMP_DIR/hybrid-used" 2>/dev/null && continue
_replacement="$_rid"
break
done <<EOF_HYB
$(sort -t'|' -k4,4n "$TEST_RESULTS" 2>/dev/null)
EOF_HYB
if [ -n "$_replacement" ]; then
slot_set "$_s" "$_replacement" || return 1
printf "${C_YELLOW}⚠ %s не прошёл тест → резерв %s.${C_NC}\n" "$(dns_name "$_id")" "$(dns_name "$_replacement")"
_id="$_replacement"
else
warn_msg "Для Hybrid-слота $_s нет проверенного резерва."
slot_set "$_s" "" || return 1
fi
fi
[ -n "$_id" ] && printf '%s\n' "$_id" >> "$TMP_DIR/hybrid-used"
done
_yok="$(awk -F'|' -v id="$SLOT_RU" '$1==id && $5=="OK"{print "yes";exit}' "$TEST_RESULTS" 2>/dev/null)"
if [ "$_yok" != yes ]; then
warn_msg "Yandex RU сейчас не прошёл тест. RU-маршрут не применяется автоматически."
SLOT_RU=""
fi
fi
sync_regional_dns_state
PORT_1="$HYBRID_PORT_1"; PORT_2="$HYBRID_PORT_2"; PORT_3="$HYBRID_PORT_3"
PORT_4="$HYBRID_PORT_4"; PORT_5="$HYBRID_PORT_5"; PORT_6="$HYBRID_PORT_6"
[ -n "$SLOT_RU" ] && PORT_RU="$HYBRID_PORT_RU"
}
# ==========================================
# ==========================================
show_hybrid_profile() {
while :; do
menu_header "ГИБРИДНЫЙ DNS"
menu_section "ОБЩИЕ DNS-СЕРВЕРЫ"
printf "${C_WHITE}  %-8s %-34s %s${C_NC}\n" "ПОРТ" "DNS" "РОЛЬ"
printf "  ──────────────────────────────────────────────────────────\n"
for _s in 1 2 3 4 5 6; do
eval "_id=\${SLOT_$_s}"
_p="$(hybrid_desired_port "$_s")"
[ -n "$_id" ] && printf "  ${C_YELLOW}%-8s${C_NC} %-34s общий\n" "$_p" "$(dns_name "$_id")"
done
if [ -n "$SLOT_RU" ]; then
printf "\n${C_SECTION}РЕГИОНАЛЬНЫЙ МАРШРУТ${C_NC}\n"
printf "  ${C_YELLOW}%-8s${C_NC} %-34s .ru / .su / .рф\n" "$HYBRID_PORT_RU" "$(dns_name "$SLOT_RU")"
fi
printf "\n${C_SECTION}РЕЖИМ${C_NC}\n"
printf "  ${C_WHITE}Общий DNS:${C_NC} 6 серверов работают одновременно.\n"
printf "  ${C_WHITE}RU:${C_NC}       .ru / .su / .рф → отдельный DNS.\n"
menu_section "ДЕЙСТВИЯ"
menu_item "[1]" "Автоматически настроить"
menu_item "[2]" "Проверить DNS"
menu_item "[3]" "Изменить слоты"
menu_back
menu_prompt
safe_read _c
case "$_c" in
1)
if [ ! -s "$TEST_RESULTS" ]; then test_dns_catalog; fi
HYBRID_AUTO_REPAIR=1
hybrid_prepare_selection
HYBRID_AUTO_REPAIR=0
ok_msg "Гибридный DNS подготовлен."
apply_settings
pause
;;
2) test_dns_catalog; show_tests;;
3) menu_slots;;
'') return;;
*) warn_msg "Неверный пункт."; pause;;
esac
done
}
ntp_servers_for_profile() {
case "$1" in
cf_ip) echo "162.159.200.1 162.159.200.123";;
nist_ip) echo "129.6.15.28 129.6.15.29 129.6.15.30 129.6.15.27 129.6.15.26";;
google_ip) echo "216.239.35.0 216.239.35.4 216.239.35.8 216.239.35.12";;
vniiftri_moscow) echo "89.109.251.21 89.109.251.22 89.109.251.23 89.109.251.24 89.109.251.25";;
vniiftri_all) echo "89.109.251.21 89.109.251.22 89.109.251.23 89.109.251.24 89.109.251.25 46.254.241.74 46.254.241.75 212.19.6.218 212.19.17.26 80.242.83.227 80.242.83.228 91.189.237.182";;
*) echo "";;
esac
}
apply_ntp_ip_fallback() {
    servers="$(grep -v '^#' "$NTP_CATALOG" 2>/dev/null | grep "^${NTP_PRESET}|" | head -1 | cut -d'|' -f4)"
    if [ -z "$servers" ]; then
        servers="$(ntp_servers_for_profile "$NTP_PRESET")"
        [ -n "$servers" ] && log_msg "NTP: локальный catalog для '$NTP_PRESET' отсутствует; использую встроенный профиль."
    fi
    [ -n "$servers" ] || { warn_msg "NTP-профиль '$NTP_PRESET' не найден ни в каталоге, ни во встроенных профилях."; return 1; }
    [ -n "$(uci -q get system.ntp 2>/dev/null)" ] || uci -q set system.ntp=timeserver || return 1

    uci -q delete system.ntp.server || true
    for ipx in $servers; do
        uci add_list system.ntp.server="$ipx" || return 1
    done
    uci set system.ntp.enabled='1' || return 1
    uci set system.ntp.use_dhcp='0' || return 1
    uci commit system || return 1
    /etc/init.d/sysntpd restart >/dev/null 2>&1 || return 1
    log_tx "APPLY" "NTP" "SERVER_PROFILE" "OK" "profile=$NTP_PRESET;servers=$servers"
    ok_msg "NTP: выбран профиль '$NTP_PRESET'. Источники времени роутера установлены точно по выбранному набору."
}
apply_ntp_host_ips() {
    [ "${NTP_IP_FALLBACK:-0}" = 1 ] || return 0
    [ -n "$(uci -q get system.ntp 2>/dev/null)" ] || return 0
    _ntp_servers="$(uci -q get system.ntp.server 2>/dev/null)"
    [ -n "$_ntp_servers" ] || return 0
    _ntp_changed=0
    _ntp_all="$_ntp_servers"
    for _ntp_host in $_ntp_servers; do
        printf '%s' "$_ntp_host" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' && continue
        case "$_ntp_host" in
            *[!A-Za-z0-9._-]*|*.*.*.*.*) continue ;;
            *.*) ;;
            *) continue ;;
        esac
        _ntp_ip="$(resolve_host "$_ntp_host" 2>/dev/null || true)"
        [ -n "$_ntp_ip" ] || _ntp_ip="$(resolve_host_fallback "$_ntp_host" 2>/dev/null || true)"
        [ -n "$_ntp_ip" ] || continue
        _exists=0
        for _cur_ntp in $_ntp_all; do
            [ "$_cur_ntp" = "$_ntp_ip" ] && _exists=1
        done
        [ "$_exists" = 1 ] && continue
        uci add_list system.ntp.server="$_ntp_ip" || return 1
        _ntp_all="$_ntp_all $_ntp_ip"
        _ntp_changed=1
    done
    if [ "$_ntp_changed" = 1 ]; then
        uci set system.ntp.enabled='1' || return 1
        uci set system.ntp.use_dhcp='0' || return 1
        uci commit system || return 1
        log_tx "APPLY" "NTP" "ADD_IP" "OK" "system.ntp.server hostname-to-ip"
    fi
    return 0
}
# ==========================================
# ==========================================
menu_ntp() {
menu_header "СЕРВЕРЫ ТОЧНОГО ВРЕМЕНИ"
_cur_ntp="$(uci -q get system.ntp.server 2>/dev/null)"
printf "${C_YELLOW}${C_BOLD}Текущие серверы времени:${C_NC}\n"
if [ -n "$_cur_ntp" ]; then
for _s in $_cur_ntp; do
printf "  ${C_CYAN}•${C_NC} %s\n" "$_s"
done
else
printf "  ${C_YELLOW}(не настроены)${C_NC}\n"
fi
printf "\n${C_YELLOW}${C_BOLD}Выбранный набор:${C_NC} ${C_YELLOW}${C_BOLD}%s${C_NC}\n\n" "$(case "$NTP_PRESET" in cf_ip) printf "Cloudflare";; nist_ip) printf "NIST";; vniiftri_moscow) printf "ВНИИФТРИ";; google_ip) printf "Google";; *) printf "%s" "$NTP_PRESET";; esac)"
menu_item "[1]" "ВНИИФТРИ — российские серверы времени (по IP)"
menu_item "[2]" "NIST — серверы точного времени"
menu_item "[3]" "Cloudflare — серверы времени по IP"
menu_item "[4]" "Google — серверы времени по IP"
menu_back
menu_prompt
safe_read c
_old_ntp_preset="$NTP_PRESET"
case "$c" in
1) prepare_dns_operation || { pause; continue; }; menu_dns;;
2) test_dns_catalog; show_tests;;
3) show_map;;
4) prepare_dns_operation || { pause; continue; }; menu_ntp;;
5) prepare_dns_operation || { pause; continue; }; menu_extras;;
6) uninstall_manager;;
7)
   _luci_state="$(check_module_state luci)"
   if [ "$_luci_state" = 1 ] && [ "${LUCI_UPDATE_AVAILABLE:-0}" = 1 ]; then
       luci_companion_update; _rc=$?
       case "$_rc" in
           0) ok_msg "LuCI обновлена до версии ${LUCI_REMOTE_VERSION:-новой версии}." ;;
           2) info_msg "Новой версии LuCI нет." ;;
           *) err_msg "LuCI не удалось обновить." ;;
       esac
       pause
   elif [ "$_luci_state" = 1 ]; then
       setting_process luci "Удалить Нативный интерфейс DNS Manager" "Нативный интерфейс DNS Manager в LuCI." "$_luci_state"
   else
       setting_process luci "Нативный интерфейс DNS Manager" "Нативный интерфейс DNS Manager в LuCI." "$_luci_state"
   fi
*) warn_msg "Неверный пункт."; pause;;
esac
done
}
show_best() {
menu_category_select
}
auto_fill_slots() {
_cat="$1"
if ! case "$_cat" in bypass|clean|security|privacy|adblock|family|all) true;; *) false;; esac; then
    warn_msg "Неизвестная категория DNS."
    pause
    return 1
fi
ensure_test_results_fresh || { warn_msg "Не удалось получить свежие результаты теста."; pause; return 1; }
[ -s "$TEST_RESULTS" ] || { warn_msg "Не удалось получить результаты теста."; pause; return 1; }
_pool="$TMP_DIR/auto-slots"
_src="$TMP_DIR/auto-candidates"
: > "$_pool"
: > "$_src"
if [ "$_cat" = all ]; then
    awk -F'|' 'NF>=5 && $5=="OK" && $2!="regional" && $4 ~ /^[0-9]+$/ {print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n > "$_src"
else
    awk -F'|' -v c="$_cat" 'NF>=5 && $2==c && $5=="OK" && $4 ~ /^[0-9]+$/ {print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n > "$_src"
fi
[ -s "$_src" ] || {
    _cat_ok_count="$(awk -F'|' -v c="$_cat" 'NF>=5 && $2==c && $5=="OK" {n++} END{print n+0}' "$TEST_RESULTS" 2>/dev/null)"
    if [ "$_cat" = bypass ]; then
        warn_msg "В категории «Обход блокировок» не найдено подходящих проверенных DNS. Настройки не изменены."
    else
        warn_msg "В категории «$(category_ru "$_cat")» нет подходящих проверенных DNS. Настройки не изменены."
    fi
    pause
    return 1
}
_seen_urls="$TMP_DIR/auto-seen-urls"
: > "$_seen_urls"
i=1
while IFS='|' read -r _id _cat2 _name _ms _st; do
    [ -n "$_id" ] || continue
    _url="$(normalize_url "$(dns_url "$_id")")"
    [ -n "$_url" ] || continue
    grep -qxF "$_url" "$_seen_urls" 2>/dev/null && continue
    printf '%s\n' "$_url" >> "$_seen_urls"
    printf '%s\n' "$_id|$_cat2|$_name|$_ms|$_st" >> "$_pool"
    i=$((i+1))
    [ "$i" -gt 6 ] && break
done < "$_src"
[ -s "$_pool" ] || { warn_msg "Не удалось сформировать набор DNS."; pause; return 1; }
if [ "$_cat" = bypass ]; then
    _bypass_count="$(awk 'END{print NR+0}' "$_pool" 2>/dev/null)"
    if [ "$_bypass_count" -lt 6 ]; then
        warn_msg "В категории «Обход блокировок» подтверждено только $_bypass_count DNS из 6. Набор не применён."
        return 1
    fi
fi
if [ "$_cat" = all ]; then
    _src2="$TMP_DIR/auto-candidates-all"
    : > "$_src2"
    for _c in bypass clean security privacy adblock family; do
        awk -F'|' -v c="$_c" '$2==c{print}' "$_src" 2>/dev/null | head -n1 >> "$_src2"
    done
    cat "$_src" 2>/dev/null >> "$_src2"
    : > "$_pool"
    : > "$_seen_urls"
    i=1
    while IFS='|' read -r _id _cat2 _name _ms _st; do
        [ -n "$_id" ] || continue
        _url="$(normalize_url "$(dns_url "$_id")")"
        [ -n "$_url" ] || continue
        grep -qxF "$_url" "$_seen_urls" 2>/dev/null && continue
        printf '%s\n' "$_url" >> "$_seen_urls"
        printf '%s\n' "$_id|$_cat2|$_name|$_ms|$_st" >> "$_pool"
        i=$((i+1))
        [ "$i" -gt 6 ] && break
    done < "$_src2"
fi
i=1
while IFS='|' read -r _id _cat2 _name _ms _st; do
    [ -n "$_id" ] || continue
    slot_set "$i" "$_id" || return 1
    if [ "$_cat" = bypass ]; then
        slot_cat_set "$i" "bypass" || return 1
    else
        slot_cat_set "$i" "$_cat2" || return 1
    fi
    i=$((i+1))
    [ "$i" -gt 6 ] && break
done < "$_pool"
while [ "$i" -le 6 ]; do
    slot_set "$i" "" || return 1
    slot_cat_set "$i" "bypass" || return 1
    i=$((i+1))
done
_ru1=""
_yandex_ok="$(awk -F'|' 'NF>=5 && $1=="yandex_ru" && $2=="regional" && $5=="OK" && $4 ~ /^[0-9]+$/ {print "yes";exit}' "$TEST_RESULTS" 2>/dev/null)"
if [ "$_yandex_ok" = yes ]; then
    SLOT_RU="yandex_ru"
    SLOT_RU_CAT="regional"
    _ru1="yandex_ru"
else
    _ru1="$(awk -F'|' 'NF>=5 && $2=="regional" && $5=="OK" && $4 ~ /^[0-9]+$/ {print $1;exit}' "$TEST_RESULTS" 2>/dev/null)"
    if [ -n "$_ru1" ]; then
        SLOT_RU="$_ru1"
        SLOT_RU_CAT="regional"
    else
        warn_msg "Нет проверенных региональных DNS. RU-сегмент оставлен без нового назначения."
        SLOT_RU=""
        SLOT_RU_CAT="regional"
    fi
fi
return 0
}
# ==========================================
# ==========================================
select_slot() {
    slot="$1"
    clear_screen
    menu_header "ВЫБОР DNS-СЕРВЕРА $slot"
    _sel_catalog="$TMP_DIR/slot-catalog-${slot}-$$"
    case "$slot" in
        RU) awk -F'|' 'NF>=5 && $1 !~ /^#/ && $2=="regional" {print}' "$DNS_CATALOG" > "$_sel_catalog" ;;
        1|2|3|4|5|6) awk -F'|' 'NF>=5 && $1 !~ /^#/ && $2!="regional" {print}' "$DNS_CATALOG" > "$_sel_catalog" ;;
        *) return 1 ;;
    esac
    n=1
    while IFS='|' read -r id cat prof name url region status; do
        [ -n "$id" ] || continue
        printf "  ${C_CYAN}${C_BOLD}[%3d]${C_NC} ${C_GREEN}${C_BOLD}%-30s${C_NC} ${C_CYAN}[%s]${C_NC}\n" "$n" "$name" "$(category_ru "$cat")"
        n=$((n+1))
    done < "$_sel_catalog"
    rm -f "$_sel_catalog" 2>/dev/null
    printf "\n"
    menu_item "[99]" "Очистить"
    menu_back
    menu_prompt
    safe_read c
    [ -z "$c" ] && return
    if [ "$c" = "99" ]; then
        slot_set "$slot" "" || return 1
        case "$slot" in
            RU) slot_cat_set "$slot" "regional" || return 1 ;;
            *) slot_cat_set "$slot" "" || return 1 ;;
        esac
        sync_regional_dns_state
        info_msg "Изменение сохранено только после применения DNS."
        return
    fi
    case "$c" in ''|*[!0-9]*) warn_msg "Неверный номер."; pause; return;; esac
    row=""
    case "$slot" in
        RU) row="$(awk -F'|' -v n="$c" 'NF>=5 && $1 !~ /^#/ && $2=="regional" {i++; if(i==n){print; exit}}' "$DNS_CATALOG")" ;;
        1|2|3|4|5|6) row="$(awk -F'|' -v n="$c" 'NF>=5 && $1 !~ /^#/ && $2!="regional" {i++; if(i==n){print; exit}}' "$DNS_CATALOG")" ;;
    esac
    id="$(printf '%s' "$row" | cut -d'|' -f1)"
    [ -n "$id" ] || { warn_msg "Такого DNS нет в списке."; pause; return; }
    _selected_cat="$(printf '%s' "$row" | cut -d'|' -f2)"
    DNS_PROFILE="custom"
    DNS_SELECTION_MODE="manual"
    slot_set "$slot" "$id" || return 1
    slot_cat_set "$slot" "$_selected_cat" || return 1
    if [ "$slot" = RU ]; then
        DNS_SELECTION_CATEGORY="regional"
    else
        DNS_SELECTION_CATEGORY="$_selected_cat"
    fi
    sync_regional_dns_state
    info_msg "Выбор сохранится после применения DNS."
}

# ==========================================
# Read one scalar value from the manager config without executing it.
cfg_value() {
    _name="$1"
    [ -f "$CONFIG_FILE" ] || return 1
    sed -n "s/^${_name}=\"\(.*\)\"$/\1/p" "$CONFIG_FILE" 2>/dev/null | head -n1
}

# ==========================================
dns_slots_pending_changes() {
    for _v in SLOT_1 SLOT_2 SLOT_3 SLOT_4 SLOT_5 SLOT_6 SLOT_RU SLOT_1_CAT SLOT_2_CAT SLOT_3_CAT SLOT_4_CAT SLOT_5_CAT SLOT_6_CAT SLOT_RU_CAT; do
        eval "_mem=\${$_v:-}"
        _disk="$(cfg_value "$_v")"
        [ "$_mem" = "$_disk" ] || return 0
    done
    for _v in DNS_PROFILE DNS_SELECTION_MODE DNS_SELECTION_CATEGORY TLD_RU_ENABLED; do
        eval "_mem=\${$_v:-}"
        _disk="$(cfg_value "$_v")"
        [ "$_mem" = "$_disk" ] || return 0
    done
    return 1
}
dns_slots_discard_pending() {
    load_config
    reset_hybrid_runtime_ports >/dev/null 2>&1 || true
    sync_regional_dns_state
}
# ==========================================
menu_slots() {
while :; do
menu_header "СЕРВЕРЫ DNS"
if [ "$DNS_PROFILE" = "hybrid" ]; then
printf "${C_YELLOW}${C_BOLD}Профиль:${C_NC} ${C_GREEN}${C_BOLD}Гибридный DNS${C_NC}\n"
else
printf "${C_YELLOW}${C_BOLD}Настройка:${C_NC} ${C_GREEN}${C_BOLD}своя${C_NC}\n"
fi
menu_section "ОБЩИЕ СЛОТЫ"
printf "  ${C_YELLOW}${C_BOLD}%-4s %-34s %-8s${C_NC}\n" "№" "DNS" "ПОРТ"
printf "  ──────────────────────────────────────────────────────────\n"
for s in 1 2 3 4 5 6; do
eval "v=\${SLOT_$s}"
eval "p=\${PORT_$s}"
[ -n "$p" ] || p="$(hybrid_desired_port "$s")"
printf "  ${C_CYAN}${C_BOLD}%-4s${C_NC} ${C_GREEN}${C_BOLD}%-34s${C_NC} ${C_YELLOW}${C_BOLD}%-8s${C_NC}\n" "$s" "$(dns_name "$v")" "${p:-авто}"
done
menu_section "РЕГИОНАЛЬНЫЕ СЛОТЫ"
printf "  ${C_CYAN}${C_BOLD}[7]${C_NC} ${C_GREEN}${C_BOLD}RU${C_NC}   ${C_GREEN}%-30s${C_NC} ${C_YELLOW}${C_BOLD}%s${C_NC}\n" "$(dns_name "$SLOT_RU")" "${PORT_RU:-$HYBRID_PORT_RU}"

menu_section "ДЕЙСТВИЯ"
menu_item "[8]" "Сохранить и применить DNS"
menu_item "[9]" "Восстановить стандартную настройку"
menu_back
menu_prompt
safe_read c
if [ -z "$c" ]; then
    if dns_slots_pending_changes; then
        if confirm_action "Есть неприменённые изменения DNS-слотов. Применить их перед выходом?"; then
            CORE_ONLY=1
            apply_settings
            _rc=$?
            CORE_ONLY=0
            if [ "$_rc" -ne 0 ]; then
                warn_msg "Не удалось применить изменения. Остаюсь в меню DNS."
                pause
                continue
            fi
        else
            dns_slots_discard_pending
            info_msg "Неприменённые изменения DNS-слотов отменены."
            pause
        fi
    fi
    return
fi
case "$c" in
1|2|3|4|5|6) select_slot "$c";;
7) select_slot RU;;
8) CORE_ONLY=1; apply_settings; _rc=$?; CORE_ONLY=0; [ "$_rc" -eq 0 ] || warn_msg "Не удалось применить выбранные DNS."; pause;;
9)
    hybrid_set_defaults
    CORE_ONLY=1
    apply_settings
    _rc=$?
    CORE_ONLY=0
    [ "$_rc" -eq 0 ] || warn_msg "Не удалось восстановить стандартную настройку DNS."
    pause
    ;;
*) warn_msg "Неверный пункт."; pause;;
esac
done
}
menu_bogus() {
apply_bogus
}
firewall_wan_zone() {
    firewall_wan_zone_require
}

firewall_dot_rule_matches() {
    _sec="$1"
    firewall_resolve_zones >/dev/null 2>&1 || true
    [ "$(uci -q get "firewall.$_sec" 2>/dev/null)" = rule ] || return 1
    [ "$(uci -q get "firewall.$_sec.disabled" 2>/dev/null)" = 1 ] && return 1
    firewall_ref_matches_zone "$(uci -q get "firewall.$_sec.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" || return 1
    firewall_ref_matches_zone "$(uci -q get "firewall.$_sec.dest" 2>/dev/null)" "$FIREWALL_WAN_ZONE" || return 1
    [ "$(uci -q get "firewall.$_sec.proto" 2>/dev/null)" = 'tcp udp' ] || return 1
    [ "$(uci -q get "firewall.$_sec.dest_port" 2>/dev/null)" = 853 ] || return 1
    [ "$(uci -q get "firewall.$_sec.target" 2>/dev/null)" = REJECT ] || return 1
    return 0
}
ntp_profile_matches_current() {
    _exp="$(ntp_servers_for_profile "$NTP_PRESET" 2>/dev/null)"
    [ -n "$_exp" ] || return 1
    [ "$(uci -q get system.ntp.use_dhcp 2>/dev/null)" = 0 ] || return 1
    [ "$(uci -q get system.ntp.enabled 2>/dev/null)" = 1 ] || return 1
    _expected_sorted="$(printf '%s\n' $_exp | sort -u)"
    _current_sorted="$(uci -q get system.ntp.server 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -u)"
    [ "$_current_sorted" = "$_expected_sorted" ]
}
remove_ntp_ip_fallback() {
    uci -q delete system.ntp.server || true
    uci -q set system.ntp.use_dhcp=1 || return 1
    uci commit system || return 1
    /etc/init.d/sysntpd restart >/dev/null 2>&1 || true
    return 0
}
check_module_state() {
    # State detection must use current network values, not a stale discovery snapshot.
    disc_network >/dev/null 2>&1 || true
    _sec="$(get_dnsmasq_section)"
    firewall_resolve_zones >/dev/null 2>&1 || true
    case "$1" in
        balance)
            [ "$(uci -q get "dhcp.$_sec.allservers" 2>/dev/null)" = 1 ] || { printf 0; return; }
            [ "$(uci -q get "dhcp.$_sec.strictorder" 2>/dev/null)" = 0 ] || { printf 0; return; }
            [ "$(uci -q get "dhcp.$_sec.noresolv" 2>/dev/null)" = 1 ] && printf 1 || printf 0
            ;;
        tld)
            _ok=1; _seen=0
            _srv="$(uci -q get "dhcp.$_sec.server" 2>/dev/null | tr ' ' '\n')"
            for _slot in RU; do
                eval "_tid=\${SLOT_${_slot}:-}"
                [ -n "$_tid" ] || continue
                _seen=1
                eval "_tp=\${PORT_${_slot}:-}"
                [ -n "$_tp" ] || _tp="$(hybrid_desired_port "$_slot")"
                [ -n "$_tp" ] || { _ok=0; continue; }
                for _t in /ru /su /xn--p1ai; do
                    printf '%s\n' "$_srv" | grep -qxF "$_t/127.0.0.1#$_tp" || _ok=0
                done
            done
            [ "$_seen" = 1 ] && [ "$_ok" = 1 ] && printf 1 || printf 0
            ;;
        ntp)
            ntp_profile_matches_current && printf 1 || {
                _use="$(uci -q get system.ntp.use_dhcp 2>/dev/null)"
                _srv="$(uci -q get system.ntp.server 2>/dev/null)"
                # system.ntp.enabled=1 is normal stock behavior and is not
                # evidence that the DNS Manager NTP-by-IP module is active.
                if [ "$_use" = 0 ] || [ -n "$_srv" ]; then printf 2; else printf 0; fi
            }
            ;;
        force)
            detect_forced_dns_path >/dev/null 2>&1 || true
            detect_steer_dns_path >/dev/null 2>&1 || true
            if [ "${STEER_DNS_ACTIVE:-0}" = 1 ]; then
                if [ "${FORCE_DOH:-0}" = 1 ]; then
                    _ok=1
                    [ "$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null)" = "-" ] || _ok=0
                    [ "$(uci -q get https-dns-proxy.config.force_ip_family 2>/dev/null)" = "auto" ] || _ok=0
                    [ -z "$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)" ] || _ok=0
                    [ -z "$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null)" ] || _ok=0
                    [ -z "$(uci -q get https-dns-proxy.config.force_dns_port 2>/dev/null)" ] || _ok=0
                    [ -z "$(uci -q get https-dns-proxy.config.force_dns_src_interface 2>/dev/null)" ] || _ok=0
                    steer_dns_upstream_ready || _ok=0
                    dns_dot_block_ready || _ok=0
                    [ "$_ok" = 1 ] && printf 1 || printf 2
                else
                    printf 2
                fi
                return
            fi
            # External forced-DNS is informational only. The selected
            # DNS Manager setting remains authoritative and may overwrite it.

            # Package defaults are not an active DNS Manager feature.
            # Activation requires the manager flag and a real LAN DNS redirect.
            if [ "${FORCE_DOH:-0}" = 1 ]; then
                _ok=1
                [ "$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)" = 1 ] || _ok=0
                [ "$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null)" = 1 ] || _ok=0
                [ "$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null)" = '*' ] || _ok=0
                [ "$(uci -q get https-dns-proxy.config.procd_trigger_wan6 2>/dev/null)" = 0 ] || _ok=0
                [ "$(uci -q get https-dns-proxy.config.heartbeat_domain 2>/dev/null)" = heartbeat.mossdef.org ] || _ok=0
                [ "$(uci -q get https-dns-proxy.config.heartbeat_sleep_timeout 2>/dev/null)" = 10 ] || _ok=0
                [ "$(uci -q get https-dns-proxy.config.heartbeat_wait_timeout 2>/dev/null)" = 10 ] || _ok=0
                [ "$(uci -q get https-dns-proxy.config.user 2>/dev/null)" = nobody ] || _ok=0
                [ "$(uci -q get https-dns-proxy.config.group 2>/dev/null)" = nogroup ] || _ok=0
                [ "$(uci -q get https-dns-proxy.config.listen_addr 2>/dev/null)" = 127.0.0.1 ] || _ok=0
                [ "$(uci -q get https-dns-proxy.config.force_ip_family 2>/dev/null)" = auto ] || _ok=0
                [ "$(uci -q get https-dns-proxy.config.canary_domains_icloud 2>/dev/null)" = 1 ] || _ok=0
                [ "$(uci -q get https-dns-proxy.config.canary_domains_mozilla 2>/dev/null)" = 1 ] || _ok=0
                force_dns_ports_match_expected || _ok=0
                force_dns_src_matches_expected || _ok=0
                if [ "$_ok" = 1 ] && [ "${FORCED_DNS_ACTIVE:-0}" = 1 ]; then
                    printf 1
                else
                    printf 2
                fi
            else
                # No manager activation and no real external redirect = stock/off.
                if [ "${FORCED_DNS_ACTIVE:-0}" = 1 ]; then
                    printf 2
                else
                    printf 0
                fi
            fi
            ;;
        dnsmasq_perf)
            _stock=1
            _desired=1
            for _spec in "cachesize|1000|$DNSMASQ_CACHE_SIZE" "dnsforwardmax|150|300" "max_cache_ttl|__DM_UNSET__|86400" "boguspriv|1|1" "domainneeded|1|1" "quietdhcp|__DM_UNSET__|1"; do
                _k="${_spec%%|*}"; _r="${_spec#*|}"; _fallback="${_r%%|*}"; _desired_v="${_r#*|}"
                _cur="$(uci_value_normalized "dhcp.$_sec.$_k")"
                _stock_v="$(stock_uci_value_normalized dhcp "dhcp.@dnsmasq[0].$_k" "$_fallback")"
                [ "$_cur" = "$_stock_v" ] || _stock=0
                [ "$_cur" = "$_desired_v" ] || _desired=0
            done
            if [ "$IPV6_ROUTE" != yes ]; then
                _cur="$(uci_value_normalized "dhcp.$_sec.filter_aaaa")"
                _stock_v="$(stock_uci_value_normalized dhcp "dhcp.@dnsmasq[0].filter_aaaa" "0")"
                [ "$_cur" = "$_stock_v" ] || _stock=0
                [ "$_cur" = 1 ] || _desired=0
            fi
            if [ "$_stock" = 1 ]; then printf 0
            elif [ "$_desired" = 1 ]; then printf 1
            else printf 2
            fi
            ;;

        watchdog)
            watchdog_state_word_procd
            ;;
        luci)
            luci_component_state
            ;;
        web)
            if web_access_real; then
                printf 1
            elif web_access_listener_exists "${WEB_ACCESS_PORT:-7682}" 2>/dev/null && [ "$(web_access_pid_count 2>/dev/null || printf 0)" -gt 1 ]; then
                printf 2
            else
                printf 0
            fi
            ;;
        *)
            printf 0
            ;;
    esac
}

force_state_word() {
    detect_forced_dns_path >/dev/null 2>&1 || true
    detect_steer_dns_path >/dev/null 2>&1 || true
    if [ "${FORCED_DNS_EXTERNAL:-0}" = 1 ]; then
        printf "${C_BOLD}${C_RED}ВНЕШНИЙ${C_NC}"
        return 0
    fi
    _real="$(check_module_state force)"
    if [ "${STEER_DNS_ACTIVE:-0}" = 1 ] && [ "$_real" != 1 ]; then
        printf "${C_BOLD}${C_RED}ДРУГОЕ • Steer${C_NC}"
        return 0
    fi
    case "$_real" in
        1) printf "${C_BOLD}${C_GREEN}ВКЛ${C_NC}" ;;
        2) printf "${C_BOLD}${C_RED}ДРУГОЕ${C_NC}" ;;
        *) printf "${C_BOLD}${C_CYAN}ВЫКЛ${C_NC}" ;;
    esac
}
module_state_word() {
    case "$1" in
    esac
    _real="$(check_module_state "$1")"
    case "$_real" in
        1) printf "${C_BOLD}${C_GREEN}ВКЛ • работает${C_NC}" ;;
        2) printf "${C_BOLD}${C_RED}ДРУГОЕ • отличается${C_NC}" ;;
        *) printf "${C_BOLD}${C_CYAN}ВЫКЛ${C_NC}" ;;
    esac
}
# ==========================================
luci_component_files_present() {
    [ -f "$LUCI_MENU_FILE" ] || return 1
    [ -f "$LUCI_ACL_FILE" ] || return 1
    [ -x "$LUCI_RPC_PLUGIN" ] || return 1
    [ -f "$LUCI_VIEW_FILE" ] || return 1
    grep -Eq 'admin/services/dns-manager|admin/services/dns_manager' "$LUCI_MENU_FILE" 2>/dev/null || return 1
    grep -Fq 'luci-app-dns-manager' "$LUCI_ACL_FILE" 2>/dev/null || return 1
    grep -Fq 'DNS Manager LuCI rpcd plugin' "$LUCI_RPC_PLUGIN" 2>/dev/null || return 1
    grep -Fq 'DNS Manager' "$LUCI_VIEW_FILE" 2>/dev/null || return 1
    return 0
}

luci_component_runtime_valid() {
    [ -x "$LUCI_RPC_PLUGIN" ] || return 1
    [ -f "$LUCI_BACKEND_FILE" ] || return 1
    sh -n "$LUCI_RPC_PLUGIN" >/dev/null 2>&1 || return 1
    sh -n "$LUCI_BACKEND_FILE" >/dev/null 2>&1 || return 1
    return 0
}

luci_component_state() {
    if ! luci_component_files_present; then
        printf '0\n'
        return 0
    fi
    if ! luci_component_runtime_valid; then
        printf '2\n'
        return 0
    fi
    if command -v ubus >/dev/null 2>&1; then
        if ubus -S list dns_manager 2>/dev/null | grep -q '^dns_manager$'; then
            printf '1\n'
            return 0
        fi
    fi
    printf '2\n'
    return 0
}

luci_companion_fetch() {
    LUCI_COMPANION_FETCH_ERROR=""
    mkdir -p "$CFG_DIR" "$STATE_DIR" "$TMP_DIR" 2>/dev/null || { LUCI_COMPANION_FETCH_ERROR="Не удалось подготовить каталог временных файлов."; return 1; }
    _tmp="$TMP_DIR/dns-manager-luci-$$"
    rm -f "$_tmp" 2>/dev/null || true
    _cb="$(date +%s 2>/dev/null || printf 0)-$$"
    _fetch_url="${LUCI_COMPANION_URL}&_dmcb=$_cb"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 5 --max-time 30 -H 'User-Agent: DNS-Manager-LuCI' -H 'Accept: application/vnd.github.raw+json' -H 'Cache-Control: no-cache' -o "$_tmp" "$_fetch_url" >/dev/null 2>&1 || {
            LUCI_COMPANION_FETCH_ERROR="Ошибка загрузки companion через curl."
            rm -f "$_tmp" 2>/dev/null || true
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 30 --header='User-Agent: DNS-Manager-LuCI' --header='Accept: application/vnd.github.raw+json' --header='Cache-Control: no-cache' -O "$_tmp" "$_fetch_url" >/dev/null 2>&1 || {
            LUCI_COMPANION_FETCH_ERROR="Ошибка загрузки companion через wget."
            rm -f "$_tmp" 2>/dev/null || true
            return 1
        }
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$_tmp" "$_fetch_url" >/dev/null 2>&1 || {
            LUCI_COMPANION_FETCH_ERROR="Ошибка загрузки companion через uclient-fetch."
            rm -f "$_tmp" 2>/dev/null || true
            return 1
        }
    else
        LUCI_COMPANION_FETCH_ERROR="Не найден curl, wget или uclient-fetch."
        rm -f "$_tmp" 2>/dev/null || true
        return 1
    fi

    [ -s "$_tmp" ] || { LUCI_COMPANION_FETCH_ERROR="GitHub вернул пустой companion."; rm -f "$_tmp"; return 1; }
    head -n 1 "$_tmp" 2>/dev/null | grep -q '^#!/bin/sh' || { LUCI_COMPANION_FETCH_ERROR="Companion не похож на штатный POSIX shell-установщик."; rm -f "$_tmp"; return 1; }
    grep -Fq '# DNS Manager LuCI companion' "$_tmp" 2>/dev/null || { LUCI_COMPANION_FETCH_ERROR="Не найден маркер DNS Manager LuCI companion."; rm -f "$_tmp"; return 1; }
    grep -Fq '/usr/libexec/rpcd/dns_manager' "$_tmp" 2>/dev/null || { LUCI_COMPANION_FETCH_ERROR="В companion отсутствует ожидаемый RPC backend."; rm -f "$_tmp"; return 1; }
    grep -Eq 'admin/services/dns-manager|admin/services/dns_manager' "$_tmp" 2>/dev/null || { LUCI_COMPANION_FETCH_ERROR="В companion отсутствует меню LuCI Службы → DNS Manager."; rm -f "$_tmp"; return 1; }
    sh -n "$_tmp" >/dev/null 2>&1 || { LUCI_COMPANION_FETCH_ERROR="Companion не прошёл проверку shell-синтаксиса."; rm -f "$_tmp"; return 1; }

    LUCI_COMPANION_FETCH_FILE="$_tmp"
    LUCI_COMPANION_FETCH_VERSION="$(sed -n 's/^# Version:[[:space:]]*//p' "$_tmp" 2>/dev/null | head -n1)"
    return 0
}

luci_companion_check_update() {
    LUCI_REMOTE_VERSION=""
    LUCI_UPDATE_AVAILABLE=0

    luci_component_files_present || return 0

    _installed_ver="$(sed -n 's/^version=//p' "$LUCI_STATE_FILE" 2>/dev/null | head -n1)"
    [ -n "$_installed_ver" ] || _installed_ver="$(sed -n 's|^// DNS Manager LuCI version:[[:space:]]*||p' "$LUCI_VIEW_FILE" 2>/dev/null | head -n1)"
    [ -n "$_installed_ver" ] || return 0

    luci_companion_fetch || return 0

    _remote_ver="${LUCI_COMPANION_FETCH_VERSION:-}"
    LUCI_REMOTE_VERSION="$_remote_ver"
    if [ -n "$_remote_ver" ] && _ver_newer "$_remote_ver" "$_installed_ver" >/dev/null 2>&1; then
        LUCI_UPDATE_AVAILABLE=1
    fi

    rm -f "${LUCI_COMPANION_FETCH_FILE:-}" 2>/dev/null || true
    LUCI_COMPANION_FETCH_FILE=""
    LUCI_COMPANION_FETCH_VERSION=""
    return 0
}

luci_companion_update() {
    [ "$(luci_component_state)" = 1 ] || {
        err_msg "LuCI не установлена."
        return 1
    }

    _installed_ver="$(sed -n 's/^version=//p' "$LUCI_STATE_FILE" 2>/dev/null | head -n1)"
    [ -n "$_installed_ver" ] || _installed_ver="$(sed -n 's|^// DNS Manager LuCI version:[[:space:]]*||p' "$LUCI_VIEW_FILE" 2>/dev/null | head -n1)"
    [ -n "$_installed_ver" ] || { err_msg "Не удалось определить установленную версию LuCI."; return 1; }

    luci_companion_fetch || {
        [ -n "${LUCI_COMPANION_FETCH_ERROR:-}" ] && err_msg "LuCI: ${LUCI_COMPANION_FETCH_ERROR}" || err_msg "LuCI: не удалось получить свежую версию с GitHub."
        return 1
    }
    _new_ver="${LUCI_COMPANION_FETCH_VERSION:-}"
    [ -n "$_new_ver" ] || { rm -f "${LUCI_COMPANION_FETCH_FILE:-}" 2>/dev/null || true; LUCI_COMPANION_FETCH_FILE=""; err_msg "LuCI: в загруженном файле не найдена версия."; return 1; }
    if ! _ver_newer "$_new_ver" "$_installed_ver" >/dev/null 2>&1; then
        rm -f "${LUCI_COMPANION_FETCH_FILE:-}" 2>/dev/null || true
        LUCI_COMPANION_FETCH_FILE=""
        LUCI_REMOTE_VERSION="$_new_ver"
        return 2
    fi

    _tmp="${LUCI_COMPANION_FETCH_FILE:-}"
    _installed_cache="$LUCI_COMPANION_CACHE"
    log_msg "LuCI: чистое обновление $_installed_ver → $_new_ver — удаление старого интерфейса."
    luci_companion_remove || {
        rm -f "$_tmp" 2>/dev/null || true
        LUCI_COMPANION_FETCH_FILE=""
        err_msg "Не удалось удалить старую версию LuCI. Новую версию не устанавливаю."
        return 1
    }

    mkdir -p "$BASE_DIR" "$CFG_DIR" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null || true; LUCI_COMPANION_FETCH_FILE=""; return 1; }
    if ! cp -f "$_tmp" "$_installed_cache" 2>/dev/null || ! chmod 700 "$_installed_cache" 2>/dev/null; then
        rm -f "$_tmp" "$_installed_cache" 2>/dev/null || true
        LUCI_COMPANION_FETCH_FILE=""
        err_msg "Не удалось подготовить новый установщик LuCI."
        return 1
    fi
    rm -f "$_tmp" 2>/dev/null || true
    LUCI_COMPANION_FETCH_FILE=""

    sh "$_installed_cache" install >"$TMP_DIR/luci-install.log" 2>&1
    _luci_rc=$?
    if [ "$_luci_rc" -ne 0 ]; then
        [ -s "$TMP_DIR/luci-install.log" ] && while IFS= read -r _luci_line; do [ -n "$_luci_line" ] && log_msg "LuCI installer: $_luci_line"; done < "$TMP_DIR/luci-install.log"
        rm -f "$_installed_cache" 2>/dev/null || true
        err_msg "Установщик LuCI завершился с ошибкой (код $_luci_rc)."
        return 1
    fi

    [ "$(luci_component_state)" = 1 ] || {
        err_msg "Новая версия LuCI установлена не полностью."
        return 1
    }
    LUCI_REMOTE_VERSION="$_new_ver"
    return 0
}

luci_companion_install() {
    luci_companion_fetch || {
        [ -n "${LUCI_COMPANION_FETCH_ERROR:-}" ] && err_msg "LuCI: ${LUCI_COMPANION_FETCH_ERROR}" || err_msg "LuCI: не удалось безопасно получить dns-manager-luci.sh с GitHub."
        err_msg "Основной DNS Manager не изменён."
        return 1
    }

    _tmp="${LUCI_COMPANION_FETCH_FILE:-}"
    [ -s "$_tmp" ] || return 1
    mkdir -p "$BASE_DIR" "$CFG_DIR" 2>/dev/null || { rm -f "$_tmp"; return 1; }

    if ! cp -f "$_tmp" "$LUCI_COMPANION_CACHE" 2>/dev/null; then
        rm -f "$_tmp" 2>/dev/null || true
        err_msg "Не удалось сохранить локальную копию установщика LuCI."
        return 1
    fi
    chmod 700 "$LUCI_COMPANION_CACHE" 2>/dev/null || true

    sh "$LUCI_COMPANION_CACHE" install >"$TMP_DIR/luci-install.log" 2>&1
    _luci_rc=$?
    if [ "$_luci_rc" -ne 0 ]; then
        [ -s "$TMP_DIR/luci-install.log" ] && while IFS= read -r _luci_line; do [ -n "$_luci_line" ] && log_msg "LuCI installer: $_luci_line"; done < "$TMP_DIR/luci-install.log"
        rm -f "$LUCI_COMPANION_CACHE" 2>/dev/null || true
        rm -f "$_tmp" 2>/dev/null || true
        err_msg "Установщик LuCI завершился с ошибкой (код $_luci_rc). Подробность записана в журнал DNS Manager."
        return 1
    fi
    rm -f "$_tmp" 2>/dev/null || true

    if ! luci_component_runtime_valid; then
        err_msg "LuCI-установщик завершился, но сгенерированный RPC backend не прошёл shell-проверку."
        return 1
    fi

    luci_component_files_present || {
        err_msg "LuCI-установщик завершился, но комплект файлов интерфейса не прошёл контроль."
        return 1
    }

    _ver="${LUCI_COMPANION_FETCH_VERSION:-unknown}"
    {
        printf 'installed=1\n'
        printf 'version=%s\n' "$_ver"
        printf 'installed_at=%s\n' "$(date +%s 2>/dev/null)"
        printf 'source=%s\n' "$LUCI_COMPANION_URL"
    } > "${LUCI_STATE_FILE}.tmp.$$" 2>/dev/null || true
    if [ -s "${LUCI_STATE_FILE}.tmp.$$" ]; then
        chmod 600 "${LUCI_STATE_FILE}.tmp.$$" 2>/dev/null || true
        mv "${LUCI_STATE_FILE}.tmp.$$" "$LUCI_STATE_FILE" 2>/dev/null || rm -f "${LUCI_STATE_FILE}.tmp.$$"
    fi

    # A legacy 2.86 ttyd section is no longer the DNS Manager web interface.
    # Remove only the exact stable DNS Manager section; do not stop/remove shared ttyd.
    if uci -q get 'ttyd.dns_manager.command' 2>/dev/null | grep -qx '/usr/bin/dns-manager'; then
        WEB_ACCESS_ENABLED=0
        if manager_running_under_ttyd; then
            # Do not restart ttyd from inside its own session. Remove the manager-owned
            # section now and defer the shared ttyd restart until this shell has exited.
            web_access_remove_config_no_restart >/dev/null 2>&1 || true
            defer_ttyd_action restart 0 "${PKG_MGR:-}"
        else
            web_access_remove_config >/dev/null 2>&1 || true
        fi
        save_config >/dev/null 2>&1 || true
        log_msg "LuCI: устаревший ttyd-раздел DNS Manager удалён; общий ttyd не изменён."
    fi

    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
    fi
    if [ "$(luci_component_state)" = 1 ]; then
        log_msg "LuCI: нативный интерфейс DNS Manager установлен${_ver:+, companion=$_ver}."
        return 0
    fi

    log_msg "LuCI: файлы нативного интерфейса установлены, но rpcd ещё не зарегистрировал dns_manager."
    return 2
}

luci_companion_remove() {
    # Only remove an interface which this DNS Manager installation explicitly installed.
    [ -s "$LUCI_STATE_FILE" ] || return 0
    [ "$(sed -n 's/^installed=//p' "$LUCI_STATE_FILE" 2>/dev/null | head -n1)" = 1 ] || return 0

    if [ -x "$LUCI_COMPANION_CACHE" ]; then
        sh "$LUCI_COMPANION_CACHE" remove >/dev/null 2>&1 || return 1
    else
        # No cached installer: refuse destructive guessing.
        err_msg "Локальная копия установщика LuCI отсутствует; интерфейс автоматически не удаляю."
        return 1
    fi

    if luci_component_files_present; then
        err_msg "После удаления LuCI её файлы всё ещё присутствуют; очистку не считаю завершённой."
        return 1
    fi
    rm -f "$LUCI_COMPANION_CACHE" "$LUCI_STATE_FILE" 2>/dev/null || true
    return 0
}

# ==========================================
web_access_listener_exists() {
    _wp="$1"
    [ -n "$_wp" ] || return 1
    if command -v ss >/dev/null 2>&1; then
        ss -lnt 2>/dev/null | grep -qE "(^|[[:space:]])[^[:space:]]*:${_wp}([[:space:]]|$)" && return 0
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -lnt 2>/dev/null | grep -qE "(^|[[:space:]])[^[:space:]]*:${_wp}([[:space:]]|$)" && return 0
    fi
    listener_port_exists "$_wp"
}
web_access_owner_pid() {
    _wp="$1"
    [ -n "$_wp" ] || return 1
    if command -v pidof >/dev/null 2>&1; then
        for _pid in $(pidof ttyd 2>/dev/null); do
            [ -r "/proc/$_pid/cmdline" ] || continue
            _cmd="$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null)"
            case "$_cmd" in
                *ttyd*"-p $_wp"*"/usr/bin/dns-manager"*) printf '%s\n' "$_pid"; return 0;;
                *ttyd*"/usr/bin/dns-manager"*) printf '%s\n' "$_pid"; return 0;;
            esac
        done
    fi
    return 1
}
web_access_pid_count() {
    _wp="${WEB_ACCESS_PORT:-7682}"
    _n=0
    for _pid in $(ps w 2>/dev/null | awk -v p="$_wp" '$1 ~ /^[0-9]+$/ && index($0,"ttyd") && index($0,"/usr/bin/dns-manager") && (index($0,"-p " p) || index($0," " p " ")) {print $1}'); do
        kill -0 "$_pid" 2>/dev/null || continue
        _n=$((_n + 1))
    done
    printf '%s\n' "$_n"
}

web_access_real() {
    _wp="${WEB_ACCESS_PORT:-7682}"
    web_access_listener_exists "$_wp" || return 1
    _pid="$(web_access_owner_pid "$_wp" 2>/dev/null || true)"
    [ -n "$_pid" ] || return 1
    kill -0 "$_pid" 2>/dev/null
}
web_access_port_busy() {
    _wp="${WEB_ACCESS_PORT:-7682}"
    web_access_listener_exists "$_wp" || return 1
    web_access_real && return 1
    return 0
}
package_is_installed() {
    _pkg="$1"
    [ -n "$_pkg" ] || return 1
    if [ "$PKG_MGR" = apk ]; then
        apk info -e "$_pkg" >/dev/null 2>&1
    elif [ "$PKG_MGR" = opkg ]; then
        opkg status "$_pkg" 2>/dev/null | grep -q '^Status:.*installed'
    else
        return 1
    fi
}
package_owner_record_if_new() {
    _pkg="$1"
    [ -n "$_pkg" ] || return 0
    package_is_installed "$_pkg" && return 0
    mkdir -p "$CFG_DIR" 2>/dev/null || return 1
    touch "$PACKAGE_OWNERSHIP" 2>/dev/null || return 1
    grep -Fqx -- "$_pkg" "$PACKAGE_OWNERSHIP" 2>/dev/null || printf '%s\n' "$_pkg" >> "$PACKAGE_OWNERSHIP" || return 1
    return 0
}
package_owner_remove_owned() {
    [ -f "$PACKAGE_OWNERSHIP" ] || return 0
    _pkg_rc=0
    while IFS= read -r _pkg; do
        [ -n "$_pkg" ] || continue
        case "$_pkg" in
            *[!A-Za-z0-9._+:-]*) continue ;;
        esac
        if [ "$_pkg" = "ttyd" ] && [ "${UNINSTALL_UNDER_TTYD:-0}" = 1 ]; then
            UNINSTALL_DEFER_TTYD_PACKAGE=1
            continue
        fi
        _baseline_pkg="$(sed -n "s/^package_${_pkg}=//p" "$BASELINE_META" 2>/dev/null | head -n1)"
        [ "$_baseline_pkg" = 0 ] || continue
        if [ "$PKG_MGR" = apk ]; then
            if apk info -e "$_pkg" >/dev/null 2>&1; then
                apk del "$_pkg" >/dev/null 2>&1 || _pkg_rc=1
            fi
        elif [ "$PKG_MGR" = opkg ]; then
            if opkg status "$_pkg" 2>/dev/null | grep -q '^Status:.*installed'; then
                opkg remove "$_pkg" >/dev/null 2>&1 || _pkg_rc=1
            fi
        fi
    done < "$PACKAGE_OWNERSHIP"
    return "$_pkg_rc"
}

web_access_install() {
    _need=""
    command -v ttyd >/dev/null 2>&1 || _need="ttyd"
    if [ ! -f "$TTYD_CONFIG" ] && [ -n "$_need" ]; then :; fi
    if [ -n "$_need" ] || [ ! -x "$WEB_SERVICE_CONFIG" ]; then
        [ -n "$_need" ] && package_owner_record_if_new ttyd || true
        if [ "$PKG_MGR" = "apk" ]; then
            apk update >/dev/null 2>&1 || return 1
            apk add ttyd >/dev/null 2>&1 || return 1
        elif [ "$PKG_MGR" = "opkg" ]; then
            opkg update >/dev/null 2>&1 || return 1
            opkg install ttyd >/dev/null 2>&1 || return 1
        else
            return 1
        fi
    fi
    command -v ttyd >/dev/null 2>&1 || return 1
    [ -x "$WEB_SERVICE_CONFIG" ] || return 1
}
web_access_write_config() {
    mkdir -p /etc/config 2>/dev/null || return 1
    _ipv6="0"
    [ "${IPV6_ROUTE:-no}" = yes ] && _ipv6="1"

    # Stable UCI section: ttyd.dns_manager. Never rewrite the whole ttyd
    # configuration, so other ttyd instances remain untouched.
    uci -q set "ttyd.dns_manager=ttyd" || return 1
    uci set "ttyd.dns_manager.enable=1" || return 1
    uci set "ttyd.dns_manager.port=${WEB_ACCESS_PORT:-7682}" || return 1
    uci set "ttyd.dns_manager.interface=@lan" || return 1
    uci set "ttyd.dns_manager.command=/usr/bin/dns-manager" || return 1
    uci set "ttyd.dns_manager.readonly=0" || return 1
    uci set "ttyd.dns_manager.check_origin=1" || return 1
    uci set "ttyd.dns_manager.ipv6=$_ipv6" || return 1
    uci commit ttyd || return 1
    return 0
}
web_access_remove_config() {
    # Do not restart the shared ttyd service when DNS Manager has no section.
    _had_section=0
    uci -q get "ttyd.dns_manager" >/dev/null 2>&1 && _had_section=1
    uci -q delete "ttyd.dns_manager" || true
    if [ "$_had_section" = 1 ]; then
        uci commit ttyd >/dev/null 2>&1 || true
        [ -x "$WEB_SERVICE_CONFIG" ] && "$WEB_SERVICE_CONFIG" restart >/dev/null 2>&1 || true
    fi
    return 0
}
web_access_remove_config_no_restart() {
    # Remove only DNS Manager's stable ttyd section. Used by uninstall so the
    # running terminal is not killed before the manager has removed itself.
    WEB_ACCESS_SECTION_REMOVED=0
    _had_section=0
    uci -q get "ttyd.dns_manager" >/dev/null 2>&1 && _had_section=1
    uci -q delete "ttyd.dns_manager" || true
    if [ "$_had_section" = 1 ]; then
        uci commit ttyd >/dev/null 2>&1 || return 1
        WEB_ACCESS_SECTION_REMOVED=1
    fi
    return 0
}

web_access_start() {
    [ -x "$WEB_SERVICE_CONFIG" ] || return 1
    "$WEB_SERVICE_CONFIG" enable >/dev/null 2>&1 || true
    "$WEB_SERVICE_CONFIG" restart >/dev/null 2>&1 || "$WEB_SERVICE_CONFIG" start >/dev/null 2>&1 || return 1
    sleep 2
    web_access_real
}
web_access_stop() {
    [ -x "$WEB_SERVICE_CONFIG" ] && "$WEB_SERVICE_CONFIG" stop >/dev/null 2>&1 || true
    return 0
}
web_access_luci_install() {
    # Small LuCI launcher only: the terminal itself is the stock ttyd service.
    # No firewall rule and no second init script are created by DNS Manager.
    [ -d /usr/lib/lua/luci ] || return 0
    mkdir -p /usr/lib/lua/luci/controller || return 1
    cat > "$LUCI_CONTROLLER" <<'EOF_LUCI'
module("luci.controller.dns_manager", package.seeall)

function index()
    local fs = require "nixio.fs"
    local data = fs.readfile("/etc/dns-manager/config/manager.conf") or ""
    if not data:match("WEB_ACCESS_ENABLED=[\"\']1[\"\']") then return end
    local e = entry({"admin", "services", "dns_manager"}, call("redirect_to_ttyd"), _("DNS Manager Terminal"), 71)
    e.leaf = true
    e.dependent = false
end

function redirect_to_ttyd()
    local http = require "luci.http"
    local uci = require "luci.model.uci".cursor()
    local ip = uci:get("network", "lan", "ipaddr") or "192.168.1.1"
    local port = "7682"
    local fs = require "nixio.fs"
    local data = fs.readfile("/etc/dns-manager/config/manager.conf") or ""
    local found = data:match("WEB_ACCESS_PORT=[\"\']([0-9]+)[\"\']")
    if found then port = found end
    ip = ip:match("^[^/]+") or ip
    if ip:find(":", 1, true) then
        http.redirect("http://[" .. ip .. "]:" .. port .. "/")
    else
        http.redirect("http://" .. ip .. ":" .. port .. "/")
    end
end
EOF_LUCI
    chmod 0644 "$LUCI_CONTROLLER"
    rm -rf /tmp/luci-* /tmp/luci-indexcache* /tmp/luci-modulecache* 2>/dev/null || true
    /etc/init.d/rpcd reload >/dev/null 2>&1 || true
}
web_access_luci_remove() {
    _had_controller=0
    [ -f "$LUCI_CONTROLLER" ] && _had_controller=1
    rm -f "$LUCI_CONTROLLER"
    if [ "$_had_controller" = 1 ]; then
        rm -rf /tmp/luci-* /tmp/luci-indexcache* /tmp/luci-modulecache* 2>/dev/null || true
        if [ -x /etc/init.d/rpcd ]; then
            /etc/init.d/rpcd restart >/dev/null 2>&1 || /etc/init.d/rpcd reload >/dev/null 2>&1 || true
        fi
    fi
}

apply_web_access() {
    case "${WEB_ACCESS_ENABLED:-0}" in
        1)
            WEB_ACCESS_PORT=7682
            if web_access_install >/dev/null 2>&1; then :; else
                WEB_ACCESS_ENABLED=0
                save_config
                err_msg 'Не удалось установить/подготовить штатный ttyd.'
                return 1
            fi
            if web_access_port_busy; then
                WEB_ACCESS_ENABLED=0
                save_config
                err_msg "Порт терминала $WEB_ACCESS_PORT уже занят другим процессом."
                return 1
            fi
            if ! web_access_write_config; then
                WEB_ACCESS_ENABLED=0; save_config
                err_msg 'Не удалось записать /etc/config/ttyd.'
                return 1
            fi
            if ! web_access_start; then
                WEB_ACCESS_ENABLED=0
                save_config
                err_msg 'Штатный ttyd не запустился. Проверьте: /etc/init.d/ttyd status и logread -e ttyd.'
                return 1
            fi
            web_access_luci_install || true
            save_config
            ok_msg "Терминал DNS Manager работает через штатный ttyd на LAN: http://$(uci -q get network.lan.ipaddr 2>/dev/null | cut -d/ -f1 | head -n1):$WEB_ACCESS_PORT"
            return 0
            ;;
        *)
            WEB_ACCESS_ENABLED=0
            web_access_luci_remove
            web_access_remove_config
            save_config
            ok_msg 'Терминальный доступ DNS Manager выключен.'
            return 0
            ;;
    esac
}
setting_process() {
    _module="$1"
    _title="$2"
    _description="$3"
    _state="$4"
    [ -n "$_state" ] || _state="$(check_module_state "$_module")"

    printf "\n${C_WHITE}%s${C_NC}\n" "$_title"

    if [ "$_module" != luci ]; then
        if [ "$_module" = force ]; then
            detect_forced_dns_path >/dev/null 2>&1 || true
            if [ "${FORCED_DNS_EXTERNAL:-0}" = 1 ]; then
                printf "  ${C_YELLOW}Обнаружен внешний forced-DNS${C_NC}"
                if [ -n "${FORCED_DNS_SOURCE:-}" ] && [ "${FORCED_DNS_SOURCE:-none}" != "none" ]; then
                    printf " (${C_WHITE}%s${C_NC})" "$FORCED_DNS_SOURCE"
                fi
                printf ".\n"
                info_msg "Настройка будет приведена к конфигурации DNS Manager."
                printf "\n"
            elif [ "$_state" = 2 ]; then
                printf "  ${C_YELLOW}Обнаружены другие настройки forced-DNS.${C_NC}\n"
                info_msg "Текущие отличающиеся настройки будут исправлены."
                printf "\n"
            fi
        fi

        case "$_state" in
            0) printf "${C_GREEN}Включаю...${C_NC}\n" ;;
            1) printf "${C_GREEN}Выключаю...${C_NC}\n" ;;
            2) printf "${C_GREEN}Исправляю...${C_NC}\n" ;;
            *)
                err_msg "Не удалось определить состояние настройки."
                pause
                return 1
                ;;
        esac
    fi

    if [ "$_module" = luci ]; then
        case "$_state" in
            1)
                luci_companion_remove
                _rc=$?
                ;;
            *)
                luci_companion_install
                _rc=$?
                ;;
        esac
        if [ "$_rc" -eq 0 ]; then
            case "$_state" in
                1) ok_msg "Нативный интерфейс LuCI DNS Manager удалён. Сам DNS Manager и его DNS-настройки не изменены." ;;
                *) ok_msg "Нативный интерфейс LuCI DNS Manager установлен: LuCI → Службы → DNS Manager." ;;
            esac
        elif [ "$_rc" -eq 2 ]; then
            warn_msg "Файлы LuCI установлены, но rpcd ещё не зарегистрировал интерфейс. Обновите страницу LuCI после перезагрузки rpcd."
        else
            err_msg "Не удалось изменить нативный интерфейс LuCI DNS Manager."
        fi
        pause
        return "$_rc"
    fi

    _old_force="$FORCE_APPLY_SETTINGS"
    case "$_state" in
        0) _new=1 ;;
        1) _new=0 ;;
        2) _new=1; FORCE_APPLY_SETTINGS=1 ;;
    esac

    case "$_module" in
    esac

    case "$_module" in
        watchdog)
            _old_watchdog="$WATCHDOG_ENABLED"; WATCHDOG_ENABLED="$_new"
            apply_watchdog
            _rc=$?
            [ "$_rc" -eq 0 ] || WATCHDOG_ENABLED="$_old_watchdog"
            ;;
        *)
            apply_extras_now "$_module"
            _rc=$?
            if [ "$_rc" -ne 0 ]; then
                case "$_module" in
                esac
                save_config >/dev/null 2>&1 || true
            fi
            ;;
    esac

    FORCE_APPLY_SETTINGS="$_old_force"

    if [ "$_rc" -eq 0 ]; then
        case "$_state:$_module" in
            0:force|2:force) ok_msg "Принудительный DNS для устройств настроен." ;;
            1:force) ok_msg "Принудительный DNS для устройств выключен." ;;
            0:dnsmasq_perf|2:dnsmasq_perf) ok_msg "Увеличенный кэш DNS настроен." ;;
            1:dnsmasq_perf) ok_msg "Увеличенный кэш DNS выключен." ;;
            0:web|2:web) ok_msg "Терминальный доступ LuCI включён: пункт LuCI ведёт в ttyd DNS Manager." ;;
            1:web) ok_msg "Терминальный доступ LuCI выключен, пункт DNS Manager удалён." ;;
        esac
    else
        case "$_module" in
            force) err_msg "Не удалось изменить принудительный DNS для устройств." ;;
            dnsmasq_perf) err_msg "Не удалось изменить увеличенный кэш DNS." ;;
        esac
    fi
    pause
    return "$_rc"
}

menu_extras() {
while :; do
    _state_watchdog="$(check_module_state watchdog)"
    _state_force="$(check_module_state force)"
    _state_dnsmasq_perf="$(check_module_state dnsmasq_perf)"
    menu_header "СЕТЕВОЙ ТЮНИНГ"
    menu_section "DNS И СЕТЬ"
    menu_item_action "[1]" "Автопроверка и замена DNS" watchdog "$_state_watchdog"
    menu_item_action "[2]" "Принудительный DNS для устройств" force "$_state_force"
    menu_section "ТЮНИНГ DNS"
    menu_item_action "[3]" "Увеличенный кэш DNS" dnsmasq_perf "$_state_dnsmasq_perf"
    menu_back
    menu_prompt
    safe_read c
    case "$c" in
        1) setting_process watchdog "Автопроверка и замена DNS" "Проверяет только выбранные DNS-порты. При повторном подтверждённом сбое автоматически восстанавливает рабочий вариант." "$_state_watchdog" ;;
        2) setting_process force "Принудительный DNS для устройств" "DNS-запросы устройств на портах 53 направляются на DNS роутера; DoT на 853 блокируется." "$_state_force" ;;
        3) setting_process dnsmasq_perf "Увеличенный кэш DNS" "Увеличивает только кэш dnsmasq для повторных DNS-запросов." "$_state_dnsmasq_perf" ;;
        '') return ;;
        *) warn_msg "Неизвестный пункт."; pause ;;
    esac
done
}
# ==========================================
ensure_dependencies(){
missing=""
command -v curl >/dev/null 2>&1 || missing="$missing curl"
command -v https-dns-proxy >/dev/null 2>&1 || missing="$missing https-dns-proxy"
CA_OK=no
[ -s /etc/ssl/certs/ca-certificates.crt ] || [ -s /etc/ssl/certs/ca-bundle.crt ] && CA_OK=yes
if [ "$CA_OK" != yes ]; then
    if command -v apk >/dev/null 2>&1; then
        apk info -e ca-bundle >/dev/null 2>&1 && CA_OK=yes
        apk info -e ca-certificates >/dev/null 2>&1 && CA_OK=yes
    elif command -v opkg >/dev/null 2>&1; then
        opkg status ca-bundle 2>/dev/null | grep -q '^Status:.*installed' && CA_OK=yes
        opkg status ca-certificates 2>/dev/null | grep -q '^Status:.*installed' && CA_OK=yes
    fi
fi
[ "$CA_OK" = yes ] || missing="$missing ca-bundle"
[ "$HAS_DNSMASQ" = yes ] || missing="$missing dnsmasq"
printf '%s\n' "$missing"
}
prepare_dns_operation(){
    write_catalogs
    load_config
    run_discovery >/dev/null 2>&1 || true
    return 0
}
install_missing_dependencies(){
    _need="$(ensure_dependencies)"

    if [ -n "$_need" ]; then
        printf "
${C_YELLOW}↻ Обнаружены недостающие компоненты. Устанавливаю...${C_NC}
"
        for _pkg in $_need; do
            printf "  ${C_PINK}↻${C_NC} %s
" "$_pkg"
            package_owner_record_if_new "$_pkg" >/dev/null 2>&1 || true
        done
        printf "
"

        if [ "$PKG_MGR" = "apk" ]; then
            apk update >/dev/null 2>&1 && apk add $_need
        else
            opkg update >/dev/null 2>&1 && opkg install $_need
        fi
    fi

    if [ "${HAS_DIG:-no}" != yes ]; then
        printf "  ${C_PINK}↻${C_NC} dig (bind-dig/knot-dig)
"
        package_owner_record_if_new bind-dig >/dev/null 2>&1 || true
        package_owner_record_if_new knot-dig >/dev/null 2>&1 || true

        if [ "$PKG_MGR" = "apk" ]; then
            apk update >/dev/null 2>&1 || true
            apk add bind-dig >/dev/null 2>&1 || apk add knot-dig >/dev/null 2>&1 || true
        else
            opkg update >/dev/null 2>&1 || true
            opkg install bind-dig >/dev/null 2>&1 || opkg install knot-dig >/dev/null 2>&1 || true
        fi
    fi

    run_discovery >/dev/null 2>&1 || true

    _left="$(ensure_dependencies)"
    if [ -n "$_left" ]; then
        err_msg "Не удалось установить все необходимые компоненты: $_left"
        return 1
    fi

    if [ "${HAS_DIG:-no}" != yes ]; then
        err_msg "Не удалось установить dig (bind-dig или knot-dig). Локальные проверки DNS-портов могут работать неверно."
        return 1
    fi

    if [ -n "$_need" ]; then
        ok_msg "Все необходимые компоненты установлены."
    fi

    return 0
}
# ==========================================
# ==========================================
# ==========================================
# ==========================================
quick_max_bypass() {
menu_header "МАКСИМАЛЬНЫЙ ОБХОД"
printf "${C_WHITE}В этом пункте:${C_NC}\n"
printf "  ${C_GREEN}✓${C_NC} до 6 рабочих DNS-серверов (минимум 3 для применения)\n"
printf "  ${C_GREEN}✓${C_NC} отдельный DNS для .ru / .su / .рф\n"
printf "  ${C_GREEN}✓${C_NC} автоматическая замена неработающих серверов\n"
printf "  ${C_GREEN}✓${C_NC} одновременная работа выбранных DNS\n"
printf "  ${C_GREEN}✓${C_NC} проверка после настройки\n"
printf "  ${C_GREEN}✓${C_NC} сохранение исходных настроек для отката\n\n"
if watchdog_test_results_fresh; then
    info_msg "Использую свежие результаты полной проверки DNS; повторный тест не требуется."
else
    test_dns_catalog || return 1
fi
[ -s "$TEST_RESULTS" ] || return 1
DNS_PROFILE="hybrid"
DNS_SELECTION_MODE="quick"
DNS_SELECTION_CATEGORY="bypass"
SLOT_1=""; SLOT_2=""; SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""

SLOT_1_CAT="bypass"; SLOT_2_CAT="bypass"; SLOT_3_CAT="bypass"
SLOT_4_CAT="bypass"; SLOT_5_CAT="bypass"; SLOT_6_CAT="bypass"

TLD_RU_ENABLED=1
TLD_SPLIT=1
BALANCER_ENABLED=1
BOOTSTRAP_DNS="$BOOTSTRAP_DNS_ALL"
PORT_1="$HYBRID_PORT_1"; PORT_2="$HYBRID_PORT_2"; PORT_3="$HYBRID_PORT_3"
PORT_4="$HYBRID_PORT_4"; PORT_5="$HYBRID_PORT_5"; PORT_6="$HYBRID_PORT_6"

HYBRID_FORCE_RESELECT=1
   CORE_ONLY=1
    apply_settings
    _rc=$?
    CORE_ONLY=0
    HYBRID_FORCE_RESELECT=0
    return "$_rc"
}
# ==========================================
# ==========================================
dependency_preflight(){
run_discovery >/dev/null 2>&1 || true
printf "${C_TITLE} ПРОВЕРКА ЗАВИСИМОСТЕЙ${C_NC}\n"
printf '  curl              : %b\n' "$(state_word "$HAS_CURL")"
printf '  dig               : %b\n' "$(state_word "$HAS_DIG")"
printf '  https-dns-proxy   : %b\n' "$(state_word "$HAS_HDP")"
if [ -s /etc/ssl/certs/ca-certificates.crt ] || [ -s /etc/ssl/certs/ca-bundle.crt ]; then
printf '  CA-сертификаты    : %b✓ ВКЛ%b\n' "$C_GREEN" "$C_NC"
else
printf '  CA-сертификаты    : %b✗ НЕТ%b\n' "$C_RED" "$C_NC"
fi
}
# ==========================================
# ==========================================
# ==========================================
test_results_max_age_for_category() {
    case "${TEST_RESULTS_MAX_AGE:-}" in
        ''|*[!0-9]*) ;;
        *) printf '%s' "$TEST_RESULTS_MAX_AGE"; return 0 ;;
    esac
    case "$1" in
        bypass) printf '%s' "${TEST_RESULTS_MAX_AGE_BYPASS:-21600}" ;;
        clean) printf '%s' "${TEST_RESULTS_MAX_AGE_CLEAN:-21600}" ;;
        security) printf '%s' "${TEST_RESULTS_MAX_AGE_SECURITY:-21600}" ;;
        privacy) printf '%s' "${TEST_RESULTS_MAX_AGE_PRIVACY:-21600}" ;;
        adblock) printf '%s' "${TEST_RESULTS_MAX_AGE_ADBLOCK:-21600}" ;;
        family) printf '%s' "${TEST_RESULTS_MAX_AGE_FAMILY:-21600}" ;;
        regional) printf '%s' "${TEST_RESULTS_MAX_AGE_REGIONAL:-21600}" ;;
        *) printf '%s' "${TEST_RESULTS_MAX_AGE:-21600}" ;;
    esac
}

watchdog_test_results_fresh() {
    _fresh_cat="${1:-}"
    _fresh_max="$(test_results_max_age_for_category "$_fresh_cat")"
    case "$_fresh_max" in ''|*[!0-9]*) _fresh_max="${TEST_RESULTS_MAX_AGE:-21600}";; esac
    [ -s "$TEST_RESULTS" ] || return 1
    [ -s "$TEST_RESULTS_META" ] || return 1
    _ts="$(sed -n 's/^timestamp=//p' "$TEST_RESULTS_META" 2>/dev/null | head -n1)"
    _cv="$(sed -n 's/^catalog_version=//p' "$TEST_RESULTS_META" 2>/dev/null | head -n1)"
    _cc="$(sed -n 's/^catalog_count=//p' "$TEST_RESULTS_META" 2>/dev/null | head -n1)"
    _ch="$(sed -n 's/^catalog_hash=//p' "$TEST_RESULTS_META" 2>/dev/null | head -n1)"
    _now="$(date +%s 2>/dev/null)"
    case "$_ts" in ''|*[!0-9]*) return 1;; esac
    case "$_now" in ''|*[!0-9]*) return 1;; esac
    case "$_cc" in ''|*[!0-9]*) return 1;; esac
    [ -n "$_cv" ] || return 1
    [ -n "$_ch" ] || return 1
    [ "$_cv" = "$(dns_catalog_version)" ] || return 1
    [ "$_cc" = "$(count_dns)" ] || return 1
    [ "$(wc -l < "$TEST_RESULTS" 2>/dev/null | tr -d " ")" = "$_cc" ] || return 1
    [ "$_ch" = "$(file_hash "$DNS_CATALOG")" ] || return 1
    [ "$(( _now - _ts ))" -ge 0 ] 2>/dev/null || return 1
    [ "$(( _now - _ts ))" -le "$_fresh_max" ] 2>/dev/null || return 1
    return 0
}
ensure_test_results_fresh() {
    _fresh_cat="${1:-}"
    if watchdog_test_results_fresh "$_fresh_cat"; then
        return 0
    fi
    if [ "${HAS_CURL:-no}" != yes ]; then
        _dep_now="$(date +%s 2>/dev/null)"
        _dep_last="$(cat "$TEST_DEPENDENCY_WARNING_FILE" 2>/dev/null)"
        case "$_dep_now" in ''|*[!0-9]*) _dep_now="";; esac
        case "$_dep_last" in ''|*[!0-9]*) _dep_last="";; esac
        if [ -z "$_dep_now" ] || [ -z "$_dep_last" ] || [ "$((_dep_now-_dep_last))" -lt 0 ] 2>/dev/null || [ "$((_dep_now-_dep_last))" -ge "$TEST_DEPENDENCY_WARNING_MAX_AGE" ] 2>/dev/null; then
            warn_msg "Полную проверку DNS нельзя выполнить: curl не установлен."
            [ -n "$_dep_now" ] && printf '%s\n' "$_dep_now" > "$TEST_DEPENDENCY_WARNING_FILE" 2>/dev/null || true
        fi
        return 1
    fi
    info_msg "Результаты проверки DNS отсутствуют или устарели. Запускаю свежую проверку каталога."
    test_dns_catalog || return 1
    watchdog_test_results_fresh
}
watchdog_desired_cat() {
    _slot="$1"
    case "$DNS_SELECTION_MODE" in
        quick)
            case "$_slot" in RU) printf '%s\n' regional ;; *) printf '%s\n' bypass ;; esac
            return 0
            ;;
        profile|manual)
            _cat=""
            eval "_cat=\${SLOT_${_slot}_CAT:-}"
            [ -n "$_cat" ] || { eval "_id=\${SLOT_${_slot}:-}"; [ -n "$_id" ] && _cat="$(dns_cat "$_id")"; }
            case "$_slot" in RU) [ -n "$_cat" ] || _cat="regional" ;; esac
            printf '%s\n' "$_cat"
            return 0
            ;;
        *)
            _cat=""
            eval "_cat=\${SLOT_${_slot}_CAT:-}"
            [ -n "$_cat" ] || _cat="$(dns_cat "$(eval "printf '%s' \"\${SLOT_${_slot}:-}\"")")"
            case "$_slot" in RU) [ -n "$_cat" ] || _cat="regional" ;; *) [ -n "$_cat" ] || _cat="bypass" ;; esac
            printf '%s\n' "$_cat"
            ;;
    esac
}
watchdog_candidate_categories() {
    _slot="$1"
    _desired="$(watchdog_desired_cat "$_slot")"
    [ -n "$_desired" ] || return 1
    printf '%s\n' "$_desired"
}
watchdog_enforce_hdp_control() {
    [ "${FORCE_DOH:-0}" = 1 ] || return 0
    detect_steer_dns_path >/dev/null 2>&1 || true
    if [ "${STEER_DNS_ACTIVE:-0}" = 1 ]; then
        _changed=0
        for _k in force_dns notrack_dns force_dns_port force_dns_src_interface; do
            uci -q get "https-dns-proxy.config.$_k" >/dev/null 2>&1 && _changed=1
        done
        [ "$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null)" = "-" ] || _changed=1
        [ "$(uci -q get https-dns-proxy.config.force_ip_family 2>/dev/null)" = "auto" ] || _changed=1
        if [ "$_changed" = 1 ]; then
            for _k in force_dns notrack_dns force_dns_port force_dns_src_interface; do
                uci -q delete "https-dns-proxy.config.$_k" || true
            done
            uci set https-dns-proxy.config.dnsmasq_config_update="-" || return 1
            uci set https-dns-proxy.config.force_ip_family="auto" || return 1
            uci commit https-dns-proxy || return 1
            watchdog_restart_hdp || return 1
        fi
        ensure_dns_dot_block || return 1
        return 0
    fi
    _changed=0
    [ "$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null)" = "*" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)" = "1" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null)" = "1" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.procd_trigger_wan6 2>/dev/null)" = "0" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.heartbeat_domain 2>/dev/null)" = "heartbeat.mossdef.org" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.heartbeat_sleep_timeout 2>/dev/null)" = "10" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.heartbeat_wait_timeout 2>/dev/null)" = "10" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.user 2>/dev/null)" = "nobody" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.group 2>/dev/null)" = "nogroup" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.listen_addr 2>/dev/null)" = "127.0.0.1" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.force_ip_family 2>/dev/null)" = "auto" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.canary_domains_icloud 2>/dev/null)" = "1" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.canary_domains_mozilla 2>/dev/null)" = "1" ] || _changed=1
    force_dns_ports_match_expected || _changed=1
    force_dns_src_matches_expected || _changed=1
    [ "$_changed" = 0 ] && return 0
    log_msg "Обнаружен drift forced-DNS. Возвращаю конфигурацию DNS Manager, совместимую с Zapret Manager."
    sync_hdp_force_contract 1 || return 1
    return 0
}
watchdog_enforce_doh_authority() {
    [ "$DNS_PROFILE" = hybrid ] || [ "$DNS_PROFILE" = custom ] || return 0
    _expected=0
    for _s in 1 2 3 4 5 6 RU; do
        eval "_id=\${SLOT_${_s}:-}"
        [ -n "$_id" ] && _expected=$((_expected+1))
    done
    _actual=0
    _i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$_i]" >/dev/null 2>&1; do
        _actual=$((_actual+1))
        _i=$((_i+1))
    done
    if [ "$_actual" != "$_expected" ]; then
        log_msg "Количество DNS-секций отличается от выбранной схемы ($_actual вместо $_expected). Пересобираю полный набор DNS Manager."
        rebuild_selected_hdp_sections || return 1
        watchdog_restart_hdp || return 1
        sleep 3
        return 0
    fi
    return 0
}
watchdog_expected_servers() {
    _out="$TMP_DIR/watchdog-expected-servers-$$"
    : > "$_out"
    for _ws in 1 2 3 4 5 6; do
        case "$_ws" in 1) _wid="${SLOT_1:-}"; _wp="${PORT_1:-}";; 2) _wid="${SLOT_2:-}"; _wp="${PORT_2:-}";; 3) _wid="${SLOT_3:-}"; _wp="${PORT_3:-}";; 4) _wid="${SLOT_4:-}"; _wp="${PORT_4:-}";; 5) _wid="${SLOT_5:-}"; _wp="${PORT_5:-}";; 6) _wid="${SLOT_6:-}"; _wp="${PORT_6:-}";; esac
        [ -n "$_wid" ] || continue
        [ -n "$_wp" ] || continue
        printf '127.0.0.1#%s\n' "$_wp" >> "$_out"
    done
    if [ "${TLD_RU_ENABLED:-0}" = 1 ]; then
        if [ -n "$SLOT_RU" ] && [ -n "$PORT_RU" ]; then
            for _t in /ru /su /xn--p1ai; do printf '%s/127.0.0.1#%s\n' "$_t" "$PORT_RU" >> "$_out"; done
        fi
    fi
    sort -u "$_out" -o "$_out" 2>/dev/null || true
    printf '%s\n' "$_out"
}
watchdog_dns_path_guard() {
    detect_forced_dns_path >/dev/null 2>&1 || true
    if [ "${FORCED_DNS_EXTERNAL:-0}" = 1 ]; then
        # External forced-DNS is a valid coexistence state (for example Zapret).
        # It is reported by discovery/status, but it is not a watchdog error.
        return 0
    fi
    return 0
}
watchdog_dnsmasq_guard() {
    _sec="$(get_dnsmasq_section)"
    [ -n "$_sec" ] || return 1
    _actual="$TMP_DIR/watchdog-actual-servers-$$"
    _expected="$TMP_DIR/watchdog-expected-servers-$$"
    : > "$_actual"
    uci -q get "dhcp.$_sec.server" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -u > "$_actual"
    _expected="$(watchdog_expected_servers)"
    if [ ! -s "$_expected" ]; then
        return 0
    fi
    _balance_bad=0
    if [ "${BALANCER_ENABLED:-1}" = 1 ]; then
        [ "$(uci -q get "dhcp.$_sec.allservers" 2>/dev/null)" = 1 ] || _balance_bad=1
    else
        [ -z "$(uci -q get "dhcp.$_sec.allservers" 2>/dev/null)" ] || _balance_bad=1
    fi
    if ! cmp -s "$_actual" "$_expected" 2>/dev/null || [ "$(uci -q get "dhcp.$_sec.noresolv" 2>/dev/null)" != 1 ] || [ "$_balance_bad" = 1 ]; then
        log_msg "Обнаружен drift dnsmasq. Восстанавливаю авторитетную конфигурацию DNS Manager."
        reconcile_dnsmasq || return 1
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
    fi
    return 0
}
watchdog_service_recover() {
    local _bad=0 _rs _rid _rport _rdomain
    for _rs in 1 2 3 4 5 6 RU; do
        eval "_rid=\${SLOT_${_rs}:-}"
        [ -n "$_rid" ] || continue
        eval "_rport=\${PORT_${_rs}:-}"
        [ -n "$_rport" ] || { _bad=1; break; }
        case "$_rs" in RU) _rdomain="yandex.ru" ;; *) _rdomain="example.com" ;; esac
        if ! listener_port_exists "$_rport" || ! local_dns_query_ok "$_rport" "$_rdomain"; then
            _bad=1
            break
        fi
    done
    [ "$_bad" = 0 ] && return 0
    log_msg "Обнаружен неработающий экземпляр https-dns-proxy. Выполняю восстановительный перезапуск."
    watchdog_restart_hdp || return 1
    return 0
}
process_matches_doh_slot() {
    _pm_port="$1"
    _pm_url="$(normalize_url "$2")"
    [ -n "$_pm_port" ] && [ -n "$_pm_url" ] || return 1
    for _pm_pid in $(pgrep -f '[h]ttps-dns-proxy' 2>/dev/null); do
        [ -r "/proc/$_pm_pid/cmdline" ] || continue
        if tr '\0' '\n' < "/proc/$_pm_pid/cmdline" 2>/dev/null | awk -v want_p="$_pm_port" -v want_r="$_pm_url" '
            $0 == "-p" { need_p=1; next }
            $0 == "-r" { need_r=1; next }
            need_p { if ($0 == want_p) ok_p=1; need_p=0; next }
            need_r { if ($0 == want_r) ok_r=1; need_r=0; next }
            END { exit (ok_p && ok_r) ? 0 : 1 }
        ' >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}
watchdog_hdp_guard() {
    _bad=0
    _expected="$TMP_DIR/watchdog-hdp-expected-$$"
    _actual="$TMP_DIR/watchdog-hdp-actual-$$"
    : > "$_expected" || return 1
    : > "$_actual" || { rm -f "$_expected"; return 1; }
    for _s in 1 2 3 4 5 6 RU; do
        eval "_id=\${SLOT_${_s}:-}"
        [ -n "$_id" ] || continue
        eval "_p=\${PORT_${_s}:-}"
        [ -n "$_p" ] || continue
        _u="$(normalize_url "$(dns_url "$_id")")"
        [ -n "$_u" ] || { rm -f "$_expected" "$_actual"; return 1; }
        printf '%s|%s|%s\n' "$_s" "$_p" "$_u" >> "$_expected"
    done
    _i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$_i]" >/dev/null 2>&1; do
        _p="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].listen_port" 2>/dev/null)"
        _u="$(normalize_url "$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].resolver_url" 2>/dev/null)")"
        printf '%s|%s\n' "$_p" "$_u" >> "$_actual"
        if [ -n "$_p" ] && [ -n "$_u" ] && ! process_matches_doh_slot "$_p" "$_u"; then
            _bad=1
        fi
        _i=$((_i+1))
    done
    _expected_n="$(wc -l < "$_expected" 2>/dev/null | tr -d ' ')"
    _actual_n="$(wc -l < "$_actual" 2>/dev/null | tr -d ' ')"
    [ "$_expected_n" = "$_actual_n" ] || _bad=1
    while IFS='|' read -r _slot _port _url; do
        [ -n "$_url" ] || continue
        grep -qxF "$_port|$_url" "$_actual" 2>/dev/null || { _bad=1; break; }
    done < "$_expected"
    if [ "$_bad" = 1 ]; then
        log_msg "Обнаружено изменение конфигурации DNS. Восстанавливаю выбранные серверы без изменения профиля."
        rebuild_selected_hdp_sections || { rm -f "$_expected" "$_actual"; return 1; }
        watchdog_restart_hdp || { rm -f "$_expected" "$_actual"; return 1; }
        sleep 3
    fi
    rm -f "$_expected" "$_actual" 2>/dev/null
    return 0
}
watchdog_check_slot() {
    _slot="$1"
    case "$_slot" in
        1) _id="${SLOT_1:-}"; _port="${PORT_1:-}"; _domain="example.com";;
        2) _id="${SLOT_2:-}"; _port="${PORT_2:-}"; _domain="example.com";;
        3) _id="${SLOT_3:-}"; _port="${PORT_3:-}"; _domain="example.com";;
        4) _id="${SLOT_4:-}"; _port="${PORT_4:-}"; _domain="example.com";;
        5) _id="${SLOT_5:-}"; _port="${PORT_5:-}"; _domain="example.com";;
        6) _id="${SLOT_6:-}"; _port="${PORT_6:-}"; _domain="example.com";;
        RU) _id="${SLOT_RU:-}"; _port="${PORT_RU:-}"; _domain="yandex.ru";;
        *) return 1;;
    esac
    [ -n "$_id" ] || return 1
    [ -n "$_port" ] || return 1
    listener_port_exists "$_port" || return 1
    local_dns_query_ok "$_port" "$_domain" || return 1
    return 0
}
# ==========================================
watchdog_test_candidate() {
    _slot="$1"
    _id="$2"
    [ -n "$_id" ] || return 1
    _port="$(hybrid_desired_port "$_slot")"
    [ -n "$_port" ] || return 1
    case "$_slot" in RU) _domain="yandex.ru" ;; *) _domain="example.com" ;; esac
    listener_port_exists "$_port" || return 1
    local_dns_query_ok "$_port" "$_domain" || return 1
    return 0
}
watchdog_preferred_quick_candidate() {
    _slot="$1"
    case "$_slot" in
        1|2|3|4|5|6) eval "_pref=\${QUICK_PREF_$_slot:-}" ;;
        *) _pref="" ;;
    esac
    [ -n "$_pref" ] || return 1
    printf '%s\n' "$_pref"
}
watchdog_probe_catalog_candidate() {
    _id="$1"
    _domain="${2:-example.com}"
    [ -n "$_id" ] || return 1
    [ "${HAS_CURL:-no}" = yes ] || return 2

    _url="$(normalize_url "$(dns_url "$_id")")"
    _host="$(url_host "$_url")"
    _port="$(url_port "$_url")"
    [ -n "$_url" ] && [ -n "$_host" ] && [ -n "$_port" ] || return 1

    _q="$TMP_DIR/watchdog-q-$$"
    _b="$TMP_DIR/watchdog-b-$$"
    _h="$TMP_DIR/watchdog-h-$$"
    rm -f "$_q" "$_b" "$_h" 2>/dev/null || true

    case "$_domain" in
        yandex.ru)
            printf '\022\064\001\000\000\001\000\000\000\000\000\000\006yandex\002ru\000\000\001\000\001' > "$_q" || { rm -f "$_q"; return 1; }
            ;;
        *)
            printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$_q" || { rm -f "$_q"; return 1; }
            ;;
    esac

    _ips="$(resolve_host "$_host" 2>/dev/null)"
    [ -n "$_ips" ] || {
        rm -f "$_q"
        return 1
    }
    _ok=0
    while IFS= read -r _ip; do
        [ -n "$_ip" ] || continue
        : > "$_b"
        : > "$_h"
        _res="$(curl -sS -o "$_b" -D "$_h" -w '%{http_code}' \
            --connect-timeout 2 --max-time 4 \
            --resolve "$_host:$_port:$_ip" \
            -H 'Content-Type: application/dns-message' \
            -H 'Accept: application/dns-message' \
            --data-binary "@$_q" "$_url" 2>/dev/null)"
        _bytes="$(wc -c < "$_b" 2>/dev/null | tr -d ' ')"
        case "$_bytes" in ''|*[!0-9]*) _bytes=0;; esac
        _ctype="$(awk -F': *' 'tolower($1)=="content-type"{print tolower($2)}' "$_h" 2>/dev/null | tail -n1 | tr -d '\r')"
        if [ "$_res" = 200 ] && [ "$_bytes" -ge 12 ] && printf '%s' "$_ctype" | grep -q 'application/dns-message'; then
            _ok=1
            break
        fi
    done <<EOF_WD_IPS
$_ips
EOF_WD_IPS
    rm -f "$_q" "$_b" "$_h" 2>/dev/null || true
    [ "$_ok" = 1 ]
}
watchdog_pick_replacement() {
    _slot="$1"
    _used="$2"
    _tried="$3"
    _desired_for_pick="$(watchdog_desired_cat "$_slot")"
    [ -n "$_desired_for_pick" ] || return 1
    case "$_slot" in
        RU) _probe_domain="yandex.ru" ;;
        *) _probe_domain="example.com" ;;
    esac

    _passcats="$_desired_for_pick"
    # Only bypass is allowed to fall back to clean, and only after the
    # bounded bypass candidate set has been rejected. Regional never falls back.
    if [ "$_desired_for_pick" = bypass ]; then
        _passcats="bypass clean"
    fi

    for _passcat in $_passcats; do
        _checked_cat=0

        # In quick mode, try the already preferred bypass entry first.
        if [ "$_passcat" = bypass ] && [ "${DNS_SELECTION_MODE:-}" = quick ]; then
            _preferred="$(watchdog_preferred_quick_candidate "$_slot" 2>/dev/null)"
            if [ -n "$_preferred" ] && [ "$(dns_cat "$_preferred" 2>/dev/null)" = bypass ] && [ "$_preferred" != "${_current_id:-}" ]; then
                _purl="$(normalize_url "$(dns_url "$_preferred")")"
                if [ -n "$_purl" ] && ! grep -qxF "$_purl" "$_used" 2>/dev/null && ! grep -qxF "$_preferred" "$_tried" 2>/dev/null; then
                    _checked_cat=$((_checked_cat+1))
                    if [ "$_checked_cat" -le "${WATCHDOG_MAX_CANDIDATES:-3}" ] && watchdog_probe_catalog_candidate "$_preferred" "$_probe_domain"; then
                        printf '%s|bypass\n' "$_preferred"
                        return 0
                    fi
                    printf '%s\n' "$_preferred" >> "$_tried"
                fi
            fi
        fi

        while IFS='|' read -r _rid _rcat _rname _rms _rst; do
            [ -n "$_rid" ] || continue
            case "$_rid" in \#*) continue ;; esac
            [ "$_rcat" = "$_passcat" ] || continue
            [ -n "${REPAIR_BAD_IDS:-}" ] && grep -qxF "$_rid" "$REPAIR_BAD_IDS" 2>/dev/null && continue
            [ "$_rid" != "${_current_id:-}" ] || continue
            _rurl="$(normalize_url "$(dns_url "$_rid")")"
            [ -n "$_rurl" ] || continue
            grep -qxF "$_rurl" "$_used" 2>/dev/null && continue
            grep -qxF "$_rid" "$_tried" 2>/dev/null && continue
            _checked_cat=$((_checked_cat+1))
            [ "$_checked_cat" -le "${WATCHDOG_MAX_CANDIDATES:-3}" ] || break
            # This is a direct DoH probe. No UCI write, no service restart, no flash.
            if watchdog_probe_catalog_candidate "$_rid" "$_probe_domain"; then
                printf '%s|%s\n' "$_rid" "$_rcat"
                return 0
            fi
            printf '%s\n' "$_rid" >> "$_tried"
        done < "$DNS_CATALOG"

        # Do not try clean for non-bypass profiles.
        [ "$_desired_for_pick" = bypass ] || break
    done
    return 1
}
watchdog_apply_slot_candidate() {
    _slot="$1"; _new_id="$2"; _new_cat="$3"; _old_id="$4"; _old_cat="$5"
    eval "_port=\${PORT_${_slot}:-}"
    [ -n "$_slot" ] && [ -n "$_new_id" ] || return 1
    slot_set "$_slot" "$_new_id" || return 1
    slot_cat_set "$_slot" "$_new_cat" || return 1

    watchdog_candidate_rollback() {
        slot_set "$_slot" "$_old_id" || return 1
        slot_cat_set "$_slot" "$_old_cat" || return 1
        if ! rebuild_selected_hdp_sections >/dev/null 2>&1; then
            log_msg "Watchdog: не удалось пересобрать старую конфигурацию после неудачной замены слота $_slot."
            return 1
        fi
        /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || {
            log_msg "Watchdog: не удалось перезапустить https-dns-proxy после отката слота $_slot."
            return 1
        }
        sleep 3
        watchdog_check_slot "$_slot"
    }

    if ! rebuild_selected_hdp_sections >/dev/null 2>&1; then
        watchdog_candidate_rollback >/dev/null 2>&1 || true
        return 1
    fi
    if ! watchdog_restart_hdp burst; then
        watchdog_candidate_rollback >/dev/null 2>&1 || true
        return 1
    fi
    sleep 3
    if watchdog_check_slot "$_slot"; then
        if ! save_config; then
            watchdog_candidate_rollback >/dev/null 2>&1 || true
            return 1
        fi
        normalize_ownership_snapshot >/dev/null 2>&1 || true
        _new_url="$(normalize_url "$(dns_url "$_new_id")")"
        [ -n "$_new_url" ] && record_own "doh" "$_port" "$_new_url" "slot=$_slot;name=$(dns_name "$_new_id")"
        return 0
    fi
    watchdog_candidate_rollback >/dev/null 2>&1 || true
    return 1
}

# ==========================================
WATCHDOG_RESTART_COUNT=0
watchdog_restart_hdp() {
    _mode="${1:-normal}"
    _max="${WATCHDOG_MAX_RESTARTS:-2}"
    [ "${WATCHDOG_RESTART_COUNT:-0}" -lt "$_max" ] || {
        log_msg "Watchdog: лимит контролируемых перезапусков https-dns-proxy за одну операцию достигнут ($_max)."
        return 1
    }
    _now="$(date +%s 2>/dev/null)"
    _last="${WATCHDOG_LAST_RESTART_TS:-0}"
    case "$_now" in ''|*[!0-9]*) _now=0;; esac
    case "$_last" in ''|*[!0-9]*) _last=0;; esac

    # Normal watchdog paths are protected by the global restart cooldown.
    # A single slot-repair/service-recovery operation is allowed to restart
    # https-dns-proxy up to WATCHDOG_MAX_RESTARTS times so the second candidate
    # is not blocked by the timestamp written by the first candidate.
    if [ "$_mode" != burst ] && [ "$_last" -gt 0 ] && [ $((_now-_last)) -lt "${WATCHDOG_RESTART_COOLDOWN:-300}" ]; then
        return 1
    fi

    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
    WATCHDOG_RESTART_COUNT=$((WATCHDOG_RESTART_COUNT+1))
    WATCHDOG_LAST_RESTART_TS="$_now"
    sleep 3
    refresh_runtime_capabilities

    _expected="$(expected_managed_slots 2>/dev/null)"
    case "$_expected" in ''|*[!0-9]*) _expected=0;; esac
    [ "$_expected" -gt 0 ] || return 0
    [ "$DOH_TOTAL" = "$_expected" ] || return 1
    [ "$HDP_RUNNING" = yes ] || return 1

    for _rs in 1 2 3 4 5 6 RU; do
        eval "_rid=\${SLOT_${_rs}:-}"
        [ -n "$_rid" ] || continue
        eval "_rport=\${PORT_${_rs}:-}"
        [ -n "$_rport" ] || return 1
        listener_port_exists "$_rport" || return 1
    done
    return 0
}
watchdog_resource_guard() {
    _mem="$(awk '/^MemAvailable:/{print $2; exit}' /proc/meminfo 2>/dev/null)"
    case "$_mem" in ''|*[!0-9]*) ;; *)
        if [ "$_mem" -lt 16384 ]; then
            log_msg "Watchdog пропущен: доступная RAM ${_mem} KB (<16 MB)."
            return 1
        fi
        ;;
    esac
    _load="$(awk '{print $1; exit}' /proc/loadavg 2>/dev/null)"
    _load10="$(awk -v x="$_load" 'BEGIN{printf "%.0f", x*10}' 2>/dev/null)"
    _cpu="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
    case "$_cpu" in ''|*[!0-9]*) _cpu=1;; esac
    case "$_load10" in ''|*[!0-9]*) return 0;; esac
    _limit=$(( _cpu * 20 ))
    if [ "$_load10" -gt "$_limit" ]; then
        log_msg "Watchdog пропущен: высокая загрузка системы (load1=$_load, cpu=$_cpu)."
        return 1
    fi
    return 0
}
# ==========================================
# ==========================================
watchdog_light_probe() {
    _port="$1"
    _domain="${2:-example.com}"
    case "$_port" in ''|*[!0-9]*) return 1;; esac
    if command -v dig >/dev/null 2>&1; then
        _ans="$(dig @127.0.0.1 -p "$_port" "$_domain" A +time=1 +tries=1 +short 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print; exit}')"
        [ -n "$_ans" ] && return 0
        return 1
    fi
    if command -v nslookup >/dev/null 2>&1; then
        _ans="$(nslookup -port="$_port" "$_domain" 127.0.0.1 2>/dev/null | awk '/^Address/ {for(i=2;i<=NF;i++) if($i ~ /^[0-9]+(\.[0-9]+){3}$/ && $i !~ /^127\./ && $i != "0.0.0.0") {print $i; exit}}')"
        [ -n "$_ans" ] && return 0
        return 1
    fi
    return 2
}
watchdog_refresh_listener_snapshot() {
    # One /proc scan per watchdog cycle. This avoids invoking ss/netstat for
    # every slot and keeps the normal healthy path cheap on small routers.
    WD_LISTEN_PORTS="$(awk '
        BEGIN { out="" }
        NR > 1 {
            split($2,a,":");
            if ($4 == "0A") {
                p=toupper(a[2]);
                if (p != "") {
                    out = out p " "
                }
            }
        }
        END { print out }
    ' /proc/net/tcp /proc/net/tcp6 2>/dev/null)"
}
watchdog_listener_snapshot_has_port() {
    _port="$1"
    _hex="$(printf '%04X' "$_port" 2>/dev/null)" || return 1
    case " ${WD_LISTEN_PORTS:-} " in
        *" $_hex "*) return 0;;
        *) return 1;;
    esac
}
watchdog_loop_repair_cooldown_ok() {
    _slot="$1"
    eval "_last=\${WD_REPAIR_TS_${_slot}:-0}"
    case "$_last" in ''|*[!0-9]*) _last=0;; esac
    _now="$(date +%s 2>/dev/null)"
    case "$_now" in ''|*[!0-9]*) return 1;; esac
    [ $((_now-_last)) -ge "${WATCHDOG_REPAIR_COOLDOWN:-300}" ] 2>/dev/null
}
watchdog_loop_mark_repair() {
    _slot="$1"
    _now="$(date +%s 2>/dev/null)"
    case "$_now" in ''|*[!0-9]*) return 0;; esac
    eval "WD_REPAIR_TS_${_slot}=\$_now"
}
watchdog_loop_reset_slot() {
    _slot="$1"
    eval "WD_FAIL_${_slot}=0"
    eval "WD_MISSING_${_slot}=0"
}
watchdog_embedded_integrity_guard() {
    _now="$(date +%s 2>/dev/null)"
    case "$_now" in ''|*[!0-9]*) return 0;; esac
    _last="${WD_LAST_GUARD_TS:-0}"
    case "$_last" in ''|*[!0-9]*) _last=0;; esac
    [ "$_last" -gt 0 ] && [ $((_now-_last)) -lt "${WATCHDOG_GUARD_INTERVAL:-900}" ] 2>/dev/null && return 0
    acquire_mutation_lock || return 0
    WD_LAST_GUARD_TS="$_now"
    WATCHDOG_RESTART_COUNT=0
    watchdog_enforce_hdp_control || log_msg "Watchdog: не удалось полностью восстановить контроль над настройками https-dns-proxy."
    watchdog_enforce_doh_authority || log_msg "Watchdog: не удалось полностью синхронизировать набор DNS Manager."
    watchdog_hdp_guard || log_msg "Watchdog: проверка экземпляров https-dns-proxy завершилась с ошибкой."
    watchdog_dns_path_guard || log_msg "Watchdog: проверка пути forced-DNS завершилась с ошибкой."
    watchdog_dnsmasq_guard || log_msg "Watchdog: проверка конфигурации dnsmasq завершилась с ошибкой."
    release_mutation_lock
    return 0
}
watchdog_embedded_loop() {
    [ "${WATCHDOG_ENABLED:-0}" = 1 ] || return 0

    # RAM-first watchdog: no catalog refresh, no persistent log writes, no
    # per-cycle runtime files. Persistent configuration is only read here.
    DNS_MANAGER_RAM_LOG=1
    mkdir -p "$STATE_DIR" 2>/dev/null || return 1
    load_config
    refresh_runtime_capabilities

    for _slot in 1 2 3 4 5 6 RU; do
        eval "WD_FAIL_${_slot}=0"
        eval "WD_MISSING_${_slot}=0"
        eval "WD_REPAIR_TS_${_slot}=0"
    done
    WD_RESTART_COUNT=0
    WATCHDOG_LAST_RESTART_TS=0
    WD_LAST_GUARD_TS="$(date +%s 2>/dev/null)"
    CHECKER_MISSING_LOGGED=0
    log_msg "Фоновый watchdog embedded/procd запущен: проверка каждые ${WATCHDOG_INTERVAL:-90}с, замена после ${WATCHDOG_FAIL_THRESHOLD:-2} последовательных циклов."

    # Give network + https-dns-proxy a short settling window after procd start/WAN-up.
    sleep 12

    while :; do
        [ "${WATCHDOG_ENABLED:-0}" = 1 ] || return 0
        _interval="${WATCHDOG_INTERVAL:-90}"
        case "$_interval" in ''|*[!0-9]*) _interval=90;; esac
        [ "$_interval" -ge 30 ] 2>/dev/null || _interval=90
        [ "$_interval" -le 600 ] 2>/dev/null || _interval=90

        if ! watchdog_resource_guard; then
            sleep "$_interval"
            continue
        fi

        if ! command -v dig >/dev/null 2>&1 && ! command -v nslookup >/dev/null 2>&1; then
            if [ "${CHECKER_MISSING_LOGGED:-0}" != 1 ]; then
                log_msg "DNS-проверка временно приостановлена: dig/nslookup недоступен. Ротацию не выполняю."
                CHECKER_MISSING_LOGGED=1
            fi
            sleep "$_interval"
            continue
        fi
        if [ "${CHECKER_MISSING_LOGGED:-0}" = 1 ]; then
            log_msg "Утилита DNS-проверки снова доступна; embedded watchdog продолжил работу."
            CHECKER_MISSING_LOGGED=0
        fi

        _checked=0
        _failed=0
        _live=0
        _missing=0
        _threshold_slots=""
        _local_recover_slots=""
        _probe_rc=0

        watchdog_refresh_listener_snapshot

        for _slot in 1 2 3 4 5 6 RU; do
            eval "_id=\${SLOT_${_slot}:-}"
            [ -n "$_id" ] || continue
            eval "_port=\${PORT_${_slot}:-}"
            [ -n "$_port" ] || continue
            case "$_slot" in RU) _domain="yandex.ru" ;; *) _domain="example.com" ;; esac

            _checked=$((_checked+1))
            if ! watchdog_listener_snapshot_has_port "$_port"; then
                _missing=$((_missing+1))
                eval "WD_FAIL_${_slot}=0"
                eval "_mc=\${WD_MISSING_${_slot}:-0}"
                _mc=$((_mc+1))
                eval "WD_MISSING_${_slot}=\$_mc"
                if [ "$_mc" -ge "${WATCHDOG_FAIL_THRESHOLD:-2}" ] 2>/dev/null; then
                    _local_recover_slots="$_local_recover_slots $_slot"
                fi
                continue
            fi

            _live=$((_live+1))
            eval "WD_MISSING_${_slot}=0"
            watchdog_light_probe "$_port" "$_domain"
            _probe_rc=$?
            [ "$_probe_rc" = 2 ] && break
            if [ "$_probe_rc" = 0 ]; then
                watchdog_loop_reset_slot "$_slot"
                continue
            fi

            _failed=$((_failed+1))
            eval "_fc=\${WD_FAIL_${_slot}:-0}"
            _fc=$((_fc+1))
            eval "WD_FAIL_${_slot}=\$_fc"
            if [ "$_fc" -ge "${WATCHDOG_FAIL_THRESHOLD:-2}" ] 2>/dev/null; then
                _threshold_slots="$_threshold_slots $_slot"
            fi
        done

        [ "$_probe_rc" = 2 ] && { sleep "$_interval"; continue; }
        [ "$_checked" -gt 0 ] || { sleep "$_interval"; continue; }

        _watchdog_action=0

        if [ "$_missing" -eq "$_checked" ] && [ "$_checked" -gt 0 ]; then
            for _slot in 1 2 3 4 5 6 RU; do watchdog_loop_reset_slot "$_slot"; done
            log_msg "Все локальные DoH-listener одновременно отсутствуют. Запрашиваю восстановление https-dns-proxy без ротации DNS."
            watchdog_service_recover_run >/dev/null 2>&1 || true
            _watchdog_action=1
            load_config
            refresh_runtime_capabilities
            WD_LAST_GUARD_TS="$(date +%s 2>/dev/null)"
            sleep 5
        elif [ -n "$_local_recover_slots" ]; then
            _local_trigger="${_local_recover_slots# }"
            log_msg "Локальный DoH-listener слота $_local_trigger отсутствует два цикла подряд. Запрашиваю восстановление https-dns-proxy без ротации DNS."
            watchdog_service_recover_run >/dev/null 2>&1 || true
            _watchdog_action=1
            load_config
            refresh_runtime_capabilities
            WD_LAST_GUARD_TS="$(date +%s 2>/dev/null)"
            for _slot in 1 2 3 4 5 6 RU; do watchdog_loop_reset_slot "$_slot"; done
            sleep 5
        elif [ "$_live" -gt 0 ] && [ "$_failed" -eq "$_live" ] && [ "$_missing" -eq 0 ]; then
            # All live DNS paths failed together: treat as WAN/upstream outage.
            # Never rotate healthy DNS choices during a common outage.
            for _slot in 1 2 3 4 5 6 RU; do watchdog_loop_reset_slot "$_slot"; done
        else
            _trigger=""
            for _slot in $_threshold_slots; do
                if watchdog_loop_repair_cooldown_ok "$_slot"; then
                    _trigger="$_slot"
                    break
                fi
            done
            if [ -n "$_trigger" ]; then
                watchdog_loop_mark_repair "$_trigger"
                log_msg "Подтверждён сбой слота $_trigger в двух последовательных циклах при живом локальном listener. Запрашиваю точечную замену."
                watchdog_slot_target_run "$_trigger" >/dev/null 2>&1 || log_msg "Точечное восстановление слота $_trigger завершилось неуспешно; повторю после новых двух циклов."
                _watchdog_action=1
                load_config
                refresh_runtime_capabilities
                WD_LAST_GUARD_TS="$(date +%s 2>/dev/null)"
                eval "WD_FAIL_${_trigger}=0"
                sleep 5
            fi
        fi

        if [ "$_watchdog_action" = 0 ] && [ "$_failed" -eq 0 ] && [ "$_missing" -eq 0 ]; then
            watchdog_embedded_integrity_guard >/dev/null 2>&1 || true
        fi

        sleep "$_interval"
    done
}

# ==========================================
# ==========================================
run_watchdog() {
    [ "${WATCHDOG_ENABLED:-0}" = 1 ] || return 0
    _wd_rc=0
    _wd_repairs=0
    WATCHDOG_RESTART_COUNT=0
    if ! watchdog_resource_guard; then
        return 0
    fi
    if ! acquire_mutation_lock; then
        return 0
    fi
    load_config
    _managed_slots=0
    for _s in 1 2 3 4 5 6 RU; do
        eval "_mid=\${SLOT_${_s}:-}"
        [ -n "$_mid" ] && _managed_slots=$((_managed_slots+1))
    done
    if [ "$_managed_slots" -eq 0 ]; then
        log_msg "Watchdog: активная схема DNS Manager не настроена; сторонний https-dns-proxy не изменяю."
        release_mutation_lock
        return 0
    fi
    sync_regional_dns_state
    cleanup_stale_tmp_dirs
    watchdog_enforce_hdp_control || log_msg "Не удалось полностью восстановить контроль над настройками https-dns-proxy."
    watchdog_enforce_doh_authority || log_msg "Не удалось полностью синхронизировать набор DNS Manager."
    watchdog_service_recover || log_msg "Не удалось выполнить восстановительное перезапускание https-dns-proxy."
    watchdog_hdp_guard || log_msg "Не удалось проверить соответствие DNS-серверов выбранному набору."
    watchdog_dns_path_guard || log_msg "Не удалось проверить путь forced-DNS в firewall."
    watchdog_dnsmasq_guard || log_msg "Не удалось полностью восстановить конфигурацию dnsmasq."
    _used="$TMP_DIR/watchdog-used-$$"
    : > "$_used"
    for _s in 1 2 3 4 5 6 RU; do
        eval "_uid=\${SLOT_${_s}:-}"
        [ -n "$_uid" ] || continue
        _u="$(normalize_url "$(dns_url "$_uid")")"
        [ -n "$_u" ] && printf '%s\n' "$_u" >> "$_used"
    done
    for _slot in 1 2 3 4 5 6 RU; do
        [ "$_wd_repairs" -lt "${WATCHDOG_MAX_REPAIRS:-1}" ] || break
        eval "_id=\${SLOT_${_slot}:-}"
        [ -n "$_id" ] || continue
        _current_cat="$(dns_cat "$_id")"
        _force_replace=0
        case "$_slot" in
            RU) ;;
            *)
                if [ -n "$_desired" ] && [ -n "$_current_cat" ] && [ "$_desired" != "$_current_cat" ]; then
                    _force_replace=1
                fi
                ;;
        esac
        if [ "$_force_replace" = 0 ] && watchdog_check_slot "$_slot"; then continue; fi
        if [ "$_force_replace" = 0 ]; then
            sleep 2
            watchdog_check_slot "$_slot" && continue
        else
            log_msg "DNS в слоте $_slot не соответствует выбранной категории ($_current_cat вместо $_desired). Ищу замену."
        fi
        log_msg "DNS в слоте $_slot: $(dns_name "$_id") требует замены. Ищу подходящий DNS той же категории."
        _tried="$TMP_DIR/watchdog-tried-${_slot}-$$"
        : > "$_tried"
        _old="$_id"
        _oldcat="$_current_cat"
        _replacement_ok=0
        _attempt=0
        while [ "$_attempt" -lt 2 ]; do
            _attempt=$((_attempt+1))
            _picked="$(watchdog_pick_replacement "$_slot" "$_used" "$_tried")"
            _repl="${_picked%%|*}"
            _repl_cat="${_picked#*|}"
            [ -n "$_repl" ] || break
            [ "$_repl" = "$_old" ] && { printf '%s\n' "$_repl" >> "$_tried"; continue; }
            printf '%s\n' "$_repl" >> "$_tried"
            printf "  ${C_YELLOW}↻ Слот %s: %s не отвечает или не соответствует профилю. Проверяю замену %s.${C_NC}\n" "$_slot" "$(dns_name "$_old")" "$(dns_name "$_repl")"
            if watchdog_apply_slot_candidate "$_slot" "$_repl" "$_repl_cat" "$_old" "$_oldcat"; then
                printf "  ${C_GREEN}✓ Слот %s: %s подтверждён на 127.0.0.1:%s.${C_NC}\n" "$_slot" "$(dns_name "$_repl")" "$(eval "printf %s \"\${PORT_${_slot}:-}\"")"
                _u="$(normalize_url "$(dns_url "$_repl")")"
                grep -qxF "$_u" "$_used" 2>/dev/null || printf '%s\n' "$_u" >> "$_used"
                _replacement_ok=1
                _wd_repairs=$((_wd_repairs+1))
                break
            fi
            printf "  ${C_RED}✗ Слот %s: %s не подтвердился через 127.0.0.1:%s.${C_NC}\n" "$_slot" "$(dns_name "$_repl")" "$(eval "printf %s \"\${PORT_${_slot}:-}\"")"
        done
        [ "$_replacement_ok" = 1 ] || _wd_rc=1
        rm -f "$_tried"
    done
    rm -f "$TMP_DIR"/watchdog-*-$$ "$TMP_DIR"/watchdog-used-$$ "$TMP_DIR"/watchdog-categories-$$ 2>/dev/null
    release_mutation_lock
    return "$_wd_rc"
}
watchdog_cron_scheduler_detect_pid() {
    WATCHDOG_CRON_PID=""
    WATCHDOG_CRON_PID_COUNT=0
    WATCHDOG_CRON_AMBIGUOUS="no"
    if command -v pidof >/dev/null 2>&1; then
        _pids="$(pidof crond 2>/dev/null)"
        for _p in $_pids; do
            case "$_p" in ''|*[!0-9]*) continue;; esac
            WATCHDOG_CRON_PID_COUNT=$((WATCHDOG_CRON_PID_COUNT+1))
            [ -n "$WATCHDOG_CRON_PID" ] || WATCHDOG_CRON_PID="$_p"
        done
    fi
    if [ "$WATCHDOG_CRON_PID_COUNT" -eq 0 ]; then
        _pscount=0
        _pspid=""
        while IFS= read -r _p; do
            case "$_p" in ''|*[!0-9]*) continue;; esac
            _pscount=$((_pscount+1))
            [ -n "$_pspid" ] || _pspid="$_p"
        done <<EOF
$(ps w 2>/dev/null | awk 'NR>1 && $0 ~ /(^|[[:space:]])([^[:space:]]*\/)?crond([[:space:]]|$)/ {print $1}')
EOF
        WATCHDOG_CRON_PID_COUNT="$_pscount"
        [ "$WATCHDOG_CRON_PID_COUNT" -gt 0 ] && WATCHDOG_CRON_PID="$_pspid"
    fi
    [ "$WATCHDOG_CRON_PID_COUNT" -gt 1 ] && WATCHDOG_CRON_AMBIGUOUS="yes"
    [ "$WATCHDOG_CRON_PID_COUNT" -gt 0 ] && WATCHDOG_CRON_RUNNING="yes" || WATCHDOG_CRON_RUNNING="no"
}
watchdog_cron_extract_cdir() {
    _src="$1"
    [ -f "$_src" ] || return 1
    _v="$(awk '{for(i=1;i<NF;i++) if($i=="-c" && $(i+1) ~ /^\//) {print $(i+1); exit}}' "$_src" 2>/dev/null)"
    case "$_v" in
        /*) printf '%s\n' "$_v"; return 0;;
    esac
    return 1
}
watchdog_cron_atomic_replace() {
    _src="$1"
    _tmp="$2"
    _before="$3"
    [ -f "$_tmp" ] || return 1
    [ -L "$_src" ] 2>/dev/null && return 2
    if [ -n "$_before" ] && [ -f "$_src" ]; then
        _current="$(file_hash "$_src" 2>/dev/null)"
        if [ -n "$_current" ] && [ "$_current" != "$_before" ]; then
            rm -f "$_tmp" 2>/dev/null || true
            return 2
        fi
    fi
    mv "$_tmp" "$_src" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null || true; return 1; }
    return 0
}
watchdog_cron_preserve_attrs() {
    _src="$1"
    _tmp="$2"
    [ -f "$_src" ] && [ -f "$_tmp" ] || return 0
    if command -v stat >/dev/null 2>&1; then
        _mode="$(stat -c '%a' "$_src" 2>/dev/null)"
        case "$_mode" in ''|*[!0-9]*) _mode="";; esac
        [ -n "$_mode" ] && chmod "$_mode" "$_tmp" 2>/dev/null || true
        _ug="$(stat -c '%u:%g' "$_src" 2>/dev/null)"
        case "$_ug" in *:*) chown "$_ug" "$_tmp" 2>/dev/null || true;; esac
    fi
}
watchdog_cron_scheduler_detect() {
    WATCHDOG_CRON_FILE=""
    WATCHDOG_CRON_DIR=""
    WATCHDOG_CRON_INIT=""
    WATCHDOG_CRON_DAEMON=""
    WATCHDOG_CRON_PID=""
    WATCHDOG_CRON_AVAILABLE="no"
    WATCHDOG_CRON_RUNNING="no"
    WATCHDOG_CRON_AMBIGUOUS="no"
    WATCHDOG_CRON_PID_COUNT=0
    WATCHDOG_CRON_BOOT_ENABLED="unknown"
    WATCHDOG_CRON_DETECT_SOURCE="none"

    for _ci in /etc/init.d/cron /etc/init.d/crond; do
        [ -x "$_ci" ] || continue
        WATCHDOG_CRON_INIT="$_ci"
        break
    done

    if [ -n "$WATCHDOG_CRON_INIT" ]; then
        if "$WATCHDOG_CRON_INIT" enabled >/dev/null 2>&1; then
            WATCHDOG_CRON_BOOT_ENABLED="yes"
        else
            WATCHDOG_CRON_BOOT_ENABLED="no"
        fi
    fi

    if command -v crond >/dev/null 2>&1; then
        WATCHDOG_CRON_DAEMON="$(command -v crond)"
    elif [ -x /usr/sbin/crond ]; then
        WATCHDOG_CRON_DAEMON="/usr/sbin/crond"
    elif [ -x /sbin/crond ]; then
        WATCHDOG_CRON_DAEMON="/sbin/crond"
    fi

    watchdog_cron_scheduler_detect_pid

    _cdir=""
    if [ "$WATCHDOG_CRON_RUNNING" = yes ]; then
        _psline="$(ps w 2>/dev/null | awk 'NR>1 && $0 ~ /(^|[[:space:]])([^[:space:]]*\/)?crond([[:space:]]|$)/ {print; exit}')"
        _cdir="$(printf '%s\n' "$_psline" | awk '{for(i=1;i<NF;i++) if($i=="-c" && $(i+1) ~ /^\//) {print $(i+1); exit}}')"
        case "$_cdir" in /*) ;; *) _cdir="";; esac
    fi
    [ -n "$_cdir" ] || [ -z "$WATCHDOG_CRON_INIT" ] || _cdir="$(watchdog_cron_extract_cdir "$WATCHDOG_CRON_INIT" 2>/dev/null)"

    _base="${TMP_DIR:-/tmp}"
    mkdir -p "$_base" 2>/dev/null || true
    _candidates="$_base/watchdog-cron-candidates-$$"
    : > "$_candidates" 2>/dev/null || _candidates=""
    [ -n "$_cdir" ] && printf '%s\n' "$_cdir" >> "$_candidates"
    if [ -f "$WATCHDOG_CRON_SCHEDULER_STATE" ]; then
        _saved_dir="$(sed -n 's/^dir=//p' "$WATCHDOG_CRON_SCHEDULER_STATE" 2>/dev/null | head -n1)"
        case "$_saved_dir" in /*) printf '%s\n' "$_saved_dir" >> "$_candidates";; esac
    fi
    printf '%s\n' "/etc/crontabs" "/var/spool/cron/crontabs" "/var/spool/cron" >> "$_candidates"
    [ -n "$WATCHDOG_CRON_INIT" ] && printf '%s\n' "/etc/crontabs" >> "$_candidates"
    if [ -n "$_candidates" ]; then
        awk 'NF && !seen[$0]++' "$_candidates" > "${_candidates}.u" 2>/dev/null && mv "${_candidates}.u" "$_candidates" 2>/dev/null || true
    fi

    _found=0
    if [ -n "$_candidates" ] && [ -f "$_candidates" ]; then
        while IFS= read -r _d; do
            [ -n "$_d" ] || continue
            [ -f "$_d/root" ] || continue
            if grep -Fqx -- "$WATCHDOG_CRON_MARKER" "$_d/root" 2>/dev/null; then
                WATCHDOG_CRON_DIR="$_d"
                WATCHDOG_CRON_FILE="$_d/root"
                _found=1
                WATCHDOG_CRON_DETECT_SOURCE="existing-marker"
                break
            fi
        done < "$_candidates"
    fi
    if [ "$_found" = 0 ] && [ -n "$_candidates" ] && [ -f "$_candidates" ]; then
        while IFS= read -r _d; do
            [ -n "$_d" ] || continue
            [ -f "$_d/root" ] || continue
            WATCHDOG_CRON_DIR="$_d"
            WATCHDOG_CRON_FILE="$_d/root"
            _found=1
            WATCHDOG_CRON_DETECT_SOURCE="existing-root"
            break
        done < "$_candidates"
    fi
    if [ "$_found" = 0 ] && [ -n "$_cdir" ]; then
        WATCHDOG_CRON_DIR="$_cdir"
        WATCHDOG_CRON_FILE="$_cdir/root"
        _found=1
        WATCHDOG_CRON_DETECT_SOURCE="process-cdir"
    fi
    if [ "$_found" = 0 ] && [ -n "$WATCHDOG_CRON_INIT" ]; then
        _vdir="$(watchdog_cron_extract_cdir "$WATCHDOG_CRON_INIT" 2>/dev/null)"
        case "$_vdir" in
            /*) WATCHDOG_CRON_DIR="$_vdir"; WATCHDOG_CRON_FILE="$_vdir/root"; _found=1; WATCHDOG_CRON_DETECT_SOURCE="init-cdir";;
        esac
    fi
    if [ "$_found" = 0 ] && [ -n "$WATCHDOG_CRON_INIT" ]; then
        WATCHDOG_CRON_DIR="/etc/crontabs"
        WATCHDOG_CRON_FILE="/etc/crontabs/root"
        _found=1
        WATCHDOG_CRON_DETECT_SOURCE="openwrt-default"
    fi

    if [ -n "$WATCHDOG_CRON_INIT" ] || [ -n "$WATCHDOG_CRON_DAEMON" ] || [ "$WATCHDOG_CRON_RUNNING" = yes ]; then
        WATCHDOG_CRON_AVAILABLE="yes"
    fi

    [ -z "$_candidates" ] || rm -f "$_candidates" "${_candidates}.u" 2>/dev/null || true

    if [ "$WATCHDOG_CRON_AVAILABLE" = yes ] && [ -n "$WATCHDOG_CRON_DIR" ]; then
        _st="${WATCHDOG_CRON_SCHEDULER_STATE}.tmp.$$"
        {
            printf 'version=1\n'
            printf 'backend=crond\n'
            printf 'init=%s\n' "$WATCHDOG_CRON_INIT"
            printf 'daemon=%s\n' "$WATCHDOG_CRON_DAEMON"
            printf 'pid=%s\n' "$WATCHDOG_CRON_PID"
            printf 'pid_count=%s\n' "$WATCHDOG_CRON_PID_COUNT"
            printf 'ambiguous=%s\n' "$WATCHDOG_CRON_AMBIGUOUS"
            printf 'dir=%s\n' "$WATCHDOG_CRON_DIR"
            printf 'boot_enabled=%s\n' "$WATCHDOG_CRON_BOOT_ENABLED"
            printf 'source=%s\n' "$WATCHDOG_CRON_DETECT_SOURCE"
        } > "$_st" 2>/dev/null && mv "$_st" "$WATCHDOG_CRON_SCHEDULER_STATE" 2>/dev/null || rm -f "$_st" 2>/dev/null
    fi
    return 0
}
watchdog_cron_scheduler_require() {
    watchdog_cron_scheduler_detect
    [ "$WATCHDOG_CRON_AMBIGUOUS" != yes ] || {
        log_msg "Cron автопроверки недоступен: обнаружено несколько одновременно работающих crond. Scheduler неоднозначен, изменения не применяются."
        return 1
    }
    [ "$WATCHDOG_CRON_AVAILABLE" = yes ] || {
        log_msg "Cron автопроверки недоступен: не найден init-сервис cron и не обнаружен демон crond."
        return 1
    }
    [ -n "$WATCHDOG_CRON_FILE" ] || {
        log_msg "Cron автопроверки недоступен: не удалось определить crontab root."
        return 1
    }
    return 0
}
watchdog_cron_scheduler_start() {
    watchdog_cron_scheduler_detect
    [ "$WATCHDOG_CRON_AVAILABLE" = yes ] || return 1
    [ "$WATCHDOG_CRON_RUNNING" = yes ] && return 0
    if [ -n "$WATCHDOG_CRON_INIT" ]; then
        log_msg "Cron не запущен. Запускаю scheduler для работы автопроверки DNS; существующие cron-задания не изменяю."
        "$WATCHDOG_CRON_INIT" start >/dev/null 2>&1 || return 1
        sleep 1
        watchdog_cron_scheduler_detect
        [ "$WATCHDOG_CRON_RUNNING" = yes ] && return 0
    fi
    return 1
}
watchdog_cron_scheduler_apply() {
    watchdog_cron_scheduler_detect
    if [ -n "$WATCHDOG_CRON_INIT" ] && [ -x "$WATCHDOG_CRON_INIT" ]; then
        "$WATCHDOG_CRON_INIT" restart >/dev/null 2>&1 && return 0
        return 1
    fi
    [ "$WATCHDOG_CRON_RUNNING" = yes ] && return 0
    return 1
}
watchdog_cron_read_state() {
    WATCHDOG_CRON_STATE_MODE="$(sed -n 's/^mode=//p' "$WATCHDOG_CRON_STATE" 2>/dev/null | head -n1)"
    WATCHDOG_CRON_STATE_LINE="$(sed -n 's/^line=//p' "$WATCHDOG_CRON_STATE" 2>/dev/null | head -n1)"
    case "$WATCHDOG_CRON_STATE_MODE" in
        owned|external|conflict) ;;
        *) WATCHDOG_CRON_STATE_MODE="";;
    esac
}
watchdog_cron_write_state() {
    _mode="$1"
    _line="$2"
    _tmp="${WATCHDOG_CRON_STATE}.tmp.$$"
    {
        printf 'version=1\n'
        printf 'mode=%s\n' "$_mode"
        printf 'line=%s\n' "$_line"
    } > "$_tmp" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
    chmod 600 "$_tmp" 2>/dev/null || true
    mv "$_tmp" "$WATCHDOG_CRON_STATE" 2>/dev/null || { rm -f "$_tmp" 2>/dev/null; return 1; }
    return 0
}
watchdog_cron_file_prepare() {
    watchdog_cron_scheduler_require || return 1
    if [ -L "$WATCHDOG_CRON_FILE" ] 2>/dev/null; then
        log_msg "Cron автопроверки: crontab root является симлинком. Изменение через DNS Manager остановлено, чтобы не заменить чужой путь."
        return 1
    fi
    if [ ! -f "$WATCHDOG_CRON_FILE" ]; then
        [ "${WATCHDOG_ENABLED:-0}" = 1 ] || return 0
        mkdir -p "$WATCHDOG_CRON_DIR" 2>/dev/null || return 1
        (umask 077; : > "$WATCHDOG_CRON_FILE") || return 1
        chmod 600 "$WATCHDOG_CRON_FILE" 2>/dev/null || true
        chown root:root "$WATCHDOG_CRON_FILE" 2>/dev/null || true
    fi
    [ -r "$WATCHDOG_CRON_FILE" ] && [ -w "$WATCHDOG_CRON_FILE" ] || return 1
    return 0
}
watchdog_cron_desired_line() {
    printf '%s\n' "*/${WATCHDOG_INTERVAL:-15} * * * * ${MANAGER_PATH} watchdog >> ${LOG_FILE} 2>&1"
}
watchdog_cron_line_exists() {
    _line="$1"
    [ -n "$_line" ] || return 1
    watchdog_cron_scheduler_detect
    [ -n "$WATCHDOG_CRON_FILE" ] && [ -f "$WATCHDOG_CRON_FILE" ] || return 1
    grep -Fqx -- "$_line" "$WATCHDOG_CRON_FILE" 2>/dev/null
}
watchdog_cron_owned_block_status() {
    _want_line="$1"
    watchdog_cron_scheduler_detect
    [ -n "$WATCHDOG_CRON_FILE" ] && [ -f "$WATCHDOG_CRON_FILE" ] || return 1
    awk -v marker="$WATCHDOG_CRON_MARKER" -v want="$_want_line" '
        $0==marker {seen=1; next}
        seen==1 {
            if ($0==want) {found=1; exit}
            seen=0
        }
        END {exit found?0:1}
    ' "$WATCHDOG_CRON_FILE" 2>/dev/null
}
watchdog_cron_marker_exists() {
    watchdog_cron_scheduler_detect
    [ -n "$WATCHDOG_CRON_FILE" ] && [ -f "$WATCHDOG_CRON_FILE" ] || return 1
    grep -Fqx -- "$WATCHDOG_CRON_MARKER" "$WATCHDOG_CRON_FILE" 2>/dev/null
}
watchdog_cron_remove_owned_block() {
    watchdog_cron_scheduler_detect
    [ -n "$WATCHDOG_CRON_FILE" ] && [ -f "$WATCHDOG_CRON_FILE" ] || { rm -f "$WATCHDOG_CRON_STATE" 2>/dev/null || true; return 0; }
    watchdog_cron_read_state
    _state_line="${WATCHDOG_CRON_STATE_LINE:-}"
    if ! watchdog_cron_marker_exists; then
        rm -f "$WATCHDOG_CRON_STATE" 2>/dev/null || true
        return 0
    fi

    _cron_before="$(file_hash "$WATCHDOG_CRON_FILE" 2>/dev/null)"
    _tmp="$WATCHDOG_CRON_FILE.dns-manager.$$"
    _owner_suffix="${MANAGER_PATH} watchdog >> ${LOG_FILE} 2>&1"

    awk -v marker="$WATCHDOG_CRON_MARKER" -v state_line="$_state_line" -v suffix="$_owner_suffix" '
        $0==marker { pending=1; next }
        pending==1 {
            # A current-version state file identifies the exact owned line.
            # For older installations, the marker plus the exact DNS Manager
            # command is sufficient to remove the legacy block safely.
            if ((state_line!="" && $0==state_line) || (index($0,suffix)>0 && $0 ~ /^\*\/[0-9]+[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*/)) {
                pending=0
                removed=1
                next
            }
            print marker
            print
            pending=0
            next
        }
        {print}
        END {
            if (pending==1) print marker
            if (removed!=1) exit 7
        }
    ' "$WATCHDOG_CRON_FILE" > "$_tmp" 2>/dev/null
    _awk_rc=$?
    if [ "$_awk_rc" -eq 7 ]; then
        rm -f "$_tmp" 2>/dev/null || true
        log_msg "Cron: маркер DNS Manager найден, но принадлежащая ему команда не подтверждена. Запись сохранена."
        return 2
    fi
    [ "$_awk_rc" -eq 0 ] || { rm -f "$_tmp" 2>/dev/null || true; return 1; }

    watchdog_cron_preserve_attrs "$WATCHDOG_CRON_FILE" "$_tmp"
    watchdog_cron_atomic_replace "$WATCHDOG_CRON_FILE" "$_tmp" "$_cron_before"
    _ar=$?
    [ "$_ar" -eq 0 ] || { rm -f "$_tmp" 2>/dev/null || true; return "$_ar"; }
    rm -f "$WATCHDOG_CRON_STATE" 2>/dev/null || true
    watchdog_cron_scheduler_apply >/dev/null 2>&1 || true
    log_tx "ROLLBACK" "watchdog" "CRON_REMOVE" "OK" "file=$WATCHDOG_CRON_FILE"
    return 0
}

watchdog_service_file_owned() {
    _wf="$1"
    _marker="$2"
    [ -f "$_wf" ] || return 1
    grep -Fqx -- "$_marker" "$_wf" 2>/dev/null
}
watchdog_service_file_matches() {
    _wf="$1"
    _marker="$2"
    _version="$3"
    watchdog_service_file_owned "$_wf" "$_marker" || return 1
    grep -Fqx -- "$_version" "$_wf" 2>/dev/null || return 1
    return 0
}
watchdog_service_install_files() {
    # DNS Manager owns this path and may replace an older or external file when enabled.
    mkdir -p "$(dirname "$WATCHDOG_SERVICE_PATH")" || return 1
    _stmp="${WATCHDOG_SERVICE_PATH}.tmp.$$"
    cat > "$_stmp" <<'EOF_DNS_WATCHDOG_SERVICE'
#!/bin/sh /etc/rc.common
# DNS_MANAGER_WATCHDOG_SERVICE=2
# DNS_MANAGER_WATCHDOG_SERVICE_VERSION=3.11.6

USE_PROCD=1
START=95
STOP=10

PROG="/usr/bin/dns-manager"
CMD="__watchdog-loop"

start_service() {
    [ -x "$PROG" ] || return 1
    [ -r /etc/dns-manager/config/manager.conf ] || return 0
    [ "$(sed -n 's/^WATCHDOG_ENABLED="\([01]\)"$/\1/p' /etc/dns-manager/config/manager.conf 2>/dev/null | head -n1)" = 1 ] || return 0
    procd_open_instance "dns-watchdog"
    procd_set_param command /bin/sh "$PROG" "$CMD"
    procd_set_param respawn 3600 5 5
    procd_set_param stdout 0
    procd_set_param stderr 1
    procd_close_instance
}

service_triggers() {
    . /lib/functions/network.sh 2>/dev/null || true
    network_flush_cache 2>/dev/null || true
    network_find_wan wan 2>/dev/null || true
    wan="${wan:-wan}"
    procd_add_interface_trigger "interface.*.up" "$wan" /etc/init.d/dns-watchdog restart
}
EOF_DNS_WATCHDOG_SERVICE
    chmod 755 "$_stmp" 2>/dev/null || { rm -f "$_stmp"; return 1; }
    mv "$_stmp" "$WATCHDOG_SERVICE_PATH" 2>/dev/null || { rm -f "$_stmp"; return 1; }

    rm -rf "$WATCHDOG_LEGACY_RUNTIME_DIR" 2>/dev/null || true
    chmod 755 "$WATCHDOG_SERVICE_PATH" 2>/dev/null || return 1
    [ -x "$WATCHDOG_SERVICE_PATH" ] || return 1
    return 0
}
watchdog_service_running() {
    [ -x "$WATCHDOG_SERVICE_PATH" ] || return 1
    "$WATCHDOG_SERVICE_PATH" running >/dev/null 2>&1
}
watchdog_service_enabled() {
    [ -x "$WATCHDOG_SERVICE_PATH" ] || return 1
    "$WATCHDOG_SERVICE_PATH" enabled >/dev/null 2>&1
}
watchdog_service_stop_disable() {
    if [ -x "$WATCHDOG_SERVICE_PATH" ]; then
        "$WATCHDOG_SERVICE_PATH" stop >/dev/null 2>&1 || true
        "$WATCHDOG_SERVICE_PATH" disable >/dev/null 2>&1 || true
        if watchdog_service_running; then
            err_msg "Служба dns-watchdog не остановилась. Изменение watchdog прекращено для безопасности."
            return 1
        fi
    fi
    return 0
}
watchdog_remove_legacy_daemon() {
    if pgrep -f "$WATCHDOG_LEGACY_DAEMON_PATH" >/dev/null 2>&1; then
        err_msg "Старый watchdog-daemon всё ещё запущен; не удаляю его до полной остановки."
        return 1
    fi
    if [ -f "$WATCHDOG_LEGACY_DAEMON_PATH" ]; then
        grep -Fqx -- "$WATCHDOG_LEGACY_DAEMON_MARKER" "$WATCHDOG_LEGACY_DAEMON_PATH" 2>/dev/null || {
            err_msg "Чужой/изменённый файл $WATCHDOG_LEGACY_DAEMON_PATH обнаружен; не удаляю его автоматически."
            return 1
        }
        rm -f "$WATCHDOG_LEGACY_DAEMON_PATH" 2>/dev/null || return 1
    fi
    return 0
}
watchdog_service_start_enable() {
    watchdog_service_install_files || return 1
    "$WATCHDOG_SERVICE_PATH" enable >/dev/null 2>&1 || return 1
    "$WATCHDOG_SERVICE_PATH" start >/dev/null 2>&1 || return 1
    sleep 1
    watchdog_service_running || return 1
    watchdog_remove_legacy_daemon || return 1
    return 0
}
watchdog_service_remove_files() {
    if [ -x "$WATCHDOG_SERVICE_PATH" ]; then
        "$WATCHDOG_SERVICE_PATH" stop >/dev/null 2>&1 || true
        "$WATCHDOG_SERVICE_PATH" disable >/dev/null 2>&1 || true
    fi
    watchdog_remove_legacy_daemon >/dev/null 2>&1 || true
    rm -f "$WATCHDOG_SERVICE_PATH" 2>/dev/null || return 1
    rm -rf "$WATCHDOG_LEGACY_RUNTIME_DIR" 2>/dev/null || true
    return 0
}
watchdog_apply_restore_previous_state() {
    WATCHDOG_ENABLED="${WATCHDOG_APPLY_OLD_DISK_ENABLED:-0}"
    WATCHDOG_BACKEND="procd"
    if [ -n "${WATCHDOG_APPLY_OLD_INTERVAL:-}" ]; then
        WATCHDOG_INTERVAL="$WATCHDOG_APPLY_OLD_INTERVAL"
    else
        WATCHDOG_INTERVAL="${WATCHDOG_CHECK_INTERVAL_DEFAULT:-90}"
    fi
    save_config >/dev/null 2>&1 || true

    if [ "${WATCHDOG_APPLY_OLD_SERVICE_PRESENT:-0}" = 1 ]; then
        if [ "${WATCHDOG_APPLY_OLD_SERVICE_ENABLED:-0}" = 1 ]; then
            "$WATCHDOG_SERVICE_PATH" enable >/dev/null 2>&1 || true
        else
            "$WATCHDOG_SERVICE_PATH" disable >/dev/null 2>&1 || true
        fi
        if [ "${WATCHDOG_APPLY_OLD_SERVICE_RUNNING:-0}" = 1 ]; then
            "$WATCHDOG_SERVICE_PATH" start >/dev/null 2>&1 || true
        else
            "$WATCHDOG_SERVICE_PATH" stop >/dev/null 2>&1 || true
        fi
    else
        watchdog_service_stop_disable >/dev/null 2>&1 || true
        rm -f "$WATCHDOG_SERVICE_PATH" 2>/dev/null || true
        if [ "${TX_WD_LEGACY_DAEMON_EXISTED:-0}" != 1 ]; then
            watchdog_remove_legacy_daemon >/dev/null 2>&1 || true
        fi
        rm -rf "$WATCHDOG_LEGACY_RUNTIME_DIR" 2>/dev/null || true
    fi
    return 0
}
watchdog_service_migrate_legacy() {
    [ "${FIRST_RUN_INITIAL:-0}" = 1 ] && return 0
    [ "${WATCHDOG_ENABLED:-0}" = 1 ] || return 0
    [ -s "$BASELINE_MANIFEST" ] || {
        log_msg "Watchdog: исходный baseline отсутствует; procd автоматически не включаю."
        return 1
    }

    _legacy_cron=0
    watchdog_cron_marker_exists >/dev/null 2>&1 && _legacy_cron=1

    _service_ready=0
    watchdog_service_file_matches "$WATCHDOG_SERVICE_PATH" "$WATCHDOG_SERVICE_MARKER" "$WATCHDOG_SERVICE_VERSION_MARKER" && _service_ready=1

    # If the service is manager-owned but old, stop it before replacing the launcher.
    if [ "$_service_ready" != 1 ] && watchdog_service_running >/dev/null 2>&1; then
        "$WATCHDOG_SERVICE_PATH" stop >/dev/null 2>&1 || return 1
        sleep 1
    fi

    if [ "$_service_ready" = 0 ]; then
        watchdog_service_install_files || return 1
    fi

    "$WATCHDOG_SERVICE_PATH" enable >/dev/null 2>&1 || return 1
    "$WATCHDOG_SERVICE_PATH" start >/dev/null 2>&1 || return 1
    sleep 1
    watchdog_service_running || return 1
    watchdog_remove_legacy_daemon || return 1

    if [ "$_legacy_cron" = 1 ]; then
        log_msg "Watchdog: обнаружен старый cron DNS Manager; выполняю однократную миграцию на embedded procd."
        watchdog_cron_remove_owned_block >/dev/null 2>&1 || {
            log_msg "Watchdog: старый cron DNS Manager не удалось удалить безопасно; watchdog оставляю выключенным."
            "$WATCHDOG_SERVICE_PATH" stop >/dev/null 2>&1 || true
            "$WATCHDOG_SERVICE_PATH" disable >/dev/null 2>&1 || true
            return 1
        }
        watchdog_cron_marker_exists >/dev/null 2>&1 && {
            log_msg "Watchdog: старый cron-маркер всё ещё присутствует; procd watchdog выключен."
            "$WATCHDOG_SERVICE_PATH" stop >/dev/null 2>&1 || true
            "$WATCHDOG_SERVICE_PATH" disable >/dev/null 2>&1 || true
            return 1
        }
        log_msg "Watchdog: миграция на embedded procd завершена."
    elif [ "$_service_ready" = 0 ]; then
        log_msg "Watchdog: embedded procd-служба DNS Manager установлена и запущена."
    fi
    return 0
}
watchdog_state_word_procd() {
    _service=0
    _enabled=0
    _running=0
    _service_file=0
    [ -x "$WATCHDOG_SERVICE_PATH" ] && watchdog_service_file_owned "$WATCHDOG_SERVICE_PATH" "$WATCHDOG_SERVICE_MARKER" && _service_file=1
    watchdog_service_enabled && _enabled=1
    watchdog_service_running && _running=1
    [ "$_service_file" = 1 ] && _service=1
    if [ "$_service" = 1 ] && [ "$_enabled" = 1 ] && [ "$_running" = 1 ]; then
        printf '1'
    elif [ "$_service" = 1 ] || [ "$_enabled" = 1 ] || [ "$_running" = 1 ]; then
        printf '2'
    else
        printf '0'
    fi
}
watchdog_slot_target_run() {
    _slot="$1"
    case "$_slot" in 1|2|3|4|5|6|RU) ;; *) return 2 ;; esac
    [ "${WATCHDOG_ENABLED:-0}" = 1 ] || return 0
    eval "_target_id=\${SLOT_${_slot}:-}"
    eval "_target_port=\${PORT_${_slot}:-}"
    [ -n "$_target_id" ] && [ -n "$_target_port" ] || return 2

    if ! watchdog_resource_guard; then
        return 0
    fi
    acquire_mutation_lock || return 0
    WATCHDOG_RESTART_COUNT=0
    _slot_rc=0
    _old_id="$_target_id"
    _old_cat="$(dns_cat "$_old_id" 2>/dev/null)"
    case "$_slot" in RU) _domain="yandex.ru" ;; *) _domain="example.com" ;; esac

    # The daemon has already seen two failures; re-check once before touching config.
    if watchdog_check_slot "$_slot"; then
        release_mutation_lock
        return 0
    fi

    _used="$TMP_DIR/watchdog-slot-used-$$"
    _tried="$TMP_DIR/watchdog-slot-tried-$$"
    : > "$_used" || { release_mutation_lock; return 1; }
    : > "$_tried" || { rm -f "$_used"; release_mutation_lock; return 1; }
    for _s in 1 2 3 4 5 6 RU; do
        eval "_uid=\${SLOT_${_s}:-}"
        [ -n "$_uid" ] || continue
        _u="$(normalize_url "$(dns_url "$_uid")")"
        [ -n "$_u" ] && printf '%s\n' "$_u" >> "$_used"
    done

    _attempt=0
    _replacement_ok=0
    while [ "$_attempt" -lt 2 ]; do
        _attempt=$((_attempt+1))
        _picked="$(watchdog_pick_replacement "$_slot" "$_used" "$_tried")"
        _repl="${_picked%%|*}"
        _repl_cat="${_picked#*|}"
        [ -n "$_repl" ] || break
        [ "$_repl" = "$_old_id" ] && { printf '%s\n' "$_repl" >> "$_tried"; continue; }
        printf '%s\n' "$_repl" >> "$_tried"
        log_msg "Watchdog slot $_slot: заменяю $(dns_name "$_old_id") на $(dns_name "$_repl")."
        if watchdog_apply_slot_candidate "$_slot" "$_repl" "$_repl_cat" "$_old_id" "$_old_cat"; then
            log_msg "Watchdog slot $_slot: замена подтверждена на 127.0.0.1:$(eval "printf %s \"\${PORT_${_slot}:-}\"")."
            _replacement_ok=1
            break
        fi
    done
    [ "$_replacement_ok" = 1 ] || _slot_rc=1
    rm -f "$_used" "$_tried"
    release_mutation_lock
    return "$_slot_rc"
}
watchdog_service_recover_run() {
    [ "${WATCHDOG_ENABLED:-0}" = 1 ] || return 0
    acquire_mutation_lock || return 0
    if ! watchdog_resource_guard; then
        release_mutation_lock
        return 0
    fi
    WATCHDOG_RESTART_COUNT=0
    watchdog_restart_hdp burst
    _rc=$?
    release_mutation_lock
    return "$_rc"
}
apply_watchdog() {
    # Stop first so a running watchdog cannot race an in-progress Apply.
    watchdog_service_stop_disable || return 1

    WATCHDOG_BACKEND="procd"
    : "${WATCHDOG_INTERVAL:=${WATCHDOG_CHECK_INTERVAL_DEFAULT:-90}}"
    save_config || return 1

    if [ "${WATCHDOG_ENABLED:-0}" = 1 ]; then
        watchdog_service_install_files || return 1
        # During a transaction the final manager.conf has not been committed yet.
        # Do not start the embedded loop until Apply commits the new configuration.
        if [ "${TX_ACTIVE:-0}" = 1 ] && [ "${DEFER_CONFIG_SAVE:-0}" = 1 ]; then
            watchdog_cron_marker_exists >/dev/null 2>&1 && watchdog_cron_remove_owned_block >/dev/null 2>&1 || true
            return 0
        fi
        "$WATCHDOG_SERVICE_PATH" enable >/dev/null 2>&1 || return 1
        "$WATCHDOG_SERVICE_PATH" start >/dev/null 2>&1 || return 1
        sleep 1
        watchdog_service_running || return 1
        watchdog_remove_legacy_daemon || return 1
        watchdog_cron_marker_exists >/dev/null 2>&1 && watchdog_cron_remove_owned_block >/dev/null 2>&1 || true
    else
        watchdog_cron_marker_exists >/dev/null 2>&1 && watchdog_cron_remove_owned_block >/dev/null 2>&1 || true
        watchdog_service_remove_files || return 1
    fi
    return 0
}

menu_dns() {
while :; do
menu_header "НАСТРОЙКА DNS"
menu_section "ГОТОВЫЕ ПРОФИЛИ"
menu_item "[1]" "Максимальный обход"
menu_item "[2]" "Максимальная скорость"
menu_item "[3]" "Максимальная безопасность"
menu_item "[4]" "Максимальная приватность"
menu_item "[5]" "Блокировка рекламы"
menu_item "[6]" "Выбор по категориям"
menu_section "РУЧНАЯ НАСТРОЙКА"
menu_item "[7]" "Серверы DNS"
menu_back
menu_prompt
safe_read c
[ -z "$c" ] && return
case "$c" in
1) apply_profile_now bypass;;
2) apply_profile_now clean;;
3) apply_profile_now security;;
4) apply_profile_now privacy;;
5) apply_profile_now adblock;;
6) menu_category_select;;
7) menu_slots;;
*) warn_msg "Неизвестный пункт."; pause;;
esac
done
}
# ==========================================
# ==========================================
main_menu() {
while :; do
menu_header "DNS Manager $VERSION"
menu_section "НАСТРОЙКА DNS"
menu_item "[1]" "Настроить DNS"
menu_section "СЕРВИСЫ"
menu_item "[2]" "Проверка DNS-серверов"
menu_item "[3]" "Состояние и журнал"
menu_item "[4]" "Серверы точного времени"
menu_item "[5]" "Сетевой тюнинг"
menu_item "[6]" "Удалить DNS Manager"
menu_section "LUCI"
_luci_state="$(check_module_state luci)"
if [ "$_luci_state" = 1 ]; then
    if [ "${LUCI_UPDATE_AVAILABLE:-0}" = 1 ]; then
        menu_item "[7]" "Обновить LuCI → ${LUCI_REMOTE_VERSION}"
    else
        menu_item "[7]" "Удалить Нативный интерфейс DNS Manager"
    fi
else
    case "$_luci_state" in
        0) menu_item "[7]" "Установить Нативный интерфейс DNS Manager" ;;
        2) menu_item "[7]" "Восстановить Нативный интерфейс DNS Manager" ;;
        *) menu_item "[7]" "Нативный интерфейс DNS Manager" ;;
    esac
fi
menu_back
menu_prompt
safe_read c
[ -z "$c" ] && { clear_screen; printf "${C_GREEN}DNS Manager завершён.${C_NC}\n"; exit 0; }
case "$c" in
2) test_dns_catalog; show_tests;;
3) show_map;;
6) uninstall_manager;;
   _luci_state="$(check_module_state luci)"
   if [ "$_luci_state" = 1 ] && [ "${LUCI_UPDATE_AVAILABLE:-0}" = 1 ]; then
       luci_companion_update; _rc=$?
       case "$_rc" in
           0) ok_msg "LuCI обновлена до версии ${LUCI_REMOTE_VERSION:-новой версии}." ;;
           2) info_msg "Новой версии LuCI нет." ;;
           *) err_msg "LuCI не удалось обновить." ;;
       esac
       pause
   elif [ "$_luci_state" = 1 ]; then
       setting_process luci "Удалить Нативный интерфейс DNS Manager" "Нативный интерфейс DNS Manager в LuCI." "$_luci_state"
   else
       setting_process luci "Нативный интерфейс DNS Manager" "Нативный интерфейс DNS Manager в LuCI." "$_luci_state"
   fi
*) warn_msg "Неизвестный пункт."; pause;;
esac
done
}
# ==========================================
expected_managed_slots() {
    _n=0
    for _s in 1 2 3 4 5 6 RU; do
        eval "_id=\${SLOT_${_s}:-}"
        [ -n "$_id" ] && _n=$((_n + 1))
    done
    printf '%s' "$_n"
}

normalize_hybrid_ports() {
    case "${DNS_PROFILE:-}" in hybrid|custom) ;; *) return 0 ;; esac

    _changed=0

    for _s in 1 2 3 4 5 6 RU; do
        eval "_id=\${SLOT_${_s}:-}"
        eval "_cur=\${PORT_${_s}:-}"

        if [ -n "$_id" ]; then
            _want="$(hybrid_desired_port "$_s")"
            if [ "$_cur" != "$_want" ]; then
                port_set "$_s" "$_want" || return 1
                _changed=1
            fi
        elif [ -n "$_cur" ]; then
            port_set "$_s" "" || return 1
            _changed=1
        fi
    done


    return 0
}

restore_persistent_test_results() {
    # Test results are runtime data only. Nothing from /etc/dns-manager/state
    # is restored into /var/run after reboot.
    return 0
}

save_persistent_test_results() {
    # Intentionally disabled: a full catalog benchmark must not wear flash.
    return 0
}

startup_self_repair() {
    [ "${DNS_MANAGER_NO_STARTUP_REPAIR:-0}" = 1 ] && return 0

    case "${DNS_PROFILE:-}" in
        hybrid|custom) ;;
        *) return 0 ;;
    esac

    normalize_hybrid_ports

    run_discovery >/dev/null 2>&1 || true

    _expected="$(expected_managed_slots)"
    [ "$_expected" -gt 0 ] || return 0

    _need=0

    if [ "$DOH_TOTAL" != "$_expected" ] || [ "$DOH_MATCH" != "$_expected" ]; then
        _need=1
    fi

    if [ "$DOH_TOTAL" -gt 0 ] && [ "${HDP_RUNNING:-no}" != yes ]; then
        _need=1
    fi

    if [ "$_need" = 0 ]; then
        _sec="$(get_dnsmasq_section)"
        if [ -n "$_sec" ]; then
            _exp="$(watchdog_expected_servers)"
            _act="$TMP_DIR/startup-actual-servers-$$"
            : > "$_act"

            uci -q get "dhcp.$_sec.server" 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -u > "$_act"

            if [ -s "$_exp" ] && ! cmp -s "$_act" "$_exp" 2>/dev/null; then
                _need=1
            fi

            rm -f "$_act" "$_exp" 2>/dev/null
        fi
    fi

    [ "$_need" = 1 ] || return 0

    log_msg "Startup: обнаружено расхождение конфигурации. Выполняю автоматическое восстановление."

    WATCHDOG_LAST_RESTART_TS=0

    if acquire_mutation_lock; then
        watchdog_enforce_hdp_control || true
        watchdog_enforce_doh_authority || true
        watchdog_service_recover || true
        watchdog_hdp_guard || true
        watchdog_dns_path_guard || true
        watchdog_dnsmasq_guard || true
        release_mutation_lock
    fi

    run_discovery >/dev/null 2>&1 || true

    _expected2="$(expected_managed_slots)"
    if [ "$_expected2" -gt 0 ] && { [ "$DOH_TOTAL" != "$_expected2" ] || [ "$DOH_MATCH" != "$_expected2" ]; }; then
        log_msg "Startup: после восстановления набор DNS ещё не синхронизирован; запускаю один контрольный watchdog-проход."
        run_watchdog >/dev/null 2>&1 || true
        run_discovery >/dev/null 2>&1 || true
    fi

    return 0
}

# ==========================================
# STARTUP UPDATE CHECK
# ==========================================
startup_update_check() {
    if [ "${DNS_MANAGER_NO_UPDATE:-0}" = 1 ]; then luci_companion_check_update >/dev/null 2>&1 || true; return 0; fi
    printf "\n${C_CYAN}${C_BOLD}↻ Проверяю обновление DNS Manager...${C_NC}\n"
    auto_update_manager
    _rc=$?
    case "${AUTO_UPDATE_RESULT:-unknown}" in
        current) info_msg "Проверка обновления: версия $VERSION актуальна." ;;
        updated) info_msg "DNS Manager обновлён до версии $VERSION." ;;
        throttled|disabled) info_msg "Проверка обновления пропущена по ограничению частоты." ;;
        skipped) info_msg "Проверка обновления пропущена: условия обновления не выполнены." ;;
        failed) warn_msg "Проверка обновления не удалась. Продолжаю запуск текущей версии $VERSION." ;;
        busy) info_msg "Проверка обновления уже выполняется другим процессом; продолжаю запуск версии $VERSION." ;;
        *) [ "$_rc" -eq 0 ] && info_msg "Проверка обновления завершена. Используется версия $VERSION." || warn_msg "Проверка обновления завершилась с кодом $_rc. Продолжаю запуск текущей версии." ;;
    esac
    luci_companion_check_update >/dev/null 2>&1 || true
    return 0
}
# ==========================================
# STARTUP REQUIRED FUNCTION CHECK
# ==========================================
startup_required_function_check() {
    for _fn in get_dnsmasq_section exact_list_has doh_selected_config_current validate_selected_slots ensure_dnsmasq_balancer web_access_pid_count detect_forced_dns_path clear_all_doh_for_apply rebuild_selected_hdp_sections reconcile_dnsmasq apply_ntp_ip_fallback luci_component_state luci_companion_check_update luci_companion_install luci_companion_remove luci_companion_update watchdog_embedded_loop watchdog_service_install_files watchdog_service_remove_files; do
        type "$_fn" >/dev/null 2>&1 || {
            printf "${C_RED}[✗] Критическая ошибка: отсутствует функция $_fn. Запуск остановлен до изменения настроек роутера.${C_NC}\n"
            return 1
        }
    done
    return 0
}

# ==========================================
# ==========================================
case "${1:-}" in
force-state|--force-state)
    preflight_readonly
    init_dirs
    load_config
    startup_required_function_check || exit 1
    refresh_runtime_capabilities
    check_module_state force
    exit $?
    ;;
update-check|--update-check)
    preflight_readonly
    init_dirs
    write_catalogs >/dev/null 2>&1 || true
    load_config
    DNS_MANAGER_FORCE_UPDATE=1 DNS_MANAGER_UPDATE_NO_EXEC=1 auto_update_manager --force
    case "${AUTO_UPDATE_RESULT:-failed}" in
        updated) exit 0 ;;
        current|throttled) exit 2 ;;
        busy|failed|skipped|disabled) exit 1 ;;
        *) exit 3 ;;
    esac
    ;;
auto-update|--auto-update)
    preflight_readonly
    init_dirs
    DNS_MANAGER_SCHEDULED_UPDATE=1 DNS_MANAGER_UPDATE_NO_EXEC=1 auto_update_manager --scheduled
    exit 0
    ;;
uninstall|--uninstall|remove|--remove)
    preflight_readonly
    init_dirs
    write_catalogs >/dev/null 2>&1 || true
    load_config
    uninstall_manager
    exit $?
    ;;
watchdog-slot|--watchdog-slot)
    preflight_readonly
    init_dirs
    load_config
    startup_required_function_check || exit 1
    DNS_MANAGER_RAM_LOG=1
    refresh_runtime_capabilities
    watchdog_slot_target_run "$2"
    exit $?
    ;;
watchdog-service-recover|--watchdog-service-recover)
    preflight_readonly
    init_dirs
    load_config
    startup_required_function_check || exit 1
    DNS_MANAGER_RAM_LOG=1
    refresh_runtime_capabilities
    watchdog_service_recover_run
    exit $?
    ;;
watchdog|--watchdog|-w)
    DNS_MANAGER_RAM_LOG=1
    preflight_readonly
    init_dirs
    load_config
    startup_required_function_check || exit 1
    refresh_runtime_capabilities
    log_msg "Запуск одноразовой проверки DNS."
    run_watchdog
    exit $?
    ;;
__watchdog-loop)
    preflight_readonly
    init_dirs
    load_config
    startup_required_function_check || exit 1
    refresh_runtime_capabilities
    watchdog_embedded_loop
    exit $?
    ;;
esac

preflight_readonly
init_dirs
write_catalogs
load_config
startup_required_function_check || exit 1
startup_update_check
run_discovery

if [ "${FIRST_RUN_INITIAL:-0}" = 1 ]; then
    # Initialization only: do not synchronize or mutate cron on first launch.
    info_msg "Первый запуск: watchdog-служба procd не запускается и cron не изменяю."
fi

log_msg "Запуск DNS Manager. Версия $VERSION. OpenWrt=$SYS_OWRT; платформа=$SYS_TARGET; архитектура=$SYS_ARCH; firewall=$SYS_FW; backend=$FIREWALL_BACKEND; wan_network=${FIREWALL_WAN_NETWORK:-unknown}"

if [ "${FIRST_RUN_INITIAL:-0}" = 1 ]; then
    if mkdir -p "$CFG_DIR" 2>/dev/null && {
        printf 'version=%s\n' "$VERSION"
        printf 'completed_at=%s\n' "$(date +%s)"
    } > "${FIRST_RUN_MARKER}.tmp.$$" 2>/dev/null; then
        chmod 600 "${FIRST_RUN_MARKER}.tmp.$$" 2>/dev/null || true
        if mv "${FIRST_RUN_MARKER}.tmp.$$" "$FIRST_RUN_MARKER" 2>/dev/null; then
            FIRST_RUN=0
            info_msg "Первичная инициализация завершена. Watchdog procd и cron оставлены без изменений до явного включения автопроверки."
        else
            rm -f "${FIRST_RUN_MARKER}.tmp.$$" 2>/dev/null || true
            warn_msg "Не удалось сохранить маркер первого запуска. Watchdog procd и cron останутся защищёнными до следующего запуска."
        fi
    else
        rm -f "${FIRST_RUN_MARKER}.tmp.$$" 2>/dev/null || true
        warn_msg "Не удалось сохранить маркер первого запуска. Watchdog procd и cron останутся защищёнными до следующего запуска."
    fi
fi

# Existing installations: move watchdog from cron to procd only after a valid baseline exists.
# FIRST_RUN_INITIAL is immutable for this invocation, so first launch never migrates cron.
if [ "${FIRST_RUN_INITIAL:-0}" = 0 ] && [ "${WATCHDOG_ENABLED:-0}" = 1 ]; then
    watchdog_service_migrate_legacy >/dev/null 2>&1 || warn_msg "Не удалось завершить переход watchdog с cron на procd. Состояние watchdog оставлено без самовольной ротации DNS."
fi

main_menu
