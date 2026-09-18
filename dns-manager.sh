#!/bin/sh
MANAGER_PATH="/usr/bin/dns-manager"
# ==========================================
# ==========================================
VERSION="2.58"
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
BOOTSTRAP_DNS_ALL="77.88.8.8,77.88.8.1,94.140.14.14,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,9.9.9.9,149.112.112.112,208.67.222.222,208.67.220.220,149.112.121.10,149.112.122.10,76.76.2.0,76.76.10.0,194.242.2.2,194.242.2.3"
DNSCAT_VERSION="8.5-RU-NOSOCIAL"
WATCHDOG_SPEC_VERSION="16"
WATCHDOG_RESTART_COOLDOWN=300
WATCHDOG_LAST_RESTART_FILE="$STATE_DIR/watchdog-last-restart"
AUTO_UPDATE_LAST_CHECK_FILE="$STATE_DIR/auto-update-last-check"
AUTO_UPDATE_CHECK_MAX_AGE=43200
AUTO_UPDATE_LOCK_DIR="$STATE_DIR/auto-update.lock"
TEST_RESULTS_META="$STATE_DIR/dns-test-results.meta"
TEST_RESULTS_MAX_AGE=21600
TEST_DEPENDENCY_WARNING_FILE="$STATE_DIR/dns-test-dependency-warning"
TEST_DEPENDENCY_WARNING_MAX_AGE=3600
TEST_PROGRESS_EVERY=20
# Resource-safety defaults for small OpenWrt routers.
TEST_BATCH_DEFAULT=4
WATCHDOG_MAX_REPAIRS=1
WATCHDOG_MAX_RESTARTS=2
LOG_MAX_BYTES=65536
TX_LOG_MAX_BYTES=65536
OWNERSHIP_MAX_BYTES=32768
TX_KEEP_MINUTES=15
PREV_DNSMASQ="$CFG_DIR/dnsmasq-previous.conf"
PREV_SERVICES="$CFG_DIR/services-previous.conf"
BASELINE_DIR="$BASE_DIR/baseline"
BASELINE_MANIFEST="$BASELINE_DIR/manifest"
BASELINE_LAST="$BASELINE_DIR/last-applied.manifest"
BASELINE_META="$BASELINE_DIR/meta"
OWNERSHIP="$STATE_DIR/ownership.conf"
MTU_BEFORE="$STATE_DIR/mtu-before-zone.conf"
LEGACY_MTU_BEFORE="$STATE_DIR/mtu-before.conf"
NTP_CLIENTS_BEFORE="$STATE_DIR/ntp-clients-before.conf"
FORCE_DNS_BEFORE="$STATE_DIR/force-dns-before.conf"
TEST_RESULTS="$STATE_DIR/dns-test-results.conf"
TEST_LOCK_DIR="$STATE_DIR/dns-test.lock"
TEST_LOCK_HELD=0
WEB_INIT="/etc/init.d/dns-manager-web"
WEB_ACCESS_PORT="7682"
WEB_ACCESS_ENABLED=0
WEB_TTYD_SECTION="dns_manager"
WEB_SERVICE_CONFIG="/etc/init.d/dns-manager-web"
WEB_PIDFILE="/var/run/dns-manager-web.pid"
SYSCTL_BASE_MARKER="# DNS_MANAGER_MANAGED_SYSCTL=1"
SYSCTL_EXTENDED_MARKER="# DNS_MANAGER_MANAGED_SYSCTL_EXTENDED=1"
CLIENT_FIXES_MARKER="# DNS_MANAGER_MANAGED_CLIENT_FIXES=1"
CLIENT_FIXES_FILE=""
FIREWALL_OWNERSHIP="$CFG_DIR/firewall-ownership.conf"
FW_NTP_SECTION="dns_manager_ntp_client"
FW_DNS_REDIRECT_SECTION="dns_manager_dns_redirect"
FW_DOT_SECTION="dns_manager_dot_block"
FW_WEB_SECTION="dns_manager_web_ttyd"
FW_QUIC80_SECTION="dns_manager_quic_udp_80"
FW_QUIC443_SECTION="dns_manager_quic_udp_443"
FIREWALL_LAN_ZONE=""
FIREWALL_WAN_ZONE=""
FIREWALL_LAN_NAME=""
FIREWALL_WAN_NAME=""
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

                # Процесс живой, но не похож на DNS Manager.
                # Удаляем только действительно старые каталоги.
                find "$_old_dir" -maxdepth 0 -mmin +30 -exec rm -rf {} \; 2>/dev/null || true
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
    if [ "${DNS_MANAGER_NO_UPDATE:-0}" = "1" ] && [ "${DNS_MANAGER_FORCE_UPDATE:-0}" != 1 ]; then
        return 0
    fi

    [ -n "${AUTO_UPDATE_LOCK_DIR:-}" ] || AUTO_UPDATE_LOCK_DIR="$STATE_DIR/auto-update.lock"
    acquire_auto_update_lock || return 0

    _scheduled=0
    [ "${DNS_MANAGER_SCHEDULED_UPDATE:-0}" = "1" ] && _scheduled=1
    if [ "$_scheduled" = 1 ] && [ "${DNS_MANAGER_FORCE_UPDATE:-0}" != 1 ]; then
        _upd_now="$(date +%s 2>/dev/null)"
        _upd_last="$(cat "$AUTO_UPDATE_LAST_CHECK_FILE" 2>/dev/null)"
        case "$_upd_now" in ''|*[!0-9]*) _upd_now="";; esac
        case "$_upd_last" in ''|*[!0-9]*) _upd_last="";; esac
        if [ -n "$_upd_now" ] && [ -n "$_upd_last" ]; then
            _upd_age=$((_upd_now-_upd_last))
            if [ "$_upd_age" -ge 0 ] 2>/dev/null && [ "$_upd_age" -lt "$AUTO_UPDATE_CHECK_MAX_AGE" ] 2>/dev/null; then
                release_auto_update_lock
                return 0
            fi
        fi
        [ -n "$_upd_now" ] && printf '%s\n' "$_upd_now" > "$AUTO_UPDATE_LAST_CHECK_FILE" 2>/dev/null || true
    fi

    case "$0" in
        "$MANAGER_PATH"|*/dns-manager|dns-manager) ;;
        *)
            log_msg "Автообновление: запуск не из $MANAGER_PATH (0=$0), проверка пропущена."
            release_auto_update_lock
            return 0
            ;;
    esac

    [ -f "$MANAGER_PATH" ] || {
        log_msg "Автообновление: файл $MANAGER_PATH не найден."
        release_auto_update_lock
        return 0
    }

    [ -w "${MANAGER_PATH%/*}" ] || {
        log_msg "Автообновление: каталог ${MANAGER_PATH%/*} недоступен для записи."
        release_auto_update_lock
        return 0
    }

    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log_msg "Автообновление: нет curl или wget, проверка пропущена."
        release_auto_update_lock
        return 0
    fi

    _upd_tmp="/tmp/dns-manager-update-$$"
    UPDATE_TMP_FILE="$_upd_tmp"
    rm -f "$_upd_tmp" 2>/dev/null

    log_msg "Автообновление: проверяю $UPDATE_URL"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 4 --max-time 20 -o "$_upd_tmp" "$UPDATE_URL" >/dev/null 2>&1
    else
        wget -q -T 20 -O "$_upd_tmp" "$UPDATE_URL" >/dev/null 2>&1
    fi

    if [ ! -s "$_upd_tmp" ]; then
        log_msg "Автообновление: файл не получен. Нет связи, блокировка, нет curl/wget или сервер недоступен. Продолжаю работу без обновления."
        rm -f "$_upd_tmp" 2>/dev/null
        UPDATE_TMP_FILE=""
        release_auto_update_lock
        return 0
    fi

    head -n 1 "$_upd_tmp" 2>/dev/null | grep -q '^#!/bin/sh' || {
        log_msg "Автообновление: загруженный файл не является sh-скриптом."
        rm -f "$_upd_tmp" 2>/dev/null
        UPDATE_TMP_FILE=""
        release_auto_update_lock
        return 0
    }

    _new_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$_upd_tmp" 2>/dev/null | head -n1)"
    [ -n "$_new_version" ] || {
        log_msg "Автообновление: в загруженном файле не найдена строка VERSION."
        rm -f "$_upd_tmp" 2>/dev/null
        UPDATE_TMP_FILE=""
        release_auto_update_lock
        return 0
    }

    if ! sh -n "$_upd_tmp" 2>/dev/null; then
        log_msg "Автообновление: синтаксическая проверка загруженного файла не пройдена."
        rm -f "$_upd_tmp" 2>/dev/null
        UPDATE_TMP_FILE=""
        release_auto_update_lock
        return 0
    fi

    _new_hash="$(file_hash "$_upd_tmp")"
    _old_hash="$(file_hash "$MANAGER_PATH")"

    if [ "$_new_version" = "$VERSION" ]; then
        if [ -z "$_new_hash" ] || [ -z "$_old_hash" ] || [ "$_new_hash" = "$_old_hash" ]; then
            log_msg "Автообновление: текущая версия $VERSION актуальна."
            rm -f "$_upd_tmp" 2>/dev/null
            UPDATE_TMP_FILE=""
            release_auto_update_lock
            return 0
        fi
    else
        if ! _ver_newer "$_new_version" "$VERSION"; then
            log_msg "Автообновление: удалённая версия $_new_version не новее текущей $VERSION."
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

    log_msg "Автообновление: не удалось заменить $MANAGER_PATH."
    rm -f "$_upd_tmp" 2>/dev/null
    UPDATE_TMP_FILE=""
    release_auto_update_lock
    return 0
}
# ==========================================
# ==========================================
log_msg() {
mkdir -p "$BASE_DIR" "$STATE_DIR" 2>/dev/null
printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null
LOG_MSG_COUNT=$(( ${LOG_MSG_COUNT:-0} + 1 ))
if [ $((LOG_MSG_COUNT % 32)) -eq 0 ]; then rotate_runtime_logs; fi
}
log_tx() {
printf 'TX|%s|%s|%s|%s|%s|%s\n' "$TX_ID" "$(date +%s)" "$1" "$2" "$3" "$4" "$5" >> "$TX_LOG" 2>/dev/null
LOG_TX_COUNT=$(( ${LOG_TX_COUNT:-0} + 1 ))
if [ $((LOG_TX_COUNT % 32)) -eq 0 ]; then rotate_runtime_logs; fi
}
ok_msg() { log_msg "Готово: $*"; printf "${C_GREEN}[✓] %s${C_NC}\n" "$*"; }
info_msg() { log_msg "Информация: $*"; printf "${C_CYAN}[ℹ] %s${C_NC}\n" "$*"; }
warn_msg() { log_msg "Внимание: $*"; printf "${C_YELLOW}[!] %s${C_NC}\n" "$*"; }
err_msg() { log_msg "Ошибка: $*"; printf "${C_RED}[✗] %s${C_NC}\n" "$*"; }
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
        *) warn_msg "Используйте Y/Н — Да или N/Т — Нет."; return 1 ;;
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
printf "  ${C_CYAN}${C_BOLD}%-5s${C_NC} ${C_YELLOW}${C_BOLD}%-38s${C_NC} %b\n" "$1" "$2" "$3"
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
if command -v apk >/dev/null 2>&1; then PKG_MGR="apk"; else PKG_MGR="opkg"; fi
command -v timeout >/dev/null 2>&1 && HAVE_TIMEOUT=yes || HAVE_TIMEOUT=no
SYS_OWRT="$(sed -n "s/^DISTRIB_RELEASE='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"
SYS_REV="$(sed -n "s/^DISTRIB_REVISION='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"
SYS_TARGET="$(sed -n "s/^DISTRIB_TARGET='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"
SYS_ARCH="$(sed -n "s/^DISTRIB_ARCH='\([^']*\)'.*/\1/p" /etc/openwrt_release | head -n1)"
}
# ==========================================
# ==========================================
init_dirs() {
mkdir -p "$CFG_DIR" "$STATE_DIR" "$TMP_DIR" "$BASELINE_DIR" 2>/dev/null
touch "$LOG_FILE" "$TX_LOG" "$OWNERSHIP" 2>/dev/null
sanitize_baseline_shared_files 2>/dev/null || true
}
# ==========================================
# ==========================================
baseline_files() {
printf '%s\n'  /etc/config/dhcp  /etc/config/https-dns-proxy  /etc/config/firewall  /etc/config/system  /etc/sysctl.d/90-dns-manager.conf /etc/sysctl.d/91-dns-manager-extended.conf  /etc/dnsmasq.d/90-dns-manager-bogus.conf  /etc/dnsmasq.d/91-dns-manager-client-fixes.conf  
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
baseline_capture_once() {
    [ -s "$BASELINE_MANIFEST" ] && return 0
    mkdir -p "$BASELINE_DIR/files" || return 1
    : > "$BASELINE_MANIFEST"
    _legacy=0
    [ -s "$OWNERSHIP" ] && _legacy=1
    [ -s "$PREV_DNSMASQ" ] && _legacy=1
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
    printf 'legacy=%s\n' "$_legacy" >> "$BASELINE_META"
    if [ "$_legacy" = 1 ]; then
        printf 'restorable=0\n' >> "$BASELINE_META"
        warn_msg "Найдена старая настройка. Полное автоматическое восстановление недоступно."
    else
        printf 'restorable=1\n' >> "$BASELINE_META"
        info_msg "Исходная копия сохранена."
    fi
    log_tx "BASELINE" "router" "CAPTURE" "OK" "dir=$BASELINE_DIR;legacy=$_legacy"
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
baseline_restore_if_safe() {
    [ -s "$BASELINE_MANIFEST" ] || return 1
    [ -s "$BASELINE_LAST" ] || return 1
    grep -q '^restorable=1$' "$BASELINE_META" 2>/dev/null || return 1
    _conflict=0
    while IFS='|' read -r _f _k _last_existed _last_hash; do
        [ -n "$_f" ] || continue
        if [ "$_last_existed" = 1 ]; then
            _cur="$(file_hash "$_f")"
        else
            _cur="NONE"
            [ -f "$_f" ] && _cur="$(file_hash "$_f")"
        fi
        [ "$_cur" = "$_last_hash" ] || { _conflict=1; break; }
    done < "$BASELINE_LAST"
    if [ "$_conflict" = 1 ]; then
        warn_msg "Исходное состояние изменилось после последнего применения. Выполняю только безопасное удаление изменений DNS Manager."
        return 2
    fi
    while IFS='|' read -r _f _k _existed _basehash; do
        [ -n "$_f" ] || continue
        if [ "$_existed" = 1 ]; then
            cp -p "$BASELINE_DIR/files/$_k" "$_f" 2>/dev/null || return 1
        else
            rm -f "$_f" 2>/dev/null
        fi
    done < "$BASELINE_MANIFEST"
    log_tx "BASELINE" "router" "RESTORE" "OK" "safe=yes"
    return 0
}
clear_baseline_for_reacquire() {
    rm -rf "$BASELINE_DIR" 2>/dev/null
    mkdir -p "$BASELINE_DIR/files" 2>/dev/null || return 1
    rm -f "$BASELINE_MANIFEST" "$BASELINE_LAST" "$BASELINE_META" 2>/dev/null
    info_msg "Исходная копия удалена. При следующем применении будет создана новая."
}
write_catalogs() {
rm -f "$DNS_CATALOG.previous" "$NTP_CATALOG.previous" "$BOOTSTRAP_CATALOG.previous" "$BOGUS_CATALOG.previous" 2>/dev/null
_old_dnscatver="$(sed -n 's/^# DNSCATVER=//p' "$DNS_CATALOG" 2>/dev/null | head -n1)"
if [ ! -s "$DNS_CATALOG" ] || [ "$_old_dnscatver" != "$DNSCAT_VERSION" ]; then
cat > "$DNS_CATALOG" <<'EOF_DNS'
# DNSCATVER=8.5-RU-NOSOCIAL
# ==========================================
# ==========================================
mafioznik|bypass|geo+services|Mafioznik DNS|https://dns.mafioznik.com/dns-query|ru/global|verified-current
mafioznik_xyz|bypass|geo+services|Mafioznik DNS XYZ|https://dns.mafioznik.xyz/dns-query|ru/global|runtime-check
astracat|bypass|geo+ads+services|Astrakat DNS|https://dns.astrakat.ru/dns-query|ru/global|user-confirmed-current
astracat_1498|bypass|geo+ads+services|AstraCat DNS :1498|https://dns.astrakat.ru:1498/dns-query|ru/global|runtime-check
astracat_8443|bypass|geo+ads+services|AstraCat DNS :8443|https://dns.astrakat.ru:8443/dns-query|ru/global|runtime-check
malw_link|bypass|ip-block+geo|Malw.link|https://dns.malw.link/dns-query|ru/global|verified-current
xbox_dns|bypass|games+supercell|Xbox DNS|https://xbox-dns.ru/dns-query|ru/global|verified-current
geohide|bypass|geo+services|GeoHide DNS|https://dns.geohide.ru:444/dns-query|ru/global|verified-current
geohide_8443|bypass|geo+services|GeoHide DNS :8443|https://dns.geohide.ru:8443/dns-query|ru/global|runtime-check
comss_ru|bypass|geo+services|Comss DNS RU|https://dns.comss.ru/dns-query|ru/global|user-confirmed-current
comss_bypass|bypass|geo+security|Comss.one|https://dns.comss.one/dns-query|ru/global|verified-published-current
comss_adblock_bypass|bypass|geo+ads+security|Comss.one Ad Filter|https://router.comss.one/dns-query|ru/global|verified-published-current
dns_ai_ru|bypass|geo+services|DNS-AI.RU|https://dns.dns-ai.ru/dns-query|ru/global|official-current
yo1nk|bypass|geo+services|YO1NK DNS|https://dns.yo1nk.app/dns-query|global|user-confirmed-current
vppay|bypass|geo+services|VPPay DNS|https://dns.vppay.ru/dns-query|ru/global|user-confirmed-current
dynx|bypass|geo+youtube|DynX DNS|https://dns.dynx.pro/dns-query|global|review-runtime
paesa|bypass|geo+youtube|Paesa DNS|https://dns.paesa.es/dns-query|global|review-runtime
anon_no|bypass|privacy+geo|Anon.no DNS|https://dns.anon.no/dns-query|norway|review-runtime
bebas_unfiltered|bypass|uncensored|BebasDNS Unfiltered|https://dns.bebasid.com/unfiltered|id/global|source-listed
dns4all|bypass|uncensored|DNS4all|https://doh.dns4all.eu/dns-query|eu/global|source-listed
dns4eu_unfiltered|clean|unfiltered|DNS4EU Unfiltered|https://unfiltered.joindns4.eu/dns-query|eu|verified-published-current
shecan|bypass|geo+services|Shecan DNS|https://free.shecan.ir/dns-query|ir/global|runtime-check
# ==========================================
# ==========================================
yandex_ru|regional|ru+su+rf|Yandex RU|https://common.dot.dns.yandex.net/dns-query|ru|verified-published-current
yandex_safe|regional|ru+su+rf|Yandex Safe|https://safe.dot.dns.yandex.net/dns-query|ru|runtime-check
yandex_family|regional|ru+su+rf|Yandex Family|https://family.dot.dns.yandex.net/dns-query|ru|runtime-check
# ==========================================
# ==========================================
cloudflare_clean|clean|unfiltered|Cloudflare|https://cloudflare-dns.com/dns-query|global|verified-published-current
google_clean|clean|unfiltered|Google Public DNS|https://dns.google/dns-query|global|verified-published-current
quad9_unfiltered|clean|unfiltered+dnssec|Quad9 Unsecured|https://dns10.quad9.net/dns-query|global|verified-published-current
adguard_unfiltered|clean|unfiltered|AdGuard Unfiltered|https://unfiltered.adguard-dns.com/dns-query|global|verified-published-current
controld_p0|clean|unfiltered|Control D Unfiltered|https://freedns.controld.com/p0|global|verified-published-current
controld_uncensored|clean|uncensored|Control D Uncensored|https://freedns.controld.com/uncensored|global|verified-published-current
he_public|clean|unfiltered+anycast|Hurricane Electric Public Recursor|https://ordns.he.net/dns-query|global|verified-published-current
18bit_cn|clean|unfiltered|18bit.cn|https://doh.18bit.cn/dns-query|asia|source-listed
aa_dns|clean|unfiltered|Andrews & Arnold|https://dns.aa.net.uk/dns-query|uk/eu|source-listed
aquilenet|clean|unfiltered+dnssec|Aquilenet DNS|https://dns.aquilenet.fr/dns-query|fr/eu|source-listed
belnet|clean|unfiltered|Belnet DNS|https://dns.belnet.be/dns-query|be/eu|source-listed
cynthia|clean|unfiltered|CynthiaLabs DNS|https://dns.cynthialabs.net/dns-query|global|source-listed
digitalsize|clean|unfiltered+privacy|DigitalSize DNS|https://dns.digitalsize.net/dns-query|de/eu|source-listed
doh_disconnect|clean|unfiltered|Disconnect DNS|https://doh.disconnect.app/dns-query|global|source-listed
dnshome|clean|unfiltered|DNSHome|https://dns.dnshome.de/dns-query|de/eu|source-listed
one_dns_pure|clean|unfiltered|OneDNS Pure|https://doh-pure.onedns.net/dns-query|asia|verified-published-current
dns_pub|clean|unfiltered|DNSPod Public DNS|https://dns.pub/dns-query|cn/global|source-listed
dns_fdn0|clean|unfiltered|FDN DNS 0|https://ns0.fdn.fr/dns-query|fr/eu|source-listed
dns_fdn1|clean|unfiltered|FDN DNS 1|https://ns1.fdn.fr/dns-query|fr/eu|source-listed
doh_lacontrevoie|clean|unfiltered|LaContreVoie DNS|https://doh.lacontrevoie.fr/dns-query|fr/eu|source-listed
cznic_odvr_doh|clean|unfiltered|CZ.NIC ODVR DNS-сервер|https://odvr.nic.cz/doh|cz/eu|verified-published-current
cznic_odvr_query|clean|unfiltered|CZ.NIC ODVR Query|https://odvr.nic.cz/dns-query|cz/eu|source-listed
doh_seby|clean|unfiltered|Seby DNS|https://doh.seby.io/dns-query|global|source-listed
dns_surfshark|clean|unfiltered|Surfshark DNS|https://dns.surfsharkdns.com/dns-query|global|source-listed
hostux|clean|unfiltered|Hostux DNS|https://dns.hostux.net/dns-query|global|source-listed
# ==========================================
# ==========================================
cloudflare_security|security|malware|Cloudflare Security|https://security.cloudflare-dns.com/dns-query|global|verified-published-current
quad9_secure|security|malware+dnssec|Quad9 Secure|https://dns.quad9.net/dns-query|global|verified-published-current
quad9_ecs|security|malware+ecs|Quad9 Secure ECS|https://dns11.quad9.net/dns-query|global|verified-published-current
controld_p1|security|malware|Control D Malware|https://freedns.controld.com/p1|global|verified-published-current
opendns_standard|security|phishing+malware|OpenDNS Standard|https://doh.opendns.com/dns-query|global|verified-published-current
cleanbrowsing_security|security|phishing+malware|CleanBrowsing Security|https://doh.cleanbrowsing.org/doh/security-filter/|global|verified-published-current
dns4eu_protective|security|malware+phishing|DNS4EU Protective|https://protective.joindns4.eu/dns-query|eu|verified-published-current
cert_ee|security|malware+phishing|CERT-EE|https://dns.cert.ee/dns-query|estonia|verified-published-current
cira_protected|security|malware+phishing|CIRA Protected|https://protected.canadianshield.cira.ca/dns-query|canada|verified-published-current
one_dns_block|security|malware|OneDNS Block|https://doh.onedns.net/dns-query|asia|verified-published-current
hagezi_root|security|ads+tracking+malware+phishing|HaGeZi Root|https://root.hagezi.org/dns-query|germany|verified-published-current
hagezi_wurzn|security|ads+tracking+malware+phishing|HaGeZi Wurzn|https://wurzn.hagezi.org/dns-query|germany|verified-published-current
hagezi_juuri|security|ads+tracking+malware+phishing|HaGeZi Juuri|https://juuri.hagezi.org/dns-query|finland|verified-published-current
hagezi_ctif|security|threat-only|HaGeZi CTIF|https://ctif.hagezi.org/dns-query|germany|verified-published-current
openbld_ada|security|ads+tracking+malware+phishing|OpenBLD ADA|https://ada.openbld.net/dns-query|global|verified-published-current
openbld_ric|security|strict-filtering|OpenBLD RIC|https://ric.openbld.net/dns-query|global|verified-published-current
dnsforge_strict|security|strict-filtering|dnsforge Strict|https://hard.dnsforge.de/dns-query|germany|verified-published-current
dnsbunker|security|balanced-threat|DNSBUNKER Pro+TIF|https://dnsbunker.org/dns-query|germany|verified-published-current
nsec_arnor|security|malware+phishing|arnor.org|https://nsec.arnor.org/dns-query|global|source-listed
# ==========================================
# ==========================================
mullvad_clean|privacy|qname-minimization|Mullvad Clean|https://dns.mullvad.net/dns-query|global|verified-published-current
mullvad_adblock|adblock|ads+tracking|Mullvad Adblock|https://adblock.dns.mullvad.net/dns-query|global|verified-published-current
mullvad_base|security|ads+tracking+malware|Mullvad Base|https://base.dns.mullvad.net/dns-query|global|verified-published-current
mullvad_extended|security|ads+tracking+malware+social|Mullvad Extended|https://extended.dns.mullvad.net/dns-query|global|verified-published-current
nextdns_fast|privacy|unfiltered|NextDNS|https://dns.nextdns.io|global|verified-published-current
nextdns_anycast|privacy|anycast|NextDNS Anycast|https://anycast.dns.nextdns.io|global|verified-published-current
dns_sb|privacy|dnssec+no-logging|DNS.SB|https://doh.dns.sb/dns-query|global|verified-published-current
applied_privacy|privacy|privacy|Applied Privacy|https://doh.applied-privacy.net/query|europe|verified-published-current
cznic_odvr|security|dnssec+privacy|CZ.NIC ODVR|https://odvr.nic.cz/doh|czechia|verified-published-current
digitale_gesellschaft|privacy|privacy|Digitale Gesellschaft|https://dns.digitale-gesellschaft.ch/dns-query|switzerland|verified-published-current
cira_private|privacy|unfiltered|CIRA Private|https://private.canadianshield.cira.ca/dns-query|canada|verified-published-current
libredns_clean|privacy|privacy|LibreDNS|https://doh.libredns.gr/dns-query|greece/eu|verified-published-current
switch_ch|privacy|privacy|SWITCH DNS|https://dns.switch.ch/dns-query|switzerland|verified-published-current
wikimedia|privacy|anycast|Wikimedia DNS|https://wikimedia-dns.org/dns-query|global|verified-published-current
pumplex|privacy|no-ads+dnssec|PumpleX|https://dns.pumplex.com/dns-query|france|verified-published-current
dnsforge|privacy|privacy|dnsforge|https://dnsforge.de/dns-query|germany|verified-published-current
ffmuc|privacy|community|FFMUC|https://doh.ffmuc.net/dns-query|germany|verified-published-current
# ==========================================
# ==========================================
adguard_default|adblock|ads+tracking+phishing|AdGuard DNS|https://dns.adguard-dns.com/dns-query|global|verified-published-current
controld_p2|adblock|ads+tracking|Control D Ads+Tracking|https://freedns.controld.com/p2|global|verified-published-current
dns4eu_noads|adblock|ads+malware|DNS4EU No Ads|https://noads.joindns4.eu/dns-query|eu|verified-published-current
libredns_ads|adblock|ads|LibreDNS Ads|https://doh.libredns.gr/ads|greece/eu|verified-published-current
dnsguard|adblock|ads+tracking+malware|DNSGuard|https://dns.dnsguard.pub/dns-query|global|verified-published-current
nwps_standard|adblock|ads+tracking+malware|NWPS.fi Standard|https://public.ns.nwps.fi/dns-query|finland|verified-published-current
oszx|adblock|ads|OSZX DNS|https://dns.oszx.co/dns-query|france|verified-published-current
angry_im|adblock|ads|Angry.im|https://doh.angry.im/dns-query|global|source-listed
dns_bebas_default|adblock|ads+malware+phishing|BebasDNS|https://dns.bebasid.com/dns-query|id/global|source-listed
blokada|adblock|privacy|Blokada DNS|https://dns.blokada.org/dns-query|global|source-listed
# ==========================================
# ==========================================
cloudflare_family|family|malware+adult|Cloudflare Family|https://family.cloudflare-dns.com/dns-query|global|verified-published-current
adguard_family|family|ads+tracking+adult|AdGuard Family|https://family.adguard-dns.com/dns-query|global|verified-published-current
mullvad_family|family|ads+tracking+malware+adult+gambling|Mullvad Family|https://family.dns.mullvad.net/dns-query|global|verified-published-current
mullvad_all|family|ads+tracking+malware+adult+gambling+social|Mullvad All|https://all.dns.mullvad.net/dns-query|global|verified-published-current
controld_family|family|family|Control D Family|https://freedns.controld.com/family|global|verified-published-current
opendns_family|family|adult|OpenDNS FamilyShield|https://doh.familyshield.opendns.com/dns-query|global|verified-published-current
cleanbrowsing_adult|family|adult+malware|CleanBrowsing Adult|https://doh.cleanbrowsing.org/doh/adult-filter/|global|verified-published-current
cleanbrowsing_family|family|adult+family|CleanBrowsing Family|https://doh.cleanbrowsing.org/doh/family-filter/|global|verified-published-current
dns4eu_child|family|child+malware|DNS4EU Child|https://child.joindns4.eu/dns-query|eu|verified-published-current
dns4eu_child_noads|family|child+ads|DNS4EU Child No Ads|https://child-noads.joindns4.eu/dns-query|eu|verified-published-current
dns_for_family|family|adult|DNS for Family|https://dns-doh.dnsforfamily.com/dns-query|global|verified-published-current
cira_family|family|adult+malware|CIRA Family|https://family.canadianshield.cira.ca/dns-query|canada|verified-published-current
nwps_kids|family|kids+ads+malware|NWPS.fi Kids|https://kids.ns.nwps.fi/dns-query|finland|verified-published-current
iijjp|family|child-protection|IIJ.JP DNS|https://public.dns.iij.jp/dns-query|japan|verified-published-current
dnsforge_youth|family|youth-protection|dnsforge Youth Protection|https://clean.dnsforge.de/dns-query|germany|verified-published-current
EOF_DNS
fi
if [ ! -s "$NTP_CATALOG" ] || ! grep -q '^# NTPCATVER=6.6-FINAL-HYBRID' "$NTP_CATALOG" 2>/dev/null; then
cat > "$NTP_CATALOG" <<'EOF_NTP'
cf_ip|global|Cloudflare|162.159.200.1 162.159.200.123|2606:4700:f1::1 2606:4700:f1::123|ip-first|no-smear|verified-current
nist_ip|global|NIST|129.6.15.28 129.6.15.29 129.6.15.30 129.6.15.27 129.6.15.26|2610:20:6f15:15::27 2610:20:6f15:15::26|ip-first|no-smear|verified-current
google_ip|special|Google Public NTP|216.239.35.0 216.239.35.4 216.239.35.8 216.239.35.12||ip-only|smear|verified-current
vniiftri_moscow|ru|ВНИИФТРИ Менделеево|89.109.251.21 89.109.251.22 89.109.251.23 89.109.251.24 89.109.251.25||ip-first|no-smear|verified-source
vniiftri_irkutsk|ru|ВНИИФТРИ Иркутск|46.254.241.74 46.254.241.75||ip-first|no-smear|verified-source
vniiftri_khabarovsk|ru|ВНИИФТРИ Хабаровск|212.19.6.218 212.19.17.26||ip-first|no-smear|verified-source
vniiftri_novosibirsk|ru|ВНИИФТРИ Новосибирск|80.242.83.227 80.242.83.228||ip-first|no-smear|verified-source
vniiftri_kamchatka|ru|ВНИИФТРИ Камчатка|91.189.237.182||ip-only|no-smear|verified-source
pool_global|pool|NTP Pool Global||||hostname|no-smear|runtime-check
pool_ru|pool|NTP Pool Russia||||hostname|no-smear|runtime-check
EOF_NTP
fi
if [ ! -s "$BOOTSTRAP_CATALOG" ] || ! grep -q '^# BOOTSTRAPCATVER=6.6-FIX13' "$BOOTSTRAP_CATALOG" 2>/dev/null; then
cat > "$BOOTSTRAP_CATALOG" <<'EOF_BOOT'
yandex|Yandex|77.88.8.8,77.88.8.1|2a02:6b8::feed:0ff,2a02:6b8:0:1::feed:0ff|bootstrap|verified-current
adguard|AdGuard|94.140.14.14,94.140.15.15|2a10:50c0::ad1:ff,2a10:50c0::ad2:ff|bootstrap|verified-current
cloudflare|Cloudflare|1.1.1.1,1.0.0.1|2606:4700:4700::1111,2606:4700:4700::1001|bootstrap|verified-current
google|Google|8.8.8.8,8.8.4.4|2001:4860:4860::8888,2001:4860:4860::8844|bootstrap|verified-current
quad9|Quad9|9.9.9.9,149.112.112.112|2620:fe::fe,2620:fe::9|bootstrap|verified-current
opendns|OpenDNS|208.67.222.222,208.67.220.220|2620:119:35::35,2620:119:53::53|bootstrap|verified-current
cira|CIRA|149.112.121.10,149.112.122.10|2620:10A:80BB::10,2620:10A:80BC::10|bootstrap|verified-current
controld|Control D|76.76.2.0,76.76.10.0|2606:1a40::0,2606:1a40:1::0|bootstrap|verified-current
mullvad|Mullvad|194.242.2.2,194.242.2.3|2a07:e340::2,2a07:e340::3|bootstrap|verified-current
EOF_BOOT
fi
if [ ! -s "$BOGUS_CATALOG" ] || ! grep -q '^# BOGUSCATVER=6.6-FIX13' "$BOGUS_CATALOG" 2>/dev/null; then
cat > "$BOGUS_CATALOG" <<'EOF_BOGUS'
rtk_95_167|hijack|95.167.13.50|Ростелеком: исторически подтвержденная заглушка|high|historical-confirmed
ttk_62_33|hijack|62.33.207.195|ТТК: исторически указанный адрес|medium|historical-confirmed
onlime_77_37|hijack|77.37.254.90|Онлайм: исторически указанный адрес|medium|historical-confirmed
enforta_87_241|hijack|87.241.223.133|Enforta: исторически указанный адрес|medium|historical-confirmed
legacy_185_179|hijack|185.179.189.20|Легаси-кандидат|low|needs-runtime-check
legacy_195_208|hijack|195.208.1.1|Легаси-кандидат|low|needs-runtime-check
legacy_95_182|hijack|95.182.120.241|Легаси-кандидат|low|needs-runtime-check
legacy_45_155|hijack|45.155.204.190|Легаси-кандидат|low|needs-runtime-check
legacy_37_230|hijack|37.230.192.51|Легаси-кандидат|low|needs-runtime-check
legacy_217_169|hijack|217.169.211.21|Легаси-кандидат|low|needs-runtime-check
sys_zero|system|0.0.0.0|Системное значение: только вручную|high|manual-only
sys_loop|system|127.0.0.1|Системное значение: только вручную|high|manual-only
EOF_BOGUS
fi
if [ "${_old_dnscatver:-}" != "$DNSCAT_VERSION" ]; then
    rm -f "$TEST_RESULTS" "$TEST_RESULTS_META"
    printf '%s\n' "$DNSCAT_VERSION" > "$STATE_DIR/dns-catalog.version" 2>/dev/null
fi
}
# ==========================================
# ==========================================
sync_regional_dns_state() {
    if [ -n "${SLOT_RU:-}" ] || [ -n "${SLOT_RU_2:-}" ]; then
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
BOOTSTRAP_DNS="$BOOTSTRAP_DNS_ALL"
: "${SLOT_1:=}"; : "${SLOT_2:=}"; : "${SLOT_3:=}"; : "${SLOT_4:=}"; : "${SLOT_5:=}"; : "${SLOT_6:=}"
: "${SLOT_RU:=}"; : "${SLOT_RU_2:=}"
: "${SLOT_1_CAT:=}"; : "${SLOT_2_CAT:=}"; : "${SLOT_3_CAT:=}"; : "${SLOT_4_CAT:=}"; : "${SLOT_5_CAT:=}"; : "${SLOT_6_CAT:=}"
: "${SLOT_RU_CAT:=}"; : "${SLOT_RU_2_CAT:=}"
: "${PORT_1:=}"; : "${PORT_2:=}"; : "${PORT_3:=}"; : "${PORT_4:=}"; : "${PORT_5:=}"; : "${PORT_6:=}"
: "${PORT_RU:=}"; : "${PORT_RU_2:=}"
: "${BOOTSTRAP_DNS:=$BOOTSTRAP_DNS_ALL}"
: "${TLD_RU_ENABLED:=1}"; : "${BLOCK_QUIC:=0}"; : "${MTU_FIX:=0}"; : "${FORCE_DOH:=0}"
: "${NTP_IP_FALLBACK:=1}"; : "${SYSCTL_TUNING:=0}"; : "${DNSMASQ_PERF:=0}"; : "${NTP_CLIENTS:=0}"; : "${CLIENT_FIXES:=0}"; : "${SYSCTL_EXTENDED:=0}"
: "${BALANCER_ENABLED:=1}"; : "${NTP_PRESET:=cf_ip}"; : "${DNS_PROFILE:=hybrid}"; : "${DNS_SELECTION_MODE:=quick}"; : "${DNS_SELECTION_CATEGORY:=bypass}"
: "${QUICK_PREF_1:=}"; : "${QUICK_PREF_2:=}"; : "${QUICK_PREF_3:=}"; : "${QUICK_PREF_4:=}"; : "${QUICK_PREF_5:=}"; : "${QUICK_PREF_6:=}"
: "${WATCHDOG_ENABLED:=1}"; : "${WATCHDOG_INTERVAL:=15}"
: "${WEB_ACCESS_ENABLED:=0}"; : "${WEB_ACCESS_PORT:=7682}"; : "${CLIENT_FIXES_FILE:=}"
TLD_SPLIT="$TLD_RU_ENABLED"
if [ "$_had_dns_profile" = 0 ] && [ -z "$DNS_PROFILE" ]; then
DNS_PROFILE="hybrid"
fi
if [ "$DNS_PROFILE" = "hybrid" ]; then
    for _slot in 1 2 3 4 5 6 RU RU_2; do
        eval "_sid=\${SLOT_${_slot}:-}"
        eval "_scat=\${SLOT_${_slot}_CAT:-}"
        if [ -n "$_sid" ] && [ -z "$_scat" ]; then
            _scat="$(dns_cat "$_sid")"
            case "$_slot" in RU|RU_2) [ -n "$_scat" ] || _scat="regional" ;; esac
            eval "SLOT_${_slot}_CAT=\"$_scat\""
        fi
    done
fi
sync_regional_dns_state
}
save_config() {
sync_regional_dns_state
umask 077
mkdir -p "$CFG_DIR" 2>/dev/null || return 1
_cfg_tmp="${CONFIG_FILE}.tmp.$$"
cat > "$_cfg_tmp" <<EOF_CFG
SLOT_1="$SLOT_1"
SLOT_2="$SLOT_2"
SLOT_3="$SLOT_3"
SLOT_4="$SLOT_4"
SLOT_5="$SLOT_5"
SLOT_6="$SLOT_6"
SLOT_RU="$SLOT_RU"
SLOT_RU_2="$SLOT_RU_2"
SLOT_1_CAT="$SLOT_1_CAT"
SLOT_2_CAT="$SLOT_2_CAT"
SLOT_3_CAT="$SLOT_3_CAT"
SLOT_4_CAT="$SLOT_4_CAT"
SLOT_5_CAT="$SLOT_5_CAT"
SLOT_6_CAT="$SLOT_6_CAT"
SLOT_RU_CAT="$SLOT_RU_CAT"
SLOT_RU_2_CAT="$SLOT_RU_2_CAT"
PORT_1="$PORT_1"
PORT_2="$PORT_2"
PORT_3="$PORT_3"
PORT_4="$PORT_4"
PORT_5="$PORT_5"
PORT_6="$PORT_6"
PORT_RU="$PORT_RU"
PORT_RU_2="$PORT_RU_2"
BOOTSTRAP_DNS="$BOOTSTRAP_DNS_ALL"
TLD_RU_ENABLED="$TLD_RU_ENABLED"
BLOCK_QUIC="$BLOCK_QUIC"
MTU_FIX="$MTU_FIX"
NTP_IP_FALLBACK="$NTP_IP_FALLBACK"
SYSCTL_TUNING="$SYSCTL_TUNING"
FORCE_DOH="$FORCE_DOH"
DNSMASQ_PERF="$DNSMASQ_PERF"
NTP_CLIENTS="$NTP_CLIENTS"
CLIENT_FIXES="$CLIENT_FIXES"
CLIENT_FIXES_FILE="$CLIENT_FIXES_FILE"
SYSCTL_EXTENDED="$SYSCTL_EXTENDED"
BALANCER_ENABLED="$BALANCER_ENABLED"
NTP_PRESET="$NTP_PRESET"
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
WEB_ACCESS_ENABLED="$WEB_ACCESS_ENABLED"
WEB_ACCESS_PORT="$WEB_ACCESS_PORT"
EOF_CFG
mv "$_cfg_tmp" "$CONFIG_FILE" || { rm -f "$_cfg_tmp"; return 1; }
}
# ==========================================
# ==========================================
firewall_resolve_zones() {
    FIREWALL_LAN_ZONE=""
    FIREWALL_WAN_ZONE=""
    FIREWALL_LAN_NAME=""
    FIREWALL_WAN_NAME=""
    _lan_zone=""
    _wan_zone=""
    _lan_name=""
    _wan_name=""
    _lan_count=0
    _wan_count=0
    _zones="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=zone$/\1/p')"
    for _z in $_zones; do
        _nets="$(uci -q get "firewall.$_z.network" 2>/dev/null)"
        printf '%s\n' "$_nets" | tr ' ' '\n' | grep -qxF lan 2>/dev/null && {
            _lan_zone="$_z"
            _lan_name="$(uci -q get "firewall.$_z.name" 2>/dev/null)"
            _lan_count=$((_lan_count+1))
        }
        printf '%s\n' "$_nets" | tr ' ' '\n' | grep -qxF wan 2>/dev/null && {
            _wan_zone="$_z"
            _wan_name="$(uci -q get "firewall.$_z.name" 2>/dev/null)"
            _wan_count=$((_wan_count+1))
        }
    done
    [ "$_lan_count" -eq 1 ] && { FIREWALL_LAN_ZONE="$_lan_zone"; FIREWALL_LAN_NAME="$_lan_name"; }
    [ "$_wan_count" -eq 1 ] && { FIREWALL_WAN_ZONE="$_wan_zone"; FIREWALL_WAN_NAME="$_wan_name"; }
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
firewall_cleanup_legacy_web_rule() {
    firewall_resolve_zones
    [ -n "$FIREWALL_LAN_ZONE" ] || return 0
    [ -n "$FIREWALL_WAN_ZONE" ] || return 0
    if [ "$(uci -q get "firewall.$FW_WEB_SECTION" 2>/dev/null)" = rule ]; then
        if firewall_ref_matches_zone "$(uci -q get "firewall.$FW_WEB_SECTION.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" \
           && firewall_ref_matches_zone "$(uci -q get "firewall.$FW_WEB_SECTION.dest" 2>/dev/null)" "$FIREWALL_WAN_ZONE" \
           && [ "$(uci -q get "firewall.$FW_WEB_SECTION.proto" 2>/dev/null)" = udp ] \
           && [ "$(uci -q get "firewall.$FW_WEB_SECTION.dest_port" 2>/dev/null)" = 443 ] \
           && [ "$(uci -q get "firewall.$FW_WEB_SECTION.target" 2>/dev/null)" = REJECT ]; then
            uci -q delete "firewall.$FW_WEB_SECTION" || return 1
            firewall_owner_remove "$FW_WEB_SECTION" >/dev/null 2>&1 || true
            return 2
        fi
    fi
    return 0
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
    _fw_init="/etc/init.d/firewall"
    if [ -x "$_fw_init" ]; then
        if grep -Eq '(^|[[:space:];])fw4([[:space:];]|$)' "$_fw_init" 2>/dev/null; then
            SYS_FW="fw4"
            FIREWALL_BACKEND="fw4"
            FIREWALL_DETECT_SOURCE="init"
        elif grep -Eq '(^|[[:space:];])fw3([[:space:];]|$)' "$_fw_init" 2>/dev/null; then
            SYS_FW="fw3"
            FIREWALL_BACKEND="fw3"
            FIREWALL_DETECT_SOURCE="init"
        fi
    fi
    if [ "$SYS_FW" = unknown ]; then
        if [ -f /var/run/fw4.state ] && command -v nft >/dev/null 2>&1 && nft list table inet fw4 >/dev/null 2>&1; then
            SYS_FW="fw4"
            FIREWALL_BACKEND="fw4"
            FIREWALL_DETECT_SOURCE="runtime"
        elif [ -f /var/run/fw3.state ] && (command -v fw3 >/dev/null 2>&1 || [ -x /sbin/fw3 ] || [ -x /usr/sbin/fw3 ]); then
            SYS_FW="fw3"
            FIREWALL_BACKEND="fw3"
            FIREWALL_DETECT_SOURCE="runtime"
        fi
    fi
    if [ "$SYS_FW" = unknown ]; then
        _has_fw4=0
        _has_fw3=0
        if command -v fw4 >/dev/null 2>&1 || [ -x /sbin/fw4 ] || [ -x /usr/sbin/fw4 ]; then _has_fw4=1; fi
        if command -v fw3 >/dev/null 2>&1 || [ -x /sbin/fw3 ] || [ -x /usr/sbin/fw3 ]; then _has_fw3=1; fi
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
        1|2|3|4|5|6|RU|RU_2) ;;
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
        for _slot in 1 2 3 4 5 6 RU RU_2; do
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
    _secs="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=redirect$/\1/p')"
    for _sec in $_secs; do
        [ "$_sec" = "$FW_DNS_REDIRECT_SECTION" ] && continue
        [ "$(uci -q get "firewall.$_sec.disabled" 2>/dev/null)" = 1 ] && continue
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
        /iifname[[:space:]]+"[^"]+"/ && /dport[[:space:]]+53/ && /redirect[[:space:]]+to[[:space:]]+:[0-9]+/ && /#[[:space:]]*handle[[:space:]]+[0-9]+/ {
            ok=0; if ($0 ~ /iifname[[:space:]]+"br-lan"/) ok=1
            if (ld != "" && index($0,"iifname \"" ld "\"")>0) ok=1
            if (li != "" && index($0,"iifname \"" li "\"")>0) ok=1
            if (!ok) next
            line=$0
            sub(/^.*redirect[[:space:]]+to[[:space:]]+:/,"",line)
            port=line; sub(/[^0-9].*$/,"",port)
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
            _rules="$_rules
$(cat /etc/firewall.user 2>/dev/null)"
        fi
    else
        return 1
    fi
    [ -n "$_rules" ] || return 1
    _lan_dev="$(uci -q get network.lan.device 2>/dev/null)"
    _lan_if="$(uci -q get network.lan.ifname 2>/dev/null)"
    printf '%s\n' "$_rules" | awk -v ld="$_lan_dev" -v li="$_lan_if" '
        /-A PREROUTING / {
            devok = ($0 ~ / -i br-lan([[:space:]]|$)/)
            if (ld != "") { pat=" -i " ld "([[:space:]]|$)"; if ($0 ~ pat) devok=1 }
            if (li != "") { pat2=" -i " li "([[:space:]]|$)"; if ($0 ~ pat2) devok=1 }
            if (!devok || $0 !~ / --dport 53([[:space:]]|$)/) next
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
prepare_dns_path() {
    _cfg_result="$(dns_redirect_conflict_uci 2>/dev/null || true)"
    _cfg_changed="${_cfg_result%%|*}"
    _cfg_conflict="${_cfg_result#*|}"
    case "$_cfg_changed" in 0|1) ;; *) _cfg_changed=0;; esac
    case "$_cfg_conflict" in 0|1) ;; *) _cfg_conflict=0;; esac
    if [ "$_cfg_changed" = 1 ]; then
        uci commit firewall >/dev/null 2>&1 || return 1
        reload_fw || return 1
    fi
    if [ "$_cfg_conflict" = 1 ]; then
        warn_msg "Обнаружено стороннее перенаправление DNS с LAN:53. DNS Manager его не изменяет."
        return 1
    fi
    if [ "$SYS_FW" = fw4 ]; then
        dns_path_conflict_nft >/dev/null 2>&1 && return 1
    elif [ "$SYS_FW" = fw3 ]; then
        dns_path_conflict_iptables >/dev/null 2>&1 && return 1
    fi
    return 0
}
disc_firewall() {
    QUIC_OURS=0
    QUIC_FOREIGN=0
    firewall_quic_rule_owned "$FW_QUIC80_SECTION" 80 2>/dev/null && QUIC_OURS=1
    firewall_quic_rule_owned "$FW_QUIC443_SECTION" 443 2>/dev/null && QUIC_OURS=1
    firewall_find_exact_quic 80 "$FW_QUIC80_SECTION" >/dev/null 2>&1 && QUIC_FOREIGN=1
    firewall_find_exact_quic 443 "$FW_QUIC443_SECTION" >/dev/null 2>&1 && QUIC_FOREIGN=1
    [ "$(uci -q get firewall.@defaults[0].flow_offloading 2>/dev/null)" = 1 ] && FLOW_OFFLOAD="yes" || FLOW_OFFLOAD="no"
    NFT_ACTIVE="no"
    IPTABLES_ACTIVE="no"
    if [ "$SYS_FW" = fw4 ] && command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then
        NFT_ACTIVE="yes"
    elif [ "$SYS_FW" = fw3 ]; then
        IPTABLES_ACTIVE="yes"
    fi
    DNS_PATH_CONFLICT="no"
    if [ "$SYS_FW" = fw4 ]; then
        dns_path_conflict_nft >/dev/null 2>&1 && DNS_PATH_CONFLICT="yes"
    elif [ "$SYS_FW" = fw3 ]; then
        dns_path_conflict_iptables >/dev/null 2>&1 && DNS_PATH_CONFLICT="yes"
    fi
}
run_discovery() {
init_dirs
    migrate_legacy_manager_files >/dev/null 2>&1 || true
disc_system
disc_network
disc_listeners
disc_dns
disc_clients
firewall_resolve_zones
disc_firewall
watchdog_cron_scheduler_detect >/dev/null 2>&1 || true
firewall_migrate_legacy_owned >/dev/null 2>&1 || true
log_tx "DISCOVER" "router" "READ" "OK" "OpenWrt=$SYS_OWRT;fw=$SYS_FW;fw_source=$FIREWALL_DETECT_SOURCE;dns=$DNSMASQ_RUN;doh=$DOH_TOTAL;cron=$WATCHDOG_CRON_AVAILABLE;crond=$WATCHDOG_CRON_RUNNING;cron_ambiguous=$WATCHDOG_CRON_AMBIGUOUS"
}
refresh_runtime_capabilities() {
    disc_system
    disc_network
    disc_listeners
    disc_dns
}
# ==========================================
# ==========================================
dns_field() { awk -F'|' -v id="$1" -v f="$2" '$1==id{print $f;exit}' "$DNS_CATALOG"; }
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
ipx="$(dig +short "@$bs" "$host" A +time=2 +tries=1 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/{print;exit}')"
elif command -v nslookup >/dev/null 2>&1; then
ipx="$(nslookup "$host" "$bs" 2>/dev/null | awk '/^Address[ 0-9]*: / {print $NF}' | awk '/^[0-9]+(\.[0-9]+){3}$/ {print;exit}')"
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
    ipx="$(dig +short "$host" A +time=3 +tries=1 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/{print;exit}')"
    [ -n "$ipx" ] || ipx="$(dig +short "$host" A +tcp +time=3 +tries=1 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/{print;exit}')"
