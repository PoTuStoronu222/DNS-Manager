#!/bin/sh
# A self-update can exec this script while the previous process had stdout/stderr
# redirected. Restore an interactive TTY only when stdin is itself a terminal;
# cron/RPC launches remain untouched.
if [ -t 0 ] && [ ! -t 1 ] && [ -r /dev/tty ] && [ -w /dev/tty ]; then
    exec </dev/tty >/dev/tty 2>&1
fi
MANAGER_PATH="/usr/bin/dns-manager"
VERSION="3.43"
# 3.38: clear the LuCI update flag after a successful CLI update.
BASE_DIR="/etc/dns-manager"
CFG_DIR="$BASE_DIR/config"
STATE_DIR="/var/run/dns-manager"
LOG_FILE="/var/log/dns-manager.log"
TX_LOG="/var/log/dns-manager.tx"
CONFIG_FILE="$CFG_DIR/manager.conf"
DNS_CATALOG="$CFG_DIR/dns-catalog.conf"
NTP_CATALOG="$CFG_DIR/ntp-catalog.conf"
BOOTSTRAP_DNS_ALL="77.88.8.8,77.88.8.1,94.140.14.14,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112,208.67.222.222,208.67.220.220,149.112.121.10,149.112.122.10,76.76.2.0,76.76.10.0,194.242.2.2,194.242.2.3,2606:4700:4700::1111,2606:4700:4700::1001,2001:4860:4860::8888,2001:4860:4860::8844,2620:fe::fe,2620:fe::9"
DNSCAT_VERSION="8.6-RU-NOSOCIAL"
DNSCAT_REVISION="2"
DNSCAT_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/catalogs/dns-8.5-RU-NOSOCIAL.conf"
WATCHDOG_RESTART_COOLDOWN=300
WATCHDOG_BACKEND="procd"
WATCHDOG_CHECK_INTERVAL_DEFAULT=600
WATCHDOG_FAIL_THRESHOLD=2
WATCHDOG_REPAIR_COOLDOWN=1800
WATCHDOG_GUARD_INTERVAL=3600
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
OWNERSHIP="$CFG_DIR/ownership.conf"
PACKAGE_OWNERSHIP="$CFG_DIR/package-ownership.conf"
TEST_RESULTS="$STATE_DIR/dns-test-results.conf"
TEST_LOCK_DIR="$STATE_DIR/dns-test.lock"
TEST_LOCK_HELD=0
FIREWALL_OWNERSHIP="$CFG_DIR/firewall-ownership.conf"
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
LUCI_COMPANION_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager-luci.sh"
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
    AUTO_UPDATE_REASON=""
    if [ "${DNS_MANAGER_NO_UPDATE:-0}" = 1 ] && [ "${DNS_MANAGER_FORCE_UPDATE:-0}" != 1 ]; then
        return 0
    fi
    AUTO_UPDATE_RESULT="started"

    [ -n "${AUTO_UPDATE_LOCK_DIR:-}" ] || AUTO_UPDATE_LOCK_DIR="$STATE_DIR/auto-update.lock"
    if ! acquire_auto_update_lock; then
        AUTO_UPDATE_RESULT="busy"
        return 0
    fi

    _scheduled=0
    [ "${DNS_MANAGER_SCHEDULED_UPDATE:-0}" = 1 ] && _scheduled=1
    if [ "$_scheduled" = 1 ] && [ "${DNS_MANAGER_FORCE_UPDATE:-0}" != 1 ]; then
        _upd_now="$(date +%s 2>/dev/null || printf 0)"
        _upd_last="$(cat "$AUTO_UPDATE_LAST_CHECK_FILE" 2>/dev/null || true)"
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
        *) AUTO_UPDATE_RESULT="skipped"; release_auto_update_lock; return 0 ;;
    esac
    [ -f "$MANAGER_PATH" ] || { AUTO_UPDATE_RESULT="skipped"; release_auto_update_lock; return 0; }
    [ -w "${MANAGER_PATH%/*}" ] || { AUTO_UPDATE_RESULT="skipped"; release_auto_update_lock; return 0; }
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1 && ! command -v uclient-fetch >/dev/null 2>&1; then
        AUTO_UPDATE_RESULT="skipped"; release_auto_update_lock; return 0
    fi

    _upd_tmp="/tmp/dns-manager-update-$$"
    _upd_syntax="${_upd_tmp}.syntax"
    UPDATE_TMP_FILE="$_upd_tmp"
    rm -f "$_upd_tmp" "$_upd_syntax" 2>/dev/null || true
    _update_url="${UPDATE_URL}?_dmcb=$(date +%s 2>/dev/null || printf 0)-$$"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 4 --max-time 15 -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "$_upd_tmp" "$_update_url" >/dev/null 2>&1 || { AUTO_UPDATE_RESULT="failed"; AUTO_UPDATE_REASON="не удалось скачать файл с GitHub"; rm -f "$_upd_tmp" "$_upd_syntax"; UPDATE_TMP_FILE=""; release_auto_update_lock; return 0; }
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 15 --header="Cache-Control: no-cache" --header="Pragma: no-cache" -O "$_upd_tmp" "$_update_url" >/dev/null 2>&1 || { AUTO_UPDATE_RESULT="failed"; AUTO_UPDATE_REASON="не удалось скачать файл с GitHub"; rm -f "$_upd_tmp" "$_upd_syntax"; UPDATE_TMP_FILE=""; release_auto_update_lock; return 0; }
    else
        uclient-fetch -q -T 15 -O "$_upd_tmp" "$_update_url" >/dev/null 2>&1 || { AUTO_UPDATE_RESULT="failed"; AUTO_UPDATE_REASON="не удалось скачать файл с GitHub"; rm -f "$_upd_tmp" "$_upd_syntax"; UPDATE_TMP_FILE=""; release_auto_update_lock; return 0; }
    fi

    [ -s "$_upd_tmp" ] || { AUTO_UPDATE_RESULT="failed"; AUTO_UPDATE_REASON="GitHub вернул пустой файл"; rm -f "$_upd_tmp" "$_upd_syntax"; UPDATE_TMP_FILE=""; release_auto_update_lock; return 0; }
    head -n 1 "$_upd_tmp" 2>/dev/null | grep -q "^#!/bin/sh" || { AUTO_UPDATE_RESULT="failed"; AUTO_UPDATE_REASON="загруженный файл не начинается с #!/bin/sh"; rm -f "$_upd_tmp" "$_upd_syntax"; UPDATE_TMP_FILE=""; release_auto_update_lock; return 0; }
    _new_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$_upd_tmp" 2>/dev/null | head -n1)"
    [ -n "$_new_version" ] || { AUTO_UPDATE_RESULT="failed"; AUTO_UPDATE_REASON="в загруженном файле не найдена VERSION"; rm -f "$_upd_tmp" "$_upd_syntax"; UPDATE_TMP_FILE=""; release_auto_update_lock; return 0; }
    sh -n "$_upd_tmp" 2>"$_upd_syntax" || { AUTO_UPDATE_RESULT="failed"; AUTO_UPDATE_REASON="syntax-check"; rm -f "$_upd_tmp" "$_upd_syntax"; UPDATE_TMP_FILE=""; release_auto_update_lock; return 0; }

    _upd_now="$(date +%s 2>/dev/null || printf 0)"
    case "$_upd_now" in ''|*[!0-9]*) _upd_now="";; esac
    [ -n "$_upd_now" ] && printf "%s\n" "$_upd_now" > "$AUTO_UPDATE_LAST_CHECK_FILE" 2>/dev/null || true

    _new_hash="$(file_hash "$_upd_tmp")"
    _old_hash="$(file_hash "$MANAGER_PATH")"
    if [ "$_new_version" = "$VERSION" ] && { [ -z "$_new_hash" ] || [ -z "$_old_hash" ] || [ "$_new_hash" = "$_old_hash" ]; }; then
        AUTO_UPDATE_RESULT="current"; rm -f "$_upd_tmp" "$_upd_syntax"; UPDATE_TMP_FILE=""; release_auto_update_lock; return 0
    fi
    if [ "$_new_version" != "$VERSION" ] && ! _ver_newer "$_new_version" "$VERSION"; then
        AUTO_UPDATE_RESULT="current"; rm -f "$_upd_tmp" "$_upd_syntax"; UPDATE_TMP_FILE=""; release_auto_update_lock; return 0
    fi

    if [ "$_new_version" = "$VERSION" ]; then
        log_msg "Автообновление: версия $VERSION та же, но содержимое отличается. Синхронизирую файл."
    else
        log_msg "Автообновление: найдено обновление $VERSION → $_new_version. Устанавливаю."
    fi
    if cp -f "$_upd_tmp" "$MANAGER_PATH" 2>/dev/null && chmod 755 "$MANAGER_PATH" 2>/dev/null; then
        sync 2>/dev/null || true
        rm -f "$_upd_tmp" "$_upd_syntax" 2>/dev/null || true
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
    rm -f "$_upd_tmp" "$_upd_syntax" 2>/dev/null || true
    UPDATE_TMP_FILE=""
    release_auto_update_lock
    return 0
}
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
    mkdir -p "$CFG_DIR" "$STATE_DIR" 2>/dev/null || return 1
    if [ -n "${TMP_DIR:-}" ]; then
        mkdir -p "$TMP_DIR" 2>/dev/null || return 1
    fi
    [ -f "$OWNERSHIP" ] || { (umask 077; : > "$OWNERSHIP") 2>/dev/null || return 1; }
    chmod 600 "$OWNERSHIP" 2>/dev/null || true
}
# ==========================================
# ==========================================
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
# procd watchdog tuning is persisted in manager.conf and validated on load.
# The defaults below remain the safe baseline for small OpenWrt routers.
WATCHDOG_BACKEND="procd"
: "${WATCHDOG_INTERVAL:=${WATCHDOG_CHECK_INTERVAL_DEFAULT:-600}}"
case "$WATCHDOG_INTERVAL" in
    ''|*[!0-9]*) WATCHDOG_INTERVAL="${WATCHDOG_CHECK_INTERVAL_DEFAULT:-600}" ;;
    *)
        [ "$WATCHDOG_INTERVAL" -ge 60 ] 2>/dev/null || WATCHDOG_INTERVAL="${WATCHDOG_CHECK_INTERVAL_DEFAULT:-600}"
        [ "$WATCHDOG_INTERVAL" -le 3600 ] 2>/dev/null || WATCHDOG_INTERVAL="${WATCHDOG_CHECK_INTERVAL_DEFAULT:-600}"
        ;;
esac
: "${WATCHDOG_FAIL_THRESHOLD:=2}"
case "$WATCHDOG_FAIL_THRESHOLD" in
    ''|*[!0-9]*) WATCHDOG_FAIL_THRESHOLD=2 ;;
    *) [ "$WATCHDOG_FAIL_THRESHOLD" -ge 1 ] 2>/dev/null && [ "$WATCHDOG_FAIL_THRESHOLD" -le 5 ] 2>/dev/null || WATCHDOG_FAIL_THRESHOLD=2 ;;
esac
: "${WATCHDOG_REPAIR_COOLDOWN:=300}"
case "$WATCHDOG_REPAIR_COOLDOWN" in
    ''|*[!0-9]*) WATCHDOG_REPAIR_COOLDOWN=300 ;;
    *) [ "$WATCHDOG_REPAIR_COOLDOWN" -ge 300 ] 2>/dev/null && [ "$WATCHDOG_REPAIR_COOLDOWN" -le 7200 ] 2>/dev/null || WATCHDOG_REPAIR_COOLDOWN=300 ;;
esac
: "${WATCHDOG_MAX_REPAIRS:=1}"
case "$WATCHDOG_MAX_REPAIRS" in
    ''|*[!0-9]*) WATCHDOG_MAX_REPAIRS=1 ;;
    *) [ "$WATCHDOG_MAX_REPAIRS" -ge 1 ] 2>/dev/null && [ "$WATCHDOG_MAX_REPAIRS" -le 3 ] 2>/dev/null || WATCHDOG_MAX_REPAIRS=1 ;;
esac
: "${WATCHDOG_MAX_RESTARTS:=2}"
case "$WATCHDOG_MAX_RESTARTS" in
    ''|*[!0-9]*) WATCHDOG_MAX_RESTARTS=2 ;;
    *) [ "$WATCHDOG_MAX_RESTARTS" -ge 1 ] 2>/dev/null && [ "$WATCHDOG_MAX_RESTARTS" -le 5 ] 2>/dev/null || WATCHDOG_MAX_RESTARTS=2 ;;
esac
: "${WATCHDOG_MAX_CANDIDATES:=3}"
case "$WATCHDOG_MAX_CANDIDATES" in
    ''|*[!0-9]*) WATCHDOG_MAX_CANDIDATES=3 ;;
    *) [ "$WATCHDOG_MAX_CANDIDATES" -ge 1 ] 2>/dev/null && [ "$WATCHDOG_MAX_CANDIDATES" -le 10 ] 2>/dev/null || WATCHDOG_MAX_CANDIDATES=3 ;;
esac
: "${WATCHDOG_GUARD_INTERVAL:=900}"
case "$WATCHDOG_GUARD_INTERVAL" in
    ''|*[!0-9]*) WATCHDOG_GUARD_INTERVAL=900 ;;
    *) [ "$WATCHDOG_GUARD_INTERVAL" -ge 300 ] 2>/dev/null && [ "$WATCHDOG_GUARD_INTERVAL" -le 3600 ] 2>/dev/null || WATCHDOG_GUARD_INTERVAL=900 ;;
esac
: "${SLOT_1:=}"; : "${SLOT_2:=}"; : "${SLOT_3:=}"; : "${SLOT_4:=}"; : "${SLOT_5:=}"; : "${SLOT_6:=}"
: "${SLOT_RU:=}"
: "${SLOT_1_CAT:=}"; : "${SLOT_2_CAT:=}"; : "${SLOT_3_CAT:=}"; : "${SLOT_4_CAT:=}"; : "${SLOT_5_CAT:=}"; : "${SLOT_6_CAT:=}"
: "${SLOT_RU_CAT:=}"
: "${PORT_1:=}"; : "${PORT_2:=}"; : "${PORT_3:=}"; : "${PORT_4:=}"; : "${PORT_5:=}"; : "${PORT_6:=}"
: "${PORT_RU:=}"
: "${TLD_RU_ENABLED:=1}"; : "${FORCE_DOH:=0}"
: "${NTP_IP_FALLBACK:=1}"; : "${DNSMASQ_PERF:=0}"
: "${BALANCER_ENABLED:=1}"; : "${NTP_PRESET:=vniiftri_moscow}"; : "${NTP_PRESET_USER_SET:=0}"; : "${DNS_PROFILE:=hybrid}"; : "${DNS_SELECTION_MODE:=quick}"; : "${DNS_SELECTION_CATEGORY:=bypass}"
: "${QUICK_PREF_1:=}"; : "${QUICK_PREF_2:=}"; : "${QUICK_PREF_3:=}"; : "${QUICK_PREF_4:=}"; : "${QUICK_PREF_5:=}"; : "${QUICK_PREF_6:=}"
: "${WATCHDOG_ENABLED:=0}"
: "${TEST_RESULTS_MAX_AGE_BYPASS:=21600}"; : "${TEST_RESULTS_MAX_AGE_CLEAN:=21600}"
: "${TEST_RESULTS_MAX_AGE_SECURITY:=21600}"; : "${TEST_RESULTS_MAX_AGE_PRIVACY:=21600}"
: "${TEST_RESULTS_MAX_AGE_ADBLOCK:=21600}"; : "${TEST_RESULTS_MAX_AGE_FAMILY:=21600}"
: "${TEST_RESULTS_MAX_AGE_REGIONAL:=21600}"
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
    for _slot in 1 2 3 4 5 6 RU; do
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
WATCHDOG_FAIL_THRESHOLD="$WATCHDOG_FAIL_THRESHOLD"
WATCHDOG_REPAIR_COOLDOWN="$WATCHDOG_REPAIR_COOLDOWN"
WATCHDOG_MAX_REPAIRS="$WATCHDOG_MAX_REPAIRS"
WATCHDOG_MAX_RESTARTS="$WATCHDOG_MAX_RESTARTS"
WATCHDOG_MAX_CANDIDATES="$WATCHDOG_MAX_CANDIDATES"
WATCHDOG_GUARD_INTERVAL="$WATCHDOG_GUARD_INTERVAL"
TEST_RESULTS_MAX_AGE="$TEST_RESULTS_MAX_AGE"
TEST_RESULTS_MAX_AGE_BYPASS="$TEST_RESULTS_MAX_AGE_BYPASS"
TEST_RESULTS_MAX_AGE_CLEAN="$TEST_RESULTS_MAX_AGE_CLEAN"
TEST_RESULTS_MAX_AGE_SECURITY="$TEST_RESULTS_MAX_AGE_SECURITY"
TEST_RESULTS_MAX_AGE_PRIVACY="$TEST_RESULTS_MAX_AGE_PRIVACY"
TEST_RESULTS_MAX_AGE_ADBLOCK="$TEST_RESULTS_MAX_AGE_ADBLOCK"
TEST_RESULTS_MAX_AGE_FAMILY="$TEST_RESULTS_MAX_AGE_FAMILY"
TEST_RESULTS_MAX_AGE_REGIONAL="$TEST_RESULTS_MAX_AGE_REGIONAL"
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
HDP_RUNNING="no"; pgrep -f '[h]ttps-dns-proxy' >/dev/null 2>&1 && HDP_RUNNING="yes"
IPV4_ROUTE="no"; ip -4 route show default 2>/dev/null | grep -q . && IPV4_ROUTE="yes"
IPV6_ROUTE="no"; ip -6 route show default 2>/dev/null | grep -q . && IPV6_ROUTE="yes"
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
WAN_PROTO="$(uci -q get network.wan.proto 2>/dev/null)"
[ -n "$WAN_PROTO" ] || {
    firewall_resolve_zones >/dev/null 2>&1 || true
    [ -n "${FIREWALL_WAN_NETWORK:-}" ] && WAN_PROTO="$(uci -q get "network.$FIREWALL_WAN_NETWORK.proto" 2>/dev/null)"
}
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
firewall_section_owned_redirect() {
    _sec="$1"
    _src="$2"; _proto="$3"; _src_dport="$4"; _dest_ip="$5"; _dest_port="$6"; _target="$7"
    uci -q get "firewall.$_sec" >/dev/null 2>&1 || return 1
    dns_redirect_rule_matches "$_sec" "$_src" "$_proto" "$_src_dport" "$_dest_ip" "$_dest_port" "$_target"
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
            # https-dns-proxy legitimately creates redirect :53 when
            # port 53 is already listening (typically dnsmasq). That is still
            # its own forced-DNS firewall rule, not an inactive path.
            if (port == "" || (port == "53" && $0 !~ /ubus:https-dns-proxy/)) next
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
    _exp="$(force_dns_list_normalize "$(force_dns_expected_src_interfaces)")"
    _cur="$(force_dns_list_normalize "$(uci -q get https-dns-proxy.config.force_dns_src_interface 2>/dev/null)")"
    [ -n "$_exp" ] && [ "$_cur" = "$_exp" ]
}
force_dns_ports_match_expected() {
    _cur="$(force_dns_list_normalize "$(uci -q get https-dns-proxy.config.force_dns_port 2>/dev/null)")"
    [ "$_cur" = "53 853" ]
}
steer_dns_upstream_ready() {
    [ "${STEER_DNS_ACTIVE:-0}" = 1 ] || return 1
    _sec="$(get_dnsmasq_section)"
    [ -n "$_sec" ] || return 1
    _expected="$(watchdog_expected_servers 2>/dev/null || true)"
    [ -n "$_expected" ] || return 1
    _actual="$TMP_DIR/steer-dns-actual-$$"
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
# to separate DNS Manager from external forced-DNS without
# consulting ownership files.
detect_forced_dns_path() {
    FORCED_DNS_ACTIVE=0
    FORCED_DNS_EXTERNAL=0
    FORCED_DNS_SOURCE="none"
    FORCED_DNS_TARGETS=""
    _manager_force_cfg=0
    _external=0
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
                elif [ "$_manager_force_cfg" = 1 ] && printf '%s\n' "$_line" | grep -q 'ubus:https-dns-proxy'; then
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

    if [ "$_external" = 1 ]; then
        FORCED_DNS_EXTERNAL=1
        FORCED_DNS_SOURCE="внешний сервис"
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
selected_general_category() {
    # Classify only the six general DoH slots. RU is a separate regional route.
    _sgc_common=""
    _sgc_count=0
    for _sgc_slot in 1 2 3 4 5 6; do
        eval "_sgc_id=\${SLOT_${_sgc_slot}:-}"
        [ -n "$_sgc_id" ] || continue
        _sgc_cat="$(dns_cat "$_sgc_id" 2>/dev/null || true)"
        case "$_sgc_cat" in
            bypass|clean|security|privacy|adblock|family) ;;
            *) printf "%s\n" custom; return 0 ;;
        esac
        if [ -z "$_sgc_common" ]; then
            _sgc_common="$_sgc_cat"
        elif [ "$_sgc_common" != "$_sgc_cat" ]; then
            printf "%s\n" custom
            return 0
        fi
        _sgc_count=$((_sgc_count+1))
    done
    if [ "$_sgc_count" -gt 0 ]; then
        printf "%s\n" "$_sgc_common"
    else
        printf "%s\n" none
    fi
}
sync_profile_from_selected_categories() {
    _spc="$(selected_general_category)"
    case "$_spc" in
        bypass|clean|security|privacy|adblock|family)
            DNS_PROFILE="hybrid"
            DNS_SELECTION_MODE="profile"
            DNS_SELECTION_CATEGORY="$_spc"
            ;;
        custom|none)
            DNS_PROFILE="custom"
            DNS_SELECTION_MODE="manual"
            DNS_SELECTION_CATEGORY="none"
            ;;
    esac
    printf "%s\n" "$_spc"
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
ipx="$(dig +short "@$bs" "$host" A +time=1 +tries=1 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print;exit}')"
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
    ipx="$(dig +short "$host" A +time=1 +tries=1 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print;exit}')"
    [ -n "$ipx" ] || ipx="$(dig +short "$host" A +tcp +time=1 +tries=1 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print;exit}')"
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
# Individual checks must be self-contained. The catalog runner pre-creates
# this immutable query for parallel workers, while a standalone test_one call
# may arrive without that file. Create it on demand instead of turning a valid
# unassigned DNS into a false "unavailable" result.
if [ ! -s "$q" ]; then
    printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$q" 2>/dev/null || {
        printf '%s\n' "$id|$cat|$name|-1|INTERNAL_TEST_QUERY_CREATE_FAIL" > "$TMP_DIR/t.$id"
        rm -f "$body" "$hdr"
        return
    }
