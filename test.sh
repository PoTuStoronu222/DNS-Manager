#!/bin/sh
MANAGER_PATH="/usr/bin/dns-manager"
# ==========================================
# ==========================================
VERSION="1.82"
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
PREV_DNSMASQ="$CFG_DIR/dnsmasq-previous.conf"
PREV_SERVICES="$CFG_DIR/services-previous.conf"
BASELINE_DIR="$BASE_DIR/baseline"
BASELINE_MANIFEST="$BASELINE_DIR/manifest"
BASELINE_LAST="$BASELINE_DIR/last-applied.manifest"
BASELINE_META="$BASELINE_DIR/meta"
OWNERSHIP="$STATE_DIR/ownership.conf"
TEST_RESULTS="$STATE_DIR/dns-test-results.conf"
WEB_INIT="/etc/init.d/dns-manager-web"
WEB_ACCESS_PORT="7682"
WEB_ACCESS_ENABLED=0
cleanup_stale_tmp_dirs() {
    _self_tmp="${TMP_DIR:-}"
    find /tmp -maxdepth 1 -type d -name 'dnsmgr.*' -mtime +1 -print 2>/dev/null | while IFS= read -r _old_dir; do
        [ -n "$_old_dir" ] || continue
        [ "$_old_dir" = "$_self_tmp" ] && continue
        case "$_old_dir" in
            /tmp/dnsmgr.[A-Za-z0-9._-]*) ;;
            *) continue ;;
        esac
        rm -rf "$_old_dir" 2>/dev/null || true
    done
}
TMP_DIR="$(mktemp -d /tmp/dnsmgr.XXXXXX 2>/dev/null || { d="/tmp/dnsmgr.$$"; mkdir -p "$d"; printf "%s" "$d"; })"
cleanup_stale_tmp_dirs
TX_ID="$(date +%Y%m%d-%H%M%S)-$$"
TX_DIR="$STATE_DIR/tx-$TX_ID"
TX_ACTIVE=0
TX_RESERVED_PORTS=""
TX_PRE_SLOTS=""
CORE_ONLY=0
cleanup_runtime() {
    for _pid in ${STAGE_PIDS:-}; do
        [ -n "$_pid" ] || continue
        kill "$_pid" 2>/dev/null || true
    done
    sleep 1 2>/dev/null || true
    for _pid in ${STAGE_PIDS:-}; do
        [ -n "$_pid" ] || continue
        kill -9 "$_pid" 2>/dev/null || true
    done
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
        split(a, x, "\\."); split(b, y, "\\.");
        ma=(x[1]=="" ? 0 : x[1]+0); mb=(y[1]=="" ? 0 : y[1]+0);
        if (ma > mb) exit 0;
        if (ma < mb) exit 1;
        a12=ma + (x[2]=="" ? 0 : (x[2]+0)/10^(length(x[2])));
        b12=mb + (y[2]=="" ? 0 : (y[2]+0)/10^(length(y[2])));
        if (a12 > b12) exit 0;
        if (a12 < b12) exit 1;
        for (i=3; i<=10; i++) {
            va=(x[i]=="" ? 0 : x[i]+0); vb=(y[i]=="" ? 0 : y[i]+0);
            if (va > vb) exit 0;
            if (va < vb) exit 1;
        }
        exit 1;
    }'
}
auto_update_manager() {
[ "$#" -eq 0 ] || return 0
[ "${DNS_MANAGER_NO_UPDATE:-0}" = "1" ] && return 0
[ "$0" = "$MANAGER_PATH" ] || return 0
[ -f "$MANAGER_PATH" ] || return 0
[ -w "${MANAGER_PATH%/*}" ] || return 0
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 || return 0
_upd_tmp="/tmp/dns-manager-update-$$"
rm -f "$_upd_tmp" 2>/dev/null
if command -v curl >/dev/null 2>&1; then
  curl -fsSL --connect-timeout 4 --max-time 15 -o "$_upd_tmp" "$UPDATE_URL" >/dev/null 2>&1
else
  wget -q -T 15 -O "$_upd_tmp" "$UPDATE_URL" >/dev/null 2>&1
fi
if [ ! -s "$_upd_tmp" ]; then
  printf "${C_CYAN}ℹ Проверка обновления: источник недоступен. Запуск продолжается.${C_NC}\n"
  rm -f "$_upd_tmp" 2>/dev/null; return 0
fi
head -n 1 "$_upd_tmp" 2>/dev/null | grep -q '^#!/bin/sh' || { rm -f "$_upd_tmp"; return 0; }
_new_version="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$_upd_tmp" 2>/dev/null | head -n1)"
if [ -z "$_new_version" ]; then rm -f "$_upd_tmp"; return 0; fi
sh -n "$_upd_tmp" 2>/dev/null || { rm -f "$_upd_tmp"; return 0; }
if [ "$_new_version" = "$VERSION" ]; then
  printf "${C_GREEN}✓ Проверка обновления: версия %s актуальна.${C_NC}\n" "$VERSION"
  rm -f "$_upd_tmp" 2>/dev/null; return 0
fi
if ! _ver_newer "$_new_version" "$VERSION"; then
  printf "${C_CYAN}ℹ Версия %s не новее установленной %s. Обновление не требуется.${C_NC}\n" "$_new_version" "$VERSION"
  rm -f "$_upd_tmp" 2>/dev/null; return 0
fi
printf "${C_PINK}↻ Доступна версия %s. Обновление...${C_NC}\n" "$_new_version"
if cp -f "$_upd_tmp" "$MANAGER_PATH" 2>/dev/null && chmod 755 "$MANAGER_PATH" 2>/dev/null; then
  rm -f "$_upd_tmp" 2>/dev/null
  printf "${C_GREEN}✓ Диспетчер DNS обновлён: %s → %s${C_NC}\n" "$VERSION" "$_new_version"
  mkdir -p "$STATE_DIR" 2>/dev/null
  log_msg "Обновление $VERSION -> $_new_version"
  DNS_MANAGER_NO_UPDATE=1 exec "$MANAGER_PATH"