fi
if [ -z "$ipx" ] && command -v nslookup >/dev/null 2>&1; then
    ipx="$(nslookup "$host" 2>/dev/null | awk '/^Address[ 0-9]*: / {print $NF}' | awk '/^[0-9]+(\.[0-9]+){3}$/{print;exit}')"
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
q="$TMP_DIR/q.$id"; body="$TMP_DIR/body.$id"; hdr="$TMP_DIR/h.$id"
: > "$body"; : > "$hdr"
printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$q"
_ips=""
if [ "$HAS_DIG" = yes ]; then
    _chunk="$(dig +short +time=3 +tries=1 "$host" A 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/{print}' | head -n 4)"
    [ -n "$_chunk" ] && _ips="$_chunk"
fi
[ -n "$_ips" ] || { _one="$(resolve_host_fallback "$host")"; [ -n "$_one" ] && _ips="$_one"; }
[ -n "$_ips" ] || { _one="$(resolve_host "$host")"; [ -n "$_one" ] && _ips="$_one"; }
[ -n "$_ips" ] || { printf '%s|%s|%s|-1|BOOTSTRAP_FAIL\n' "$id" "$cat" "$name" > "$TMP_DIR/t.$id"; rm -f "$q" "$body" "$hdr"; return; }
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
rm -f "$q" "$body" "$hdr"
}
# ==========================================
# ==========================================
test_dns_catalog() {
    rotate_runtime_logs
    [ "$HAS_CURL" = yes ] || { warn_msg "Полную проверку DNS нельзя выполнить: curl не установлен."; return 1; }
    acquire_test_lock || { warn_msg "Полная проверка DNS уже выполняется другим процессом. Текущая проверка отменена."; return 1; }
    rm -f "$TMP_DIR/t."* "$TMP_DIR/q."* "$TMP_DIR/body."* "$TMP_DIR/h."* 2>/dev/null
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
save_persistent_test_results
    rm -f "$TMP_DIR"/t.* "$TMP_DIR"/q.* "$TMP_DIR"/body.* "$TMP_DIR"/h.* 2>/dev/null || true
release_test_lock
return 0
}

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
HYBRID_PORT_RU_2=5060
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
SLOT_RU_2=""
SLOT_1_CAT="bypass"
SLOT_2_CAT="bypass"
SLOT_3_CAT="bypass"
SLOT_4_CAT="bypass"
SLOT_5_CAT="bypass"
SLOT_6_CAT="bypass"
SLOT_RU_CAT="regional"
SLOT_RU_2_CAT="regional"
PORT_1="$HYBRID_PORT_1"
PORT_2="$HYBRID_PORT_2"
PORT_3="$HYBRID_PORT_3"
PORT_4="$HYBRID_PORT_4"
PORT_5="$HYBRID_PORT_5"
PORT_6="$HYBRID_PORT_6"
PORT_RU="$HYBRID_PORT_RU"
PORT_RU_2=""
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
        RU_2) printf '%s' "${HYBRID_PORT_RU_2:-5060}";;
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
WATCHDOG_ENABLED=1
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
eval "SLOT_$_s=\"$_replacement\""
printf "${C_YELLOW}⚠ %s не прошёл тест → резерв %s.${C_NC}\n" "$(dns_name "$_id")" "$(dns_name "$_replacement")"
_id="$_replacement"
else
warn_msg "Для Hybrid-слота $_s нет проверенного резерва."
eval "SLOT_$_s="
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
save_config
ok_msg "Гибридный DNS подготовлен."
if confirm_action "Применить настройки Гибридный DNS?"; then apply_settings; fi
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
[ -n "$servers" ] || { warn_msg "NTP-профиль '$NTP_PRESET' не найден в каталоге."; return 1; }
[ -n "$(uci -q get system.ntp 2>/dev/null)" ] || uci -q set system.ntp=timeserver || return 1
for ipx in $servers; do
    _exists=0
    for _cur_ntp in $(uci -q get system.ntp.server 2>/dev/null); do
        [ "$_cur_ntp" = "$ipx" ] && _exists=1
    done
    [ "$_exists" = 1 ] || uci add_list system.ntp.server="$ipx" || return 1