fi
_ips=""
# Resolve all available A records through the trusted bootstrap DNS set first.
# Keep the existing per-IP DoH check below; one successful address is enough.
if [ "$HAS_DIG" = yes ]; then
    for _bs in $(printf '%s' "$BOOTSTRAP_DNS" | tr ',' ' '); do
        _chunk="$(dig +short "@$_bs" "$host" A +time=1 +tries=1 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print}' | head -n 4)"
        if [ -n "$_chunk" ]; then
            _ips="$_chunk"
            break
        fi
    done
fi
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
    # The DNS test must always hit the DoH endpoint directly. In particular,
    # an rpcd/LuCI environment must not inherit HTTP(S)/SOCKS proxy settings or
    # curlrc rules, otherwise a dead resolver can be replaced by a proxy response.
    result="$(curl -q --noproxy '*' -sS -o "$body" -D "$hdr" -w '%{http_code}|%{time_total}|%{errormsg}'  --connect-timeout 1 --max-time 3 --resolve "$host:$port:$ipx"  -H 'Content-Type: application/dns-message' -H 'Accept: application/dns-message'  --data-binary "@$q" "$url" 2>/dev/null)"
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
    _test_scope="${1:-all}"
    case "$_test_scope" in
        all|bypass|clean|security|privacy|adblock|family) ;;
        *) _test_scope=all ;;
    esac
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
    _test_source="$TMP_DIR/test-source-$$"
    if [ "$_test_scope" = all ]; then
        grep -v '^#' "$DNS_CATALOG" 2>/dev/null | grep '|' > "$_test_source" || : > "$_test_source"
        _test_scope_label="весь каталог"
    else
        awk -F'|' -v c="$_test_scope" 'NF>=5 && $1 !~ /^#/ && ($2==c || $2=="regional") {print}' "$DNS_CATALOG" > "$_test_source" 2>/dev/null || : > "$_test_source"
        _test_scope_label="категорию «$(category_ru "$_test_scope")» и региональные DNS"
    fi
    total="$(wc -l < "$_test_source" 2>/dev/null | tr -d ' ')"
    case "$total" in ''|*[!0-9]*) total=0;; esac
    [ "$total" -gt 0 ] || { rm -f "$_test_source"; release_test_lock; warn_msg "В выбранной области проверки нет DNS-серверов."; return 1; }
    printf "${C_WHITE}Проверяю %s DNS-серверов: %s. Это может занять до 5 минут...${C_NC}\n" "$total" "$_test_scope_label"
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
            if [ $((n % TEST_PROGRESS_EVERY)) -eq 0 ]; then
                test_progress
            fi
        fi
    done < "$_test_source"
    wait

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
        printf 'test_scope=%s\n' "$_test_scope"
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
    rm -f "$TMP_DIR"/t.* "$TMP_DIR"/q.* "$TMP_DIR"/body.* "$TMP_DIR"/h.* "$_test_source" 2>/dev/null || true
release_test_lock
return 0
)

# ==========================================
# ==========================================
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
# ==========================================
# ==========================================
ntp_current_preset() {
_cur="$(uci -q get system.ntp.server 2>/dev/null || true)"
_cur="$(printf '%s
' "$_cur" | awk '{$1=$1; print}')"
[ -n "$_cur" ] || { printf 'none'; return 0; }
_expected="0.openwrt.pool.ntp.org 1.openwrt.pool.ntp.org 2.openwrt.pool.ntp.org 3.openwrt.pool.ntp.org"
[ "$_cur" = "$_expected" ] && { printf 'openwrt_default'; return 0; }
for _p in cf_ip nist_ip google_ip vniiftri_moscow; do
    _expected="$(ntp_servers_for_profile "$_p")"
    [ "$_cur" = "$_expected" ] && { printf '%s' "$_p"; return 0; }
done
printf 'other'
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
printf "\n${C_YELLOW}${C_BOLD}Выбранный набор:${C_NC} ${C_YELLOW}${C_BOLD}%s${C_NC}\n\n" "$(case "$(ntp_current_preset)" in cf_ip) printf "Cloudflare";; nist_ip) printf "NIST";; vniiftri_moscow) printf "ВНИИФТРИ";; google_ip) printf "Google";; openwrt_default) printf "Стандарт OpenWrt";; other) printf "ДРУГОЕ";; *) printf "Не выбран";; esac)"
menu_item "[1]" "ВНИИФТРИ — российские серверы времени (по IP)"
menu_item "[2]" "NIST — серверы точного времени"
menu_item "[3]" "Cloudflare — серверы времени по IP"
menu_item "[4]" "Google — серверы времени по IP"
menu_back
menu_prompt
safe_read c
_old_ntp_preset="$NTP_PRESET"
case "$c" in
1) NTP_PRESET="vniiftri_moscow";;
2) NTP_PRESET="nist_ip";;
3) NTP_PRESET="cf_ip";;
4) NTP_PRESET="google_ip";;
*) return;;
esac
if ! confirm_action "Применить выбранный набор NTP?"; then
    NTP_PRESET="$_old_ntp_preset"
    info_msg "Отменено. Настройки роутера не изменены."
    pause
    return
fi
if apply_ntp_ip_fallback; then
    NTP_PRESET_USER_SET=1
    save_config
else
    NTP_PRESET="$_old_ntp_preset"
    save_config >/dev/null 2>&1 || true
    err_msg "Не удалось применить выбранный набор NTP. Предыдущий выбор сохранён."
fi
pause
}
# ==========================================
# ==========================================
# ==========================================
find_doh_by_url() {
    awk -F'|' -v u="$(normalize_url "$1")" '$5==u{print $1"|"$2"|"$3"|"$4"|"$5;exit}' "$DOH_INV"
}
port_used_anywhere() {
    p="$1"
    [ -n "$p" ] || return 1

    if [ -s "$LISTENERS" ] && grep -qE "(:|\])$p([[:space:]]|$)" "$LISTENERS" 2>/dev/null; then
        return 0
    fi

    if listener_port_exists "$p"; then
        return 0
    fi

    awk -F'|' -v p="$p" '$2==p{found=1} END{exit found?0:1}' "$DOH_INV" 2>/dev/null
}
port_reserved_tx() {
p="$1"
for rp in $TX_RESERVED_PORTS; do [ "$rp" = "$p" ] && return 0; done
return 1
}
claim_port_tx() {
p="$1"
port_reserved_tx "$p" && return 1
TX_RESERVED_PORTS="$TX_RESERVED_PORTS $p"
return 0
}
FREE_PORT_RESULT=""
free_port() {
FREE_PORT_RESULT=""
p=5053
while [ "$p" -le 5099 ]; do
port_reserved_tx "$p" && { p=$((p+1)); continue; }
port_used_anywhere "$p"; rc=$?
[ "$rc" = 2 ] && return 2
if [ "$rc" = 1 ]; then
claim_port_tx "$p" || { p=$((p+1)); continue; }
FREE_PORT_RESULT="$p"
return 0
fi
p=$((p+1))
done
return 1
}
# ==========================================
# DNSMASQ / UCI LIST HELPERS
# ==========================================
validate_selected_slots() {
    _urls="$TMP_DIR/selected-urls"
    _ports="$TMP_DIR/selected-ports"
    : > "$_urls"; : > "$_ports"
    for s in 1 2 3 4 5 6 RU; do
        eval "_id=\${SLOT_$s}"
        [ -n "$_id" ] || continue
        _u="$(normalize_url "$(dns_url "$_id")")"
        [ -n "$_u" ] || { err_msg "Слот $s содержит DNS без URL."; return 1; }
        if [ "$DNS_PROFILE" = hybrid ]; then
            _validate_scope=all
            case "${DNS_SELECTION_MODE:-}" in
                profile)
                    _validate_scope="${DNS_SELECTION_CATEGORY:-all}"
                    ;;
                quick)
                    _validate_scope=bypass
                    ;;
            esac
            ensure_test_results_fresh "$_validate_scope" || return 1
            _tested_ok="$(awk -F'|' -v id="$_id" 'NF>=5 && $1==id && $5=="OK" && $4 ~ /^[0-9]+$/ {print "yes"; exit}' "$TEST_RESULTS" 2>/dev/null)"
            if [ "$_tested_ok" != yes ]; then
                err_msg "DNS «$(dns_name "$_id")» не прошёл последнюю полную проверку. Он не может быть применён."
                return 1
            fi
        fi
        if grep -qxF "$_u" "$_urls" 2>/dev/null; then
            err_msg "Один и тот же адрес DNS-сервера выбран несколько раз: $(dns_name "$_id")."
            return 1
        fi
        printf '%s\n' "$_u" >> "$_urls"
    done
    return 0
}

ensure_dnsmasq_balancer() {
    _sec="$(get_dnsmasq_section)"
    [ -n "$_sec" ] || return 1
    _changed=0
    if [ "$(uci -q get "dhcp.$_sec.allservers" 2>/dev/null)" != 1 ]; then
        uci set "dhcp.$_sec.allservers=1" || return 1
        _changed=1
        record_own "dnsmasq" "allservers" 1 "section=$_sec"
    fi
    if [ "$(uci -q get "dhcp.$_sec.strictorder" 2>/dev/null)" != 0 ]; then
        uci set "dhcp.$_sec.strictorder=0" || return 1
        _changed=1
        record_own "dnsmasq" "strictorder" 0 "section=$_sec"
    fi
    if [ "$(uci -q get "dhcp.$_sec.noresolv" 2>/dev/null)" != 1 ]; then
        uci set "dhcp.$_sec.noresolv=1" || return 1
        _changed=1
        record_own "dnsmasq" "noresolv" 1 "section=$_sec"
    fi
    if [ "$_changed" = 1 ]; then
        uci commit dhcp || return 1
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
        sleep 2
        ok_msg "Одновременный опрос DNS включён и проверен."
    fi
    [ "$(uci -q get "dhcp.$_sec.allservers" 2>/dev/null)" = 1 ] || return 1
    [ "$(uci -q get "dhcp.$_sec.strictorder" 2>/dev/null)" = 0 ] || return 1
    [ "$(uci -q get "dhcp.$_sec.noresolv" 2>/dev/null)" = 1 ] || return 1
    return 0
}

get_dnsmasq_section() {
    _secs="$(uci show dhcp 2>/dev/null | sed -n 's/^dhcp\.\([^.=]*\)=dnsmasq$/\1/p')"
    for _s in $_secs; do
        _iface="$(uci -q get "dhcp.$_s.interface" 2>/dev/null)"
        [ "$_iface" = "lan" ] && { printf '%s' "$_s"; return 0; }
    done
    _s="$(printf '%s\n' $_secs | head -n1)"
    [ -n "$_s" ] && { printf '%s' "$_s"; return 0; }
    printf '%s' '@dnsmasq[0]'
}
exact_list_has() {
    _target="$1"
    _val="$2"
    [ -n "$_target" ] || return 1
    [ -n "$_val" ] || return 1
    uci -q get "$_target" 2>/dev/null | tr ' ' '\n' | sed 's/^['"'"'\"]//; s/['"'"'\"]$//' | grep -qxF -- "$_val"
}
# Module state is determined only from STOCK OpenWrt, CURRENT values and DESIRED values.
uci_value_normalized() {
    _uv="$(uci -q get "$1" 2>/dev/null || true)"
    [ -n "$_uv" ] && printf '%s' "$_uv" || printf '__DM_UNSET__'
}
stock_uci_value_normalized() {
    _sv_pkg="$1"
    _sv_target="$2"
    _sv_fallback="$3"
    if [ -r "/rom/etc/config/$_sv_pkg" ]; then
        _sv="$(uci -q -c /rom/etc/config get "$_sv_target" 2>/dev/null || true)"
        [ -n "$_sv" ] && { printf '%s' "$_sv"; return 0; }
        printf '__DM_UNSET__'
        return 0
    fi
    printf '%s' "$_sv_fallback"
}
# Effective stock value: an unset option in the immutable OpenWrt image is
# replaced by the caller-supplied protocol default for state detection.

# ==========================================
# ==========================================
clear_all_doh_for_apply() {
    # DNS Manager is the authoritative owner of the DoH configuration.
    # This function is called only after doh_selected_config_current() found
    # a real difference, so a repeated Apply does not rebuild an identical set.
    apply_progress "Пересобираю DNS-секции https-dns-proxy: текущая схема отличается от выбранной."
    _removed=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[0]" >/dev/null 2>&1; do
        _u="$(uci -q get "https-dns-proxy.@https-dns-proxy[0].resolver_url" 2>/dev/null)"
        [ -n "$_u" ] && apply_progress "Удаляется DNS-секция: $_u"
        uci -q delete "https-dns-proxy.@https-dns-proxy[0]" || return 1
        _removed=$((_removed+1))
    done
    uci commit https-dns-proxy || return 1
    : > "$DOH_INV"
    DOH_TOTAL=0
    DOH_MATCH=0
    DOH_OTHER=0
    disc_listeners
    disc_dns
    apply_progress_ok "Старых DNS-секций удалено: $_removed. Устанавливается полный набор DNS Manager."
}
record_own() {
    _own_line="$(printf '%s|%s|%s|%s' "$1" "$2" "$3" "$4")"
    grep -Fqx -- "$_own_line" "$OWNERSHIP" 2>/dev/null || printf '%s\n' "$_own_line" >> "$OWNERSHIP"
}
sync_hdp_force_contract() {
    _want="${1:-0}"
    case "$_want" in 0|1) ;; *) return 1 ;; esac
    [ -f /etc/config/https-dns-proxy ] || return 0

    # Match the shared / LuCI https-dns-proxy "forced DNS" contract
    # exactly. DNS Manager is authoritative here: an existing external setup
    # is deliberately replaced with this shared configuration.
    firewall_resolve_zones >/dev/null 2>&1 || true

    detect_steer_dns_path >/dev/null 2>&1 || true

    # Steer already owns LAN:53 -> :5300. Do not create a second forced-DNS path.
    if [ "${STEER_DNS_ACTIVE:-0}" = 1 ]; then
        if [ "$_want" = 1 ]; then
            for _k in force_dns notrack_dns force_dns_port force_dns_src_interface; do
                uci -q delete "https-dns-proxy.config.$_k" || true
            done
            uci set https-dns-proxy.config.force_ip_family="auto" || return 1
            uci set https-dns-proxy.config.dnsmasq_config_update="-" || return 1
            uci commit https-dns-proxy || return 1
            if [ -x /etc/init.d/https-dns-proxy ] && /etc/init.d/https-dns-proxy running >/dev/null 2>&1; then
                /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || return 1
            fi
            ensure_dns_dot_block || return 1
            reconcile_dnsmasq || return 1
            if [ -x /etc/init.d/dnsmasq ]; then /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1; fi
        else
            for _k in force_dns notrack_dns force_dns_port force_dns_src_interface force_ip_family dnsmasq_config_update; do
                uci -q delete "https-dns-proxy.config.$_k" || true
            done
            uci commit https-dns-proxy || return 1
            remove_dns_dot_block || return 1
            if [ -x /etc/init.d/https-dns-proxy ] && /etc/init.d/https-dns-proxy running >/dev/null 2>&1; then
                /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
            fi
        fi
        return 0
    fi

    # Rebuild the main section from the shared contract so stray/foreign
    # stray options cannot leave a configuration that only partially matches the shared contract.
    _main_opts="$(uci -q show https-dns-proxy.config 2>/dev/null | sed -n 's/^https-dns-proxy\.config\.\([^.=]*\)=.*/\1/p' | sort -u)"
    for _opt in $_main_opts; do
        case "$_opt" in
            dnsmasq_config_update|force_dns|notrack_dns|force_dns_port|force_dns_src_interface|procd_trigger_wan6|heartbeat_domain|heartbeat_sleep_timeout|heartbeat_wait_timeout|user|group|listen_addr|force_ip_family|canary_domains_icloud|canary_domains_mozilla) ;;
            *) uci -q delete "https-dns-proxy.config.$_opt" || true ;;
        esac
    done
    uci set https-dns-proxy.config.dnsmasq_config_update='*' || return 1
    uci set https-dns-proxy.config.force_dns="$_want" || return 1
    uci set https-dns-proxy.config.notrack_dns='1' || return 1
    uci set https-dns-proxy.config.procd_trigger_wan6='0' || return 1
    uci set https-dns-proxy.config.heartbeat_domain='heartbeat.mossdef.org' || return 1
    uci set https-dns-proxy.config.heartbeat_sleep_timeout='10' || return 1
    uci set https-dns-proxy.config.heartbeat_wait_timeout='10' || return 1
    uci set https-dns-proxy.config.user='nobody' || return 1
    uci set https-dns-proxy.config.group='nogroup' || return 1
    uci set https-dns-proxy.config.listen_addr='127.0.0.1' || return 1
    uci set https-dns-proxy.config.force_ip_family='auto' || return 1

    uci -q delete https-dns-proxy.config.force_dns_port >/dev/null 2>&1 || true
    for _p in 53 853; do
        uci add_list https-dns-proxy.config.force_dns_port="$_p" || return 1
    done

    uci -q delete https-dns-proxy.config.force_dns_src_interface >/dev/null 2>&1 || true
    _force_src_nets="$(force_dns_expected_src_interfaces)"
    for _n in $_force_src_nets; do
        [ -n "$_n" ] || continue
        uci add_list https-dns-proxy.config.force_dns_src_interface="$_n" || return 1
    done

    if [ "$_want" = 1 ]; then
        uci set https-dns-proxy.config.canary_domains_icloud='1' || return 1
        uci set https-dns-proxy.config.canary_domains_mozilla='1' || return 1
    else
        uci -q delete https-dns-proxy.config.canary_domains_icloud >/dev/null 2>&1 || true
        uci -q delete https-dns-proxy.config.canary_domains_mozilla >/dev/null 2>&1 || true
    fi

    uci commit https-dns-proxy || return 1

    if [ "$_want" = 1 ]; then
        ensure_dns_dot_block || return 1
    else
        remove_dns_dot_block || return 1
    fi

    if [ -x /etc/init.d/https-dns-proxy ] && /etc/init.d/https-dns-proxy running >/dev/null 2>&1; then
        /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || return 1
    fi
    return 0
}