fi
printf "${C_YELLOW}! Не удалось заменить %s. Запуск продолжается на %s.${C_NC}\n" "$MANAGER_PATH" "$VERSION"
rm -f "$_upd_tmp" 2>/dev/null
return 0
}
# ==========================================
# ==========================================
log_msg() {
mkdir -p "$BASE_DIR" "$STATE_DIR" 2>/dev/null
printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null
}
log_tx() {
printf 'TX|%s|%s|%s|%s|%s|%s\n' "$TX_ID" "$(date +%s)" "$1" "$2" "$3" "$4" "$5" >> "$TX_LOG" 2>/dev/null
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
    printf "  ${C_GREEN}[✓] Y / y  или  Н / н — Да, применить${C_NC}\n"
    printf "  ${C_RED}[✗] N / n  или  Т / т — Нет, назад${C_NC}\n"
    printf "  ${C_WHITE}[Enter] — отмена / назад${C_NC}\n"
    menu_prompt
    safe_read _ans
    case "$_ans" in
        y|Y|н|Н|yes|YES|да|Да|ДА) return 0 ;;
        n|N|т|Т|no|NO|нет|Нет|НЕТ|"") return 1 ;;
        *) warn_msg "Неверный выбор. Используйте Y/Н — Да или N/Т — Нет."; return 1 ;;
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
}
# ==========================================
# ==========================================
baseline_files() {
printf '%s\n'  /etc/config/dhcp  /etc/config/https-dns-proxy  /etc/config/firewall  /etc/config/system  /etc/sysctl.d/90-dns-manager.conf  /etc/sysctl.d/91-dns-manager-extended.conf  /etc/dnsmasq.d/90-dns-manager-bogus.conf  /etc/dnsmasq.d/91-dns-manager-client-fixes.conf  /etc/hotplug.d/iface/99-dns-manager-tailscale  /etc/crontabs/root  /etc/init.d/tg-ws-proxy-go  /etc/init.d/tailscale  /etc/init.d/dns-manager-web
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
        warn_msg "Исходное состояние изменилось после последнего применения. Выполняю только безопасное удаление изменений диспетчера DNS."
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
    rm -f "$TEST_RESULTS"
    printf '%s\n' "$DNSCAT_VERSION" > "$STATE_DIR/dns-catalog.version" 2>/dev/null
fi
}
# ==========================================
# ==========================================
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
: "${NTP_IP_FALLBACK:=1}"; : "${SYSCTL_TUNING:=0}"; : "${GO_OPTIMIZE:=0}"; : "${DNSMASQ_PERF:=0}"; : "${NTP_CLIENTS:=0}"; : "${CLIENT_FIXES:=0}"; : "${SYSCTL_EXTENDED:=0}"; : "${TAILSCALE_HOTPLUG:=0}"; : "${CRON_CLEANUP:=0}"
: "${BALANCER_ENABLED:=1}"; : "${NTP_PRESET:=cf_ip}"; : "${DNS_PROFILE:=hybrid}"; : "${DNS_SELECTION_MODE:=quick}"; : "${DNS_SELECTION_CATEGORY:=bypass}"
: "${QUICK_PREF_1:=}"; : "${QUICK_PREF_2:=}"; : "${QUICK_PREF_3:=}"; : "${QUICK_PREF_4:=}"; : "${QUICK_PREF_5:=}"; : "${QUICK_PREF_6:=}"
: "${WATCHDOG_ENABLED:=1}"; : "${WATCHDOG_INTERVAL:=15}"
: "${WEB_ACCESS_ENABLED:=0}"; : "${WEB_ACCESS_PORT:=7682}"
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
}
save_config() {
umask 077
cat > "$CONFIG_FILE" <<EOF_CFG
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
GO_OPTIMIZE="$GO_OPTIMIZE"
FORCE_DOH="$FORCE_DOH"
DNSMASQ_PERF="$DNSMASQ_PERF"
NTP_CLIENTS="$NTP_CLIENTS"
CLIENT_FIXES="$CLIENT_FIXES"
SYSCTL_EXTENDED="$SYSCTL_EXTENDED"
TAILSCALE_HOTPLUG="$TAILSCALE_HOTPLUG"
CRON_CLEANUP="$CRON_CLEANUP"
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
}
# ==========================================
# ==========================================
disc_system() {
HAS_DNSMASQ="no"; command -v dnsmasq >/dev/null 2>&1 && HAS_DNSMASQ="yes"
SYS_FW="fw3"
if command -v fw4 >/dev/null 2>&1 || [ -x /sbin/fw4 ] || [ -x /usr/sbin/fw4 ] || [ -f /usr/share/fw4/main.uc ] || [ -f /usr/share/fw4/helpers.sh ]; then
SYS_FW="fw4"
fi
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
LAN_IP="$(ip -4 addr 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | awk '/^192\.|^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\./{print; exit}')"
[ -n "$LAN_IP" ] || LAN_IP="$(uci -q get network.lan.ipaddr 2>/dev/null | cut -d/ -f1 | head -n1)"
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
disc_dns() {
DNSMASQ_RUN="no"; if /etc/init.d/dnsmasq status >/dev/null 2>&1; then DNSMASQ_RUN="yes"; elif pgrep -x dnsmasq >/dev/null 2>&1; then DNSMASQ_RUN="yes"; fi
DOH_INV="$TMP_DIR/doh_inventory"; : > "$DOH_INV"
DOH_TOTAL=0; DOH_OURS=0; DOH_FOREIGN=0; DOH_UNKNOWN=0
FORCE_DNS="$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)"
i=0
while uci -q get "https-dns-proxy.@https-dns-proxy[$i]" >/dev/null 2>&1; do
p="$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].listen_port" 2>/dev/null)"
a="$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].listen_addr" 2>/dev/null)"
u="$(normalize_url "$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].resolver_url" 2>/dev/null)")"
m="$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].dns_manager" 2>/dev/null)"
[ "$m" = 1 ] && owner="OURS" || owner="UNKNOWN"
running="no"
if [ -n "$p" ] && [ -s "$LISTENERS" ] && grep -qE "(:|\])$p([[:space:]]|$)" "$LISTENERS" 2>/dev/null; then running="yes"; fi
[ "$owner" = UNKNOWN ] && [ "$running" = yes ] && owner="FOREIGN"
[ "$owner" = OURS ] && DOH_OURS=$((DOH_OURS+1))
[ "$owner" = FOREIGN ] && DOH_FOREIGN=$((DOH_FOREIGN+1))
[ "$owner" = UNKNOWN ] && DOH_UNKNOWN=$((DOH_UNKNOWN+1))
printf '%s|%s|%s|%s|%s|%s\n' "$i" "$p" "$owner" "$a" "$running" "$u" >> "$DOH_INV"
i=$((i+1)); DOH_TOTAL=$((DOH_TOTAL+1))
done
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
OTHER_TAILSCALE="no"; [ -x /etc/init.d/tailscale ] && OTHER_TAILSCALE="yes"
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
HAS_TAILSCALE="$OTHER_TAILSCALE"
}
# ==========================================
# ==========================================
dns_redirect_conflict_uci() {
    _changed=0
    _secs="$(uci show firewall 2>/dev/null | sed -n "s/^firewall\.\([^.=]*\)=redirect$/\1/p")"
    for _sec in $_secs; do
        [ "$(uci -q get "firewall.$_sec.src" 2>/dev/null)" = "lan" ] || continue
        _sd="$(uci -q get "firewall.$_sec.src_dport" 2>/dev/null)"
        printf '%s' "$_sd" | tr ' ' '\n' | grep -qxF '53' || continue
        _target="$(uci -q get "firewall.$_sec.target" 2>/dev/null)"
        case "$_target" in DNAT|dnat|REDIRECT|redirect) ;; *) continue ;; esac
        _dp="$(uci -q get "firewall.$_sec.dest_port" 2>/dev/null)"
        [ -n "$_dp" ] || continue
        case "$_dp" in
            53|53-53) continue ;;
        esac
        _disabled="$(uci -q get "firewall.$_sec.disabled" 2>/dev/null)"
        [ "$_disabled" = 1 ] && continue
        uci set "firewall.$_sec.disabled=1" || return 1
        _changed=1
    done
    printf '%s\n' "$_changed"
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
prepare_dns_path() {
    _cfg_changed="$(dns_redirect_conflict_uci 2>/dev/null || printf 0)"
    [ "$_cfg_changed" = 1 ] && uci commit firewall >/dev/null 2>&1 || true
    [ "$_cfg_changed" = 1 ] && reload_fw || true
    if dns_path_conflict_nft >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
disc_firewall() {
    QUIC_OURS=0
    QUIC_FOREIGN=0
    if uci show firewall 2>/dev/null | grep -q "name='Block_UDP_80'" ||        uci show firewall 2>/dev/null | grep -q "name='Block_UDP_443'"; then
        QUIC_OURS=1
    fi
    [ "$(uci -q get firewall.@defaults[0].flow_offloading 2>/dev/null)" = 1 ] && FLOW_OFFLOAD="yes" || FLOW_OFFLOAD="no"
    if command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then NFT_ACTIVE="yes"; else NFT_ACTIVE="no"; fi
    DNS_PATH_CONFLICT="no"
    dns_path_conflict_nft >/dev/null 2>&1 && DNS_PATH_CONFLICT="yes"
}
run_discovery() {
init_dirs
disc_system
disc_network
disc_listeners
disc_dns
disc_clients
disc_firewall
log_tx "DISCOVER" "router" "READ" "OK" "OpenWrt=$SYS_OWRT;fw=$SYS_FW;dns=$DNSMASQ_RUN;doh=$DOH_TOTAL"
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
    set -- $(od -An -tu1 -N12 "$_file" 2>/dev/null)
    [ "$#" -ge 12 ] || return 1
    [ "$1" -eq 18 ] 2>/dev/null || return 1
    [ "$2" -eq 52 ] 2>/dev/null || return 1
    [ $(( $3 & 128 )) -ne 0 ] 2>/dev/null || return 1
    [ $(( $3 & 120 )) -eq 0 ] 2>/dev/null || return 1
    [ $(( $4 & 15 )) -eq 0 ] 2>/dev/null || return 1
    [ $(( $5 * 256 + $6 )) -eq 1 ] 2>/dev/null || return 1
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
        if [ "$bytes" -ge 12 ] && [ "$ct_ok" = yes ]; then
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
[ "$HAS_CURL" = yes ] || { warn_msg "curl не установлен. Сначала установите его через пункт I."; return 1; }
rm -f "$TMP_DIR/t."* "$TMP_DIR/q."* "$TMP_DIR/body."* "$TMP_DIR/h."* "$TEST_RESULTS" 2>/dev/null
total="$(count_dns)"
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
batch=30
while IFS='|' read -r id _rest; do
    case "$id" in ''|\#*) continue;; esac
    test_one_dns "$id" &
    n=$((n+1))
    if [ $((n % batch)) -eq 0 ]; then
        wait
        test_progress
    fi
done < "$DNS_CATALOG"
wait
test_progress
cat "$TMP_DIR"/t.* > "$TEST_RESULTS" 2>/dev/null
okn="$(awk -F'|' 'NF>=5 && $5=="OK"{n++} END{print n+0}' "$TEST_RESULTS" 2>/dev/null)"
failn=$((total-okn))
printf "${C_GREEN}✓ Успешно: %s${C_NC} | ${C_YELLOW}Проблемные: %s${C_NC} | Всего: %s\n" "$okn" "$failn" "$total"
printf "${C_CYAN}Время ответа — сколько занял полный запрос к DNS. Чем меньше число, тем быстрее сервер. Знак «—» означает, что ответ не получен.${C_NC}\n"
if [ "$okn" -eq 0 ]; then
    warn_msg "Не удалось проверить ни одного DNS-сервера. Настройки не изменены."
    log_tx "TEST" "dns-catalog" "RUN" "FAIL" "ok=$okn,total=$total"
    return 1
fi
log_tx "TEST" "dns-catalog" "RUN" "OK" "ok=$okn,total=$total"
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
RU_2) printf '%s' "5060";;
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
if [ "${HYBRID_AUTO_REPAIR:-0}" = 1 ] && [ -s "$TEST_RESULTS" ]; then
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
menu_header "СИНХРОНИЗАЦИЯ ВРЕМЕНИ — точное время на роутере"
_cur_ntp="$(uci -q get system.ntp.server 2>/dev/null)"
printf "${C_WHITE}Зачем нужен этот раздел:${C_NC}\n"
printf "  Точное время нужно роутеру для HTTPS-соединений, проверки сертификатов,\n"
printf "  журналов и автоматических задач.\n\n"
printf "${C_YELLOW}${C_BOLD}Текущие серверы времени:${C_NC}\n"
if [ -n "$_cur_ntp" ]; then
for _s in $_cur_ntp; do
printf "  ${C_CYAN}•${C_NC} %s\n" "$_s"
done
else
printf "  ${C_YELLOW}(не настроены)${C_NC}\n"
fi
printf "\n${C_YELLOW}${C_BOLD}Выбранный источник времени:${C_NC} ${C_YELLOW}${C_BOLD}%s${C_NC}\n\n" "$NTP_PRESET"
menu_item "[1]" "Cloudflare — быстрый источник по IP, DNS не нужен"
menu_item "[2]" "NIST — несколько серверов точного времени"
menu_item "[3]" "ВНИИФТРИ Москва — российские серверы времени"
menu_item "[4]" "Google — серверы времени по IP"
menu_back
menu_prompt
safe_read c
case "$c" in
1) NTP_PRESET="cf_ip";;
2) NTP_PRESET="nist_ip";;
3) NTP_PRESET="vniiftri_moscow";;
4) NTP_PRESET="google_ip";;
*) return;;
esac
save_config
apply_ntp_ip_fallback
pause
}
# ==========================================
# ==========================================
# ==========================================
find_own_doh_by_url() {
awk -F'|' -v u="$(normalize_url "$1")" '$6==u && $3=="OURS"{print $1"|"$2"|"$6;exit}' "$DOH_INV"
}
find_any_doh_by_url() {
awk -F'|' -v u="$(normalize_url "$1")" '$6==u{print $1"|"$2"|"$3"|"$4"|"$5;exit}' "$DOH_INV"
}
find_own_doh_by_port() {
awk -F'|' -v p="$1" '$2==p && $3=="OURS"{print $1"|"$2"|"$6;exit}' "$DOH_INV"
}
port_used_anywhere() {
p="$1"
[ -s "$LISTENERS" ] || return 2
grep -qE ":$p([[:space:]]|$)" "$LISTENERS" 2>/dev/null && return 0
awk -F'|' -v p="$p" '$2==p{found=1} END{exit found?0:1}' "$DOH_INV"
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
    printf "${C_PINK}↻ Все существующие DNS-серверы будут удалены и заменены выбранной схемой диспетчер DNS.${C_NC}\n"
    _removed=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[0]" >/dev/null 2>&1; do
        _u="$(uci -q get "https-dns-proxy.@https-dns-proxy[0].resolver_url" 2>/dev/null)"
        [ -n "$_u" ] && printf "  ${C_PINK}↻ Удаляется DNS-сервер: %s${C_NC}\n" "$_u"
        uci -q delete "https-dns-proxy.@https-dns-proxy[0]" || return 1
        _removed=$((_removed+1))
    done
    uci commit https-dns-proxy || return 1
    : > "$DOH_INV"
    DOH_TOTAL=0
    DOH_OURS=0
    DOH_FOREIGN=0
    DOH_UNKNOWN=0
    printf "${C_GREEN}✓ Старых DNS-серверов удалено: %s. Остаются выбранные DNS-серверы.${C_NC}\n" "$_removed"
}
record_own() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$OWNERSHIP"; }
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
existing_own="$(find_own_doh_by_url "$url")"
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
[ "$(uci -q get "https-dns-proxy.@https-dns-proxy[$sec_idx].dns_manager" 2>/dev/null)" = "1" ] || return 1
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
local existing_foreign
existing_foreign="$(find_any_doh_by_url "$url")"
if [ -n "$existing_foreign" ]; then
local _foreign_idx="$(printf '%s' "$existing_foreign" | cut -d'|' -f1)"
local owner="$(printf '%s' "$existing_foreign" | cut -d'|' -f3)"
local p_old="$(printf '%s' "$existing_foreign" | cut -d'|' -f2)"
warn_msg "$name уже использовался чужой/неизвестной секцией (порт $p_old, владелец=$(owner_ru "$owner")). Она удаляется: при активном диспетчер DNS не оставляет другие DNS-серверы."
[ -n "$_foreign_idx" ] && uci -q delete "https-dns-proxy.@https-dns-proxy[$_foreign_idx]" || return 1
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
uci set "https-dns-proxy.$sec.dns_manager=1" || return 1
record_own "doh" "$target" "$url" "slot=$slot;name=$name"
eval "PORT_$slot=\"$target\""
printf "  ${C_GREEN}+ %s → 127.0.0.1:%s${C_NC}\n" "$name" "$target"
}
repair_duplicate_own_doh_ports() {
[ -s "$DOH_INV" ] || return 0
dup_ports="$TMP_DIR/dup-own-ports"
awk -F'|' '$3=="OURS" && $2!=""{cnt[$2]++} END{for(p in cnt) if(cnt[p]>1) print p}' "$DOH_INV" > "$dup_ports"
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
$(awk -F'|' -v p="$p" '$3=="OURS" && $2==p{print $1"|"$6}' "$DOH_INV")
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
        _m="$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].dns_manager" 2>/dev/null)"
        if [ "$_m" = 1 ]; then
            _u="$(normalize_url "$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].resolver_url" 2>/dev/null)")"
            if [ -z "$_u" ] || ! grep -qxF "$_u" "$_keep" 2>/dev/null; then
                printf "${C_PINK}↻ Удаляется устаревшая собственная секция DNS: %s${C_NC}\n" "${_u:-без URL}"
                uci -q delete "https-dns-proxy.@https-dns-proxy[$i]" || return 1
                continue
            fi
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
        if [ "$DNS_PROFILE" = hybrid ] && [ -s "$TEST_RESULTS" ]; then
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
    while uci -q delete "dhcp.$sec.server" >/dev/null 2>&1; do :; done
    for s in 1 2 3 4 5 6; do
        eval "id=\${SLOT_$s}"; eval "p=\${PORT_$s}"
        [ -n "$id" ] && [ -n "$p" ] || continue
        val="127.0.0.1#$p"
        uci add_list "dhcp.$sec.server=$val" || return 1
        record_own "dnsmasq" "server" "$val" "section=$sec"
    done
    if [ "$TLD_RU_ENABLED" = 1 ] && [ -n "$SLOT_RU" ] && [ -n "$PORT_RU" ]; then
        for t in /ru /su /xn--p1ai; do
            val="$t/127.0.0.1#$PORT_RU"
            uci add_list "dhcp.$sec.server=$val" || return 1
            record_own "dnsmasq" "server" "$val" "section=$sec"
        done
    fi
    if [ "$TLD_RU_ENABLED" = 1 ] && [ -n "$SLOT_RU_2" ] && [ -n "$PORT_RU_2" ]; then
        for t in /ru /su /xn--p1ai; do
            val="$t/127.0.0.1#$PORT_RU_2"
            uci add_list "dhcp.$sec.server=$val" || return 1
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
apply_quic() {
    [ "$BLOCK_QUIC" = 1 ] || return 0
    for _rname in Block_UDP_80 Block_UDP_443; do
        while :; do
            _ridx="$(uci show firewall 2>/dev/null | grep "name='$_rname'" | head -n1 | cut -d. -f2 | cut -d= -f1)"
            [ -n "$_ridx" ] || break
            uci -q delete "firewall.$_ridx" || return 1
        done
    done
    uci add firewall rule >/dev/null 2>&1 || return 1
    uci set firewall.@rule[-1].name='Block_UDP_80' || return 1
    uci add_list firewall.@rule[-1].proto='udp' || return 1
    uci set firewall.@rule[-1].src='lan' || return 1
    uci set firewall.@rule[-1].dest='wan' || return 1
    uci set firewall.@rule[-1].dest_port='80' || return 1
    uci set firewall.@rule[-1].target='REJECT' || return 1
    uci add firewall rule >/dev/null 2>&1 || return 1
    uci set firewall.@rule[-1].name='Block_UDP_443' || return 1
    uci add_list firewall.@rule[-1].proto='udp' || return 1
    uci set firewall.@rule[-1].src='lan' || return 1
    uci set firewall.@rule[-1].dest='wan' || return 1
    uci set firewall.@rule[-1].dest_port='443' || return 1
    uci set firewall.@rule[-1].target='REJECT' || return 1
    uci commit firewall || return 1
}
# ==========================================
# ==========================================
apply_sysctl() {
[ "$SYSCTL_TUNING" = 1 ] || return 0
f="/etc/sysctl.d/90-dns-manager.conf"
sf="$STATE_DIR/sysctl-before.conf"
[ -f "$f" ] || : > "$f" || return 1
for p in "net.ipv4.tcp_fastopen=3" "net.ipv4.tcp_fin_timeout=15" "net.core.somaxconn=1024"; do
key="${p%%=*}"; val="${p#*=}"; before="$(sysctl -n "$key" 2>/dev/null)"
grep -q "^${key}|" "$sf" 2>/dev/null || printf '%s|%s\n' "$key" "${before:-unknown}" >> "$sf"
foreign="$(grep -Rhs "^${key}=" /etc/sysctl.d 2>/dev/null | grep -v '^#' | grep -v "^${key}=${val}$" | head -n1)"
if [ -n "$foreign" ] && ! grep -q "^${key}=${val}$" "$f" 2>/dev/null; then
warn_msg "Не меняю $key: найдено стороннее значение ($foreign). Проверьте конфигурацию sysctl для этого параметра."
continue
fi
grep -q "^${key}=${val}$" "$f" 2>/dev/null || printf '%s\n' "$p" >> "$f"
sysctl -w "$p" >/dev/null 2>&1 || warn_msg "Не удалось применить $p"
record_own "sysctl" "$key" "$val" "before=${before:-unknown}"
done
}
remove_sysctl_base() {
    f="/etc/sysctl.d/90-dns-manager.conf"
    sf="$STATE_DIR/sysctl-before.conf"
    [ -f "$f" ] || return 0
    for kv in net.ipv4.tcp_fastopen net.ipv4.tcp_fin_timeout net.core.somaxconn; do
        old="$(awk -F'|' -v k="$kv" '$1==k{print $2;exit}' "$sf" 2>/dev/null)"
        [ -n "$old" ] && [ "$old" != unknown ] && sysctl -w "$kv=$old" >/dev/null 2>&1 || true
    done
    rm -f "$f" "$sf"
}
remove_go_optimize() {
    for f in /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale; do
        bak="$f.dns-manager.bak"
        [ -f "$bak" ] || continue
        curh="$(file_hash "$f")"
        managedh="$(cat "$STATE_DIR/$(basename "$f").managed.sha256" 2>/dev/null)"
        if [ -n "$managedh" ] && [ -n "$curh" ] && [ "$curh" != "$managedh" ]; then
            warn_msg "Не восстанавливаю $f: файл изменён вручную после настройки."
            continue
        fi
        mv "$bak" "$f" 2>/dev/null || continue
        rm -f "$STATE_DIR/$(basename "$f").managed.sha256"
    done
}
reload_fw() {
    if [ "$SYS_FW" = fw4 ]; then
        /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1
    else
        /etc/init.d/firewall restart >/dev/null 2>&1
    fi
}
# ==========================================
# ==========================================
apply_extras_now() {
    case "$1" in
        balance|tld)
            reconcile_dnsmasq || return 1
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
            ;;
        ntp)
            [ "$NTP_IP_FALLBACK" = 1 ] && apply_ntp_ip_fallback || true
            ;;
        quic)
            apply_quic_toggle || return 1
            ;;
        mtu)
            apply_mtu_toggle || return 1
            ;;
        sysctl)
            if [ "$SYSCTL_TUNING" = 1 ]; then apply_sysctl; else remove_sysctl_base; fi
            ;;
        go)
            if [ "$GO_OPTIMIZE" = 1 ]; then apply_go; else remove_go_optimize; fi
            ;;
        force)
            if [ "$FORCE_DOH" = 1 ]; then apply_dns_force; else remove_dns_force; fi
            reload_fw
            ;;
        ntp_clients)
            if [ "$NTP_CLIENTS" = 1 ]; then apply_ntp_clients; else remove_ntp_clients; fi
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
            reload_fw
            ;;
        dnsmasq_perf)
            if [ "$DNSMASQ_PERF" = 1 ]; then apply_dnsmasq_perf; else remove_dnsmasq_perf; fi
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
            ;;
        client_fixes)
            if [ "$CLIENT_FIXES" = 1 ]; then apply_client_fixes; else remove_client_fixes; fi
            /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
            ;;
        sysctl_ext)
            if [ "$SYSCTL_EXTENDED" = 1 ]; then apply_sysctl_extended; else remove_sysctl_extended; fi
            ;;
        ts_hotplug)
            if [ "$TAILSCALE_HOTPLUG" = 1 ]; then apply_tailscale_hotplug; else remove_tailscale_hotplug; fi
            ;;
        cron)
            if [ "$CRON_CLEANUP" = 1 ]; then cleanup_manager_cron; fi
            ;;
    esac
    run_discovery
    save_config
}
# ==========================================
# ==========================================
apply_go() {
[ "$GO_OPTIMIZE" = 1 ] || return 0
for f in /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale; do
[ -f "$f" ] || continue
marker="$(grep -c 'DNS_MANAGER_GOMEMLIMIT' "$f" 2>/dev/null)"
current_hash="$(file_hash "$f")"
hash_file="$STATE_DIR/$(basename "$f").managed.sha256"
if [ -s "$hash_file" ] && [ "$(cat "$hash_file")" != "$current_hash" ] && [ "$marker" = 1 ]; then
warn_msg "$f был изменён после последнего применения диспетчер DNS. Пропускаю Go-оптимизацию."
continue
fi
if [ "$marker" = 1 ]; then
continue
fi
bak="$f.dns-manager.bak"
[ -f "$bak" ] || cp "$f" "$bak" 2>/dev/null || { warn_msg "Не удалось создать backup $f"; continue; }
ev="GOMEMLIMIT=85MiB"; [ "$f" = "/etc/init.d/tg-ws-proxy-go" ] && ev="GOMAXPROCS=1 GOMEMLIMIT=50MiB"
awk -v ev="$ev" '/procd_open_instance/{print;print "    # ОГРАНИЧЕНИЕ ПАМЯТИ GO";print "    procd_set_param env "ev;next}1' "$f" > "$TMP_DIR/go.$$" || { rm -f "$TMP_DIR/go.$$"; continue; }
mv "$TMP_DIR/go.$$" "$f" || continue
file_hash "$f" > "$hash_file"
record_own "file" "$f" "managed-hash" "$hash_file"
done
}
# ==========================================
# ==========================================
# ==========================================
apply_ntp_clients() {
    [ "${NTP_CLIENTS:-0}" = 1 ] || return 0
    sec="$(get_dnsmasq_section)"
    [ -n "$sec" ] || return 1
    _opt="42,$LAN_IP"
    _cur="$(uci -q get "dhcp.$sec.dhcp_option" 2>/dev/null)"
    if ! printf '%s\n' "$_cur" | tr ' ' '\n' | grep -qxF "$_opt"; then
        uci add_list "dhcp.$sec.dhcp_option=$_opt" || return 1
        record_own "dnsmasq" "dhcp_option" "$_opt" "section=$sec"
    fi
    uci -q delete firewall.dns_manager_ntp_client
    uci set firewall.dns_manager_ntp_client=redirect || return 1
    uci set firewall.dns_manager_ntp_client.name='диспетчер DNS: NTP клиентов в роутер' || return 1
    uci set firewall.dns_manager_ntp_client.src='lan' || return 1
    uci set firewall.dns_manager_ntp_client.proto='udp' || return 1
    uci set firewall.dns_manager_ntp_client.src_dport='123' || return 1
    uci set firewall.dns_manager_ntp_client.dest_ip="$LAN_IP" || return 1
    uci set firewall.dns_manager_ntp_client.dest_port='123' || return 1
    uci set firewall.dns_manager_ntp_client.target='DNAT' || return 1
    uci commit dhcp || return 1
    uci commit firewall || return 1
}
remove_ntp_clients() {
    sec="$(get_dnsmasq_section)"
    [ -n "$sec" ] && uci -q del_list "dhcp.$sec.dhcp_option=42,$LAN_IP"
    uci -q delete firewall.dns_manager_ntp_client
    uci commit dhcp >/dev/null 2>&1 || true
    uci commit firewall >/dev/null 2>&1 || true
}
# ==========================================
# ==========================================
apply_dnsmasq_perf() {
    [ "${DNSMASQ_PERF:-0}" = 1 ] || return 0
    sec="$(get_dnsmasq_section)"
    [ -n "$sec" ] || return 1
    _f="$STATE_DIR/dnsmasq-perf-before.conf"
    : > "$_f" || return 1
    for _k in cachesize dnsforwardmax max_cache_ttl boguspriv domainneeded quietdhcp filter_aaaa; do
        _v="$(uci -q get "dhcp.$sec.$_k" 2>/dev/null)"
        printf '%s|%s\n' "$_k" "$_v" >> "$_f"
    done
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
    if [ -s "$_f" ]; then
        while IFS='|' read -r _k _v; do
            if [ -n "$_v" ]; then uci set "dhcp.$sec.$_k=$_v"; else uci -q delete "dhcp.$sec.$_k"; fi
        done < "$_f"
        uci commit dhcp >/dev/null 2>&1 || true
        rm -f "$_f"
    fi
}
# ==========================================
# ==========================================
apply_client_fixes() {
    [ "${CLIENT_FIXES:-0}" = 1 ] || return 0
    f="/etc/dnsmasq.d/91-dns-manager-client-fixes.conf"
    [ -f "$f" ] || printf '%s\n' '# DNS_MANAGER_MANAGED=1' > "$f" || return 1
    {
        printf '%s\n' '# DNS_MANAGER_CLIENT_FIXES=1'
        printf '%s\n' 'local=/telemetry.mozilla.org/'
        printf '%s\n' 'local=/telemetry.microsoft.com/'
        printf '%s\n' 'local=/vortex.data.microsoft.com/'
        printf '%s\n' 'local=/settings-win.data.microsoft.com/'
        printf '%s\n' 'local=/metrics.android.com/'
        printf '%s\n' 'local=/metrics.samsung.com/'
        printf '%s\n' 'server=/clients3.google.com/77.88.8.8'
        printf '%s\n' 'server=/clients3.google.com/77.88.8.1'
        printf '%s\n' 'server=/connectivitycheck.gstatic.com/77.88.8.8'
        printf '%s\n' 'server=/connectivitycheck.gstatic.com/77.88.8.1'
        printf '%s\n' 'server=/connectivitycheck.android.com/77.88.8.8'
        printf '%s\n' 'server=/connectivitycheck.android.com/77.88.8.1'
        printf '%s\n' 'server=/connectivitycheck.samsung.com/77.88.8.8'
        printf '%s\n' 'server=/connectivitycheck.samsung.com/77.88.8.1'
        printf '%s\n' 'server=/connectivitycheck.platform.hicloud.com/77.88.8.8'
        printf '%s\n' 'server=/connectivitycheck.platform.hicloud.com/77.88.8.1'
    } > "$f.tmp" || return 1
    mv "$f.tmp" "$f" || return 1
    record_own "file" "$f" "managed" "client-fixes"
}
remove_client_fixes() {
    f="/etc/dnsmasq.d/91-dns-manager-client-fixes.conf"
    if grep -q '^# DNS_MANAGER_MANAGED=1$' "$f" 2>/dev/null; then rm -f "$f"; /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true; fi
}
apply_sysctl_extended() {
    [ "${SYSCTL_EXTENDED:-0}" = 1 ] || return 0
    f="/etc/sysctl.d/91-dns-manager-extended.conf"
    sf="$STATE_DIR/sysctl-extended-before.conf"
    : > "$sf" || return 1
    for p in "net.netfilter.nf_conntrack_max=65536" "net.ipv4.tcp_keepalive_time=600" "net.ipv4.tcp_keepalive_intvl=60" "net.ipv4.tcp_keepalive_probes=5" "net.core.rmem_max=4194304" "net.core.wmem_max=4194304" "net.core.rmem_default=262144" "net.core.wmem_default=262144"; do
        _k="${p%%=*}"; _v="${p#*=}"; _old="$(sysctl -n "$_k" 2>/dev/null)"; printf '%s|%s\n' "$_k" "${_old:-unknown}" >> "$sf"
        printf '%s\n' "$p" >> "$f.tmp"
    done
    mv "$f.tmp" "$f" || return 1
    command -v modprobe >/dev/null 2>&1 && modprobe nf_conntrack >/dev/null 2>&1 || true
    sysctl -p "$f" >/dev/null 2>&1 || true
    record_own "file" "$f" "managed" "extended-sysctl"
}
remove_sysctl_extended() {
    f="/etc/sysctl.d/91-dns-manager-extended.conf"; sf="$STATE_DIR/sysctl-extended-before.conf"
    if [ -s "$sf" ]; then
        while IFS='|' read -r _k _v; do
            [ -n "$_k" ] && [ "$_v" != unknown ] && sysctl -w "$_k=$_v" >/dev/null 2>&1 || true
        done < "$sf"
    fi
    rm -f "$f" "$sf"
}
# ==========================================
# ==========================================
apply_tailscale_hotplug() {
[ "${TAILSCALE_HOTPLUG:-0}" = 1 ] || return 0
f="/etc/hotplug.d/iface/99-dns-manager-tailscale"
mkdir -p /etc/hotplug.d/iface 2>/dev/null
if [ -f "$f" ] && ! grep -q '^# DNS_MANAGER_TAILSCALE_HOTPLUG=1$' "$f" 2>/dev/null; then
cp -p "$f" "$f.previous" 2>/dev/null
info_msg "Старый скрипт $f сохранён в $f.previous"
fi
cat > "$f.tmp" <<'EOF_HOT'
[ "$ACTION" = ifup ] || exit 0
[ "$INTERFACE" = wan ] || exit 0
MARK="/var/run/dns-manager/tailscale-hotplug-window"
[ -s "$MARK" ] || exit 0
NOW="$(date +%s)"; START="$(cat "$MARK" 2>/dev/null)"
[ -n "$START" ] || exit 0
[ $((NOW-START)) -ge 0 ] 2>/dev/null || exit 0
[ $((NOW-START)) -le 600 ] 2>/dev/null || { rm -f "$MARK"; exit 0; }
[ -x /etc/init.d/tailscale ] && /etc/init.d/tailscale restart >/dev/null 2>&1 || true
rm -f "$MARK"
EOF_HOT
mv "$f.tmp" "$f" || return 1
chmod 755 "$f"
date +%s > "$STATE_DIR/tailscale-hotplug-window" 2>/dev/null || true
record_own "file" "$f" "created" "tailscale-hotplug"
if [ -x /etc/init.d/tailscale ]; then
ok_msg "Hotplug-скрипт Tailscale установлен."
else
info_msg "Tailscale сейчас не установлен — скрипт уже лежит и заработает сразу после установки Tailscale."
fi
}
remove_tailscale_hotplug() {
f="/etc/hotplug.d/iface/99-dns-manager-tailscale"
if [ -f "$f" ]; then
rm -f "$f"
if [ -f "$f.previous" ]; then
ok_msg "Hotplug-скрипт Tailscale удалён. Старая копия: $f.previous"
else
ok_msg "Hotplug-скрипт Tailscale удалён."
fi
fi
rm -f "$STATE_DIR/tailscale-hotplug-window"
}
# ==========================================
# ==========================================
cleanup_manager_cron() {
    [ "${CRON_CLEANUP:-0}" = 1 ] || return 0
    f="/etc/crontabs/root"
    [ -f "$f" ] || return 0
    cand="$TMP_DIR/cron-manager-candidates"
    grep -E '(DNS_MANAGER_CRON|dns-manager|dns_manager).*(dnsmasq|https-dns-proxy|tailscale).*(restart|reload)' "$f" > "$cand" 2>/dev/null || true
    if [ ! -s "$cand" ]; then
        info_msg "Старых помеченных cron-запусков диспетчер DNS не найдено. Пользовательский cron не изменён."
        return 0
    fi
    awk '!/(DNS_MANAGER_CRON|dns-manager|dns_manager).*(dnsmasq|https-dns-proxy|tailscale).*(restart|reload)/{print}' "$f" > "$f.tmp" || return 1
    mv "$f.tmp" "$f" || return 1
    /etc/init.d/cron reload >/dev/null 2>&1 || true
    ok_msg "Старые cron-запуски диспетчер DNS удалены. Остальные задания cron сохранены."
}
# ==========================================
# ==========================================
apply_dns_force() {
    [ "${FORCE_DOH:-0}" = 1 ] || return 0
    if [ "${FORCE_DNS:-}" = 1 ]; then
        warn_msg "Сторонний force_dns уже включён. Второй перехват DNS не создаётся."
        return 0
    fi
    uci -q delete firewall.dns_manager_dns_redirect
    uci set firewall.dns_manager_dns_redirect=redirect || return 1
    uci set firewall.dns_manager_dns_redirect.name='диспетчер DNS: перенаправление DNS' || return 1
    uci set firewall.dns_manager_dns_redirect.src='lan' || return 1
    uci set firewall.dns_manager_dns_redirect.proto='tcp udp' || return 1
    uci set firewall.dns_manager_dns_redirect.src_dport='53' || return 1
    uci set firewall.dns_manager_dns_redirect.dest_ip="$LAN_IP" || return 1
    uci set firewall.dns_manager_dns_redirect.dest_port='53' || return 1
    uci set firewall.dns_manager_dns_redirect.target='DNAT' || return 1
    uci -q delete firewall.dns_manager_dot_block
    uci set firewall.dns_manager_dot_block=rule || return 1
    uci set firewall.dns_manager_dot_block.name='диспетчер DNS: блокировка DoT' || return 1
    uci set firewall.dns_manager_dot_block.src='lan' || return 1
    uci set firewall.dns_manager_dot_block.dest='wan' || return 1
    uci set firewall.dns_manager_dot_block.proto='tcp udp' || return 1
    uci set firewall.dns_manager_dot_block.dest_port='853' || return 1
    uci set firewall.dns_manager_dot_block.target='REJECT' || return 1
    uci commit firewall || return 1
    record_own "firewall" "name" "dns_manager_dns_redirect" "created"
    record_own "firewall" "name" "dns_manager_dot_block" "created"
}
remove_dns_force() {
    uci -q delete firewall.dns_manager_dns_redirect
    uci -q delete firewall.dns_manager_dot_block
    uci commit firewall >/dev/null 2>&1 || true
}
# ==========================================
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
printf '%s\n' '# DNS_MANAGER_MANAGED=1' > "$conf" || return 1
record_own "file" "$conf" "created" "bogus"
elif ! grep -q '^# DNS_MANAGER_MANAGED=1$' "$conf"; then
warn_msg "$conf уже существует и не помечен диспетчер DNS. Не меняю его."
pause; return
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
    apply_ntp_host_ips || return 1
    if [ "$NTP_IP_FALLBACK" = 1 ]; then
        apply_ntp_ip_fallback || return 1
    fi
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
    _suffix="$$-$(date +%s%N | cut -c1-8)"
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
        _m="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].dns_manager" 2>/dev/null)"
        if [ "$_m" = 1 ]; then
            _p="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].listen_port" 2>/dev/null)"
            _u="$(normalize_url "$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].resolver_url" 2>/dev/null)")"
            printf '%s|%s\n' "$_p" "$_u" >> "$_actual"
            [ "$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].listen_addr" 2>/dev/null)" = "127.0.0.1" ] || {
                err_msg "секция DNS $_i не ограничена 127.0.0.1."; return 1;
            }
        fi
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
        _ans="$(dig @127.0.0.1 -p "$_lp" "$_domain" A +time=3 +tries=1 +short 2>/dev/null | awk '/^[0-9]+(\.[0-9]+){3}$/ {print; exit}')"
        [ -n "$_ans" ] && return 0
        _ans="$(dig @127.0.0.1 -p "$_lp" "$_domain" A +time=3 +tries=1 2>/dev/null | awk '$4=="A" && $NF ~ /^[0-9]+(\.[0-9]+){3}$/ {print $NF; exit}')"
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
    [ "$DNS_PROFILE" = hybrid ] || return 1
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
    _i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$_i]" >/dev/null 2>&1; do
        _m="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].dns_manager" 2>/dev/null)"
        if [ "$_m" = 1 ]; then
            uci -q delete "https-dns-proxy.@https-dns-proxy[$_i]" || { rm -f "$_keep_file"; return 1; }
            continue
        fi
        _i=$((_i+1))
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
        uci set "https-dns-proxy.$_sec.dns_manager=1" || { rm -f "$_keep_file"; return 1; }
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
    [ -s "$TEST_RESULTS" ] || return 1
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
    fi
    return 0
}
# ==========================================
tx_snapshot_start() {
TX_DIR="$STATE_DIR/tx-$TX_ID"
rm -rf "$TX_DIR" 2>/dev/null
mkdir -p "$TX_DIR/files" || return 1
TX_ACTIVE=1
for f in /etc/config/dhcp /etc/config/https-dns-proxy /etc/config/firewall /etc/config/system /etc/sysctl.d/90-dns-manager.conf /etc/sysctl.d/91-dns-manager-extended.conf /etc/dnsmasq.d/90-dns-manager-bogus.conf /etc/dnsmasq.d/91-dns-manager-client-fixes.conf /etc/hotplug.d/iface/99-dns-manager-tailscale /etc/crontabs/root /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale; do
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
/etc/init.d/firewall reload 2>/dev/null || /etc/init.d/firewall restart 2>/dev/null || true
TX_ACTIVE=0
log_tx "ROLLBACK" "transaction" "RESTORE" "OK" "dir=$TX_DIR;guarded=yes"
}
tx_commit() {
TX_ACTIVE=0
printf '%s\n' "$(date +%s)" > "$TX_DIR/COMMITTED" 2>/dev/null
log_tx "TX" "transaction" "COMMIT" "OK" "dir=$TX_DIR"
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
    [ -s "$TEST_RESULTS" ] || test_dns_catalog || return 1
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
    awk -F'|' 'NF>=5 && $2=="clean" && $5=="OK" && $4 ~ /^[0-9]+$/ {print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n > "$_pool.clean"
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
        while IFS='|' read -r _id _cat _name _ms _st; do
            [ -n "$_id" ] || continue
            [ "$_fill" -ge 6 ] && break
            _u="$(normalize_url "$(dns_url "$_id")")"
            [ -n "$_u" ] || continue
            grep -qxF "$_u" "$_selected_urls" 2>/dev/null && continue
            printf '%s\n' "$_id" >> "$_tried"
            printf '%s\n' "$_u" >> "$_selected_urls"
            printf '%s|%s|%s|%s|%s\n' "$_id" "$_cat" "$_name" "$_ms" "$_st" >> "$_pool"
            _fill=$((_fill+1))
        done < "$_pool.clean"
    fi
    if [ "$_fill" -lt 6 ]; then
        rm -f "$_pool" "$_pool.bypass" "$_pool.clean" "$_tried" "$_selected_urls" 2>/dev/null
        err_msg "После полной проверки подтверждённых DNS недостаточно даже с резервом. Набор не применён."
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
        if [ "$_cat" = bypass ]; then
            printf "  ${C_GREEN}✓ Слот %s: %s → 127.0.0.1:%s${C_NC}\n" "$_slot" "$(dns_name "$_id")" "$_port"
        else
            printf "  ${C_YELLOW}↳ Слот %s: %s → 127.0.0.1:%s (резерв, DNS обхода недостаточно)${C_NC}\n" "$_slot" "$(dns_name "$_id")" "$_port"
        fi
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
    if [ "${_bypass_count:-0}" -lt 6 ]; then
        warn_msg "Рабочих DNS обхода не хватило: ${_bypass_count:-0} из 6. Остальные слоты заполнены быстрыми DNS-резервами."
    fi
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
apply_settings() {
    clear_screen
    run_discovery
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
        [ "$GO_OPTIMIZE" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Настройка сетевых служб\n" || printf "  ${C_YELLOW}—${C_NC} Go/Tailscale/TG WS не изменяется\n"
        [ "${FORCE_DOH:-0}" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Принудительный локальный DNS\n" || printf "  ${C_YELLOW}—${C_NC} Принудительный локальный DNS не изменяется\n"
        [ "$NTP_CLIENTS" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Время для устройств сети (DHCP 42 + DNAT 123)\n" || printf "  ${C_YELLOW}—${C_NC} NTP клиентов не изменяется\n"
        [ "$DNSMASQ_PERF" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Настройка DNS-кэша\n" || printf "  ${C_YELLOW}—${C_NC} Настройка DNS-кэша не изменяется\n"
        [ "$CLIENT_FIXES" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Клиентские DNS-фиксы\n" || printf "  ${C_YELLOW}—${C_NC} Клиентские фиксы не изменяются\n"
        [ "$SYSCTL_EXTENDED" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Расширенная настройка сети\n" || printf "  ${C_YELLOW}—${C_NC} Расширенный sysctl не изменяется\n"
        [ "$TAILSCALE_HOTPLUG" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Запуск Tailscale после сети\n" || printf "  ${C_YELLOW}—${C_NC} Tailscale hotplug не изменяется\n"
        [ "$CRON_CLEANUP" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Очистка старых заданий диспетчер DNS\n" || printf "  ${C_YELLOW}—${C_NC} Cron не изменяется\n"
        [ "$WATCHDOG_ENABLED" = 1 ] && printf "  ${C_GREEN}✓${C_NC} Автоматическая проверка DNS: каждые %s мин\n" "$WATCHDOG_INTERVAL" || printf "  ${C_YELLOW}—${C_NC} Автоматическая проверка DNS не изменяется\n"
    fi
    printf "\n${C_WHITE}Текущее состояние до применения:${C_NC}\n"
    printf "  dnsmasq: %b\n" "$(state_word "$DNSMASQ_RUN")"
    printf "  DNS-сервер: %s (настройка %s / другие %s / без определения %s)\n" "$DOH_TOTAL" "$DOH_OURS" "$DOH_FOREIGN" "$DOH_UNKNOWN"
    if [ "$DOH_TOTAL" -gt 0 ]; then
        printf "  ${C_YELLOW}↻ После подтверждения старые DNS-серверы будут заменены выбранными.${C_NC}\n"
    fi
    printf "  ${C_CYAN}${C_NC}\n"
    validate_selected_slots || return 1
    confirm_action "Применить показанную выше конфигурацию?" || return
    printf "\n${C_CYAN}Начинаю применение. Это может занять немного времени...${C_NC}\n"
    TX_ID="$(date +%Y%m%d-%H%M%S)-$$"
    TX_RESERVED_PORTS=""
    baseline_capture_once || { err_msg "Не удалось сохранить исходную копию. Настройки не изменены."; return 1; }
    tx_snapshot_start || { err_msg "Не удалось сохранить копию настроек. Настройки не изменены."; return 1; }
    log_tx "PLAN" "all" "APPLY" "START" "version=$VERSION"
    apply_ntp_host_ips || { err_msg "Не удалось подготовить серверы времени."; tx_restore_on_failure; return 1; }
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
        uci -q set firewall.@defaults[0].mtu_fix=1
        uci commit firewall
    fi
    if [ "$CORE_ONLY" != 1 ] && [ "$SYSCTL_TUNING" = 1 ]; then
        apply_sysctl || { err_msg "Не удалось применить sysctl."; tx_restore_on_failure; return 1; }
    fi
    if [ "$CORE_ONLY" != 1 ] && [ "$GO_OPTIMIZE" = 1 ]; then
        apply_go || { err_msg "Не удалось применить оптимизацию Go."; tx_restore_on_failure; return 1; }
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
    if [ "$CORE_ONLY" != 1 ] && [ "$SYSCTL_EXTENDED" = 1 ]; then
        apply_sysctl_extended || { err_msg "Не удалось применить расширенный sysctl."; tx_restore_on_failure; return 1; }
    fi
    if [ "$CORE_ONLY" != 1 ] && [ "$TAILSCALE_HOTPLUG" = 1 ]; then
        apply_tailscale_hotplug || { err_msg "Не удалось настроить автоматический запуск Tailscale."; tx_restore_on_failure; return 1; }
    fi
    if [ "$CORE_ONLY" != 1 ] && [ "$CRON_CLEANUP" = 1 ]; then
        cleanup_manager_cron || { err_msg "Не удалось очистить cron диспетчер DNS."; tx_restore_on_failure; return 1; }
    fi
    WATCHDOG_ENABLED="${WATCHDOG_ENABLED:-1}"
    apply_watchdog || { err_msg "Не удалось настроить cron Автопроверка."; tx_restore_on_failure; return 1; }
    /etc/init.d/https-dns-proxy restart 2>/dev/null || true
    /etc/init.d/dnsmasq restart 2>/dev/null || true
    sleep 2
    ensure_dnsmasq_balancer || { err_msg "Одновременный опрос DNS не включился после запуска. Изменения откатываются."; tx_restore_on_failure; return 1; }
    reload_fw
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
rollback_ours() {
clear_screen
printf "${C_YELLOW}=== 🔄 Удаление изменений диспетчер DNS ===${C_NC}\n"
if baseline_restore_if_safe; then
    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
    /etc/init.d/dnsmasq restart >/dev/null 2>&1 || true
    if [ "$SYS_FW" = fw4 ]; then
        /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1
    else
        /etc/init.d/firewall restart >/dev/null 2>&1
    fi
    rm -f "$BASELINE_LAST" 2>/dev/null
    ok_msg "Исходное состояние до первого захвата диспетчер DNS восстановлено. Исходная копия сохранён для аудита и повторного применения."
    pause
    return 0
fi
i=0
while uci -q get "https-dns-proxy.@https-dns-proxy[$i]" >/dev/null 2>&1; do
m="$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].dns_manager" 2>/dev/null)"
if [ "$m" = 1 ]; then uci -q delete "https-dns-proxy.@https-dns-proxy[$i]"; else i=$((i+1)); fi
done
uci commit https-dns-proxy 2>/dev/null
restore_hdp_control_from_baseline
sec="$(get_dnsmasq_section)"
grep '^dnsmasq|server|' "$OWNERSHIP" 2>/dev/null | while IFS='|' read -r _type _key val _meta; do
uci -q del_list "dhcp.$sec.server=$val" 2>/dev/null
done
uci commit dhcp 2>/dev/null
if [ -s "$PREV_DNSMASQ" ]; then
    _prev_sec="$(sed -n 's/^SECTION=//p' "$PREV_DNSMASQ" | head -n1)"
    [ -n "$_prev_sec" ] || _prev_sec="$sec"
    while uci -q delete "dhcp.$_prev_sec.server" >/dev/null 2>&1; do :; done
    _in_servers=0
    while IFS= read -r _line; do
        case "$_line" in
            SERVER) _in_servers=1; continue ;;
            ALLSERVERS=*) _in_servers=0; _v="${_line#ALLSERVERS=}"; [ -n "$_v" ] && uci set "dhcp.$_prev_sec.allservers=$_v" || uci -q delete "dhcp.$_prev_sec.allservers"; continue ;;
            STRICTORDER=*) _v="${_line#STRICTORDER=}"; [ -n "$_v" ] && uci set "dhcp.$_prev_sec.strictorder=$_v" || uci -q delete "dhcp.$_prev_sec.strictorder"; continue ;;
            NORESOLV=*) _v="${_line#NORESOLV=}"; [ -n "$_v" ] && uci set "dhcp.$_prev_sec.noresolv=$_v" || uci -q delete "dhcp.$_prev_sec.noresolv"; continue ;;
            SECTION=*) continue ;;
        esac
        [ "$_in_servers" = 1 ] && [ -n "$_line" ] && uci add_list "dhcp.$_prev_sec.server=$_line" >/dev/null 2>&1 || true
    done < "$PREV_DNSMASQ"
    uci commit dhcp 2>/dev/null
    rm -f "$PREV_DNSMASQ" 2>/dev/null
fi
for r in Block_UDP_80 Block_UDP_443; do
while :; do idx="$(uci show firewall 2>/dev/null | grep "name='$r'" | head -n1 | cut -d. -f2 | cut -d= -f1)"; [ -n "$idx" ] || break; uci -q delete "firewall.$idx"; done
done
uci commit firewall 2>/dev/null
remove_ntp_clients >/dev/null 2>&1 || true
remove_client_fixes >/dev/null 2>&1 || true
remove_dnsmasq_perf >/dev/null 2>&1 || true
remove_sysctl_extended >/dev/null 2>&1 || true
remove_tailscale_hotplug >/dev/null 2>&1 || true
if [ -f /etc/sysctl.d/90-dns-manager.conf ]; then
for kv in net.ipv4.tcp_fastopen net.ipv4.tcp_fin_timeout net.core.somaxconn; do
old="$(awk -F'|' -v k="$kv" '$1==k{print $2;exit}' "$STATE_DIR/sysctl-before.conf" 2>/dev/null)"
cur="$(sysctl -n "$kv" 2>/dev/null)"
mgr="$(awk -F'=' -v k="$kv" '$1==k{print $2;exit}' /etc/sysctl.d/90-dns-manager.conf 2>/dev/null)"
[ -n "$old" ] && [ -n "$mgr" ] && [ "$cur" = "$mgr" ] && [ "$old" != unknown ] && sysctl -w "$kv=$old" >/dev/null 2>&1
done
rm -f /etc/sysctl.d/90-dns-manager.conf "$STATE_DIR/sysctl-before.conf"
fi
for f in /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale; do
bak="$f.dns-manager.bak"
if [ -f "$bak" ]; then
curh="$(file_hash "$f")"; managedh="$(cat "$STATE_DIR/$(basename "$f").managed.sha256" 2>/dev/null)"
if [ -n "$managedh" ] && [ -n "$curh" ] && [ "$curh" != "$managedh" ]; then
warn_msg "Не восстанавливаю $f: он изменён после последнего применения диспетчер DNS."
else
mv "$bak" "$f" 2>/dev/null
fi
fi
done
/etc/init.d/https-dns-proxy restart 2>/dev/null
/etc/init.d/dnsmasq restart 2>/dev/null
printf "${C_GREEN}✓ Изменения обработаны.${C_NC}\n"
printf "${C_YELLOW}! Ручные изменения не перезаписывались.${C_NC}\n"
pause
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
owner_ru() {
case "$1" in
OURS) printf '%s' 'наш менеджер';;
FOREIGN) printf '%s' 'другое приложение';;
UNKNOWN) printf '%s' 'владелец не определён';;
*) printf '%s' "$1";;
esac
}
config_state_word() {
if [ "$1" = 1 ]; then
printf "${C_GREEN}ВКЛ • выбрано${C_NC}"
else
printf "${C_YELLOW}ВЫКЛ • не выбрано${C_NC}"
fi
}
hybrid_runtime_state_word() {
    [ "${DNS_PROFILE:-}" = "hybrid" ] || return 0
    _expected=0
    _actual=0
    for _hs in 1 2 3 4 5 6 RU RU_2; do
        eval "_hid=\${SLOT_${_hs}:-}"
        [ -n "$_hid" ] || continue
        _expected=$((_expected+1))
        _hp="$(hybrid_desired_port "$_hs")"
        _hu="$(normalize_url "$(dns_url "$_hid")")"
        if [ -s "${DOH_INV:-}" ] && awk -F'|' -v p="$_hp" -v u="$_hu" '$2==p && $3=="OURS" && $5=="yes" && $6==u {ok=1} END{exit !ok}' "$DOH_INV" 2>/dev/null; then
            _actual=$((_actual+1))
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
        tailscale) pgrep -f 'tailscaled' >/dev/null 2>&1 || pgrep -f 'tailscale' >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}