done
uci set system.ntp.enabled='1' || return 1
uci set system.ntp.use_dhcp='0' || return 1
uci commit system || return 1
/etc/init.d/sysntpd restart >/dev/null 2>&1
record_own "ntp" "system.ntp.server" "$servers" "profile=$NTP_PRESET"
ok_msg "NTP: IP-профиль '$NTP_PRESET' добавлен без удаления существующих серверов."
log_tx "APPLY" "NTP" "ADD" "OK" "profile=$NTP_PRESET;servers=$servers"
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
menu_item "[1]" "Cloudflare — серверы времени по IP"
menu_item "[2]" "NIST — серверы точного времени"
menu_item "[3]" "ВНИИФТРИ — российские серверы времени"
menu_item "[4]" "Google — серверы времени по IP"
menu_back
menu_prompt
safe_read c
_old_ntp_preset="$NTP_PRESET"
case "$c" in
1) NTP_PRESET="cf_ip";;
2) NTP_PRESET="nist_ip";;
3) NTP_PRESET="vniiftri_moscow";;
4) NTP_PRESET="google_ip";;
*) return;;
esac
if apply_ntp_ip_fallback; then
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
find_doh_by_port() {
    awk -F'|' -v p="$1" '$2==p{print $1"|"$2"|"$3"|"$4"|"$5;exit}' "$DOH_INV"
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
# ==========================================
clear_all_doh_for_apply() {
    # DNS Manager is the authoritative owner of the DoH configuration.
    # Before every apply, remove ALL existing https-dns-proxy sections and
    # rebuild the complete selected set from the manager configuration.
    printf "${C_PINK}↻ Все существующие DNS-секции https-dns-proxy будут удалены и заменены выбранной схемой DNS Manager.${C_NC}\n"
    _removed=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[0]" >/dev/null 2>&1; do
        _u="$(uci -q get "https-dns-proxy.@https-dns-proxy[0].resolver_url" 2>/dev/null)"
        [ -n "$_u" ] && printf "  ${C_PINK}↻ Удаляется DNS-секция: %s${C_NC}\n" "$_u"
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
    printf "${C_GREEN}✓ Старых DNS-секций удалено: %s. Устанавливается полный набор DNS Manager.${C_NC}\n" "$_removed"
}
record_own() {
    _own_line="$(printf '%s|%s|%s|%s' "$1" "$2" "$3" "$4")"
    grep -Fqx -- "$_own_line" "$OWNERSHIP" 2>/dev/null || printf '%s\n' "$_own_line" >> "$OWNERSHIP"
}
configure_hdp_manager_control() {
    uci set https-dns-proxy.config.dnsmasq_config_update='-' || return 1
    uci set https-dns-proxy.config.force_dns='0' || return 1
    uci set https-dns-proxy.config.notrack_dns='0' || return 1
    uci commit https-dns-proxy || return 1
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
eval "PORT_$slot=\"$target\""
printf "  ${C_GREEN}+ %s → 127.0.0.1:%s${C_NC}\n" "$name" "$target"
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
eval "PORT_$slot=\"$target\""
printf "  ${C_GREEN}+ %s → 127.0.0.1:%s${C_NC}\n" "$name" "$target"
}
repair_duplicate_own_doh_ports() {
[ -s "$DOH_INV" ] || return 0
dup_ports="$TMP_DIR/dup-own-ports"
awk -F'|' '$2!=""{cnt[$2]++} END{for(p in cnt) if(cnt[p]>1) print p}' "$DOH_INV" > "$dup_ports"
[ -s "$dup_ports" ] || return 0
while IFS= read -r p; do
first=1
while IFS='|' read -r idx url; do
if [ "$first" -eq 1 ]; then
first=0
claim_port_tx "$p" || return 1
continue
fi
oldp="$p"
free_port || return 1
newp="$FREE_PORT_RESULT"
uci set "https-dns-proxy.@https-dns-proxy[$idx].listen_port=$newp" || return 1
record_own "doh" "$newp" "$url" "repair_duplicate_port=$oldp;section=$idx"
log_tx "PLAN" "doh.duplicate.$idx" "MOVE" "OK" "from=$oldp;to=$newp;url=$url"
printf "  ${C_YELLOW}↻ Исправлен дубликат порта %s для %s → %s (${C_GREEN}успешно${C_NC})\n" "$oldp" "$(dns_name "$url")" "$newp"
done <<EOF_DUP
$(awk -F'|' -v p="$p" '$2==p{print $1"|"$5}' "$DOH_INV")
EOF_DUP
done < "$dup_ports"
}
reconcile_selected_own_doh() {
    _keep="$TMP_DIR/keep-own-doh"
    : > "$_keep"
    for s in 1 2 3 4 5 6 RU RU_2; do
        eval "_id=\${SLOT_$s}"
        [ -n "$_id" ] || continue
        _u="$(normalize_url "$(dns_url "$_id")")"
        [ -n "$_u" ] && printf '%s\n' "$_u" >> "$_keep"
    done
    sort -u "$_keep" -o "$_keep" 2>/dev/null || true
    i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$i]" >/dev/null 2>&1; do
        _u="$(normalize_url "$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].resolver_url" 2>/dev/null)")"
        if [ -z "$_u" ] || ! grep -qxF "$_u" "$_keep" 2>/dev/null; then
            uci -q delete "https-dns-proxy.@https-dns-proxy[$i]" || return 1
            continue
        fi
        i=$((i+1))
    done
    return 0
}
validate_selected_slots() {
    _urls="$TMP_DIR/selected-urls"
    _ports="$TMP_DIR/selected-ports"
    : > "$_urls"; : > "$_ports"
    for s in 1 2 3 4 5 6 RU RU_2; do
        eval "_id=\${SLOT_$s}"
        [ -n "$_id" ] || continue
        _u="$(normalize_url "$(dns_url "$_id")")"
        [ -n "$_u" ] || { err_msg "Слот $s содержит DNS без URL."; return 1; }
        if [ "$DNS_PROFILE" = hybrid ]; then
            ensure_test_results_fresh || return 1
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
get_dnsmasq_section() {
_secs="$(uci show dhcp 2>/dev/null | sed -n 's/^dhcp\.\([^.=]*\)=dnsmasq$/\1/p')"
for _s in $_secs; do
_iface="$(uci -q get "dhcp.$_s.interface" 2>/dev/null)"
[ "$_iface" = "lan" ] && { printf '%s' "$_s"; return; }
done
_s="$(printf '%s\n' $_secs | head -n1)"
[ -n "$_s" ] && { printf '%s' "$_s"; return; }
printf '%s' "@dnsmasq[0]"
}
exact_list_has() {
target="$1"; val="$2"
uci -q get "$target" 2>/dev/null | tr ' ' '\n' | sed "s/^['\"]//; s/['\"]$//" | grep -qxF "$val"
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
                for _os in 1 2 3 4 5 6 RU RU_2; do
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
    if [ -n "${PORT_RU_2:-}" ]; then
        case "$_val" in
            /ru/127.0.0.1#${PORT_RU_2}|/su/127.0.0.1#${PORT_RU_2}|/xn--p1ai/127.0.0.1#${PORT_RU_2}) return 0 ;;
        esac
    fi
    return 1
}
reconcile_dnsmasq() {
    sec="$(get_dnsmasq_section)"
    uci -q get "dhcp.$sec" >/dev/null 2>&1 || return 1
    [ -s "$PREV_DNSMASQ" ] || {
      {
        printf 'SERVER\n'
        uci -q get "dhcp.$sec.server" 2>/dev/null | tr ' ' '\n'
        printf 'ALLSERVERS=%s\n' "$(uci -q get "dhcp.$sec.allservers" 2>/dev/null)"
        printf 'STRICTORDER=%s\n' "$(uci -q get "dhcp.$sec.strictorder" 2>/dev/null)"
        printf 'NORESOLV=%s\n' "$(uci -q get "dhcp.$sec.noresolv" 2>/dev/null)"
        printf 'SECTION=%s\n' "$sec"
      } > "$PREV_DNSMASQ" 2>/dev/null || true
    }
    # DNS Manager is authoritative for upstream DNS in this profile.
    # Rebuild the server list from scratch so stale/foreign DNS entries cannot
    # survive an apply. The original values are preserved in PREV_DNSMASQ.
    while uci -q delete "dhcp.$sec.server" >/dev/null 2>&1; do :; done
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
    if [ "$TLD_RU_ENABLED" = 1 ] && [ -n "$SLOT_RU_2" ] && [ -n "$PORT_RU_2" ]; then
        for t in /ru /su /xn--p1ai; do
            val="$t/127.0.0.1#$PORT_RU_2"
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
# ==========================================
firewall_quic_rule_matches() {
    _rsec="$1"; _port="$2"
    [ "$(uci -q get "firewall.$_rsec" 2>/dev/null)" = rule ] || return 1
    firewall_ref_matches_zone "$(uci -q get "firewall.$_rsec.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" || return 1
    firewall_ref_matches_zone "$(uci -q get "firewall.$_rsec.dest" 2>/dev/null)" "$FIREWALL_WAN_ZONE" || return 1
    [ "$(uci -q get "firewall.$_rsec.proto" 2>/dev/null)" = udp ] || return 1
    [ "$(uci -q get "firewall.$_rsec.dest_port" 2>/dev/null)" = "$_port" ] || return 1
    [ "$(uci -q get "firewall.$_rsec.target" 2>/dev/null)" = REJECT ] || return 1
    return 0
}
firewall_owner_has() {
    _sec="$1"
    [ -n "$_sec" ] || return 1
    [ -f "$FIREWALL_OWNERSHIP" ] || return 1
    grep -Fqx -- "$_sec" "$FIREWALL_OWNERSHIP" 2>/dev/null
}
firewall_owner_add() {
    _sec="$1"
    [ -n "$_sec" ] || return 1
    mkdir -p "$CFG_DIR" 2>/dev/null || return 1
    firewall_owner_has "$_sec" || printf '%s\n' "$_sec" >> "$FIREWALL_OWNERSHIP" || return 1
    return 0
}
firewall_owner_remove() {
    _sec="$1"
    [ -f "$FIREWALL_OWNERSHIP" ] || return 0
    _tmp="$FIREWALL_OWNERSHIP.tmp.$$"
    grep -Fvx -- "$_sec" "$FIREWALL_OWNERSHIP" > "$_tmp" 2>/dev/null || :
    mv "$_tmp" "$FIREWALL_OWNERSHIP" 2>/dev/null || { rm -f "$_tmp"; return 1; }
    return 0
}
firewall_ownership_sync() {
    [ -f "$FIREWALL_OWNERSHIP" ] || return 0
    _tmp="$FIREWALL_OWNERSHIP.tmp.$$"
    : > "$_tmp" || return 1
    while IFS= read -r _sec; do
        [ -n "$_sec" ] || continue
        case "$_sec" in
            "$FW_NTP_SECTION") firewall_section_owned_redirect "$FW_NTP_SECTION" "$FIREWALL_LAN_ZONE" udp 123 "$LAN_IP" 123 DNAT && printf '%s\n' "$_sec" >> "$_tmp";;
            "$FW_DNS_REDIRECT_SECTION") firewall_section_owned_redirect "$FW_DNS_REDIRECT_SECTION" "$FIREWALL_LAN_ZONE" 'tcp udp' 53 "$LAN_IP" 53 DNAT && printf '%s\n' "$_sec" >> "$_tmp";;
            "$FW_DOT_SECTION")
                [ "$(uci -q get "firewall.$FW_DOT_SECTION" 2>/dev/null)" = rule ] || continue
                firewall_ref_matches_zone "$(uci -q get "firewall.$FW_DOT_SECTION.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" || continue
                firewall_ref_matches_zone "$(uci -q get "firewall.$FW_DOT_SECTION.dest" 2>/dev/null)" "$FIREWALL_WAN_ZONE" || continue
                [ "$(uci -q get "firewall.$FW_DOT_SECTION.proto" 2>/dev/null)" = 'tcp udp' ] || continue
                [ "$(uci -q get "firewall.$FW_DOT_SECTION.dest_port" 2>/dev/null)" = 853 ] || continue
                [ "$(uci -q get "firewall.$FW_DOT_SECTION.target" 2>/dev/null)" = REJECT ] || continue
                printf '%s\n' "$_sec" >> "$_tmp";;
            "$FW_WEB_SECTION")
                [ "$(uci -q get "firewall.$FW_WEB_SECTION" 2>/dev/null)" = rule ] || continue
                firewall_ref_matches_zone "$(uci -q get "firewall.$FW_WEB_SECTION.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" || continue
                [ "$(uci -q get "firewall.$FW_WEB_SECTION.proto" 2>/dev/null)" = tcp ] || continue
                [ "$(uci -q get "firewall.$FW_WEB_SECTION.dest_port" 2>/dev/null)" = "$WEB_ACCESS_PORT" ] || continue
                [ "$(uci -q get "firewall.$FW_WEB_SECTION.target" 2>/dev/null)" = ACCEPT ] || continue
                printf '%s\n' "$_sec" >> "$_tmp";;
            "$FW_QUIC80_SECTION") firewall_quic_rule_matches "$FW_QUIC80_SECTION" 80 && printf '%s\n' "$_sec" >> "$_tmp";;
            "$FW_QUIC443_SECTION") firewall_quic_rule_matches "$FW_QUIC443_SECTION" 443 && printf '%s\n' "$_sec" >> "$_tmp";;
        esac
    done < "$FIREWALL_OWNERSHIP"
    mv "$_tmp" "$FIREWALL_OWNERSHIP" 2>/dev/null || rm -f "$_tmp"
    return 0
}
firewall_migrate_legacy_owned() {
    mkdir -p "$CFG_DIR" 2>/dev/null || return 0
    # Previous DNS Manager versions used reserved section IDs without an ownership registry.
    # Migrate only when the full rule signature matches the known manager rule.
    firewall_section_owned_redirect "$FW_NTP_SECTION" "$FIREWALL_LAN_ZONE" udp 123 "$LAN_IP" 123 DNAT && firewall_owner_add "$FW_NTP_SECTION"
    firewall_section_owned_redirect "$FW_DNS_REDIRECT_SECTION" "$FIREWALL_LAN_ZONE" 'tcp udp' 53 "$LAN_IP" 53 DNAT && firewall_owner_add "$FW_DNS_REDIRECT_SECTION"
    firewall_quic_rule_matches "$FW_QUIC80_SECTION" 80 && firewall_owner_add "$FW_QUIC80_SECTION"
    firewall_quic_rule_matches "$FW_QUIC443_SECTION" 443 && firewall_owner_add "$FW_QUIC443_SECTION"
    if [ "$(uci -q get "firewall.$FW_DOT_SECTION" 2>/dev/null)" = rule ] && firewall_ref_matches_zone "$(uci -q get "firewall.$FW_DOT_SECTION.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" && firewall_ref_matches_zone "$(uci -q get "firewall.$FW_DOT_SECTION.dest" 2>/dev/null)" "$FIREWALL_WAN_ZONE" && [ "$(uci -q get "firewall.$FW_DOT_SECTION.proto" 2>/dev/null)" = 'tcp udp' ] && [ "$(uci -q get "firewall.$FW_DOT_SECTION.dest_port" 2>/dev/null)" = 853 ] && [ "$(uci -q get "firewall.$FW_DOT_SECTION.target" 2>/dev/null)" = REJECT ]; then firewall_owner_add "$FW_DOT_SECTION"; fi
    if [ "$(uci -q get "firewall.$FW_WEB_SECTION" 2>/dev/null)" = rule ] && firewall_ref_matches_zone "$(uci -q get "firewall.$FW_WEB_SECTION.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" && [ "$(uci -q get "firewall.$FW_WEB_SECTION.proto" 2>/dev/null)" = tcp ] && [ "$(uci -q get "firewall.$FW_WEB_SECTION.dest_port" 2>/dev/null)" = "$WEB_ACCESS_PORT" ] && [ "$(uci -q get "firewall.$FW_WEB_SECTION.target" 2>/dev/null)" = ACCEPT ]; then firewall_owner_add "$FW_WEB_SECTION"; fi
    firewall_ownership_sync
    return 0
}
firewall_find_exact_quic() {
    _port="$1"; _skip="$2"
    _secs="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=rule$/\1/p')"
    for _sec in $_secs; do
        [ "$_sec" = "$_skip" ] && continue
        if firewall_quic_rule_matches "$_sec" "$_port"; then
            printf '%s\n' "$_sec"
            return 0
        fi
    done
    return 1
}
firewall_quic_function_exists() {
    _port="$1"
    firewall_resolve_zones >/dev/null 2>&1 || return 1
    _secs="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=rule$/\1/p')"
    for _sec in $_secs; do
        [ "$(uci -q get "firewall.$_sec.disabled" 2>/dev/null)" = 1 ] && continue
        [ "$(uci -q get "firewall.$_sec.proto" 2>/dev/null)" = udp ] || continue
        [ "$(uci -q get "firewall.$_sec.dest_port" 2>/dev/null)" = "$_port" ] || continue
        [ "$(uci -q get "firewall.$_sec.target" 2>/dev/null)" = REJECT ] || continue
        _src="$(uci -q get "firewall.$_sec.src" 2>/dev/null)"
        _dst="$(uci -q get "firewall.$_sec.dest" 2>/dev/null)"
        _src_name="$(firewall_zone_name "$_src" 2>/dev/null)"
        _dst_name="$(firewall_zone_name "$_dst" 2>/dev/null)"
        [ "$_src_name" = "$FIREWALL_LAN_NAME" ] || continue
        [ "$_dst_name" = "$FIREWALL_WAN_NAME" ] || continue
        printf '%s\n' "$_sec"
        return 0
    done
    return 1
}
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
firewall_quic_rule_owned() {
    _rsec="$1"; _port="$2"
    [ "$_rsec" = "$FW_QUIC80_SECTION" ] || [ "$_rsec" = "$FW_QUIC443_SECTION" ] || return 1
    firewall_quic_rule_matches "$_rsec" "$_port" || return 1
    firewall_owner_has "$_rsec"
}
quic_remove_managed_rules() {
    for _pair in "$FW_QUIC80_SECTION|80" "$FW_QUIC443_SECTION|443"; do
        _rsec="${_pair%%|*}"
        _port="${_pair#*|}"
        if uci -q get "firewall.$_rsec" >/dev/null 2>&1; then
            if firewall_quic_rule_matches "$_rsec" "$_port"; then
                uci -q delete "firewall.$_rsec" || return 1
                firewall_owner_remove "$_rsec" >/dev/null 2>&1 || true
            fi
        fi
    done
    return 0
}
quic_ensure_rule() {
    _rsec="$1"; _port="$2"; _label="$3"
    if uci -q get "firewall.$_rsec" >/dev/null 2>&1; then
        if firewall_quic_rule_matches "$_rsec" "$_port"; then
            firewall_owner_add "$_rsec" >/dev/null 2>&1 || true
            return 0
        fi
        if firewall_find_exact_quic "$_port" "$_rsec" >/dev/null 2>&1; then
            uci -q delete "firewall.$_rsec" || return 1
            firewall_owner_remove "$_rsec" >/dev/null 2>&1 || true
            return 3
        fi
        if [ "${FORCE_APPLY_SETTINGS:-0}" = 1 ]; then
            uci set "firewall.$_rsec=rule" || return 1
            uci set "firewall.$_rsec.name=$_label" || return 1
            uci set "firewall.$_rsec.proto=udp" || return 1
            uci set "firewall.$_rsec.src=$FIREWALL_LAN_NAME" || return 1
            uci set "firewall.$_rsec.dest=$FIREWALL_WAN_NAME" || return 1
            uci set "firewall.$_rsec.dest_port=$_port" || return 1
            uci set "firewall.$_rsec.target=REJECT" || return 1
            firewall_owner_add "$_rsec" || return 1
            return 0
        fi
        return 2
    fi
    if firewall_find_exact_quic "$_port" "$_rsec" >/dev/null 2>&1; then
        return 3
    fi
    uci set "firewall.$_rsec=rule" || return 1
    uci set "firewall.$_rsec.name=$_label" || return 1
    uci set "firewall.$_rsec.proto=udp" || return 1
    uci set "firewall.$_rsec.src=$FIREWALL_LAN_NAME" || return 1
    uci set "firewall.$_rsec.dest=$FIREWALL_WAN_NAME" || return 1
    uci set "firewall.$_rsec.dest_port=$_port" || return 1
    uci set "firewall.$_rsec.target=REJECT" || return 1
    firewall_owner_add "$_rsec" || return 1
    return 0
}
apply_quic() {
    [ "$BLOCK_QUIC" = 1 ] || return 0
    firewall_lan_zone_require >/dev/null || return 1
    firewall_wan_zone_require >/dev/null || return 1
    quic_remove_managed_rules || return 1
    quic_ensure_rule "$FW_QUIC80_SECTION" 80 'DNS Manager: Block UDP 80'
    _rc=$?
    [ "$_rc" -eq 0 ] || { [ "$_rc" -eq 3 ] || return 1; }
    quic_ensure_rule "$FW_QUIC443_SECTION" 443 'DNS Manager: Block UDP 443'
    _rc=$?
    [ "$_rc" -eq 0 ] || { [ "$_rc" -eq 3 ] || return 1; }
    uci commit firewall || return 1
}

sysctl_base_manager_path() { printf '%s' "/etc/sysctl.d/90-dns-manager.conf"; }
sysctl_extended_manager_path() { printf '%s' "/etc/sysctl.d/91-dns-manager-extended.conf"; }
sysctl_base_managed_files() {
    [ -f "/etc/sysctl.d/90-dns-manager.conf" ] && printf '%s\n' "/etc/sysctl.d/90-dns-manager.conf"
}
sysctl_extended_managed_files() {
    [ -f "/etc/sysctl.d/91-dns-manager-extended.conf" ] && printf '%s\n' "/etc/sysctl.d/91-dns-manager-extended.conf"
}

migrate_legacy_manager_files() {
    _src="/etc/sysctl.d/98-dns-manager.conf"
    _dst="/etc/sysctl.d/90-dns-manager.conf"
    if [ -f "$_src" ] && [ ! -f "$_dst" ] && sysctl_base_file_owned "$_src"; then
        cp -p "$_src" "$_dst" 2>/dev/null || return 1
        rm -f "$_src" 2>/dev/null || return 1
    elif [ -f "$_src" ] && [ -f "$_dst" ] && sysctl_base_file_owned "$_src"; then
        rm -f "$_src" 2>/dev/null || return 1
    fi
    _src="/etc/sysctl.d/99-dns-manager-extended.conf"
    _dst="/etc/sysctl.d/91-dns-manager-extended.conf"
    if [ -f "$_src" ] && [ ! -f "$_dst" ] && sysctl_extended_file_owned "$_src"; then
        cp -p "$_src" "$_dst" 2>/dev/null || return 1
        rm -f "$_src" 2>/dev/null || return 1
    elif [ -f "$_src" ] && [ -f "$_dst" ] && sysctl_extended_file_owned "$_src"; then
        rm -f "$_src" 2>/dev/null || return 1
    fi
    return 0
}

sysctl_base_expected() {
    cat <<EOF_SYSCTL_BASE_EXPECTED
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_fin_timeout=15
net.core.somaxconn=1024
EOF_SYSCTL_BASE_EXPECTED
}

sysctl_file_state() {
    _f="$1"; _marker="$2"; _expected="$3"
    [ -f "$_f" ] || { printf '0'; return 0; }
    _managed="$(printf '%s\n%s' "$_marker" "$_expected")"
    _actual="$(cat "$_f" 2>/dev/null)"
    [ "$_actual" = "$_managed" ] && { printf '1'; return 0; }
    [ "$_actual" = "$_expected" ] && { printf '1'; return 0; }
    _first="$(sed -n '1p' "$_f" 2>/dev/null)"
    [ "$_first" = "$_marker" ] && printf '2' || printf '3'
}

sysctl_base_file_owned() {
    _f="$1"
    [ -f "$_f" ] || return 1
    _state="$(sysctl_file_state "$_f" "$SYSCTL_BASE_MARKER" "$(sysctl_base_expected)")"
    [ "$_state" = 1 ]
}
apply_sysctl() {
    f="$(sysctl_base_manager_path)"
    sf="$STATE_DIR/sysctl-before.conf"
    _expected="$(sysctl_base_expected)"
    [ "${SYSCTL_TUNING:-0}" = 1 ] || return 0

    if [ -f "$f" ]; then
        _state="$(sysctl_file_state "$f" "$SYSCTL_BASE_MARKER" "$_expected")"
        case "$_state" in
            2) err_msg "Файл $f содержит маркер DNS Manager, но был изменён извне. Перезапись запрещена."; return 2;;
            3) err_msg "Файл $f уже используется другой настройкой. DNS Manager его не перезаписывает."; return 2;;
        esac
    fi

    if [ ! -s "$sf" ]; then : > "$sf" || return 1; fi
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        _k="${_p%%=*}"
        _old="$(sysctl -n "$_k" 2>/dev/null)"
        grep -q "^${_k}|" "$sf" 2>/dev/null || printf '%s|%s\n' "$_k" "${_old:-unknown}" >> "$sf" || return 1
    done <<EOF_SYSCTL_BASE_SAVE
$_expected
EOF_SYSCTL_BASE_SAVE

    _tmp="$f.tmp.$$"
    {
        printf '%s\n' "$SYSCTL_BASE_MARKER"
        printf '%s\n' "$_expected"
    } > "$_tmp" || { rm -f "$_tmp"; return 1; }

    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        _out="$(sysctl -w "$_p" 2>&1)"
        _rc=$?
        [ "$_rc" -eq 0 ] || {
            [ -n "$_out" ] && err_msg "Не удалось применить $_p: $_out" || err_msg "Не удалось применить $_p."
            rm -f "$_tmp"
            while IFS='|' read -r _k _v; do
                [ -n "$_k" ] && [ "$_v" != unknown ] && sysctl -w "$_k=$_v" >/dev/null 2>&1 || true
            done < "$sf"
            return 1
        }
        record_own "sysctl" "${_p%%=*}" "${_p#*=}" "base-applied"
    done <<EOF_SYSCTL_BASE_APPLY
$_expected
EOF_SYSCTL_BASE_APPLY

    mv "$_tmp" "$f" || { rm -f "$_tmp"; return 1; }
    return 0
}
sysctl_restore_key_if_unchanged() {
    _k="$1"; _old="$2"; _managed="$3"
    [ -n "$_old" ] && [ "$_old" != unknown ] || return 0
    _cur="$(sysctl -n "$_k" 2>/dev/null)"
    if [ "$_cur" = "$_managed" ]; then
        sysctl -w "$_k=$_old" >/dev/null 2>&1 || true
    else
        warn_msg "sysctl: $_k изменён извне после применения DNS Manager. Текущее значение сохранено."
    fi
}

remove_sysctl_base() {
    sf="$STATE_DIR/sysctl-before.conf"
    _f="$(sysctl_base_manager_path)"
    _state=0
    [ -f "$_f" ] && _state="$(sysctl_file_state "$_f" "$SYSCTL_BASE_MARKER" "$(sysctl_base_expected)")"
    case "$_state" in
        2) warn_msg "Базовый sysctl-файл изменён извне: $_f. Файл сохранён."; rm -f "$sf"; return 0;;
        3) warn_msg "Базовый sysctl-файл не принадлежит DNS Manager: $_f. Файл сохранён."; rm -f "$sf"; return 0;;
    esac
    if [ -s "$sf" ]; then
        for _kv in "net.ipv4.tcp_fastopen|3" "net.ipv4.tcp_fin_timeout|15" "net.core.somaxconn|1024"; do
            _k="${_kv%%|*}"; _m="${_kv#*|}"
            _old="$(awk -F'|' -v k="$_k" '$1==k{print $2;exit}' "$sf" 2>/dev/null)"
            sysctl_restore_key_if_unchanged "$_k" "$_old" "$_m"
        done
    fi
    [ -f "$_f" ] && rm -f "$_f" || true
    rm -f "$sf"
    return 0
}
apply_sysctl_bundle() {
    _want_base="$1"
    _want_ext="$2"
    _saved_base="$SYSCTL_TUNING"
    _saved_ext="$SYSCTL_EXTENDED"
    SYSCTL_TUNING="$_want_base"
    SYSCTL_EXTENDED="$_want_ext"

    if [ "$_want_base" = 1 ]; then
        apply_sysctl || {
            SYSCTL_TUNING="$_saved_base"
            SYSCTL_EXTENDED="$_saved_ext"
            err_msg "Базовый sysctl не применён. Проверьте параметры net.ipv4.tcp_fastopen, net.ipv4.tcp_fin_timeout и net.core.somaxconn."
            return 1
        }
    else
        remove_sysctl_base || {
            SYSCTL_TUNING="$_saved_base"
            SYSCTL_EXTENDED="$_saved_ext"
            err_msg "Не удалось отключить базовый sysctl."
            return 1
        }
    fi

    if [ "$_want_ext" = 1 ]; then
        apply_sysctl_extended || {
            remove_sysctl_base >/dev/null 2>&1 || true
            SYSCTL_TUNING="$_saved_base"
            SYSCTL_EXTENDED="$_saved_ext"
            err_msg "Расширенный sysctl не применён. Проверьте nf_conntrack и параметры TCP/buffer. Базовый слой откатан."
            return 1
        }
    else
        remove_sysctl_extended || {
            SYSCTL_TUNING="$_saved_base"
            SYSCTL_EXTENDED="$_saved_ext"
            err_msg "Не удалось отключить расширенный sysctl."
            return 1
        }
    fi

    run_discovery || return 1
    save_config || return 1
    return 0
}
# ==========================================
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
        quic)
            apply_quic_toggle || return 1
            ;;
        mtu)
            apply_mtu_toggle || return 1
            ;;
        sysctl)
            apply_sysctl_bundle "$SYSCTL_TUNING" "$SYSCTL_EXTENDED" || return 1
            ;;
        force)
            if [ "$FORCE_DOH" = 1 ]; then
                apply_dns_force || return 1
            else
                remove_dns_force || return 1
            fi
            reload_fw || return 1
            ;;
        ntp_clients)
            if [ "$NTP_CLIENTS" = 1 ]; then
                apply_ntp_clients || return 1
            else
                remove_ntp_clients || return 1
            fi
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
            reload_fw || return 1
            ;;
        dnsmasq_perf)
            if [ "$DNSMASQ_PERF" = 1 ]; then
                apply_dnsmasq_perf || return 1
            else
                remove_dnsmasq_perf || return 1
            fi
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
            ;;
        client_fixes)
            f="$(client_fixes_find_owned 2>/dev/null || true)"
            [ -n "$f" ] || { printf 0; return; }
            client_fixes_file_owned "$f" && printf 1 || printf 0
            ;;
        sysctl_ext)
            if [ "$SYSCTL_EXTENDED" = 1 ]; then
                apply_sysctl_extended || return 1
            else
                remove_sysctl_extended || return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
    run_discovery || return 1
    save_config || return 1
    return 0
}

apply_extras_now() {
    _label="$2"
    if [ -z "$_label" ]; then
        case "$1" in
            balance|tld) _label="Применяю DNS и перезапускаю dnsmasq";;
            ntp) _label="Применяю настройку времени";;
            quic) _label="Применяю правила QUIC";;
            mtu) _label="Применяю MTU/MSS";;
            sysctl) _label="Применяю тюнинг TCP и Conntrack";;
            force) _label="Применяю принудительный DNS";;
            ntp_clients) _label="Применяю NTP для устройств сети";;
            dnsmasq_perf) _label="Применяю кэширование DNS";;
            client_fixes) _label="Применяю клиентские исправления";;
            sysctl_ext) _label="Применяю расширенный sysctl";;
            *) _label="Применяю настройки";;
        esac
    fi
    apply_wait_message "$_label"
    acquire_mutation_lock || return 1
    _rc=0
    _apply_extras_now_impl "$1" || _rc=$?
    release_mutation_lock
    return "$_rc"
}