configure_hdp_manager_control() {
    # Core/profile-only DNS operations must not modify independent Settings.
    # Forced-DNS is synchronized only during the full settings apply path.
    [ "${CORE_ONLY:-0}" = 1 ] && return 0
    [ "${PROFILE_APPLY:-0}" = 1 ] && return 0
    sync_hdp_force_contract "${FORCE_DOH:-0}"
}
ensure_doh_slot() {
slot="$1"; id="$2"; [ -n "$id" ] || return 0
url="$(normalize_url "$(dns_url "$id")")"; name="$(dns_name "$id")"
[ -n "$url" ] || return 1
local desired=""
[ "$DNS_PROFILE" = "hybrid" ] && desired="$(hybrid_desired_port "$slot")"
local existing_own
existing_own="$(find_doh_by_url "$url")"
if [ -n "$existing_own" ]; then
local sec_idx="$(printf '%s' "$existing_own" | cut -d'|' -f1)"
local current="$(printf '%s' "$existing_own" | cut -d'|' -f2)"
local target="$current"
if [ -n "$desired" ] && [ "$current" != "$desired" ]; then
port_used_anywhere "$desired"; rc=$?
if [ "$rc" = 2 ]; then
err_msg "Не удалось проверить порт $desired для $name."
return 1
elif [ "$rc" = 1 ]; then
target="$desired"
else
free_port || return 1
target="$FREE_PORT_RESULT"
fi
elif [ -z "$desired" ]; then
target="$current"
fi
if port_reserved_tx "$target" && [ "$target" != "$current" ]; then
free_port || return 1
target="$FREE_PORT_RESULT"
fi
if [ "$target" != "$current" ]; then
if [ -n "$sec_idx" ]; then
uci set "https-dns-proxy.@https-dns-proxy[$sec_idx].listen_port=$target" || return 1
uci set "https-dns-proxy.@https-dns-proxy[$sec_idx].listen_addr=127.0.0.1" || return 1
else
err_msg "Не найден идентификатор секции DNS-сервер для $name"
return 1
fi
fi
port_set "$slot" "$target" || return 1
[ "${APPLY_OUTPUT_QUIET:-0}" = 1 ] || printf "  ${C_GREEN}+ %s → 127.0.0.1:%s${C_NC}\n" "$name" "$target"
return 0
fi
local target="$desired"
if [ -n "$target" ]; then
port_used_anywhere "$target"; rc=$?
[ "$rc" = 2 ] && { err_msg "Не удалось проверить порт $target."; return 1; }
[ "$rc" = 0 ] && target=""
fi
if [ -z "$target" ]; then
free_port || return 1
target="$FREE_PORT_RESULT"
else
if ! claim_port_tx "$target"; then
free_port || return 1
target="$FREE_PORT_RESULT"
fi
fi
local sec
sec="$(uci add https-dns-proxy https-dns-proxy 2>/dev/null)" || return 1
local b_list="$(printf '%s' "$BOOTSTRAP_DNS")"
[ -z "$b_list" ] && b_list="1.1.1.1"
uci set "https-dns-proxy.$sec.bootstrap_dns=$b_list" || return 1
uci set "https-dns-proxy.$sec.listen_port=$target" || return 1
uci set "https-dns-proxy.$sec.listen_addr=127.0.0.1" || return 1
uci set "https-dns-proxy.$sec.resolver_url=$url" || return 1
uci set "https-dns-proxy.$sec.request_timeout=2" || return 1
record_own "doh" "$target" "$url" "slot=$slot;name=$name"
port_set "$slot" "$target" || return 1
[ "${APPLY_OUTPUT_QUIET:-0}" = 1 ] || printf "  ${C_GREEN}+ %s → 127.0.0.1:%s${C_NC}\n" "$name" "$target"
}
normalize_ownership_snapshot() {
    [ -f "$OWNERSHIP" ] || return 0
    _own_tmp="$TMP_DIR/ownership-normalized-$$"
    : > "$_own_tmp" || return 1
    while IFS='|' read -r _ot _ok _ov _od; do
        [ -n "$_ot" ] || continue
        case "$_ot|$_ok" in
            dnsmasq\|server)
                dnsmasq_manager_server_owned "$_ov" && printf '%s|%s|%s|%s\n' "$_ot" "$_ok" "$_ov" "$_od" >> "$_own_tmp"
                ;;
            doh)
                _live=0
                for _os in 1 2 3 4 5 6 RU; do
                    eval "_oid=\${SLOT_${_os}:-}"
                    eval "_op=\${PORT_${_os}:-}"
                    [ -n "$_oid" ] && [ -n "$_op" ] || continue
                    _ou="$(normalize_url "$(dns_url "$_oid")")"
                    _norm_ov="$(normalize_url "$_ov")"
                    if [ "$_op" = "$_ok" ] && [ "$_ou" = "$_norm_ov" ]; then
                        _live=1
                        break
                    fi
                done
                [ "$_live" = 1 ] && printf '%s|%s|%s|%s\n' "$_ot" "$_ok" "$_ov" "$_od" >> "$_own_tmp"
                ;;
            *)
                printf '%s|%s|%s|%s\n' "$_ot" "$_ok" "$_ov" "$_od" >> "$_own_tmp"
                ;;
        esac
    done < "$OWNERSHIP"
    mv "$_own_tmp" "$OWNERSHIP" 2>/dev/null || rm -f "$_own_tmp" 2>/dev/null
    return 0
}
dnsmasq_manager_server_owned() {
    _val="$1"
    [ -n "$_val" ] || return 1
    # Ownership is derived from the current DNS Manager selection. The
    for _s in 1 2 3 4 5 6; do
        eval "_p=\${PORT_$_s:-}"
        [ -n "$_p" ] && [ "$_val" = "127.0.0.1#$_p" ] && return 0
    done
    if [ -n "${PORT_RU:-}" ]; then
        case "$_val" in
            /ru/127.0.0.1#${PORT_RU}|/su/127.0.0.1#${PORT_RU}|/xn--p1ai/127.0.0.1#${PORT_RU}) return 0 ;;
        esac
    fi
    # Legacy Hybrid ports remain recognised so an upgrade can safely clean
    # an older manager installation without trusting its stale journal.
    case "$_val" in
        127.0.0.1#505[3-9]|/ru/127.0.0.1#505[3-9]|/su/127.0.0.1#505[3-9]|/xn--p1ai/127.0.0.1#505[3-9]) return 0 ;;
    esac
    return 1
}
reconcile_dnsmasq() {
    sec="$(get_dnsmasq_section)"
    uci -q get "dhcp.$sec" >/dev/null 2>&1 || return 1
    # On a clean OpenWrt baseline DNS Manager is authoritative for upstream DNS.
    # Rebuild the server list from scratch so stale entries from an earlier apply
    # cannot survive. Full rollback is handled by the baseline snapshot.
    uci -q delete "dhcp.$sec.server" >/dev/null 2>&1 || true
    for s in 1 2 3 4 5 6; do
        eval "id=\${SLOT_$s}"; eval "p=\${PORT_$s}"
        [ -n "$id" ] && [ -n "$p" ] || continue
        val="127.0.0.1#$p"
        exact_list_has "dhcp.$sec.server" "$val" || {
            uci add_list "dhcp.$sec.server=$val" || return 1
        }
        record_own "dnsmasq" "server" "$val" "section=$sec"
    done
    if [ "$TLD_RU_ENABLED" = 1 ] && [ -n "$SLOT_RU" ] && [ -n "$PORT_RU" ]; then
        for t in /ru /su /xn--p1ai; do
            val="$t/127.0.0.1#$PORT_RU"
            exact_list_has "dhcp.$sec.server" "$val" || uci add_list "dhcp.$sec.server=$val" || return 1
            record_own "dnsmasq" "server" "$val" "section=$sec"
        done
    fi
    if ! exact_list_has "dhcp.$sec.confdir" /etc/dnsmasq.d; then
        uci add_list "dhcp.$sec.confdir=/etc/dnsmasq.d" || return 1
        record_own "dnsmasq" "confdir" /etc/dnsmasq.d "section=$sec"
    fi
    if [ "$BALANCER_ENABLED" = 1 ]; then
        uci set "dhcp.$sec.allservers=1" || return 1
        uci set "dhcp.$sec.strictorder=0" || return 1
    else
        uci -q delete "dhcp.$sec.allservers" || true
        uci -q delete "dhcp.$sec.strictorder" || true
    fi
    uci set "dhcp.$sec.noresolv=1" || return 1
    uci commit dhcp || return 1
}
# ==========================================
# FIREWALL AUDIT HELPERS
# ==========================================
# These helpers are bookkeeping only. Runtime decisions are made from the
# actual UCI/fw4/fw3 configuration, never from this registry as authority.
firewall_owner_remove() {
    _sec="$1"
    [ -f "$FIREWALL_OWNERSHIP" ] || return 0
    _tmp="${FIREWALL_OWNERSHIP}.tmp.$$"
    grep -Fvx -- "$_sec" "$FIREWALL_OWNERSHIP" > "$_tmp" 2>/dev/null || :
    mv "$_tmp" "$FIREWALL_OWNERSHIP" 2>/dev/null || { rm -f "$_tmp"; return 1; }
    return 0
}
# ==========================================
# ==========================================
firewall_find_exact_rule_signature() {
    _type="$1"; _skip="$2"; _port="$3"
    _secs="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=rule$/\1/p')"
    for _sec in $_secs; do
        [ "$_sec" = "$_skip" ] && continue
        [ "$(uci -q get "firewall.$_sec.disabled" 2>/dev/null)" = 1 ] && continue
        case "$_type" in
            dot)
                firewall_ref_matches_zone "$(uci -q get "firewall.$_sec.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" || continue
                firewall_ref_matches_zone "$(uci -q get "firewall.$_sec.dest" 2>/dev/null)" "$FIREWALL_WAN_ZONE" || continue
                [ "$(uci -q get "firewall.$_sec.proto" 2>/dev/null)" = 'tcp udp' ] || continue
                [ "$(uci -q get "firewall.$_sec.dest_port" 2>/dev/null)" = 853 ] || continue
                [ "$(uci -q get "firewall.$_sec.target" 2>/dev/null)" = REJECT ] || continue
                ;;
            web)
                firewall_ref_matches_zone "$(uci -q get "firewall.$_sec.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" || continue
                [ "$(uci -q get "firewall.$_sec.proto" 2>/dev/null)" = tcp ] || continue
                [ "$(uci -q get "firewall.$_sec.dest_port" 2>/dev/null)" = "$_port" ] || continue
                [ "$(uci -q get "firewall.$_sec.target" 2>/dev/null)" = ACCEPT ] || continue
                ;;
            *) continue ;;
        esac
        printf '%s\n' "$_sec"
        return 0
    done
    return 1
}

apply_wait_message() {
    _label="$1"
    printf "\n${C_YELLOW}${C_BOLD}⏳ ПОДОЖДИТЕ${C_NC}: %s...\n" "${_label:-Применяю настройки}"
    printf ""
}
_apply_extras_now_impl() {

    case "$1" in
        balance|tld)
            reconcile_dnsmasq || return 1
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
            ;;
        ntp)
            [ "$NTP_IP_FALLBACK" = 1 ] || return 0
            apply_ntp_ip_fallback || return 1
            ;;
        force)
            if [ "${FORCE_DOH:-0}" = 1 ]; then
                apply_dns_force || return 1
            else
                remove_dns_force || return 1
            fi
            # https-dns-proxy reload already marks the firewall config
            # for re-generation; do not perform a second full firewall reload.
            # Forced-DNS changes are fully represented by the applied UCI/firewall
            # state. Do not run the full router discovery here.
            save_config || return 1
            return 0
            ;;
        dnsmasq_perf)
            if [ "$DNSMASQ_PERF" = 1 ]; then
                apply_dnsmasq_perf || return 1
            else
                remove_dnsmasq_perf || return 1
            fi
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
            ;;
    esac
    run_discovery || return 1
    save_config || return 1
    return 0
}

apply_extras_now() {
    # Profiles never apply independent Settings modules.
    if [ "${PROFILE_APPLY:-0}" = 1 ]; then
        log_msg "Профиль DNS не может применять дополнительные настройки; операция отклонена."
        return 1
    fi
    acquire_mutation_lock || return 1
    _rc=0
    _apply_extras_now_impl "$1" || _rc=$?
    release_mutation_lock
    return "$_rc"
}

apply_dnsmasq_perf() {
    [ "${DNSMASQ_PERF:-0}" = 1 ] || return 0
    sec="$(get_dnsmasq_section)"
    [ -n "$sec" ] || return 1
    # This module changes one thing only: dnsmasq cachesize.
    # No other dnsmasq tuning options belong to this module.
    uci set "dhcp.$sec.cachesize=$DNSMASQ_CACHE_SIZE" || return 1
    uci commit dhcp || return 1
}
remove_dnsmasq_perf() {
    sec="$(get_dnsmasq_section)" || return 1
    _stock_v="$(stock_uci_value_normalized dhcp "dhcp.@dnsmasq[0].cachesize" "1000")"
    if [ "$_stock_v" = "__DM_UNSET__" ]; then
        uci -q delete "dhcp.$sec.cachesize" || true
    else
        uci set "dhcp.$sec.cachesize=$_stock_v" || return 1
    fi
    uci commit dhcp >/dev/null 2>&1 || return 1
    return 0
}
apply_dns_force() {
    [ "${FORCE_DOH:-0}" = 1 ] || return 0
    sync_hdp_force_contract 1
}

remove_dns_force() {
    # The shared forced-DNS contract switches only
    # force_dns to 0 when interception is disabled.
    sync_hdp_force_contract 0
}
url_host() {
    _u="${1#https://}"
    _u="${_u%%/*}"
    case "$_u" in
        \[* )
            _rest="${_u#\[}"
            _h="${_rest%%\]*}"
            printf '%s' "$_h"
            ;;
        *:*) printf '%s' "${_u%%:*}" ;;
        *) printf '%s' "$_u" ;;
    esac
}
url_port() {
    _u="${1#https://}"
    _u="${_u%%/*}"
    case "$_u" in
        \[* )
            _rest="${_u#\[}"
            case "$_rest" in
                *\]:[0-9]*) printf '%s' "${_rest##*:}" ;;
                *) printf '443' ;;
            esac
            ;;
        *:[0-9]*) printf '%s' "${_u##*:}" ;;
        *) printf '443' ;;
    esac
}
# ==========================================
# ==========================================
verify_applied_doh_config() {
    # Profile verification is limited to the DNS instances selected/applied by the profile.
    # The IP-family option belongs to the independent Forced-DNS settings contract and is
    # validated by check_module_state force instead. A profile must not fail merely
    # because that optional setting is absent or uses the package default.
    _expected="$TMP_DIR/expected-doh-map"
    _actual="$TMP_DIR/actual-doh-map"
    : > "$_expected" || return 1
    : > "$_actual" || return 1
    for s in 1 2 3 4 5 6 RU; do
        eval "_id=\${SLOT_${s}:-}"
        eval "_p=\${PORT_${s}:-}"
        [ -n "$_id" ] || continue
        [ -n "$_p" ] || { err_msg "Слот $s: не определён боевой порт."; return 1; }
        _u="$(normalize_url "$(dns_url "$_id")")"
        [ -n "$_u" ] || { err_msg "Слот $s: у выбранного DNS отсутствует URL."; return 1; }
        printf '%s|%s|%s\n' "$s" "$_p" "$_u" >> "$_expected"
    done
    _i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$_i]" >/dev/null 2>&1; do
        _p="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].listen_port" 2>/dev/null)"
        _u="$(normalize_url "$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].resolver_url" 2>/dev/null)")"
        printf '%s|%s\n' "$_p" "$_u" >> "$_actual"
        [ "$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].listen_addr" 2>/dev/null)" = "127.0.0.1" ] || {
            err_msg "секция DNS $_i не ограничена 127.0.0.1."; return 1;
        }
        _i=$((_i+1))
    done
    _expected_n="$(wc -l < "$_expected" 2>/dev/null | tr -d ' ')"
    _actual_n="$(wc -l < "$_actual" 2>/dev/null | tr -d ' ')"
    [ "$_expected_n" = "$_actual_n" ] || {
        err_msg "После применения найдено $_actual_n DNS-серверов вместо $_expected_n."; return 1;
    }
    while IFS='|' read -r _slot _port _url; do
        [ -n "$_url" ] || continue
        grep -qxF "$_port|$_url" "$_actual" 2>/dev/null || {
            err_msg "Слот $_slot не совпадает с настроенным DNS-сервером."; return 1;
        }
    done < "$_expected"
    return 0
}
listener_port_exists() {
    _lp="$1"
    [ -n "$_lp" ] || return 1
    if command -v ss >/dev/null 2>&1; then
        ss -lntu 2>/dev/null | grep -Eq "(^|[[:space:]])(127\\.0\\.0\\.1|0\\.0\\.0\\.0|\\[::\\]|::):${_lp}([[:space:]]|$)" && return 0
        ss -lnut 2>/dev/null | grep -Eq "(^|[[:space:]])(127\\.0\\.0\\.1|0\\.0\\.0\\.0|\\[::\\]|::):${_lp}([[:space:]]|$)" && return 0
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -lntu 2>/dev/null | grep -Eq "(^|[[:space:]])[^[:space:]]*:${_lp}([[:space:]]|$)" && return 0
    fi
    _hx="$(printf '%04X' "$_lp" 2>/dev/null)"
    if [ -n "$_hx" ]; then
        awk -v p="$_hx" 'BEGIN{ok=0} NR>1 {split($2,a,":"); if (toupper(a[2])==p && ($4=="0A" || $4=="07" || $4=="01")) {ok=1}} END{exit !ok}' /proc/net/tcp 2>/dev/null && return 0
        awk -v p="$_hx" 'BEGIN{ok=0} NR>1 {split($2,a,":"); if (toupper(a[2])==p && $4=="07") {ok=1}} END{exit !ok}' /proc/net/udp 2>/dev/null && return 0
    fi
    return 1
}
local_dns_query_ok() {
    _lp="$1"
    _domain="${2:-example.com}"
    [ -n "$_lp" ] || return 1
    if command -v dig >/dev/null 2>&1; then
        for _try in 1 2 3; do
            _ans="$(dig @127.0.0.1 -p "$_lp" "$_domain" A +time=2 +tries=1 +short 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print; exit}')"
            [ -n "$_ans" ] && return 0
            _ans="$(dig @127.0.0.1 -p "$_lp" "$_domain" A +time=2 +tries=1 2>/dev/null | awk '$4=="A" && $NF ~ /^[0-9]+(\.[0-9]+){3}$/ && $NF !~ /^127\./ && $NF != "0.0.0.0" {print $NF; exit}')"
            [ -n "$_ans" ] && return 0
        done
        return 1
    fi
    if command -v nslookup >/dev/null 2>&1; then
        for _try in 1 2 3; do
            _ans="$(nslookup -port="$_lp" "$_domain" 127.0.0.1 2>/dev/null | awk '/^Address [0-9]+: / {print $NF} /^Address: / {print $2}' | awk '/^[0-9]+(\.[0-9]+){3}$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {print; exit}')"
            [ -n "$_ans" ] && return 0
        done
    fi
    return 1
}