show_map() {
menu_header "СОСТОЯНИЕ РОУТЕРА"
menu_section "СИСТЕМА"
printf "  OpenWrt:        ${C_WHITE}%s${C_NC}\n" "$SYS_OWRT"
printf "  Платформа:      ${C_WHITE}%s${C_NC}\n" "$SYS_TARGET"
printf "  Архитектура:    ${C_WHITE}%s${C_NC}\n" "$SYS_ARCH"
printf "  Firewall:       ${C_WHITE}%s${C_NC}\n" "$SYS_FW"
printf "  LAN:            ${C_WHITE}%s${C_NC}\n" "$LAN_IP"
printf "  WAN:            ${C_WHITE}%s${C_NC}\n" "$WAN_PROTO"
printf "  IPv4:           %s\n" "$(state_word "$IPV4_ROUTE")"
printf "  IPv6:           %s\n" "$(state_word "$IPV6_ROUTE")"
printf "  curl:            %s\n" "$(state_word "$HAS_CURL")"
printf "  dig:             %s\n" "$(state_word "$HAS_DIG")"
printf "  ntpd:            %s\n" "$(state_word "$HAS_NTPD")"
menu_section "DNS"
printf "  dnsmasq:         %s\n" "$(state_word "$DNSMASQ_RUN")"
printf "  DNS-серверов всего:       ${C_WHITE}%s${C_NC}\n" "$DOH_TOTAL"
printf "  наших:           ${C_WHITE}%s${C_NC}\n" "$DOH_OURS"
printf "  Других:           ${C_WHITE}%s${C_NC}\n" "$DOH_FOREIGN"
printf "  Без владельца:     ${C_WHITE}%s${C_NC}\n" "$DOH_UNKNOWN"
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
    printf "  %-6s %-32s 127.0.0.1:%s\n" "RU2" "$(dns_name "$SLOT_RU_2")" "${PORT_RU_2:-5060}"
fi
menu_section "СТОРОННИЕ РЕШЕНИЯ"
_side_found=0
for _tp in  "zapret|Zapret" "zapret2|Zapret2" "netshift|NetShift" "splify|splify"  "mixomo|Mixomo" "magi|MagiTrickle" "hev|HevSocks5Tunnel" "awg|AWG"  "tggo|TG-Go" "tgrs|TG-Rust" "tgmt|TG-MTProto" "byedpi|ByeDPI" "tailscale|Tailscale"; do
    _kind="${_tp%%|*}"
    _label="${_tp#*|}"
    if third_party_running "$_kind"; then
        printf "  ${C_GREEN}✓${C_NC} %s — работает\n" "$_label"
        _side_found=1
    fi
done
[ "$_side_found" = 1 ] || printf "  ${C_YELLOW}—${C_NC} Активных сторонних служб не обнаружено\n"
menu_section "FIREWALL"
printf "  QUIC нашего менеджера:      %s\n" "$(state_word "$QUIC_OURS")"
printf "  Чужое эквивалентное правило: %s\n" "$(state_word "$QUIC_FOREIGN")"
printf "  Активный nft:               %s\n" "$(state_word "$NFT_ACTIVE")"
printf "  Аппаратное ускорение:       %s\n" "$(state_word "$FLOW_OFFLOAD")"
menu_section "НАСТРОЙКИ ДИСПЕТЧЕРА DNS"
printf "  Настройка:                   ${C_YELLOW}%s${C_NC}\n" "$( [ "$DNS_PROFILE" = hybrid ] && printf '%s' 'Гибридный DNS — 6 серверов + Яндекс RU' || printf '%s' 'Своя настройка' )"
printf "  Балансировка DNS:           %s\n" "$(config_state_word "$BALANCER_ENABLED")"
printf "  Отдельный DNS (.ru/.su/.рф): %s\n" "$(config_state_word "$TLD_SPLIT")"
printf "  Блокировка QUIC (DPI):      %s\n" "$(module_state_word quic "$BLOCK_QUIC")"
printf "  Исправление сетевых параметров / MSS:      %s\n" "$(module_state_word mtu "$MTU_FIX")"
printf "  Принудительный DNS:         %s\n" "$(module_state_word force "$FORCE_DOH")"
printf "  Настройка сети:     %s\n" "$(module_state_word sysctl "$SYSCTL_TUNING")"
printf "  Настройка DNS-кэша:             %s\n" "$(module_state_word dnsmasq_perf "$DNSMASQ_PERF")"
printf "  Оптимизация Go-приложений:  %s\n" "$(module_state_word go "$GO_OPTIMIZE")"
printf "  NTP для клиентов:           %s\n" "$(module_state_word ntp_clients "$NTP_CLIENTS")"
printf "  Запуск Tailscale после сети:  %s\n" "$(module_state_word ts_hotplug "$TAILSCALE_HOTPLUG")"
printf "  Связь системных служб:     %s\n" "$(module_state_word client_fixes "$CLIENT_FIXES")"
printf "${C_GREEN}✓ Discovery завершён. Изменений в конфигурацию не внесено.${C_NC}\n"
pause
}
# ==========================================
# ==========================================
show_doh() {
menu_header "НАЙДЕННЫЕ DNS-СЕРВЕРЫ"
[ -s "$DOH_INV" ] || { printf "${C_YELLOW}https-dns-proxy секции не найдены.${C_NC}\n"; pause; return; }
menu_section "СЕКЦИИ"
printf "  ${C_WHITE}%-4s %-8s %-12s %-8s %-12s${C_NC}\n" "#" "ПОРТ" "ВЛАДЕЛЕЦ" "СОСТ." "АДРЕС"
printf "  ──────────────────────────────────────────────────────────\n"
while IFS='|' read -r idx port owner addr running url; do
printf "  ${C_YELLOW}%-4s${C_NC} %-8s %-12s %b %-12s\n" "#$idx" "$port" "$(owner_ru "$owner")" "$(state_word "$running")" "$addr:$port"
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
show_best() {
while :; do
menu_header "ВЫБОР DNS"
menu_section "ГОТОВЫЕ ПРОФИЛИ"
menu_item "[1]" "Гибридный DNS — 6 DNS-серверов + Яндекс RU"
menu_item "[2]" "Чистый быстрый DNS"
menu_item "[3]" "Максимальная безопасность"
menu_item "[4]" "Максимальная приватность"
menu_item "[5]" "Блокировка рекламы"
menu_section "КАТЕГОРИИ"
menu_item "[6]" "Обход блокировок"
menu_item "[7]" "Семейный DNS"
menu_item "[8]" "Все категории"
menu_back
menu_prompt
safe_read goal
[ -z "$goal" ] && return
case "$goal" in
1) show_hybrid_profile;;
2) menu_best_actions clean "БЫСТРЫЙ DNS";;
3) menu_best_actions security "МАКСИМАЛЬНАЯ БЕЗОПАСНОСТЬ";;
4) menu_best_actions privacy "МАКСИМАЛЬНАЯ ПРИВАТНОСТЬ";;
5) menu_best_actions adblock "БЛОКИРОВКА РЕКЛАМЫ";;
6) menu_best_actions bypass "ОБХОД БЛОКИРОВОК";;
7) menu_best_actions family "СЕМЕЙНЫЙ DNS";;
8) menu_best_actions all "ВСЕ КАТЕГОРИИ";;
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
if [ ! -s "$TEST_RESULTS" ]; then
    info_msg "Результатов теста ещё нет. Запускаю один полный тест каталога..."
    test_dns_catalog