# ==========================================
# ==========================================
# ==========================================
# ==========================================
# ==========================================
ntp_firewall_rule_owned() {
    firewall_lan_zone_require >/dev/null || return 1
    firewall_section_owned_redirect "$FW_NTP_SECTION" "$FIREWALL_LAN_ZONE" udp 123 "$LAN_IP" 123 DNAT
}
ntp_firewall_rule_exact_external() {
    firewall_find_exact_redirect "$FIREWALL_LAN_ZONE" udp 123 "$LAN_IP" 123 DNAT "$FW_NTP_SECTION" >/dev/null 2>&1
}
apply_ntp_clients() {
    [ "${NTP_CLIENTS:-0}" = 1 ] || return 0
    firewall_lan_zone_require >/dev/null || return 1
    sec="$(get_dnsmasq_section)"; [ -n "$sec" ] || return 1
    if [ ! -s "$NTP_CLIENTS_BEFORE" ]; then
        {
            printf 'state_version|2\n'
            printf 'section|%s\n' "$sec"
            if exact_list_has "dhcp.$sec.dhcp_option" "42,$LAN_IP"; then
                printf 'dhcp_added|0\n'
                printf 'dhcp_added_option|\n'
            else
                printf 'dhcp_added|1\n'
                printf 'dhcp_added_option|42,%s\n' "$LAN_IP"
            fi
            if ntp_firewall_rule_owned && firewall_owner_has "$FW_NTP_SECTION"; then
                printf 'fw_manager_owned|1\n'
            else
                printf 'fw_manager_owned|0\n'
            fi
        } > "$NTP_CLIENTS_BEFORE" || return 1
    fi

    _opt="42,$LAN_IP"
    exact_list_has "dhcp.$sec.dhcp_option" "$_opt" ||         uci add_list "dhcp.$sec.dhcp_option=$_opt" || return 1

    if uci -q get "firewall.$FW_NTP_SECTION" >/dev/null 2>&1; then
        if ntp_firewall_rule_owned; then
            uci -q set "firewall.$FW_NTP_SECTION.dest=$FIREWALL_LAN_NAME" || return 1
            firewall_owner_add "$FW_NTP_SECTION" >/dev/null 2>&1 || true
        elif [ "${FORCE_APPLY_SETTINGS:-0}" = 1 ]; then
            uci set "firewall.$FW_NTP_SECTION=redirect" || return 1
            uci set "firewall.$FW_NTP_SECTION.name=DNS Manager: NTP клиентов в роутер" || return 1
            uci set "firewall.$FW_NTP_SECTION.src=$FIREWALL_LAN_NAME" || return 1
            uci set "firewall.$FW_NTP_SECTION.dest=$FIREWALL_LAN_NAME" || return 1
            uci set "firewall.$FW_NTP_SECTION.proto=udp" || return 1
            uci set "firewall.$FW_NTP_SECTION.src_dport=123" || return 1
            uci set "firewall.$FW_NTP_SECTION.dest_ip=$LAN_IP" || return 1
            uci set "firewall.$FW_NTP_SECTION.dest_port=123" || return 1
            uci set "firewall.$FW_NTP_SECTION.target=DNAT" || return 1
            firewall_owner_add "$FW_NTP_SECTION" || return 1
        else
            return 2
        fi
    elif ntp_firewall_rule_exact_external; then
        :
    else
        uci set "firewall.$FW_NTP_SECTION=redirect" || return 1
        uci set "firewall.$FW_NTP_SECTION.name=DNS Manager: NTP клиентов в роутер" || return 1
        uci set "firewall.$FW_NTP_SECTION.src=$FIREWALL_LAN_NAME" || return 1
        uci set "firewall.$FW_NTP_SECTION.dest=$FIREWALL_LAN_NAME" || return 1
        uci set "firewall.$FW_NTP_SECTION.proto=udp" || return 1
        uci set "firewall.$FW_NTP_SECTION.src_dport=123" || return 1
        uci set "firewall.$FW_NTP_SECTION.dest_ip=$LAN_IP" || return 1
        uci set "firewall.$FW_NTP_SECTION.dest_port=123" || return 1
        uci set "firewall.$FW_NTP_SECTION.target=DNAT" || return 1
        firewall_owner_add "$FW_NTP_SECTION" || return 1
    fi

    uci commit dhcp || return 1
    uci commit firewall || return 1
}
apply_dnsmasq_perf() {
    [ "${DNSMASQ_PERF:-0}" = 1 ] || return 0
    sec="$(get_dnsmasq_section)"
    [ -n "$sec" ] || return 1
    _f="$STATE_DIR/dnsmasq-perf-before.conf"
    if [ ! -s "$_f" ]; then
        : > "$_f" || return 1
        for _k in cachesize dnsforwardmax max_cache_ttl boguspriv domainneeded quietdhcp filter_aaaa; do
            _v="$(uci -q get "dhcp.$sec.$_k" 2>/dev/null)"
            printf '%s|%s\n' "$_k" "$_v" >> "$_f" || return 1
        done
    fi
    uci set "dhcp.$sec.cachesize=1000" || return 1
    uci set "dhcp.$sec.dnsforwardmax=300" || return 1
    uci set "dhcp.$sec.max_cache_ttl=86400" || return 1
    uci set "dhcp.$sec.boguspriv=1" || return 1
    uci set "dhcp.$sec.domainneeded=1" || return 1
    uci set "dhcp.$sec.quietdhcp=1" || return 1
    if [ "$IPV6_ROUTE" != yes ]; then uci set "dhcp.$sec.filter_aaaa=1" || return 1; fi
    uci commit dhcp || return 1
}
remove_dnsmasq_perf() {
    sec="$(get_dnsmasq_section)"
    [ -n "$sec" ] || return 0
    _f="$STATE_DIR/dnsmasq-perf-before.conf"
    [ -s "$_f" ] || return 0
    _changed=0
    while IFS='|' read -r _k _old; do
        [ -n "$_k" ] || continue
        case "$_k" in
            cachesize) _mgr=1000;;
            dnsforwardmax) _mgr=300;;
            max_cache_ttl) _mgr=86400;;
            boguspriv|domainneeded|quietdhcp|filter_aaaa) _mgr=1;;
            *) continue;;
        esac
        _cur="$(uci -q get "dhcp.$sec.$_k" 2>/dev/null)"
        if [ "$_cur" = "$_mgr" ]; then
            if [ -n "$_old" ]; then uci set "dhcp.$sec.$_k=$_old"; else uci -q delete "dhcp.$sec.$_k"; fi
            _changed=1
        else
            warn_msg "dnsmasq: $_k изменён извне после применения DNS Manager. Текущее значение сохранено."
        fi
    done < "$_f"
    [ "$_changed" = 1 ] && uci commit dhcp >/dev/null 2>&1 || true
    rm -f "$_f"
}
client_fixes_expected_body() {
    cat <<EOF_CLIENT_FIXES_BODY
local=/telemetry.mozilla.org/
local=/telemetry.microsoft.com/
local=/vortex.data.microsoft.com/
local=/settings-win.data.microsoft.com/
local=/metrics.android.com/
local=/metrics.samsung.com/
server=/clients3.google.com/77.88.8.8
server=/clients3.google.com/77.88.8.1
server=/connectivitycheck.gstatic.com/77.88.8.8
server=/connectivitycheck.gstatic.com/77.88.8.1
server=/connectivitycheck.android.com/77.88.8.8
server=/connectivitycheck.android.com/77.88.8.1
server=/connectivitycheck.samsung.com/77.88.8.8
server=/connectivitycheck.samsung.com/77.88.8.1
server=/connectivitycheck.platform.hicloud.com/77.88.8.8
server=/connectivitycheck.platform.hicloud.com/77.88.8.1
EOF_CLIENT_FIXES_BODY
}
client_fixes_file_state() {
    _f="$1"
    [ -f "$_f" ] || { printf '0'; return 0; }
    _actual="$(sed         -e '1{/^# DNS_MANAGER_MANAGED_CLIENT_FIXES=1$/d;}'         -e '1{/^# DNS_MANAGER_CLIENT_FIXES=1$/d;}'         -e '/^[[:space:]]*$/d' "$_f" 2>/dev/null)"
    [ "$_actual" = "$(client_fixes_expected_body)" ] && printf '1' || printf '2'
}
client_fixes_file_owned() {
    [ "$(client_fixes_file_state "$1")" = 1 ]
}
client_fixes_find_owned() {
    for _cand in /etc/dnsmasq.d/*dns-manager-client-fixes*.conf; do
        [ -f "$_cand" ] || continue
        [ "$(client_fixes_file_state "$_cand")" = 1 ] && { printf '%s\n' "$_cand"; return 0; }
    done
    return 1
}
client_fixes_find_modified_owned() {
    for _cand in /etc/dnsmasq.d/*dns-manager-client-fixes*.conf; do
        [ -f "$_cand" ] || continue
        [ "$(client_fixes_file_state "$_cand")" = 2 ] && { printf '%s\n' "$_cand"; return 0; }
    done
    return 1
}
apply_client_fixes() {
    [ "${CLIENT_FIXES:-0}" = 1 ] || return 0
    _modified="$(client_fixes_find_modified_owned 2>/dev/null || true)"
    if [ -n "$_modified" ]; then
        err_msg "Файл DNS Manager client-fixes изменён извне: $_modified. Перезапись и создание второго файла запрещены."
        return 2
    fi
    _managed="$(client_fixes_find_owned 2>/dev/null || true)"
    [ -n "$_managed" ] || _managed="${CLIENT_FIXES_FILE:-}"
    if [ -n "$_managed" ] && [ -e "$_managed" ] && [ "$(client_fixes_file_state "$_managed")" != 1 ]; then _managed=""; fi
    if [ -z "$_managed" ]; then
        _n=91
        while :; do
            _candidate="/etc/dnsmasq.d/${_n}-dns-manager-client-fixes.conf"
            [ ! -e "$_candidate" ] && { _managed="$_candidate"; break; }
            _n=$((_n+1)); [ "$_n" -le 99 ] || { err_msg "Нет свободного имени для DNS Manager client-fixes; чужие файлы не перезаписываются."; return 2; }
        done
    fi
    CLIENT_FIXES_FILE="$_managed"
    {
        printf '%s\n' "$CLIENT_FIXES_MARKER"
        client_fixes_expected_body
    } > "$_managed.tmp.$$" || return 1
    mv "$_managed.tmp.$$" "$_managed" || { rm -f "$_managed.tmp.$$"; return 1; }
    return 0
}
remove_client_fixes() {
    for _f in /etc/dnsmasq.d/*dns-manager-client-fixes*.conf; do
        [ -f "$_f" ] || continue
        case "$(client_fixes_file_state "$_f")" in
            1) rm -f "$_f" || return 1;;
            2) warn_msg "Файл DNS Manager client-fixes изменён извне: $_f. Файл сохранён.";;
        esac
    done
    CLIENT_FIXES_FILE=""
    return 0
}
recommended_conntrack_max() {
    _mem="$(awk '/^MemTotal:/{print $2; exit}' /proc/meminfo 2>/dev/null)"
    case "$_mem" in ''|*[!0-9]*) printf '16384'; return;; esac
    if [ "$_mem" -lt 131072 ]; then printf '8192'
    elif [ "$_mem" -lt 262144 ]; then printf '16384'
    elif [ "$_mem" -lt 524288 ]; then printf '32768'
    else printf '65536'
    fi
}
sysctl_extended_params() {
    _ct="$(recommended_conntrack_max)"
    _buf=4194304
    _def=262144
    _mem="$(awk '/^MemTotal:/{print $2; exit}' /proc/meminfo 2>/dev/null)"
    case "$_mem" in ''|*[!0-9]*) ;; *)
        if [ "$_mem" -lt 262144 ]; then _buf=2097152; _def=131072; fi
        ;;
    esac
    cat <<EOF_SYSCTL_VALUES
net.netfilter.nf_conntrack_max=$_ct
net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_intvl=60
net.ipv4.tcp_keepalive_probes=5
net.core.rmem_max=$_buf
net.core.wmem_max=$_buf
net.core.rmem_default=$_def
net.core.wmem_default=$_def
EOF_SYSCTL_VALUES
}
apply_sysctl_extended() {
    f="$(sysctl_extended_manager_path)"
    sf="$STATE_DIR/sysctl-extended-before.conf"
    _params="$(sysctl_extended_params)"
    [ "${SYSCTL_EXTENDED:-0}" = 1 ] || return 0
    if [ -f "$f" ]; then
        _state="$(sysctl_file_state "$f" "$SYSCTL_EXTENDED_MARKER" "$_params")"
        case "$_state" in
            2) err_msg "Файл $f содержит маркер DNS Manager, но был изменён извне. Перезапись запрещена."; return 2;;
            3) err_msg "Файл $f уже используется другой настройкой. DNS Manager его не перезаписывает."; return 2;;
        esac
    fi
    [ -s "$sf" ] || : > "$sf" || return 1
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        _k="${p%%=*}"; _old="$(sysctl -n "$_k" 2>/dev/null)"
        grep -q "^${_k}|" "$sf" 2>/dev/null || printf '%s|%s\n' "$_k" "${_old:-unknown}" >> "$sf" || return 1
    done <<EOF_SYSCTL_EXT
$_params
EOF_SYSCTL_EXT
    if command -v modprobe >/dev/null 2>&1; then modprobe nf_conntrack >/dev/null 2>&1 || true; fi
    _tmp="$f.tmp.$$"
    {
        printf '%s\n' "$SYSCTL_EXTENDED_MARKER"
        printf '%s\n' "$_params"
    } > "$_tmp" || { rm -f "$_tmp"; return 1; }
    while IFS= read -r _p; do
        [ -n "$_p" ] || continue
        _out="$(sysctl -w "$_p" 2>&1)"
        [ $? -eq 0 ] || {
            [ -n "$_out" ] && err_msg "Не удалось применить расширенный sysctl: $_p: $_out" || err_msg "Не удалось применить расширенный sysctl: $_p"
            rm -f "$_tmp"
            while IFS='|' read -r _k _v; do
                [ -n "$_k" ] && [ "$_v" != unknown ] && sysctl -w "$_k=$_v" >/dev/null 2>&1 || true
            done < "$sf"
            return 1
        }
        record_own "sysctl" "${_p%%=*}" "${_p#*=}" "extended-applied"
    done <<EOF_SYSCTL_APPLY
$_params
EOF_SYSCTL_APPLY
    mv "$_tmp" "$f" || { rm -f "$_tmp"; return 1; }
    return 0
}
sysctl_extended_file_owned() {
    _f="$1"
    [ -f "$_f" ] || return 1
    _state="$(sysctl_file_state "$_f" "$SYSCTL_EXTENDED_MARKER" "$(sysctl_extended_params)")"
    [ "$_state" = 1 ]
}
remove_sysctl_extended() {
    sf="$STATE_DIR/sysctl-extended-before.conf"
    _f="$(sysctl_extended_manager_path)"
    _state=0
    [ -f "$_f" ] && _state="$(sysctl_file_state "$_f" "$SYSCTL_EXTENDED_MARKER" "$(sysctl_extended_params)")"
    case "$_state" in
        2) warn_msg "Расширенный sysctl-файл изменён извне: $_f. Файл сохранён."; rm -f "$sf"; return 0;;
        3) warn_msg "Расширенный sysctl-файл не принадлежит DNS Manager: $_f. Файл сохранён."; rm -f "$sf"; return 0;;
    esac
    if [ -s "$sf" ]; then
        while IFS='|' read -r _k _old; do
            [ -n "$_k" ] || continue
            _managed="$(sysctl_extended_params | awk -F'=' -v k="$_k" '$1==k{print $2;exit}')"
            [ -n "$_managed" ] || continue
            sysctl_restore_key_if_unchanged "$_k" "$_old" "$_managed"
        done < "$sf"
    fi
    [ -f "$_f" ] && rm -f "$_f" || true
    rm -f "$sf"
    return 0
}
apply_dns_force() {
    [ "${FORCE_DOH:-0}" = 1 ] || return 0
    firewall_lan_zone_require >/dev/null || return 1
    firewall_wan_zone_require >/dev/null || return 1
    if [ ! -s "$FORCE_DNS_BEFORE" ]; then
        {
            printf 'force_dns|%s\n' "$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)"
            printf 'notrack_dns|%s\n' "$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null)"
            printf 'dnsmasq_config_update|%s\n' "$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null)"
        } > "$FORCE_DNS_BEFORE" || return 1
    fi

    uci set https-dns-proxy.config.force_dns=0 || return 1
    uci set https-dns-proxy.config.notrack_dns=0 || return 1
    uci set https-dns-proxy.config.dnsmasq_config_update=- || return 1

    if uci -q get "firewall.$FW_DNS_REDIRECT_SECTION" >/dev/null 2>&1; then
        if firewall_section_owned_redirect "$FW_DNS_REDIRECT_SECTION" "$FIREWALL_LAN_ZONE" 'tcp udp' 53 "$LAN_IP" 53 DNAT; then
            uci -q set "firewall.$FW_DNS_REDIRECT_SECTION.dest=$FIREWALL_LAN_NAME" || return 1
            firewall_owner_add "$FW_DNS_REDIRECT_SECTION" >/dev/null 2>&1 || true
        elif [ "${FORCE_APPLY_SETTINGS:-0}" = 1 ]; then
            uci set "firewall.$FW_DNS_REDIRECT_SECTION=redirect" || return 1
            uci set "firewall.$FW_DNS_REDIRECT_SECTION.name=DNS Manager: перенаправление DNS" || return 1
            uci set "firewall.$FW_DNS_REDIRECT_SECTION.src=$FIREWALL_LAN_NAME" || return 1
            uci set "firewall.$FW_DNS_REDIRECT_SECTION.dest=$FIREWALL_LAN_NAME" || return 1
            uci set "firewall.$FW_DNS_REDIRECT_SECTION.proto=tcp udp" || return 1
            uci set "firewall.$FW_DNS_REDIRECT_SECTION.src_dport=53" || return 1
            uci set "firewall.$FW_DNS_REDIRECT_SECTION.dest_ip=$LAN_IP" || return 1
            uci set "firewall.$FW_DNS_REDIRECT_SECTION.dest_port=53" || return 1
            uci set "firewall.$FW_DNS_REDIRECT_SECTION.target=DNAT" || return 1
            firewall_owner_add "$FW_DNS_REDIRECT_SECTION" || return 1
        else
            return 2
        fi
    elif firewall_find_exact_redirect "$FIREWALL_LAN_ZONE" 'tcp udp' 53 "$LAN_IP" 53 DNAT "$FW_DNS_REDIRECT_SECTION" >/dev/null 2>&1; then
        :
    else
        uci set "firewall.$FW_DNS_REDIRECT_SECTION=redirect" || return 1
        uci set "firewall.$FW_DNS_REDIRECT_SECTION.name=DNS Manager: перенаправление DNS" || return 1
        uci set "firewall.$FW_DNS_REDIRECT_SECTION.src=$FIREWALL_LAN_NAME" || return 1
        uci set "firewall.$FW_DNS_REDIRECT_SECTION.dest=$FIREWALL_LAN_NAME" || return 1
        uci set "firewall.$FW_DNS_REDIRECT_SECTION.proto=tcp udp" || return 1
        uci set "firewall.$FW_DNS_REDIRECT_SECTION.src_dport=53" || return 1
        uci set "firewall.$FW_DNS_REDIRECT_SECTION.dest_ip=$LAN_IP" || return 1
        uci set "firewall.$FW_DNS_REDIRECT_SECTION.dest_port=53" || return 1
        uci set "firewall.$FW_DNS_REDIRECT_SECTION.target=DNAT" || return 1
        firewall_owner_add "$FW_DNS_REDIRECT_SECTION" || return 1
    fi

    if uci -q get "firewall.$FW_DOT_SECTION" >/dev/null 2>&1; then
        if [ "$(uci -q get "firewall.$FW_DOT_SECTION" 2>/dev/null)" = rule ] &&
           firewall_ref_matches_zone "$(uci -q get "firewall.$FW_DOT_SECTION.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" &&
           firewall_ref_matches_zone "$(uci -q get "firewall.$FW_DOT_SECTION.dest" 2>/dev/null)" "$FIREWALL_WAN_ZONE" &&
           [ "$(uci -q get "firewall.$FW_DOT_SECTION.proto" 2>/dev/null)" = 'tcp udp' ] &&
           [ "$(uci -q get "firewall.$FW_DOT_SECTION.dest_port" 2>/dev/null)" = 853 ] &&
           [ "$(uci -q get "firewall.$FW_DOT_SECTION.target" 2>/dev/null)" = REJECT ]; then
            firewall_owner_add "$FW_DOT_SECTION" >/dev/null 2>&1 || true
        elif [ "${FORCE_APPLY_SETTINGS:-0}" = 1 ]; then
            uci set "firewall.$FW_DOT_SECTION=rule" || return 1
            uci set "firewall.$FW_DOT_SECTION.name=DNS Manager: блокировка DoT" || return 1
            uci set "firewall.$FW_DOT_SECTION.src=$FIREWALL_LAN_NAME" || return 1
            uci set "firewall.$FW_DOT_SECTION.dest=$FIREWALL_WAN_NAME" || return 1
            uci set "firewall.$FW_DOT_SECTION.proto=tcp udp" || return 1
            uci set "firewall.$FW_DOT_SECTION.dest_port=853" || return 1
            uci set "firewall.$FW_DOT_SECTION.target=REJECT" || return 1
            firewall_owner_add "$FW_DOT_SECTION" || return 1
        else
            return 2
        fi
    elif firewall_find_exact_rule_signature dot "$FW_DOT_SECTION" >/dev/null 2>&1; then
        :
    else
        uci set "firewall.$FW_DOT_SECTION=rule" || return 1
        uci set "firewall.$FW_DOT_SECTION.name=DNS Manager: блокировка DoT" || return 1
        uci set "firewall.$FW_DOT_SECTION.src=$FIREWALL_LAN_NAME" || return 1
        uci set "firewall.$FW_DOT_SECTION.dest=$FIREWALL_WAN_NAME" || return 1
        uci set "firewall.$FW_DOT_SECTION.proto=tcp udp" || return 1
        uci set "firewall.$FW_DOT_SECTION.dest_port=853" || return 1
        uci set "firewall.$FW_DOT_SECTION.target=REJECT" || return 1
        firewall_owner_add "$FW_DOT_SECTION" || return 1
    fi

    uci commit https-dns-proxy || return 1
    uci commit firewall || return 1
    return 0
}
remove_dns_force() {
    firewall_resolve_zones
    if firewall_section_owned_redirect "$FW_DNS_REDIRECT_SECTION" "$FIREWALL_LAN_ZONE" 'tcp udp' 53 "$LAN_IP" 53 DNAT && firewall_owner_has "$FW_DNS_REDIRECT_SECTION"; then
        uci -q delete "firewall.$FW_DNS_REDIRECT_SECTION"
        firewall_owner_remove "$FW_DNS_REDIRECT_SECTION"
    fi
    if uci -q get "firewall.$FW_DOT_SECTION" >/dev/null 2>&1; then
        if firewall_owner_has "$FW_DOT_SECTION" && firewall_ref_matches_zone "$(uci -q get "firewall.$FW_DOT_SECTION.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" && firewall_ref_matches_zone "$(uci -q get "firewall.$FW_DOT_SECTION.dest" 2>/dev/null)" "$FIREWALL_WAN_ZONE" && [ "$(uci -q get "firewall.$FW_DOT_SECTION.proto" 2>/dev/null)" = 'tcp udp' ] && [ "$(uci -q get "firewall.$FW_DOT_SECTION.dest_port" 2>/dev/null)" = 853 ] && [ "$(uci -q get "firewall.$FW_DOT_SECTION.target" 2>/dev/null)" = REJECT ]; then
            uci -q delete "firewall.$FW_DOT_SECTION"
            firewall_owner_remove "$FW_DOT_SECTION"
        fi
    fi
    if [ -s "$FORCE_DNS_BEFORE" ]; then
        while IFS='|' read -r _k _v; do
            case "$_k" in
                force_dns|notrack_dns|dnsmasq_config_update)
                    case "$_k" in
                        force_dns|notrack_dns) _mgr=0;;
                        dnsmasq_config_update) _mgr=-;;
                    esac
                    _cur="$(uci -q get "https-dns-proxy.config.$_k" 2>/dev/null)"
                    if [ "$_cur" = "$_mgr" ]; then
                        if [ -n "$_v" ]; then uci set "https-dns-proxy.config.$_k=$_v"; else uci -q delete "https-dns-proxy.config.$_k"; fi
                    else
                        warn_msg "https-dns-proxy: $_k изменён извне после применения DNS Manager. Текущее значение сохранено."
                    fi
                    ;;
            esac
        done < "$FORCE_DNS_BEFORE"
        rm -f "$FORCE_DNS_BEFORE"
    fi
    uci commit https-dns-proxy >/dev/null 2>&1 || return 1
    uci commit firewall >/dev/null 2>&1 || return 1
    return 0
}
# ==========================================
apply_bogus() {
clear_screen
printf "${C_RED}=== IP-заглушки / bogus-nxdomain ===${C_NC}\n"
printf "Каталог содержит адреса для проверки. Применяйте только подтверждённые для вашего DNS-источника IP.\n"
n=1
while IFS='|' read -r id typ ip desc conf status; do
case "$id" in ''|\#*) continue;; esac
printf "%2d) %-15s %-8s %s [%s]\n" "$n" "$ip" "$typ" "$desc" "$status"
n=$((n+1))
done < "$BOGUS_CATALOG"
printf "\nНомера через пробел, Enter=отмена: "; safe_read pick
[ -n "$pick" ] || return
conf="/etc/dnsmasq.d/90-dns-manager-bogus.conf"
if [ ! -f "$conf" ]; then
    : > "$conf" || return 1
    record_own "file" "$conf" "created" "bogus"
fi
for n in $pick; do
row="$(grep -v '^#' "$BOGUS_CATALOG" | sed -n "${n}p")"
ip="$(printf '%s' "$row" | cut -d'|' -f3)"; status="$(printf '%s' "$row" | cut -d'|' -f6)"
case "$status" in manual-only|needs-runtime-check) warn_msg "$ip нельзя применять автоматически: статус=$status"; continue;; esac
[ -n "$ip" ] && ! grep -qxF "bogus-nxdomain=$ip" "$conf" 2>/dev/null && printf 'bogus-nxdomain=%s\n' "$ip" >> "$conf"
done
/etc/init.d/dnsmasq restart 2>/dev/null
ok_msg "Выбранные подтверждённые bogus-nxdomain добавлены."
pause
}
apply_ntp_if_needed() {
    [ "$NTP_IP_FALLBACK" = 1 ] || return 0
    apply_ntp_host_ips || return 1
    apply_ntp_ip_fallback || return 1
    return 0
}
url_host() {
    _u="$1"
    _h="${_u#https://}"
    _h="${_h%%/*}"
    case "$_h" in
        *:*) printf '%s' "${_h%%:*}" ;;
        *) printf '%s' "$_h" ;;
    esac
}
url_port() {
    _u="$1"
    _h="${_u#https://}"
    _h="${_h%%/*}"
    case "$_h" in
        *:*)
            _p="${_h##*:}"
            case "$_p" in
                ''|*[!0-9]*) printf '443' ;;
                *) printf '%s' "$_p" ;;
            esac
            ;;
        *) printf '443' ;;
    esac
}
# ==========================================
# ==========================================
verify_doh_endpoint() {
    _url="$(normalize_url "$1")"
    _name="$2"
    _host="$(url_host "$_url")"
    _port="$(url_port "$_url")"
    [ -n "$_host" ] || { err_msg "DNS «$_name»: не удалось определить имя DNS-сервера."; return 1; }
    _ips=""
    if [ "$HAS_DIG" = yes ]; then
        for bs in $(printf '%s' "$BOOTSTRAP_DNS" | tr ',' ' '); do
            _chunk="$(dig +short +time=2 +tries=1 "@$bs" "$_host" A 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/{print}' | head -n 4)"
            if [ -n "$_chunk" ]; then
                _ips="$_chunk"
                break
            fi
        done
    fi
    [ -n "$_ips" ] || _one="$(resolve_host "$_host")"
    [ -n "$_ips" ] || [ -n "$_one" ] || {
        err_msg "DNS «$_name»: не удалось определить адрес $_host через bootstrap DNS."; return 1;
    }
    [ -n "$_ips" ] || _ips="$_one"
    _q="$TMP_DIR/verify-q.$_suffix"
    _b="$TMP_DIR/verify-b.$_suffix"
    _h="$TMP_DIR/verify-h.$_suffix"
    : > "$_b" || return 1
    : > "$_h" || { rm -f "$_b"; return 1; }
    printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$_q" || {
        rm -f "$_q" "$_b" "$_h"
        return 1
    }
    _last_code="000"
    _last_err=""
    _ok=0
    while IFS= read -r _ip; do
        [ -n "$_ip" ] || continue
        : > "$_b"
        : > "$_h"
        _res="$(curl -sS -o "$_b" -D "$_h" -w '%{http_code}|%{errormsg}'          --connect-timeout 3 --max-time 6          --resolve "$_host:$_port:$_ip"          -H 'Content-Type: application/dns-message'          -H 'Accept: application/dns-message'          --data-binary "@$_q" "$_url" 2>/dev/null)"
        _code="${_res%%|*}"
        _err="${_res#*|}"
        [ -n "$_code" ] || _code="000"
        _bytes="$(wc -c < "$_b" 2>/dev/null | tr -d ' ')"
        [ -n "$_bytes" ] || _bytes=0
        _ctype="$(awk -F': *' 'tolower($1)=="content-type"{print tolower($2)}' "$_h" 2>/dev/null | tail -n1 | tr -d '\r')"
        _last_code="$_code"
        _last_err="$_err"
        if [ "$_code" = 200 ] && [ "$_bytes" -ge 12 ] && printf '%s' "$_ctype" | grep -q 'application/dns-message'; then
            _ok=1
            break
        fi
    done <<EOF_VERIFY_IPS
$_ips
EOF_VERIFY_IPS
    rm -f "$_q" "$_b" "$_h"
    [ "$_ok" = 1 ] || {
        _reason="HTTPS $_last_code"
        if [ "$_last_code" = 000 ] && [ -n "$_last_err" ]; then
            _elc="$(printf '%s' "$_last_err" | tr '[:upper:]' '[:lower:]')"
            case "$_elc" in
                *timed*|*timeout*) _reason="тайм-аут" ;;
                *ssl*|*tls*|*certificate*) _reason="ошибка TLS/сертификата" ;;
                *resolve*|*name\ or\ service*) _reason="ошибка DNS" ;;
                *connection\ refused*|*failed\ to\ connect*|*connection\ reset*) _reason="сервер недоступен" ;;
            esac
        fi
        err_msg "DNS «$_name»: корректный ответ DNS-сервера не получен ($_reason)."; return 1
    }
    printf "${C_GREEN}✓ Адрес DNS-сервера подтверждён: %s${C_NC}\n" "$_name"
    return 0
}
verify_applied_doh_config() {
    _expected="$TMP_DIR/expected-doh-map"
    _actual="$TMP_DIR/actual-doh-map"
    : > "$_expected" || return 1
    : > "$_actual" || return 1
    for s in 1 2 3 4 5 6 RU RU_2; do
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
        _ans="$(dig @127.0.0.1 -p "$_lp" "$_domain" A +time=2 +tries=1 +short 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/ {print; exit}')"
        [ -n "$_ans" ] && return 0
        _ans="$(dig @127.0.0.1 -p "$_lp" "$_domain" A +time=2 +tries=1 2>/dev/null | awk '$4=="A" && $NF ~ /^[0-9]+(\.[0-9]+){3}$/ {print $NF; exit}')"
        [ -n "$_ans" ] && return 0
        return 1
    fi
    if command -v nslookup >/dev/null 2>&1; then
        _ans="$(nslookup -port="$_lp" "$_domain" 127.0.0.1 2>/dev/null | awk '/^Address [0-9]+: / {print $NF} /^Address: / {print $2}' | awk '/^[0-9]+(\.[0-9]+){3}$/ {print; exit}')"
        [ -n "$_ans" ] && return 0
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
            printf "  ${C_GREEN}✓${C_NC} Слот %s работает: 127.0.0.1:%s ← %s\n" "$s" "$_p" "$(dns_name "$_id")"
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
            printf "  ${C_GREEN}✓${C_NC} RU работает: 127.0.0.1:%s ← %s\n" "$PORT_RU" "$(dns_name "$SLOT_RU")"
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
    if [ -n "${SLOT_RU_2:-}" ]; then
        [ -n "${PORT_RU_2:-}" ] || { err_msg "RU2: боевой порт не определён."; return 1; }
        if listener_port_exists "$PORT_RU_2" && local_dns_query_ok "$PORT_RU_2" "yandex.ru"; then
            printf "  ${C_GREEN}✓${C_NC} RU2 работает: 127.0.0.1:%s ← %s\n" "$PORT_RU_2" "$(dns_name "$SLOT_RU_2")"
            _checked=$((_checked+1))
        else
            FAILED_SLOT="RU_2"
            FAILED_SLOT_ID="$SLOT_RU_2"
            FAILED_SLOT_PORT="$PORT_RU_2"
            FAILED_SLOT_CAT="regional"
            err_msg "RU2 ($(dns_name "$SLOT_RU_2")): DNS не ответил через 127.0.0.1:$PORT_RU_2."
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
    for _rs in 1 2 3 4 5 6 RU RU_2; do
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
    local _slot _old_id _port _cat _slot_tried _used _current_id _current_name _candidate_name _new_url _rcat _rms _rst _rid _rname _previous_id _previous_name _domain _candidate_ok
    local _old_display _candidate_display
    _slot="$FAILED_SLOT"
    _old_id="$FAILED_SLOT_ID"
    _port="$FAILED_SLOT_PORT"
    _cat="$FAILED_SLOT_CAT"
    [ -n "$_slot" ] || return 1
    ensure_test_results_fresh || return 1
    case "$_slot" in RU|RU_2) _cat="regional" ;; esac
    _slot_tried="$TMP_DIR/repair-tried-$$-$_slot"
    _used="$TMP_DIR/repair-used-$$-$_slot"
    : > "$_slot_tried" || return 1
    : > "$_used" || { rm -f "$_slot_tried"; return 1; }
    [ -n "${REPAIR_BAD_IDS:-}" ] || REPAIR_BAD_IDS="$TMP_DIR/repair-bad-ids-$$"
    [ -f "$REPAIR_BAD_IDS" ] || : > "$REPAIR_BAD_IDS"
    for _s in 1 2 3 4 5 6 RU RU_2; do
        eval "_u_id=\${SLOT_${_s}:-}"
        [ -n "$_u_id" ] || continue
        _new_url="$(normalize_url "$(dns_url "$_u_id")")"
        [ -n "$_new_url" ] && printf '%s\n' "$_new_url" >> "$_used"
    done
    printf '%s\n' "$_old_id" >> "$_slot_tried"
    grep -qxF "$_old_id" "$REPAIR_BAD_IDS" 2>/dev/null || printf '%s\n' "$_old_id" >> "$REPAIR_BAD_IDS"
    _previous_id="$_old_id"
    _old_display="$(dns_name "$_old_id")"
    [ -n "$_old_display" ] || _old_display="выбранный DNS"
    for _passcat in bypass clean; do
        if [ "$DNS_SELECTION_MODE" != quick ]; then
            [ "$_passcat" = "bypass" ] || break
            _passcat="$_cat"
        fi
        while IFS='|' read -r _rid _rcat _rname _rms _rst; do
            [ -n "$_rid" ] || continue
            [ "$_rst" = OK ] || continue
            case "$_rms" in ''|*[!0-9]*) continue ;; esac
            [ "$_rid" = "$_old_id" ] && continue
            grep -qxF "$_rid" "$_slot_tried" 2>/dev/null && continue
            grep -qxF "$_rid" "$REPAIR_BAD_IDS" 2>/dev/null && continue
            if [ "$DNS_SELECTION_MODE" = quick ]; then
                [ "$_rcat" = "$_passcat" ] || continue
            else
                [ "$_rcat" = "$_cat" ] || continue
            fi
            _new_url="$(normalize_url "$(dns_url "$_rid")")"
            [ -n "$_new_url" ] || continue
            grep -qxF "$_new_url" "$_used" 2>/dev/null && continue
            _current_name="$_old_display"
            _candidate_name="$(dns_name "$_rid")"
            [ -n "$_candidate_name" ] || _candidate_name="новый DNS"
            printf "  ${C_YELLOW}↻ Слот %s: %s не отвечает. Проверяю замену %s.${C_NC}\n" "$_slot" "$_current_name" "$_candidate_name"
            eval "SLOT_${_slot}=\"$_rid\""
            if [ "$DNS_SELECTION_MODE" = quick ]; then
                eval "SLOT_${_slot}_CAT=\"bypass\""
            else
                eval "SLOT_${_slot}_CAT=\"$_rcat\""
            fi
            eval "PORT_${_slot}=\"$_port\""
            if ! rebuild_selected_hdp_sections; then
                eval "SLOT_${_slot}=\"$_previous_id\""
                if [ "$DNS_SELECTION_MODE" = quick ]; then
                    eval "SLOT_${_slot}_CAT=\"bypass\""
                else
                    eval "SLOT_${_slot}_CAT=\"$_cat\""
                fi
                printf '%s\n' "$_rid" >> "$_slot_tried"
                grep -qxF "$_rid" "$REPAIR_BAD_IDS" 2>/dev/null || printf '%s\n' "$_rid" >> "$REPAIR_BAD_IDS"
                continue
            fi
            /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
            sleep 4
            _domain="example.com"
            case "$_slot" in RU|RU_2) _domain="yandex.ru" ;; esac
            _candidate_ok=0
            for _try in 1 2 3; do
                if listener_port_exists "$_port" && local_dns_query_ok "$_port" "$_domain"; then
                    _candidate_ok=1
                    break
                fi
                [ "$_try" -lt 3 ] && sleep 1
            done
            if [ "$_candidate_ok" = 1 ]; then
                printf "  ${C_GREEN}✓ Слот %s: %s подтверждён на 127.0.0.1:%s.${C_NC}\n" "$_slot" "$_candidate_name" "$_port"
                rm -f "$_slot_tried" "$_used" 2>/dev/null
                return 0
            fi
            printf "  ${C_RED}✗ Слот %s: %s также не ответил через 127.0.0.1:%s. Больше его не пробую.${C_NC}\n" "$_slot" "$_candidate_name" "$_port"
            printf '%s\n' "$_rid" >> "$_slot_tried"
            grep -qxF "$_rid" "$REPAIR_BAD_IDS" 2>/dev/null || printf '%s\n' "$_rid" >> "$REPAIR_BAD_IDS"
            _previous_id="$_rid"
            _old_display="$_candidate_name"
        done <<EOF_REPAIR_PASS
$(awk -F'|' -v c="$_passcat" '$1!="" && NF>=5 && $2==c && $5=="OK" && $4 ~ /^[0-9]+$/ {print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n)
EOF_REPAIR_PASS
        [ "$DNS_SELECTION_MODE" = quick ] || break
    done
    rm -f "$_slot_tried" "$_used" 2>/dev/null
    warn_msg "Для слота $_slot не найден другой DNS, который прошёл общую проверку и заработал через локальный порт."
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
        printf "  ${C_CYAN}Проверка не пройдена. Подбираю другую замену из успешных результатов общего теста (попытка $_attempt/$_max).${C_NC}\n"
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
    if [ -n "${SLOT_RU:-}" ] || [ -n "${SLOT_RU_2:-}" ]; then
        [ "$(check_module_state tld 2>/dev/null)" = 1 ] || {
            err_msg "Маршрут .ru/.su/.рф после применения не соответствует выбранному DNS."; return 1;
        }
    fi
    if [ "$CORE_ONLY" != 1 ]; then
        if [ "${FORCE_DOH:-0}" = 1 ]; then
            [ "$(check_module_state force 2>/dev/null)" = 1 ] || { err_msg "Принудительный DNS после применения не подтверждён."; return 1; }
        fi
        if [ "${BLOCK_QUIC:-0}" = 1 ]; then
            [ "$(check_module_state quic 2>/dev/null)" = 1 ] || { err_msg "Блокировка QUIC после применения не подтверждена."; return 1; }
        fi
        if [ "${MTU_FIX:-0}" = 1 ]; then
            [ "$(check_module_state mtu 2>/dev/null)" = 1 ] || { err_msg "Исправление MTU/MSS после применения не подтверждено."; return 1; }
        fi
        if [ "${SYSCTL_TUNING:-0}" = 1 ]; then
            [ "$(check_module_state sysctl 2>/dev/null)" = 1 ] || { err_msg "Настройка сети (sysctl) после применения не подтверждена."; return 1; }
        fi
        if [ "${NTP_CLIENTS:-0}" = 1 ]; then
            [ "$(check_module_state ntp_clients 2>/dev/null)" = 1 ] || { err_msg "NTP для клиентов после применения не подтверждён."; return 1; }
        fi
        if [ "${DNSMASQ_PERF:-0}" = 1 ]; then
            [ "$(check_module_state dnsmasq_perf 2>/dev/null)" = 1 ] || { err_msg "Настройка DNS-кэша после применения не подтверждена."; return 1; }
        fi
        if [ "${CLIENT_FIXES:-0}" = 1 ]; then
            [ "$(check_module_state client_fixes 2>/dev/null)" = 1 ] || { err_msg "Клиентские DNS-фиксы после применения не подтверждены."; return 1; }
        fi
        if [ "${SYSCTL_EXTENDED:-0}" = 1 ]; then
            [ "$(check_module_state sysctl_ext 2>/dev/null)" = 1 ] || { err_msg "Расширенная настройка сети после применения не подтверждена."; return 1; }
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
for f in "$CONFIG_FILE" "$OWNERSHIP" /etc/config/dhcp /etc/config/https-dns-proxy /etc/config/firewall /etc/config/system /etc/sysctl.d/90-dns-manager.conf /etc/sysctl.d/91-dns-manager-extended.conf /etc/dnsmasq.d/90-dns-manager-bogus.conf /etc/dnsmasq.d/91-dns-manager-client-fixes.conf; do
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
tx_restore_on_failure() {
[ "$TX_ACTIVE" = 1 ] || return 0
warn_msg "Применение не прошло проверку. Выполняю автоматический откат этой транзакции."
# Cron is shared infrastructure. Never restore the whole crontab on rollback;
# remove only a DNS Manager-owned entry and preserve everything else.
watchdog_cron_remove_owned_block >/dev/null 2>&1 || true
if [ -f "$TX_DIR/manifest" ]; then
while IFS='|' read -r f key existed; do
[ -n "$f" ] || continue
cur="$(file_hash "$f")"
before="$(cat "$TX_DIR/$key.before" 2>/dev/null)"
after="$(cat "$TX_DIR/$key.after" 2>/dev/null)"
if [ -n "$after" ] && [ "$cur" != "$after" ]; then
warn_msg "Не откатываю $f: обнаружено изменение после применения. Чужие изменения сохранены. Проверьте конфигурацию вручную."
continue
fi
if [ "$existed" = 1 ]; then
if [ -f "$TX_DIR/files/$key" ]; then
cp -p "$TX_DIR/files/$key" "$f" 2>/dev/null || warn_msg "Не удалось восстановить $f"
fi
else
rm -f "$f" 2>/dev/null
fi
done < "$TX_DIR/manifest"
fi
/etc/init.d/https-dns-proxy restart 2>/dev/null || true
/etc/init.d/dnsmasq restart 2>/dev/null || true
reload_fw >/dev/null 2>&1 || true
TX_ACTIVE=0
log_tx "ROLLBACK" "transaction" "RESTORE" "OK" "dir=$TX_DIR;guarded=yes"
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
HYBRID_STAGE_MIN="${HYBRID_STAGE_MIN:-1}"
HYBRID_STAGE_FIRST_PORT=5153
HYBRID_STAGE_LAST_PORT=5199
STAGE_USED=""
STAGE_PIDS=""
stage_port_used() {
_p="$1"; for _x in $STAGE_USED; do [ "$_x" = "$_p" ] && return 0; done; return 1
}
stage_free_port() {
FREE_STAGE_PORT=""; _p="$HYBRID_STAGE_FIRST_PORT"
while [ "$_p" -le "$HYBRID_STAGE_LAST_PORT" ]; do
    stage_port_used "$_p" && { _p=$((_p+1)); continue; }
    if listener_port_exists "$_p"; then
        _p=$((_p+1)); continue
    fi
    STAGE_USED="$STAGE_USED $_p"
    FREE_STAGE_PORT="$_p"
    return 0
done
return 1
}
stage_cleanup() {
    [ -n "${STAGE_PIDS:-}" ] || return 0
    for _pid in $STAGE_PIDS; do
        [ -n "$_pid" ] || continue
        kill "$_pid" 2>/dev/null || true
    done
    sleep 1
    for _pid in $STAGE_PIDS; do
        [ -n "$_pid" ] || continue
        kill -9 "$_pid" 2>/dev/null || true
    done
    STAGE_PIDS=""
}
stage_bootstrap_for_ipv4() {
    printf '%s\n' "$BOOTSTRAP_DNS_ALL"
}
stage_start_one() {
    _slot="$1"; _id="$2"; _url="$(normalize_url "$(dns_url "$_id")")"; _name="$(dns_name "$_id")"
    [ -n "$_url" ] || return 1
    _port="$(hybrid_desired_port "$_slot")"
    [ -n "$_port" ] || return 1
    if stage_port_used "$_port" || listener_port_exists "$_port"; then
        return 1
    fi
    STAGE_USED="$STAGE_USED $_port"
    _bin="$(command -v https-dns-proxy 2>/dev/null)"
    [ -n "$_bin" ] || return 1
    _log="$TMP_DIR/stage-${_slot}-${_port}.log"
    _b="$(stage_bootstrap_for_ipv4)"
    _family_args=""
    [ "${IPV6_ROUTE:-no}" != "yes" ] && _family_args="-4"
    _host="$(url_host "$_url")"
    _resolved_ip="$(resolve_host_fallback "$_host" 2>/dev/null || true)"
    [ -n "$_resolved_ip" ] || _resolved_ip="$(resolve_host "$_host" 2>/dev/null || true)"
    if [ "${HYBRID_PREFLIGHT_SILENT:-0}" != 1 ]; then
        printf "  ${C_CYAN}◇ Проверка DNS: %s → 127.0.0.1:%s${C_NC}\n" "$_name" "$_port"
    fi
    if [ -n "$_resolved_ip" ]; then
        "$_bin" -a 127.0.0.1 -p "$_port" -b "$_b" $_family_args -R "$_resolved_ip" -r "$_url" -u nobody -g nogroup >"$_log" 2>&1 &
    else
        "$_bin" -a 127.0.0.1 -p "$_port" -b "$_b" $_family_args -r "$_url" -u nobody -g nogroup >"$_log" 2>&1 &
    fi
    _pid=$!
    STAGE_PIDS="$STAGE_PIDS $_pid"
    STAGE_LAST_PID="$_pid"
    STAGE_LAST_PORT="$_port"
    STAGE_LAST_LOG="$_log"
    STAGE_LAST_URL="$_url"
    return 0
}
stage_process_alive() {
    _pid="$1"
    [ -n "$_pid" ] || return 1
    kill -0 "$_pid" 2>/dev/null || return 1
    return 0
}
stage_local_ok() {
    _p="$1"
    _domain="${2:-example.com}"
    _wait=0
    while [ "$_wait" -lt 5 ]; do
        if listener_port_exists "$_p" && local_dns_query_ok "$_p" "$_domain"; then
            return 0
        fi
        sleep 1
        _wait=$((_wait+1))
    done
    _log="${STAGE_LAST_LOG:-}"
    if [ -s "$_log" ] && grep -Eiq 'fatal|panic|bind failed|address already in use|invalid option|unknown option' "$_log" 2>/dev/null; then
        return 1
    fi
    listener_port_exists "$_p" && local_dns_query_ok "$_p" "$_domain"
}
stage_try_candidate() {
    _slot="$1"
    _id="$2"
    _domain="${3:-example.com}"
    _port="$(hybrid_desired_port "$_slot")"
    [ -n "$_port" ] || return 1
    STAGE_USED=""
    STAGE_LAST_PID=""
    STAGE_LAST_PORT=""
    STAGE_LAST_LOG=""
    STAGE_LAST_URL=""
    stage_start_one "$_slot" "$_id" || return 1
    if stage_local_ok "$_port" "$_domain"; then
        stage_stop_last
        return 0
    fi
    stage_stop_last
    return 1
}
stage_stop_last() {
    _old="$STAGE_LAST_PID"
    _old_port="$STAGE_LAST_PORT"
    [ -n "$_old" ] && kill "$_old" 2>/dev/null || true
    sleep 0.3
    [ -n "$_old" ] && kill -9 "$_old" 2>/dev/null || true
    if [ -n "$_old_port" ]; then
        _w=0
        while listener_port_exists "$_old_port" && [ "$_w" -lt 6 ]; do
            sleep 0.3
            _w=$((_w+1))
        done
    fi
    _new=""
    for _pid in $STAGE_PIDS; do
        [ "$_pid" = "$_old" ] || _new="$_new $_pid"
    done
    STAGE_PIDS="$_new"
    if [ -n "$_old_port" ]; then
        _stage_new_used=""
        for _sp in $STAGE_USED; do
            [ "$_sp" = "$_old_port" ] || _stage_new_used="$_stage_new_used $_sp"
        done
        STAGE_USED="$_stage_new_used"
    fi
    STAGE_LAST_PID=""; STAGE_LAST_PORT=""; STAGE_LAST_LOG=""; STAGE_LAST_URL=""
}
stage_drop_by_url() {
    return 0
}
candidate_already_used() {
_id="$1"
for _slot in 1 2 3 4 5 6 RU RU_2; do eval "_v=\${SLOT_$_slot:-}"; [ "$_v" = "$_id" ] && return 0; done
return 1
}
next_hybrid_candidate() {
_wantcat="$1"; _fallback="$2"; _skip="$3"; _triedfile="$4"
_candfile="$TMP_DIR/next-candidates-$$"
awk -F'|' -v c="$_wantcat" -v f="$_fallback" '$5=="OK" && ($2==c || (f=="yes" && $2=="clean")){print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n > "$_candfile"
while IFS='|' read -r _id _cat _name _ms _st; do
    [ -n "$_id" ] || continue
    [ "$_id" = "$_skip" ] && continue
    [ -n "$_triedfile" ] && grep -qxF "$_id" "$_triedfile" 2>/dev/null && continue
    printf '%s\n' "$_id"
    rm -f "$_candfile" 2>/dev/null
    return 0
done < "$_candfile"
rm -f "$_candfile" 2>/dev/null
return 1
}
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
        [ "$_fill" -ge 6 ] && break
    done < "$_pool.bypass"
    _bypass_count="$_fill"
    if [ "$_fill" -lt 6 ]; then
        rm -f "$_pool" "$_pool.bypass" "$_tried" "$_selected_urls" 2>/dev/null
        err_msg "В категории «Обход блокировок» подтверждено только $_fill DNS из 6. Набор не применён."
        return 1
    fi
    for _slot in 1 2 3 4 5 6; do
        IFS='|' read -r _id _cat _name _ms _st < "$_pool"
        [ -n "$_id" ] || { rm -f "$_pool" "$_pool.bypass" "$_pool.clean" "$_tried" "$_selected_urls" 2>/dev/null; return 1; }
        sed '1d' "$_pool" > "$_pool.tmp" && mv "$_pool.tmp" "$_pool"
        eval "SLOT_$_slot=\"$_id\""
        if [ "$_cat" = bypass ]; then
            eval "QUICK_PREF_$_slot=\"$_id\""
        else
            eval "QUICK_PREF_$_slot=\"\""
        fi
        eval "SLOT_${_slot}_CAT=\"bypass\""
        _port="$(hybrid_desired_port "$_slot")"
        printf "  ${C_GREEN}✓ Слот %s: %s → 127.0.0.1:%s${C_NC}\n" "$_slot" "$(dns_name "$_id")" "$_port"
        _success=$((_success+1))
    done
    SLOT_RU=""
    SLOT_RU_CAT="regional"
    _yandex_ok="$(awk -F'|' 'NF>=5 && $1=="yandex_ru" && $2=="regional" && $5=="OK" && $4 ~ /^[0-9]+$/ {print "yes";exit}' "$TEST_RESULTS" 2>/dev/null)"
    if [ "$_yandex_ok" = yes ]; then
        SLOT_RU="yandex_ru"
        printf "  ${C_GREEN}✓ RU: Yandex RU → 127.0.0.1:%s${C_NC}\n" "$(hybrid_desired_port RU)"
        _success=$((_success+1))
    else
        rm -f "$_pool" "$_pool.bypass" "$_pool.clean" "$_tried" "$_selected_urls" 2>/dev/null
        err_msg "Yandex RU не прошёл последнюю полную проверку. Настройка не применена."
        return 1
    fi
    SLOT_RU_2=""
    SLOT_RU_2_CAT="regional"
    PORT_1="$HYBRID_PORT_1"; PORT_2="$HYBRID_PORT_2"; PORT_3="$HYBRID_PORT_3"
    PORT_4="$HYBRID_PORT_4"; PORT_5="$HYBRID_PORT_5"; PORT_6="$HYBRID_PORT_6"
    PORT_RU="$HYBRID_PORT_RU"; PORT_RU_2=""
    DNS_SELECTION_MODE="quick"
    DNS_SELECTION_CATEGORY="bypass"
    rm -f "$_pool" "$_pool.bypass" "$_pool.clean" "$_tried" "$_selected_urls" 2>/dev/null
    return 0
}
reset_hybrid_runtime_ports() {
    [ "$DNS_PROFILE" = hybrid ] || return 0
    for _s in 1 2 3 4 5 6; do
        eval "_v=\${SLOT_$_s:-}"
        if [ -n "$_v" ]; then
            eval "PORT_$_s=\$(hybrid_desired_port "$_s")"
        else
            eval "PORT_$_s=''"
        fi
    done
    if [ -n "${SLOT_RU:-}" ]; then
        PORT_RU="$(hybrid_desired_port RU)"
    else
        PORT_RU=""
    fi
    if [ -n "${SLOT_RU_2:-}" ]; then
        PORT_RU_2="$(hybrid_desired_port RU_2)"
    else
        PORT_RU_2=""
    fi
    return 0
}
_apply_settings_impl() {
    clear_screen
    run_discovery
    if [ "$CORE_ONLY" != 1 ] && { [ "${BLOCK_QUIC:-0}" = 1 ] || [ "${MTU_FIX:-0}" = 1 ] || [ "${FORCE_DOH:-0}" = 1 ] || [ "${NTP_CLIENTS:-0}" = 1 ]; }; then
        firewall_backend_require || return 1
    fi
    if [ "${HYBRID_FORCE_RESELECT:-0}" = 1 ] && [ "$DNS_PROFILE" = hybrid ]; then
        SLOT_1=""; SLOT_2=""; SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""
        SLOT_RU=""; SLOT_RU_2=""
        QUICK_PREF_1=""; QUICK_PREF_2=""; QUICK_PREF_3=""; QUICK_PREF_4=""; QUICK_PREF_5=""; QUICK_PREF_6=""
        SLOT_1_CAT="bypass"; SLOT_2_CAT="bypass"; SLOT_3_CAT="bypass"
        SLOT_4_CAT="bypass"; SLOT_5_CAT="bypass"; SLOT_6_CAT="bypass"
        SLOT_RU_CAT="regional"; SLOT_RU_2_CAT="regional"
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
    printf "${C_TITLE}===  ПОДГОТОВКА И ПЛАН ПРИМЕНЕНИЯ ===${C_NC}\n"
    printf "${C_WHITE}Будет настроено:${C_NC}\n"
    if [ "$DNS_PROFILE" = hybrid ]; then
        printf "  ${C_YELLOW}Гибридный DNS — 6 серверов + Яндекс RU${C_NC}\n"
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
    [ "$NTP_IP_FALLBACK" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Время по IP\n" || printf "  ${C_YELLOW}—${C_NC} NTP не изменяется\n"
    if [ "$CORE_ONLY" != 1 ]; then
        printf "\n${C_WHITE}Дополнительные настройки:${C_NC}\n"
        [ "$BLOCK_QUIC" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Блокировка быстрых соединений UDP\n" || printf "  ${C_YELLOW}—${C_NC} QUIC не изменяется\n"
        [ "$MTU_FIX" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Исправление сетевых параметров\n" || printf "  ${C_YELLOW}—${C_NC} MTU не изменяется\n"
        [ "$SYSCTL_TUNING" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Настройка сети\n" || printf "  ${C_YELLOW}—${C_NC} sysctl не изменяется\n"
        [ "${FORCE_DOH:-0}" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Принудительный локальный DNS\n" || printf "  ${C_YELLOW}—${C_NC} Принудительный локальный DNS не изменяется\n"
        [ "$NTP_CLIENTS" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Время для устройств сети (DHCP 42 + DNAT 123)\n" || printf "  ${C_YELLOW}—${C_NC} NTP клиентов не изменяется\n"
        [ "$DNSMASQ_PERF" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Настройка DNS-кэша\n" || printf "  ${C_YELLOW}—${C_NC} Настройка DNS-кэша не изменяется\n"
        [ "$CLIENT_FIXES" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Клиентские DNS-фиксы\n" || printf "  ${C_YELLOW}—${C_NC} Клиентские фиксы не изменяются\n"
        [ "$SYSCTL_EXTENDED" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Расширенная настройка сети\n" || printf "  ${C_YELLOW}—${C_NC} Расширенный sysctl не изменяется\n"
        [ "$WATCHDOG_ENABLED" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Автоматическая проверка DNS: каждые %s мин\n" "$WATCHDOG_INTERVAL" || printf "  ${C_YELLOW}—${C_NC} Автоматическая проверка DNS не изменяется\n"
    fi
    printf "\n${C_WHITE}Текущее состояние до применения:${C_NC}\n"
    printf "  dnsmasq: %b\n" "$(state_word "$DNSMASQ_RUN")"
    printf "  DNS-серверов: %s (по текущей схеме %s / вне схемы %s)\n" "$DOH_TOTAL" "$DOH_MATCH" "$DOH_OTHER"
    if [ "$DOH_TOTAL" -gt 0 ]; then
        printf "  ${C_YELLOW}↻ После подтверждения ВСЕ существующие DNS-секции будут заменены выбранным набором DNS Manager.${C_NC}\n"
    fi
    printf "  ${C_CYAN}${C_NC}\n"
    validate_selected_slots || return 1
    confirm_action "Применить показанную выше конфигурацию?" || return
    printf "\n${C_CYAN}Начинаю применение. Это может занять немного времени...${C_NC}\n"
    TX_ID="$(date +%Y%m%d-%H%M%S)-$$"
    TX_RESERVED_PORTS=""
    baseline_capture_once || { err_msg "Не удалось сохранить исходную копию. Настройки не изменены."; return 1; }
    tx_snapshot_start || { err_msg "Не удалось сохранить копию настроек. Настройки не изменены."; return 1; }
    : > "$OWNERSHIP" || { err_msg "Не удалось подготовить снимок ownership для текущего применения."; tx_restore_on_failure; return 1; }
    log_tx "PLAN" "all" "APPLY" "START" "version=$VERSION"
    if [ "$NTP_IP_FALLBACK" = 1 ]; then
        apply_ntp_host_ips || { err_msg "Не удалось подготовить серверы времени."; tx_restore_on_failure; return 1; }
    fi
    if [ "$DNS_PROFILE" = hybrid ] && [ "${HYBRID_STAGE_SKIP:-0}" != 1 ]; then
        validate_selected_slots || { err_msg "Выбранный набор DNS больше не соответствует последней полной проверке."; tx_restore_on_failure; return 1; }
        /etc/init.d/https-dns-proxy stop >/dev/null 2>&1 || true
        sleep 1
    elif [ "$DOH_TOTAL" -gt 0 ]; then
        /etc/init.d/https-dns-proxy stop >/dev/null 2>&1 || true
        sleep 1
    fi
    configure_hdp_manager_control || {
        err_msg "Не удалось подготовить настройки DNS."
        tx_restore_on_failure
        return 1
    }
    disc_listeners
    disc_dns
    clear_all_doh_for_apply || {
        err_msg "Не удалось очистить старые DNS-серверы перед настройкой."
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
    ensure_doh_slot RU_2 "${SLOT_RU_2:-}" || {
        err_msg "Не удалось настроить резервный DNS для доменов .ru/.su/.рф."
        tx_restore_on_failure
        return 1
    }
    plan_dup="$(for s in 1 2 3 4 5 6 RU RU_2; do eval "p=\${PORT_$s:-}"; [ -n "$p" ] && printf '%s\n' "$p"; done | sort | uniq -d | head -n1)"
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
    reconcile_dnsmasq || { err_msg "Не удалось настроить dnsmasq."; tx_restore_on_failure; return 1; }
    ensure_dnsmasq_balancer || { err_msg "Не удалось включить одновременный опрос DNS."; tx_restore_on_failure; return 1; }
    if [ "$NTP_IP_FALLBACK" = 1 ]; then
        apply_ntp_ip_fallback || { err_msg "Не удалось настроить NTP по IP."; tx_restore_on_failure; return 1; }
    fi
    if [ "$CORE_ONLY" != 1 ] && [ "${FORCE_DOH:-0}" = 1 ]; then
        apply_dns_force || { err_msg "Не удалось применить принудительный DNS."; tx_restore_on_failure; return 1; }
    fi
    if [ "$CORE_ONLY" != 1 ] && [ "$BLOCK_QUIC" = 1 ]; then
        apply_quic || { err_msg "Не удалось применить блокировку QUIC."; tx_restore_on_failure; return 1; }
    fi
    if [ "$CORE_ONLY" != 1 ] && [ "$MTU_FIX" = 1 ]; then
        apply_mtu_toggle || {
            err_msg "Не удалось включить исправление MTU/MSS."
            tx_restore_on_failure
            return 1
        }
    fi
    if [ "$CORE_ONLY" != 1 ] && { [ "$SYSCTL_TUNING" = 1 ] || [ "$SYSCTL_EXTENDED" = 1 ]; }; then
        apply_sysctl_bundle "$SYSCTL_TUNING" "$SYSCTL_EXTENDED" || { err_msg "Не удалось применить общий пакет TCP/Conntrack sysctl."; tx_restore_on_failure; return 1; }
    fi
    if [ "$CORE_ONLY" != 1 ] && [ "$NTP_CLIENTS" = 1 ]; then
        apply_ntp_clients || { err_msg "Не удалось настроить NTP для клиентов."; tx_restore_on_failure; return 1; }
    fi
    if [ "$CORE_ONLY" != 1 ] && [ "$DNSMASQ_PERF" = 1 ]; then
        apply_dnsmasq_perf || { err_msg "Не удалось настроить производительность dnsmasq."; tx_restore_on_failure; return 1; }
    fi
    if [ "$CORE_ONLY" != 1 ] && [ "$CLIENT_FIXES" = 1 ]; then
        apply_client_fixes || { err_msg "Не удалось применить клиентские DNS-фиксы."; tx_restore_on_failure; return 1; }
    fi
    WATCHDOG_ENABLED="${WATCHDOG_ENABLED:-1}"
    apply_watchdog || { err_msg "Не удалось настроить cron Автопроверка."; tx_restore_on_failure; return 1; }
    /etc/init.d/https-dns-proxy restart 2>/dev/null || true
    /etc/init.d/dnsmasq restart 2>/dev/null || true
    sleep 2
    ensure_dnsmasq_balancer || { err_msg "Одновременный опрос DNS не включился после запуска. Изменения откатываются."; tx_restore_on_failure; return 1; }
    reload_fw || { err_msg "Не удалось применить настройки firewall."; tx_restore_on_failure; return 1; }
    prepare_dns_path || { err_msg "Не удалось подготовить DNS для устройств сети."; tx_restore_on_failure; return 1; }
    run_discovery
    tx_snapshot_after_apply
    if verify_after_apply_with_repair; then
        baseline_mark_applied || warn_msg "Не удалось обновить контрольный снимок."
        tx_commit
        save_config
        printf "\n${C_WHITE}Фактическая применённая схема:${C_NC}\n"
        for _s in 1 2 3 4 5 6; do
            eval "_v=\${SLOT_$_s:-}"
            eval "_p=\${PORT_$_s:-}"
            [ -n "$_v" ] && printf "  ${C_GREEN}✓${C_NC} Слот %s: 127.0.0.1:%s ← %s\n" "$_s" "$_p" "$(dns_name "$_v")"
        done
        [ -n "${SLOT_RU:-}" ] && printf "  ${C_GREEN}✓${C_NC} RU: 127.0.0.1:%s ← %s (.ru/.su/.рф)\n" "$PORT_RU" "$(dns_name "$SLOT_RU")"
        [ -n "${SLOT_RU_2:-}" ] && printf "  ${C_GREEN}✓${C_NC} RU2: 127.0.0.1:%s ← %s\n" "$PORT_RU_2" "$(dns_name "$SLOT_RU_2")"
        ok_msg "Готово. Выбранная схема реально развернута и проверена."
        log_tx "VERIFY" "all" "VERIFY" "OK" "dnsmasq=$DNSMASQ_RUN,doh=$DOH_TOTAL"
    else
        log_tx "VERIFY" "all" "VERIFY" "FAIL" "dnsmasq=$DNSMASQ_RUN,doh=$DOH_TOTAL"
        tx_restore_on_failure
        err_msg "Конфигурация не прошла локальную проверку после запуска. Изменения этой транзакции откатаны, где это безопасно возможно."
    fi
    pause
}
firewall_backend_require() {
    case "$SYS_FW" in
        fw4|fw3) firewall_resolve_zones; return 0 ;;
    esac
    err_msg "Не удалось однозначно определить активный firewall backend (fw4/fw3). Firewall-зависимые изменения не применяются."
    return 1
}
apply_settings() {
    apply_wait_message "Применяю выбранную конфигурацию DNS и дополнительные настройки"
    install_missing_dependencies || return 1
    acquire_mutation_lock || return 1
    _rc=0
    _apply_settings_impl "$@" || _rc=$?
    release_mutation_lock
    return "$_rc"
}

restore_hdp_control_from_baseline() {
    _bf="$BASELINE_DIR/files/etc_config_https-dns-proxy"
    [ -f "$_bf" ] || return 0
    for _opt in dnsmasq_config_update force_dns notrack_dns; do
        _v="$(awk -v o="$_opt" '
            /^config[[:space:]]+main([[:space:]]|$)/ { in_main=1; next }
            /^config[[:space:]]/ { in_main=0 }
            in_main && $1=="option" && $2==o { v=$3; gsub(/^'"'"'|'"'"'$/, "", v); print v; exit }
        ' "$_bf" 2>/dev/null)"
        if [ -n "$_v" ]; then
            uci set "https-dns-proxy.config.$_opt=$_v" 2>/dev/null || true
        else
            uci -q delete "https-dns-proxy.config.$_opt" 2>/dev/null || true
        fi
    done
    uci commit https-dns-proxy 2>/dev/null || true
}
_rollback_ours_impl() {
clear_screen
WEB_ACCESS_ENABLED=0
web_access_luci_remove
web_access_remove_config
web_access_remove_firewall
watchdog_cron_remove_owned_block >/dev/null 2>&1 || true
printf "${C_YELLOW}=== 🔄 Удаление изменений DNS Manager ===${C_NC}\n"
if baseline_restore_if_safe; then
    WEB_ACCESS_ENABLED=0
    web_access_luci_remove
    web_access_remove_config
    web_access_remove_firewall
    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
    reload_fw >/dev/null 2>&1 || true
    rm -f "$BASELINE_LAST" 2>/dev/null
    firewall_ownership_sync >/dev/null 2>&1 || true
    ok_msg "Исходное состояние до первого захвата DNS Manager восстановлено. Исходная копия сохранён для аудита и повторного применения."
    pause
    return 0
fi
while uci -q get "https-dns-proxy.@https-dns-proxy[0]" >/dev/null 2>&1; do
uci -q delete "https-dns-proxy.@https-dns-proxy[0]" || break
done
uci commit https-dns-proxy 2>/dev/null
restore_hdp_control_from_baseline
sec="$(get_dnsmasq_section)"
# DNS Manager owns the active upstream-DNS zone. In legacy fallback mode
# restore the captured pre-manager dnsmasq values when available; otherwise clear
# the manager's canonical upstream list so a fresh apply starts cleanly.
if [ -s "$PREV_DNSMASQ" ]; then
    _oldsec="$(sed -n 's/^SECTION=//p' "$PREV_DNSMASQ" 2>/dev/null | head -n1)"
    [ -n "$_oldsec" ] && sec="$_oldsec"
    while uci -q delete "dhcp.$sec.server" >/dev/null 2>&1; do :; done
    _old_servers="$(sed -n '/^SERVER$/,/^ALLSERVERS=/p' "$PREV_DNSMASQ" 2>/dev/null | sed '1d;/^ALLSERVERS=/d')"
    for _v in $_old_servers; do uci add_list "dhcp.$sec.server=$_v" 2>/dev/null || true; done
    _as="$(sed -n 's/^ALLSERVERS=//p' "$PREV_DNSMASQ" 2>/dev/null | head -n1)"
    _so="$(sed -n 's/^STRICTORDER=//p' "$PREV_DNSMASQ" 2>/dev/null | head -n1)"
    _nr="$(sed -n 's/^NORESOLV=//p' "$PREV_DNSMASQ" 2>/dev/null | head -n1)"
    [ -n "$_as" ] && uci set "dhcp.$sec.allservers=$_as" || uci -q delete "dhcp.$sec.allservers"
    [ -n "$_so" ] && uci set "dhcp.$sec.strictorder=$_so" || uci -q delete "dhcp.$sec.strictorder"
    [ -n "$_nr" ] && uci set "dhcp.$sec.noresolv=$_nr" || uci -q delete "dhcp.$sec.noresolv"
    uci commit dhcp 2>/dev/null || true
    rm -f "$PREV_DNSMASQ" 2>/dev/null
else
    while uci -q delete "dhcp.$sec.server" >/dev/null 2>&1; do :; done
    uci commit dhcp 2>/dev/null || true
fi
quic_remove_managed_rules >/dev/null 2>&1 || true
uci commit firewall 2>/dev/null
remove_ntp_clients >/dev/null 2>&1 || true
remove_client_fixes >/dev/null 2>&1 || true
remove_dnsmasq_perf >/dev/null 2>&1 || true
remove_sysctl_extended >/dev/null 2>&1 || true
for _sf in /etc/sysctl.d/90-dns-manager.conf; do
    [ -f "$_sf" ] || continue
    sysctl_base_file_owned "$_sf" || continue
    for kv in net.ipv4.tcp_fastopen net.ipv4.tcp_fin_timeout net.core.somaxconn; do
        old="$(awk -F'|' -v k="$kv" '$1==k{print $2;exit}' "$STATE_DIR/sysctl-before.conf" 2>/dev/null)"
        cur="$(sysctl -n "$kv" 2>/dev/null)"
        mgr="$(awk -F'=' -v k="$kv" '$1==k{print $2;exit}' "$_sf" 2>/dev/null)"
        [ -n "$old" ] && [ -n "$mgr" ] && [ "$cur" = "$mgr" ] && [ "$old" != unknown ] && sysctl -w "$kv=$old" >/dev/null 2>&1
    done
    rm -f "$_sf" "$STATE_DIR/sysctl-before.conf"
done
/etc/init.d/https-dns-proxy restart 2>/dev/null
/etc/init.d/dnsmasq restart 2>/dev/null
printf "${C_GREEN}✓ Изменения обработаны.${C_NC}\n"
printf "${C_YELLOW}! Изменения вне зоны DNS Manager не затрагивались.${C_NC}\n"
pause
}
rollback_ours() {
    acquire_mutation_lock || return 1
    _rc=0
    _rollback_ours_impl "$@" || _rc=$?
    release_mutation_lock
    return "$_rc"
}

# ==========================================
# ==========================================
state_word() {
case "$1" in
yes|1|on|working|running) printf "${C_GREEN}ВКЛ • работает${C_NC}";;
no|0|off|stopped|missing) printf "${C_YELLOW}ВЫКЛ • нет${C_NC}";;
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
    [ "${DNS_PROFILE:-}" = "hybrid" ] || return 0

    _expected=0
    _actual=0

    for _hs in 1 2 3 4 5 6 RU RU_2; do
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
third_party_running() {
    _n="$1"
    case "$_n" in
        zapret) pgrep -f '(^|/)(zms|zapret)' >/dev/null 2>&1 ;;
        zapret2) pgrep -f '(^|/)(zapret2|zaproxy2)' >/dev/null 2>&1 ;;
        netshift) pgrep -f '(^|/)netshift([[:space:]]|$)' >/dev/null 2>&1 ;;
        splify) pgrep -f '(^|/)splify([[:space:]]|$)' >/dev/null 2>&1 ;;
        mixomo) pgrep -f 'mihomo' >/dev/null 2>&1 ;;
        magi) pgrep -f 'magitrickle' >/dev/null 2>&1 ;;
        hev) pgrep -f 'hev-socks5-tunnel' >/dev/null 2>&1 ;;
        awg) pgrep -f 'awg|amneziawg' >/dev/null 2>&1 ;;
        tggo) pgrep -f 'tg-ws-proxy-go' >/dev/null 2>&1 ;;
        tgrs) pgrep -f 'tg-ws-proxy-rs' >/dev/null 2>&1 ;;
        tgmt) pgrep -f 'tg-ws-proxy-mtproto' >/dev/null 2>&1 ;;
        byedpi) pgrep -f 'byedpi' >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}
show_map() {
sync_regional_dns_state
menu_header "СОСТОЯНИЕ РОУТЕРА"
menu_section "СИСТЕМА"
printf "  OpenWrt:        ${C_WHITE}%s${C_NC}\n" "$SYS_OWRT"
printf "  Платформа:      ${C_WHITE}%s${C_NC}\n" "$SYS_TARGET"
printf "  Архитектура:    ${C_WHITE}%s${C_NC}\n" "$SYS_ARCH"
printf "  Scheduler:      ${C_WHITE}%s${C_NC}\n" "$WATCHDOG_CRON_AVAILABLE"
printf "  Crond:          ${C_WHITE}%s${C_NC}\n" "$WATCHDOG_CRON_RUNNING"
printf "  Firewall:       ${C_WHITE}%s${C_NC}\n" "$SYS_FW"
printf "  Backend:        ${C_WHITE}%s${C_NC}\n" "$FIREWALL_BACKEND"
printf "  LAN:            ${C_WHITE}%s${C_NC}\n" "$LAN_IP"
printf "  WAN:            ${C_WHITE}%s${C_NC}\n" "$WAN_PROTO"
printf "  IPv4:           %s\n" "$(state_word "$IPV4_ROUTE")"
printf "  IPv6:           %s\n" "$(state_word "$IPV6_ROUTE")"
printf "  curl:            %s\n" "$(state_word "$HAS_CURL")"
printf "  dig:             %s\n" "$(state_word "$HAS_DIG")"
printf "  ntpd:            %s\n" "$(state_word "$HAS_NTPD")"
menu_section "DNS"
printf "  dnsmasq:         %s\n" "$(state_word "$DNSMASQ_RUN")"
refresh_doh_scheme_counts
printf "  DNS-серверов всего:       ${C_WHITE}%s${C_NC}\n" "$DOH_TOTAL"
printf "  По текущей схеме:         ${C_WHITE}%s${C_NC}\n" "$DOH_MATCH"
printf "  Вне текущей схемы:        ${C_WHITE}%s${C_NC}\n" "$DOH_OTHER"
hybrid_runtime_state_word | grep -q . && printf "  Гибридный DNS:    %s\n" "$(hybrid_runtime_state_word)"
[ "$DNS_SMARTDNS" = yes ] && printf "  SmartDNS:         %s\n" "$(state_word "$DNS_SMARTDNS")"
[ "$DNS_UNBOUND" = yes ] && printf "  Unbound:          %s\n" "$(state_word "$DNS_UNBOUND")"
[ "$DNS_ADGUARD" = yes ] && printf "  AdGuard Home:     %s\n" "$(state_word "$DNS_ADGUARD")"
[ "$DNS_MOSDNS" = yes ] && printf "  MosDNS:           %s\n" "$(state_word "$DNS_MOSDNS")"
[ "$DNS_SINGBOX" = yes ] && printf "  Sing-box:         %s\n" "$(state_word "$DNS_SINGBOX")"
menu_section "ВЫБРАННЫЕ DNS"
printf "  ${C_WHITE}%-6s %-32s %s${C_NC}\n" "СЛОТ" "DNS" "ФАКТИЧЕСКИЙ ПОРТ"
for _s in 1 2 3 4 5 6; do
    eval "_v=\${SLOT_$_s:-}"
    eval "_p=\${PORT_$_s:-}"
    [ -n "$_v" ] || continue
    [ -n "$_p" ] || _p="$(hybrid_desired_port "$_s")"
    printf "  %-6s %-32s 127.0.0.1:%s\n" "$_s" "$(dns_name "$_v")" "$_p"
done
if [ -n "${SLOT_RU:-}" ]; then
    printf "  %-6s %-32s 127.0.0.1:%s (.ru/.su/.рф)\n" "RU" "$(dns_name "$SLOT_RU")" "${PORT_RU:-$HYBRID_PORT_RU}"
else
    printf "  %-6s %s\n" "RU" "не выбран"
fi
if [ -n "${SLOT_RU_2:-}" ]; then
    printf "  %-6s %-32s 127.0.0.1:%s
" "RU2" "$(dns_name "$SLOT_RU_2")" "${PORT_RU_2:-${HYBRID_PORT_RU_2:-5060}}"
fi
menu_section "СТОРОННИЕ РЕШЕНИЯ"
_side_found=0
for _tp in  "zapret|Zapret" "zapret2|Zapret2" "netshift|NetShift" "splify|splify"  "mixomo|Mixomo" "magi|MagiTrickle" "hev|HevSocks5Tunnel" "awg|AWG"  "tggo|TG-Go" "tgrs|TG-Rust" "tgmt|TG-MTProto" "byedpi|ByeDPI"; do
    _kind="${_tp%%|*}"
    _label="${_tp#*|}"
    if third_party_running "$_kind"; then
        printf "  ${C_GREEN}✓${C_NC} %s — работает\n" "$_label"
        _side_found=1
    fi
done
[ "$_side_found" = 1 ] || printf "  ${C_YELLOW}—${C_NC} Активных сторонних служб не обнаружено\n"
menu_section "FIREWALL"
printf "  QUIC:                       %s\n" "$(module_state_word quic "$BLOCK_QUIC")"
printf "  Активный nft:               %s\n" "$(state_word "$NFT_ACTIVE")"
printf "  Активный iptables:          %s\n" "$(state_word "$IPTABLES_ACTIVE")"
printf "  Аппаратное ускорение:       %s\n" "$(state_word "$FLOW_OFFLOAD")"
menu_section "НАСТРОЙКИ DNS Manager"
printf "  Настройка:                   ${C_YELLOW}%s${C_NC}\n" "$( [ "$DNS_PROFILE" = hybrid ] && printf '%s' 'Гибридный DNS — 6 серверов + Яндекс RU' || printf '%s' 'Своя настройка' )"
printf "  Балансировка DNS:           %s\n" "$(module_state_word balance "$BALANCER_ENABLED")"
printf "  Отдельный DNS (.ru/.su/.рф): %s\n" "$(module_state_word tld "$TLD_SPLIT")"
printf "  Блокировка QUIC (DPI):      %s\n" "$(module_state_word quic "$BLOCK_QUIC")"
printf "  Исправление сетевых параметров / MSS:      %s\n" "$(module_state_word mtu "$MTU_FIX")"
printf "  Принудительный DNS:         %s\n" "$(module_state_word force "$FORCE_DOH")"
printf "  Настройка сети:     %s\n" "$(module_state_word sysctl "$SYSCTL_TUNING")"
printf "  Настройка DNS-кэша:             %s\n" "$(module_state_word dnsmasq_perf "$DNSMASQ_PERF")"
printf "  NTP для клиентов:           %s\n" "$(module_state_word ntp_clients "$NTP_CLIENTS")"
printf "  Связь системных служб:     %s\n" "$(module_state_word client_fixes "$CLIENT_FIXES")"
printf "${C_GREEN}✓ Discovery завершён. Изменений в конфигурацию не внесено.${C_NC}\n"
menu_section "ЖУРНАЛ"
printf "${C_WHITE}Последние события:${C_NC}\n"
if [ -s "$LOG_FILE" ]; then tail -15 "$LOG_FILE" | sed -e "s/ START / Запуск /" -e "s/ UPDATE / Обновление /" -e "s/ INFO / Информация: /" -e "s/ WARN / Внимание: /" -e "s/ ERROR / Ошибка: /"; else printf "${C_YELLOW}Журнал пока пуст.${C_NC}\n"; fi
echo ""
printf "${C_WHITE}Последняя проверка:${C_NC}\n"
if [ -s "$TEST_RESULTS" ]; then
    _status_total="$(count_dns)"
    _status_ok="$(awk -F'|' 'NF>=5 && $5=="OK"{n++} END{print n+0}' "$TEST_RESULTS" 2>/dev/null)"
    _status_fail=$((_status_total-_status_ok))
    printf "  DNS: ${C_GREEN}%s работают${C_NC}, ${C_YELLOW}%s не прошли${C_NC}, всего %s\n" "$_status_ok" "$_status_fail" "$_status_total"
else
    printf "  ${C_YELLOW}Тест DNS ещё не запускался.${C_NC}\n"
fi
echo ""
printf "${C_WHITE}Последние действия:${C_NC}\n"
if [ -s "$TX_LOG" ]; then
    tail -10 "$TX_LOG" | awk -F'|' 'NF>=8 && $4 != "" {
        phase=$4; obj=$5; act=$6; res=$7;
        if (phase=="DISCOVER") phase="Проверка состояния";
        else if (phase=="TEST") phase="Тест";
        else if (phase=="PLAN") phase="Подготовка";
        else if (phase=="APPLY") phase="Настройка";
        else if (phase=="VERIFY") phase="Проверка результата";
        if (res=="OK") res="успешно"; else if (res=="FAIL") res="ошибка";
        printf "  %s: %s → %s → %s\n", phase,obj,act,res;
    }'
else
    printf "  ${C_YELLOW}Транзакций пока нет.${C_NC}\n"
fi
pause
}
# ==========================================
# ==========================================
show_doh() {
menu_header "НАЙДЕННЫЕ DNS-СЕРВЕРЫ"
[ -s "$DOH_INV" ] || { printf "${C_YELLOW}https-dns-proxy секции не найдены.${C_NC}\n"; pause; return; }
menu_section "СЕКЦИИ"
printf "  ${C_WHITE}%-4s %-8s %-14s %-8s %-12s${C_NC}\n" "#" "ПОРТ" "СООТВЕТСТВИЕ" "СОСТ." "АДРЕС"
printf "  ──────────────────────────────────────────────────────────\n"
while IFS='|' read -r idx port addr running url; do
    _match="нет"
    for _slot in 1 2 3 4 5 6 RU RU_2; do
        if doh_slot_matches_current "$_slot" "$port" "$url"; then _match="да"; break; fi
    done
    printf "  ${C_YELLOW}%-4s${C_NC} %-8s %-14s %b %-12s\n" "#$idx" "$port" "$_match" "$(state_word "$running")" "$addr:$port"
    printf "      ${C_CYAN}%s${C_NC}\n" "$url"
done < "$DOH_INV"
pause
}
show_tests() {
menu_header "РЕЗУЛЬТАТЫ ПРОВЕРКИ DNS"
[ -s "$TEST_RESULTS" ] || { printf "${C_YELLOW}Тест ещё не запускался.${C_NC}\n"; pause; return; }
okn="$(awk -F'|' 'NF>=5 && $5=="OK"{n++} END{print n+0}' "$TEST_RESULTS" 2>/dev/null)"; total="$(count_dns)"; failn=$((total-okn))
printf "${C_GREEN}✓ Работают: %s${C_NC}    ${C_RED}✗ Ошибки: %s${C_NC}    ${C_WHITE}Всего: %s${C_NC}\n\n" "$okn" "$failn" "$total"
printf "${C_YELLOW}${C_BOLD}%-28s %-18s %-9s %s${C_NC}\n" "DNS" "КАТЕГОРИЯ" "ВРЕМЯ" "СТАТУС"
printf "  ──────────────────────────────────────────────────────────\n"
{ grep '|OK$' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n; grep -v '|OK$' "$TEST_RESULTS" 2>/dev/null; } | while IFS='|' read -r id cat name ms st; do
status_text="$(status_ru "$st")"
cat_text="$(category_ru "$cat")"
case "$st" in
OK) status="${C_GREEN}${status_text}${C_NC}";;
BOOTSTRAP_FAIL|BAD_DOH_RESPONSE) status="${C_YELLOW}${status_text}${C_NC}";;
*) status="${C_RED}${status_text}${C_NC}";;
esac
case "$ms" in ''|-1) time="—";; *) time="${ms} мс";; esac
printf "%-28s %-18s %-9s %b\n" "$name" "$cat_text" "$time" "$status"
done
pause
}
apply_profile_now() {
goal="$1"
case "$goal" in
bypass)
    quick_max_bypass
    return
    ;;
clean|security|privacy|adblock|family|all)
    DNS_PROFILE="custom"
    DNS_SELECTION_MODE="profile"
    DNS_SELECTION_CATEGORY="$goal"
    TLD_RU_ENABLED=0
    TLD_SPLIT=0
    BALANCER_ENABLED=1
    PORT_1="$HYBRID_PORT_1"; PORT_2="$HYBRID_PORT_2"; PORT_3="$HYBRID_PORT_3"
    PORT_4="$HYBRID_PORT_4"; PORT_5="$HYBRID_PORT_5"; PORT_6="$HYBRID_PORT_6"
    PORT_RU=""; PORT_RU_2=""
    SLOT_RU=""; SLOT_RU_2=""
    if auto_fill_slots "$goal"; then
        CORE_ONLY=1
        apply_settings
        CORE_ONLY=0
    fi
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
    eval "SLOT_$i=\"$_id\""
    if [ "$_cat" = bypass ]; then
        eval "SLOT_${i}_CAT=\"bypass\""
    else
        eval "SLOT_${i}_CAT=\"$_cat2\""
    fi
    i=$((i+1))
    [ "$i" -gt 6 ] && break
done < "$_pool"
while [ "$i" -le 6 ]; do
    eval "SLOT_$i=\"\""
    eval "SLOT_${i}_CAT=\"bypass\""
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
SLOT_RU_2="$(awk -F'|' -v skip="$_ru1" 'NF>=5 && $2=="regional" && $5=="OK" && $4 ~ /^[0-9]+$/ && $1!=skip{print $1;exit}' "$TEST_RESULTS" 2>/dev/null)"
if [ -n "$SLOT_RU_2" ]; then SLOT_RU_2_CAT="regional"; else SLOT_RU_2_CAT="regional"; fi
save_config
if [ "${HYBRID_SELECTION_QUIET:-0}" != 1 ]; then
    printf "${C_GREEN}✓ Автоматически выбран набор DNS без дублей.${C_NC}\n"
    for i in 1 2 3 4 5 6; do
        eval "_v=\${SLOT_$i}"
        [ -n "$_v" ] && printf "  ${C_WHITE}Слот %s: %s${C_NC}\n" "$i" "$(dns_name "$_v")"
    done
    [ -n "$SLOT_RU" ] && printf "  ${C_WHITE}RU: %s${C_NC}\n" "$(dns_name "$SLOT_RU")"
    [ -n "$SLOT_RU_2" ] && printf "  ${C_WHITE}RU2: %s${C_NC}\n" "$(dns_name "$SLOT_RU_2")"
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
        RU|RU_2) awk -F'|' 'NF>=5 && $1 !~ /^#/ && $2=="regional" {print}' "$DNS_CATALOG" > "$_sel_catalog" ;;
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
        eval "SLOT_$slot=''"
        case "$slot" in
            RU|RU_2) eval "SLOT_${slot}_CAT='regional'" ;;
            *) eval "SLOT_${slot}_CAT=''" ;;
        esac
        sync_regional_dns_state
        save_config
        return
    fi
    case "$c" in ''|*[!0-9]*) warn_msg "Неверный номер."; pause; return;; esac
    row=""
    case "$slot" in
        RU|RU_2) row="$(awk -F'|' -v n="$c" 'NF>=5 && $1 !~ /^#/ && $2=="regional" {i++; if(i==n){print; exit}}' "$DNS_CATALOG")" ;;
        1|2|3|4|5|6) row="$(awk -F'|' -v n="$c" 'NF>=5 && $1 !~ /^#/ && $2!="regional" {i++; if(i==n){print; exit}}' "$DNS_CATALOG")" ;;
    esac
    id="$(printf '%s' "$row" | cut -d'|' -f1)"
    [ -n "$id" ] || { warn_msg "Такого DNS нет в списке."; pause; return; }
    _selected_cat="$(printf '%s' "$row" | cut -d'|' -f2)"
    DNS_PROFILE="custom"
    DNS_SELECTION_MODE="manual"
    eval "SLOT_$slot=\$id"
    eval "SLOT_${slot}_CAT=\$_selected_cat"
    if [ "$slot" = RU ] || [ "$slot" = RU_2 ]; then
        DNS_SELECTION_CATEGORY="regional"
    else
        DNS_SELECTION_CATEGORY="$_selected_cat"
    fi
    sync_regional_dns_state
    save_config
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
printf "  ${C_CYAN}${C_BOLD}[8]${C_NC} ${C_GREEN}${C_BOLD}RU2${C_NC}  ${C_GREEN}%-30s${C_NC} ${C_YELLOW}${C_BOLD}%s${C_NC}\n" "$(dns_name "$SLOT_RU_2")" "${PORT_RU_2:-авто}"
menu_section "ДЕЙСТВИЯ"
menu_item "[9]" "Сохранить и применить DNS"
menu_item "[10]" "Восстановить стандартную настройку"
menu_back
menu_prompt
safe_read c
[ -z "$c" ] && return
case "$c" in
1|2|3|4|5|6) select_slot "$c";;
7) select_slot RU;;
8) select_slot RU_2;;
9) CORE_ONLY=1; apply_settings; _rc=$?; CORE_ONLY=0; [ "$_rc" -eq 0 ] || warn_msg "Не удалось применить выбранные DNS."; pause;;
10) hybrid_set_defaults; save_config; ok_msg "Стандартный Гибридный DNS восстановлен: 5053–5058 + Yandex 5059."; pause;;
*) warn_msg "Неверный пункт."; pause;;
esac
done
}
menu_bogus() {
apply_bogus
}
apply_quic_toggle() {
    QUIC_EXTERNAL_REMAINING=0
    if [ "$BLOCK_QUIC" != 1 ]; then
        quic_remove_managed_rules || return 1
    else
        apply_quic || return 1
    fi
    uci commit firewall >/dev/null 2>&1 || return 1
    reload_fw >/dev/null 2>&1 || return 1
    if [ "$BLOCK_QUIC" != 1 ]; then
        firewall_resolve_zones
        firewall_find_exact_quic 80 "$FW_QUIC80_SECTION" >/dev/null 2>&1 && QUIC_EXTERNAL_REMAINING=1
        firewall_find_exact_quic 443 "$FW_QUIC443_SECTION" >/dev/null 2>&1 && QUIC_EXTERNAL_REMAINING=1
    fi
    save_config || return 1
    return 0
}
firewall_wan_zone() {
    firewall_wan_zone_require
}

cleanup_legacy_mtu_default() {
    _legacy_mtu="$(uci -q get firewall.@defaults[0].mtu_fix 2>/dev/null)"
    [ "$_legacy_mtu" = 1 ] || return 0
    uci -q delete firewall.@defaults[0].mtu_fix || return 1
    rm -f "$LEGACY_MTU_BEFORE" 2>/dev/null || true
    log_msg "Миграция MTU/MSS: удалена устаревшая firewall.@defaults[0].mtu_fix; параметр управляется через WAN-зону."
    return 0
}

apply_mtu_toggle() {
    _wan_zone="$(firewall_wan_zone 2>/dev/null)" || return 1
    if [ "${MTU_FIX:-0}" = 1 ]; then
        if [ ! -s "$MTU_BEFORE" ]; then
            printf '%s\n' "$(uci -q get "firewall.$_wan_zone.mtu_fix" 2>/dev/null)" > "$MTU_BEFORE" || return 1
        fi
        uci -q set "firewall.$_wan_zone.mtu_fix=1" || return 1
        cleanup_legacy_mtu_default || return 1
    else
        if [ -s "$MTU_BEFORE" ]; then
            _old="$(head -n1 "$MTU_BEFORE" 2>/dev/null)"
            _cur_mtu="$(uci -q get "firewall.$_wan_zone.mtu_fix" 2>/dev/null)"
            if [ "$_cur_mtu" = 1 ]; then
                if [ -n "$_old" ]; then
                    uci -q set "firewall.$_wan_zone.mtu_fix=$_old" || return 1
                else
                    uci -q delete "firewall.$_wan_zone.mtu_fix" || true
                fi
            else
                warn_msg "MTU/MSS: значение в WAN-зоне изменено извне после применения. Текущее значение сохранено."
            fi
            rm -f "$MTU_BEFORE"
        else
            warn_msg "MTU/MSS: нет снимка владения DNS Manager. Текущее значение WAN mtu_fix сохранено."
        fi
        cleanup_legacy_mtu_default || return 1
    fi
    rm -f "$LEGACY_MTU_BEFORE" 2>/dev/null || true
    uci commit firewall >/dev/null 2>&1 || return 1
    reload_fw >/dev/null 2>&1 || return 1
    return 0
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
check_module_state() {
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
            for _slot in RU RU_2; do
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
            [ "$(uci -q get system.ntp.use_dhcp 2>/dev/null)" = 0 ] || { printf 0; return; }
            [ "$(uci -q get system.ntp.enabled 2>/dev/null)" = 1 ] || { printf 0; return; }
            _exp="$(ntp_servers_for_profile "$NTP_PRESET")"
            [ -n "$_exp" ] || { printf 0; return; }
            _cur="$(uci -q get system.ntp.server 2>/dev/null)"
            for _ip in $_exp; do
                printf '%s\n' $_cur | grep -qxF "$_ip" || { printf 0; return; }
            done
            printf 1
            ;;
        quic)
            _q80=0; _q443=0
            firewall_quic_function_exists 80 >/dev/null 2>&1 && _q80=1
            firewall_quic_function_exists 443 >/dev/null 2>&1 && _q443=1
            if [ "$_q80" = 1 ] && [ "$_q443" = 1 ]; then
                printf 1
            elif [ "$_q80" = 1 ] || [ "$_q443" = 1 ]; then
                printf 2
            else
                printf 0
            fi
            ;;
        mtu)
            _wan_zone="$(firewall_wan_zone 2>/dev/null)" || { printf 0; return; }
            _v="$(uci -q get "firewall.$_wan_zone.mtu_fix" 2>/dev/null)"
            [ "$_v" = 1 ] && printf 1 || { [ -n "$_v" ] && printf 2 || printf 0; }
            ;;
        sysctl)
            _base="$(sysctl_base_manager_path)"
            _all=1; _any=0
            for _p in "net.ipv4.tcp_fastopen=3" "net.ipv4.tcp_fin_timeout=15" "net.core.somaxconn=1024"; do
                _k="${_p%%=*}"; _v="${_p#*=}"
                _cur="$(sysctl -n "$_k" 2>/dev/null)"
                [ "$_cur" = "$_v" ] && _any=1
                [ "$_cur" = "$_v" ] || _all=0
                [ -f "$_base" ] || _all=0
                [ -f "$_base" ] && grep -qxF "$_p" "$_base" 2>/dev/null || _all=0
            done
            if [ "${SYSCTL_EXTENDED:-0}" = 1 ]; then
                _ext="$(sysctl_extended_manager_path)"
                [ -f "$_ext" ] || _all=0
                while IFS= read -r _p; do
                    [ -n "$_p" ] || continue
                    _k="${_p%%=*}"; _v="${_p#*=}"
                    _cur="$(sysctl -n "$_k" 2>/dev/null)"
                    [ "$_cur" = "$_v" ] && _any=1
                    [ "$_cur" = "$_v" ] || _all=0
                    [ -f "$_ext" ] && grep -qxF "$_p" "$_ext" 2>/dev/null || _all=0
                done <<EOF_CHECK_EXT
$(sysctl_extended_params)
EOF_CHECK_EXT
            fi
            [ "$_all" = 1 ] && printf 1 || { [ "$_any" = 1 ] || [ -f "$_base" ] && printf 2 || printf 0; }
            ;;
        force)
            _proxy=0; _dns=0; _dot=0
            [ "$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)" = 0 ] &&
            [ "$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null)" = 0 ] &&
            { [ "$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null)" = - ] ||
              [ -z "$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null)" ]; } && _proxy=1
            firewall_section_owned_redirect "$FW_DNS_REDIRECT_SECTION" "$FIREWALL_LAN_ZONE" 'tcp udp' 53 "$LAN_IP" 53 DNAT 2>/dev/null && _dns=1
            firewall_find_exact_redirect "$FIREWALL_LAN_ZONE" 'tcp udp' 53 "$LAN_IP" 53 DNAT "$FW_DNS_REDIRECT_SECTION" >/dev/null 2>&1 && _dns=1
            firewall_dot_rule_matches "$FW_DOT_SECTION" && _dot=1
            firewall_find_exact_rule_signature dot "$FW_DOT_SECTION" >/dev/null 2>&1 && _dot=1
            if [ "$_proxy" = 1 ] && [ "$_dns" = 1 ] && [ "$_dot" = 1 ]; then
                printf 1
            elif [ "$_proxy" = 1 ] || [ "$_dns" = 1 ] || [ "$_dot" = 1 ]; then
                printf 2
            else
                printf 0
            fi
            ;;
        ntp_clients)
            _opt="42,$LAN_IP"; _dhcp=0; _fw=0
            exact_list_has "dhcp.$_sec.dhcp_option" "$_opt" && _dhcp=1
            ntp_firewall_rule_owned && _fw=1
            ntp_firewall_rule_exact_external && _fw=1
            if [ "$_dhcp" = 1 ] && [ "$_fw" = 1 ]; then
                printf 1
            elif [ "$_dhcp" = 1 ] || [ "$_fw" = 1 ]; then
                printf 2
            else
                printf 0
            fi
            ;;
        dnsmasq_perf)
            _all=1; _any=0
            for _kv in "cachesize|1000" "dnsforwardmax|300" "max_cache_ttl|86400" "boguspriv|1" "domainneeded|1" "quietdhcp|1"; do
                _k="${_kv%%|*}"; _v="${_kv#*|}"
                _cur="$(uci -q get "dhcp.$_sec.$_k" 2>/dev/null)"
                [ "$_cur" = "$_v" ] && _any=1 || _all=0
            done
            if [ "$IPV6_ROUTE" != yes ]; then
                [ "$(uci -q get "dhcp.$_sec.filter_aaaa" 2>/dev/null)" = 1 ] || _all=0
            fi
            [ "$_all" = 1 ] && printf 1 || { [ "$_any" = 1 ] && printf 2 || printf 0; }
            ;;
        client_fixes)
            _f="${CLIENT_FIXES_FILE:-/etc/dnsmasq.d/91-dns-manager-client-fixes.conf}"
            [ -f "$_f" ] || { printf 0; return; }
            _ok=1
            for _fix in \
                'local=/telemetry.mozilla.org/' \
                'local=/telemetry.microsoft.com/' \
                'local=/vortex.data.microsoft.com/' \
                'local=/settings-win.data.microsoft.com/' \
                'local=/metrics.android.com/' \
                'local=/metrics.samsung.com/' \
                'server=/clients3.google.com/77.88.8.8' \
                'server=/clients3.google.com/77.88.8.1' \
                'server=/connectivitycheck.gstatic.com/77.88.8.8' \
                'server=/connectivitycheck.gstatic.com/77.88.8.1' \
                'server=/connectivitycheck.android.com/77.88.8.8' \
                'server=/connectivitycheck.android.com/77.88.8.1' \
                'server=/connectivitycheck.samsung.com/77.88.8.8' \
                'server=/connectivitycheck.samsung.com/77.88.8.1' \
                'server=/connectivitycheck.platform.hicloud.com/77.88.8.8' \
                'server=/connectivitycheck.platform.hicloud.com/77.88.8.1'; do
                grep -qxF "$_fix" "$_f" 2>/dev/null || _ok=0
            done
            [ "$_ok" = 1 ] && printf 1 || printf 2
            ;;
        watchdog)
            _wd_line="*/${WATCHDOG_INTERVAL:-15} * * * * ${MANAGER_PATH} watchdog >> ${LOG_FILE} 2>&1"
            if watchdog_cron_line_exists "$_wd_line"; then
                printf 1
            elif [ "${WATCHDOG_ENABLED:-0}" = 0 ]; then
                printf 0
            else
                printf 0
            fi
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

module_state_word() {
    _real="$(check_module_state "$1")"
    case "$_real" in
        1) printf "${C_BOLD}${C_GREEN}✓ ВКЛ${C_NC} ${C_CYAN}${C_BOLD}• настроено${C_NC}" ;;
        2) printf "${C_BOLD}${C_YELLOW}⚠ ДРУГОЕ${C_NC} ${C_CYAN}${C_BOLD}• отличается от целевой настройки${C_NC}" ;;
        *) printf "${C_BOLD}${C_RED}✗ ВЫКЛ${C_NC} ${C_CYAN}${C_BOLD}• сток${C_NC}" ;;
    esac
}
# ==========================================
web_access_listener_exists() {
    _wp="$1"
    [ -n "$_wp" ] || return 1
    if command -v ss >/dev/null 2>&1; then
        ss -lntp 2>/dev/null | grep -qE "(^|[[:space:]])[^[:space:]]*:[0-9]+.*:${_wp}([[:space:]]|$)" && return 0
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -lntp 2>/dev/null | grep -qE "(^|[[:space:]])[^[:space:]]*:${_wp}([[:space:]]|$)" && return 0
    fi
    listener_port_exists "$_wp"
}
web_access_owner_pid() {
    _wp="$1"
    [ -n "$_wp" ] || return 1
    _pid=""
    if command -v ps >/dev/null 2>&1; then
        _pid="$(ps w 2>/dev/null | awk -v p="$_wp" '$1 ~ /^[0-9]+$/ && index($0,"ttyd") && index($0,"/usr/bin/dns-manager") && (index($0,"-p " p) || index($0," " p " ")) {print $1; exit}')"
        case "$_pid" in
            ''|*[!0-9]*) ;;
            *) printf '%s\n' "$_pid"; return 0;;
        esac
    fi
    if command -v ss >/dev/null 2>&1; then
        _line="$(ss -lntp 2>/dev/null | grep -E "(^|[[:space:]])[^[:space:]]*:${_wp}([[:space:]]|$)" | head -n1)"
        _pid="$(printf '%s\n' "$_line" | sed -n 's/.*pid=\([0-9][0-9]*\),.*/\1/p')"
        case "$_pid" in ''|*[!0-9]*) ;; *) printf '%s\n' "$_pid"; return 0;; esac
    fi
    return 1
}
web_access_cmdline_is_ours() {
    _pid="$1"
    [ -n "$_pid" ] || return 1
    [ -r "/proc/$_pid/cmdline" ] || return 1
    _cmd="$(tr '\0' ' ' < "/proc/$_pid/cmdline" 2>/dev/null)"
    case "$_cmd" in
        *ttyd*"-p ${WEB_ACCESS_PORT}"*"/usr/bin/dns-manager"*) return 0;;
        *ttyd*"${WEB_ACCESS_PORT}"*"/usr/bin/dns-manager"*) return 0;;
    esac
    return 1
}
web_access_cleanup_legacy_uci() {
    _legacy_cmd="$(uci -q get "ttyd.$WEB_TTYD_SECTION.command" 2>/dev/null || true)"
    if [ "$_legacy_cmd" = "/usr/bin/dns-manager" ]; then
        uci -q delete "ttyd.$WEB_TTYD_SECTION" || true
        uci commit ttyd >/dev/null 2>&1 || true
    fi
}
web_access_write_service() {
    mkdir -p /etc/init.d /var/run 2>/dev/null || return 1
    cat > "$WEB_SERVICE_CONFIG" <<'EOF_WEB_INIT'
#!/bin/sh /etc/rc.common

START=95
STOP=10
USE_PROCD=1

PROG=/usr/bin/ttyd
PORT=7682
IFACE=br-lan
CMD=/usr/bin/dns-manager
PIDFILE=/var/run/dns-manager-web.pid

start_service() {
    [ -x "$PROG" ] || return 1
    [ -x "$CMD" ] || return 1

    procd_open_instance
    procd_set_param command "$PROG"
    procd_append_param command -p "$PORT"
    procd_append_param command -i "$IFACE"
    procd_append_param command -W
    procd_append_param command -t fontSize=15
    procd_append_param command "$CMD"
    procd_set_param respawn 3600 5 5
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

EOF_WEB_INIT
    chmod 0755 "$WEB_SERVICE_CONFIG" || return 1
    return 0
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
    [ "$(web_access_pid_count 2>/dev/null || printf 0)" -eq 1 ] || return 1
    _pid="$(web_access_owner_pid "$_wp" 2>/dev/null || true)"
    [ -n "$_pid" ] || return 1
    kill -0 "$_pid" 2>/dev/null || return 1
    web_access_cmdline_is_ours "$_pid"
}
web_access_own_port() {
    _wp="${WEB_ACCESS_PORT:-7682}"
    _pid="$(web_access_owner_pid "$_wp" 2>/dev/null || true)"
    [ -n "$_pid" ] || return 1
    web_access_cmdline_is_ours "$_pid"
}
web_access_port_busy() {
    _wp="${WEB_ACCESS_PORT:-7682}"
    web_access_listener_exists "$_wp" || return 1
    web_access_own_port && return 1
    return 0
}
web_access_install() {
    if ! command -v ttyd >/dev/null 2>&1; then
        if [ "$PKG_MGR" = "apk" ]; then
            apk update >/dev/null 2>&1 || return 1
            apk add ttyd >/dev/null 2>&1 || return 1
        else
            opkg update >/dev/null 2>&1 || return 1
            opkg install ttyd >/dev/null 2>&1 || return 1
        fi
    fi
    command -v ttyd >/dev/null 2>&1 || return 1
    web_access_write_service || return 1
    web_access_cleanup_legacy_uci
    return 0
}
web_access_write_config() {
    web_access_write_service
}
web_access_remove_config() {
    web_access_stop
    web_access_cleanup_legacy_uci
    rm -f "$WEB_SERVICE_CONFIG" 2>/dev/null || true
    return 0
}
web_access_start() {
    [ -x "$WEB_SERVICE_CONFIG" ] || web_access_write_service || return 1
    "$WEB_SERVICE_CONFIG" enable >/dev/null 2>&1 || true
    web_access_stop || true
    "$WEB_SERVICE_CONFIG" start >/dev/null 2>&1 || return 1
    sleep 2
    _count="$(web_access_pid_count 2>/dev/null || printf 0)"
    [ "$_count" -eq 1 ] && web_access_real
}
web_access_stop() {
    if [ -x "$WEB_SERVICE_CONFIG" ]; then
        "$WEB_SERVICE_CONFIG" stop >/dev/null 2>&1 || true
        sleep 1
    fi
    for _pid in $(ps w 2>/dev/null | awk -v p="${WEB_ACCESS_PORT:-7682}" '$1 ~ /^[0-9]+$/ && index($0,"ttyd") && index($0,"/usr/bin/dns-manager") && (index($0,"-p " p) || index($0," " p " ")) {print $1}'); do
        kill "$_pid" 2>/dev/null || true
    done
    sleep 1
    for _pid in $(ps w 2>/dev/null | awk -v p="${WEB_ACCESS_PORT:-7682}" '$1 ~ /^[0-9]+$/ && index($0,"ttyd") && index($0,"/usr/bin/dns-manager") && (index($0,"-p " p) || index($0," " p " ")) {print $1}'); do
        kill -9 "$_pid" 2>/dev/null || true
    done
    rm -f "$WEB_PIDFILE" 2>/dev/null || true
    return 0
}
web_access_restart() {
    [ -x "$WEB_SERVICE_CONFIG" ] || return 0
    web_access_stop || true
    "$WEB_SERVICE_CONFIG" start >/dev/null 2>&1 || return 1
    sleep 1
    web_access_real
}
web_access_firewall() {
    firewall_lan_zone_require >/dev/null || return 1
    firewall_cleanup_legacy_web_rule >/dev/null 2>&1 || true
    _external_web="$(firewall_find_exact_rule_signature web "$FW_WEB_SECTION" "$WEB_ACCESS_PORT" 2>/dev/null)"
    if uci -q get "firewall.$FW_WEB_SECTION" >/dev/null 2>&1; then
        firewall_owner_has "$FW_WEB_SECTION" || return 2
        firewall_ref_matches_zone "$(uci -q get "firewall.$FW_WEB_SECTION.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" || return 1
        [ "$(uci -q get "firewall.$FW_WEB_SECTION.proto" 2>/dev/null)" = tcp ] || return 1
        [ "$(uci -q get "firewall.$FW_WEB_SECTION.dest_port" 2>/dev/null)" = "$WEB_ACCESS_PORT" ] || return 1
        [ "$(uci -q get "firewall.$FW_WEB_SECTION.target" 2>/dev/null)" = ACCEPT ] || return 1
        if [ -n "$_external_web" ]; then
            uci -q delete "firewall.$FW_WEB_SECTION" || return 1
            firewall_owner_remove "$FW_WEB_SECTION" || return 1
        fi
    elif [ -n "$_external_web" ]; then
        :
    else
        uci set "firewall.$FW_WEB_SECTION=rule" || return 1
        uci set "firewall.$FW_WEB_SECTION.name=DNS Manager Web" || return 1
        uci set "firewall.$FW_WEB_SECTION.src=$FIREWALL_LAN_NAME" || return 1
        uci set "firewall.$FW_WEB_SECTION.proto=tcp" || return 1
        uci set "firewall.$FW_WEB_SECTION.dest_port=$WEB_ACCESS_PORT" || return 1
        uci set "firewall.$FW_WEB_SECTION.target=ACCEPT" || return 1
        firewall_owner_add "$FW_WEB_SECTION" || return 1
    fi
    uci commit firewall || return 1
    reload_fw >/dev/null 2>&1 || return 1
}
web_access_remove_firewall() {
    firewall_cleanup_legacy_web_rule >/dev/null 2>&1 || true
    firewall_resolve_zones
    if uci -q get "firewall.$FW_WEB_SECTION" >/dev/null 2>&1; then
        if firewall_owner_has "$FW_WEB_SECTION" && firewall_ref_matches_zone "$(uci -q get "firewall.$FW_WEB_SECTION.src" 2>/dev/null)" "$FIREWALL_LAN_ZONE" && [ "$(uci -q get "firewall.$FW_WEB_SECTION.proto" 2>/dev/null)" = tcp ] && [ "$(uci -q get "firewall.$FW_WEB_SECTION.dest_port" 2>/dev/null)" = "$WEB_ACCESS_PORT" ] && [ "$(uci -q get "firewall.$FW_WEB_SECTION.target" 2>/dev/null)" = ACCEPT ]; then
            uci -q delete "firewall.$FW_WEB_SECTION"
            firewall_owner_remove "$FW_WEB_SECTION"
        fi
    fi
    uci commit firewall >/dev/null 2>&1 || true
    reload_fw >/dev/null 2>&1 || true
}

web_access_luci_install() {
    mkdir -p /usr/lib/lua/luci/controller || return 1
    cat > "$LUCI_CONTROLLER" <<'EOF_LUCI'
module("luci.controller.dns_manager", package.seeall)

function manager_web_enabled()
    local fs = require "nixio.fs"
    local p = "/etc/dns-manager/config/manager.conf"
    local data = fs.readfile(p) or ""
    return data:match('WEB_ACCESS_ENABLED=["\']1["\']') ~= nil
end

function index()
    if not manager_web_enabled() then return end
    local e = entry({"admin", "services", "dns_manager"}, call("redirect_to_manager"), _("DNS Manager"), 70)
    e.leaf = true
end

function redirect_to_manager()
    local uci = require "luci.model.uci".cursor()
    local http = require "luci.http"
    local ip = uci:get("network", "lan", "ipaddr") or "192.168.1.1"
    local port = "7682"
    local fs = require "nixio.fs"
    local data = fs.readfile("/etc/dns-manager/config/manager.conf") or ""
    local found = data:match('WEB_ACCESS_PORT=["\']([0-9]+)["\']')
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
    rm -rf /tmp/luci-* /tmp/luci-indexcache* 2>/dev/null || true
    /etc/init.d/rpcd reload >/dev/null 2>&1 || true
}
web_access_luci_remove() {
    rm -f "$LUCI_CONTROLLER"
    rm -rf /tmp/luci-* /tmp/luci-indexcache* 2>/dev/null || true
    /etc/init.d/rpcd reload >/dev/null 2>&1 || true
}
apply_web_access() {
    apply_wait_message "$( [ "${WEB_ACCESS_ENABLED:-0}" = 1 ] && printf '%s' 'Включаю web-доступ DNS Manager' || printf '%s' 'Выключаю web-доступ DNS Manager' )"
    case "${WEB_ACCESS_ENABLED:-0}" in
        1)
            WEB_ACCESS_PORT=7682
            if web_access_port_busy; then WEB_ACCESS_ENABLED=0; save_config; err_msg "Порт web-доступа $WEB_ACCESS_PORT уже занят."; return 1; fi
            if ! web_access_install; then WEB_ACCESS_ENABLED=0; save_config; err_msg 'Не удалось подготовить web-службу DNS Manager.'; return 1; fi
            if ! web_access_write_config; then WEB_ACCESS_ENABLED=0; save_config; err_msg 'Не удалось подготовить web-службу.'; return 1; fi
            if ! web_access_firewall; then WEB_ACCESS_ENABLED=0; web_access_remove_firewall; web_access_remove_config; save_config; err_msg 'Не удалось открыть web-доступ в LAN.'; return 1; fi
            if ! web_access_luci_install; then WEB_ACCESS_ENABLED=0; web_access_remove_firewall; web_access_remove_config; save_config; err_msg 'Не удалось добавить пункт DNS Manager в LuCI.'; return 1; fi
            if ! web_access_start; then
                WEB_ACCESS_ENABLED=0
                web_access_remove_firewall
                web_access_remove_config
                web_access_luci_remove
                save_config
                err_msg 'Web-доступ не запустился.'
                return 1
            fi
            save_config
            _web_ip="$(uci -q get network.lan.ipaddr 2>/dev/null | cut -d/ -f1)"
            ok_msg "Доступ из браузера включён: http://${_web_ip:-192.168.1.1}:$WEB_ACCESS_PORT"
            return 0
            ;;
        *)
            WEB_ACCESS_ENABLED=0
            web_access_luci_remove
            web_access_remove_firewall
            web_access_remove_config
            save_config
            ok_msg 'Доступ из браузера выключен.'
            return 0
            ;;
    esac
}
# ==========================================
setting_process() {
    _module="$1"
    _title="$2"
    _description="$3"
    _state="$(check_module_state "$_module")"

    printf "\n${C_WHITE}Настройка: %s${C_NC}\n" "$_title"
    printf "  Состояние: %s\n" "$(module_state_word "$_module")"

    case "$_state" in
        0) printf "  Действие:  ВКЛЮЧИТЬ\n" ;;
        1) printf "  Действие:  ВЫКЛЮЧИТЬ\n" ;;
        2) printf "  Действие:  ИСПРАВИТЬ\n" ;;
        *) err_msg "Не удалось определить состояние настройки."; pause; return 1 ;;
    esac
    [ -n "$_description" ] && printf "  %s\n" "$_description"

    case "$_state" in
        0) confirm_action "Включить «$_title»?" || return 0 ;;
        1) confirm_action "Выключить «$_title» и вернуть стоковое состояние?" || return 0 ;;
        2) confirm_action "Исправить «$_title» и применить целевую настройку DNS Manager?" || return 0 ;;
    esac

    _old_force="$FORCE_APPLY_SETTINGS"
    case "$_state" in
        0) _new=1 ;;
        1) _new=0 ;;
        2) _new=1; FORCE_APPLY_SETTINGS=1 ;;
    esac

    case "$_module" in
        sysctl)
            _old="$SYSCTL_TUNING"; _old_ext="$SYSCTL_EXTENDED"
            SYSCTL_TUNING="$_new"
            [ "$_new" = 1 ] && SYSCTL_EXTENDED=1 || SYSCTL_EXTENDED=0
            ;;
        quic) _old="$BLOCK_QUIC"; BLOCK_QUIC="$_new" ;;
        mtu) _old="$MTU_FIX"; MTU_FIX="$_new" ;;
        force) _old="$FORCE_DOH"; FORCE_DOH="$_new" ;;
        dnsmasq_perf) _old="$DNSMASQ_PERF"; DNSMASQ_PERF="$_new" ;;
        ntp_clients) _old="$NTP_CLIENTS"; NTP_CLIENTS="$_new" ;;
        client_fixes) _old="$CLIENT_FIXES"; CLIENT_FIXES="$_new" ;;
    esac

    case "$_module" in
        watchdog)
            _old_watchdog="$WATCHDOG_ENABLED"; WATCHDOG_ENABLED="$_new"
            apply_watchdog
            _rc=$?
            [ "$_rc" -eq 0 ] || WATCHDOG_ENABLED="$_old_watchdog"
            ;;
        web)
            _old_web="$WEB_ACCESS_ENABLED"; WEB_ACCESS_ENABLED="$_new"
            apply_web_access
            _rc=$?
            [ "$_rc" -eq 0 ] || WEB_ACCESS_ENABLED="$_old_web"
            ;;
        *)
            apply_extras_now "$_module"
            _rc=$?
            if [ "$_rc" -ne 0 ]; then
                case "$_module" in
                    sysctl) SYSCTL_TUNING="$_old"; SYSCTL_EXTENDED="$_old_ext" ;;
                    quic) BLOCK_QUIC="$_old" ;;
                    mtu) MTU_FIX="$_old" ;;
                    force) FORCE_DOH="$_old" ;;
                    dnsmasq_perf) DNSMASQ_PERF="$_old" ;;
                    ntp_clients) NTP_CLIENTS="$_old" ;;
                    client_fixes) CLIENT_FIXES="$_old" ;;
                esac
                save_config >/dev/null 2>&1 || true
            fi
            ;;
    esac

    FORCE_APPLY_SETTINGS="$_old_force"

    if [ "$_rc" -eq 0 ]; then
        case "$_state:$_module" in
            0:quic|2:quic) ok_msg "Блокировка QUIC включена." ;;
            1:quic)
                if [ "${QUIC_EXTERNAL_REMAINING:-0}" = 1 ]; then
                    info_msg "Правила DNS Manager для QUIC сняты. Блокировка QUIC остаётся активной по другому правилу (например, Zapret Manager)."
                else
                    ok_msg "Блокировка QUIC выключена, стоковое состояние восстановлено."
                fi
                ;;
            0:mtu|2:mtu) ok_msg "MTU/MSS настроено." ;;
            1:mtu) ok_msg "MTU/MSS возвращено к стоку." ;;
            0:force|2:force) ok_msg "Принудительный DNS настроен." ;;
            1:force) ok_msg "Принудительный DNS выключен, стоковое состояние восстановлено." ;;
            0:sysctl|2:sysctl) ok_msg "TCP и Conntrack настроены." ;;
            1:sysctl) ok_msg "TCP и Conntrack возвращены к стоку." ;;
            0:dnsmasq_perf|2:dnsmasq_perf) ok_msg "DNS-кэш настроен." ;;
            1:dnsmasq_perf) ok_msg "DNS-кэш возвращён к стоку." ;;
            0:ntp_clients|2:ntp_clients) ok_msg "NTP для устройств настроен." ;;
            1:ntp_clients) ok_msg "NTP для устройств выключен, стоковое состояние восстановлено." ;;
            0:client_fixes|2:client_fixes) ok_msg "Исправления телеметрии и связи настроены." ;;
            1:client_fixes) ok_msg "Исправления телеметрии и связи выключены." ;;
            0:watchdog|2:watchdog) ok_msg "Автопроверка DNS включена." ;;
            1:watchdog) ok_msg "Автопроверка DNS выключена." ;;
            0:web|2:web) ok_msg "Web-доступ включён." ;;
            1:web) ok_msg "Web-доступ выключен." ;;
        esac
    else
        case "$_module" in
            quic) err_msg "Не удалось изменить блокировку QUIC." ;;
            mtu) err_msg "Не удалось изменить исправление сетевых параметров." ;;
            force) err_msg "Не удалось изменить принудительный DNS." ;;
            sysctl) err_msg "Не удалось изменить TCP и Conntrack." ;;
            dnsmasq_perf) err_msg "Не удалось изменить кэширование DNS." ;;
            ntp_clients) err_msg "Не удалось изменить NTP для устройств." ;;
            client_fixes) err_msg "Не удалось изменить исправления телеметрии и связи." ;;
            watchdog) err_msg "Не удалось изменить автопроверку DNS." ;;
            web) err_msg "Не удалось изменить web-доступ." ;;
        esac
    fi
    pause
    return "$_rc"
}