verify_selected_doh() {
    FAILED_SLOT=""
    FAILED_SLOT_ID=""
    FAILED_SLOT_PORT=""
    FAILED_SLOT_CAT=""
    verify_applied_doh_config || return 1
    _checked=0
    for s in 1 2 3 4 5 6; do
        eval "_id=\${SLOT_$s:-}"
        eval "_p=\${PORT_$s:-}"
        [ -n "$_id" ] || continue
        [ -n "$_p" ] || { err_msg "Слот $s: боевой порт не определён."; return 1; }
        if listener_port_exists "$_p" && local_dns_query_ok "$_p" "example.com"; then
            [ "${APPLY_OUTPUT_QUIET:-0}" = 1 ] || printf "  ${C_GREEN}✓${C_NC} Слот %s работает: 127.0.0.1:%s ← %s\n" "$s" "$_p" "$(dns_name "$_id")"
            _checked=$((_checked+1))
        else
            FAILED_SLOT="$s"
            FAILED_SLOT_ID="$_id"
            FAILED_SLOT_PORT="$_p"
            FAILED_SLOT_CAT="$(watchdog_desired_cat "$s" 2>/dev/null || dns_cat "$_id")"
            err_msg "Слот $s ($(dns_name "$_id")): DNS не ответил через 127.0.0.1:$_p."
            return 1
        fi
    done
    if [ -n "${SLOT_RU:-}" ]; then
        [ -n "${PORT_RU:-}" ] || { err_msg "RU: боевой порт не определён."; return 1; }
        if listener_port_exists "$PORT_RU" && local_dns_query_ok "$PORT_RU" "yandex.ru"; then
            [ "${APPLY_OUTPUT_QUIET:-0}" = 1 ] || printf "  ${C_GREEN}✓${C_NC} RU работает: 127.0.0.1:%s ← %s\n" "$PORT_RU" "$(dns_name "$SLOT_RU")"
            _checked=$((_checked+1))
        else
            FAILED_SLOT="RU"
            FAILED_SLOT_ID="$SLOT_RU"
            FAILED_SLOT_PORT="$PORT_RU"
            FAILED_SLOT_CAT="regional"
            err_msg "RU ($(dns_name "$SLOT_RU")): DNS не ответил через 127.0.0.1:$PORT_RU."
            return 1
        fi
    fi
    [ "$_checked" -gt 0 ] || { err_msg "После применения не найдено ни одного рабочего локального DNS-порта."; return 1; }
    return 0
}
rebuild_selected_hdp_sections() {
    case "$DNS_PROFILE" in hybrid|custom) ;; *) return 1 ;; esac
    _keep_file="$TMP_DIR/rebuild-keep-$$"
    : > "$_keep_file" || return 1
    for _rs in 1 2 3 4 5 6 RU; do
        eval "_rid=\${SLOT_${_rs}:-}"
        [ -n "$_rid" ] || continue
        eval "_rport=\${PORT_${_rs}:-}"
        [ -n "$_rport" ] || _rport="$(hybrid_desired_port "$_rs")"
        _rurl="$(normalize_url "$(dns_url "$_rid")")"
        [ -n "$_rurl" ] || { rm -f "$_keep_file"; return 1; }
        printf '%s|%s|%s\n' "$_rs" "$_rport" "$_rurl" >> "$_keep_file"
    done

    # DNS Manager owns the complete https-dns-proxy configuration while an
    # active DNS profile is applied. Remove every existing section and rebuild
    # exactly the selected set below.
    while uci -q get "https-dns-proxy.@https-dns-proxy[0]" >/dev/null 2>&1; do
        uci -q delete "https-dns-proxy.@https-dns-proxy[0]" || { rm -f "$_keep_file"; return 1; }
    done

    while IFS='|' read -r _rs _rport _rurl; do
        [ -n "$_rs" ] || continue
        _sec="$(uci add https-dns-proxy https-dns-proxy 2>/dev/null)" || { rm -f "$_keep_file"; return 1; }
        _bl="${BOOTSTRAP_DNS_ALL:-1.1.1.1}"
        uci set "https-dns-proxy.$_sec.bootstrap_dns=$_bl" || { rm -f "$_keep_file"; return 1; }
        uci set "https-dns-proxy.$_sec.listen_addr=127.0.0.1" || { rm -f "$_keep_file"; return 1; }
        uci set "https-dns-proxy.$_sec.listen_port=$_rport" || { rm -f "$_keep_file"; return 1; }
        uci set "https-dns-proxy.$_sec.resolver_url=$_rurl" || { rm -f "$_keep_file"; return 1; }
        uci set "https-dns-proxy.$_sec.request_timeout=2" || { rm -f "$_keep_file"; return 1; }
    done < "$_keep_file"
    uci commit https-dns-proxy || { rm -f "$_keep_file"; return 1; }
    rm -f "$_keep_file"
    return 0
}
replace_failed_slot_from_test() {
    local _slot _old_id _port _cat _slot_tried _used _oldcat _picked _rid _rcat _candidate_name _old_display _u _domain
    _slot="$FAILED_SLOT"
    _old_id="$FAILED_SLOT_ID"
    _port="$FAILED_SLOT_PORT"
    _cat="$FAILED_SLOT_CAT"
    [ -n "$_slot" ] || return 1
    case "$_slot" in RU) _cat="regional" ;; esac
    _slot_tried="$TMP_DIR/repair-tried-$$-$_slot"
    _used="$TMP_DIR/repair-used-$$-$_slot"
    : > "$_slot_tried" || return 1
    : > "$_used" || { rm -f "$_slot_tried"; return 1; }
    [ -n "${REPAIR_BAD_IDS:-}" ] || REPAIR_BAD_IDS="$TMP_DIR/repair-bad-ids-$$"
    [ -f "$REPAIR_BAD_IDS" ] || : > "$REPAIR_BAD_IDS"
    for _s in 1 2 3 4 5 6 RU; do
        eval "_u_id=\${SLOT_${_s}:-}"
        [ -n "$_u_id" ] || continue
        _u="$(normalize_url "$(dns_url "$_u_id")")"
        [ -n "$_u" ] && printf '%s\n' "$_u" >> "$_used"
    done
    printf '%s\n' "$_old_id" >> "$_slot_tried"
    grep -qxF "$_old_id" "$REPAIR_BAD_IDS" 2>/dev/null || printf '%s\n' "$_old_id" >> "$REPAIR_BAD_IDS"
    _oldcat="$_cat"
    _old_display="$(dns_name "$_old_id")"
    [ -n "$_old_display" ] || _old_display="выбранный DNS"
    _domain="example.com"
    case "$_slot" in RU) _domain="yandex.ru" ;; esac

    _attempt=0
    while [ "$_attempt" -lt 2 ]; do
        _attempt=$((_attempt+1))
        _target_live="$(watchdog_target_live_count 2>/dev/null || printf 0)"
        case "$_target_live" in ""|*[!0-9]*) _target_live=0;; esac
        _allow_clean=0
        [ "$_target_live" -eq 0 ] && _allow_clean=1
        _picked="$(watchdog_pick_replacement "$_slot" "$_used" "$_slot_tried" "$_allow_clean")"
        _rid="${_picked%%|*}"
        _rcat="${_picked#*|}"
        [ -n "$_rid" ] || break
        printf '%s\n' "$_rid" >> "$_slot_tried"
        _candidate_name="$(dns_name "$_rid")"
        [ -n "$_candidate_name" ] || _candidate_name="новый DNS"
        [ "${APPLY_OUTPUT_QUIET:-0}" = 1 ] || printf "  ${C_YELLOW}↻ Слот %s: %s не отвечает. Проверен кандидат %s; применяю только подтверждённый вариант.${C_NC}\n" "$_slot" "$_old_display" "$_candidate_name"

        slot_set "$_slot" "$_rid" || return 1
        slot_cat_set "$_slot" "$_rcat" || return 1
        port_set "$_slot" "$_port" || return 1
        if watchdog_apply_slot_candidate "$_slot" "$_rid" "$_rcat" "$_old_id" "$_oldcat"; then
            [ "${APPLY_OUTPUT_QUIET:-0}" = 1 ] || printf "  ${C_GREEN}✓ Слот %s: %s подтверждён на 127.0.0.1:%s.${C_NC}\n" "$_slot" "$_candidate_name" "$_port"
            rm -f "$_slot_tried" "$_used" 2>/dev/null
            return 0
        fi
        grep -qxF "$_rid" "$REPAIR_BAD_IDS" 2>/dev/null || printf '%s\n' "$_rid" >> "$REPAIR_BAD_IDS"
        [ "${APPLY_OUTPUT_QUIET:-0}" = 1 ] || printf "  ${C_RED}✗ Слот %s: %s не подтвердился локально; откат выполнен.${C_NC}\n" "$_slot" "$_candidate_name"
    done
    rm -f "$_slot_tried" "$_used" 2>/dev/null
    if [ "${_target_live:-0}" -gt 0 ] && [ "$_slot" != RU ] && [ -n "$_old_id" ]; then
        slot_set "$_slot" "" || return 1
        slot_cat_set "$_slot" "" || return 1
        if watchdog_apply_slot_candidate "$_slot" "" "" "$_old_id" "$_oldcat"; then
            [ "${APPLY_OUTPUT_QUIET:-0}" = 1 ] || printf "  ${C_GREEN}✓ Слот %s освобождён; рабочий DNS целевой категории сохранён.${C_NC}\n" "$_slot"
            return 0
        fi
    fi
    warn_msg "Для слота $_slot не найден подтверждённый DNS в целевой категории."
    return 1
}
verify_after_apply_with_repair() {
    _attempt=0
    _max=8
    REPAIR_BAD_IDS="$TMP_DIR/repair-bad-ids-$$"
    : > "$REPAIR_BAD_IDS" || return 1
    while [ "$_attempt" -lt "$_max" ]; do
        FAILED_SLOT=""
        FAILED_SLOT_ID=""
        FAILED_SLOT_PORT=""
        FAILED_SLOT_CAT=""
        if verify_after_apply; then
            rm -f "$REPAIR_BAD_IDS" 2>/dev/null
            return 0
        fi
        [ -n "$FAILED_SLOT" ] || { rm -f "$REPAIR_BAD_IDS" 2>/dev/null; return 1; }
        _attempt=$((_attempt+1))
        [ "${APPLY_OUTPUT_QUIET:-0}" = 1 ] || printf "  ${C_CYAN}Проверка не пройдена. Подбираю другую замену из выбранной категории (точечная проверка, попытка $_attempt/$_max).${C_NC}\n"
        if ! replace_failed_slot_from_test; then
            rm -f "$REPAIR_BAD_IDS" 2>/dev/null
            return 1
        fi
        tx_snapshot_after_apply
    done
    rm -f "$REPAIR_BAD_IDS" 2>/dev/null
    return 1
}
verify_after_apply() {
    sleep 3
    if ! /etc/init.d/dnsmasq status >/dev/null 2>&1 && ! pgrep -x dnsmasq >/dev/null 2>&1; then
        err_msg "dnsmasq не запущен после применения."; return 1
    fi
    if [ "$DOH_TOTAL" -gt 0 ]; then
        pgrep -f 'https-dns-proxy' >/dev/null 2>&1 || { err_msg "https-dns-proxy не запущен после применения."; return 1; }
    fi
    verify_selected_doh || return 1
    local_dns_query_ok 53 "example.com" || {
        err_msg "Локальный DNS после применения не отвечает через 127.0.0.1:53."; return 1;
    }
    _sec="$(get_dnsmasq_section)"
    [ -n "$_sec" ] || { err_msg "Не удалось определить секцию dnsmasq для проверки."; return 1; }
    [ "$(uci -q get "dhcp.$_sec.noresolv" 2>/dev/null)" = 1 ] || {
        err_msg "dnsmasq: noresolv=1 не применён."; return 1;
    }
    if [ "$BALANCER_ENABLED" = 1 ]; then
        [ "$(uci -q get "dhcp.$_sec.allservers" 2>/dev/null)" = 1 ] || {
            err_msg "Одновременный опрос DNS не включён."; return 1;
        }
        [ "$(uci -q get "dhcp.$_sec.strictorder" 2>/dev/null)" = 0 ] || {
            err_msg "dnsmasq: strictorder=0 не применён."; return 1;
        }
    fi
    if [ -n "${SLOT_RU:-}" ]; then
        [ "$(check_module_state tld 2>/dev/null)" = 1 ] || {
            err_msg "Маршрут .ru/.su/.рф после применения не соответствует выбранному DNS."; return 1;
        }
    fi
    if [ "$CORE_ONLY" != 1 ]; then
        if [ "${FORCE_DOH:-0}" = 1 ]; then
            [ "$(check_module_state force 2>/dev/null)" = 1 ] || { err_msg "Принудительный DNS после применения не подтверждён."; return 1; }
        fi
        if [ "${DNSMASQ_PERF:-0}" = 1 ]; then
            [ "$(check_module_state dnsmasq_perf 2>/dev/null)" = 1 ] || { err_msg "Увеличенный кэш DNS после применения не подтверждена."; return 1; }
        fi
        if [ "${NTP_IP_FALLBACK:-0}" = 1 ]; then
            [ "$(check_module_state ntp 2>/dev/null)" = 1 ] || { err_msg "NTP по IP после применения не подтверждён."; return 1; }
        fi
    fi
    return 0
}
# ==========================================
tx_snapshot_start() {
TX_DIR="$STATE_DIR/tx-$TX_ID"
rm -rf "$TX_DIR" 2>/dev/null
mkdir -p "$TX_DIR/files" || return 1
TX_ACTIVE=1
TX_WD_LEGACY_DAEMON_EXISTED=0
TX_WD_SERVICE_EXISTED=0
[ -f "$WATCHDOG_LEGACY_DAEMON_PATH" ] && TX_WD_LEGACY_DAEMON_EXISTED=1
[ -f "$WATCHDOG_SERVICE_PATH" ] && TX_WD_SERVICE_EXISTED=1
TX_WD_ENABLED=unknown
TX_WD_RUNNING=unknown
if [ -x "$WATCHDOG_SERVICE_PATH" ]; then
    "$WATCHDOG_SERVICE_PATH" enabled >/dev/null 2>&1 && TX_WD_ENABLED=yes || TX_WD_ENABLED=no
    "$WATCHDOG_SERVICE_PATH" running >/dev/null 2>&1 && TX_WD_RUNNING=yes || TX_WD_RUNNING=no
fi
for f in "$CONFIG_FILE" "$OWNERSHIP" "$WATCHDOG_SERVICE_PATH" "$WATCHDOG_LEGACY_DAEMON_PATH" /etc/config/dhcp /etc/config/https-dns-proxy /etc/config/firewall /etc/config/system /etc/dnsmasq.d/90-dns-manager-bogus.conf ; do
key="$(printf '%s' "$f" | sed 's#^/##; s#[/ ]#_#g')"
if [ -f "$f" ]; then cp -p "$f" "$TX_DIR/files/$key"; file_hash "$f" > "$TX_DIR/$key.before"; printf '%s|%s|1\n' "$f" "$key" >> "$TX_DIR/manifest"; else printf '%s|%s|0\n' "$f" "$key" >> "$TX_DIR/manifest"; fi
done
: > "$TX_DIR/after.manifest"
log_tx "TX" "transaction" "SNAPSHOT" "OK" "dir=$TX_DIR"
}
tx_snapshot_after_apply() {
[ "$TX_ACTIVE" = 1 ] || return 0
: > "$TX_DIR/after.manifest"
while IFS='|' read -r f key existed; do
[ -n "$f" ] || continue
if [ -f "$f" ]; then
file_hash "$f" > "$TX_DIR/$key.after"
printf '%s|%s|1\n' "$f" "$key" >> "$TX_DIR/after.manifest"
else
printf '%s|%s|0\n' "$f" "$key" >> "$TX_DIR/after.manifest"
fi
done < "$TX_DIR/manifest"
}
tx_restore_watchdog_state() {
    # Restore the watchdog supervisor state that existed before the transaction.
    if [ "${TX_WD_SERVICE_EXISTED:-0}" = 1 ]; then
        if [ -x "$WATCHDOG_SERVICE_PATH" ]; then
            case "${TX_WD_ENABLED:-unknown}" in
                yes) "$WATCHDOG_SERVICE_PATH" enable >/dev/null 2>&1 || true ;;
                no) "$WATCHDOG_SERVICE_PATH" disable >/dev/null 2>&1 || true ;;
            esac
            case "${TX_WD_RUNNING:-unknown}" in
                yes) "$WATCHDOG_SERVICE_PATH" start >/dev/null 2>&1 || true ;;
                no) "$WATCHDOG_SERVICE_PATH" stop >/dev/null 2>&1 || true ;;
            esac
        fi
    else
        watchdog_service_stop_disable >/dev/null 2>&1 || true
        watchdog_service_remove_files >/dev/null 2>&1 || true
    fi
    return 0
}
tx_restore_on_failure() {
[ "$TX_ACTIVE" = 1 ] || return 0
warn_msg "Применение не прошло проверку. Выполняю автоматический откат этой транзакции."
watchdog_cron_remove_owned_block >/dev/null 2>&1 || true
if [ -f "$TX_DIR/manifest" ]; then
    while IFS='|' read -r f key existed; do
        [ -n "$f" ] || continue
        if [ "$existed" = 1 ]; then
            if [ -f "$TX_DIR/files/$key" ]; then
                cp -p "$TX_DIR/files/$key" "$f" 2>/dev/null || warn_msg "Не удалось восстановить $f"
            fi
        else
            rm -f "$f" 2>/dev/null || true
        fi
    done < "$TX_DIR/manifest"
fi
tx_restore_watchdog_state
/etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
/etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
reload_fw >/dev/null 2>&1 || true
TX_ACTIVE=0
log_tx "ROLLBACK" "transaction" "RESTORE" "OK" "dir=$TX_DIR;guarded=no"
rm -rf "$TX_DIR" 2>/dev/null || true
TX_DIR=""
}
tx_commit() {
TX_ACTIVE=0
printf '%s\n' "$(date +%s)" > "$TX_DIR/COMMITTED" 2>/dev/null
log_tx "TX" "transaction" "COMMIT" "OK" "dir=$TX_DIR"
rm -rf "$TX_DIR" 2>/dev/null || true
TX_DIR=""
}
# ==========================================
# ==========================================
# ==========================================
# ==========================================
adaptive_hybrid_prepare() {
    [ "$DNS_PROFILE" = hybrid ] || return 0
    ensure_test_results_fresh || return 1
    _success=0
    _tried="$TMP_DIR/hybrid-selected-tried-$$"
    _selected_urls="$TMP_DIR/hybrid-selected-urls-$$"
    : > "$_tried" || return 1
    : > "$_selected_urls" || { rm -f "$_tried" 2>/dev/null; return 1; }
    printf "\n${C_CYAN}Формирую набор только из DNS, которые прошли последнюю полную проверку DoH.${C_NC}\n"
    _hybrid_ok_count="$(awk -F'|' '$1!="" && NF>=5 && $5=="OK" && $4 ~ /^[0-9]+$/{n++} END{print n+0}' "$TEST_RESULTS" 2>/dev/null)"
    printf "  В последней полной проверке подтверждено: %s DNS.\n" "$_hybrid_ok_count"
    _pool="$TMP_DIR/hybrid-pool-$$"
    : > "$_pool"
    awk -F'|' 'NF>=5 && $2=="bypass" && $5=="OK" && $4 ~ /^[0-9]+$/ {print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n > "$_pool.bypass"
    _fill=0
    _hybrid_max_slots=6
    _hybrid_min_slots=3
    while IFS='|' read -r _id _cat _name _ms _st; do
        [ -n "$_id" ] || continue
        grep -qxF "$_id" "$_tried" 2>/dev/null && continue
        _u="$(normalize_url "$(dns_url "$_id")")"
        [ -n "$_u" ] || continue
        grep -qxF "$_u" "$_selected_urls" 2>/dev/null && continue
        printf '%s\n' "$_id" >> "$_tried"
        printf '%s\n' "$_u" >> "$_selected_urls"
        printf '%s|%s|%s|%s|%s\n' "$_id" "$_cat" "$_name" "$_ms" "$_st" >> "$_pool"
        _fill=$((_fill+1))
        [ "$_fill" -ge "$_hybrid_max_slots" ] && break
    done < "$_pool.bypass"
    _bypass_count="$_fill"
    _hybrid_clean_fallback=0
    if [ "$_fill" -lt "$_hybrid_max_slots" ]; then
        _hybrid_clean_pool="$TMP_DIR/hybrid-pool-clean-$$"
        awk -F'|' 'NF>=5 && $2=="clean" && $5=="OK" && $4 ~ /^[0-9]+$/ {print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n > "$_hybrid_clean_pool"
        while [ "$_fill" -lt "$_hybrid_max_slots" ]; do
            _picked_clean=""
            while IFS='|' read -r _cid _ccat _cname _cms _cst; do
                [ -n "$_cid" ] || continue
                grep -qxF "$_cid" "$_tried" 2>/dev/null && continue
                _cu="$(normalize_url "$(dns_url "$_cid")")"
                [ -n "$_cu" ] || continue
                grep -qxF "$_cu" "$_selected_urls" 2>/dev/null && continue
                _picked_clean="$_cid|$_ccat|$_cname|$_cms|$_cst"
                break
            done < "$_hybrid_clean_pool"
            [ -n "$_picked_clean" ] || break
            _cid="${_picked_clean%%|*}"
            printf '%s\n' "$_cid" >> "$_tried"
            _cu="$(normalize_url "$(dns_url "$_cid")")"
            printf '%s\n' "$_cu" >> "$_selected_urls"
            printf '%s\n' "$_picked_clean" >> "$_pool"
            _fill=$((_fill+1))
            _hybrid_clean_fallback=1
            awk -F'|' -v id="$_cid" '$1!=id{print}' "$_hybrid_clean_pool" > "$_hybrid_clean_pool.tmp" && mv "$_hybrid_clean_pool.tmp" "$_hybrid_clean_pool"
        done
        rm -f "$_hybrid_clean_pool" 2>/dev/null
    fi
    rm -f "$_pool.bypass" 2>/dev/null

    if [ "$_fill" -lt "$_hybrid_min_slots" ]; then
        rm -f "$_pool" "$_tried" "$_selected_urls" 2>/dev/null
        err_msg "После полной проверки и добора из чистых DNS найдено только $_fill рабочих серверов. Нужно минимум $_hybrid_min_slots; набор не применён."
        return 1
    fi
    if [ "$_fill" -lt "$_hybrid_max_slots" ]; then
        warn_msg "Удалось сформировать только $_fill из $_hybrid_max_slots слотов. Применяю доступные рабочие DNS; незаполненные слоты останутся пустыми."
    elif [ "$_hybrid_clean_fallback" = 1 ]; then
        warn_msg "В обходе подтверждено только $_bypass_count DNS; недостающие слоты временно заполнены проверенными DNS категории «Без фильтрации»."
    fi

    # Assign only after the minimum viable pool is ready, so a failed selection
    # cannot leave this function half-filled when it is called outside a TX.
    SLOT_1=""; SLOT_2=""; SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""
    QUICK_PREF_1=""; QUICK_PREF_2=""; QUICK_PREF_3=""; QUICK_PREF_4=""; QUICK_PREF_5=""; QUICK_PREF_6=""
    _slot=1
    while [ "$_slot" -le "$_hybrid_max_slots" ]; do
        IFS='|' read -r _id _cat _name _ms _st < "$_pool" || break
        [ -n "$_id" ] || break
        sed '1d' "$_pool" > "$_pool.tmp" && mv "$_pool.tmp" "$_pool"
        slot_set "$_slot" "$_id" || return 1
        if [ "$_cat" = bypass ]; then
            quick_pref_set "$_slot" "$_id" || return 1
        fi
        slot_cat_set "$_slot" "$_cat" || return 1
        _port="$(hybrid_desired_port "$_slot")"
        printf "  ${C_GREEN}✓ Слот %s: %s → 127.0.0.1:%s${C_NC}\n" "$_slot" "$(dns_name "$_id")" "$_port"
        _success=$((_success+1))
        _slot=$((_slot+1))
    done
    while [ "$_slot" -le "$_hybrid_max_slots" ]; do
        slot_set "$_slot" "" || return 1
        slot_cat_set "$_slot" "bypass" || return 1
        _slot=$((_slot+1))
    done

    SLOT_RU=""
    SLOT_RU_CAT="regional"
    _yandex_ok="$(awk -F'|' 'NF>=5 && $1=="yandex_ru" && $2=="regional" && $5=="OK" && $4 ~ /^[0-9]+$/ {print "yes";exit}' "$TEST_RESULTS" 2>/dev/null)"
    if [ "$_yandex_ok" = yes ]; then
        SLOT_RU="yandex_ru"
        printf "  ${C_GREEN}✓ RU: Yandex RU → 127.0.0.1:%s${C_NC}\n" "$(hybrid_desired_port RU)"
    else
        _ru1="$(awk -F'|' 'NF>=5 && $2=="regional" && $5=="OK" && $4 ~ /^[0-9]+$/ {print $1;exit}' "$TEST_RESULTS" 2>/dev/null)"
        if [ -n "$_ru1" ]; then
            SLOT_RU="$_ru1"
            warn_msg "Yandex RU не прошёл последнюю проверку. Для RU выбран другой подтверждённый региональный DNS: $(dns_name "$_ru1")."
        else
            warn_msg "Проверенного регионального DNS нет. RU-маршрут оставлен без нового назначения."
        fi
    fi
    _ru_skip="${SLOT_RU:-}"

    PORT_1="$HYBRID_PORT_1"; PORT_2="$HYBRID_PORT_2"; PORT_3="$HYBRID_PORT_3"
    PORT_4="$HYBRID_PORT_4"; PORT_5="$HYBRID_PORT_5"; PORT_6="$HYBRID_PORT_6"
    PORT_RU="$HYBRID_PORT_RU"
    DNS_SELECTION_MODE="quick"
    DNS_SELECTION_CATEGORY="bypass"
    rm -f "$_pool" "$_tried" "$_selected_urls" 2>/dev/null
    return 0
}
reset_hybrid_runtime_ports() {
    [ "$DNS_PROFILE" = hybrid ] || return 0
    for _s in 1 2 3 4 5 6; do
        eval "_v=\${SLOT_$_s:-}"
        if [ -n "$_v" ]; then
            _want="$(hybrid_desired_port "$_s")"
            port_set "$_s" "$_want" || return 1
        else
            port_set "$_s" "" || return 1
        fi
    done
    if [ -n "${SLOT_RU:-}" ]; then
        PORT_RU="$(hybrid_desired_port RU)"
    else
        PORT_RU=""
    fi
    return 0
}
_apply_settings_impl() {
    # Hard contract: profile application can touch DNS core only.
    if [ "${PROFILE_APPLY:-0}" = 1 ]; then
        CORE_ONLY=1
    fi
    local APPLY_OUTPUT_QUIET=0
    clear_screen
    run_discovery
    if [ "$CORE_ONLY" != 1 ] && [ "${FORCE_DOH:-0}" = 1 ]; then
        firewall_backend_require || return 1
    fi
    if [ "${HYBRID_FORCE_RESELECT:-0}" = 1 ] && [ "$DNS_PROFILE" = hybrid ]; then
        SLOT_1=""; SLOT_2=""; SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""
        SLOT_RU=""
        QUICK_PREF_1=""; QUICK_PREF_2=""; QUICK_PREF_3=""; QUICK_PREF_4=""; QUICK_PREF_5=""; QUICK_PREF_6=""
        SLOT_1_CAT="bypass"; SLOT_2_CAT="bypass"; SLOT_3_CAT="bypass"
        SLOT_4_CAT="bypass"; SLOT_5_CAT="bypass"; SLOT_6_CAT="bypass"
        SLOT_RU_CAT="regional"
    fi
    BOOTSTRAP_DNS="$BOOTSTRAP_DNS_ALL"
    BALANCER_ENABLED=1
    HYBRID_SELECTION_READY=0
    HYBRID_PREFLIGHT_WAS_RUNNING=0
    if [ "$DNS_PROFILE" = hybrid ] && [ "${HYBRID_STAGE_SKIP:-0}" != 1 ]; then
        adaptive_hybrid_prepare || return 1
        reset_hybrid_runtime_ports || {
            err_msg "Не удалось определить боевые порты DNS."
            return 1
        }
        HYBRID_SELECTION_READY=1
    fi
    sync_regional_dns_state
    # Refresh live counts after any auto-selection/normalization so the plan
    # never shows stale DOH_MATCH/DOH_OTHER values from the pre-selection scan.
    disc_listeners
    disc_dns
    printf "${C_TITLE}===  ПОДГОТОВКА И ПЛАН ПРИМЕНЕНИЯ ===${C_NC}\n"
    printf "${C_WHITE}Будет настроено:${C_NC}\n"
    if [ "$DNS_PROFILE" = hybrid ]; then
        printf "  ${C_YELLOW}Гибридный DNS — до 6 серверов + RU${C_NC}\n"
        printf "${C_WHITE}DNS-серверы:${C_NC}\n"
        for _s in 1 2 3 4 5 6; do
            eval "_v=\${SLOT_$_s:-}"
            [ -n "$_v" ] && printf "  127.0.0.1:%s  ←  %s\n" "$(hybrid_desired_port "$_s")" "$(dns_name "$_v")"
        done
        if [ -n "${SLOT_RU:-}" ]; then
            printf "\n${C_WHITE}Домены .ru / .su / .рф:${C_NC}\n"
            printf "  127.0.0.1:%s  ←  %s  (.ru / .su / .рф)\n" "$HYBRID_PORT_RU" "$(dns_name "$SLOT_RU")"
        else
            printf "\n${C_YELLOW}RU-маршрут сейчас не выбран.${C_NC}\n"
        fi
        printf "\n"
    else
        printf "  ${C_YELLOW}Своя настройка DNS${C_NC}\n"
        for _s in 1 2 3 4 5 6; do
            eval "_v=\${SLOT_$_s:-}"
            [ -n "$_v" ] && printf "  Слот %s: %s\n" "$_s" "$(dns_name "$_v")"
        done
        [ -n "${SLOT_RU:-}" ] && printf "  RU: %s\n" "$(dns_name "$SLOT_RU")"
    fi
    printf "\n${C_WHITE}Основные настройки DNS:${C_NC}\n"
    [ "$TLD_RU_ENABLED" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Отдельный DNS для .ru/.su/.рф\n" || printf "  ${C_YELLOW}—${C_NC} Раздельный DNS не выбран\n"
    [ "$BALANCER_ENABLED" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Одновременный опрос DNS\n" || printf "  ${C_YELLOW}—${C_NC} Одновременный опрос не выбран\n"
    if [ "$CORE_ONLY" != 1 ]; then
        [ "$NTP_IP_FALLBACK" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Время по IP\n" || printf "  ${C_YELLOW}—${C_NC} NTP не изменяется\n"
        printf "\n${C_WHITE}Дополнительные настройки:${C_NC}\n"
        [ "${FORCE_DOH:-0}" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Принудительный DNS для устройств\n" || printf "  ${C_YELLOW}—${C_NC} Принудительный DNS для устройств не изменяется\n"
        [ "$DNSMASQ_PERF" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Увеличенный кэш DNS\n" || printf "  ${C_YELLOW}—${C_NC} Увеличенный кэш DNS не изменяется\n"
        [ "$WATCHDOG_ENABLED" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Фоновая автопроверка DNS: каждые %s сек\n" "$WATCHDOG_INTERVAL" || printf "  ${C_YELLOW}—${C_NC} Автоматическая проверка DNS не изменяется\n"
    fi
    printf "\n${C_WHITE}Текущее состояние до применения:${C_NC}\n"
    printf "  dnsmasq: %b\n" "$(state_word "$DNSMASQ_RUN")"
    printf "  DNS-серверов: %s (по текущей схеме %s / вне схемы %s)\n" "$DOH_TOTAL" "$DOH_MATCH" "$DOH_OTHER"
    if doh_selected_config_current; then
        printf "  ${C_GREEN}✓ Текущая схема уже совпадает с выбранной. DNS-секции будут сохранены.${C_NC}\n"
    elif [ "$DOH_TOTAL" -gt 0 ]; then
        printf "  ${C_YELLOW}↻ Текущая схема отличается. После подтверждения будет пересобран только необходимый набор DNS Manager.${C_NC}\n"
    else
        printf "  ${C_YELLOW}↻ Текущих DNS-секций нет. После подтверждения будет установлен выбранный набор DNS Manager.${C_NC}\n"
    fi
    printf "  ${C_CYAN}${C_NC}\n"
    validate_selected_slots || return 1
    confirm_action "Применить показанную выше конфигурацию?" || return
    APPLY_OUTPUT_QUIET=0
    printf "\n${C_CYAN}Начинаю применение. Это может занять немного времени...${C_NC}\n"
    TX_ID="$(date +%Y%m%d-%H%M%S)-$$"
    TX_RESERVED_PORTS=""
    DOH_REBUILD_NEEDED=1
    # Re-check the live UCI state after confirmation. Another process may have
    # changed https-dns-proxy since the plan was displayed.
    disc_listeners
    disc_dns
    if doh_selected_config_current; then
        DOH_REBUILD_NEEDED=0
        apply_progress_ok "Выбранная DNS-схема уже установлена; пересоздание DNS-секций не требуется."
    else
        apply_progress "Текущая DNS-схема отличается; выполняется пересборка выбранного набора DNS Manager."
    fi
    tx_snapshot_start || { err_msg "Не удалось сохранить копию настроек. Настройки не изменены."; return 1; }
    DEFER_CONFIG_SAVE=1
    log_tx "PLAN" "all" "APPLY" "START" "version=$VERSION"
    if [ "$CORE_ONLY" != 1 ] && [ "$NTP_IP_FALLBACK" = 1 ]; then
        apply_ntp_host_ips || { err_msg "Не удалось подготовить серверы времени."; tx_restore_on_failure; return 1; }
    fi
    if [ "$DNS_PROFILE" = hybrid ] && [ "${HYBRID_STAGE_SKIP:-0}" != 1 ]; then
        validate_selected_slots || { err_msg "Выбранный набор DNS больше не соответствует последней полной проверке."; tx_restore_on_failure; return 1; }
    else
        validate_selected_slots || { err_msg "Выбранный набор DNS больше не соответствует последней полной проверке."; tx_restore_on_failure; return 1; }
    fi
    if [ "$DOH_REBUILD_NEEDED" = 1 ] && [ "${DOH_TOTAL:-0}" -gt 0 ]; then
        apply_progress "Останавливаю текущие экземпляры https-dns-proxy перед пересборкой."
        /etc/init.d/https-dns-proxy stop >/dev/null 2>&1 || true
        apply_progress_ok "Текущие экземпляры https-dns-proxy остановлены."
        sleep 1
    fi
    configure_hdp_manager_control || {
        err_msg "Не удалось подготовить настройки DNS."
        tx_restore_on_failure
        return 1
    }
    if [ "$DOH_REBUILD_NEEDED" = 1 ]; then
        disc_listeners
        disc_dns
        clear_all_doh_for_apply || {
            err_msg "Не удалось пересобрать DNS-серверы выбранной схемы."
            tx_restore_on_failure
            return 1
        }
        disc_listeners
        disc_dns
        for s in 1 2 3 4 5 6; do
            eval "v=\${SLOT_$s:-}"
            [ -n "$v" ] || continue
            ensure_doh_slot "$s" "$v" || {
                err_msg "Не удалось настроить DNS-сервер для слота $s."
                tx_restore_on_failure
                return 1
            }
        done
        ensure_doh_slot RU "${SLOT_RU:-}" || {
            err_msg "Не удалось настроить DNS для доменов .ru/.su/.рф."
            tx_restore_on_failure
            return 1
        }
    fi
    plan_dup="$(for s in 1 2 3 4 5 6 RU; do eval "p=\${PORT_$s:-}"; [ -n "$p" ] && printf '%s\n' "$p"; done | sort | uniq -d | head -n1)"
    if [ -n "$plan_dup" ]; then
        err_msg "План отменён: порт $plan_dup назначен нескольким DNS одновременно."
        tx_restore_on_failure
        return 1
    fi
    uci commit https-dns-proxy 2>/dev/null || {
        err_msg "Не удалось сохранить настройки DNS."
        tx_restore_on_failure
        return 1
    }
    apply_progress_ok "Конфигурация https-dns-proxy сохранена."
    apply_progress "Обновляю конфигурацию dnsmasq."
    reconcile_dnsmasq || { err_msg "Не удалось настроить dnsmasq."; tx_restore_on_failure; return 1; }
    apply_progress_ok "Конфигурация dnsmasq обновлена."
    apply_progress "Включаю одновременный опрос DNS (allservers)."
    ensure_dnsmasq_balancer || { err_msg "Не удалось включить одновременный опрос DNS."; tx_restore_on_failure; return 1; }
    if [ "$CORE_ONLY" != 1 ] && [ "$NTP_IP_FALLBACK" = 1 ]; then
        apply_progress "Применяю NTP по IP."
        apply_ntp_ip_fallback || { err_msg "Не удалось настроить NTP по IP."; tx_restore_on_failure; return 1; }
        apply_progress_ok "NTP по IP применён."
    fi
    if [ "$CORE_ONLY" != 1 ] && [ "${FORCE_DOH:-0}" = 1 ]; then
        apply_progress "Применяю принудительный локальный DNS."
        apply_dns_force || { err_msg "Не удалось применить принудительный DNS для устройств."; tx_restore_on_failure; return 1; }
        apply_progress_ok "Принудительный DNS для устройств применён."
    fi
    if [ "$CORE_ONLY" != 1 ] && [ "$DNSMASQ_PERF" = 1 ]; then
        apply_progress "Настраиваю Увеличенный кэш DNS."
        apply_dnsmasq_perf || { err_msg "Не удалось применить увеличенный кэш DNS."; tx_restore_on_failure; return 1; }
        apply_progress_ok "Увеличенный кэш DNS применён."
    fi
    if [ "$CORE_ONLY" != 1 ]; then
        WATCHDOG_ENABLED="${WATCHDOG_ENABLED:-0}"
        apply_progress "Проверяю и применяю фоновую автопроверку DNS (procd)."
        apply_watchdog || { err_msg "Не удалось настроить фоновую автопроверку DNS."; tx_restore_on_failure; return 1; }
        apply_progress_ok "Фоновая автопроверка DNS обработана."
    fi
    apply_progress "Запускаю https-dns-proxy с выбранными экземплярами."
    /etc/init.d/https-dns-proxy restart || true
    apply_progress "Перезапускаю dnsmasq."
    /etc/init.d/dnsmasq restart || true
    sleep 2
    apply_progress "Повторно проверяю параметры dnsmasq после запуска."
    ensure_dnsmasq_balancer || { err_msg "Одновременный опрос DNS не включился после запуска. Изменения откатываются."; tx_restore_on_failure; return 1; }
    apply_progress "Обновляю правила firewall."
    reload_fw || { err_msg "Не удалось применить настройки firewall."; tx_restore_on_failure; return 1; }
    apply_progress_ok "Firewall обновлён."
    apply_progress "Выполняю итоговое обнаружение состояния системы."
    run_discovery
    apply_progress_ok "Итоговое обнаружение завершено. Начинаю локальную проверку всех выбранных DNS."
    tx_snapshot_after_apply
    apply_progress "Проверяю dnsmasq, все локальные DoH-порты, .ru/.su/.рф и дополнительные настройки."
    if [ "${SKIP_POST_APPLY_VERIFY:-0}" = 1 ]; then
        apply_progress_ok "Конфигурация применена без проверки доступности выбранных DNS."
    elif verify_after_apply_with_repair; then
        apply_progress_ok "Все локальные проверки после применения пройдены."
    else
        log_tx "VERIFY" "all" "VERIFY" "FAIL" "dnsmasq=$DNSMASQ_RUN,doh=$DOH_TOTAL"
        tx_restore_on_failure
        err_msg "Конфигурация не прошла локальную проверку после запуска. Изменения этой транзакции откатаны, где это безопасно возможно."
        pause
        return 1
    fi
        DEFER_CONFIG_SAVE=0
        save_config || {
            err_msg "Не удалось сохранить итоговую конфигурацию DNS Manager. Изменения откатываются."
            tx_restore_on_failure
            return 1
        }
        if [ "${WATCHDOG_ENABLED:-0}" = 1 ]; then
            if ! watchdog_service_start_enable; then
                err_msg "Watchdog не удалось запустить после фиксации конфигурации. Изменения DNS откатываются."
                tx_restore_on_failure
                return 1
            fi
            watchdog_cron_marker_exists >/dev/null 2>&1 && watchdog_cron_remove_owned_block >/dev/null 2>&1 || true
        fi
        tx_commit
        # Keep the complete live Apply progress visible while the operation runs.
        # After success, present a clean final screen with only the actual scheme.
        clear_screen
        printf "${C_WHITE}Фактическая применённая схема:${C_NC}\n"
        for _s in 1 2 3 4 5 6; do
            eval "_v=\${SLOT_$_s:-}"
            eval "_p=\${PORT_$_s:-}"
            [ -n "$_v" ] && printf "  ${C_GREEN}✓${C_NC} Слот %s: 127.0.0.1:%s ← %s\n" "$_s" "$_p" "$(dns_name "$_v")"
        done
        [ -n "${SLOT_RU:-}" ] && printf "  ${C_GREEN}✓${C_NC} RU: 127.0.0.1:%s ← %s (.ru/.su/.рф)\n" "$PORT_RU" "$(dns_name "$SLOT_RU")"
        ok_msg "Готово. Выбранная схема реально развернута и проверена."
        log_tx "VERIFY" "all" "VERIFY" "OK" "dnsmasq=$DNSMASQ_RUN,doh=$DOH_TOTAL"
    pause
}
firewall_backend_require() {
    detect_firewall_backend
    case "$SYS_FW" in
        fw4|fw3) firewall_resolve_zones; return 0 ;;
    esac
    err_msg "Не удалось однозначно определить активный firewall backend (fw4/fw3). Firewall-зависимые изменения не применяются."
    return 1
}
apply_settings() {
    if [ "${CORE_ONLY:-0}" = 1 ]; then
        apply_wait_message "Применяю выбранную конфигурацию DNS"
    else
        apply_wait_message "Применяю выбранную конфигурацию DNS и дополнительные настройки"
    fi
    acquire_mutation_lock || return 1
    _rc=0
    install_missing_dependencies || _rc=$?
    if [ "$_rc" -eq 0 ]; then
        _apply_settings_impl "$@" || _rc=$?
    fi
    release_mutation_lock
    return "$_rc"
}
rollback_ownership_has() {
    _t="$1"; _k="$2"; _v="$3"
    [ -f "$OWNERSHIP" ] || return 1
    awk -F'|' -v t="$_t" -v k="$_k" -v v="$_v" '$1==t && $2==k && $3==v{found=1;exit} END{exit found?0:1}' "$OWNERSHIP" 2>/dev/null
}

rollback_dnsmasq_targeted() {
    sec="$(get_dnsmasq_section 2>/dev/null)"
    [ -n "$sec" ] || return 0
    _changed=0

    # Remove only DNS Manager-owned upstream entries. Unrelated server= entries
    # are left intact, including entries introduced by another package.
    _cur="$(uci -q get "dhcp.$sec.server" 2>/dev/null | tr ' ' '\n')"
    while IFS= read -r _val; do
        [ -n "$_val" ] || continue
        rollback_ownership_has dnsmasq server "$_val" || continue
        if uci -q del_list "dhcp.$sec.server=$_val" >/dev/null 2>&1; then
            _changed=1
            printf '  - dnsmasq server: %s\n' "$_val"
        fi
    done <<EOF_RB_DNSMASQ
$_cur
EOF_RB_DNSMASQ

    # Restore only scalar settings that DNS Manager explicitly recorded as
    # changed. If the value was subsequently changed by somebody else, keep it.
    for _kv in 'allservers|1' 'strictorder|0' 'noresolv|1'; do
        _k="${_kv%%|*}"; _managed="${_kv#*|}"
        rollback_ownership_has dnsmasq "$_k" "$_managed" || continue
        _curv="$(uci -q get "dhcp.$sec.$_k" 2>/dev/null)"
        if [ "$_curv" = "$_managed" ]; then
            uci -q delete "dhcp.$sec.$_k" || true
            _changed=1
        else
            warn_msg "dnsmasq: $_k изменён после применения DNS Manager. Текущее значение сохранено."
        fi
    done

    if [ "${ROLLBACK_DNS_CORE_ONLY:-0}" != 1 ] && rollback_ownership_has dnsmasq confdir /etc/dnsmasq.d; then
        _cur_conf="$(uci -q get "dhcp.$sec.confdir" 2>/dev/null | tr " " "\n")"
        if printf "%s\n" "$_cur_conf" | grep -qxF /etc/dnsmasq.d 2>/dev/null; then
            uci -q del_list "dhcp.$sec.confdir=/etc/dnsmasq.d" >/dev/null 2>&1 && _changed=1
        fi
    fi
    if [ "$_changed" = 1 ]; then
        uci commit dhcp >/dev/null 2>&1 || return 1
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
    fi
    return 0
}

rollback_hdp_targeted() {
    _changed=0
    _sections="$(uci show https-dns-proxy 2>/dev/null | sed -n 's/^https-dns-proxy\.\([^.=]*\)=https-dns-proxy$/\1/p')"
    for _sec in $_sections; do
        _url="$(uci -q get "https-dns-proxy.$_sec.resolver_url" 2>/dev/null)"
        _port="$(uci -q get "https-dns-proxy.$_sec.listen_port" 2>/dev/null)"
        _own=0
        if rollback_ownership_has doh "$_port" "$_url"; then
            _own=1
        else
            for _slot in 1 2 3 4 5 6 RU; do
                eval "_sid=\${SLOT_${_slot}:-}"
                eval "_sport=\${PORT_${_slot}:-}"
                [ -n "$_sid" ] && [ -n "$_sport" ] || continue
                _surl="$(normalize_url "$(dns_url "$_sid")")"
                _nurl="$(normalize_url "$_url")"
                if [ "$_sport" = "$_port" ] && [ "$_surl" = "$_nurl" ]; then
                    _own=1
                    break
                fi
            done
        fi
        [ "$_own" = 1 ] || continue
        # A section modified by hand no longer matches both recorded URL/port;
        # ownership fallback is therefore intentionally conservative.
        uci -q delete "https-dns-proxy.$_sec" || continue
        _changed=1
    done

    if [ "$_changed" = 1 ]; then
        uci commit https-dns-proxy >/dev/null 2>&1 || return 1
        /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
    fi
    return 0
}

rollback_firewall_targeted() {
    firewall_resolve_zones >/dev/null 2>&1 || true
    _changed=0

    if [ "$(uci -q get "firewall.$FW_DNS_REDIRECT_SECTION" 2>/dev/null)" = redirect ] && \
       [ -n "${FIREWALL_LAN_ZONE:-}" ] && \
       firewall_section_owned_redirect "$FW_DNS_REDIRECT_SECTION" "$FIREWALL_LAN_ZONE" 'tcp udp' 53 "$LAN_IP" 53 DNAT; then
        uci -q delete "firewall.$FW_DNS_REDIRECT_SECTION" || return 1
        firewall_owner_remove "$FW_DNS_REDIRECT_SECTION" || true
        _changed=1
    fi

    if [ "$(uci -q get "firewall.$FW_DOT_SECTION" 2>/dev/null)" = rule ] && firewall_dot_rule_matches "$FW_DOT_SECTION"; then
        uci -q delete "firewall.$FW_DOT_SECTION" || return 1
        firewall_owner_remove "$FW_DOT_SECTION" || true
        _changed=1
    fi

    # Also handle legacy manager ownership records, but only after the complete
    # runtime signature has been confirmed. Never remove a rule by name alone.
    if [ -f "$FIREWALL_OWNERSHIP" ]; then
        while IFS= read -r _sec; do
            [ -n "$_sec" ] || continue
            case "$_sec" in
                "$FW_DNS_REDIRECT_SECTION") continue;;
                "$FW_DOT_SECTION") continue;;
            esac
            case "$(uci -q get "firewall.$_sec" 2>/dev/null)" in
                redirect)
                    if [ -n "${FIREWALL_LAN_ZONE:-}" ] && firewall_section_owned_redirect "$_sec" "$FIREWALL_LAN_ZONE" 'tcp udp' 53 "$LAN_IP" 53 DNAT; then
                        uci -q delete "firewall.$_sec" || continue
                        firewall_owner_remove "$_sec" || true
                        _changed=1
                    fi
                    ;;
                rule)
                    if firewall_dot_rule_matches "$_sec"; then
                        uci -q delete "firewall.$_sec" || continue
                        firewall_owner_remove "$_sec" || true
                        _changed=1
                    fi
                    ;;
            esac
        done < "$FIREWALL_OWNERSHIP"
    fi

    if [ "$_changed" = 1 ]; then
        uci commit firewall >/dev/null 2>&1 || return 1
        reload_fw >/dev/null 2>&1 || true
    fi
    return 0
}

clear_dns_core_runtime_state() {
    SLOT_1=""; SLOT_2=""; SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""
    SLOT_RU=""
    PORT_1=""; PORT_2=""; PORT_3=""; PORT_4=""; PORT_5=""; PORT_6=""
    PORT_RU=""
    SLOT_1_CAT=""; SLOT_2_CAT=""; SLOT_3_CAT=""; SLOT_4_CAT=""; SLOT_5_CAT=""; SLOT_6_CAT=""
    SLOT_RU_CAT=""
    QUICK_PREF_1=""; QUICK_PREF_2=""; QUICK_PREF_3=""; QUICK_PREF_4=""; QUICK_PREF_5=""; QUICK_PREF_6=""
    DNS_PROFILE="none"
    DNS_SELECTION_MODE="none"
    DNS_SELECTION_CATEGORY="none"
    TLD_RU_ENABLED=0
    TLD_SPLIT=0
    BALANCER_ENABLED=0
    save_config >/dev/null 2>&1
}
restore_dns_core() {
    acquire_mutation_lock || return 1
    clear_screen
    printf "%s\n" "${C_YELLOW}=== Восстановление стандартной настройки DNS ===${C_NC}"

    _rc=0
    rollback_hdp_targeted >/dev/null 2>&1 || _rc=1
    rollback_dnsmasq_targeted >/dev/null 2>&1 || _rc=1
    rollback_firewall_targeted >/dev/null 2>&1 || _rc=1
    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
    reload_fw >/dev/null 2>&1 || true
    clear_dns_core_runtime_state || _rc=1

    if [ "$_rc" -eq 0 ]; then
        ok_msg "Стандартная настройка DNS восстановлена."
    else
        err_msg "Стандартную настройку DNS удалось восстановить не полностью."
    fi
    [ "${SILENT_APPLY:-0}" = 1 ] || pause
    release_mutation_lock
    return "$_rc"
}
manager_force_config_matches() {
    [ -f /etc/config/https-dns-proxy ] || return 1
    [ "$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)" = 1 ] || return 1
    [ "$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null)" = 1 ] || return 1
    [ "$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null)" = "*" ] || return 1
    [ "$(uci -q get https-dns-proxy.config.force_dns_port 2>/dev/null)" = "53 853" ] || return 1
    [ "$(uci -q get https-dns-proxy.config.force_dns_src_interface 2>/dev/null)" = "lan" ] || return 1
    return 0
}
uninstall_manager_impl() {
    clear_screen
    menu_header "УДАЛЕНИЕ DNS MANAGER"
    warn_msg "DNS Manager будет удалён, его функции выключены, а созданные им настройки и службы очищены."
    printf "\n${C_YELLOW}Изменения сторонних служб и настроек автоматически не восстанавливаются и не удаляются.${C_NC}\n\n"
    confirm_action "Полностью удалить DNS Manager?" || { info_msg "Отменено."; pause; return 0; }

    acquire_mutation_lock || return 1
    _rc=0

    _hdp_package_owned=0
    [ -f "$PACKAGE_OWNERSHIP" ] && grep -Fqx "https-dns-proxy" "$PACKAGE_OWNERSHIP" 2>/dev/null && _hdp_package_owned=1

    watchdog_service_stop_disable >/dev/null 2>&1 || true
    watchdog_cron_remove_owned_block >/dev/null 2>&1 || true

    rollback_hdp_targeted >/dev/null 2>&1 || _rc=1
    rollback_dnsmasq_targeted >/dev/null 2>&1 || _rc=1
    rollback_firewall_targeted >/dev/null 2>&1 || _rc=1

    # Disable forced-DNS only when the live configuration matches the exact
    # DNS Manager contract. External forced-DNS configurations are left alone.
    if manager_force_config_matches; then
        FORCE_DOH=0
        remove_dns_force >/dev/null 2>&1 || _rc=1
    fi
    if [ "$(check_module_state dnsmasq_perf 2>/dev/null)" = 1 ]; then
        DNSMASQ_PERF=0
        remove_dnsmasq_perf >/dev/null 2>&1 || _rc=1
    fi
    if [ "$(check_module_state ntp 2>/dev/null)" = 1 ]; then
        remove_ntp_ip_fallback >/dev/null 2>&1 || _rc=1
    fi
    if rollback_ownership_has file /etc/dnsmasq.d/90-dns-manager-bogus.conf created; then
        rm -f /etc/dnsmasq.d/90-dns-manager-bogus.conf >/dev/null 2>&1 || _rc=1
    fi

    if [ "$_hdp_package_owned" = 1 ]; then
        /etc/init.d/https-dns-proxy stop >/dev/null 2>&1 || true
    else
        /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
    fi
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
    reload_fw >/dev/null 2>&1 || true

    watchdog_service_remove_files >/dev/null 2>&1 || _rc=1

    if ! package_owner_remove_owned >/dev/null 2>&1; then
        warn_msg "Некоторые пакеты DNS Manager не удалось удалить."
        _rc=1
    fi
    if [ "$_hdp_package_owned" = 1 ]; then
        rm -f /etc/config/https-dns-proxy >/dev/null 2>&1 || _rc=1
    fi

    if ! luci_companion_remove >/dev/null 2>&1; then
        warn_msg "Нативный интерфейс LuCI DNS Manager не удалось удалить полностью."
        _rc=1
    fi

    rm -rf "$BASE_DIR" 2>/dev/null || _rc=1
    rm -f "$LOG_FILE" "$TX_LOG" 2>/dev/null || true
    rm -rf "$STATE_DIR" 2>/dev/null || true
    cleanup_stale_tmp_dirs >/dev/null 2>&1 || true
    find /tmp -maxdepth 1 -type f -name "dns-manager-update-*" -mmin +30 -exec rm -f {} \; 2>/dev/null || true
    rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache* 2>/dev/null || true

    rm -f "$MANAGER_PATH" 2>/dev/null || _rc=1

    release_mutation_lock
    if [ "$_rc" -eq 0 ]; then
        printf "\n${C_GREEN}${C_BOLD}DNS Manager полностью удалён.${C_NC}\n"
        printf "${C_GREEN}Функции выключены, собственные DNS/Firewall/служебные настройки очищены.${C_NC}\n"
        exit 0
    fi

    err_msg "DNS Manager удалён не полностью. Проверьте остаточные файлы и журнал DNS Manager."
    pause
    return 1
}
uninstall_manager() {
    # Directly invoked from the installed executable or menu.
    uninstall_manager_impl "$@"
}

# ==========================================
# ==========================================
state_word() {
case "$1" in
yes|1|on|working|running) printf "${C_GREEN}ВКЛ • работает${C_NC}";;
no|0|off|stopped|missing) printf "${C_YELLOW}ВЫКЛ •${C_NC}";;
warn|warning) printf "${C_YELLOW}ВНИМАНИЕ${C_NC}";;
error|fail) printf "${C_RED}ОШИБКА${C_NC}";;
*) printf "${C_WHITE}%s${C_NC}" "$1";;
esac
}
status_ru() {
case "$1" in
OK) printf '%s' '✓ работает';;
BOOTSTRAP_FAIL) printf '%s' '⚠ не удалось определить адрес сервера';;
BAD_DOH_RESPONSE) printf '%s' '⚠ неверный ответ DNS-сервер';;
CURL_TIMEOUT|CURL_TIMEOUT*) printf '%s' '✗ тайм-аут соединения';;
TLS_ERROR|TLS_ERROR*) printf '%s' '✗ ошибка TLS/сертификата';;
CONNECTION_ERROR|CONNECTION_ERROR*) printf '%s' '✗ сервер недоступен';;
DNS_ERROR|DNS_ERROR*) printf '%s' '✗ ошибка DNS-запроса';;
HTTP_400) printf '%s' '✗ сервер отклонил запрос (400)';;
HTTP_401) printf '%s' '✗ требуется авторизация (401)';;
HTTP_403) printf '%s' '✗ доступ запрещён (403)';;
HTTP_404) printf '%s' '✗ адрес DNS-сервер не найден (404)';;
HTTP_429) printf '%s' '✗ слишком много запросов (429)';;
HTTP_500) printf '%s' '✗ ошибка сервера (500)';;
HTTP_502) printf '%s' '✗ шлюз сервера недоступен (502)';;
HTTP_503) printf '%s' '✗ сервис временно недоступен (503)';;
HTTP_504) printf '%s' '✗ сервер не ответил вовремя (504)';;
HTTP_*) printf '%s' "✗ ответ HTTPS: код ${1#HTTP_}";;
CURL_ERROR*) printf '%s' '✗ ошибка соединения HTTPS';;
*) printf '%s' '✗ неизвестная ошибка';;
esac
}
category_ru() {
case "$1" in
bypass) printf '%s' 'Обход';;
clean) printf '%s' 'Чистый';;
security) printf '%s' 'Безопасность';;
privacy) printf '%s' 'Приватность';;
adblock) printf '%s' 'Блокировка рекламы';;
family) printf '%s' 'Семейный';;
regional) printf '%s' 'Региональный';;
*) printf '%s' "$1";;
esac
}
hybrid_runtime_state_word() {
    case "${DNS_PROFILE:-}" in
        hybrid|custom) ;;
        *) return 0 ;;
    esac

    _expected=0
    _actual=0

    for _hs in 1 2 3 4 5 6 RU; do
        eval "_hid=\${SLOT_${_hs}:-}"
        [ -n "$_hid" ] || continue

        _expected=$((_expected + 1))

        eval "_hp=\${PORT_${_hs}:-}"
        [ -n "$_hp" ] || _hp="$(hybrid_desired_port "$_hs")"

        _hu="$(normalize_url "$(dns_url "$_hid")")"

        if [ -s "${DOH_INV:-}" ] && awk -F'|' -v p="$_hp" -v u="$_hu" '$2==p && $4=="yes" && $5==u {ok=1} END{exit !ok}' "$DOH_INV" 2>/dev/null; then
            _actual=$((_actual + 1))
        fi
    done

    if [ "$_expected" -eq 0 ]; then
        printf "${C_YELLOW}ВЫКЛ • не настроен${C_NC}"
    elif [ "$_actual" -eq "$_expected" ]; then
        printf "${C_GREEN}ВКЛ • работает${C_NC}"
    elif [ "$_actual" -gt 0 ]; then
        printf "${C_YELLOW}ВКЛ • работает частично${C_NC}"
    else
        printf "${C_YELLOW}ВКЛ • настроен, но не запущен${C_NC}"
    fi
}
# ==========================================
# ==========================================
show_map() {
sync_regional_dns_state
menu_header "СОСТОЯНИЕ РОУТЕРА"
menu_section "СИСТЕМА"
printf_plain_row "OpenWrt" "$SYS_OWRT"
printf_plain_row "Платформа" "$SYS_TARGET"
printf_plain_row "Архитектура" "$SYS_ARCH"
printf_plain_row "DNS Watchdog" "$(module_state_word watchdog)"
printf_plain_row "Watchdog core" "procd"
printf_plain_row "Watchdog scheduler" "procd"
printf_plain_row "Crond" "$(state_word "$WATCHDOG_CRON_RUNNING")"
printf_plain_row "Firewall" "$SYS_FW"
printf_plain_row "Backend" "$FIREWALL_BACKEND"
printf_plain_row "LAN" "$LAN_IP"
printf_plain_row "WAN" "$WAN_PROTO"
printf_plain_row "IPv4" "$(state_word "$IPV4_ROUTE")"
printf_plain_row "IPv6" "$(state_word "$IPV6_ROUTE")"
printf_plain_row "curl" "$(state_word "$HAS_CURL")"
printf_plain_row "dig" "$(state_word "$HAS_DIG")"
menu_section "DNS"
printf_plain_row "dnsmasq" "$(state_word "$DNSMASQ_RUN")"
refresh_doh_scheme_counts
printf_plain_row "DNS-серверов всего" "$DOH_TOTAL"
printf_plain_row "По текущей схеме" "$DOH_MATCH"
printf_plain_row "Вне текущей схемы" "$DOH_OTHER"
hybrid_runtime_state_word | grep -q . && printf_plain_row "Локальный DoH" "$(hybrid_runtime_state_word)"
menu_section "DNS В СЛОТАХ"
printf "  ${C_WHITE}%-6s %s${C_NC}\n" "СЛОТ" "DNS"
for _s in 1 2 3 4 5 6; do
    eval "_v=\${SLOT_$_s:-}"
    [ -n "$_v" ] || continue
    printf "  %-6s %s\n" "$_s" "$(dns_name "$_v")"
done
if [ -n "${SLOT_RU:-}" ]; then
    printf "  %-6s %s\n" "RU" "$(dns_name "$SLOT_RU")"
else
    printf "  %-6s %s\n" "RU" "не выбран"
fi
if [ "${DOH_TOTAL:-0}" -gt 0 ]; then
    menu_section "ФАКТИЧЕСКИЕ DNS"
    while IFS="|" read -r _idx _port _addr _running _url; do
        [ -n "$_url" ] || continue
        _name="$(awk -F"|" -v u="$_url" '$5==u{print $4;exit}' "$DNS_CATALOG" 2>/dev/null)"
        [ -n "$_name" ] || _name="Пользовательский DNS"
        _slot="";
        for _s in 1 2 3 4 5 6 RU; do
            eval "_sid=\${SLOT_${_s}:-}"; eval "_sport=\${PORT_${_s}:-}"
            [ -n "$_sid" ] && [ -n "$_sport" ] || continue
            [ "$_sport" = "$_port" ] || continue
            [ "$(normalize_url "$(dns_url "$_sid")")" = "$_url" ] || continue
            _slot="$_s"; break
        done
        [ -n "$_slot" ] && _where="слот $_slot" || _where="вне слотов"
        [ "$_running" = yes ] && _state="запущен" || _state="остановлен"
        printf "  %-30s %s · %s\n" "$_name" "$_where" "$_state"
    done < "$DOH_INV"
fi
menu_section "FIREWALL"
printf_plain_row "Активный nft" "$(state_word "$NFT_ACTIVE")"
printf_plain_row "Активный iptables" "$(state_word "$IPTABLES_ACTIVE")"
printf_plain_row "Аппаратное ускорение" "$(state_word "$FLOW_OFFLOAD")"
menu_section "НАСТРОЙКИ DNS Manager"
_profile_name="Не выбран"
# Display the intended profile category. Runtime clean fallback DNS does not
# change this value.
if [ "${DOH_TOTAL:-0}" -gt 0 ] 2>/dev/null && [ "${DOH_MATCH:-0}" -eq "${DOH_TOTAL:-0}" ] 2>/dev/null; then
case "${DNS_SELECTION_MODE:-}:${DNS_SELECTION_CATEGORY:-}" in
    quick:bypass|profile:bypass) _profile_name="Обход блокировок";;
    profile:clean) _profile_name="Без фильтрации";;
    profile:security) _profile_name="Безопасность";;
    profile:privacy) _profile_name="Приватность";;
    profile:adblock) _profile_name="Блокировка рекламы";;
    profile:family) _profile_name="Семейный DNS";;
    manual:none) _profile_name="Собственный выбор";;
    *) ;;