fi
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
if [ "$_cat" = bypass ]; then
    _n=0
    [ -s "$_pool" ] && _n="$(awk 'END{print NR+0}' "$_pool")"
    if [ "$_n" -lt 6 ]; then
        _src_clean="$TMP_DIR/auto-clean-fallback"
        : > "$_src_clean"
        awk -F'|' 'NF>=5 && $2=="clean" && $5=="OK" && $4 ~ /^[0-9]+$/ {print}' "$TEST_RESULTS" 2>/dev/null | sort -t'|' -k4,4n > "$_src_clean"
        while IFS='|' read -r _id _cat2 _name _ms _st; do
            [ "$_n" -ge 6 ] && break
            [ -n "$_id" ] || continue
            _url="$(normalize_url "$(dns_url "$_id")")"
            [ -n "$_url" ] || continue
            grep -qxF "$_url" "$_seen_urls" 2>/dev/null && continue
            printf '%s\n' "$_url" >> "$_seen_urls"
            printf '%s\n' "$_id|$_cat2|$_name|$_ms|$_st" >> "$_pool"
            _n=$((_n+1))
        done < "$_src_clean"
    fi
fi
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
_n_bypass=0
_n_clean_fallback=0
while IFS='|' read -r _id _cat2 _name _ms _st; do
    [ -n "$_id" ] || continue
    eval "SLOT_$i=\"$_id\""
    if [ "$_cat" = bypass ]; then
        eval "SLOT_${i}_CAT=\"bypass\""
        [ "$_cat2" = clean ] && _n_clean_fallback=$((_n_clean_fallback+1)) || _n_bypass=$((_n_bypass+1))
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
if [ "$_cat" = bypass ] && [ "$_n_clean_fallback" -gt 0 ]; then
        warn_msg "Рабочих DNS обхода не хватило: $_n_bypass из 6. $_n_clean_fallback слота заполнены быстрыми clean DNS; менеджер пометил их как резерв обхода."