menu_extras() {
while :; do
    menu_header "НАСТРОЙКИ"
    menu_section "СЕТЬ И ОБХОД"
    menu_item_state "[1]" "Блокировка QUIC" "$(module_state_word quic)"
    menu_item_state "[2]" "Исправление сетевых параметров / MSS" "$(module_state_word mtu)"
    menu_item_state "[3]" "Принудительный DNS" "$(module_state_word force)"
    menu_section "ПРОИЗВОДИТЕЛЬНОСТЬ"
    menu_item_state "[4]" "Оптимизация TCP и Conntrack" "$(module_state_word sysctl)"
    menu_item_state "[5]" "Кэширование DNS-запросов" "$(module_state_word dnsmasq_perf)"
    menu_section "СЕРВИСЫ И КЛИЕНТЫ"
    menu_item_state "[6]" "Время для устройств сети" "$(module_state_word ntp_clients)"
    menu_item_state "[7]" "Исправления телеметрии и связи" "$(module_state_word client_fixes)"
    menu_section "ОБСЛУЖИВАНИЕ"
    menu_item_state "[8]" "Автоматическая проверка DNS" "$(module_state_word watchdog)"
    menu_item_state "[9]" "Доступ из браузера" "$(module_state_word web)"
    menu_back
    menu_prompt
    safe_read c
    case "$c" in
        1) setting_process quic "Блокировка QUIC" "Блокируются UDP-порты 80 и 443 из LAN." ;;
        2) setting_process mtu "Исправление сетевых параметров / MSS" "MTU/MSS исправление применяется только к реальной WAN-зоне." ;;
        3) setting_process force "Принудительный DNS" "DNS TCP/UDP 53 направляется на DNS роутера; DoT TCP/UDP 853 блокируется." ;;
        4) setting_process sysctl "Оптимизация TCP и Conntrack" "Применяются параметры TCP и Conntrack." ;;
        5) setting_process dnsmasq_perf "Кэширование DNS-запросов" "Применяются параметры DNS-кэша dnsmasq." ;;
        6) setting_process ntp_clients "Время для устройств сети" "DHCP выдаёт адрес роутера как NTP-сервер, LAN UDP/123 направляется на роутер." ;;
        7) setting_process client_fixes "Исправления телеметрии и связи" "Добавляются DNS-правила для телеметрии и проверок подключения некоторых устройств." ;;
        8) setting_process watchdog "Автоматическая проверка DNS" "Watchdog запускает проверку DNS по расписанию." ;;
        9) setting_process web "Доступ из браузера" "DNS Manager доступен в LAN через web-интерфейс." ;;
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
[ -s /etc/ssl/certs/ca-certificates.crt ] && CA_OK=yes
if [ "$CA_OK" != yes ]; then
    if command -v apk >/dev/null 2>&1; then
        apk info -e ca-certificates >/dev/null 2>&1 && CA_OK=yes
        apk info -e ca-bundle >/dev/null 2>&1 && CA_OK=yes
    elif command -v opkg >/dev/null 2>&1; then
        opkg status ca-certificates 2>/dev/null | grep -q '^Status:.*installed' && CA_OK=yes
        opkg status ca-bundle 2>/dev/null | grep -q '^Status:.*installed' && CA_OK=yes
    fi