esac
fi
printf_state_row "Текущий профиль" "$_profile_name"
printf_state_row "Балансировка DNS" "$(module_state_word balance "$BALANCER_ENABLED")"
printf_state_row "Отдельный DNS (.ru/.su/.рф)" "$(module_state_word tld "$TLD_SPLIT")"
printf_state_row "Принудительный DNS" "$(force_state_word)"
printf_state_row "Увеличенный кэш DNS" "$(module_state_word dnsmasq_perf "$DNSMASQ_PERF")"
menu_section "ЖУРНАЛ"
printf "${C_WHITE}Последние события:${C_NC}\n"
if [ -s "$LOG_FILE" ]; then grep -v -E "Автообновление: выполняю реальную проверку GitHub:|Автообновление: текущая версия .* актуальна\.|Автообновление: удалённая версия .* не новее текущей" "$LOG_FILE" | tail -15 | sed -e "s/ START / Запуск /" -e "s/ UPDATE / Обновление /" -e "s/ INFO / Информация: /" -e "s/ WARN / Внимание: /" -e "s/ ERROR / Ошибка: /"; else printf "${C_YELLOW}Журнал пока пуст.${C_NC}\n"; fi
echo ""
if [ -s "$TEST_RESULTS" ]; then
    _last_test_ts="$(sed -n 's/^timestamp=\([0-9][0-9]*\)$/\1/p' "$TEST_RESULTS_META" 2>/dev/null | head -n1)"
    _last_test_date=""
    if [ -n "$_last_test_ts" ]; then
        _last_test_date="$(date -d "@$_last_test_ts" '+%d.%m.%Y %H:%M:%S' 2>/dev/null)"
    fi
    if [ -n "$_last_test_date" ]; then
        printf "${C_WHITE}Последняя проверка: ${C_CYAN}%s${C_NC}\n" "$_last_test_date"
    else
        printf "${C_WHITE}Последняя проверка${C_NC}\n"
    fi
    _status_total="$(sed -n 's/^catalog_count=\([0-9][0-9]*\)$/\1/p' "$TEST_RESULTS_META" 2>/dev/null | head -n1)"
    case "$_status_total" in ''|*[!0-9]*) _status_total="$(wc -l < "$TEST_RESULTS" 2>/dev/null | tr -d ' ')";; esac
    case "$_status_total" in ''|*[!0-9]*) _status_total=0;; esac
    _status_ok="$(awk -F'|' 'NF>=5 && $5=="OK"{n++} END{print n+0}' "$TEST_RESULTS" 2>/dev/null)"
    _status_fail=$((_status_total-_status_ok))
    [ "$_status_fail" -lt 0 ] 2>/dev/null && _status_fail=0
    printf "  DNS: ${C_GREEN}%s работают${C_NC}, ${C_YELLOW}%s не прошли${C_NC}, всего %s\n" "$_status_ok" "$_status_fail" "$_status_total"