fi
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
menu_best_actions() {
goal="$1"; title="$2"
while :; do
menu_header "$title"
menu_section "ДЕЙСТВИЯ"
menu_item "[1]" "Автонастройка: подобрать и применить безопасно"
menu_item "[2]" "Показать лучшие варианты"
menu_item "[3]" "Выбрать DNS вручную"
menu_back
menu_prompt
safe_read a
case "$a" in
1)
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
2)
clear_screen
menu_header "ЛУЧШИЕ ВАРИАНТЫ — $title"
menu_section "ТОП-5 ПО ВРЕМЕНИ ОТВЕТА"
show_best_category "$goal" 5 | while IFS='|' read -r _id _cat _name _ms _st; do
printf "  ${C_CYAN}${C_BOLD}•${C_NC} ${C_GREEN}${C_BOLD}%-34s${C_NC} ${C_YELLOW}%s мс${C_NC}\n" "$_name" "$_ms"
done
pause
;;
3) menu_slots; return;;
'') return;;
*) warn_msg "Неверный пункт."; pause;;
esac
done
}
# ==========================================
# ==========================================
select_slot() {
slot="$1"; clear_screen
menu_header "ВЫБОР DNS-СЕРВЕРА $slot"
n=1
while IFS='|' read -r id cat prof name url region status; do
case "$id" in ''|\#*) continue;; esac
printf "  ${C_CYAN}${C_BOLD}[%3d]${C_NC} ${C_GREEN}${C_BOLD}%-24s${C_NC} ${C_CYAN}[%s]${C_NC}\n" "$n" "$name" "$cat"
n=$((n+1))
done < "$DNS_CATALOG"
printf "\n"
menu_item "[99]" "Очистить"
menu_back
menu_prompt
safe_read c
[ -z "$c" ] && return
if [ "$c" = "99" ]; then
eval "SLOT_$slot=''"
eval "SLOT_${slot}_CAT=''"
save_config
return
fi
row="$(grep -v '^#' "$DNS_CATALOG" | sed -n "${c}p")"
id="$(printf '%s' "$row" | cut -d'|' -f1)"
[ -n "$id" ] || return
DNS_PROFILE="custom"
DNS_SELECTION_MODE="manual"
eval "SLOT_$slot=\$id"
_selected_cat="$(printf '%s' "$row" | cut -d'|' -f2)"
DNS_SELECTION_CATEGORY="$_selected_cat"
eval "SLOT_${slot}_CAT=\$_selected_cat"
save_config
}
# ==========================================
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
menu_item "[9]" "Автоподбор лучших"
menu_item "[10]" "Восстановить стандартную настройку"
menu_back
menu_prompt
safe_read c
[ -z "$c" ] && return
case "$c" in
1|2|3|4|5|6) select_slot "$c";;
7) select_slot RU;;
8) select_slot RU_2;;
9) show_best;;
10) hybrid_set_defaults; save_config; ok_msg "Стандартный Гибридный DNS восстановлен: 5053–5058 + Yandex 5059."; pause;;
*) warn_msg "Неверный пункт."; pause;;
esac
done
}
menu_bootstrap() {
menu_header "DNS ДЛЯ ЗАПУСКА"
BOOTSTRAP_DNS="$BOOTSTRAP_DNS_ALL"
printf "${C_WHITE}Используются все встроенные DNS:${C_NC}\n"
for _bs in $(printf '%s' "$BOOTSTRAP_DNS_ALL" | tr ',' ' '); do
    printf "  ${C_GREEN}•${C_NC} %s\n" "$_bs"
done
save_config
pause
}
menu_bogus() {
apply_bogus
}
module_state() {
key="$1"; val="$2"
[ "$val" = 1 ] || { printf 'ВЫКЛ'; return; }
case "$key" in
balance) printf 'ВКЛ • ожидает применения';;
tld) printf 'ВКЛ • ожидает применения';;
quic) [ "$QUIC_OURS" = 1 ] || [ "$QUIC_FOREIGN" = 1 ] && printf 'ВКЛ • правило найдено' || printf 'ВКЛ • ожидает применения';;
mtu) printf 'ВКЛ • ожидает применения';;
ntp) printf 'ВКЛ • IP-профиль настроен';;
sysctl) printf 'ВКЛ • ожидает применения';;
go) printf 'ВКЛ • ожидает применения';;
*) printf 'ВКЛ';;
esac
}
toggle_and_apply_dnsmasq() {
reconcile_dnsmasq >/dev/null 2>&1
/etc/init.d/dnsmasq restart >/dev/null 2>&1
save_config
}
apply_bootstrap_only() {
    BOOTSTRAP_DNS="$BOOTSTRAP_DNS_ALL"
    b_list="$(printf '%s' "$BOOTSTRAP_DNS")"
    i=0; changed=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$i]" >/dev/null 2>&1; do
        if [ "$(uci -q get "https-dns-proxy.@https-dns-proxy[$i].dns_manager" 2>/dev/null)" = 1 ]; then
            uci set "https-dns-proxy.@https-dns-proxy[$i].bootstrap_dns=$b_list" || return 1
            changed=1
        fi
        i=$((i+1))
    done
    if [ "$changed" = 1 ]; then
        uci commit https-dns-proxy 2>/dev/null || return 1
        /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || return 1
        ok_msg "Все встроенные DNS для запуска прописаны."
    else
        info_msg "DNS-серверов пока нет. Все встроенные DNS будут прописаны при следующей настройке."
    fi
    save_config
}
apply_quic_toggle() {
    if [ "$BLOCK_QUIC" != 1 ]; then
        for _rname in Block_UDP_80 Block_UDP_443; do
            while :; do
                _ridx="$(uci show firewall 2>/dev/null | grep "name='$_rname'" | head -n1 | cut -d. -f2 | cut -d= -f1)"
                [ -n "$_ridx" ] || break
                uci -q delete "firewall.$_ridx" || break
            done
        done
    else
        apply_quic || return 1
    fi
    uci commit firewall >/dev/null 2>&1 || return 1
    if [ "$SYS_FW" = fw4 ]; then
        /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1
    else
        /etc/init.d/firewall restart >/dev/null 2>&1
    fi
    save_config
}
apply_mtu_toggle() {
uci -q set firewall.@defaults[0].mtu_fix="$MTU_FIX"
uci commit firewall >/dev/null 2>&1
if [ "$SYS_FW" = "fw4" ]; then
/etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1
else
/etc/init.d/firewall restart >/dev/null 2>&1
fi
save_config
}
check_module_state() {
    sec="$(get_dnsmasq_section)"
    case "$1" in
        balance) [ "$(uci -q get "dhcp.$sec.allservers" 2>/dev/null)" = 1 ] && printf 1 || printf 0 ;;
        tld) uci -q get "dhcp.$sec.server" 2>/dev/null | tr ' ' '\n' | grep -q '^/ru/' && printf 1 || printf 0 ;;
        ntp) [ "$(uci -q get system.ntp.use_dhcp 2>/dev/null)" = 0 ] && uci -q get system.ntp.server 2>/dev/null | grep -qE '([0-9]{1,3}\.){3}[0-9]{1,3}' && printf 1 || printf 0 ;;
        quic) [ "$QUIC_OURS" = 1 ] && printf 1 || printf 0 ;;
        mtu) [ "$(uci -q get firewall.@defaults[0].mtu_fix 2>/dev/null)" = 1 ] && printf 1 || printf 0 ;;
        sysctl) [ -f /etc/sysctl.d/90-dns-manager.conf ] && printf 1 || printf 0 ;;
        sysctl_ext) [ -f /etc/sysctl.d/91-dns-manager-extended.conf ] && printf 1 || printf 0 ;;
        go) grep -qs 'DNS_MANAGER_GOMEMLIMIT' /etc/init.d/tg-ws-proxy-go /etc/init.d/tailscale 2>/dev/null && printf 1 || printf 0 ;;
        force) uci -q get firewall.dns_manager_dns_redirect >/dev/null 2>&1 && printf 1 || printf 0 ;;
        ntp_clients) uci -q get firewall.dns_manager_ntp_client >/dev/null 2>&1 && printf 1 || printf 0 ;;
        dnsmasq_perf) [ "$(uci -q get "dhcp.$sec.cachesize" 2>/dev/null)" = 1000 ] && printf 1 || printf 0 ;;
        client_fixes) [ -f /etc/dnsmasq.d/91-dns-manager-client-fixes.conf ] && printf 1 || printf 0 ;;
        ts_hotplug) [ -f /etc/hotplug.d/iface/99-dns-manager-tailscale ] && printf 1 || printf 0 ;;
        cron) [ "${CRON_CLEANUP:-0}" = 1 ] && printf 1 || printf 0 ;;
        watchdog) grep -qsE '^[[:space:]]*\*/[0-9]+[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*.*dns-manager[[:space:]]+(watchdog|-w|--watchdog)([[:space:]]|$)' /etc/crontabs/root 2>/dev/null && printf 1 || printf 0 ;;
        web) [ -x "$WEB_INIT" ] && pgrep -f '[t]tyd.*dns-manager' >/dev/null 2>&1 && printf 1 || printf 0 ;;
        *) printf 0 ;;
    esac
}
module_state_word() {
    _desired="$2"
    _real="$(check_module_state "$1")"
    if [ "$_desired" = 1 ] && [ "$_real" = 1 ]; then
        printf "${C_BOLD}${C_GREEN}✓ ВКЛ${C_NC} ${C_CYAN}${C_BOLD}• применено${C_NC}"
    elif [ "$_desired" = 1 ]; then
        printf "${C_BOLD}${C_YELLOW}⚠ ВКЛ${C_NC} ${C_CYAN}${C_BOLD}• ожидает применения${C_NC}"
    elif [ "$_real" = 1 ]; then
        printf "${C_BOLD}${C_MAGENTA}↻ ЕСТЬ${C_NC} ${C_CYAN}${C_BOLD}• физически включено${C_NC}"
    else
        printf "${C_BOLD}${C_RED}✗ ВЫКЛ${C_NC}"
    fi
}
# ==========================================
# ==========================================
web_access_real() { [ -x "$WEB_INIT" ] && pgrep -f '[t]tyd.*dns-manager' >/dev/null 2>&1; }
web_access_install() {
    command -v ttyd >/dev/null 2>&1 && return 0
    if [ "$PKG_MGR" = "apk" ]; then apk update >/dev/null 2>&1 && apk add ttyd >/dev/null 2>&1; else opkg update >/dev/null 2>&1 && opkg install ttyd >/dev/null 2>&1; fi
    command -v ttyd >/dev/null 2>&1
}
web_access_write_service() {
    _web_iface="$(uci -q get network.lan.device 2>/dev/null)"
    [ -n "$_web_iface" ] || _web_iface="$(uci -q get network.lan.ifname 2>/dev/null)"
    [ -n "$_web_iface" ] || _web_iface="br-lan"
    cat > "$WEB_INIT" <<EOF_WEB_INIT
#!/bin/sh /etc/rc.common
START=98
STOP=10
USE_PROCD=1
start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/ttyd -i $_web_iface -p 7682 -W -O -t fontSize=15 sh /usr/bin/dns-manager
    procd_set_param respawn 5 10 0
    procd_close_instance
}
stop_service() { procd_kill_instance; }
EOF_WEB_INIT
    chmod 755 "$WEB_INIT" || return 1
    grep -q -- "-i $_web_iface -p 7682" "$WEB_INIT" 2>/dev/null
}
web_access_firewall() {
    uci -q delete firewall.dns_manager_web_ttyd
    uci set firewall.dns_manager_web_ttyd=rule || return 1
    uci set firewall.dns_manager_web_ttyd.name='DNS Manager Web' || return 1
    uci set firewall.dns_manager_web_ttyd.src='lan' || return 1
    uci set firewall.dns_manager_web_ttyd.proto='tcp' || return 1
    uci set firewall.dns_manager_web_ttyd.dest_port="$WEB_ACCESS_PORT" || return 1
    uci set firewall.dns_manager_web_ttyd.target='ACCEPT' || return 1
    uci commit firewall || return 1
    /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1 || return 1
}
web_access_remove_firewall() {
    uci -q delete firewall.dns_manager_web_ttyd
    uci commit firewall >/dev/null 2>&1 || true
    /etc/init.d/firewall reload >/dev/null 2>&1 || /etc/init.d/firewall restart >/dev/null 2>&1 || true
}
apply_web_access() {
    case "${WEB_ACCESS_ENABLED:-0}" in
        1)
            WEB_ACCESS_PORT=7682
            if command -v ss >/dev/null 2>&1 && ss -lnt 2>/dev/null | grep -qE ":$WEB_ACCESS_PORT([[:space:]]|$)"; then WEB_ACCESS_ENABLED=0; save_config; err_msg "Порт web-доступа $WEB_ACCESS_PORT уже занят."; return 1; fi
            if command -v netstat >/dev/null 2>&1 && netstat -lnt 2>/dev/null | grep -qE ":$WEB_ACCESS_PORT([[:space:]]|$)"; then WEB_ACCESS_ENABLED=0; save_config; err_msg "Порт web-доступа $WEB_ACCESS_PORT уже занят."; return 1; fi
            if ! web_access_install; then WEB_ACCESS_ENABLED=0; save_config; err_msg 'Не удалось установить ttyd.'; return 1; fi
            if ! web_access_write_service; then WEB_ACCESS_ENABLED=0; save_config; err_msg 'Не удалось настроить web-доступ.'; return 1; fi
            if ! web_access_firewall; then WEB_ACCESS_ENABLED=0; "$WEB_INIT" disable >/dev/null 2>&1 || true; "$WEB_INIT" stop >/dev/null 2>&1 || true; rm -f "$WEB_INIT"; save_config; err_msg 'Не удалось открыть web-доступ в LAN.'; return 1; fi
            "$WEB_INIT" enable >/dev/null 2>&1 || true
            "$WEB_INIT" restart >/dev/null 2>&1 || true
            if web_access_real; then save_config; _web_ip="$(uci -q get network.lan.ipaddr 2>/dev/null | cut -d/ -f1)"; ok_msg "Доступ из браузера включён: http://${_web_ip:-192.168.1.1}:$WEB_ACCESS_PORT"; return 0; fi
            WEB_ACCESS_ENABLED=0; web_access_remove_firewall; "$WEB_INIT" disable >/dev/null 2>&1 || true; "$WEB_INIT" stop >/dev/null 2>&1 || true; rm -f "$WEB_INIT"; save_config; err_msg 'Web-доступ не запустился.'; return 1
            ;;
        *)
            WEB_ACCESS_ENABLED=0
            [ -x "$WEB_INIT" ] && { "$WEB_INIT" disable >/dev/null 2>&1 || true; "$WEB_INIT" stop >/dev/null 2>&1 || true; }
            web_access_remove_firewall
            rm -f "$WEB_INIT"
            save_config
            ok_msg 'Доступ из браузера выключен.'
            return 0
            ;;
    esac
}
# ==========================================
menu_extras() {
while :; do
menu_header "НАСТРОЙКИ"
menu_section "СЕТЬ И ОБХОД"
menu_item_state "[1]" "Блокировка QUIC" "$(module_state_word quic "$BLOCK_QUIC")"
menu_item_state "[2]" "Исправление сетевых параметров / MSS" "$(module_state_word mtu "$MTU_FIX")"
menu_item_state "[3]" "Принудительный DNS" "$(module_state_word force "$FORCE_DOH")"
menu_section "ПРОИЗВОДИТЕЛЬНОСТЬ"
menu_item_state "[4]" "Оптимизация TCP и Conntrack" "$(module_state_word sysctl "$SYSCTL_TUNING")"
menu_item_state "[5]" "Кэширование DNS-запросов" "$(module_state_word dnsmasq_perf "$DNSMASQ_PERF")"
menu_item_state "[6]" "Оптимизация Go-сервисов" "$(module_state_word go "$GO_OPTIMIZE")"
menu_section "СЕРВИСЫ И КЛИЕНТЫ"
menu_item_state "[7]" "Время для устройств сети" "$(module_state_word ntp_clients "$NTP_CLIENTS")"
menu_item_state "[8]" "Tailscale при поднятии WAN" "$(module_state_word ts_hotplug "$TAILSCALE_HOTPLUG")"
menu_item_state "[9]" "Исправления телеметрии и связи" "$(module_state_word client_fixes "$CLIENT_FIXES")"
menu_section "ОБСЛУЖИВАНИЕ"
menu_item "[10]" "Очистка старых заданий"
menu_item_state "[11]" "Автоматическая проверка DNS" "$(module_state_word watchdog "$WATCHDOG_ENABLED")"
menu_item_state "[12]" "Доступ из браузера" "$(module_state_word web "$WEB_ACCESS_ENABLED")"
menu_item "[13]" "IP-заглушки провайдера"
menu_back
menu_prompt
safe_read c
case "$c" in
1) [ "$BLOCK_QUIC" = 1 ] && BLOCK_QUIC=0 || BLOCK_QUIC=1; apply_extras_now quic; pause;;
2) [ "$MTU_FIX" = 1 ] && MTU_FIX=0 || MTU_FIX=1; apply_extras_now mtu; pause;;
3) [ "$FORCE_DOH" = 1 ] && FORCE_DOH=0 || FORCE_DOH=1; apply_extras_now force; pause;;
4)
if [ "$SYSCTL_TUNING" = 1 ]; then
SYSCTL_TUNING=0; SYSCTL_EXTENDED=0
else
SYSCTL_TUNING=1; SYSCTL_EXTENDED=1
fi
apply_extras_now sysctl
apply_extras_now sysctl_ext
pause;;
5) [ "$DNSMASQ_PERF" = 1 ] && DNSMASQ_PERF=0 || DNSMASQ_PERF=1; apply_extras_now dnsmasq_perf; pause;;
6) [ "$GO_OPTIMIZE" = 1 ] && GO_OPTIMIZE=0 || GO_OPTIMIZE=1; apply_extras_now go; pause;;
7) [ "$NTP_CLIENTS" = 1 ] && NTP_CLIENTS=0 || NTP_CLIENTS=1; apply_extras_now ntp_clients; pause;;
8) [ "$TAILSCALE_HOTPLUG" = 1 ] && TAILSCALE_HOTPLUG=0 || TAILSCALE_HOTPLUG=1; apply_extras_now ts_hotplug; pause;;
9) [ "$CLIENT_FIXES" = 1 ] && CLIENT_FIXES=0 || CLIENT_FIXES=1; apply_extras_now client_fixes; pause;;
10) cleanup_manager_cron; CRON_CLEANUP=1; save_config; pause;;
11) [ "$WATCHDOG_ENABLED" = 1 ] && WATCHDOG_ENABLED=0 || WATCHDOG_ENABLED=1; apply_watchdog; pause;;
12) [ "$WEB_ACCESS_ENABLED" = 1 ] && WEB_ACCESS_ENABLED=0 || WEB_ACCESS_ENABLED=1; apply_web_access; pause;;
13) menu_bogus;;
'') return;;
*) warn_msg "Неизвестный пункт."; pause;;
esac
done
}
# ==========================================
# ==========================================
ensure_dependencies(){
missing=""
[ "$HAS_CURL" = yes ] || missing="$missing curl"
[ "$HAS_HDP" = yes ] || missing="$missing https-dns-proxy"
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
    run_discovery >/dev/null 2>&1 || true
    install_missing_dependencies || return 1
    write_catalogs
    load_config
    run_discovery >/dev/null 2>&1 || true
    return 0
}
install_missing_dependencies(){
    run_discovery >/dev/null 2>&1 || true
    _need="$(ensure_dependencies)"
    if [ -z "$_need" ]; then
        return 0
    fi
    printf "\n${C_YELLOW}↻ Обнаружены недостающие компоненты. Устанавливаю...${C_NC}\n"
    for _pkg in $_need; do
        printf "  ${C_PINK}↻${C_NC} %s\n" "$_pkg"
    done
    printf "\n"
    if [ "$PKG_MGR" = "apk" ]; then
        apk update >/dev/null 2>&1 && apk add $_need
    else
        opkg update >/dev/null 2>&1 && opkg install $_need
    fi
    _rc=$?
    run_discovery >/dev/null 2>&1 || true
    if [ "$_rc" -eq 0 ]; then
        _left="$(ensure_dependencies)"
        if [ -z "$_left" ]; then
            ok_msg "Все необходимые компоненты установлены."
            return 0
        fi
    fi
    err_msg "Не удалось установить все необходимые компоненты. Настройка остановлена."
    return 1
}
# ==========================================
# ==========================================
menu_install() {
menu_header "ПРОГРАММЫ"
run_discovery >/dev/null 2>&1 || true
printf "  curl              : %s\n" "$(state_word "$HAS_CURL")"
printf "  dig (доп.)         : %s\n" "$(state_word "$HAS_DIG")"
printf "  https-dns-proxy   : %s\n" "$(state_word "$HAS_HDP")"
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
printf "  CA-сертификаты    : %s\n" "$(state_word "$CA_OK")"
printf "  dnsmasq           : %s\n" "$(state_word "$HAS_DNSMASQ")"
need="$(ensure_dependencies)"
if [ -z "$need" ]; then
ok_msg "Все обязательные компоненты уже установлены."
pause
return
fi
printf "${C_YELLOW}Необходимо установить:${C_NC}\n"
for pkg in $need; do
printf "  ${C_PINK}↻${C_NC} %s\n" "$pkg"
done
printf "\n"
if confirm_action "Установить недостающие компоненты сейчас?"; then
if install_missing_dependencies; then
ok_msg "Обязательные компоненты установлены."
else
warn_msg "После установки остались недостающие компоненты. Проверьте состояние."
fi
else
info_msg "Установка отменена."
fi
pause
}
# ==========================================
# ==========================================
menu_status() {
menu_header "СОСТОЯНИЕ И ЖУРНАЛ"
_catalog_ver="$(dns_catalog_version)"
_catalog_count="$(count_dns)"
printf "${C_WHITE}Каталог DNS:${C_NC} ${C_GREEN}%s${C_NC} • ${C_CYAN}%s серверов${C_NC}\n" "${_catalog_ver:-не определён}" "${_catalog_count:-0}"
printf "${C_WHITE}Последние события:${C_NC}\n"
if [ -s "$LOG_FILE" ]; then tail -15 "$LOG_FILE" | sed -e "s/ START / Запуск /" -e "s/ UPDATE / Обновление /" -e "s/ INFO / Информация: /" -e "s/ WARN / Внимание: /" -e "s/ ERROR / Ошибка: /"; else printf "${C_YELLOW}Журнал пока пуст.${C_NC}\n"; fi
echo ""
printf "${C_WHITE}Последняя проверка:${C_NC}\n"
if [ -s "$TEST_RESULTS" ]; then
total="$(count_dns)"; okn="$(awk -F'|' 'NF>=5 && $5=="OK"{n++} END{print n+0}' "$TEST_RESULTS" 2>/dev/null)"; failn=$((total-okn))
printf "  DNS: ${C_GREEN}%s работают${C_NC}, ${C_YELLOW}%s не прошли${C_NC}, всего %s\n" "$okn" "$failn" "$total"
else
printf "  ${C_YELLOW}Тест DNS ещё не запускался.${C_NC}\n"
fi
echo ""
printf "${C_WHITE}Последние действия:${C_NC}\n"
if [ -s "$TX_LOG" ]; then
tail -10 "$TX_LOG" | awk -F'|' 'NF>=7 {
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
CORE_ONLY=0
HYBRID_FORCE_RESELECT=0
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
    if [ "$DNS_SELECTION_MODE" = quick ]; then
        printf '%s\n' bypass
        printf '%s\n' clean
    else
        printf '%s\n' "$_desired"
    fi
}
watchdog_enforce_hdp_control() {
    _changed=0
    [ "$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null)" = "-" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null)" = "0" ] || _changed=1
    [ "$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null)" = "0" ] || _changed=1
    [ "$_changed" = 1 ] || return 0
    log_msg "Обнаружен drift настроек https-dns-proxy. Возвращаю контроль диспетчер DNS.."
    uci set https-dns-proxy.config.dnsmasq_config_update='-' || return 1
    uci set https-dns-proxy.config.force_dns='0' || return 1
    uci set https-dns-proxy.config.notrack_dns='0' || return 1
    uci commit https-dns-proxy || return 1
    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || return 1
    return 0
}
watchdog_enforce_doh_authority() {
    _foreign=0
    _i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$_i]" >/dev/null 2>&1; do
        _m="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].dns_manager" 2>/dev/null)"
        [ "$_m" = 1 ] || { _foreign=1; break; }
        _i=$((_i+1))
    done
    [ "$_foreign" = 1 ] || return 0
    log_msg "Найден другой DNS-сервер. Его настройка будет удалена."
    /etc/init.d/https-dns-proxy stop >/dev/null 2>&1 || true
    _i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$_i]" >/dev/null 2>&1; do
        _m="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].dns_manager" 2>/dev/null)"
        if [ "$_m" = 1 ]; then
            _i=$((_i+1))
        else
            uci -q delete "https-dns-proxy.@https-dns-proxy[$_i]" || return 1
        fi
    done
    uci commit https-dns-proxy || return 1
    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || return 1
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
    _cfg_changed="$(dns_redirect_conflict_uci 2>/dev/null || printf 0)"
    if [ "$_cfg_changed" = 1 ]; then
        uci commit firewall >/dev/null 2>&1 || return 1
        reload_fw || return 1
    fi
    if dns_path_conflict_nft >/dev/null 2>&1; then
        return 1
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
        log_msg "Обнаружен drift dnsmasq. Восстанавливаю авторитетную конфигурацию диспетчер DNS."
        reconcile_dnsmasq || return 1
        /etc/init.d/dnsmasq restart >/dev/null 2>&1 || return 1
    fi
    return 0
}
watchdog_service_recover() {
    pgrep -f 'https-dns-proxy' >/dev/null 2>&1 && return 0
    log_msg "Служба DNS не запущена. Перезапускаю её."
    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || return 1
    sleep 3
    pgrep -f 'https-dns-proxy' >/dev/null 2>&1 || return 1
    return 0
}
watchdog_hdp_guard() {
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
        _m="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].dns_manager" 2>/dev/null)"
        if [ "$_m" = 1 ]; then
            _p="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].listen_port" 2>/dev/null)"
            _u="$(normalize_url "$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].resolver_url" 2>/dev/null)")"
            printf '%s|%s\n' "$_p" "$_u" >> "$_actual"
        fi
        _i=$((_i+1))
    done
    _expected_n="$(wc -l < "$_expected" 2>/dev/null | tr -d ' ')"
    _actual_n="$(wc -l < "$_actual" 2>/dev/null | tr -d ' ')"
    _bad=0
    [ "$_expected_n" = "$_actual_n" ] || _bad=1
    while IFS='|' read -r _slot _port _url; do
        [ -n "$_url" ] || continue
        grep -qxF "$_port|$_url" "$_actual" 2>/dev/null || { _bad=1; break; }
    done < "$_expected"
    if [ "$_bad" = 1 ]; then
        log_msg "Обнаружено изменение конфигурации DNS. Восстанавливаю выбранные серверы без изменения профиля."
        rebuild_selected_hdp_sections || { rm -f "$_expected" "$_actual"; return 1; }
        /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || { rm -f "$_expected" "$_actual"; return 1; }
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
            if [ "$_rcat" = "$_need" ] || { [ "$_need" = bypass ] && [ "$_rcat" = clean ]; }; then
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
    [ -n "$_slot" ] && [ -n "$_new_id" ] || return 1
    eval "SLOT_${_slot}=\"$_new_id\""
    if [ "$DNS_SELECTION_MODE" = quick ]; then
        eval "SLOT_${_slot}_CAT=\"bypass\""
    else
        eval "SLOT_${_slot}_CAT=\"$_new_cat\""
    fi
    if ! rebuild_selected_hdp_sections >/dev/null 2>&1; then
        eval "SLOT_${_slot}=\"$_old_id\""
        eval "SLOT_${_slot}_CAT=\"$_old_cat\""
        rebuild_selected_hdp_sections >/dev/null 2>&1 || true
        return 1
    fi
    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
    sleep 3
    if watchdog_check_slot "$_slot"; then
        save_config
        return 0
    fi
    eval "SLOT_${_slot}=\"$_old_id\""
    eval "SLOT_${_slot}_CAT=\"$_old_cat\""
    rebuild_selected_hdp_sections >/dev/null 2>&1 || true
    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
    sleep 2
    return 1
}
# ==========================================
run_watchdog() {
    _lock="$STATE_DIR/watchdog.lock"
    if [ -f "$_lock" ]; then
        _pid="$(cat "$_lock" 2>/dev/null)"
        if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
            log_msg "Проверка DNS пропущена: предыдущая проверка ещё работает (PID $_pid)."
            return 0
        fi
    fi
    printf '%s\n' "$$" > "$_lock" 2>/dev/null || return 1
    _wd_rc=0
    run_discovery
    load_config
    watchdog_enforce_hdp_control || log_msg "Не удалось полностью восстановить контроль над настройками https-dns-proxy."
    watchdog_enforce_doh_authority || log_msg "Не удалось полностью очистить сторонние DNS-сервер."
    watchdog_service_recover || log_msg "Не удалось выполнить восстановительное перезапускание https-dns-proxy."
    watchdog_hdp_guard || log_msg "Не удалось проверить соответствие DNS-серверов выбранному набору."
    watchdog_dns_path_guard || log_msg "Обнаружен конфликт пути DNS в firewall."
    watchdog_dnsmasq_guard || log_msg "Не удалось полностью восстановить конфигурацию dnsmasq."
    run_discovery
    _age=999999999
    if [ -f "$TEST_RESULTS" ]; then
        _mtime="$(stat -c %Y "$TEST_RESULTS" 2>/dev/null || printf '0')"
        case "$_mtime" in ''|*[!0-9]*) _mtime=0 ;; esac
        _now="$(date +%s)"; _age=$(( _now - _mtime )); [ "$_age" -lt 0 ] && _age=999999999
    fi
    if [ "$_age" -gt 21600 ]; then
        test_dns_catalog >/dev/null 2>&1 || true
    fi
    [ -s "$TEST_RESULTS" ] || { rm -f "$_lock"; return 1; }
    _used="$TMP_DIR/watchdog-used-$$"; : > "$_used"
    for _s in 1 2 3 4 5 6 RU RU_2; do
        eval "_uid=\${SLOT_${_s}:-}"; [ -n "$_uid" ] || continue
        _u="$(normalize_url "$(dns_url "$_uid")")"; [ -n "$_u" ] && printf '%s\n' "$_u" >> "$_used"
    done
    for _slot in 1 2 3 4 5 6 RU RU_2; do
        eval "_id=\${SLOT_${_slot}:-}"; [ -n "$_id" ] || continue
        [ "$_slot" != RU_2 ] || [ -n "${PORT_RU_2:-}" ] || continue
        _desired="$(watchdog_desired_cat "$_slot")"; _current_cat="$(dns_cat "$_id")"
        _need_return=0
        if [ "$DNS_SELECTION_MODE" = quick ] && [ "$_slot" != RU ] && [ "$_slot" != RU_2 ] && [ "$_current_cat" = clean ]; then
            _return_pref="$(watchdog_preferred_quick_candidate "$_slot" 2>/dev/null || true)"
            [ -n "$_return_pref" ] && [ "$_id" != "$_return_pref" ] && _need_return=1
        fi
        if watchdog_check_slot "$_slot"; then
            if [ "$_need_return" = 1 ]; then
                _tried="$TMP_DIR/watchdog-tried-${_slot}-$$"; : > "$_tried"; printf '%s\n' "$_id" >> "$_tried"
                _picked="$(watchdog_pick_replacement "$_slot" "$_used" "$_tried")"; _repl="${_picked%%|*}"; _repl_cat="${_picked#*|}"
                if [ -n "$_repl" ] && [ "$_repl" != "$_id" ]; then
                    printf "  ${C_YELLOW}↻ Слот %s: %s работает. Проверяю возврат %s.${C_NC}\n" "$_slot" "$(dns_name "$_id")" "$(dns_name "$_repl")"
                    if watchdog_apply_slot_candidate "$_slot" "$_repl" "$_repl_cat" "$_id" "$_current_cat"; then
                        _u="$(normalize_url "$(dns_url "$_repl")")"; grep -qxF "$_u" "$_used" 2>/dev/null || printf '%s\n' "$_u" >> "$_used"
                        printf "  ${C_GREEN}✓ Слот %s: %s возвращён.${C_NC}\n" "$_slot" "$(dns_name "$_repl")"
                    fi
                fi
                rm -f "$_tried"
            fi
            continue
        fi
        sleep 5
        watchdog_check_slot "$_slot" && continue
        log_msg "DNS в слоте $_slot: $(dns_name "$_id") не отвечает двумя локальными проверками. Ищу замену."
        _tried="$TMP_DIR/watchdog-tried-${_slot}-$$"; : > "$_tried"; _old="$_id"; _oldcat="$_current_cat"; _replacement_ok=0
        for _attempt in 1 2 3 4 5 6 7 8; do
            _picked="$(watchdog_pick_replacement "$_slot" "$_used" "$_tried")"; _repl="${_picked%%|*}"; _repl_cat="${_picked#*|}"
            [ -n "$_repl" ] || break
            [ "$_repl" = "$_old" ] && { printf '%s\n' "$_repl" >> "$_tried"; continue; }
            printf '%s\n' "$_repl" >> "$_tried"
            printf "  ${C_YELLOW}↻ Слот %s: %s не отвечает. Проверяю замену %s.${C_NC}\n" "$_slot" "$(dns_name "$_old")" "$(dns_name "$_repl")"
            if watchdog_apply_slot_candidate "$_slot" "$_repl" "$_repl_cat" "$_old" "$_oldcat"; then
                printf "  ${C_GREEN}✓ Слот %s: %s подтверждён на 127.0.0.1:%s.${C_NC}\n" "$_slot" "$(dns_name "$_repl")" "$(hybrid_desired_port "$_slot")"
                _u="$(normalize_url "$(dns_url "$_repl")")"; grep -qxF "$_u" "$_used" 2>/dev/null || printf '%s\n' "$_u" >> "$_used"
                _replacement_ok=1; break
            fi
            printf "  ${C_RED}✗ Слот %s: %s также не ответил через 127.0.0.1:%s. Больше его не пробую.${C_NC}\n" "$_slot" "$(dns_name "$_repl")" "$(hybrid_desired_port "$_slot")"
        done
        [ "$_replacement_ok" = 1 ] || _wd_rc=1
        rm -f "$_tried"
    done
    rm -f "$_used" "$_lock"
    return "$_wd_rc"
}
# ==========================================
apply_watchdog() {
    f="/etc/crontabs/root"
    [ -f "$f" ] || : > "$f" || return 1
    _interval="${WATCHDOG_INTERVAL:-15}"
    case "$_interval" in
        ''|*[!0-9]*) _interval=15 ;;
    esac
    [ "$_interval" -ge 1 ] 2>/dev/null || _interval=15
    [ "$_interval" -le 59 ] 2>/dev/null || _interval=59
    WATCHDOG_INTERVAL="$_interval"
    awk '!/^[[:space:]]*\*\/[0-9]+[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*[[:space:]]+\*.*dns-manager[[:space:]]+(watchdog|-w|--watchdog)([[:space:]]|$)/{print}' "$f" > "$f.tmp" || return 1
    mv "$f.tmp" "$f" || return 1
    if [ "${WATCHDOG_ENABLED:-0}" = 1 ]; then
        printf '*/%s * * * * %s watchdog >> %s 2>&1\n' "$WATCHDOG_INTERVAL" "$MANAGER_PATH" "$LOG_FILE" >> "$f"
        /etc/init.d/cron reload >/dev/null 2>&1 || true
        ok_msg "Автоматическая проверка DNS включена: каждые ${WATCHDOG_INTERVAL} минут."
    else
        /etc/init.d/cron reload >/dev/null 2>&1 || true
        ok_msg "Автоматическая проверка DNS выключена."
    fi
    save_config
}
# ==========================================
# ==========================================
main_menu() {
while :; do
run_discovery
menu_header "ДИСПЕТЧЕР DNS $VERSION"
menu_section "СОСТОЯНИЕ РОУТЕРА"
printf "  ${C_YELLOW}${C_BOLD}IPv4${C_NC}               %b\n" "$(state_word "$IPV4_ROUTE")"
printf "  ${C_YELLOW}${C_BOLD}IPv6${C_NC}               %b\n" "$(state_word "$IPV6_ROUTE")"
printf "  ${C_YELLOW}${C_BOLD}dnsmasq${C_NC}            %b\n" "$(state_word "$DNSMASQ_RUN")"
printf "  ${C_YELLOW}${C_BOLD}Защищённый DNS${C_NC}     %b\n" "$(state_word "$HDP_RUNNING")"
printf "  ${C_YELLOW}${C_BOLD}DNS-серверов найдено${C_NC} ${C_YELLOW}${C_BOLD}%s${C_NC}\n" "$DOH_TOTAL"
printf "  ${C_YELLOW}${C_BOLD}Каталог DNS${C_NC}              ${C_CYAN}%s • %s серверов${C_NC}\n" "$(dns_catalog_version)" "$(count_dns)"
printf "  ${C_YELLOW}${C_BOLD}Автопроверка${C_NC}            %b\n" "$(module_state_word watchdog "$WATCHDOG_ENABLED")"
[ -s "$BASELINE_MANIFEST" ] && printf "  ${C_YELLOW}${C_BOLD}Исходная копия${C_NC}      ${C_GREEN}есть${C_NC}\n" || printf "  ${C_YELLOW}${C_BOLD}Исходная копия${C_NC}      ${C_YELLOW}нет${C_NC}\n"
printf "  ${C_YELLOW}${C_BOLD}Web-доступ${C_NC}            %b\n" "$(module_state_word web "$WEB_ACCESS_ENABLED")"
[ "$FORCE_DNS" = 1 ] && printf "  ${C_YELLOW}${C_BOLD}Принудительный DNS${C_NC} ${C_CYAN}включён${C_NC}\n"
menu_section "БЫСТРЫЙ ЗАПУСК"
menu_item "[1]" "МАКСИМАЛЬНЫЙ ОБХОД"
menu_section "ПРОФИЛИ DNS"
menu_item "[2]" "Максимальная скорость"
menu_item "[3]" "Максимальная безопасность"
menu_item "[4]" "Максимальная приватность"
menu_item "[5]" "Блокировка рекламы"
menu_item "[6]" "Выбор по категориям"
menu_section "НАСТРОЙКА"
menu_item "[7]" "Карта состояния"
printf "  ${C_CYAN}${C_BOLD}%-5s${C_NC} ${C_YELLOW}${C_BOLD}%-38s${C_NC} ${C_CYAN}${C_BOLD}(%s)${C_NC}\n" "[8]" "Проверка DNS-серверов" "$(count_dns)"
printf "  ${C_WHITE}      Каталог DNS: ${C_CYAN}%s${C_NC} • ${C_CYAN}%s серверов${C_NC}\n" "$(dns_catalog_version)" "$(count_dns)"
printf "  ${C_CYAN}${C_BOLD}%-5s${C_NC} ${C_YELLOW}${C_BOLD}%-38s${C_NC} ${C_CYAN}${C_BOLD}(6+2)${C_NC}\n" "[9]" "Серверы DNS"
menu_item "[10]" "DNS ДЛЯ ЗАПУСКА"
menu_item "[11]" "СИНХРОНИЗАЦИЯ ВРЕМЕНИ"
menu_item "[12]" "НАСТРОЙКИ"
menu_item "[13]" "Состояние и журнал"
menu_item "[14]" "Показать и применить"
menu_item "[15]" "Установить недостающее"
menu_item "[16]" "Удалить изменения"
menu_back
menu_prompt
safe_read c
[ -z "$c" ] && { clear_screen; printf "${C_GREEN}Диспетчер DNS завершён.${C_NC}\n"; exit 0; }
case "$c" in
1) prepare_dns_operation || { pause; continue; }; quick_max_bypass ;;
2) prepare_dns_operation || { pause; continue; }; menu_best_actions clean "БЫСТРАЯ НАСТРОЙКА" ;;
3) prepare_dns_operation || { pause; continue; }; menu_best_actions security "МАКСИМАЛЬНАЯ БЕЗОПАСНОСТЬ" ;;
4) prepare_dns_operation || { pause; continue; }; menu_best_actions privacy "МАКСИМАЛЬНАЯ ПРИВАТНОСТЬ" ;;
5) prepare_dns_operation || { pause; continue; }; menu_best_actions adblock "БЛОКИРОВКА РЕКЛАМЫ" ;;
6) prepare_dns_operation || { pause; continue; }; show_best ;;
7) show_map ;;
8) prepare_dns_operation || { pause; continue; }; test_dns_catalog; show_tests ;;
9) prepare_dns_operation || { pause; continue; }; menu_slots ;;
10) prepare_dns_operation || { pause; continue; }; menu_bootstrap ;;
11) prepare_dns_operation || { pause; continue; }; menu_ntp ;;
12) prepare_dns_operation || { pause; continue; }; menu_extras ;;
13) menu_status ;;
14) prepare_dns_operation || { pause; continue; }; apply_settings ;;
15) menu_install ;;
16)
clear_screen
menu_header "УДАЛЕНИЕ ИЗМЕНЕНИЙ"
warn_msg "Будут удалены только изменения диспетчера DNS."
if confirm_action "Удалить изменения?"; then rollback_ours; else info_msg "Отменено."; fi
;;
*) warn_msg "Неизвестный пункт."; pause ;;
esac
done
}
case "${1:-}" in
watchdog|--watchdog|-w)
    preflight_readonly
    init_dirs
    run_discovery
    install_missing_dependencies || exit 1
    write_catalogs
    load_config
    log_msg "Запуск автоматической проверки DNS."
    run_watchdog
    exit $?
    ;;
esac
preflight_readonly
init_dirs
run_discovery
install_missing_dependencies || exit 1
auto_update_manager
write_catalogs
load_config
if [ "${_had_dns_profile:-1}" = 0 ]; then
hybrid_set_defaults
save_config
printf "${C_YELLOW}ℹ Обнаружена старая конфигурацию без профиля. Создан основной профиль Гибридный DNS (без изменения настроек роутера).${C_NC}\n"
fi
run_discovery
printf "${C_GREEN}✓ Первый проход завершён. Настройки роутера не изменены.${C_NC}\n"
printf "${C_YELLOW}ℹ DNS-серверов в списке: %s.${C_NC}\n" "$(count_dns)"
log_msg "Запуск диспетчера DNS. Версия $VERSION. OpenWrt=$SYS_OWRT; платформа=$SYS_TARGET; архитектура=$SYS_ARCH; firewall=$SYS_FW"
main_menu