fi
[ "$CA_OK" = yes ] || missing="$missing ca-certificates"
[ "$HAS_DNSMASQ" = yes ] || missing="$missing dnsmasq"
printf '%s\n' "$missing"
}
prepare_dns_operation(){
    write_catalogs
    load_config
    cleanup_legacy_mtu_default 2>/dev/null || true
    uci commit firewall >/dev/null 2>&1 || true
    normalize_hybrid_ports 2>/dev/null || true
    restore_persistent_test_results 2>/dev/null || true
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
printf "  ${C_GREEN}✓${C_NC} 6 рабочих DNS-серверов\n"
printf "  ${C_GREEN}✓${C_NC} отдельный DNS для .ru / .su / .рф\n"
printf "  ${C_GREEN}✓${C_NC} автоматическая замена неработающих серверов\n"
printf "  ${C_GREEN}✓${C_NC} одновременная работа выбранных DNS\n"
printf "  ${C_GREEN}✓${C_NC} проверка после настройки\n"
printf "  ${C_GREEN}✓${C_NC} сохранение исходных настроек для отката\n"
printf "  ${C_GREEN}✓${C_NC} кэш DNS для более быстрых повторных запросов\n\n"
test_dns_catalog || return 1
[ -s "$TEST_RESULTS" ] || return 1
DNS_PROFILE="hybrid"
DNS_SELECTION_MODE="quick"
DNS_SELECTION_CATEGORY="bypass"
SLOT_1=""; SLOT_2=""; SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""
SLOT_RU=""; SLOT_RU_2=""
SLOT_1_CAT="bypass"; SLOT_2_CAT="bypass"; SLOT_3_CAT="bypass"
SLOT_4_CAT="bypass"; SLOT_5_CAT="bypass"; SLOT_6_CAT="bypass"
SLOT_RU_CAT="regional"; SLOT_RU_2_CAT="regional"
TLD_RU_ENABLED=1
TLD_SPLIT=1
BALANCER_ENABLED=1
WATCHDOG_ENABLED=1
DNSMASQ_PERF=1
BOOTSTRAP_DNS="$BOOTSTRAP_DNS_ALL"
PORT_1="$HYBRID_PORT_1"; PORT_2="$HYBRID_PORT_2"; PORT_3="$HYBRID_PORT_3"
PORT_4="$HYBRID_PORT_4"; PORT_5="$HYBRID_PORT_5"; PORT_6="$HYBRID_PORT_6"
PORT_RU="$HYBRID_PORT_RU"; PORT_RU_2=""
HYBRID_FORCE_RESELECT=1
   CORE_ONLY=1
    apply_settings
    _rc=$?
    CORE_ONLY=0
    HYBRID_FORCE_RESELECT=0
    if [ "$_rc" -eq 0 ] && [ "${DNSMASQ_PERF:-0}" = 1 ]; then
        apply_extras_now dnsmasq_perf || true
    fi
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
if [ -s /etc/ssl/certs/ca-certificates.crt ]; then
printf '  CA-сертификаты    : %b✓ ВКЛ%b\n' "$C_GREEN" "$C_NC"
else
printf '  CA-сертификаты    : %b✗ НЕТ%b\n' "$C_RED" "$C_NC"
fi
}
# ==========================================
# ==========================================
# ==========================================
watchdog_test_results_fresh() {
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
    [ "$(( _now - _ts ))" -le "${TEST_RESULTS_MAX_AGE:-21600}" ] 2>/dev/null || return 1
    return 0
}
ensure_test_results_fresh() {
    if watchdog_test_results_fresh; then
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
            case "$_slot" in RU|RU_2) printf '%s\n' regional ;; *) printf '%s\n' bypass ;; esac
            return 0
            ;;
        profile|manual)
            _cat=""
            eval "_cat=\${SLOT_${_slot}_CAT:-}"
            [ -n "$_cat" ] || { eval "_id=\${SLOT_${_slot}:-}"; [ -n "$_id" ] && _cat="$(dns_cat "$_id")"; }
            case "$_slot" in RU|RU_2) [ -n "$_cat" ] || _cat="regional" ;; esac
            printf '%s\n' "$_cat"
            return 0
            ;;
        *)
            _cat=""
            eval "_cat=\${SLOT_${_slot}_CAT:-}"
            [ -n "$_cat" ] || _cat="$(dns_cat "$(eval "printf '%s' \"\${SLOT_${_slot}:-}\"")")"
            case "$_slot" in RU|RU_2) [ -n "$_cat" ] || _cat="regional" ;; *) [ -n "$_cat" ] || _cat="bypass" ;; esac
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
    _changed=0
    [ "$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null)" = "-" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)" = "0" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null)" = "0" ] || _changed=1
    [ "$_changed" = 1 ] || return 0
    log_msg "Обнаружен drift настроек https-dns-proxy. Возвращаю контроль DNS Manager.."
    uci set https-dns-proxy.config.dnsmasq_config_update='-' || return 1
    uci set https-dns-proxy.config.force_dns='0' || return 1
    uci set https-dns-proxy.config.notrack_dns='0' || return 1
    uci commit https-dns-proxy || return 1
    watchdog_restart_hdp || return 1
    return 0
}
watchdog_enforce_doh_authority() {
    [ "$DNS_PROFILE" = hybrid ] || [ "$DNS_PROFILE" = custom ] || return 0
    _expected=0
    for _s in 1 2 3 4 5 6 RU RU_2; do
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
        case "$_ws" in 1) _wid="${SLOT_1:-}"; _wp="${PORT_1:-}";; 2) _wid="${SLOT_2:-}"; _wp="${PORT_2:-}";; 3) _wid="${SLOT_3:-}"; _wp="${PORT_3:-}";; 4) _wid="${SLOT_4:-}"; _wp="${PORT_4:-}";; 5) _wid="${SLOT_5:-}"; _wp="${PORT_5:-}";; 6) _wid="${SLOT_6:-}"; _wp="${PORT_6:-}";; RU) _wid="${SLOT_RU:-}"; _wp="${PORT_RU:-}";; RU_2) _wid="${SLOT_RU_2:-}"; _wp="${PORT_RU_2:-}";; esac
        [ -n "$_wid" ] || continue
        [ -n "$_wp" ] || continue
        printf '127.0.0.1#%s\n' "$_wp" >> "$_out"
    done
    if [ "${TLD_RU_ENABLED:-0}" = 1 ]; then
        if [ -n "$SLOT_RU" ] && [ -n "$PORT_RU" ]; then
            for _t in /ru /su /xn--p1ai; do printf '%s/127.0.0.1#%s\n' "$_t" "$PORT_RU" >> "$_out"; done
        fi
        if [ -n "$SLOT_RU_2" ] && [ -n "$PORT_RU_2" ]; then
            for _t in /ru /su /xn--p1ai; do printf '%s/127.0.0.1#%s\n' "$_t" "$PORT_RU_2" >> "$_out"; done
        fi
    fi
    sort -u "$_out" -o "$_out" 2>/dev/null || true
    printf '%s\n' "$_out"
}
watchdog_dns_path_guard() {
    _cfg_result="$(dns_redirect_conflict_uci 2>/dev/null || true)"
    _cfg_changed="${_cfg_result%%|*}"
    _cfg_conflict="${_cfg_result#*|}"
    case "$_cfg_changed" in 0|1) ;; *) _cfg_changed=0;; esac
    case "$_cfg_conflict" in 0|1) ;; *) _cfg_conflict=0;; esac
    if [ "$_cfg_changed" = 1 ]; then
        uci commit firewall >/dev/null 2>&1 || return 1
        reload_fw || return 1
    fi
    [ "$_cfg_conflict" = 1 ] && return 1
    if [ "$SYS_FW" = fw4 ]; then
        dns_path_conflict_nft >/dev/null 2>&1 && return 1
    elif [ "$SYS_FW" = fw3 ]; then
        dns_path_conflict_iptables >/dev/null 2>&1 && return 1
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
    for _rs in 1 2 3 4 5 6 RU RU_2; do
        eval "_rid=\${SLOT_${_rs}:-}"
        [ -n "$_rid" ] || continue
        eval "_rport=\${PORT_${_rs}:-}"
        [ -n "$_rport" ] || { _bad=1; break; }
        case "$_rs" in RU|RU_2) _rdomain="yandex.ru" ;; *) _rdomain="example.com" ;; esac
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
    for _s in 1 2 3 4 5 6 RU RU_2; do
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
        RU_2) _id="${SLOT_RU_2:-}"; _port="${PORT_RU_2:-}"; _domain="yandex.ru";;
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
    case "$_slot" in RU|RU_2) _domain="yandex.ru" ;; *) _domain="example.com" ;; esac
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
    [ "$_pref" != "${_current_id:-}" ] || return 1
    awk -F'|' -v id="$_pref" 'NF>=5 && $1==id && $5=="OK" && $4 ~ /^[0-9]+$/ {print $1;exit}' "$TEST_RESULTS" 2>/dev/null
}
watchdog_pick_replacement() {
    _slot="$1"
    _used="$2"
    _tried="$3"
    [ -s "$TEST_RESULTS" ] || return 1
    if [ "$DNS_SELECTION_MODE" = quick ]; then
        _preferred="$(watchdog_preferred_quick_candidate "$_slot")"
        if [ -n "$_preferred" ]; then
            _purl="$(normalize_url "$(dns_url "$_preferred")")"
            if [ -n "$_purl" ] && ! grep -qxF "$_purl" "$_used" 2>/dev/null && ! grep -qxF "$_preferred" "$_tried" 2>/dev/null; then
                printf '%s|bypass\n' "$_preferred"
                return 0
            fi
        fi
    fi
    watchdog_candidate_categories "$_slot" > "$TMP_DIR/watchdog-categories-$$"
    while IFS= read -r _need; do
        [ -n "$_need" ] || continue
        while IFS='|' read -r _rid _rcat _rname _rms _rst; do
            [ -n "$_rid" ] || continue
            [ "$_rst" = OK ] || continue
            case "$_rms" in ''|*[!0-9]*) continue ;; esac
            _rurl="$(normalize_url "$(dns_url "$_rid")")"
            [ -n "$_rurl" ] || continue
            grep -qxF "$_rurl" "$_used" 2>/dev/null && continue
            grep -qxF "$_rid" "$_tried" 2>/dev/null && continue
            if [ "$_rcat" = "$_need" ]; then
                printf '%s|%s\n' "$_rid" "$_rcat"
                rm -f "$TMP_DIR/watchdog-categories-$$" 2>/dev/null
                return 0
            fi
        done <<EOF_CANDIDATES