else
    printf "${C_WHITE}Последняя проверка${C_NC}\n"
    printf "  ${C_YELLOW}Тест DNS ещё не запускался.${C_NC}\n"
fi
_tx_meaningful=0
if [ -s "$TX_LOG" ]; then
    awk -F'|' 'NF>=8 && $4 != "" && $5 != "" && $6 != "" && $7 != "" {found=1; exit} END{exit found?0:1}' "$TX_LOG" >/dev/null 2>&1 && _tx_meaningful=1
fi
if [ "$_tx_meaningful" = 1 ]; then
    echo ""
    printf "${C_WHITE}Последние действия:${C_NC}\n"
    tail -10 "$TX_LOG" | awk -F'|' 'NF>=8 && $4 != "" && $5 != "" && $6 != "" && $7 != "" {
        phase=$4; obj=$5; act=$6; res=$7;
        if (phase=="DISCOVER") phase="Проверка состояния";
        else if (phase=="TEST") phase="Тест";
        else if (phase=="PLAN") phase="Подготовка";
        else if (phase=="APPLY") phase="Настройка";
        else if (phase=="VERIFY") phase="Проверка результата";
        if (res=="OK") res="успешно"; else if (res=="FAIL") res="ошибка";
        printf "  %s: %s → %s → %s\n", phase,obj,act,res;
    }'
fi
printf "${C_GREEN}[Enter]${C_NC} Назад\n"
safe_read _status_action
}
# ==========================================
# ==========================================
show_tests() {
menu_header "РЕЗУЛЬТАТЫ ПРОВЕРКИ DNS"
[ -s "$TEST_RESULTS" ] || { printf "${C_YELLOW}Тест ещё не запускался.${C_NC}
"; pause; return; }
_test_scope="all"
if [ -s "$TEST_RESULTS_META" ]; then
    _test_scope="$(sed -n 's/^test_scope=//p' "$TEST_RESULTS_META" 2>/dev/null | head -n1)"
fi
case "$_test_scope" in
    all|bypass|clean|security|privacy|adblock|family) ;;
    *) _test_scope=all ;;
esac
if [ "$_test_scope" = all ]; then
    total="$(count_dns)"
    _scope_label="весь каталог"
else
    total="$(awk -F'|' -v c="$_test_scope" 'NF>=5 && $1 !~ /^#/ && ($2==c || $2=="regional") {n++} END{print n+0}' "$DNS_CATALOG" 2>/dev/null)"
    _scope_label="категория «$(category_ru "$_test_scope")» + региональные DNS"
fi
okn="$(awk -F'|' 'NF>=5 && $5=="OK"{n++} END{print n+0}' "$TEST_RESULTS" 2>/dev/null)"
failn=$((total-okn))
printf "${C_GREEN}✓ Работают: %s${C_NC}    ${C_RED}✗ Ошибки: %s${C_NC}    ${C_WHITE}Всего: %s${C_NC}
" "$okn" "$failn" "$total"
printf "${C_CYAN}Область проверки: %s${C_NC}

" "$_scope_label"
printf "${C_YELLOW}${C_BOLD}%-28s %-18s %-9s %s${C_NC}
" "DNS" "КАТЕГОРИЯ" "ВРЕМЯ" "СТАТУС"
printf "  ──────────────────────────────────────────────────────────
"
{ grep '|OK$' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n; grep -v '|OK$' "$TEST_RESULTS" 2>/dev/null; } | while IFS='|' read -r id cat name ms st; do
status_text="$(status_ru "$st")"
cat_text="$(category_ru "$cat")"
case "$st" in
OK) status="${C_GREEN}${status_text}${C_NC}";;
BOOTSTRAP_FAIL|BAD_DOH_RESPONSE) status="${C_YELLOW}${status_text}${C_NC}";;
*) status="${C_RED}${status_text}${C_NC}";;
esac
case "$ms" in ''|-1) time="—";; *) time="${ms} мс";; esac
printf "%-28s %-18s %-9s %b
" "$name" "$cat_text" "$time" "$status"
done
pause
}
profile_apply_begin() {
    PROFILE_APPLY=1
    PROFILE_FULL_TEST=1
    PROFILE_OLD_NTP_IP_FALLBACK="${NTP_IP_FALLBACK:-0}"
    PROFILE_OLD_FORCE_DOH="${FORCE_DOH:-0}"
    PROFILE_OLD_DNSMASQ_PERF="${DNSMASQ_PERF:-0}"
    PROFILE_OLD_WATCHDOG_ENABLED="${WATCHDOG_ENABLED:-0}"
    test_dns_catalog "$1" || { PROFILE_FULL_TEST=0; PROFILE_APPLY=0; return 1; }
}
profile_apply_end() {
    NTP_IP_FALLBACK="$PROFILE_OLD_NTP_IP_FALLBACK"
    FORCE_DOH="$PROFILE_OLD_FORCE_DOH"
    DNSMASQ_PERF="$PROFILE_OLD_DNSMASQ_PERF"
    WATCHDOG_ENABLED="$PROFILE_OLD_WATCHDOG_ENABLED"
    PROFILE_FULL_TEST=0
    PROFILE_APPLY=0
}

apply_profile_now() {
goal="$1"
case "$goal" in
bypass)
    profile_apply_begin "$goal" || { _profile_rc=$?; profile_apply_end; return "$_profile_rc"; }
    quick_max_bypass
    _profile_rc=$?
    profile_apply_end
    return "$_profile_rc"
    ;;