$(awk -F'|' '$1!="" && NF>=5 && $5=="OK" && $4 ~ /^[0-9]+$/ {print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n)
EOF_CANDIDATES
    done < "$TMP_DIR/watchdog-categories-$$"
    rm -f "$TMP_DIR/watchdog-categories-$$" 2>/dev/null
    return 1
}
watchdog_apply_slot_candidate() {
    _slot="$1"; _new_id="$2"; _new_cat="$3"; _old_id="$4"; _old_cat="$5"
    eval "_port=\${PORT_${_slot}:-}"
    [ -n "$_slot" ] && [ -n "$_new_id" ] || return 1
    eval "SLOT_${_slot}=\"$_new_id\""
    eval "SLOT_${_slot}_CAT=\"$_new_cat\""

    watchdog_candidate_rollback() {
        eval "SLOT_${_slot}=\"$_old_id\""
        eval "SLOT_${_slot}_CAT=\"$_old_cat\""
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
    if ! watchdog_restart_hdp; then
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
    _max="${WATCHDOG_MAX_RESTARTS:-2}"
    [ "${WATCHDOG_RESTART_COUNT:-0}" -lt "$_max" ] || {
        log_msg "Watchdog: лимит перезапусков https-dns-proxy за один цикл достигнут ($_max)."
        return 1
    }
    _now="$(date +%s 2>/dev/null)"
    _last="$(cat "$WATCHDOG_LAST_RESTART_FILE" 2>/dev/null)"
    case "$_now" in ''|*[!0-9]*) _now=0;; esac
    case "$_last" in ''|*[!0-9]*) _last=0;; esac
    if [ "$_last" -gt 0 ] && [ $((_now-_last)) -lt "${WATCHDOG_RESTART_COOLDOWN:-300}" ]; then
        return 1
    fi

    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
    WATCHDOG_RESTART_COUNT=$((WATCHDOG_RESTART_COUNT+1))
    printf '%s\n' "$_now" > "$WATCHDOG_LAST_RESTART_FILE" 2>/dev/null || true
    sleep 3
    refresh_runtime_capabilities

    _expected="$(expected_managed_slots 2>/dev/null)"
    case "$_expected" in ''|*[!0-9]*) _expected=0;; esac
    [ "$_expected" -gt 0 ] || return 0
    [ "$DOH_TOTAL" = "$_expected" ] || return 1
    [ "$HDP_RUNNING" = yes ] || return 1

    for _rs in 1 2 3 4 5 6 RU RU_2; do
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
normalize_managed_firewall_duplicates() {
    disc_network >/dev/null 2>&1 || true
    _removed=0

    # NTP: if an equivalent external redirect already exists, drop only our exact
    # manager rule. The external rule remains untouched.
    if ntp_firewall_rule_owned && firewall_owner_has "$FW_NTP_SECTION"; then
        _ext="$(firewall_find_exact_redirect "$FIREWALL_LAN_ZONE" udp 123 "$LAN_IP" 123 DNAT "$FW_NTP_SECTION" 2>/dev/null)"
        if [ -n "$_ext" ]; then
            uci -q delete "firewall.$FW_NTP_SECTION" && { firewall_owner_remove "$FW_NTP_SECTION"; _removed=1; } || true
        fi
    fi

    # Forced DNS redirect: same ownership rule.
    if firewall_section_owned_redirect "$FW_DNS_REDIRECT_SECTION" "$FIREWALL_LAN_ZONE" 'tcp udp' 53 "$LAN_IP" 53 DNAT && firewall_owner_has "$FW_DNS_REDIRECT_SECTION"; then
        _ext="$(firewall_find_exact_redirect "$FIREWALL_LAN_ZONE" 'tcp udp' 53 "$LAN_IP" 53 DNAT "$FW_DNS_REDIRECT_SECTION" 2>/dev/null)"
        if [ -n "$_ext" ]; then
            uci -q delete "firewall.$FW_DNS_REDIRECT_SECTION" && { firewall_owner_remove "$FW_DNS_REDIRECT_SECTION"; _removed=1; } || true
        fi
    fi

    # QUIC: only our deterministic manager sections are ever removable.
    if firewall_quic_rule_owned "$FW_QUIC80_SECTION" 80 2>/dev/null && firewall_owner_has "$FW_QUIC80_SECTION" && firewall_find_exact_quic 80 "$FW_QUIC80_SECTION" >/dev/null 2>&1; then
        uci -q delete "firewall.$FW_QUIC80_SECTION" && { firewall_owner_remove "$FW_QUIC80_SECTION"; _removed=1; } || true
    fi
    if firewall_quic_rule_owned "$FW_QUIC443_SECTION" 443 2>/dev/null && firewall_owner_has "$FW_QUIC443_SECTION" && firewall_find_exact_quic 443 "$FW_QUIC443_SECTION" >/dev/null 2>&1; then
        uci -q delete "firewall.$FW_QUIC443_SECTION" && { firewall_owner_remove "$FW_QUIC443_SECTION"; _removed=1; } || true
    fi

    if [ "$_removed" = 1 ]; then
        uci commit firewall >/dev/null 2>&1 || return 1
        reload_fw >/dev/null 2>&1 || return 1
        log_msg "Firewall: удалены только дубли, принадлежащие DNS Manager; внешние правила сохранены."
    fi
    return 0
}