clean|security|privacy|adblock|family|all)
    profile_apply_begin "$goal" || { _profile_rc=$?; profile_apply_end; return "$_profile_rc"; }
    # Profile selection changes only the DNS selection. Preserve the operator's
    # current regional DNS where requested, while the Hybrid DNS core remains on.
    _profile_old_ru="${SLOT_RU:-}"

    _profile_old_ru_cat="${SLOT_RU_CAT:-regional}"

    _profile_old_tld="${TLD_RU_ENABLED:-0}"
    # Every ready-made category uses the same Hybrid DNS engine.
    # The category changes only which DNS candidates are selected; Hybrid remains
    # the core layout with general slots plus regional RU routing.
    DNS_PROFILE="hybrid"
    DNS_SELECTION_MODE="profile"
    DNS_SELECTION_CATEGORY="$goal"
    TLD_RU_ENABLED=1
    TLD_SPLIT=1
    BALANCER_ENABLED=1
    PORT_1="$HYBRID_PORT_1"; PORT_2="$HYBRID_PORT_2"; PORT_3="$HYBRID_PORT_3"
    PORT_4="$HYBRID_PORT_4"; PORT_5="$HYBRID_PORT_5"; PORT_6="$HYBRID_PORT_6"
    if auto_fill_slots "$goal"; then
        # auto_fill_slots() already built the exact candidate set for the
        # requested category. Do not run adaptive_hybrid_prepare() afterwards:
        # that stage is intentionally for the generic Hybrid/Max Bypass mode
        # and would reselect the default bypass pool.
        _profile_old_stage_skip="${HYBRID_STAGE_SKIP:-0}"
        HYBRID_STAGE_SKIP=1
        # On first profile selection there may be no prior RU slot. In that
        # case keep the RU server selected by auto_fill_slots(). Only restore
        # the old RU state when it actually existed before this profile change.
        if [ -n "$_profile_old_ru" ]; then
            SLOT_RU="$_profile_old_ru"
            SLOT_RU_CAT="$_profile_old_ru_cat"
            # Hybrid core always keeps regional routing enabled for every category.
            TLD_RU_ENABLED=1
            TLD_SPLIT=1
            PORT_RU="$HYBRID_PORT_RU"

        fi
        CORE_ONLY=1
        apply_settings
        _profile_rc=$?
        CORE_ONLY=0
        HYBRID_STAGE_SKIP="$_profile_old_stage_skip"
    else
        _profile_rc=1
    fi
    profile_apply_end
    return "$_profile_rc"
    ;;
*)
    warn_msg "Неизвестный профиль DNS."
    pause
    ;;
esac
}
menu_category_select() {
while :; do
menu_header "ВЫБОР DNS"
menu_section "КАТЕГОРИИ"
menu_item "[1]" "Без фильтрации"
menu_item "[2]" "Защита от угроз"
menu_item "[3]" "Конфиденциальность"
menu_item "[4]" "Блокировка рекламы"
menu_item "[5]" "Обход блокировок"
menu_item "[6]" "Семейная фильтрация"
menu_item "[7]" "Все категории"
menu_back
menu_prompt
safe_read goal
[ -z "$goal" ] && return
case "$goal" in
1) apply_profile_now clean;;
2) apply_profile_now security;;
3) apply_profile_now privacy;;
4) apply_profile_now adblock;;
5) apply_profile_now bypass;;
6) apply_profile_now family;;
7) apply_profile_now all;;
*) warn_msg "Неверный пункт."; pause;;
esac
done
}

auto_fill_slots() {
_cat="$1"
if ! case "$_cat" in bypass|clean|security|privacy|adblock|family|all) true;; *) false;; esac; then
    warn_msg "Неизвестная категория DNS."
    pause
    return 1
fi
ensure_test_results_fresh "$_cat" || { warn_msg "Не удалось получить свежие результаты теста."; pause; return 1; }
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
        sync_profile_from_selected_categories >/dev/null
        [ "$DNS_PROFILE" = hybrid ] && HYBRID_STAGE_SKIP=1
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
    slot_set "$slot" "$id" || return 1
    slot_cat_set "$slot" "$_selected_cat" || return 1
    sync_profile_from_selected_categories >/dev/null
    [ "$DNS_PROFILE" = hybrid ] && HYBRID_STAGE_SKIP=1
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
    restore_dns_core
    ;;
*) warn_msg "Неверный пункт."; pause;;
esac
done
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
            # This module changes only dnsmasq cachesize. Its state must not
            # depend on unrelated dnsmasq tuning options.
            _cur="$(uci_value_normalized "dhcp.$_sec.cachesize")"
            _stock_v="$(stock_uci_value_normalized dhcp "dhcp.@dnsmasq[0].cachesize" "1000")"
            _desired_v="$DNSMASQ_CACHE_SIZE"
            if [ "$_cur" = "$_stock_v" ]; then
                printf 0
            elif [ "$_cur" = "$_desired_v" ]; then
                printf 1
            else
                printf 2
            fi
            ;;

        watchdog)
            watchdog_state_word_procd
            ;;
        luci)
            luci_component_state
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
    _fetch_url="${LUCI_COMPANION_URL}?_dmcb=$_cb"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 5 --max-time 30 -H 'User-Agent: DNS-Manager-LuCI' -H 'Cache-Control: no-cache' -o "$_tmp" "$_fetch_url" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 30 --header='User-Agent: DNS-Manager-LuCI' --header='Cache-Control: no-cache' -O "$_tmp" "$_fetch_url" >/dev/null 2>&1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -T 30 -O "$_tmp" "$_fetch_url" >/dev/null 2>&1
    else
        LUCI_COMPANION_FETCH_ERROR="Не найден curl, wget или uclient-fetch."
        rm -f "$_tmp" 2>/dev/null || true
        return 1
    fi

    if [ ! -s "$_tmp" ]; then
        LUCI_COMPANION_FETCH_ERROR="Ошибка загрузки companion с GitHub."
        rm -f "$_tmp" 2>/dev/null || true
        return 1
    fi

    head -n 1 "$_tmp" 2>/dev/null | grep -q '^#!/bin/sh' || { LUCI_COMPANION_FETCH_ERROR="Companion не похож на штатный POSIX shell-установщик."; rm -f "$_tmp"; return 1; }
    grep -Fq '# DNS Manager LuCI companion' "$_tmp" 2>/dev/null || { LUCI_COMPANION_FETCH_ERROR="Не найден маркер DNS Manager LuCI companion."; rm -f "$_tmp"; return 1; }
    grep -Fq '/usr/libexec/rpcd/dns_manager' "$_tmp" 2>/dev/null || { LUCI_COMPANION_FETCH_ERROR="В companion отсутствует ожидаемый RPC backend."; rm -f "$_tmp"; return 1; }
    grep -Eq 'admin/services/dns-manager|admin/services/dns_manager' "$_tmp" 2>/dev/null || { LUCI_COMPANION_FETCH_ERROR="В companion отсутствует меню LuCI Службы → DNS Manager."; rm -f "$_tmp"; return 1; }
    sh -n "$_tmp" >/dev/null 2>&1 || { LUCI_COMPANION_FETCH_ERROR="Companion не прошёл проверку shell-синтаксиса."; rm -f "$_tmp"; return 1; }

    LUCI_COMPANION_FETCH_FILE="$_tmp"
    LUCI_COMPANION_FETCH_VERSION="$(sed -n 's/^# Version:[[:space:]]*//p' "$_tmp" 2>/dev/null | head -n1)"
    return 0
}
luci_installed_version() {
    _v=""
    # overview.js is the code LuCI actually loads; persistent markers are fallbacks.
    [ -r "$LUCI_VIEW_FILE" ] && _v="$(sed -n 's|^// DNS Manager LuCI version: *||p' "$LUCI_VIEW_FILE" 2>/dev/null | head -n1)"
    [ -n "$_v" ] || [ ! -r "$LUCI_STATE_FILE" ] || _v="$(sed -n 's/^version=//p' "$LUCI_STATE_FILE" 2>/dev/null | head -n1)"
    [ -n "$_v" ] || [ ! -r "${BACKUP_DIR:-/etc/dns-manager-luci}/version" ] || _v="$(sed -n 's/^version=//p' "${BACKUP_DIR:-/etc/dns-manager-luci}/version" 2>/dev/null | head -n1)"
    [ -n "$_v" ] || [ ! -r "$LUCI_COMPANION_CACHE" ] || _v="$(sed -n 's/^# Version:[[:space:]]*//p' "$LUCI_COMPANION_CACHE" 2>/dev/null | head -n1)"
    printf '%s' "$_v"
}

luci_companion_check_update() {
    LUCI_REMOTE_VERSION=""
    LUCI_UPDATE_AVAILABLE=0

    luci_component_files_present || return 0

    _installed_ver="$(luci_installed_version 2>/dev/null || true)"
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

    _installed_ver="$(luci_installed_version 2>/dev/null || true)"
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
    _cache_stage="${_installed_cache}.new.$$"
    log_msg "LuCI: обновление $_installed_ver → $_new_ver — устанавливаю новую версию поверх текущей."
    rm -f "$_cache_stage" 2>/dev/null || true
    if ! cp -f "$_tmp" "$_cache_stage" 2>/dev/null || ! chmod 700 "$_cache_stage" 2>/dev/null; then
        rm -f "$_tmp" "$_cache_stage" 2>/dev/null || true
        LUCI_COMPANION_FETCH_FILE=""
        err_msg "Не удалось подготовить новый установщик LuCI."
        return 1
    fi
    rm -f "$_tmp" 2>/dev/null || true
    LUCI_COMPANION_FETCH_FILE=""

    if ! sh "$_cache_stage" update >"$TMP_DIR/luci-install.log" 2>&1; then
        [ -s "$TMP_DIR/luci-install.log" ] && while IFS= read -r _luci_line; do [ -n "$_luci_line" ] && log_msg "LuCI installer: $_luci_line"; done < "$TMP_DIR/luci-install.log"
        rm -f "$_cache_stage" 2>/dev/null || true
        err_msg "Установщик LuCI завершился с ошибкой. Текущая версия интерфейса сохранена."
        return 1
    fi

    if ! luci_component_runtime_valid || ! luci_component_files_present; then
        rm -f "$_cache_stage" 2>/dev/null || true
        err_msg "Новая версия LuCI установлена не полностью."
        return 1
    fi

    mv -f "$_cache_stage" "$_installed_cache" 2>/dev/null || {
        rm -f "$_cache_stage" 2>/dev/null || true
        err_msg "LuCI обновлена, но не удалось сохранить локальную копию установщика."
        return 1
    }
    LUCI_REMOTE_VERSION="$_new_ver"
    LUCI_UPDATE_AVAILABLE=0
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
        # PACKAGE_OWNERSHIP records that the package was absent before installation.
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

# ==========================================
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
    _old_force_doh="${FORCE_DOH:-0}"
    _old_dnsmasq_perf="${DNSMASQ_PERF:-0}"
    case "$_state" in
        0) _new=1 ;;
        1) _new=0 ;;
        2) _new=1; FORCE_APPLY_SETTINGS=1 ;;
    esac

    case "$_module" in
        force) FORCE_DOH="$_new" ;;
        dnsmasq_perf) DNSMASQ_PERF="$_new" ;;
    esac

    if [ "$_module" = watchdog ] && [ "$_new" = 1 ]; then
        _profile_category="$(watchdog_scope_category 2>/dev/null || printf none)"
        if [ "$_profile_category" = none ]; then
            err_msg "Сначала выберите профиль DNS Manager."
            pause
            return 1
        fi
    fi

    case "$_module" in
        watchdog)
            watchdog_apply_toggle "$_new"
            _rc=$?
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

    if [ "$_rc" -ne 0 ]; then
        FORCE_DOH="$_old_force_doh"
        DNSMASQ_PERF="$_old_dnsmasq_perf"
    fi
    FORCE_APPLY_SETTINGS="$_old_force"

    if [ "$_rc" -eq 0 ]; then
        case "$_state:$_module" in
            0:force|2:force) ok_msg "Принудительный DNS для устройств настроен." ;;
            1:force) ok_msg "Принудительный DNS для устройств выключен." ;;
            0:dnsmasq_perf|2:dnsmasq_perf) ok_msg "Увеличенный кэш DNS настроен." ;;
            1:dnsmasq_perf) ok_msg "Увеличенный кэш DNS выключен." ;;
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
printf "  ${C_GREEN}✓${C_NC} до 6 рабочих DNS-серверов (можно начать с одного)\n"
printf "  ${C_GREEN}✓${C_NC} отдельный DNS для .ru / .su / .рф\n"
printf "  ${C_GREEN}✓${C_NC} автоматическая замена неработающих серверов\n"
printf "  ${C_GREEN}✓${C_NC} одновременная работа выбранных DNS\n"
printf "  ${C_GREEN}✓${C_NC} проверка после настройки\n"
printf "  ${C_GREEN}✓${C_NC} сохранение исходных настроек для отката\n\n"
if [ "${PROFILE_FULL_TEST:-0}" = 1 ]; then
    info_msg "Использую только что завершённую полную проверку DNS выбранной категории."
else
    if watchdog_test_results_fresh; then
        info_msg "Использую свежие результаты полной проверки DNS; повторный тест не требуется."
    else
        test_dns_catalog || return 1
    fi
    [ -s "$TEST_RESULTS" ] || return 1
fi
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
auto_fill_slots bypass || return 1
HYBRID_STAGE_SKIP=1
CORE_ONLY=1
apply_settings
_rc=$?
CORE_ONLY=0
HYBRID_STAGE_SKIP=0
return "$_rc"
}
# ==========================================
# ==========================================
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
    _scope="$(sed -n 's/^test_scope=//p' "$TEST_RESULTS_META" 2>/dev/null | head -n1)"
    [ -n "$_scope" ] || _scope=all
    _expected_scope="${1:-all}"
    case "$_expected_scope" in
        all|bypass|clean|security|privacy|adblock|family) ;;
        *) _expected_scope=all ;;
    esac
    [ "$_scope" = "$_expected_scope" ] || return 1
    _expected_count=0
    if [ "$_scope" = all ]; then
        _expected_count="$(count_dns)"
    else
        _expected_count="$(awk -F'|' -v c="$_scope" 'NF>=5 && $1 !~ /^#/ && ($2==c || $2=="regional") {n++} END{print n+0}' "$DNS_CATALOG" 2>/dev/null)"
    fi
    _now="$(date +%s 2>/dev/null)"
    case "$_ts" in ''|*[!0-9]*) return 1;; esac
    case "$_now" in ''|*[!0-9]*) return 1;; esac
    case "$_cc" in ''|*[!0-9]*) return 1;; esac
    [ -n "$_cv" ] || return 1
    [ -n "$_ch" ] || return 1
    [ "$_cv" = "$(dns_catalog_version)" ] || return 1
    [ "$_cc" = "$_expected_count" ] || return 1
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
    test_dns_catalog "$_fresh_cat" || return 1
    watchdog_test_results_fresh
}
watchdog_scope_category() {
    # Saved profile category is the intended category. Clean fallback DNS is
    # runtime-only and must never rewrite this value.
    case "${DNS_SELECTION_MODE:-}" in
        quick) printf "%s\n" bypass ;;
        profile)
            case "${DNS_SELECTION_CATEGORY:-}" in
                bypass|clean|security|privacy|adblock|family) printf "%s\n" "$DNS_SELECTION_CATEGORY" ;;
                *) return 1 ;;
            esac
            ;;
        *) return 1 ;;
    esac
}
watchdog_desired_cat() {
    local _slot
    _slot="$1"
    case "$_slot" in
        RU) printf "%s\n" regional ;;
        1|2|3|4|5|6) watchdog_scope_category ;;
        *) return 1 ;;
    esac
}
watchdog_target_live_count() {
    _target_live=0
    _target_cat="$(watchdog_scope_category 2>/dev/null || true)"
    [ -n "$_target_cat" ] || { printf "0\n"; return 0; }
    for _tls in 1 2 3 4 5 6; do
        eval "_tlid=\${SLOT_${_tls}:-}"
        [ -n "$_tlid" ] || continue
        [ "$(dns_cat "$_tlid" 2>/dev/null || true)" = "$_target_cat" ] || continue
        watchdog_check_slot "$_tls" >/dev/null 2>&1 && _target_live=$((_target_live+1))
    done
    printf "%s\n" "$_target_live"
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
    log_msg "Обнаружен drift forced-DNS. Возвращаю конфигурацию DNS Manager."
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
        # External forced-DNS is a valid coexistence state.
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
    local _slot _id _port _domain
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
watchdog_preferred_quick_candidate() {
    local _slot _pref
    _slot="$1"
    case "$_slot" in
        1|2|3|4|5|6) eval "_pref=\${QUICK_PREF_$_slot:-}" ;;
        *) _pref="" ;;
    esac
    [ -n "$_pref" ] || return 1
    printf '%s\n' "$_pref"
}
watchdog_pick_replacement() {
    local _slot _used _tried _allow_clean _profile_all_scope _selection_kind _desired_for_pick _passcats _results_scope _fresh_source _fresh_pass_source _passcat _checked_cat _rid _rcat _fresh_pick _fresh_rest _rurl _u _current_id _current_cat _current_url _url
    _slot="$1"
    _used="$2"
    _tried="$3"
    _allow_clean="${4:-0}"
    _profile_all_scope=0
    if [ "${DNS_SELECTION_MODE:-}" = profile ] && [ "${DNS_SELECTION_CATEGORY:-}" = all ]; then
        # "Все категории" is allowed to repair during an explicit profile apply.
        # Background watchdog still rejects mixed/all selections via
        # watchdog_scope_category().
        _selection_kind=all
        _profile_all_scope=1
        if [ "$_slot" = RU ]; then
            _desired_for_pick=regional
        else
            _desired_for_pick=all
        fi
    else
        _selection_kind="$(watchdog_scope_category 2>/dev/null || true)"
        [ -n "$_selection_kind" ] || return 1
        _desired_for_pick="$(watchdog_desired_cat "$_slot")"
        [ -n "$_desired_for_pick" ] || return 1
    fi

    # Prefer the intended category. Clean is only a temporary fallback when
    # no target-category DNS is currently alive anywhere in the profile.
    _passcats="$_desired_for_pick"
    if [ "$_profile_all_scope" = 1 ] && [ "$_slot" != RU ]; then
        _passcats=all
    elif [ "$_allow_clean" = 1 ] && [ "$_slot" != RU ] && [ "$_desired_for_pick" != clean ]; then
        _passcats="$_desired_for_pick clean"
    fi

    # During profile application TEST_RESULTS is the authoritative fresh
    # candidate pool. It already contains the complete selected category
    # (plus regional DNS), so do not cap replacement selection at the first
    # few catalog entries. Pick the fastest fresh OK candidate not already
    # used/tried and let the local post-apply check confirm the actual listener.
    _results_scope="$_selection_kind"
    if watchdog_test_results_fresh "$_results_scope" 2>/dev/null; then
        _fresh_source="$TMP_DIR/watchdog-fresh-candidates-$$-$_slot"
        _fresh_pass_source="$TMP_DIR/watchdog-fresh-pass-$$-$_slot"
        : > "$_fresh_source" || return 1
        : > "$_fresh_pass_source" || { rm -f "$_fresh_source"; return 1; }

        for _passcat in $_passcats; do
            [ -n "$_passcat" ] || continue
            if [ "$_profile_all_scope" = 1 ] && [ "$_slot" != RU ]; then
                awk -F'|' '
                    NF>=5 && $1 !~ /^#/ && $2!="regional" && $5=="OK" && $4 ~ /^[0-9]+$/ {print}
                ' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n > "$_fresh_pass_source"
            else
                awk -F'|' -v c="$_passcat" '
                    NF>=5 && $1 !~ /^#/ && $2==c && $5=="OK" && $4 ~ /^[0-9]+$/ {print}
                ' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n > "$_fresh_pass_source"
            fi

            while IFS="|" read -r _rid _rcat _rname _rms _rst; do
                [ -n "$_rid" ] || continue
                [ "$_rid" != "${_current_id:-}" ] || continue
                [ -n "${REPAIR_BAD_IDS:-}" ] && grep -qxF "$_rid" "$REPAIR_BAD_IDS" 2>/dev/null && continue
                _rurl="$(normalize_url "$(dns_url "$_rid")")"
                [ -n "$_rurl" ] || continue
                grep -qxF "$_rurl" "$_used" 2>/dev/null && continue
                grep -qxF "$_rid" "$_tried" 2>/dev/null && continue
                printf '%s|%s|%s|%s|%s\n' "$_rid" "$_rcat" "$_rname" "$_rms" "$_rst" >> "$_fresh_source"
            done < "$_fresh_pass_source"

            _fresh_pick="$(head -n1 "$_fresh_source" 2>/dev/null)"
            if [ -n "$_fresh_pick" ]; then
                _rid="${_fresh_pick%%|*}"
                _fresh_rest="${_fresh_pick#*|}"
                _rcat="${_fresh_rest%%|*}"
                rm -f "$_fresh_source" "$_fresh_pass_source" 2>/dev/null || true
                printf '%s|%s\n' "$_rid" "$_rcat"
                return 0
            fi
            : > "$_fresh_source"
        done

        rm -f "$_fresh_source" "$_fresh_pass_source" 2>/dev/null || true
    fi

    # Emergency fallback for watchdog/runtime situations where no fresh scoped
    # result exists. Keep the resource-safe candidate cap here; the candidate is
    # accepted only after the real https-dns-proxy instance answers a local DNS
    # query on its assigned port.
    for _passcat in $_passcats; do
        _checked_cat=0

        # In quick mode, try the already preferred bypass entry first.
        if [ "$_passcat" = bypass ] && [ "${DNS_SELECTION_MODE:-}" = quick ]; then
            _preferred="$(watchdog_preferred_quick_candidate "$_slot" 2>/dev/null)"
            if [ -n "$_preferred" ] && [ "$(dns_cat "$_preferred" 2>/dev/null)" = bypass ] && [ "$_preferred" != "${_current_id:-}" ]; then
                _purl="$(normalize_url "$(dns_url "$_preferred")")"
                if [ -n "$_purl" ] && ! grep -qxF "$_purl" "$_used" 2>/dev/null && ! grep -qxF "$_preferred" "$_tried" 2>/dev/null; then
                    _checked_cat=$((_checked_cat+1))
                    if [ "$_checked_cat" -le "${WATCHDOG_MAX_CANDIDATES:-3}" ]; then
                        printf "%s|bypass\n" "$_preferred"
                        return 0
                    fi
                    printf "%s\n" "$_preferred" >> "$_tried"
                fi
            fi
        fi

        while IFS="|" read -r _rid _rcat _rname _rms _rst; do
            [ -n "$_rid" ] || continue
            case "$_rid" in \#*) continue ;; esac
            if [ "$_passcat" = all ] && [ "$_slot" != RU ]; then
                [ "$_rcat" != regional ] || continue
            else
                [ "$_rcat" = "$_passcat" ] || continue
            fi
            [ -n "${REPAIR_BAD_IDS:-}" ] && grep -qxF "$_rid" "$REPAIR_BAD_IDS" 2>/dev/null && continue
            [ "$_rid" != "${_current_id:-}" ] || continue
            _rurl="$(normalize_url "$(dns_url "$_rid")")"
            [ -n "$_rurl" ] || continue
            grep -qxF "$_rurl" "$_used" 2>/dev/null && continue
            grep -qxF "$_rid" "$_tried" 2>/dev/null && continue
            _checked_cat=$((_checked_cat+1))
            [ "$_checked_cat" -le "${WATCHDOG_MAX_CANDIDATES:-3}" ] || break
            # Do not pre-test the candidate through bootstrap DNS. Install it,
            # restart the real https-dns-proxy instance, and let
            # watchdog_apply_slot_candidate() accept it only after a successful
            # local DNS query through 127.0.0.1:PORT.
            printf "%s|%s\n" "$_rid" "$_rcat"
            return 0
        done < "$DNS_CATALOG"
    done
    return 1
}
watchdog_apply_slot_candidate() {
    local _slot _new_id _new_cat _old_id _old_cat _port _new_url
    _slot="$1"; _new_id="$2"; _new_cat="$3"; _old_id="$4"; _old_cat="$5"
    eval "_port=\${PORT_${_slot}:-}"
    [ -n "$_slot" ] || return 1
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
        if [ -n "$_old_id" ]; then
            watchdog_check_slot "$_slot"
        else
            return 0
        fi
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
    if [ -z "$_new_id" ]; then
        if ! save_config; then
            watchdog_candidate_rollback >/dev/null 2>&1 || true
            return 1
        fi
        normalize_ownership_snapshot >/dev/null 2>&1 || true
        return 0
    fi
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
    local _slot _last _now
    _slot="$1"
    eval "_last=\${WD_REPAIR_TS_${_slot}:-0}"
    case "$_last" in ''|*[!0-9]*) _last=0;; esac
    _now="$(date +%s 2>/dev/null)"
    case "$_now" in ''|*[!0-9]*) return 1;; esac
    [ $((_now-_last)) -ge "${WATCHDOG_REPAIR_COOLDOWN:-300}" ] 2>/dev/null
}
watchdog_loop_mark_repair() {
    local _slot _now
    _slot="$1"
    _now="$(date +%s 2>/dev/null)"
    case "$_now" in ''|*[!0-9]*) return 0;; esac
    eval "WD_REPAIR_TS_${_slot}=\$_now"
}
watchdog_loop_reset_slot() {
    local _slot
    _slot="$1"
    eval "WD_FAIL_${_slot}=0"
    eval "WD_MISSING_${_slot}=0"
}
watchdog_embedded_integrity_guard() {
    _selection_kind="$(watchdog_scope_category 2>/dev/null || true)"
    case "$_selection_kind" in
        bypass|clean|security|privacy|adblock|family) ;;
        *) return 0 ;;
    esac
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
    log_msg "Фоновый watchdog embedded/procd запущен: проверка каждые ${WATCHDOG_INTERVAL:-600}с, замена после ${WATCHDOG_FAIL_THRESHOLD:-2} последовательных циклов."

    # Give network + https-dns-proxy a short settling window after procd start/WAN-up.
    sleep 12

    while :; do
        [ "${WATCHDOG_ENABLED:-0}" = 1 ] || return 0
        _interval="${WATCHDOG_INTERVAL:-600}"
        case "$_interval" in ''|*[!0-9]*) _interval=600;; esac
        [ "$_interval" -ge 60 ] 2>/dev/null || _interval=600
        [ "$_interval" -le 3600 ] 2>/dev/null || _interval=600

        load_config >/dev/null 2>&1 || true
        _selection_kind="$(watchdog_scope_category 2>/dev/null || true)"
        case "$_selection_kind" in
            bypass|clean|security|privacy|adblock|family) ;;
            *)
                sleep "$_interval"
                continue
                ;;
        esac

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
        _fallback_slots=""
        _empty_slots=""
        _probe_rc=0
        _target_live_count=0

        watchdog_refresh_listener_snapshot

        for _slot in 1 2 3 4 5 6 RU; do
            eval "_id=\${SLOT_${_slot}:-}"
            _current_slot_cat=""; [ -n "$_id" ] && _current_slot_cat="$(dns_cat "$_id" 2>/dev/null || true)"
            eval "_port=\${PORT_${_slot}:-}"
            [ -n "$_port" ] || _port="$(hybrid_desired_port "$_slot")"
            case "$_slot" in RU) _domain="yandex.ru" ;; *) _domain="example.com" ;; esac
            _desired_slot_cat="$(watchdog_desired_cat "$_slot" 2>/dev/null || true)"
            if [ "$_slot" != RU ] && [ -z "$_id" ]; then
                _empty_slots="$_empty_slots $_slot"
                continue
            fi
            if [ "$_slot" != RU ] && [ "$_desired_slot_cat" != clean ] && [ "$_current_slot_cat" = clean ]; then
                _fallback_slots="$_fallback_slots $_slot"
            fi
            [ -n "$_port" ] || continue

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
            local_dns_query_ok "$_port" "$_domain"
            _probe_rc=$?
            [ "$_probe_rc" = 2 ] && break
            if [ "$_probe_rc" = 0 ]; then
                [ "$_slot" != RU ] && [ "$_current_slot_cat" = "$_desired_slot_cat" ] && _target_live_count=$((_target_live_count+1))
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
        [ "$_checked" -gt 0 ] || { [ -n "$_empty_slots" ] || { sleep "$_interval"; continue; }; }

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
                watchdog_slot_target_run "$_trigger" "$_target_live_count" >/dev/null 2>&1 || log_msg "Точечное восстановление слота $_trigger завершилось неуспешно; повторю после новых двух циклов."
                _watchdog_action=1
                load_config
                refresh_runtime_capabilities
                WD_LAST_GUARD_TS="$(date +%s 2>/dev/null)"
                eval "WD_FAIL_${_trigger}=0"
                sleep 5
            fi
        fi

        if [ "$_watchdog_action" = 0 ] && [ "$_failed" -eq 0 ] && [ "$_missing" -eq 0 ]; then
            _restore_slot=""
            for _slot in $_fallback_slots; do _restore_slot="$_slot"; break; done
            [ -n "$_restore_slot" ] || for _slot in $_empty_slots; do _restore_slot="$_slot"; break; done
            if [ -n "$_restore_slot" ] && [ "$_wd_repairs" -lt "${WATCHDOG_MAX_REPAIRS:-1}" ]; then
                log_msg "Watchdog: проверяю целевую категорию для восстановления/дозаполнения слота $_restore_slot."
                watchdog_slot_target_run "$_restore_slot" "$_target_live_count" >/dev/null 2>&1 && _watchdog_action=1 || true
                load_config >/dev/null 2>&1 || true
                refresh_runtime_capabilities >/dev/null 2>&1 || true
            fi
            if [ "$_watchdog_action" = 0 ]; then
                watchdog_embedded_integrity_guard >/dev/null 2>&1 || true
            fi
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
    _selection_kind="$(watchdog_scope_category 2>/dev/null || true)"
    case "$_selection_kind" in
        bypass|clean|security|privacy|adblock|family) ;;
        *)
            log_msg "Watchdog: смешанные или пользовательские категории DNS. Проверку и замену выбранных DNS не выполняю."
            release_mutation_lock
            return 0
            ;;
    esac
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
    _selection_kind="$(watchdog_scope_category 2>/dev/null || true)"
    for _slot in 1 2 3 4 5 6 RU; do
        [ "$_wd_repairs" -lt "${WATCHDOG_MAX_REPAIRS:-1}" ] || break
        eval "_id=\${SLOT_${_slot}:-}"
        _current_cat=""; [ -n "$_id" ] && _current_cat="$(dns_cat "$_id" 2>/dev/null || true)"
        _desired="$(watchdog_desired_cat "$_slot" 2>/dev/null || true)"
        _force_replace=0
        if [ -n "$_desired" ] && [ "$_slot" != RU ]; then
            if [ -z "$_id" ] || [ "$_current_cat" != "$_desired" ]; then
                _force_replace=1
            fi
        fi
        if [ "$_force_replace" = 0 ] && [ -n "$_id" ] && watchdog_check_slot "$_slot"; then continue; fi
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