run_watchdog() {
    [ "${WATCHDOG_ENABLED:-0}" = 1 ] || return 0
    _lock="$STATE_DIR/watchdog.lock"
    if mkdir "$_lock" 2>/dev/null; then
        printf '%s\n' "$$" > "$_lock/pid"
    else
        _pid="$(cat "$_lock/pid" 2>/dev/null)"
        if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
            log_msg "Проверка DNS пропущена: предыдущая проверка ещё работает (PID $_pid)."
            return 0
        fi
        rm -rf "$_lock" 2>/dev/null || true
        mkdir "$_lock" 2>/dev/null || return 0
        printf '%s\n' "$$" > "$_lock/pid"
    fi
    _wd_rc=0
    _wd_repairs=0
    WATCHDOG_RESTART_COUNT=0
    if ! watchdog_resource_guard; then
        rm -rf "$_lock" 2>/dev/null || true
        return 0
    fi
    if ! acquire_mutation_lock; then
        rm -rf "$_lock" 2>/dev/null || true
        return 0
    fi
    load_config
    normalize_managed_firewall_duplicates || log_msg "Firewall: не удалось безопасно убрать дубли менеджера."
    _managed_slots=0
    for _s in 1 2 3 4 5 6 RU RU_2; do
        eval "_mid=\${SLOT_${_s}:-}"
        [ -n "$_mid" ] && _managed_slots=$((_managed_slots+1))
    done
    if [ "$_managed_slots" -eq 0 ]; then
        log_msg "Watchdog: активная схема DNS Manager не настроена; сторонний https-dns-proxy не изменяю."
        release_mutation_lock
        rm -rf "$_lock" 2>/dev/null || true
        return 0
    fi
    sync_regional_dns_state
    cleanup_stale_tmp_dirs
    cleanup_transaction_history
    rotate_runtime_logs
    watchdog_enforce_hdp_control || log_msg "Не удалось полностью восстановить контроль над настройками https-dns-proxy."
    watchdog_enforce_doh_authority || log_msg "Не удалось полностью синхронизировать набор DNS Manager."
    watchdog_service_recover || log_msg "Не удалось выполнить восстановительное перезапускание https-dns-proxy."
    watchdog_hdp_guard || log_msg "Не удалось проверить соответствие DNS-серверов выбранному набору."
    watchdog_dns_path_guard || log_msg "Обнаружен конфликт пути DNS в firewall."
    watchdog_dnsmasq_guard || log_msg "Не удалось полностью восстановить конфигурацию dnsmasq."
    if ! watchdog_test_results_fresh; then
        if ! ensure_test_results_fresh; then
        log_msg "Watchdog: не удалось получить свежие результаты проверки DNS. Замена серверов запрещена."
        rm -f "$TMP_DIR"/watchdog-*-$$ 2>/dev/null || true
        rm -rf "$_lock" 2>/dev/null || true
        release_mutation_lock
        return "$_wd_rc"
    fi
fi
    _used="$TMP_DIR/watchdog-used-$$"
    : > "$_used"
    for _s in 1 2 3 4 5 6 RU RU_2; do
        eval "_uid=\${SLOT_${_s}:-}"
        [ -n "$_uid" ] || continue
        _u="$(normalize_url "$(dns_url "$_uid")")"
        [ -n "$_u" ] && printf '%s\n' "$_u" >> "$_used"
    done
    for _slot in 1 2 3 4 5 6 RU RU_2; do
        [ "$_wd_repairs" -lt "${WATCHDOG_MAX_REPAIRS:-1}" ] || break
        eval "_id=\${SLOT_${_slot}:-}"
        [ -n "$_id" ] || continue
        if [ "$_slot" = RU_2 ] && [ -z "${PORT_RU_2:-}" ]; then continue; fi
        _desired="$(watchdog_desired_cat "$_slot")"
        _current_cat="$(dns_cat "$_id")"
        _force_replace=0
        case "$_slot" in
            RU|RU_2) ;;
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
    rm -rf "$_lock" 2>/dev/null || true
    release_mutation_lock
    rotate_runtime_logs
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
watchdog_cron_legacy_count() {
    watchdog_cron_scheduler_detect
    [ -n "$WATCHDOG_CRON_FILE" ] && [ -f "$WATCHDOG_CRON_FILE" ] || { printf '0\n'; return 0; }
    awk -v mp="$MANAGER_PATH" '
        $0 ~ /^# DNS_MANAGER_WATCHDOG_SPEC=[0-9][0-9]*$/ {seen=1; next}
        seen==1 {
            if ($0 !~ /^[[:space:]]*#/ && $0 ~ mp"[[:space:]]+(watchdog|-w|--watchdog)([[:space:]]|$)") count++
            seen=0
        }
        END {print count+0}
    ' "$WATCHDOG_CRON_FILE" 2>/dev/null
}
watchdog_cron_migrate_legacy_owned_block() {
    _desired="$1"
    watchdog_cron_scheduler_detect
    [ -n "$WATCHDOG_CRON_FILE" ] && [ -f "$WATCHDOG_CRON_FILE" ] || return 1
    _count="$(watchdog_cron_legacy_count)"
    case "$_count" in ''|*[!0-9]*) _count=0;; esac
    [ "$_count" -eq 1 ] || return 1
    _cron_before="$(file_hash "$WATCHDOG_CRON_FILE" 2>/dev/null)"
    _tmp="$WATCHDOG_CRON_FILE.dns-manager.$$"
    awk -v mp="$MANAGER_PATH" -v marker="$WATCHDOG_CRON_MARKER" -v desired="$_desired" '
        $0 ~ /^# DNS_MANAGER_WATCHDOG_SPEC=[0-9][0-9]*$/ && !replaced {
            old_marker=$0; seen=1; next
        }
        seen==1 {
            if ($0 !~ /^[[:space:]]*#/ && $0 ~ mp"[[:space:]]+(watchdog|-w|--watchdog)([[:space:]]|$)") {
                print marker
                print desired
                seen=0
                replaced=1
                next
            }
            print old_marker
            print
            old_marker=""
            seen=0
            next
        }
        {print}
        END {if (seen==1 && old_marker!="") print old_marker}
    ' "$WATCHDOG_CRON_FILE" > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 1; }
    watchdog_cron_preserve_attrs "$WATCHDOG_CRON_FILE" "$_tmp"
    watchdog_cron_atomic_replace "$WATCHDOG_CRON_FILE" "$_tmp" "$_cron_before"
    _ar=$?
    [ "$_ar" -eq 0 ] || { rm -f "$_tmp" 2>/dev/null || true; return "$_ar"; }
    return 0
}
watchdog_cron_remove_legacy_owned_block() {
    watchdog_cron_scheduler_detect
    [ -n "$WATCHDOG_CRON_FILE" ] && [ -f "$WATCHDOG_CRON_FILE" ] || return 0
    _count="$(watchdog_cron_legacy_count)"
    case "$_count" in ''|*[!0-9]*) _count=0;; esac
    [ "$_count" -eq 1 ] || return 0
    _cron_before="$(file_hash "$WATCHDOG_CRON_FILE" 2>/dev/null)"
    _tmp="$WATCHDOG_CRON_FILE.dns-manager.$$"
    awk -v mp="$MANAGER_PATH" '
        $0 ~ /^# DNS_MANAGER_WATCHDOG_SPEC=[0-9][0-9]*$/ && !removed {
            old_marker=$0; seen=1; next
        }
        seen==1 {
            if ($0 !~ /^[[:space:]]*#/ && $0 ~ mp"[[:space:]]+(watchdog|-w|--watchdog)([[:space:]]|$)") {
                seen=0
                old_marker=""
                removed=1
                next
            }
            print old_marker
            print
            old_marker=""
            seen=0
            next
        }
        {print}
        END {if (seen==1 && old_marker!="") print old_marker}
    ' "$WATCHDOG_CRON_FILE" > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 1; }
    if ! cmp -s "$_tmp" "$WATCHDOG_CRON_FILE" 2>/dev/null; then
        watchdog_cron_preserve_attrs "$WATCHDOG_CRON_FILE" "$_tmp"
        watchdog_cron_atomic_replace "$WATCHDOG_CRON_FILE" "$_tmp" "$_cron_before"
        _ar=$?
        [ "$_ar" -eq 0 ] || { rm -f "$_tmp" 2>/dev/null || true; return "$_ar"; }
        watchdog_cron_scheduler_apply >/dev/null 2>&1 || true
    else
        rm -f "$_tmp" 2>/dev/null || true
    fi
    return 0
}
watchdog_cron_remove_owned_block() {
    watchdog_cron_scheduler_detect
    [ -n "$WATCHDOG_CRON_FILE" ] && [ -f "$WATCHDOG_CRON_FILE" ] || { rm -f "$WATCHDOG_CRON_STATE" 2>/dev/null || true; return 0; }
    watchdog_cron_read_state
    _state_line="${WATCHDOG_CRON_STATE_LINE:-}"
    if watchdog_cron_marker_exists; then
        if [ -n "$_state_line" ] && watchdog_cron_owned_block_status "$_state_line"; then
            _cron_before="$(file_hash "$WATCHDOG_CRON_FILE" 2>/dev/null)"
            _tmp="$WATCHDOG_CRON_FILE.dns-manager.$$"
            awk -v marker="$WATCHDOG_CRON_MARKER" -v state_line="$_state_line" '
                $0==marker {skip=1; next}
                skip==1 {
                    if ($0==state_line) {skip=0; next}
                    print marker
                    print
                    skip=0
                    next
                }
                {print}
            ' "$WATCHDOG_CRON_FILE" > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 1; }
            watchdog_cron_preserve_attrs "$WATCHDOG_CRON_FILE" "$_tmp"
            watchdog_cron_atomic_replace "$WATCHDOG_CRON_FILE" "$_tmp" "$_cron_before"
            _ar=$?
            [ "$_ar" -eq 0 ] || { rm -f "$_tmp" 2>/dev/null || true; return "$_ar"; }
            rm -f "$WATCHDOG_CRON_STATE" 2>/dev/null || true
            watchdog_cron_scheduler_apply >/dev/null 2>&1 || true
            return 0
        fi
        log_msg "Cron: запись DNS Manager была изменена. Не удаляю изменённую запись."
        return 2
    fi
    rm -f "$WATCHDOG_CRON_STATE" 2>/dev/null || true
    watchdog_cron_remove_legacy_owned_block || true
    return 0
}
watchdog_cron_sync() {
    watchdog_cron_scheduler_detect
    if [ "${WATCHDOG_ENABLED:-0}" = 1 ]; then
        watchdog_cron_scheduler_require || return 1
        watchdog_cron_file_prepare || return 1
        watchdog_cron_scheduler_start || return 1
    else
        [ -n "$WATCHDOG_CRON_FILE" ] || { rm -f "$WATCHDOG_CRON_STATE" 2>/dev/null || true; return 0; }
        if [ ! -f "$WATCHDOG_CRON_FILE" ]; then
            rm -f "$WATCHDOG_CRON_STATE" 2>/dev/null || true
            return 0
        fi
    fi

    f="$WATCHDOG_CRON_FILE"
    if [ ! -f "$f" ] && [ "${WATCHDOG_ENABLED:-0}" = 1 ]; then
        mkdir -p "$WATCHDOG_CRON_DIR" 2>/dev/null || return 1
        (umask 077; : > "$f") || return 1
        chmod 600 "$f" 2>/dev/null || true
        chown root:root "$f" 2>/dev/null || true
    fi
    if [ ! -f "$f" ]; then
        return 0
    fi

    if [ "${DNS_PROFILE:-}" = "hybrid" ]; then
        WATCHDOG_ENABLED=1
    fi
    _interval="${WATCHDOG_INTERVAL:-15}"
    case "$_interval" in ''|*[!0-9]*) _interval=15;; esac
    [ "$_interval" -ge 1 ] 2>/dev/null || _interval=15
    [ "$_interval" -le 59 ] 2>/dev/null || _interval=59
    WATCHDOG_INTERVAL="$_interval"
    _desired="$(watchdog_cron_desired_line)"
    watchdog_cron_read_state

    if [ "${WATCHDOG_ENABLED:-0}" = 1 ]; then
        if watchdog_cron_legacy_count | grep -q '^1$' && ! watchdog_cron_marker_exists; then
            if watchdog_cron_migrate_legacy_owned_block "$_desired"; then
                watchdog_cron_write_state owned "$_desired" || return 1
                watchdog_cron_scheduler_apply >/dev/null 2>&1 || return 1
                return 0
            fi
            log_msg "Cron: обнаружена старая запись DNS Manager, но безопасная миграция не выполнена. Чужие записи не изменяю."
            watchdog_cron_write_state conflict "" || true
            return 2
        fi
        if watchdog_cron_owned_block_status "$_desired"; then
            watchdog_cron_write_state owned "$_desired" || return 1
            return 0
        fi
        if watchdog_cron_marker_exists; then
            if [ -n "${WATCHDOG_CRON_STATE_LINE:-}" ] && watchdog_cron_owned_block_status "$WATCHDOG_CRON_STATE_LINE"; then
                _old_line="$WATCHDOG_CRON_STATE_LINE"
                _cron_before="$(file_hash "$f" 2>/dev/null)"
                _tmp="${f}.dns-manager.$$"
                awk -v marker="$WATCHDOG_CRON_MARKER" -v old_line="$_old_line" -v new_line="$_desired" '
                    $0==marker {print; seen=1; next}
                    seen==1 {
                        if ($0==old_line) {print new_line; seen=0; next}
                        print
                        seen=0
                        next
                    }
                    {print}
                ' "$f" > "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 1; }
                watchdog_cron_preserve_attrs "$f" "$_tmp"
                watchdog_cron_atomic_replace "$f" "$_tmp" "$_cron_before"
                _ar=$?
                [ "$_ar" -eq 0 ] || { rm -f "$_tmp" 2>/dev/null || true; return "$_ar"; }
                watchdog_cron_write_state owned "$_desired" || return 1
                watchdog_cron_scheduler_apply >/dev/null 2>&1 || return 1
                return 0
            fi
            log_msg "Cron: управляемая запись DNS Manager изменена. Не перезаписываю чужие изменения."
            watchdog_cron_write_state conflict "${WATCHDOG_CRON_STATE_LINE:-}" || true
            return 2
        fi
        if watchdog_cron_line_exists "$_desired"; then
            watchdog_cron_write_state external "$_desired" || return 1
            return 0
        fi

        _cron_before="$(file_hash "$f" 2>/dev/null)"
        _tmp="${f}.dns-manager.$$"
        cp -p "$f" "$_tmp" 2>/dev/null || return 1
        {
            printf '%s\n' "$WATCHDOG_CRON_MARKER"
            printf '%s\n' "$_desired"
        } >> "$_tmp" 2>/dev/null || { rm -f "$_tmp"; return 1; }
        watchdog_cron_atomic_replace "$f" "$_tmp" "$_cron_before"
        _ar=$?
        [ "$_ar" -eq 0 ] || { rm -f "$_tmp" 2>/dev/null || true; return "$_ar"; }
        watchdog_cron_write_state owned "$_desired" || return 1
        watchdog_cron_scheduler_apply >/dev/null 2>&1 || return 1
        return 0
    fi

    watchdog_cron_remove_owned_block
    _rc=$?
    case "$_rc" in
        0) return 0;;
        2) return 2;;
        *) return "$_rc";;
    esac
}
apply_watchdog() {
    apply_wait_message "$( [ "${WATCHDOG_ENABLED:-0}" = 1 ] && printf '%s' 'Настраиваю автопроверку DNS и cron' || printf '%s' 'Отключаю автопроверку DNS и cron' )"
    watchdog_cron_sync
    _rc=$?
    case "$_rc" in
        0)
            if [ "${WATCHDOG_ENABLED:-0}" = 1 ] && [ "${WATCHDOG_CRON_BOOT_ENABLED:-unknown}" = no ]; then
                warn_msg "Cron работает, но не включён в автозапуск. DNS Manager не включает общий cron автоматически, чтобы не менять чужую политику запуска."
            fi
            ;;
        2)
            warn_msg "Cron автопроверки изменён вручную/внешним сервисом. Чужие записи сохранены, DNS Manager их не перезаписывает."
            ;;
        *)
            err_msg "Не удалось безопасно синхронизировать cron автопроверки. Чужие записи cron не изменены."
            return 1
            ;;
    esac
    save_config || return 1
    if [ "${WATCHDOG_ENABLED:-0}" = 1 ]; then
        ok_msg "Автопроверка DNS обновлена: каждые ${WATCHDOG_INTERVAL} минут."
    else
        ok_msg "Автопроверка DNS выключена."
    fi
    return 0
}

# ==========================================
# ==========================================
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
migrate_legacy_manager_files || { err_msg "Не удалось объединить старые файлы DNS Manager в единый namespace."; exit 1; }
main_menu() {
MAIN_STATE_STALE=1
while :; do
if [ "${MAIN_STATE_STALE:-1}" = 1 ]; then
    run_discovery
    MAIN_STATE_STALE=0
fi
menu_header "DNS Manager $VERSION"
menu_section "СОСТОЯНИЕ РОУТЕРА"
printf "  ${C_YELLOW}${C_BOLD}IPv4${C_NC}               %b\n" "$(state_word "$IPV4_ROUTE")"
printf "  ${C_YELLOW}${C_BOLD}IPv6${C_NC}               %b\n" "$(state_word "$IPV6_ROUTE")"
printf "  ${C_YELLOW}${C_BOLD}dnsmasq${C_NC}            %b\n" "$(state_word "$DNSMASQ_RUN")"
printf "  ${C_YELLOW}${C_BOLD}Защищённый DNS${C_NC}     %b\n" "$(state_word "$HDP_RUNNING")"
printf "  ${C_YELLOW}${C_BOLD}DNS-серверов найдено${C_NC} %s\n" "$DOH_TOTAL"
printf "  ${C_YELLOW}${C_BOLD}Каталог DNS${C_NC}        ${C_CYAN}%s • %s серверов${C_NC}\n" "$(dns_catalog_version)" "$(count_dns)"
printf "  ${C_YELLOW}${C_BOLD}Автопроверка${C_NC}       %b\n" "$(module_state_word watchdog "$WATCHDOG_ENABLED")"
[ -s "$BASELINE_MANIFEST" ] && printf "  ${C_YELLOW}${C_BOLD}Исходная копия${C_NC}    ${C_GREEN}есть${C_NC}\n" || printf "  ${C_YELLOW}${C_BOLD}Исходная копия${C_NC}    ${C_YELLOW}нет${C_NC}\n"
printf "  ${C_YELLOW}${C_BOLD}Web-доступ${C_NC}         %b\n" "$(module_state_word web "$WEB_ACCESS_ENABLED")"
[ "$FORCE_DNS" = 1 ] && printf "  ${C_YELLOW}${C_BOLD}Принудительный DNS${C_NC} ${C_CYAN}включён${C_NC}\n"
menu_section "НАСТРОЙКА DNS"
menu_item "[1]" "Настроить DNS"
menu_section "СЕРВИСЫ"
menu_item "[2]" "Проверка DNS-серверов"
menu_item "[3]" "Состояние и журнал"
menu_item "[4]" "Серверы точного времени"
menu_item "[5]" "НАСТРОЙКИ"
menu_item "[6]" "Удалить изменения"
menu_back
menu_prompt
safe_read c
[ -z "$c" ] && { clear_screen; printf "${C_GREEN}DNS Manager завершён.${C_NC}\n"; exit 0; }
case "$c" in
1) MAIN_STATE_STALE=1; prepare_dns_operation || { pause; continue; }; menu_dns;;
2) test_dns_catalog; show_tests;;
3) show_map;;
4) MAIN_STATE_STALE=1; prepare_dns_operation || { pause; continue; }; menu_ntp;;
5) MAIN_STATE_STALE=1; prepare_dns_operation || { pause; continue; }; menu_extras;;
6) MAIN_STATE_STALE=1;
clear_screen
menu_header "УДАЛЕНИЕ ИЗМЕНЕНИЙ"
warn_msg "Будут удалены только изменения DNS Manager."
if confirm_action "Удалить изменения?"; then rollback_ours; else info_msg "Отменено."; fi
;;
*) warn_msg "Неизвестный пункт."; pause;;
esac
done
}
# ==========================================
expected_managed_slots() {
    _n=0
    for _s in 1 2 3 4 5 6 RU RU_2; do
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
                eval "PORT_${_s}=\"$_want\""
                _changed=1
            fi
        elif [ -n "$_cur" ]; then
            eval "PORT_${_s}=''"
            _changed=1
        fi
    done

    if [ -n "${SLOT_RU_2:-}" ]; then
        _want="$(hybrid_desired_port RU_2)"
        if [ "${PORT_RU_2:-}" != "$_want" ]; then
            PORT_RU_2="$_want"
            _changed=1
        fi
    elif [ -n "${PORT_RU_2:-}" ]; then
        PORT_RU_2=""
        _changed=1
    fi

    if [ "$_changed" = 1 ]; then
        save_config >/dev/null 2>&1 || true
    fi

    return 0
}

restore_persistent_test_results() {
    mkdir -p "$BASE_DIR/state" 2>/dev/null || return 0

    _cur_cat_ver="$(dns_catalog_version 2>/dev/null)"
    _saved_cat_ver="$(sed -n 's/^catalog_version=//p' "$BASE_DIR/state/dns-test-results.meta" 2>/dev/null | head -n1)"

    if [ -n "$_cur_cat_ver" ] && [ -n "$_saved_cat_ver" ] && [ "$_cur_cat_ver" != "$_saved_cat_ver" ]; then
        return 0
    fi

    if [ ! -s "$TEST_RESULTS" ] && [ -s "$BASE_DIR/state/dns-test-results.conf" ]; then
        cp -f "$BASE_DIR/state/dns-test-results.conf" "$TEST_RESULTS" 2>/dev/null || true
    fi

    if [ ! -s "$TEST_RESULTS_META" ] && [ -s "$BASE_DIR/state/dns-test-results.meta" ]; then
        cp -f "$BASE_DIR/state/dns-test-results.meta" "$TEST_RESULTS_META" 2>/dev/null || true
    fi

    return 0
}

save_persistent_test_results() {
    mkdir -p "$BASE_DIR/state" 2>/dev/null || return 0

    if [ -s "$TEST_RESULTS" ]; then
        cp -f "$TEST_RESULTS" "$BASE_DIR/state/dns-test-results.conf" 2>/dev/null || true
    fi

    if [ -s "$TEST_RESULTS_META" ]; then
        cp -f "$TEST_RESULTS_META" "$BASE_DIR/state/dns-test-results.meta" 2>/dev/null || true
    fi

    return 0
}

startup_self_repair() {
    [ "${DNS_MANAGER_NO_STARTUP_REPAIR:-0}" = 1 ] && return 0

    case "${DNS_PROFILE:-}" in
        hybrid|custom) ;;
        *) return 0 ;;
    esac

    normalize_hybrid_ports
    restore_persistent_test_results

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

            uci -q get "dhcp.$_sec.server" 2>/dev/null | tr ' ' '
' | sed '/^$/d' | sort -u > "$_act"

            if [ -s "$_exp" ] && ! cmp -s "$_act" "$_exp" 2>/dev/null; then
                _need=1
            fi

            rm -f "$_act" "$_exp" 2>/dev/null
        fi
    fi

    [ "$_need" = 1 ] || return 0

    log_msg "Startup: обнаружено расхождение конфигурации. Выполняю автоматическое восстановление."

    rm -f "$WATCHDOG_LAST_RESTART_FILE" 2>/dev/null || true

    if acquire_mutation_lock; then
        normalize_managed_firewall_duplicates || true
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
        WATCHDOG_ENABLED=1
        run_watchdog >/dev/null 2>&1 || true
        run_discovery >/dev/null 2>&1 || true
    fi

    return 0
}

# ==========================================
# ==========================================
case "${1:-}" in
update-check|--update-check)
    preflight_readonly
    init_dirs
    write_catalogs >/dev/null 2>&1 || true
    load_config
    DNS_MANAGER_FORCE_UPDATE=1 DNS_MANAGER_UPDATE_NO_EXEC=1 auto_update_manager --force
    exit 0
    ;;
auto-update|--auto-update)
    preflight_readonly
    init_dirs
    DNS_MANAGER_SCHEDULED_UPDATE=1 DNS_MANAGER_UPDATE_NO_EXEC=1 auto_update_manager --scheduled
    exit 0
    ;;
watchdog|--watchdog|-w)
    preflight_readonly
    init_dirs
    DNS_MANAGER_SCHEDULED_UPDATE=1 DNS_MANAGER_UPDATE_REEXEC_COMMAND=watchdog auto_update_manager --scheduled
    write_catalogs >/dev/null 2>&1 || true
    load_config
    normalize_hybrid_ports 2>/dev/null || true
    normalize_ownership_snapshot 2>/dev/null || true
    restore_persistent_test_results 2>/dev/null || true
    refresh_runtime_capabilities

    if [ "${DNS_PROFILE:-}" = "hybrid" ]; then
        WATCHDOG_ENABLED=1
    fi

    log_msg "Запуск автоматической проверки DNS."
    run_watchdog
    exit $?
    ;;
esac

preflight_readonly
init_dirs
auto_update_manager
write_catalogs
load_config
cleanup_legacy_mtu_default 2>/dev/null || true
uci commit firewall >/dev/null 2>&1 || true
normalize_hybrid_ports 2>/dev/null || true
normalize_ownership_snapshot 2>/dev/null || true
restore_persistent_test_results 2>/dev/null || true

if [ "${DNS_PROFILE:-}" = "hybrid" ]; then
    WATCHDOG_ENABLED=1
fi

run_discovery
firewall_cleanup_legacy_web_rule >/dev/null 2>&1 || true
uci commit firewall >/dev/null 2>&1 || true

if [ "${DNS_MANAGER_NO_INSTALL:-0}" != 1 ]; then
    install_missing_dependencies >/dev/null 2>&1 || warn_msg "Не удалось автоматически установить все зависимости. Проверь пакеты вручную."
    run_discovery
fi

if acquire_mutation_lock; then
    if ! apply_watchdog; then
        release_mutation_lock
        err_msg "Не удалось синхронизировать cron для автопроверки DNS."
        exit 1
    fi
    release_mutation_lock
else
    err_msg "Не удалось получить блокировку для синхронизации watchdog."
    exit 1
fi

if [ "${_had_dns_profile:-1}" = 0 ]; then
    hybrid_set_defaults
    save_config
    printf "${C_YELLOW}ℹ Обнаружена старая конфигурация без профиля. Создан основной профиль Гибридный DNS (без изменения настроек роутера).${C_NC}
"
fi

run_discovery
startup_self_repair

printf "${C_GREEN}✓ Первый проход завершён.${C_NC}
"
printf "${C_YELLOW}ℹ DNS-серверов в списке: %s.${C_NC}
" "$(count_dns)"

log_msg "Запуск DNS Manager. Версия $VERSION. OpenWrt=$SYS_OWRT; платформа=$SYS_TARGET; архитектура=$SYS_ARCH; firewall=$SYS_FW; backend=$FIREWALL_BACKEND"

main_menu