service_stopped() {
    procd_running "dns-watchdog" || return 0
    return 1
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

        # procd stops asynchronously; give the service a short grace period
        # before declaring a safe stop failure. This does not change watchdog
        # monitoring logic or restart limits.
        _wd_wait=0
        while watchdog_service_running && [ "$_wd_wait" -lt 5 ]; do
            sleep 1
            _wd_wait=$((_wd_wait + 1))
        done

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
watchdog_service_migrate_legacy() {
    [ "${FIRST_RUN_INITIAL:-0}" = 1 ] && return 0
    [ "${WATCHDOG_ENABLED:-0}" = 1 ] || return 0
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
    local _slot _target_id _target_port _target_cat _promote_fallback _target_live _allow_clean _slot_rc _old_id _old_cat _domain _used _tried _attempt _replacement_ok _picked _repl _repl_cat
    _slot="$1"
    case "$_slot" in 1|2|3|4|5|6|RU) ;; *) return 2 ;; esac
    [ "${WATCHDOG_ENABLED:-0}" = 1 ] || return 0
    _selection_kind="$(watchdog_scope_category 2>/dev/null || true)"
    case "$_selection_kind" in
        bypass|clean|security|privacy|adblock|family) ;;
        *) return 0 ;;
    esac
    eval "_target_id=\${SLOT_${_slot}:-}"
    eval "_target_port=\${PORT_${_slot}:-}"
    [ -n "$_target_port" ] || _target_port="$(hybrid_desired_port "$_slot")"
    [ -n "$_target_port" ] || return 2
    _target_cat="$(watchdog_desired_cat "$_slot")" || return 0
    _promote_fallback=0
    if [ "$_slot" != RU ] && [ -n "$_target_id" ] && [ "$_target_cat" != clean ] && [ "$(dns_cat "$_target_id" 2>/dev/null)" = clean ]; then
        _promote_fallback=1
    fi
    _target_live="${2:-}"
    case "$_target_live" in
        ""|*[!0-9]*) _target_live="$(watchdog_target_live_count 2>/dev/null || printf 0)" ;;
    esac
    case "$_target_live" in ""|*[!0-9]*) _target_live=0;; esac
    _allow_clean=0
    [ "$_target_live" -eq 0 ] && [ "$_promote_fallback" != 1 ] && _allow_clean=1

    if ! watchdog_resource_guard; then
        return 0
    fi
    acquire_mutation_lock || return 0
    WATCHDOG_RESTART_COUNT=0
    _slot_rc=0
    _old_id="$_target_id"
    _old_cat="$(dns_cat "$_old_id" 2>/dev/null)"
    case "$_slot" in RU) _domain="yandex.ru" ;; *) _domain="example.com" ;; esac

    # A healthy clean DNS can be a temporary fallback. Promote it only when a
    # target-category candidate is actually confirmed by the direct probe.
    if [ "$_promote_fallback" != 1 ] && [ -n "$_target_id" ] && watchdog_check_slot "$_slot"; then
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
        _picked="$(watchdog_pick_replacement "$_slot" "$_used" "$_tried" "$_allow_clean")"
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
    if [ "$_replacement_ok" != 1 ] && [ "$_target_live" -gt 0 ] && [ "$_promote_fallback" != 1 ] && [ -n "$_target_id" ]; then
        log_msg "Watchdog: другой DNS целевой категории остаётся рабочим; освобождаю неработающий слот $_slot вместо перехода на clean."
        if watchdog_apply_slot_candidate "$_slot" "" "" "$_old_id" "$_old_cat"; then
            _slot_rc=0
        else
            _slot_rc=1
        fi
    else
        [ "$_replacement_ok" = 1 ] || _slot_rc=1
    fi
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
watchdog_apply_toggle() {
    _new="$1"
    case "$_new" in
        0|1) ;;
        *) return 1 ;;
    esac

    _old_enabled="$(cfg_get WATCHDOG_ENABLED 2>/dev/null || true)"
    [ "$_old_enabled" = 1 ] || _old_enabled=0

    _old_service_present=0
    [ -x "$WATCHDOG_SERVICE_PATH" ] && watchdog_service_file_owned "$WATCHDOG_SERVICE_PATH" "$WATCHDOG_SERVICE_MARKER" && _old_service_present=1
    _old_service_enabled=0
    _old_service_running=0
    [ "$_old_service_present" = 1 ] && watchdog_service_enabled && _old_service_enabled=1 || true
    [ "$_old_service_present" = 1 ] && watchdog_service_running && _old_service_running=1 || true

    WATCHDOG_ENABLED="$_new"
    if apply_watchdog; then
        return 0
    fi

    WATCHDOG_ENABLED="$_old_enabled"
    save_config >/dev/null 2>&1 || true

    if [ "$_old_service_present" = 1 ]; then
        watchdog_service_install_files >/dev/null 2>&1 || true
        if [ "$_old_service_enabled" = 1 ]; then
            "$WATCHDOG_SERVICE_PATH" enable >/dev/null 2>&1 || true
        else
            "$WATCHDOG_SERVICE_PATH" disable >/dev/null 2>&1 || true
        fi
        if [ "$_old_service_running" = 1 ]; then
            "$WATCHDOG_SERVICE_PATH" start >/dev/null 2>&1 || true
        else
            "$WATCHDOG_SERVICE_PATH" stop >/dev/null 2>&1 || true
        fi
    elif [ "$_old_enabled" = 0 ]; then
        watchdog_service_stop_disable >/dev/null 2>&1 || true
        watchdog_service_remove_files >/dev/null 2>&1 || true
    fi

    return 1
}
apply_watchdog() {
    # Stop first so a running watchdog cannot race an in-progress Apply.
    watchdog_service_stop_disable || return 1

    WATCHDOG_BACKEND="procd"
    : "${WATCHDOG_INTERVAL:=${WATCHDOG_CHECK_INTERVAL_DEFAULT:-600}}"
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
menu_item "[1]" "Обход блокировок"
menu_item "[2]" "Без фильтрации"
menu_item "[3]" "Безопасность"
menu_item "[4]" "Приватность"
menu_item "[5]" "Блокировка рекламы"
menu_item "[6]" "Выбор по категориям"
menu_section "РУЧНАЯ НАСТРОЙКА"
menu_item "[7]" "Серверы DNS"
menu_item "[8]" "Проверить DNS-серверы"
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
8) test_dns_catalog; show_tests;;
*) warn_msg "Неизвестный пункт."; pause;;
esac
done
}
# ==========================================
# ==========================================
main_menu() {
while :; do
    menu_header "DNS Manager $VERSION"
    menu_item "[1]" "Настроить DNS"
    menu_item "[2]" "Серверы точного времени"
    menu_item "[3]" "Сетевой тюнинг"
    menu_item "[4]" "Состояние и журнал"
    menu_item "[5]" "Удалить DNS Manager"
    _luci_state="$(check_module_state luci)"
    if [ "$_luci_state" = 1 ]; then
        if [ "${LUCI_UPDATE_AVAILABLE:-0}" = 1 ]; then
            menu_item "[6]" "Обновить LuCI → ${LUCI_REMOTE_VERSION}"
        else
            menu_item "[6]" "Удалить Нативный интерфейс DNS Manager"
        fi
    else
        case "$_luci_state" in
            0) menu_item "[6]" "Установить Нативный интерфейс DNS Manager" ;;
            2) menu_item "[6]" "Восстановить Нативный интерфейс DNS Manager" ;;
            *) menu_item "[6]" "Нативный интерфейс DNS Manager" ;;
        esac
    fi
    menu_back
    menu_prompt
    safe_read c
    [ -z "$c" ] && { clear_screen; printf "${C_GREEN}DNS Manager завершён.${C_NC}\n"; exit 0; }
    case "$c" in
        1) prepare_dns_operation || { pause; continue; }; menu_dns ;;
        2) prepare_dns_operation || { pause; continue; }; menu_ntp ;;
        3) prepare_dns_operation || { pause; continue; }; menu_extras ;;
        4) show_map ;;
        5) uninstall_manager ;;
        6)
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
            ;;
        *) warn_msg "Неизвестный пункт."; pause ;;
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





# ==========================================
# STARTUP UPDATE CHECK
# ==========================================
startup_update_check() {
    # During the re-exec after a successful manager update, never start another
    # network check. The new process only needs to continue normal startup.
    if [ "${DNS_MANAGER_NO_UPDATE:-0}" = 1 ]; then
        return 0
    fi

    # Only the DNS Manager backend checks itself during startup. LuCI/companion
    # updates are checked explicitly from LuCI, not as a hidden second network
    # request during every manager launch.
    auto_update_manager || true
    case "${AUTO_UPDATE_RESULT:-}" in
        updated) info_msg "DNS Manager автоматически обновлён до версии $VERSION." ;;
        failed)
            if [ -n "${AUTO_UPDATE_REASON:-}" ]; then
                log_msg "Проверка обновления DNS Manager не удалась: $AUTO_UPDATE_REASON"
            else
                log_msg "Проверка обновления DNS Manager не удалась."
            fi
            ;;
    esac
    return 0
}
# ==========================================
# STARTUP REQUIRED FUNCTION CHECK
# ==========================================
startup_required_function_check() {
    for _fn in get_dnsmasq_section exact_list_has doh_selected_config_current validate_selected_slots ensure_dnsmasq_balancer detect_forced_dns_path clear_all_doh_for_apply rebuild_selected_hdp_sections reconcile_dnsmasq apply_ntp_ip_fallback luci_component_state luci_companion_check_update luci_companion_install luci_companion_remove luci_companion_update watchdog_embedded_loop watchdog_service_install_files watchdog_service_remove_files; do
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
test-one|--test-one)
    _test_id="${2:-}"
    case "$_test_id" in ''|*[!A-Za-z0-9_-]*) printf '%s|INVALID||||INVALID_ID\n' "$_test_id"; exit 2;; esac
    preflight_readonly >/dev/null 2>&1 || { printf '%s||||PRECHECK_FAILED\n' "$_test_id"; exit 1; }
    init_dirs >/dev/null 2>&1 || { printf '%s||||INIT_FAILED\n' "$_test_id"; exit 1; }
    write_catalogs >/dev/null 2>&1 || true
    load_config >/dev/null 2>&1 || { printf '%s||||CONFIG_FAILED\n' "$_test_id"; exit 1; }
    startup_required_function_check >/dev/null 2>&1 || { printf '%s||||FUNCTION_CHECK_FAILED\n' "$_test_id"; exit 1; }
    DNS_TEST_RAM_ONLY=1
    refresh_runtime_capabilities >/dev/null 2>&1
    [ "$HAS_CURL" = yes ] || { printf '%s|unavailable||||CURL_NOT_FOUND\n' "$_test_id"; exit 1; }
    _test_lock_owned=0
    if [ "${DNS_MANAGER_TEST_LOCK_HELD:-0}" != 1 ]; then
        acquire_test_lock || { printf '%s|unavailable||||TEST_BUSY\n' "$_test_id"; exit 1; }
        _test_lock_owned=1
    fi
    rm -f "$TMP_DIR/t.$_test_id" "$TMP_DIR/dns_query.bin" "$TMP_DIR/body.$_test_id" "$TMP_DIR/h.$_test_id" 2>/dev/null || true
    q="$TMP_DIR/dns_query.bin"
    if ! printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$q" 2>/dev/null; then
        rm -f "$q" 2>/dev/null || true
        [ "$_test_lock_owned" = 1 ] && release_test_lock
        printf '%s||||INTERNAL_TEST_QUERY_CREATE_FAIL\n' "$_test_id"
        exit 1
    fi
    test_one_dns "$_test_id" || true
    _test_result_file="$TMP_DIR/t.$_test_id"
    if [ -s "$_test_result_file" ]; then
        cat "$_test_result_file"
        _test_rc=1
        grep -q '|OK$' "$_test_result_file" 2>/dev/null && _test_rc=0
    else
        printf '%s||||TEST_NO_RESULT\n' "$_test_id"
        _test_rc=1
    fi
    rm -f "$TMP_DIR/t.$_test_id" "$TMP_DIR/dns_query.bin" "$TMP_DIR/body.$_test_id" "$TMP_DIR/h.$_test_id" 2>/dev/null || true
    [ "$_test_lock_owned" = 1 ] && release_test_lock
    exit "$_test_rc"
    ;;
force-state|--force-state)
    preflight_readonly
    init_dirs
    load_config
    startup_required_function_check || exit 1
    refresh_runtime_capabilities
    _force_state="$(check_module_state force)"
    printf '%s\n' "$_force_state"
    exit "$_force_state"
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

printf "\n${C_CYAN}${C_BOLD}▶ DNS Manager $VERSION${C_NC}\n"
printf "  ${C_CYAN}↻${C_NC} Подготавливаю окружение...\n"
preflight_readonly
init_dirs
printf "  ${C_CYAN}↻${C_NC} Проверяю каталог DNS...\n"
write_catalogs
printf "  ${C_CYAN}↻${C_NC} Загружаю конфигурацию...\n"
load_config
startup_required_function_check || exit 1
printf "  ${C_CYAN}↻${C_NC} Проверяю обновления...\n"
startup_update_check
case "${AUTO_UPDATE_RESULT:-}" in
    updated) printf "  ${C_GREEN}✓${C_NC} DNS Manager автоматически обновлён до $VERSION.\n" ;;
    failed) printf "  ${C_YELLOW}!${C_NC} Проверка обновления DNS Manager не удалась.\n" ;;
    *) printf "  ${C_GREEN}✓${C_NC} Проверка обновлений завершена.\n" ;;
esac
printf "  ${C_CYAN}↻${C_NC} Проверяю состояние роутера...\n"
run_discovery
printf "  ${C_GREEN}✓${C_NC} Состояние роутера получено.\n"

if [ "${FIRST_RUN_INITIAL:-0}" = 1 ]; then
    # Initialization only: do not synchronize or mutate cron on first launch.
    info_msg "Первый запуск: watchdog-служба procd не запускается и cron не изменяю."
fi



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

# Check the LuCI companion once before entering the interactive menu.
# main_menu itself can loop without starting repeated network checks.
luci_companion_check_update >/dev/null 2>&1 || true

main_menu
