#!/bin/sh
# DNS Manager LuCI companion and full installer
# Version: 2.130
# install bootstraps the backend, required packages and native LuCI UI.
# update refreshes only the LuCI companion for the in-panel updater.
# It does not install ttyd and does not open another HTTP port.

set -eu

APP="dns-manager-luci"
MANAGER="/usr/bin/dns-manager"
RPC_PLUGIN="/usr/libexec/rpcd/dns_manager"
BACKEND_FILE="/usr/lib/dns-manager-luci/backend.sh"
ACL_FILE="/usr/share/rpcd/acl.d/luci-app-dns-manager.json"
MENU_FILE="/usr/share/luci/menu.d/luci-app-dns-manager.json"
VIEW_DIR="/www/luci-static/resources/view/dns-manager"
RESOURCE_DIR="/www/luci-static/resources/dns-manager"
COMMON_FILE="$RESOURCE_DIR/common.js"
VIEW_FILE="/www/luci-static/resources/view/dns-manager/dashboard.js"
RUNTIME_DIR="/var/run/dns-manager-luci"
JOB_DIR="$RUNTIME_DIR/jobs"
# Hard wall-clock limits for persistent background jobs. Browser timer throttling
# must not make a DNS job appear to run forever.
JOB_MAX_AGE_PROFILE=900
JOB_MAX_AGE_TEST_ALL=1800
JOB_MAX_AGE_TEST_CURRENT=300
JOB_MAX_AGE_TEST_ONE=60

BACKUP_DIR="/etc/dns-manager-luci"
CONFIG_FILE="/etc/dns-manager/config/manager.conf"
STATE_FILE="/etc/dns-manager/config/luci-state.conf"
# Legacy update compatibility: admin/services/dns_manager
VERSION_FILE="$BACKUP_DIR/version"
VERSION="2.141"
ASSET_VERSION="v$(printf '%s' "$VERSION" | tr '.' '_')"

say() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }

# A test or development branch can be selected explicitly for a complete
# installer run. Released installs keep using main by default.
SOURCE_REF="${DNS_MANAGER_SOURCE_REF:-}"
if [ -z "$SOURCE_REF" ]; then
    _installed_source="$(sed -n 's/^source=//p' "$VERSION_FILE" 2>/dev/null | head -n1)"
    case "$_installed_source" in
        https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/*/dns-manager-luci.sh)
            SOURCE_REF="${_installed_source#https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/}"
            SOURCE_REF="${SOURCE_REF%/dns-manager-luci.sh}"
            ;;
    esac
fi
SOURCE_REF="${SOURCE_REF:-main}"
case "$SOURCE_REF" in
    ''|/*|*//*|*..*|*[!A-Za-z0-9._/-]*)
        err "Некорректное имя ветки DNS_MANAGER_SOURCE_REF."
        exit 2
        ;;
esac
SOURCE_BASE="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/$SOURCE_REF"
COMPANION_URL="$SOURCE_BASE/dns-manager-luci.sh"
BACKEND_URL="$SOURCE_BASE/dns-manager.sh"

fetch_installer_source() {
    _out="$1"
    _url="$2"
    rm -f "$_out" 2>/dev/null || true
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 5 --max-time 60 -o "$_out" "$_url" || return 1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 60 -O "$_out" "$_url" || return 1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -T 60 -O "$_out" "$_url" || return 1
    else
        err "Не найден curl, wget или uclient-fetch для загрузки установщика."
        return 1
    fi
    [ -s "$_out" ] || { err "Загруженный файл пуст: $_url"; return 1; }
}

install_runtime_packages() {
    if command -v apk >/dev/null 2>&1; then
        apk update || { err "Не удалось обновить индекс пакетов apk."; return 1; }
        apk add "$@" || { err "Не удалось установить пакеты: $*"; return 1; }
    elif command -v opkg >/dev/null 2>&1; then
        opkg update || { err "Не удалось обновить список пакетов opkg."; return 1; }
        opkg install "$@" || { err "Не удалось установить пакеты: $*"; return 1; }
    else
        err "Не найден менеджер пакетов apk/opkg."
        return 1
    fi
}

ensure_luci_webui() {
    if [ -x /www/cgi-bin/luci ]; then
        say "✓ Системный LuCI уже установлен."
        return 0
    fi

    say "↻ Системный LuCI не найден. Устанавливаю официальный пакет luci..."
    install_runtime_packages luci || return 1
    [ -x /www/cgi-bin/luci ] || {
        err "Пакет luci установлен, но точка входа /www/cgi-bin/luci не найдена."
        return 1
    }

    if [ -x /etc/init.d/uhttpd ]; then
        /etc/init.d/uhttpd enable >/dev/null 2>&1 || true
        /etc/init.d/uhttpd start >/dev/null 2>&1 || true
    fi
    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd enable >/dev/null 2>&1 || true
        /etc/init.d/rpcd start >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
    fi
    say "✓ Системный LuCI установлен."
}

install_backend() {
    _candidate="/tmp/dns-manager-backend.$$.download"
    _stage="/usr/bin/dns-manager.new.$$"
    _backup="/tmp/dns-manager-backend.$$.backup"
    _had_manager=0
    _mark_first_run=0

    fetch_installer_source "$_candidate" "$BACKEND_URL" || {
        rm -f "$_candidate" "$_stage" 2>/dev/null || true
        err "Не удалось загрузить backend DNS Manager с GitHub."
        return 1
    }
    sh -n "$_candidate" || {
        rm -f "$_candidate" "$_stage" 2>/dev/null || true
        err "Backend DNS Manager не прошёл проверку shell-синтаксиса."
        return 1
    }
    grep -Eq '^VERSION="[0-9]+([.][0-9]+)*"$' "$_candidate" || {
        rm -f "$_candidate" "$_stage" 2>/dev/null || true
        err "В backend не найдена корректная версия."
        return 1
    }
    grep -Fq 'install-dependencies|--install-dependencies)' "$_candidate" || {
        rm -f "$_candidate" "$_stage" 2>/dev/null || true
        err "Backend не поддерживает подготовку зависимостей без запуска консольного меню."
        return 1
    }
    mkdir -p /usr/bin || return 1
    if [ -x "$MANAGER" ]; then
        cp "$MANAGER" "$_backup" || {
            rm -f "$_candidate" "$_stage" 2>/dev/null || true
            err "Не удалось сохранить backend для отката."
            return 1
        }
        _had_manager=1
    fi
    if [ ! -f "$CONFIG_FILE" ] && [ ! -f "/etc/dns-manager/config/.first-run.done" ]; then
        _mark_first_run=1
    fi
    cp "$_candidate" "$_stage" &&
        chmod 0755 "$_stage" &&
        mv -f "$_stage" "$MANAGER" || {
            [ "$_had_manager" = 1 ] && cp "$_backup" "$MANAGER" 2>/dev/null || true
            rm -f "$_candidate" "$_stage" "$_backup" 2>/dev/null || true
            err "Не удалось безопасно установить backend DNS Manager."
            return 1
        }
    rm -f "$_candidate" 2>/dev/null || true

    if ! DNS_MANAGER_BOOTSTRAP_MARK_FIRST_RUN="$_mark_first_run" "$MANAGER" --install-dependencies; then
        if [ "$_had_manager" = 1 ]; then
            cp "$_backup" "$MANAGER" 2>/dev/null || true
        else
            rm -f "$MANAGER" 2>/dev/null || true
        fi
        rm -f "$_backup" 2>/dev/null || true
        err "Не удалось подготовить зависимости backend. Предыдущий backend восстановлен, если он был."
        return 1
    fi

    rm -f "$_backup" 2>/dev/null || true
    say "✓ DNS Manager backend установлен; зависимости проверены."
}

full_install() {
    [ "$(id -u 2>/dev/null)" = 0 ] || { err "Установщик нужно запускать с правами root."; return 1; }
    [ -f /etc/openwrt_release ] || { err "Этот установщик предназначен для OpenWrt."; return 1; }
    say "DNS Manager — установка Native LuCI"
    ensure_luci_webui || return 1
    install_backend || return 1
    install_files || return 1
    say ""
    say "✓ Установка завершена."
    say "Откройте веб-интерфейс роутера → LuCI → Службы → DNS Manager."
    say "DNS-профиль автоматически не применялся. Завершите настройку в панели."
}

manager_version() {
    [ -r "$MANAGER" ] || return 1
    awk -F'"' '/^[[:space:]]*VERSION="/ { print $2; exit }' "$MANAGER" 2>/dev/null
}

require_manager() {
    [ -x "$MANAGER" ] || { err "Не найден $MANAGER. Сначала установите DNS Manager."; return 1; }
    [ -n "$(manager_version 2>/dev/null || true)" ] || { err "Не удалось определить версию DNS Manager."; return 1; }
}

# Publish every asset before changing the menu. The old menu and its files
# remain usable if any step fails. Keep the previous version for open tabs.
publish_versioned_assets() {
    [ -s "$COMMON_FILE" ] || { err 'Общий модуль LuCI не готов.'; return 1; }
    for _asset_page in dashboard doh slots devices network time catalog log; do
        [ -s "$VIEW_DIR/${_asset_page}.js" ] || { err "Страница LuCI $_asset_page не готова."; return 1; }
    done
    _asset_hash="$(cat "$COMMON_FILE" "$VIEW_DIR/dashboard.js" "$VIEW_DIR/doh.js" "$VIEW_DIR/slots.js" "$VIEW_DIR/devices.js" "$VIEW_DIR/network.js" "$VIEW_DIR/time.js" "$VIEW_DIR/catalog.js" "$VIEW_DIR/log.js" 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}')"
    case "$_asset_hash" in ''|*[!0-9a-f]*) err 'Не удалось вычислить версию файлов LuCI.'; return 1;; esac
    [ "${#_asset_hash}" = 64 ] || { err 'Неполная контрольная сумма файлов LuCI.'; return 1; }
    _asset_id="${ASSET_VERSION}_${_asset_hash}"
    case "${_asset_id#v}" in ''|*[!0-9a-f_]*) err 'Некорректная версия файлов LuCI.'; return 1;; esac
    _prev_asset="$(sed -n 's|.*"path": "dns-manager/\(v[0-9a-f_]*\)/dashboard".*|\1|p' "$MENU_FILE" 2>/dev/null | head -n1)"
    case "${_prev_asset#v}" in ''|*[!0-9a-f_]*) _prev_asset='';; esac
    mkdir -p "$RESOURCE_DIR/$_asset_id" "$VIEW_DIR/$_asset_id" || return 1
    _common_tmp="$RESOURCE_DIR/$_asset_id/common.js.new.$$"
    cp "$COMMON_FILE" "$_common_tmp" && chmod 0644 "$_common_tmp" && mv -f "$_common_tmp" "$RESOURCE_DIR/$_asset_id/common.js" || { rm -f "$_common_tmp"; return 1; }
    for _asset_page in dashboard doh slots devices network time catalog log; do
        _asset_tmp="$VIEW_DIR/$_asset_id/${_asset_page}.js.new.$$"
        sed "s|'require dns-manager.common as DM';|'require dns-manager.${_asset_id}.common as DM';|" "$VIEW_DIR/${_asset_page}.js" > "$_asset_tmp" || return 1
        grep -Fq "'require dns-manager.${_asset_id}.common as DM';" "$_asset_tmp" || return 1
        chmod 0644 "$_asset_tmp" && mv -f "$_asset_tmp" "$VIEW_DIR/$_asset_id/${_asset_page}.js" || return 1
    done
    _menu_versioned="${_menu_stage}.versioned"
    sed "s|\"path\": \"dns-manager/|\"path\": \"dns-manager/${_asset_id}/|g" "$_menu_stage" > "$_menu_versioned" || return 1
    [ "$(grep -c "\"path\": \"dns-manager/${_asset_id}/" "$_menu_versioned")" = 8 ] || return 1
    chmod 0644 "$_menu_versioned" && mv -f "$_menu_versioned" "$MENU_FILE" || return 1
    rm -f "$_menu_stage" 2>/dev/null || true
    for _asset_dir in "$RESOURCE_DIR"/v* "$VIEW_DIR"/v*; do
        [ -d "$_asset_dir" ] || continue
        _asset_name="${_asset_dir##*/}"
        case "${_asset_name#v}" in ''|*[!0-9a-f_]*) continue;; esac
        [ "$_asset_name" = "$_asset_id" ] && continue
        [ -n "$_prev_asset" ] && [ "$_asset_name" = "$_prev_asset" ] && continue
        rm -rf "$_asset_dir" 2>/dev/null || true
    done
}

install_dnscrypt_assets() (
    set -eu
    _dc_dest="${DNS_MANAGER_DNSCRYPT_INSTALL_DIR:-/usr/lib/dns-manager-luci/dnscrypt}"
    mkdir -p "$_dc_dest"
    _dc_stage="$(mktemp -d "$_dc_dest/.stage.XXXXXX")"
    trap 'rm -rf "$_dc_stage"' EXIT
    cat > "$_dc_stage/dns-manager-doh-stamp.sh" <<'EOF_DNSCRYPT_ASSET_1'
#!/bin/sh
# Convert an HTTPS DoH endpoint or validate a DNSCrypt stamp.
# This helper does not change DNS settings or start any service.
set -eu
LC_ALL=C
export LC_ALL

fail() { printf '%s\n' "Unsupported DoH URL: $1" >&2; exit 1; }
[ "$#" -eq 1 ] || fail 'expected one URL'
case "$1" in
    sdns://*)
        stamp=${1#sdns://}
        case "$stamp" in ''|*[!A-Za-z0-9_-]*) fail 'invalid stamp encoding' ;; esac
        [ "${#stamp}" -le 1024 ] || fail 'stamp too long'
        case $((${#stamp} % 4)) in 0) padding= ;; 2) padding='==' ;; 3) padding='=' ;; *) fail 'invalid stamp encoding' ;; esac
        if command -v base64 >/dev/null 2>&1; then
            decode() { base64 -d; }
        elif command -v ucode >/dev/null 2>&1; then
            decode() { ucode -e 'import { stdin } from "fs"; print(b64dec(stdin.read("all")));'; }
        else
            fail 'neither base64 nor ucode is available'
        fi
        if command -v hexdump >/dev/null 2>&1; then
            decimal_bytes() { hexdump -v -e '1/1 "%u "'; }
        elif command -v od >/dev/null 2>&1; then
            decimal_bytes() { od -An -v -tu1; }
        else
            fail 'neither hexdump nor od is available'
        fi
        bytes=$(printf '%s%s' "$stamp" "$padding" | tr '_-' '/+' | decode | decimal_bytes) || fail 'invalid stamp encoding'
        printf '%s\n' "$bytes" | awk '
            { for (i = 1; i <= NF; i++) b[++n] = $i }
            END {
                if (n < 44 || b[1] != 1) exit 1
                p = 10; addr = b[p]; p += addr + 1
                if (addr < 1 || p > n || b[p] != 32) exit 1
                p += 33
                if (p > n || b[p] < 1 || p + b[p] != n) exit 1
            }
        ' || fail 'invalid DNSCrypt stamp'
        printf '%s\n' "$1"
        exit 0
        ;;
esac
case "$1" in https://*) rest=${1#https://} ;; *) fail 'HTTPS is required' ;; esac
case "$rest" in *'?'*|*'#'*|*'@'*|*[![:graph:]]*) fail 'query, fragment, credentials or whitespace' ;; esac
case "$rest" in */*) host=${rest%%/*}; path=/${rest#*/} ;; *) host=$rest; path=/ ;; esac
[ -n "$host" ] || fail 'missing hostname'
case "$host" in *[!a-zA-Z0-9.:-]*|.*|*..*|*:|:*|*:*:*) fail 'invalid hostname or port' ;; esac
case "$host" in
    *:*) port=${host##*:}; host_name=${host%:*};
        case "$port" in ''|*[!0-9]*) fail 'invalid port' ;; esac
        [ "${#port}" -le 5 ] && [ "$port" -gt 0 ] && [ "$port" -le 65535 ] || fail 'invalid port'
        ;;
    *) host_name=$host ;;
esac
[ -n "$host_name" ] || fail 'missing hostname'
case "$path" in *[!a-zA-Z0-9._~/%!\$\&\'\(\)\*\+,\;=:@-]*) fail 'unsupported path character' ;; esac
[ "${#host}" -le 255 ] && [ "${#path}" -le 255 ] || fail 'hostname or path too long'

lp() {
    length=${#1}
    octal=$(printf '%03o' "$length")
    printf "\\$octal%s" "$1"
}

# DNS-over-HTTPS, zero properties, no fixed IP or certificate pin.
# With no pin dnscrypt-proxy uses its normal TLS certificate validation.
if command -v base64 >/dev/null 2>&1; then
    encode() { base64; }
elif command -v ucode >/dev/null 2>&1; then
    encode() { ucode -e 'import { stdin } from "fs"; print(b64enc(stdin.read("all")));'; }
else
    fail 'neither base64 nor ucode is available'
fi
encoded=$({
    printf '\002\000\000\000\000\000\000\000\000\000\000'
    lp "$host"
    lp "$path"
} | encode) || fail 'base64 encoding failed'
[ -n "$encoded" ] || fail 'base64 encoding failed'
encoded=$(printf '%s' "$encoded" | tr -d '\n=' | tr '/+' '_-')
printf 'sdns://%s\n' "$encoded"
EOF_DNSCRYPT_ASSET_1
    cat > "$_dc_stage/dns-manager-dnscrypt-config.sh" <<'EOF_DNSCRYPT_ASSET_2'
#!/bin/sh
# Experimental config generator. It only prints TOML; it never starts a service.
set -eu
LC_ALL=C
export LC_ALL

fail() { printf '%s\n' "$1" >&2; exit 1; }
[ "$#" -eq 3 ] || fail 'Expected local port, DoH URL and bootstrap IP list'
port=$1
case "$port" in ''|*[!0-9]*) fail 'Invalid local port' ;; esac
[ "${#port}" -le 5 ] && [ "$port" -gt 0 ] && [ "$port" -le 65535 ] || fail 'Invalid local port'
helper="$(dirname "$0")/dns-manager-doh-stamp.sh"
stamp=$(sh "$helper" "$2") || fail 'Unable to encode DoH address'

# Same public literal-address rules as bootstrap_normalize_addresses in the
# manager. Formatting is performed only after validating the complete list.
resolvers=$(printf '%s\n' "$3" | awk '
function ipv4(s,a,n,i) {
 n=split(s,a,"."); if(n!=4) return 0
 for(i=1;i<=4;i++) if(a[i] !~ /^[0-9]+$/ || length(a[i])>3 || a[i]+0>255 || (length(a[i])>1 && substr(a[i],1,1)=="0")) return 0
 return a[1]+0>0 && a[1]+0!=127 && a[1]+0<224
}
function ipv6(s,a,n,i,parts,compressed,nonzero) {
 if(s !~ /^[0-9a-fA-F:]+$/ || index(s,":")==0 || s=="::" || s=="::1") return 0
 if(s ~ /^:[^:]/ || s ~ /[^:]:$/ || s ~ /:::/) return 0
 compressed=(index(s,"::")>0)
 if(compressed) { if(index(substr(s,index(s,"::")+2),"::")>0) return 0; sub(/::/,":Z:",s); sub(/^:/,"",s); sub(/:$/,"",s) }
 if(s ~ /^:/ || s ~ /:$/ || s ~ /::/) return 0
 n=split(s,a,":"); parts=0; nonzero=0
 for(i=1;i<=n;i++) { if(a[i]=="Z") continue; if(a[i] !~ /^[0-9a-fA-F]+$/ || length(a[i])>4) return 0; parts++; if(a[i] !~ /^0+$/) nonzero++ }
 if(nonzero==0 || (nonzero==1 && a[n] ~ /^0*1$/)) return 0
 return compressed ? parts<8 : parts==8
}
NR>1 { bad=1; exit }
{
 gsub(/[,[:space:]]+/," "); sub(/^ /,""); sub(/ $/,"")
 n=split($0,a," "); if(n<1 || n>48 || a[1]=="") { bad=1; exit }
 for(i=1;i<=n;i++) {
  ip=tolower(a[i]); if((!ipv4(ip) && !ipv6(ip)) || seen[ip]++) { bad=1; exit }
  addr=index(ip,":") ? "[" ip "]:53" : ip ":53"
  result=result (i==1 ? "" : ", ") "\047" addr "\047"
 }
}
END { if(bad || NR!=1) exit 1; print result }
') || fail 'Invalid bootstrap addresses'
[ -n "$resolvers" ] || fail 'Empty bootstrap list'

printf "server_names = ['manager-slot']\n"
strategy=${DNS_MANAGER_LB_STRATEGY:-p2}
case "$strategy" in wp2|p2|p3|p4|p5|p6|ph|first|random) ;; *) fail 'Invalid load balancing strategy';; esac
protocol=${DNS_MANAGER_PROTOCOL:-mixed}
case "$protocol" in mixed|native) ;; *) fail 'Invalid DNS protocol';; esac
printf "lb_strategy = '%s'\n" "$strategy"
if [ "$protocol" = native ]; then
    printf "dnscrypt_servers = true\ndoh_servers = false\n"
fi
printf "listen_addresses = ['127.0.0.1:%s']\n" "$port"
# Values are Manager-owned and survive regeneration after profile changes.
setting() {
    value=$(uci -q get "dns-manager.global.dc_$1" 2>/dev/null || :)
    case "$value" in 0) printf false;; 1) printf true;; *) printf "%s" "$2";; esac
}
printf "cache = %s\n" "$(setting cache true)"
printf "force_tcp = %s\n" "$(setting force_tcp false)"
printf "block_ipv6 = %s\n" "$(setting block_ipv6 false)"
printf "block_unqualified = %s\n" "$(setting block_unqualified true)"
printf "block_undelegated = %s\n" "$(setting block_undelegated true)"
# Keep existing defaults unless a Manager preset has been selected.
cache_size=$(uci -q get dns-manager.global.dc_cache_size 2>/dev/null || :)
case "$cache_size" in 1000|4096|10000) ;; *) cache_size=4096;; esac
cache_ttl=$(uci -q get dns-manager.global.dc_cache_ttl 2>/dev/null || :)
case "$cache_ttl" in 0|300|900|1800) ;; *) cache_ttl=0;; esac
printf "cache_size = %s\ncache_min_ttl = %s\n" "$cache_size" "$cache_ttl"
printf "cache_neg_min_ttl = 0\n"
if [ "${DNS_MANAGER_QUERY_LOG:-0}" = 1 ]; then
    printf "log_files_max_size = 1\nlog_files_max_backups = 1\n"
fi
printf "bootstrap_resolvers = [%s]\n" "$resolvers"
printf "ignore_system_dns = true\n"
printf "[static.manager-slot]\n"
printf "stamp = '%s'\n" "$stamp"
EOF_DNSCRYPT_ASSET_2
    cat > "$_dc_stage/dns-manager-dnscrypt-pool.sh" <<'EOF_DNSCRYPT_ASSET_3'
#!/bin/sh
# Experimental one-process DoH pool. Reads one endpoint URL per input line.
# Prints a complete config only after all endpoints and bootstrap IPs validate.
set -eu
LC_ALL=C
export LC_ALL

[ "$#" -eq 2 ] || { echo 'Expected local port and bootstrap IP list' >&2; exit 1; }
port=$1
bootstrap=$2
generator="$(dirname "$0")/dns-manager-dnscrypt-config.sh"
dir=$(mktemp -d /tmp/dns-manager-pool.XXXXXX) || exit 1
trap 'rm -rf "$dir"' EXIT HUP INT TERM
: > "$dir/urls"
: > "$dir/stamps"
count=0

while IFS= read -r url || [ -n "$url" ]; do
    [ -n "$url" ] || { echo 'Empty DoH URL' >&2; exit 1; }
    count=$((count + 1))
    [ "$count" -le 6 ] || { echo 'At most six DoH endpoints are supported' >&2; exit 1; }
    # An absent path and the root path name the same HTTP endpoint.
    key=$url
    case "${url#https://}" in */*) [ "${url#https://*/}" != '' ] || key=${url%/} ;; esac
    if grep -Fqx -- "$key" "$dir/urls"; then echo 'Duplicate DoH URL' >&2; exit 1; fi
    printf '%s\n' "$key" >> "$dir/urls"
    sh "$generator" "$port" "$url" "$bootstrap" > "$dir/item" || exit 1
    stamp=$(sed -n "s/^stamp = '\(sdns:\/\/[A-Za-z0-9_-]*\)'$/\1/p" "$dir/item")
    [ -n "$stamp" ] || { echo 'Invalid generated DNS stamp' >&2; exit 1; }
    [ "$count" -ne 1 ] || cp "$dir/item" "$dir/first"
    printf '%s\n' "$stamp" >> "$dir/stamps"
done
[ "$count" -gt 0 ] || { echo 'At least one DoH endpoint is required' >&2; exit 1; }

{
    printf 'server_names = ['
    i=1
    while [ "$i" -le "$count" ]; do
        [ "$i" -eq 1 ] || printf ', '
        printf "'manager-%s'" "$i"
        i=$((i + 1))
    done
    printf ']\n'
    sed -n '2,/^\[static\./{ /^\[static\./d; p; }' "$dir/first"
    i=1
    while IFS= read -r stamp; do
        printf "[static.manager-%s]\nstamp = '%s'\n" "$i" "$stamp"
        i=$((i + 1))
    done < "$dir/stamps"
    if [ "${DNS_MANAGER_QUERY_LOG:-0}" = 1 ]; then
        printf "[query_log]\nfile = '/tmp/dns-manager-dnscrypt-query.log'\nformat = 'tsv'\n"
    fi
} > "$dir/output"
cat "$dir/output"
EOF_DNSCRYPT_ASSET_3
    cat > "$_dc_stage/dns-manager-dnscrypt-pool-apply.sh" <<'EOF_DNSCRYPT_ASSET_4'
#!/bin/sh
# Apply a Manager-owned pool. Caller must hold DNS Manager's mutation lock.
# Reads DoH URLs from stdin; no dnsmasq, firewall or other package settings
# are changed here. For initial setup the caller must keep dnsmasq on its
# previous working upstream until this function has succeeded.
set -eu

[ "$#" -eq 2 ] || { echo 'Expected local port and bootstrap IP list' >&2; exit 1; }
port=$1
bootstrap=$2
binary=${DNS_MANAGER_DNSCRYPT_BIN:-/usr/sbin/dnscrypt-proxy}
init=${DNS_MANAGER_DNSCRYPT_INIT:-/etc/init.d/dnscrypt-proxy}
config=${DNS_MANAGER_DNSCRYPT_CONFIG:-/etc/dnscrypt-proxy2/dnscrypt-proxy.toml}
generator="$(dirname "$0")/dns-manager-dnscrypt-pool.sh"
[ -x "$binary" ] && [ -x "$init" ] && [ ! -L "$config" ] || { echo 'DNSCrypt service or config unavailable' >&2; exit 1; }
had_config=0
if [ -e "$config" ]; then
    [ -f "$config" ] || { echo 'DNSCrypt config is not a regular file' >&2; exit 1; }
    had_config=1
fi

dir=$(dirname "$config")
candidate=$(mktemp "$dir/.dnscrypt-pool-new.XXXXXX") || exit 1
backup=$(mktemp "$dir/.dnscrypt-pool-old.XXXXXX") || { rm -f "$candidate"; exit 1; }
changed=0
cleanup() {
    rm -f "$candidate"
    if [ "$changed" -eq 1 ]; then
        if [ "$had_config" -eq 0 ]; then
            "$init" stop >/dev/null 2>&1 || echo 'Failed to stop new DNSCrypt service' >&2
            rm -f "$config" "$backup" || echo 'Failed to remove new DNSCrypt config' >&2
        elif mv -f "$backup" "$config"; then
            "$init" restart >/dev/null 2>&1 || echo 'Failed to restart restored DNSCrypt config' >&2
        else
            echo "Failed to restore previous DNSCrypt config; backup retained at $backup" >&2
        fi
    else
        rm -f "$backup"
    fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
DNS_MANAGER_QUERY_LOG=$(uci -q get dns-manager.global.dc_query_log 2>/dev/null || :)
export DNS_MANAGER_QUERY_LOG
sh "$generator" "$port" "$bootstrap" > "$candidate" || exit 1
"$binary" -config "$candidate" -check >/dev/null 2>&1 || { echo 'Invalid DNSCrypt pool configuration' >&2; exit 1; }
[ "$had_config" -eq 0 ] || cp -p "$config" "$backup" || exit 1
chmod 0600 "$candidate" || exit 1
mv -f "$candidate" "$config" || exit 1
changed=1

pool_query_ok() {
    if command -v dig >/dev/null 2>&1; then
        dig @127.0.0.1 -p "$port" example.com A +time=2 +tries=1 +short 2>/dev/null |
            awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $0 !~ /^127\./ && $0 != "0.0.0.0" {ok=1} END {exit !ok}'
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup -port="$port" example.com 127.0.0.1 2>/dev/null |
            awk '/^Address [0-9]+: / {a=$NF} /^Address: / {a=$2} a ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && a !~ /^127\./ && a != "0.0.0.0" {ok=1} END {exit !ok}'
    else
        return 1
    fi
}

ok=0
if "$init" restart >/dev/null 2>&1; then
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        if "$init" running >/dev/null 2>&1 && pool_query_ok; then ok=1; break; fi
        sleep 1
    done
fi
if [ "$ok" -eq 1 ]; then changed=0; exit 0; fi

# Preserve the previous pool when the new service or DNS query fails.
echo 'New DNSCrypt pool did not answer; restoring previous config' >&2
exit 1
EOF_DNSCRYPT_ASSET_4
    cat > "$_dc_stage/dns-manager-dnscrypt-profile.sh" <<'EOF_DNSCRYPT_ASSET_5'
#!/bin/sh
# Sourced by a future DNSCrypt backend after the existing manager functions are
# loaded. Selects DNS using the existing checks without applying configuration.
# On success stdout contains one catalog ID and URL per line, separated by '|'.
dnscrypt_select_profile() (
    local goal tmp started id url count ms priority native_id native_ms native_url native_scope native_category snapshot_rc
    goal=${1:-}
    case "$goal" in bypass|clean|security|privacy|adblock|family|all|dnssec) ;; *) return 1 ;; esac
    tmp=$(mktemp "${TMP_DIR:-/tmp}/dnscrypt-profile.XXXXXX") || return 1
    started=0
    cleanup_dnscrypt_profile() {
        if [ "$started" = 1 ]; then profile_apply_end >&2; fi
        rm -f "$tmp" "$tmp.native"
    }
    trap cleanup_dnscrypt_profile EXIT
    trap 'exit 1' HUP INT TERM
    # This invokes the existing direct DoH tests, including DNSSEC screening.
    if [ "${DNS_MANAGER_PROTOCOL:-mixed}" = native ]; then
        SLOT_1=''; SLOT_2=''; SLOT_3=''; SLOT_4=''; SLOT_5=''; SLOT_6=''
    else
    started=1
    if profile_apply_begin "$goal" >&2; then
        DNSCRYPT_FASTEST_ALL=1 auto_fill_slots "$goal" >&2 || {
            SLOT_1=''; SLOT_2=''; SLOT_3=''; SLOT_4=''; SLOT_5=''; SLOT_6=''
        }
    else
        [ "$goal" = dnssec ] && command -v dig >/dev/null 2>&1 || return 1
        SLOT_1=''; SLOT_2=''; SLOT_3=''; SLOT_4=''; SLOT_5=''; SLOT_6=''
    fi
    fi
    count=0
    for id in "${SLOT_1:-}" "${SLOT_2:-}" "${SLOT_3:-}" "${SLOT_4:-}" "${SLOT_5:-}" "${SLOT_6:-}"; do
        [ -n "$id" ] || continue
        case "$id" in *[!A-Za-z0-9_-]*) return 1 ;; esac
        url=$(normalize_url "$(dns_url "$id")") || return 1
        case "$url" in https://*) ;; *) return 1 ;; esac
        case "$url" in *'|'*|*[![:graph:]]*) return 1 ;; esac
        ms=$(awk -F'|' -v id="$id" '$1==id && $5=="OK" && $4 ~ /^[0-9]+$/ {print $4; exit}' "${TEST_RESULTS:-/dev/null}" 2>/dev/null)
        case "$ms" in ''|*[!0-9]*) ms=2147483647;; esac
        priority=0
        if [ "$goal" = dnssec ]; then
            [ "$(awk -F'|' -v id="$id" '$1==id {print $2; exit}' "${TEST_RESULTS:-/dev/null}")" != privacy ] || priority=1
        fi
        printf '%s|%s|%s|%s\n' "$id" "$url" "$ms" "$priority" >> "$tmp" || return 1
        count=$((count + 1))
    done
    if command -v dnscrypt_catalog_snapshot >/dev/null 2>&1; then
        native_scope=$goal; case "$goal" in all) native_scope=native;; esac
        snapshot_rc=0
        dnscrypt_catalog_snapshot "$native_scope" > "$tmp.native" || snapshot_rc=$?
        if [ "$snapshot_rc" -ne 0 ]; then
            echo 'Не удалось проверить серверы DNSCrypt. Проверьте доступность службы и сети.' >&2
        fi
        while IFS='|' read -r native_id native_ms; do
            case "$native_ms" in ''|*[!0-9]*) continue;; esac
            native_url=$(awk -F'|' -v id="$native_id" '$1==id {print $5; exit}' "${NATIVE_CATALOG:-$HELPERS/dns-manager-dnscrypt-catalog.conf}")
            priority=0
            if [ "$goal" = dnssec ]; then
                native_category=$(awk -F'|' -v id="$native_id" '$1==id {print $2; exit}' "${NATIVE_CATALOG:-$HELPERS/dns-manager-dnscrypt-catalog.conf}")
                case "$native_category" in clean|privacy) ;; *) continue;; esac
                [ "$native_category" != privacy ] || priority=1
                [ -n "$native_url" ] && dnscrypt_native_dnssec_probe "$native_url" || continue
            fi
            [ -n "$native_url" ] && printf '%s|%s|%s|%s\n' "$native_id" "$native_url" "$native_ms" "$priority" >> "$tmp"
        done < "$tmp.native"
        if [ "$snapshot_rc" -eq 0 ] && [ -s "$tmp.native" ] && ! awk -F'|' '$2 ~ /^[0-9]+$/ {found=1} END {exit !found}' "$tmp.native"; then
            echo 'Серверы DNSCrypt не ответили или проверка не завершилась. Проверьте доступ к сети и повторите.' >&2
        fi
        rm -f "$tmp.native"
    fi
    if [ ! -s "$tmp" ]; then
        if [ "${DNS_MANAGER_PROTOCOL:-mixed}:$goal" = native:bypass ]; then
            echo 'В каталоге нет DNSCrypt-серверов для обхода геоблокировок. Выберите смешанный режим или другой профиль.' >&2
        else
            echo 'Для выбранного профиля и протокола не найдено доступных серверов.' >&2
        fi
        return 1
    fi
    sort -t'|' -k4,4n -k3,3n "$tmp" | head -n 6 | cut -d'|' -f1,2
)
EOF_DNSCRYPT_ASSET_5
    cat > "$_dc_stage/dns-manager-dnscrypt-profile-apply.sh" <<'EOF_DNSCRYPT_ASSET_6'
#!/bin/sh
# Sourced by the DNSCrypt backend after the manager and selector are loaded.
# The caller owns the DNS Manager mutation lock and commits UI metadata only
# after this function succeeds. stdout is the applied catalog ID|URL list.
dnscrypt_apply_profile_pool() (
    local goal port bootstrap apply dnsmasq_apply records urls config init backup had_config
    goal=${1:-}
    port=${2:-}
    bootstrap=${3:-}
    apply=${DNS_MANAGER_DNSCRYPT_POOL_APPLY:-/usr/lib/dns-manager-luci/dnscrypt/dns-manager-dnscrypt-pool-apply.sh}
    dnsmasq_apply=${DNS_MANAGER_DNSCRYPT_DNSMASQ_APPLY:-/usr/lib/dns-manager-luci/dnscrypt/dns-manager-dnscrypt-dnsmasq.sh}
    config=${DNS_MANAGER_DNSCRYPT_CONFIG:-/etc/dnscrypt-proxy2/dnscrypt-proxy.toml}
    init=${DNS_MANAGER_DNSCRYPT_INIT:-/etc/init.d/dnscrypt-proxy}
    [ -r "$apply" ] || { echo 'DNSCrypt pool apply helper is unavailable' >&2; return 1; }
    [ -r "$dnsmasq_apply" ] || { echo 'DNSCrypt dnsmasq helper is unavailable' >&2; return 1; }
    records=$(mktemp "${TMP_DIR:-/tmp}/dnscrypt-selected.XXXXXX") || return 1
    urls=$(mktemp "${TMP_DIR:-/tmp}/dnscrypt-urls.XXXXXX") || { rm -f "$records"; return 1; }
    backup=$(mktemp "$(dirname "$config")/.dnscrypt-previous.XXXXXX") || { rm -f "$records" "$urls"; return 1; }
    trap 'rm -f "$records" "$urls"; [ -z "$backup" ] || rm -f "$backup"' EXIT
    trap 'exit 1' HUP INT TERM
    dnscrypt_select_profile "$goal" > "$records" || return 1
    [ -s "$records" ] || return 1
    if [ "${DNS_MANAGER_PROTOCOL:-mixed}" = native ]; then
        if awk -F'|' 'NF != 2 || $2 !~ /^sdns:\/\// {bad=1} END {exit !bad}' "$records"; then
            echo 'Удалите DoH-серверы из набора: выбран только DNSCrypt.' >&2
            return 1
        fi
    fi
    # Selector validates and bounds the records; pool helper independently
    # validates every URL and the bootstrap list before changing anything.
    cut -d '|' -f 2 "$records" > "$urls" || return 1
    had_config=0
    [ ! -L "$config" ] || return 1
    if [ -e "$config" ]; then
        [ -f "$config" ] && cp -p "$config" "$backup" || return 1
        had_config=1
    fi
    sh "$apply" "$port" "$bootstrap" < "$urls" || return 1
    if ! sh "$dnsmasq_apply" "$port"; then
        # The pool helper has already switched the proxy. Restore its previous
        # configuration so a failed dnsmasq update does not silently change
        # the DNS servers behind an existing profile.
        if [ "$had_config" = 1 ]; then
            if mv -f "$backup" "$config"; then
                backup=''
                "$init" restart >/dev/null 2>&1 || echo 'Failed to restart previous DNSCrypt pool' >&2
            else
                echo "Failed to restore DNSCrypt configuration; backup retained at $backup" >&2
                backup=''
            fi
        else
            # dnsmasq may still reference this listener if even its fallback
            # restart failed; keep the answering pool alive in that case.
            echo 'Previous DNSCrypt configuration absent; keeping the new listener running' >&2
        fi
        return 1
    fi
    cat "$records"
)
EOF_DNSCRYPT_ASSET_6
    cat > "$_dc_stage/dns-manager-dnscrypt-dnsmasq.sh" <<'EOF_DNSCRYPT_ASSET_7'
#!/bin/sh
# Configure the main dnsmasq instance for DNSCrypt or restore OpenWrt defaults.
set -e
mode=encrypted
case "${1:-}" in restore|clean) mode=stock; shift ;; esac
[ "$#" -eq 1 ] || exit 2
port=$1
case "$port" in ''|*[!0-9]*) exit 2;; esac
[ "$port" -gt 0 ] && [ "$port" -le 65535 ] || exit 2

restore_dns() {
    for option in noresolv localuse cachesize server; do
        uci -q delete "dhcp.@dnsmasq[0].$option" || :
    done
    uci commit dhcp
}

add_regional_servers() {
    [ "${DNS_MANAGER_IGNORE_REGIONAL:-0}" != 1 ] || return 0
    regional_mode=$(uci -q get dns-manager.global.dnscrypt_regional_mode || :)
    case "$regional_mode" in
        yandex) regional_ips='77.88.8.8 77.88.8.1' ;;
        isp) regional_ips=$(uci -q get dns-manager.global.dnscrypt_regional_ips || :)
             [ -n "$regional_ips" ] || return 1 ;;
        *) return 0 ;;
    esac
    for zone in ru su xn--p1ai by kz avito.st wbcontent.net wbstatic.net ozonusercontent.com ae-pic-a1.aliexpress-media.com yastatic.net; do
        for ip in $regional_ips; do
            uci add_list "dhcp.@dnsmasq[0].server=/$zone/$ip" || return 1
        done
    done
}

service dnsmasq stop
trap 'restore_dns || :; service dnsmasq start || :; exit 1' HUP INT TERM
if [ "$mode" = encrypted ]; then
    if ! {
        uci set 'dhcp.@dnsmasq[0].noresolv=1' &&
        uci set 'dhcp.@dnsmasq[0].localuse=1' &&
        uci set 'dhcp.@dnsmasq[0].cachesize=0' &&
        { uci -q delete 'dhcp.@dnsmasq[0].server' || :; } &&
        uci add_list "dhcp.@dnsmasq[0].server=127.0.0.1#$port" &&
        add_regional_servers &&
        uci commit dhcp && service dnsmasq start
    }; then
        restore_dns || :
        service dnsmasq start || :
        exit 1
    fi
else
    if ! restore_dns; then
        service dnsmasq start || :
        exit 1
    fi
    service dnsmasq start
fi
trap - HUP INT TERM
EOF_DNSCRYPT_ASSET_7
    cat > "$_dc_stage/dns-manager-engine-services.sh" <<'EOF_DNSCRYPT_ASSET_8'
#!/bin/sh
# Experimental service lifecycle helper; does not install packages or change DNS.
set -eu

initdir=${DNS_MANAGER_INIT_DIR:-/etc/init.d}
action=${1:-}
engine=${2:-}
case "$action:$engine" in
    quiesce:https-dns-proxy|quiesce:dnscrypt-proxy2|start:https-dns-proxy|start:dnscrypt-proxy2) ;;
    *) printf '%s\n' 'Expected quiesce|start and https-dns-proxy|dnscrypt-proxy2' >&2; exit 2 ;;
esac

service_absent() {
    # A failed procd delete can mean either "already absent" or a real ubus
    # failure. Only accept the former after a successful, valid service list.
    _service_reply=$(ubus -t 5 call service list "{\"name\":\"$1\"}" 2>/dev/null) || return 2
    _service_root=$(jsonfilter -s "$_service_reply" -e '@' 2>/dev/null) || return 2
    case "$_service_root" in \{*\}) ;; *) return 2 ;; esac
    if jsonfilter -s "$_service_reply" -e "@['$1']" >/dev/null 2>&1; then
        return 1
    else
        _service_filter_rc=$?
        [ "$_service_filter_rc" -eq 1 ] || return 2
    fi
}

stop_disable() {
    script="$initdir/$1"
    if [ ! -x "$script" ]; then
        # A removed package can leave a procd instance alive until reboot.
        # Do not start a competing engine unless absence is confirmed.
        service_absent "$1" || { printf 'Service exists without init script: %s\n' "$1" >&2; return 1; }
        return 0
    fi
    # rc.common may run stop_service even when procd has no instance.
    # In https-dns-proxy this can restore old dnsmasq settings, so do not
    # call it a second time after the service has already stopped.
    _service_state=0
    service_absent "$1" || _service_state=$?
    case "$_service_state" in
        0) ;;
        1) if ! "$script" stop && ! service_absent "$1"; then
               printf 'Failed to stop %s\n' "$1" >&2; return 1
           fi ;;
        *) printf 'Cannot verify service state: %s\n' "$1" >&2; return 1 ;;
    esac
    "$script" disable || { printf 'Failed to disable %s\n' "$1" >&2; return 1; }
    if ! service_absent "$1"; then
        printf 'Service still registered or procd unavailable: %s\n' "$1" >&2
        return 1
    fi
    if "$script" enabled >/dev/null 2>&1; then
        printf 'Still enabled: %s\n' "$1" >&2
        return 1
    fi
}

if [ "$action" = quiesce ]; then
    # The package may auto-start its own service during installation.
    for service in https-dns-proxy dnscrypt-proxy dns-manager-dnscrypt; do
        stop_disable "$service" || exit 1
    done
    exit 0
fi

case "$engine" in
    https-dns-proxy) target=https-dns-proxy ;;
    dnscrypt-proxy2) target=dnscrypt-proxy ;;
esac

# Never knowingly start a second manager while another service is enabled or
# running. The caller must have restored DNS and performed quiesce first.
for service in https-dns-proxy dnscrypt-proxy dns-manager-dnscrypt; do
    [ "$service" = "$target" ] && continue
    script="$initdir/$service"
    if { [ -x "$script" ] && "$script" enabled >/dev/null 2>&1; } || ! service_absent "$service"; then
        printf 'Conflicting service is active or enabled: %s\n' "$service" >&2
        exit 1
    fi
done
script="$initdir/$target"
[ -x "$script" ] || { printf 'Missing service: %s\n' "$target" >&2; exit 1; }
# rc.common's procd start may not propagate start_service's failure. Validate
# the Manager-owned single-process configuration before enabling it at boot.
if [ "$engine" = https-dns-proxy ]; then
    # A fresh engine switch leaves dnsmasq on provider DNS until the user
    # selects a profile. Package defaults otherwise redirect DNS and may
    # compete with Steer as soon as the service starts.
    force=$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null) || force=''
    integration=$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null) || integration=''
    if [ "$force" != 0 ] || [ "$integration" != - ]; then
        printf 'HTTPS DNS Proxy integration must be disabled before start\n' >&2
        exit 1
    fi
fi
if [ "$engine" = dnscrypt-proxy2 ]; then
    binary=${DNS_MANAGER_DNSCRYPT_BIN:-/usr/sbin/dnscrypt-proxy}
    config=${DNS_MANAGER_DNSCRYPT_CONFIG:-/etc/dnscrypt-proxy2/dnscrypt-proxy.toml}
    [ -x "$binary" ] && [ -f "$config" ] && "$binary" -config "$config" -check >/dev/null 2>&1 || {
        printf 'Invalid dnscrypt-proxy2 configuration\n' >&2
        exit 1
    }
fi
"$script" enable || { printf 'Failed to enable %s\n' "$target" >&2; exit 1; }
if ! "$script" start; then
    "$script" disable >/dev/null 2>&1 || true
    printf 'Failed to start %s\n' "$target" >&2
    exit 1
fi
# rc.common may report a successful start even if no procd instance was
# registered. Do not tell the caller it is safe to point dnsmasq at it then.
for attempt in 1 2 3; do
    if "$script" running >/dev/null 2>&1; then exit 0; fi
    [ "$attempt" -eq 3 ] || sleep 1
done
"$script" stop >/dev/null 2>&1 || true
"$script" disable >/dev/null 2>&1 || true
printf 'Service did not become ready: %s\n' "$target" >&2
exit 1
EOF_DNSCRYPT_ASSET_8
    fetch_installer_source "$_dc_stage/backend-dnscrypt.sh" "$SOURCE_BASE/libexec/backend-dnscrypt.sh"
    [ "$(sha256sum "$_dc_stage/backend-dnscrypt.sh" | cut -d' ' -f1)" = "e39c86b6048ec810bc37733524731044a3bb3cf884641bc06f9276b5184446be" ] || { err "Файл backend DNSCrypt не прошёл проверку."; return 1; }
    cat > "$_dc_stage/dns-manager-device-detach.sh" <<'EOF_DNSCRYPT_ASSET_10'
#!/bin/sh
# Detach the Manager-owned per-device redirect before stopping its listeners.
# Caller serializes Manager mutations. This script does not touch Steer rules.
set -e
guard=${DNS_MANAGER_UCI_GUARD:-/usr/lib/dns-manager-luci/cache/uci-read-guard.sh}
device_init=${DNS_MANAGER_DEVICE_INIT:-/etc/init.d/dns-manager-device-dns}
firewall_init=${DNS_MANAGER_FIREWALL_INIT:-/etc/init.d/firewall}
assignments=${DNS_MANAGER_DEVICE_ASSIGNMENTS:-/etc/dns-manager/config/device-dns.conf}
default_assignments=${DNS_MANAGER_DEVICE_DEFAULT_ASSIGNMENTS:-/etc/dns-manager/config/device-dns-default.conf}
nft_file=${DNS_MANAGER_DEVICE_NFT:-/etc/dns-manager/device-dns/redirects.nft}
legacy_nft=${DNS_MANAGER_DEVICE_LEGACY_NFT:-/etc/nftables.d/90-dns-manager-device-dns.nft}
name=dns_manager_device_dns
sid=''
cleanup() {
    [ -z "$sid" ] || ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null 2>&1 || :
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
[ -r "$guard" ] && [ -x "$firewall_init" ] || { echo 'Firewall guard or service missing' >&2; exit 1; }
sh "$guard" firewall /bin/true || { echo 'Pending firewall changes' >&2; exit 1; }
sid=$(ubus call session create '{"timeout":60}' | jsonfilter -e '@.ubus_rpc_session') || exit 1
case "$sid" in ''|*[!0-9a-f]*) exit 1;; esac
[ "${#sid}" -eq 32 ] || exit 1
ubus call session grant "{\"ubus_rpc_session\":\"$sid\",\"scope\":\"uci\",\"objects\":[[\"firewall\",\"read\"],[\"firewall\",\"write\"]]}" >/dev/null
reply=$(ubus call uci get "{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\"}") || exit 1
. /usr/share/libubox/jshn.sh
json_load "$reply" || exit 1
json_select values || exit 1
changed=0
if json_select "$name" 2>/dev/null; then
    json_get_var type '.type'
    json_get_var include_type type
    json_get_var include_path path
    json_get_var position position
    json_get_var chain chain
    [ "$type" = include ] && [ "$include_type" = nftables ] &&
    [ "$include_path" = "$nft_file" ] && [ "$position" = chain-pre ] &&
    [ "$chain" = dstnat_lan ] || { echo 'Unrelated firewall include with Manager name' >&2; exit 1; }
    ubus call uci delete "{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\",\"section\":\"$name\"}" >/dev/null
    ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"firewall\"}" >/dev/null
    changed=1
fi
ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null || exit 1
sid=''
# Reload while listeners are still alive. If reload fails, do not stop them.
if [ "$changed" = 1 ] || [ -x "$device_init" ]; then
    sh "$guard" firewall "$firewall_init" reload || { echo 'Firewall reload failed; listeners retained' >&2; exit 1; }
fi
service_absent() {
    _reply=$(ubus -t 5 call service list '{"name":"dns-manager-device-dns"}') || return 1
    _root=$(jsonfilter -s "$_reply" -e '@') || return 1
    case "$_root" in \{*\}) ;; *) return 1;; esac
    if jsonfilter -s "$_reply" -e "@['dns-manager-device-dns']" >/dev/null 2>&1; then
        return 1
    else
        [ "$?" -eq 1 ]
    fi
}
if [ -x "$device_init" ]; then
    # stop_service itself reloads firewall. Holding the read guard prevents it
    # from consuming or committing another process's staged firewall changes.
    if ! sh "$guard" firewall /bin/sh -c '
        if uci -q get firewall.dns_manager_device_dns >/dev/null 2>&1; then exit 1; fi
        "$1" stop
    ' sh "$device_init"; then
        sh "$guard" firewall /bin/sh -c '
            if uci -q get firewall.dns_manager_device_dns >/dev/null 2>&1; then exit 1; fi
        ' && service_absent || { echo 'Device DNS stop failed' >&2; exit 1; }
    fi
    "$device_init" disable || { echo 'Device DNS autostart disable failed' >&2; exit 1; }
    if ! service_absent || "$device_init" enabled >/dev/null 2>&1; then
        echo 'Device DNS remains running or enabled' >&2; exit 1
    fi
else
    service_absent || { echo 'Device DNS service exists without an init script' >&2; exit 1; }
fi
rm -f "$assignments" "$default_assignments" "$nft_file" "$legacy_nft"
EOF_DNSCRYPT_ASSET_10
    cat > "$_dc_stage/dns-manager-engine-switch.sh" <<'EOF_DNSCRYPT_ASSET_11'
#!/bin/sh
# Background engine switch. This script is intended to run under procd.
# The existing DNS Manager mutation lock serializes changes with profile jobs.
set -e
target=${1:-}
case "$target" in https-dns-proxy|dnscrypt-proxy2) ;; *) exit 2;; esac
manager=${DNS_MANAGER_MANAGER:-/usr/bin/dns-manager}
helpers=${DNS_MANAGER_DNSCRYPT_HELPERS:-/usr/lib/dns-manager-luci/dnscrypt}
runtime=${DNS_MANAGER_DNSCRYPT_RUNTIME_DIR:-/var/run/dns-manager-luci}
config_dir=${DNS_MANAGER_DNSCRYPT_CONFIG_DIR:-/etc/dns-manager/config}
job_dir=${DNS_MANAGER_DNSCRYPT_JOB_DIR:-$runtime/jobs}/engine
init_dir=${DNS_MANAGER_INIT_DIR:-/etc/init.d}
engine_file=${DNS_MANAGER_DNSCRYPT_ENGINE_FILE:-$config_dir/dnscrypt-engine}
mkdir -p "$job_dir" "$runtime" "$config_dir"
exec >>"$job_dir/output" 2>&1 </dev/null
printf 'pid=%s\n' "$$" >> "$job_dir/state"
token=$(awk '{print $22}' "/proc/$$/stat" 2>/dev/null || true)
[ -z "$token" ] || printf 'pid_start=%s\n' "$token" >> "$job_dir/state"
locked=0
changed=0
success=0
install_error=''
cleanup() {
    trap - EXIT HUP INT TERM
    if [ "$success" != 1 ]; then
        if [ "$changed" = 1 ]; then
            echo 'Ошибка переключения. Восстанавливаю стандартный DNS.'
            sh "$helpers/dns-manager-engine-services.sh" quiesce "$target" || echo 'Не удалось остановить DNS-службы.'
            if ! sh "$helpers/dns-manager-dnscrypt-dnsmasq.sh" clean 5053; then
                echo 'Не удалось подтвердить запуск dnsmasq; проверьте настройки DNS и системный журнал.'
            fi
            rm -f "$config_dir/dnscrypt-profile.state" || true
        fi
        [ -z "$install_error" ] || echo "$install_error"
        printf 'result=fail\nstatus=failed\n' >> "$job_dir/state"
    else
        printf 'result=ok\nstatus=done\n' >> "$job_dir/state"
    fi
    printf 'finished=%s\n' "$(date +%s)" >> "$job_dir/state"
    [ "$locked" != 1 ] || release_mutation_lock
    if [ "$success" = 1 ]; then printf '__DONE__ 0\n'; else printf '__DONE__ 1\n'; fi
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
src=$(mktemp "$runtime/engine-manager.XXXXXX") || exit 1
if ! sed '/^case "${1:-}" in$/,$d' "$manager" > "$src"; then rm -f "$src"; exit 1; fi
source_rc=0
. "$src" || source_rc=$?
# The manager installs its own traps when sourced; keep the switch cleanup.
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
rm -f "$src"
[ "$source_rc" -eq 0 ] || exit 1
preflight_readonly >/dev/null 2>&1 && init_dirs >/dev/null 2>&1 && load_config >/dev/null 2>&1 || exit 1
acquire_mutation_lock || { echo 'Другая операция DNS Manager уже выполняется.'; exit 1; }
locked=1
if [ "$target" = dnscrypt-proxy2 ]; then
    package=dnscrypt-proxy2; executable=${DNS_MANAGER_DNSCRYPT_BIN:-/usr/sbin/dnscrypt-proxy}
else
    package=https-dns-proxy; executable=${DNS_MANAGER_HDP_BIN:-/usr/sbin/https-dns-proxy}
fi
# Check for an upstream route before clearing the current DNS configuration.
if [ ! -x "$executable" ]; then
    printf 'phase=Проверка подключения к сети…\n' >> "$job_dir/state"
    if ! ip -4 route get 8.8.8.8 >/dev/null 2>&1 && ! ip -6 route get 2606:4700:4700::1111 >/dev/null 2>&1; then
        echo 'Нет подключения к интернету для загрузки пакета: отсутствует маршрут.'
        exit 1
    fi
fi
# Refuse a global UCI commit when another interface has staged changes.
for config_package in firewall https-dns-proxy; do
    pending=$(uci -q changes "$config_package" 2>/dev/null || true)
    [ -z "$pending" ] || { echo "Есть несохранённые изменения UCI: $config_package"; exit 1; }
done
. "$helpers/dns-manager-watchdog-common.sh" || exit 1
dns_manager_stop_watchdog || { echo 'Не удалось остановить DNS Watchdog.'; exit 1; }
# Old failure counts and candidate history must not survive a clean engine switch.
rm -f /var/run/dns-manager-watchdog.json || exit 1
WATCHDOG_ENABLED=0; WATCHDOG_AUTOREPLACE=0
save_config || exit 1
printf 'phase=Сброс настроек DNS…\n' >> "$job_dir/state"
echo 'Удаляю привязки устройств.'
sh "$helpers/dns-manager-device-detach.sh" || exit 1
changed=1
rollback_firewall_targeted || exit 1
echo 'Останавливаю DNS-службы.'
sh "$helpers/dns-manager-engine-services.sh" quiesce "$target" || exit 1
UNINSTALL_DEFER_PROXY_RESTART=1
rollback_hdp_targeted || exit 1
unset UNINSTALL_DEFER_PROXY_RESTART
echo 'Восстанавливаю стандартный DNS.'
sh "$helpers/dns-manager-dnscrypt-dnsmasq.sh" clean 5053 || exit 1
SLOT_1_DOMAINS=''; SLOT_2_DOMAINS=''; SLOT_3_DOMAINS=''; SLOT_4_DOMAINS=''; SLOT_5_DOMAINS=''; SLOT_6_DOMAINS=''
REGIONAL_SAVED_ID=''; FORCE_DOH=0; BLOCK_EXTERNAL_DNS=0
clear_dns_core_runtime_state || exit 1
# Completed profile jobs belong to the old engine after the DNS reset.
rm -f "$(dirname "$job_dir")/profile/state" "$(dirname "$job_dir")/profile/output" || exit 1
rm -f "$config_dir/dnscrypt-profile.state" "$CUSTOM_DNS_CATALOG" || exit 1
if [ ! -x "$executable" ]; then
    echo "Устанавливаю $package."
    if [ "$target" = https-dns-proxy ]; then
        # Package installation can start the service immediately. Prevent its
        # default forced DNS/firewall integration from racing with Steer.
        hdp_config=${DNS_MANAGER_HDP_CONFIG_FILE:-/etc/config/https-dns-proxy}
        [ -f "$hdp_config" ] || : > "$hdp_config"
        uci -q get https-dns-proxy.config >/dev/null 2>&1 || uci set https-dns-proxy.config=main
        uci set https-dns-proxy.config.force_dns=0
        uci set https-dns-proxy.config.dnsmasq_config_update=-
        uci commit https-dns-proxy
    fi
    package_was_missing=0
    package_is_installed "$package" || package_was_missing=1
    # Try existing package indexes first; refresh only if installation fails.
    printf 'phase=Загрузка и установка пакета…\n' >> "$job_dir/state"
    if [ "$PKG_MGR" = apk ]; then
        apk add "$package" || { printf 'phase=Обновление списка пакетов…\n' >> "$job_dir/state"; apk update && { printf 'phase=Загрузка и установка пакета…\n' >> "$job_dir/state"; apk add "$package"; }; } || install_error="Не удалось установить пакет $package. Проверьте интернет и репозитории."
    elif [ "$PKG_MGR" = opkg ]; then
        opkg install "$package" || { printf 'phase=Обновление списка пакетов…\n' >> "$job_dir/state"; opkg update && { printf 'phase=Загрузка и установка пакета…\n' >> "$job_dir/state"; opkg install "$package"; }; } || install_error="Не удалось установить пакет $package. Проверьте интернет и репозитории."
    else
        install_error='Менеджер пакетов не найден.'
    fi
    [ -z "$install_error" ] || exit 1
    if [ "$package_was_missing" = 1 ]; then
        touch "$PACKAGE_OWNERSHIP" && { grep -Fqx -- "$package" "$PACKAGE_OWNERSHIP" || printf '%s\n' "$package" >> "$PACKAGE_OWNERSHIP"; } || echo 'Не удалось записать установленный пакет.'
    fi
    sh "$helpers/dns-manager-engine-services.sh" quiesce "$target" || exit 1
fi
printf 'phase=Запуск службы и настройка DNS…\n' >> "$job_dir/state"
if [ "$target" = dnscrypt-proxy2 ]; then
    # Package installation may replace the init script; install our boot guard afterwards.
    [ -r "$helpers/dns-manager-dnscrypt.init" ] || exit 1
    cp "$helpers/dns-manager-dnscrypt.init" "$init_dir/dnscrypt-proxy.new" || exit 1
    chmod 0755 "$init_dir/dnscrypt-proxy.new" && mv -f "$init_dir/dnscrypt-proxy.new" "$init_dir/dnscrypt-proxy" || exit 1
    echo 'Запускаю DNSCrypt и проверяю DNS.'
    bootstrap=$(printf '%s' "$BOOTSTRAP_DNS" | tr ',' '\n' | awk 'NF {if(n++) printf ","; printf "%s", $0; if(n==3) exit}')
    printf '%s\n' 'https://cloudflare-dns.com/dns-query' 'https://dns.google/dns-query' | sh "$helpers/dns-manager-dnscrypt-pool-apply.sh" 5053 "$bootstrap" || exit 1
    "$init_dir/dnscrypt-proxy" enable || exit 1
    DNS_MANAGER_IGNORE_REGIONAL=1 sh "$helpers/dns-manager-dnscrypt-dnsmasq.sh" 5053 || exit 1
    state_tmp=$(mktemp "$config_dir/.dnscrypt-state.XXXXXX") || exit 1
    if ! { printf '%s\n' 'profile=none' 'server=cloudflare_clean|https://cloudflare-dns.com/dns-query' 'server=google_clean|https://dns.google/dns-query' > "$state_tmp" && chmod 600 "$state_tmp" && mv -f "$state_tmp" "$config_dir/dnscrypt-profile.state"; }; then
        rm -f "$state_tmp"; exit 1
    fi
else
    echo 'Настраиваю HTTPS DNS Proxy.'
    restore_hdp_package_defaults || exit 1
    uci set https-dns-proxy.config.force_dns=0 || exit 1
    uci set https-dns-proxy.config.dnsmasq_config_update=- || exit 1
    uci commit https-dns-proxy || exit 1
    sh "$helpers/dns-manager-engine-services.sh" start https-dns-proxy || exit 1
fi
# Persist the selection in UCI as well as the existing dispatch marker. Refuse
# to commit somebody else's pending changes to this package.
engine_uci=${DNS_MANAGER_ENGINE_UCI_CONFIG:-/etc/config/dns-manager}
if [ ! -f "$engine_uci" ]; then (umask 077; : > "$engine_uci") || exit 1; fi
pending=$(uci -q changes dns-manager 2>/dev/null || true)
[ -z "$pending" ] || { echo 'Есть несохранённые изменения UCI: dns-manager'; exit 1; }
uci -q get dns-manager.global >/dev/null 2>&1 || uci set dns-manager.global=manager
uci -q delete dns-manager.global.dnscrypt_regional_mode || :
uci -q delete dns-manager.global.dnscrypt_regional_ips || :
uci set "dns-manager.global.active_engine=$target" || exit 1
uci commit dns-manager || exit 1
tmp=$(mktemp "$config_dir/.dnscrypt-engine.XXXXXX") || exit 1
printf '%s\n' "$target" > "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$engine_file" || { rm -f "$tmp"; exit 1; }
[ ! -x "$init_dir/dns-manager-regional" ] || "$init_dir/dns-manager-regional" restart >/dev/null 2>&1 || :
if [ -f /etc/dnsmasq.d/91-dns-manager-browser.conf ] && [ "$(sed -n '1p' /etc/dnsmasq.d/91-dns-manager-browser.conf 2>/dev/null)" = '# DNS Manager browser DNS hints' ]; then
    set_browser_dns_hint 1 || echo 'Не удалось восстановить подсказку браузерам; проверьте её в LuCI.'
fi
if [ "$target" = dnscrypt-proxy2 ]; then
    (sh "$helpers/dns-manager-dnscrypt-catalog-update.sh" > /tmp/dns-manager-native-catalog.log 2>&1 < /dev/null &)
fi
echo 'Движок переключён. Выберите DNS-профиль.'
success=1
EOF_DNSCRYPT_ASSET_11
    cat > "$_dc_stage/dns-manager-dnscrypt.init" <<'EOF_DNSCRYPT_ASSET_12'
#!/bin/sh /etc/rc.common
USE_PROCD=1
START=99
STOP=89

PROG=/usr/sbin/dnscrypt-proxy
CONFIG=/etc/dnscrypt-proxy2/dnscrypt-proxy.toml
extra_command 'network_ready' 'Restart DNSCrypt after a network interface event'

boot() {
    [ "$(uci -q get dns-manager.global.active_engine 2>/dev/null)" = dnscrypt-proxy2 ] || return 0
    start "$@"
}

start_service() {
    procd_open_instance dns-manager
    procd_set_param command "$PROG" -config "$CONFIG"
    procd_set_param file "$CONFIG"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn 3600 5 5
    procd_close_instance
}

service_triggers() {
    local iface
    for iface in wan wan6; do
        uci -q get "network.$iface" >/dev/null 2>&1 || continue
        procd_add_interface_trigger "interface.up" "$iface" /etc/init.d/dnscrypt-proxy network_ready
        procd_add_interface_trigger "interface.update" "$iface" /etc/init.d/dnscrypt-proxy network_ready
    done
    if ! uci -q get network.wan >/dev/null 2>&1 && ! uci -q get network.wan6 >/dev/null 2>&1; then
        procd_add_interface_trigger "interface.up" lan /etc/init.d/dnscrypt-proxy network_ready
        procd_add_interface_trigger "interface.update" lan /etc/init.d/dnscrypt-proxy network_ready
    fi
}

network_ready() {
    [ "$(uci -q get dns-manager.global.active_engine 2>/dev/null)" = dnscrypt-proxy2 ] || return 0
    enabled || return 0
    restart
}
EOF_DNSCRYPT_ASSET_12
    cat > "$_dc_stage/dns-manager-watchdog-common.sh" <<'EOF_DNSCRYPT_ASSET_13'
#!/bin/sh
# Stop the legacy watchdog before DNSCrypt operations or engine changes.
dns_manager_stop_watchdog() {
    watchdog_service_stop_disable || return 1
    wd_reply=$(ubus -t 5 call service list '{"name":"dns-watchdog"}' 2>/dev/null) || return 1
    wd_root=$(jsonfilter -s "$wd_reply" -e '@' 2>/dev/null) || return 1
    case "$wd_root" in \{*\}) ;; *) return 1 ;; esac
    if jsonfilter -s "$wd_reply" -e "@['dns-watchdog']" >/dev/null 2>&1; then
        return 1
    else
        wd_rc=$?
        [ "$wd_rc" -eq 1 ] || return 1
    fi
    watchdog_cron_remove_owned_block
}
EOF_DNSCRYPT_ASSET_13
    cat > "$_dc_stage/dns-manager-dnscrypt-catalog.conf" <<'EOF_DNSCRYPT_CATALOG'
# DNSCrypt stamps from https://github.com/DNSCrypt/dnscrypt-resolvers/blob/master/v3/public-resolvers.md
# id|category|tags|name|stamp|region|status
native_adguard_unfiltered|clean|dnscrypt|AdGuard DNS без фильтрации (DNSCrypt)|sdns://AQcAAAAAAAAAEjk0LjE0MC4xNC4xNDA6NTQ0MyC16ETWuDo-PhJo62gfvqcN48X6aNvWiBQdvy7AZrLa-iUyLmRuc2NyeXB0LnVuZmlsdGVyZWQubnMxLmFkZ3VhcmQuY29t|any|official
native_adguard_default|adblock|dnscrypt|AdGuard DNS (DNSCrypt)|sdns://AQMAAAAAAAAAETk0LjE0MC4xNC4xNDo1NDQzINErR_JS3PLCu_iZEIbq95zkSV2LFsigxDIuUso_OQhzIjIuZG5zY3J5cHQuZGVmYXVsdC5uczEuYWRndWFyZC5jb20|any|official
native_adguard_family|family|dnscrypt|AdGuard DNS семейный (DNSCrypt)|sdns://AQMAAAAAAAAAETk0LjE0MC4xNC4xNTo1NDQzILgxXdexS27jIKRw3C7Wsao5jMnlhvhdRUXWuMm1AFq6ITIuZG5zY3J5cHQuZmFtaWx5Lm5zMS5hZGd1YXJkLmNvbQ|any|official
native_quad9_unfiltered|clean|dnscrypt|Quad9 без фильтрации (DNSCrypt)|sdns://AQcAAAAAAAAADTkuOS45LjEwOjg0NDMgZ8hHuMh1jNEgJFVDvnVnRt803x2EwAuMRwNo34Idhj4ZMi5kbnNjcnlwdC1jZXJ0LnF1YWQ5Lm5ldA|any|official
native_quad9_secure|security|dnscrypt|Quad9 защита от угроз (DNSCrypt)|sdns://AQMAAAAAAAAADDkuOS45Ljk6ODQ0MyBnyEe4yHWM0SAkVUO-dWdG3zTfHYTAC4xHA2jfgh2GPhkyLmRuc2NyeXB0LWNlcnQucXVhZDkubmV0|any|official
native_scaleway_fr|clean|dnscrypt|Scaleway France (DNSCrypt)|sdns://AQcAAAAAAAAADjIxMi40Ny4yMjguMTM2IOgBuE6mBr-wusDOQ0RbsV66ZLAvo8SqMa4QY2oHkDJNHzIuZG5zY3J5cHQtY2VydC5mci5kbnNjcnlwdC5vcmc|fr|official
native_cryptostorm_fr|privacy|dnscrypt|CryptoStorm France (DNSCrypt)|sdns://AQcAAAAAAAAADTE2My4xNzIuMzQuNTYgMTNyrVlWMsJBa4cvCY-FG925ZShMbL6aTxkJZDDbqVoeMi5kbnNjcnlwdC1jZXJ0LmNyeXB0b3N0b3JtLmlz|fr|official
native_adguard_family_2|family|dnscrypt|AdGuard DNS семейный 2 (DNSCrypt)|sdns://AQMAAAAAAAAAETk0LjE0MC4xNS4xNjo1NDQzILgxXdexS27jIKRw3C7Wsao5jMnlhvhdRUXWuMm1AFq6ITIuZG5zY3J5cHQuZmFtaWx5Lm5zMS5hZGd1YXJkLmNvbQ|any|official
native_cleanbrowsing_family|family|dnscrypt|CleanBrowsing семейный (DNSCrypt)|sdns://AQMAAAAAAAAAFDE4NS4yMjguMTY4LjE2ODo4NDQzILysMvrVQ2kXHwgy1gdQJ8MgjO7w6OmflBjcd2Bl1I8pEWNsZWFuYnJvd3Npbmcub3Jn|any|official
native_cisco_family|family|dnscrypt|OpenDNS FamilyShield (DNSCrypt)|sdns://AQEAAAAAAAAADjIwOC42Ny4yMjAuMTIzILc1EUAgbyJdPivYItf9aR6hwzzI1maNDL4Ev6vKQ_t5GzIuZG5zY3J5cHQtY2VydC5vcGVuZG5zLmNvbQ|any|official
native_dnsforfamily|family|dnscrypt|DNS for Family (DNSCrypt)|sdns://AQMAAAAAAAAADjk0LjEzMC4xODAuMjI1ILtn1Ada3rLi6VNcj4pB-I5eHBqFzFbs_XFRHG-6KenTEGRuc2ZvcmZhbWlseS5jb20|de|official
native_cryptostorm_at|privacy|dnscrypt|CryptoStorm Austria (DNSCrypt)|sdns://AQcAAAAAAAAADTk0LjE5OC40MS4yMzUgMTNyrVlWMsJBa4cvCY-FG925ZShMbL6aTxkJZDDbqVoeMi5kbnNjcnlwdC1jZXJ0LmNyeXB0b3N0b3JtLmlz|at|official
native_cryptostorm_nl|privacy|dnscrypt|CryptoStorm Netherlands (DNSCrypt)|sdns://AQcAAAAAAAAADTE4NS4xMDcuODAuODQgMTNyrVlWMsJBa4cvCY-FG925ZShMbL6aTxkJZDDbqVoeMi5kbnNjcnlwdC1jZXJ0LmNyeXB0b3N0b3JtLmlz|nl|official
native_cryptostorm_berlin|privacy|dnscrypt|CryptoStorm Berlin (DNSCrypt)|sdns://AQcAAAAAAAAADTM3LjEyMC4yMTcuNzUgMTNyrVlWMsJBa4cvCY-FG925ZShMbL6aTxkJZDDbqVoeMi5kbnNjcnlwdC1jZXJ0LmNyeXB0b3N0b3JtLmlz|de|official
EOF_DNSCRYPT_CATALOG
    mv -f "$_dc_stage/dns-manager-dnscrypt-catalog.conf" "$_dc_dest/dns-manager-dnscrypt-catalog.conf"
    cat > "$_dc_stage/dns-manager-dnscrypt-source.sh" <<'EOF_DNSCRYPT_SOURCE'
#!/bin/sh
# Export the DNSCrypt project's signed resolver source as JSON without changing DNS.
set -eu
umask 077
cache_dir=${DNS_MANAGER_SOURCE_CACHE:-/etc/dns-manager/config/dnscrypt-sources}
binary=${DNS_MANAGER_DNSCRYPT_BIN:-/usr/sbin/dnscrypt-proxy}
mkdir -p "$cache_dir"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/dns-manager-source.XXXXXX")
trap 'rm -f "$tmp/config.toml" "$tmp/list.json"; rmdir "$tmp" 2>/dev/null || :' EXIT
trap 'exit 1' HUP INT TERM
# The proxy downloads and verifies the project's minisign signature before parsing.
case "$cache_dir" in *[!A-Za-z0-9_./-]*) echo 'Invalid source cache directory' >&2; exit 1;; esac
cat > "$tmp/config.toml" <<EOF
listen_addresses = ['127.0.0.1:55399']
server_names = []
[sources.'public-resolvers']
urls = ['https://raw.githubusercontent.com/DNSCrypt/dnscrypt-resolvers/master/v3/public-resolvers.md', 'https://download.dnscrypt.info/resolvers-list/v3/public-resolvers.md']
cache_file = '$cache_dir/public-resolvers.md'
minisign_key = 'RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3'
EOF
"$binary" -config "$tmp/config.toml" -list-all -json > "$tmp/list.json"
[ -s "$tmp/list.json" ] || { echo 'Empty DNSCrypt resolver list' >&2; exit 1; }
cat "$tmp/list.json"
EOF_DNSCRYPT_SOURCE
    cat > "$_dc_stage/dns-manager-dnscrypt-catalog-update.sh" <<'EOF_DNSCRYPT_UPDATE'
#!/bin/sh
set -eu
umask 077
helpers=${DNS_MANAGER_DNSCRYPT_HELPERS:-/usr/lib/dns-manager-luci/dnscrypt}
config=${DNS_MANAGER_DNSCRYPT_CONFIG_DIR:-/etc/dns-manager/config}
mkdir -p "$config"
tmp=$(mktemp -d "$config/.native-catalog.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM
sh "$helpers/dns-manager-dnscrypt-source.sh" > "$tmp/source.json"
ucode -e '''import { stdin } from "fs";
let servers = json(stdin.read("all"));
map(servers, s => {
 if (s.proto == "DNSCrypt" && !s.ipv6 && match(s.name, /^[A-Za-z0-9_.-]+$/) && match(s.stamp, /^sdns:\/\/[A-Za-z0-9_-]+$/))
  print(s.name, "|", s.stamp, "|", s.nofilter ? "clean" : "unknown", "|", replace(split(s.description || "", "\n")[0], /\|/g, "/"), "\n");
});''' < "$tmp/source.json" > "$tmp/records"
[ -s "$tmp/records" ] || { echo "В подписанном списке нет серверов DNSCrypt" >&2; exit 1; }
cat "$helpers/dns-manager-dnscrypt-catalog.conf" > "$tmp/catalog"
while IFS='|' read -r name stamp category description; do
    case "$name" in
        adguard-dns-family|cisco-familyshield|cleanbrowsing-adult|cleanbrowsing-family) category=family ;;
        adguard-dns) category=adblock ;;
        cleanbrowsing-security) category=security ;;
    esac
    display=$(printf '%s\n' "$name" | awk '{
        if ($0 ~ /^cs-/) sub(/^cs-/, "CryptoStorm-")
        else if ($0 ~ /^adguard-/) sub(/^adguard-/, "AdGuard-")
        else if ($0 ~ /^cleanbrowsing-/) sub(/^cleanbrowsing-/, "CleanBrowsing-")
        else if ($0 ~ /^cisco/) sub(/^cisco/, "Cisco OpenDNS")
        gsub(/[-_]/, " ");
        for (i=1; i<=NF; i++) { if ($i == "dns") $i="DNS"; else if ($i ~ /^[a-z]/) $i=toupper(substr($i,1,1)) substr($i,2); }
        print
    }')
    # Only use an explicit country in the signed source description.
    region=$(printf '%s\n' "$description" | awk '
        BEGIN {n=split("Austria:AT,Spain:ES,Belgium:BE,Germany:DE,Switzerland:CH,Czech Republic:CZ,Finland:FI,France:FR,Hungary:HU,England:GB,United Kingdom:GB,Italy:IT,Canada:CA,Moldova:MD,Netherlands:NL,Norway:NO,Poland:PL,Portugal:PT,Romania:RO,Serbia:RS,Singapore:SG,Sweden:SE,Australia:AU,Japan:JP,United States:US", a, ",")}
        {for(i=1;i<=n;i++){split(a[i], b, ":"); if(index($0,b[1])) {print b[2]; exit}}}
    ')
    if [ -n "$region" ]; then
        display=$(printf '%s\n' "$display" | awk -v region="$region" '{if (NF>1 && toupper($NF)==region) NF--; print}')
        display="$display [$region]"
    fi
    hash=$(printf %s "$name" | sha256sum)
    id=official_${hash%% *}
    printf '%s|%s|dnscrypt|%s|%s|any|official\n' "$id" "$category" "$display" "$stamp"
done < "$tmp/records" >> "$tmp/catalog"
awk -F'|' '/^#/ {print; next} !seen[$5]++ && !ids[$1]++ {print}' "$tmp/catalog" > "$tmp/final"
[ -s "$tmp/final" ] || exit 1
chmod 600 "$tmp/final"
mv -f "$tmp/final" "$config/dnscrypt-native-catalog.conf"
EOF_DNSCRYPT_UPDATE
    sh -n "$_dc_stage/backend-dnscrypt.sh"
    _dc_names="dns-manager-dnscrypt-source.sh dns-manager-dnscrypt-catalog-update.sh dns-manager-watchdog-common.sh dns-manager-doh-stamp.sh dns-manager-dnscrypt-config.sh dns-manager-dnscrypt-pool.sh dns-manager-dnscrypt-pool-apply.sh dns-manager-dnscrypt-profile.sh dns-manager-dnscrypt-profile-apply.sh dns-manager-dnscrypt-dnsmasq.sh dns-manager-engine-services.sh dns-manager-device-detach.sh dns-manager-engine-switch.sh dns-manager-dnscrypt.init"
    for _dc_name in $_dc_names; do
        sh -n "$_dc_stage/$_dc_name"
    done
    for _dc_name in $_dc_names; do
        chmod 0755 "$_dc_stage/$_dc_name"
        mv -f "$_dc_stage/$_dc_name" "$_dc_dest/$_dc_name"
    done
    chmod 0755 "$_dc_stage/backend-dnscrypt.sh"
    mv -f "$_dc_stage/backend-dnscrypt.sh" "${_dc_dest%/*}/backend-dnscrypt.sh"
    # Existing DNSCrypt installations receive the same boot guard on update.
    if [ "$(uci -q get dns-manager.global.active_engine 2>/dev/null)" = dnscrypt-proxy2 ] && [ -x /etc/init.d/dnscrypt-proxy ]; then
        cp "$_dc_dest/dns-manager-dnscrypt.init" /etc/init.d/dnscrypt-proxy.new
        chmod 0755 /etc/init.d/dnscrypt-proxy.new
        mv -f /etc/init.d/dnscrypt-proxy.new /etc/init.d/dnscrypt-proxy
        /etc/init.d/dnscrypt-proxy enable
        (sh "$_dc_dest/dns-manager-dnscrypt-catalog-update.sh" > /tmp/dns-manager-native-catalog.log 2>&1 < /dev/null &)
    fi
)

install_files() {
    require_manager || return 1
    grep -Fq '__watchdog-migrate)' "$MANAGER" || { err "Сначала обновите DNS Manager, затем повторите обновление LuCI."; return 1; }
    install_dnscrypt_assets || { err "Не удалось установить файлы dnscrypt-proxy2."; return 1; }
    DNS_MANAGER_NO_UPDATE=1 "$MANAGER" __watchdog-migrate || { err "Не удалось перенести DNS Watchdog на cron."; return 1; }

    # Run only on interface events and only while the provider mode is selected.
    # The marker prevents replacing another package's hook at the same path.
    _rh=/etc/hotplug.d/iface/95-dns-manager-regional
    if [ -e "$_rh" ] && ! grep -Fqx '# DNS_MANAGER_REGIONAL_HOOK=1' "$_rh"; then
        err "Найден чужой файл $_rh; обновление остановлено."
        return 1
    fi
    mkdir -p /etc/hotplug.d/iface || return 1
    cat > "$_rh.tmp.$$" <<'EOF_REGIONAL_HOOK'
#!/bin/sh
# DNS_MANAGER_REGIONAL_HOOK=1
case "${ACTION:-}" in ifup|ifupdate) ;; *) exit 0;; esac
if [ "$(uci -q get dns-manager.global.active_engine)" = dnscrypt-proxy2 ]; then
    [ "$(uci -q get dns-manager.global.dnscrypt_regional_mode)" = isp ] || exit 0
    ( sleep 3; /usr/lib/dns-manager-luci/backend-dnscrypt.sh refresh_regional >/dev/null 2>&1 ) </dev/null >/dev/null 2>&1 &
else
    grep -q "^REGIONAL_MODE='isp'$" /etc/dns-manager/config/manager.conf 2>/dev/null || exit 0
    ( sleep 3; DNS_MANAGER_NO_UPDATE=1 /usr/bin/dns-manager __regional-refresh >/dev/null 2>&1 ) </dev/null >/dev/null 2>&1 &
fi
EOF_REGIONAL_HOOK
    chmod 0755 "$_rh.tmp.$$" && mv -f "$_rh.tmp.$$" "$_rh" || { rm -f "$_rh.tmp.$$"; return 1; }

    # DNS-only updates do not necessarily emit a netifd interface event.
    # A sleeping procd process watches the resolver file only in provider mode.
    _rs=/etc/init.d/dns-manager-regional
    if [ -e "$_rs" ] && ! grep -Fqx '# DNS_MANAGER_REGIONAL_SERVICE=1' "$_rs"; then
        err "Найден чужой файл $_rs; обновление остановлено."
        return 1
    fi
    mkdir -p /usr/lib/dns-manager-luci || return 1
    cat > /usr/lib/dns-manager-luci/regional-watch.sh <<'EOF_REGIONAL_WATCH'
#!/bin/sh
_last=''
while :; do
    if [ "$(uci -q get dns-manager.global.active_engine)" = dnscrypt-proxy2 ]; then
        [ "$(uci -q get dns-manager.global.dnscrypt_regional_mode)" = isp ] || break
        _backend=dnscrypt
    else
        grep -q "^REGIONAL_MODE='isp'$" /etc/dns-manager/config/manager.conf 2>/dev/null || break
        _backend=https
    fi
    _file=/tmp/resolv.conf.d/resolv.conf.auto
    [ -s "$_file" ] || _file=/tmp/resolv.conf.auto
    _current="$(cat "$_file" 2>/dev/null || true)"
    if [ -n "$_current" ] && [ "$_current" != "$_last" ]; then
        if { [ "$_backend" = dnscrypt ] && /usr/lib/dns-manager-luci/backend-dnscrypt.sh refresh_regional >/dev/null 2>&1; } ||
           { [ "$_backend" = https ] && DNS_MANAGER_NO_UPDATE=1 /usr/bin/dns-manager __regional-refresh >/dev/null 2>&1; }; then
            _last="$_current"
        fi
    fi
    sleep 60
done
EOF_REGIONAL_WATCH
    cat > "$_rs.tmp.$$" <<'EOF_REGIONAL_SERVICE'
#!/bin/sh /etc/rc.common
# DNS_MANAGER_REGIONAL_SERVICE=1
USE_PROCD=1
START=99
STOP=10
start_service() {
    if [ "$(uci -q get dns-manager.global.active_engine)" = dnscrypt-proxy2 ]; then
        [ "$(uci -q get dns-manager.global.dnscrypt_regional_mode)" = isp ] || return 0
    else
        grep -q "^REGIONAL_MODE='isp'$" /etc/dns-manager/config/manager.conf 2>/dev/null || return 0
    fi
    procd_open_instance
    procd_set_param command /bin/sh /usr/lib/dns-manager-luci/regional-watch.sh
    procd_set_param respawn 3600 5 5
    procd_close_instance
}
EOF_REGIONAL_SERVICE
    chmod 0755 "$_rs.tmp.$$" && mv -f "$_rs.tmp.$$" "$_rs" || { rm -f "$_rs.tmp.$$"; return 1; }
    "$_rs" enable >/dev/null 2>&1 || return 1
    "$_rs" restart >/dev/null 2>&1 || return 1

    command -v jsonfilter >/dev/null 2>&1 || say "ℹ jsonfilter не найден — используется встроенный обработчик RPC-параметров."
    mkdir -p "$VIEW_DIR" "$RESOURCE_DIR" /usr/libexec/rpcd /usr/lib/dns-manager-luci /usr/share/rpcd/acl.d /usr/share/luci/menu.d "$RUNTIME_DIR/checks" "$JOB_DIR" "$BACKUP_DIR" "$(dirname "$STATE_FILE")" /etc/dns-manager/device-dns /etc/nftables.d || return 1
    if [ -d "$JOB_DIR" ]; then
        for _jd in "$JOB_DIR"/*; do
            [ -d "$_jd" ] || continue
            _bn="${_jd##*/}"
            case "$_bn" in
                [0-9]*-[0-9]*) ;;
                *) continue ;;
            esac
            _st="$(sed -n 's/^status=//p' "$_jd/state" 2>/dev/null | tail -n1)"
            [ "$_st" = running ] && continue
            rm -rf "$_jd" 2>/dev/null || true
        done
    fi
    mkdir -p /usr/lib/dns-manager-luci/cache || return 1
    cat > /usr/lib/dns-manager-luci/cache/uci-read-guard.sh <<'EOF_DM_HELPER_UCI_READ_GUARD'
#!/bin/sh
# Experimental: guard a read/reload using UCI's shared file-lock convention.
# Usage: package command [args...]. No cache configuration is modified here.
set -eu
[ "$#" -ge 2 ] || exit 2
package=$1
shift
case "$package" in ''|*[!A-Za-z0-9_-]*) exit 2 ;; esac
file="/etc/config/$package"
delta="/tmp/.uci/$package"
[ -f "$file" ] && [ ! -L "$file" ] || exit 1
mkdir -p /tmp/.uci
exec 8<"$file"
exec 9>>"$delta"
# The base file is always locked first, matching libuci commit order. Nonblocking
# locks fail instead of stalling the UI if another UCI operation is in progress.
flock -s -n 8 || exit 1
flock -s -n 9 || exit 1
[ ! -s "$delta" ] || { echo 'Pending UCI changes; refusing to reload' >&2; exit 1; }
"$@"
EOF_DM_HELPER_UCI_READ_GUARD
    chmod 0755 /usr/lib/dns-manager-luci/cache/uci-read-guard.sh || return 1
    cat > /usr/lib/dns-manager-luci/cache/cache-transaction.sh <<'EOF_DM_HELPER_CACHE_TRANSACTION'
#!/bin/sh
# Experimental cache apply/restore. Caller must serialize DNS Manager changes.
# section size ttl guard restart-command [args...]
set -eu
[ "$#" -ge 5 ] || exit 2
section=$1; wanted_size=$2; wanted_ttl=$3; guard=$4
shift 4
package=dhcp
case "$section" in '@dnsmasq[0]') ;; ''|*[!A-Za-z0-9_]*) exit 2 ;; esac
for n in "$wanted_size" "$wanted_ttl"; do
    case "$n" in ''|*[!0-9]*|0[0-9]*) exit 2 ;; esac
    [ "${#n}" -le 5 ] || exit 2
done
[ "$wanted_size" -le 10000 ] && [ "$wanted_ttl" -le 3600 ] || exit 2
[ -r "$guard" ] || exit 1
t="$(mktemp -d /tmp/dns-cache-tx.XXXXXX)" || exit 1
sid=''
cleanup() {
    [ -z "$sid" ] || ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null 2>&1 || true
    rm -rf "$t"
}
trap cleanup EXIT HUP INT TERM
new_session() {
    sid="$(ubus call session create '{"timeout":60}' | jsonfilter -e '@.ubus_rpc_session')"
    case "$sid" in *[!a-f0-9]*|'') return 1;; esac
    [ "${#sid}" -eq 32 ] || return 1
    ubus call session grant "{\"ubus_rpc_session\":\"$sid\",\"scope\":\"uci\",\"objects\":[[\"dhcp\",\"read\"],[\"dhcp\",\"write\"]]}" >/dev/null
}
end_session() {
    ubus call session destroy "{\"ubus_rpc_session\":\"$sid\"}" >/dev/null
    sid=''
}
read_options() {
    ubus call uci get "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\",\"section\":\"$section\"}" > "$t/current" || return 1
    grep -Eq '"\.type"[[:space:]]*:[[:space:]]*"dnsmasq"' "$t/current" || return 1
    instance="$(sed -n 's/.*"\.name"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9_]*\)".*/\1/p' "$t/current")"
    case "$instance" in ''|*[!A-Za-z0-9_]*) return 1 ;; esac
    current_size='unset'; current_ttl='unset'
    if grep -q '"cachesize"[[:space:]]*:' "$t/current"; then current_size="$(jsonfilter -i "$t/current" -e '@.values.cachesize')"; fi
    if grep -q '"min_cache_ttl"[[:space:]]*:' "$t/current"; then current_ttl="$(jsonfilter -i "$t/current" -e '@.values.min_cache_ttl')"; fi
    for val in "$current_size" "$current_ttl"; do
        case "$val" in unset) ;; ''|*[!0-9]*) return 1 ;; *) [ "${#val}" -le 10 ] || return 1;; esac
    done
}
write_option() {
    key=$1; value=$2; prior=$3
    if [ "$value" = unset ]; then
        [ "$prior" = unset ] || ubus call uci delete "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\",\"section\":\"$section\",\"option\":\"$key\"}" >/dev/null
    else
        ubus call uci set "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\",\"section\":\"$section\",\"values\":{\"$key\":\"$value\"}}" >/dev/null
    fi
}
sh "$guard" "$package" /bin/true || { echo 'Pending or busy UCI configuration' >&2; exit 1; }
new_session; read_options
old_size=$current_size; old_ttl=$current_ttl
expected_instance=$instance
if [ "$old_size" = "$wanted_size" ] && [ "$old_ttl" = "$wanted_ttl" ]; then
    end_session
    state="$(ubus call service list '{"name":"dnsmasq"}' | jsonfilter -e "@.dnsmasq.instances.$expected_instance.running")" || exit 1
    [ "$state" = true ] || { echo 'dnsmasq is not running' >&2; exit 1; }
    exit 0
fi
write_option cachesize "$wanted_size" "$old_size"
write_option min_cache_ttl "$wanted_ttl" "$old_ttl"
ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\"}" >/dev/null
end_session
# Marker distinguishes a refused guard from a service that was actually run.
if sh "$guard" "$package" /bin/sh -c '
    touch "$1"; shift
    instance=$1; shift
    "$@" || exit 1
    sleep 1
    state=$(ubus call service list '\''{"name":"dnsmasq"}'\'' | jsonfilter -e "@.dnsmasq.instances.$instance.running") || exit 1
    [ "$state" = true ]
' sh "$t/restarted" "$expected_instance" "$@"; then
    exit 0
fi
echo 'Cache restart failed; attempting to restore previous cache options' >&2
new_session; read_options
if [ "$current_size" != "$wanted_size" ] || [ "$current_ttl" != "$wanted_ttl" ]; then
    echo 'Cache settings changed externally; not overwriting them' >&2; exit 1
fi
write_option cachesize "$old_size" "$current_size"
write_option min_cache_ttl "$old_ttl" "$current_ttl"
ubus call uci commit "{\"ubus_rpc_session\":\"$sid\",\"config\":\"dhcp\"}" >/dev/null
end_session
if [ -e "$t/restarted" ]; then
    sh "$guard" "$package" "$@" || { echo 'Previous settings restored, but dnsmasq restart failed' >&2; exit 1; }
fi
exit 1
EOF_DM_HELPER_CACHE_TRANSACTION
    chmod 0755 /usr/lib/dns-manager-luci/cache/cache-transaction.sh || return 1
    cat > /etc/init.d/dns-manager-device-dns <<'EOF_DEVICE_DNS_SERVICE'
#!/bin/sh /etc/rc.common
# DNS Manager per-device DoH listeners. This does not provide DHCP.
START=99
STOP=10
USE_PROCD=1
DMD_BASE="/etc/dns-manager/device-dns"
DMD_ASSIGNMENTS="/etc/dns-manager/config/device-dns.conf"
DMD_MANAGER_CONFIG="/etc/dns-manager/config/manager.conf"
DMD_NFT="/etc/dns-manager/device-dns/redirects.nft"
DMD_INCLUDE="dns_manager_device_dns"
DMD_CHAIN="dstnat_lan"
DMD_STAGE=""

dmd_log() { logger -t dns-manager-device-dns -- "$*" 2>/dev/null || true; }
dmd_cleanup_stage() { [ -n "${DMD_STAGE:-}" ] && rm -rf "$DMD_STAGE" 2>/dev/null || true; }

dmd_valid_mac() {
    printf '%s\n' "$1" | awk '
        /^[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]$/ { ok=1 }
        END { exit ok ? 0 : 1 }
    '
}

dmd_slot_id() {
    case "$1" in
        1) printf '%s' "${SLOT_1:-}" ;; 2) printf '%s' "${SLOT_2:-}" ;;
        3) printf '%s' "${SLOT_3:-}" ;; 4) printf '%s' "${SLOT_4:-}" ;;
        5) printf '%s' "${SLOT_5:-}" ;; 6) printf '%s' "${SLOT_6:-}" ;;
        *) return 1 ;;
    esac
}
dmd_slot_port() {
    case "$1" in
        1) printf '%s' "${PORT_1:-}" ;; 2) printf '%s' "${PORT_2:-}" ;;
        3) printf '%s' "${PORT_3:-}" ;; 4) printf '%s' "${PORT_4:-}" ;;
        5) printf '%s' "${PORT_5:-}" ;; 6) printf '%s' "${PORT_6:-}" ;;
        *) return 1 ;;
    esac
}
dmd_slot_domains() {
    case "$1" in
        1) printf '%s' "${SLOT_1_DOMAINS:-}" ;; 2) printf '%s' "${SLOT_2_DOMAINS:-}" ;;
        3) printf '%s' "${SLOT_3_DOMAINS:-}" ;; 4) printf '%s' "${SLOT_4_DOMAINS:-}" ;;
        5) printf '%s' "${SLOT_5_DOMAINS:-}" ;; 6) printf '%s' "${SLOT_6_DOMAINS:-}" ;;
        *) return 1 ;;
    esac
}

dmd_normalize_slots() {
    if printf '%s' "$1" | grep -q '[^1-6,[:space:]]'; then return 1; fi
    _dmd_raw="$(printf '%s' "$1" | tr ',' ' ')"
    _dmd_list=""
    for _dmd_slot in $_dmd_raw; do
        case "$_dmd_slot" in 1|2|3|4|5|6) ;; *) return 1 ;; esac
        case " $_dmd_list " in *" $_dmd_slot "*) ;; *) _dmd_list="${_dmd_list:+$_dmd_list }$_dmd_slot" ;; esac
    done
    [ -n "$_dmd_list" ] || return 1
    printf '%s\n' $_dmd_list | tr ' ' '\n' | sort -n -u | tr '\n' ',' | sed 's/,$//'
}

dmd_mask_for_slots() {
    _dmd_mask=0
    for _dmd_slot in $(printf '%s' "$1" | tr ',' ' '); do
        case "$_dmd_slot" in
            1) _dmd_bit=1 ;; 2) _dmd_bit=2 ;; 3) _dmd_bit=4 ;;
            4) _dmd_bit=8 ;; 5) _dmd_bit=16 ;; 6) _dmd_bit=32 ;;
            *) return 1 ;;
        esac
        _dmd_mask=$((_dmd_mask + _dmd_bit))
    done
    [ "$_dmd_mask" -gt 0 ] || return 1
    printf '%s' "$_dmd_mask"
}

dmd_upstream_port_exists() {
    _dmd_uport="$1"
    case "$_dmd_uport" in ''|*[!0-9]*) return 1 ;; esac
    if command -v ss >/dev/null 2>&1; then
        ss -lntu 2>/dev/null | grep -Eq "(^|[[:space:]])[^[:space:]]*:${_dmd_uport}([[:space:]]|$)" && return 0
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -lntu 2>/dev/null | grep -Eq "(^|[[:space:]])[^[:space:]]*:${_dmd_uport}([[:space:]]|$)" && return 0
    fi
    _dmd_hex="$(printf '%04X' "$_dmd_uport" 2>/dev/null || true)"
    [ -n "$_dmd_hex" ] || return 1
    awk -v p="$_dmd_hex" 'NR>1 {split($2,a,":"); if (toupper(a[2])==p && ($4=="0A" || $4=="07" || $4=="01")) ok=1} END {exit ok?0:1}' /proc/net/tcp 2>/dev/null && return 0
    awk -v p="$_dmd_hex" 'NR>1 {split($2,a,":"); if (toupper(a[2])==p && $4=="07") ok=1} END {exit ok?0:1}' /proc/net/udp 2>/dev/null && return 0
    return 1
}

dmd_port_busy() {
    _dmd_port="$1"
    if command -v netstat >/dev/null 2>&1; then
        netstat -ln 2>/dev/null | awk -v p=":$_dmd_port" '
            $4 ~ (p "$") { found=1 }
            END { exit found ? 0 : 1 }
        '
        return $?
    fi
    if command -v ss >/dev/null 2>&1; then
        ss -lnut 2>/dev/null | awk -v p=":$_dmd_port" '
            { if ($5 ~ (p "$")) found=1 }
            END { exit found ? 0 : 1 }
        '
        return $?
    fi
    return 1
}

dmd_include_is_owned() {
    [ "$(uci -q get "firewall.$DMD_INCLUDE" 2>/dev/null || true)" = include ] &&
    [ "$(uci -q get "firewall.$DMD_INCLUDE.type" 2>/dev/null || true)" = nftables ] &&
    [ "$(uci -q get "firewall.$DMD_INCLUDE.path" 2>/dev/null || true)" = "$DMD_NFT" ] &&
    [ "$(uci -q get "firewall.$DMD_INCLUDE.position" 2>/dev/null || true)" = chain-pre ] &&
    [ "$(uci -q get "firewall.$DMD_INCLUDE.chain" 2>/dev/null || true)" = "$DMD_CHAIN" ]
}

dmd_remove_include() {
    if uci -q get "firewall.$DMD_INCLUDE" >/dev/null 2>&1; then
        dmd_include_is_owned || {
            dmd_log "Refusing to remove unrelated firewall include named $DMD_INCLUDE."
            return 1
        }
        uci -q delete "firewall.$DMD_INCLUDE" || return 1
        uci commit firewall || return 1
    fi
    rm -f "$DMD_NFT" "$DMD_NFT".tmp.* /etc/nftables.d/90-dns-manager-device-dns.nft /etc/nftables.d/90-dns-manager-device-dns.nft.tmp.* 2>/dev/null || true
    /etc/init.d/firewall reload >/dev/null 2>&1 || return 1
    return 0
}

dmd_configure_include() {
    if uci -q get "firewall.$DMD_INCLUDE" >/dev/null 2>&1; then
        dmd_include_is_owned || {
            dmd_log "Refusing to overwrite unrelated firewall include named $DMD_INCLUDE."
            return 1
        }
    else
        uci set "firewall.$DMD_INCLUDE=include" || return 1
    fi
    uci set "firewall.$DMD_INCLUDE.enabled=1" || return 1
    uci set "firewall.$DMD_INCLUDE.type=nftables" || return 1
    uci set "firewall.$DMD_INCLUDE.path=$DMD_NFT" || return 1
    uci set "firewall.$DMD_INCLUDE.position=chain-pre" || return 1
    uci set "firewall.$DMD_INCLUDE.chain=$DMD_CHAIN" || return 1
    uci commit firewall || return 1

    DMD_FW4_CHECK="$DMD_STAGE/fw4-check.nft"
    fw4 print > "$DMD_FW4_CHECK" 2>/dev/null || return 1
    nft -c -f "$DMD_FW4_CHECK" >/dev/null 2>&1 || {
        dmd_log "fw4/nft rejected the per-device DNS include."
        return 1
    }
    /etc/init.d/firewall reload >/dev/null 2>&1 || return 1
    return 0
}

dmd_fail_open() {
    dmd_remove_include >/dev/null 2>&1 || true
    rm -rf "$DMD_BASE/profiles" 2>/dev/null || true
    dmd_log "Per-device DNS rules disabled after a configuration error; clients fall back to the normal LAN DNS path."
}

dmd_ensure_profile() {
    _dmd_slots="$1"
    _dmd_label="$2"
    _dmd_count=0

    for _dmd_slot in $(printf '%s' "$_dmd_slots" | tr ',' ' '); do
        _dmd_id="$(dmd_slot_id "$_dmd_slot" 2>/dev/null || true)"
        _dmd_port="$(dmd_slot_port "$_dmd_slot" 2>/dev/null || true)"
        case "$_dmd_port" in ''|*[!0-9]*) dmd_log "Missing upstream port for DNS slot $_dmd_slot ($_dmd_label)."; return 1 ;; esac
        [ -n "$_dmd_id" ] || { dmd_log "DNS slot $_dmd_slot is not assigned ($_dmd_label)."; return 1; }
        [ "$_dmd_port" -ge 1 ] 2>/dev/null && [ "$_dmd_port" -le 65535 ] 2>/dev/null || { dmd_log "Invalid upstream port for DNS slot $_dmd_slot ($_dmd_label)."; return 1; }
        dmd_upstream_port_exists "$_dmd_port" || {
            dmd_log "DNS slot $_dmd_slot has no listening DoH upstream on port $_dmd_port ($_dmd_label)."
            return 1
        }
        _dmd_count=$((_dmd_count + 1))
    done
    [ "$_dmd_count" -gt 0 ] || return 1

    _dmd_mask="$(dmd_mask_for_slots "$_dmd_slots" 2>/dev/null)" || return 1
    _dmd_listener_port=$((54100 + _dmd_mask))
    _dmd_map_line="$_dmd_slots|$_dmd_mask|$_dmd_listener_port"
    if grep -Fqx "$_dmd_map_line" "$DMD_STAGE/profiles.map" 2>/dev/null; then
        printf '%s' "$_dmd_listener_port"
        return 0
    fi
    if dmd_port_busy "$_dmd_listener_port"; then
        dmd_log "Port $_dmd_listener_port is busy; cannot activate $_dmd_label."
        return 1
    fi

    _dmd_profile="$DMD_STAGE/profiles/profile_$_dmd_mask.conf"
    {
        printf 'port=%s\n' "$_dmd_listener_port"
        printf 'pid-file=/var/run/dns-manager-device-dns/profile_%s.pid\n' "$_dmd_mask"
        printf 'interface=%s\n' "$DMD_LAN_DEV"
        printf 'bind-dynamic\nexcept-interface=lo\nno-dhcp-interface=%s\n' "$DMD_LAN_DEV"
        printf 'no-resolv\nno-poll\nno-hosts\ndomain-needed\nbogus-priv\ncache-size=0\n'
        printf 'server=/lan/127.0.0.1#53\n'
        [ "$_dmd_count" -le 1 ] || printf 'all-servers\n'
        _dmd_explicit_domains=""
        for _dmd_slot in $(printf '%s' "$_dmd_slots" | tr ',' ' '); do
            _dmd_upstream_port="$(dmd_slot_port "$_dmd_slot" 2>/dev/null || true)"
            printf 'server=127.0.0.1#%s\n' "$_dmd_upstream_port"
            _dmd_slot_domains="$(dmd_slot_domains "$_dmd_slot" 2>/dev/null | tr 'A-Z' 'a-z' || true)"
            for _dmd_domain in $_dmd_slot_domains; do
                case "$_dmd_domain" in ''|.*|*.|*[!A-Za-z0-9.-]*) continue ;; esac
                _dmd_explicit_domains="$_dmd_explicit_domains $_dmd_domain"
                printf 'server=/%s/127.0.0.1#%s\n' "$_dmd_domain" "$_dmd_upstream_port"
            done
        done
        if [ "${REGIONAL_MODE:-legacy}" = yandex ] || [ "${REGIONAL_MODE:-legacy}" = isp ]; then
            if [ "$REGIONAL_MODE" = yandex ]; then _dmd_ru_ips='77.88.8.8 77.88.8.1'; else _dmd_ru_ips="${REGIONAL_ISP_IPS:-}"; fi
            for _dmd_tld in /ru /su /xn--p1ai /by /kz /avito.st /wbcontent.net /wbstatic.net /ozonusercontent.com /ae-pic-a1.aliexpress-media.com /yastatic.net; do
                _dmd_overridden=0
                for _dmd_custom in $_dmd_explicit_domains; do
                    case "${_dmd_tld#/}" in "$_dmd_custom"|*."$_dmd_custom") _dmd_overridden=1; break;; esac
                done
                [ "$_dmd_overridden" = 0 ] || continue
                for _dmd_ru_ip in $_dmd_ru_ips; do printf 'server=%s/%s\n' "$_dmd_tld" "$_dmd_ru_ip"; done
            done
        elif [ -n "${SLOT_RU:-}" ] && [ -n "${PORT_RU:-}" ]; then
            for _dmd_tld in /ru /su /xn--p1ai /by /kz /avito.st /wbcontent.net /wbstatic.net /ozonusercontent.com /ae-pic-a1.aliexpress-media.com /yastatic.net; do
                _dmd_overridden=0
                for _dmd_custom in $_dmd_explicit_domains; do
                    case "${_dmd_tld#/}" in "$_dmd_custom"|*."$_dmd_custom") _dmd_overridden=1; break;; esac
                done
                [ "$_dmd_overridden" = 0 ] || continue
                printf 'server=%s/127.0.0.1#%s\n' "$_dmd_tld" "$PORT_RU"
            done
        fi
        if [ "${BLOCK_EXTERNAL_DNS:-0}" = 1 ]; then
            printf 'server=/mask.icloud.com/\nserver=/mask-h2.icloud.com/\nserver=/use-application-dns.net/\n'
        fi
    } > "$_dmd_profile" || return 1

    /usr/sbin/dnsmasq --test --conf-file="$_dmd_profile" >/dev/null 2>&1 || {
        dmd_log "dnsmasq rejected profile $_dmd_mask for $_dmd_label."
        rm -f "$_dmd_profile" 2>/dev/null || true
        return 1
    }
    printf '%s\n' "$_dmd_map_line" >> "$DMD_STAGE/profiles.map" || return 1
    printf '%s' "$_dmd_listener_port"
}

dmd_build_and_install() {
    # Check a same-named UCI include before writing its target path. Never overwrite
    # an unrelated user's nftables snippet even if it happens to use our filename.
    if uci -q get "firewall.$DMD_INCLUDE" >/dev/null 2>&1; then
        dmd_include_is_owned || {
            dmd_log "Refusing per-device DNS activation because firewall include $DMD_INCLUDE is not owned by DNS Manager."
            return 1
        }
    fi
    command -v fw4 >/dev/null 2>&1 || { dmd_log "fw4 is unavailable."; return 1; }
    [ -x /usr/sbin/dnsmasq ] || { dmd_log "dnsmasq is unavailable."; return 1; }

    dmd_cleanup_stage
    DMD_STAGE="$(mktemp -d /tmp/dns-manager-device-dns.stage.XXXXXX 2>/dev/null)" || return 1
    mkdir -p "$DMD_STAGE/profiles" "$DMD_BASE" "$(dirname "$DMD_NFT")" /var/run/dns-manager-device-dns || { dmd_cleanup_stage; return 1; }
    : > "$DMD_STAGE/profiles.map"
    : > "$DMD_STAGE/nft.rules"

    SLOT_1=""; SLOT_2=""; SLOT_3=""; SLOT_4=""; SLOT_5=""; SLOT_6=""; SLOT_RU=""
    PORT_1=""; PORT_2=""; PORT_3=""; PORT_4=""; PORT_5=""; PORT_6=""; PORT_RU=""
    [ ! -r "$DMD_MANAGER_CONFIG" ] || . "$DMD_MANAGER_CONFIG" || { dmd_cleanup_stage; return 1; }

    DMD_LAN_DEV="$(uci -q get network.lan.device 2>/dev/null || true)"
    [ -n "$DMD_LAN_DEV" ] || DMD_LAN_DEV="br-lan"
    case "$DMD_LAN_DEV" in ''|*[!A-Za-z0-9_.:-]*) dmd_cleanup_stage; return 1 ;; esac

    DMD_ACTIVE=0
    : > "$DMD_STAGE/nft.rules"

    if [ -r "$DMD_ASSIGNMENTS" ]; then
        while IFS='|' read -r DMD_MAC DMD_RAW_SLOTS DMD_EXTRA; do
            DMD_MAC="$(printf '%s' "$DMD_MAC" | tr 'A-F' 'a-f')"
            [ -n "$DMD_MAC" ] || continue
            dmd_valid_mac "$DMD_MAC" || continue
            [ -z "$DMD_EXTRA" ] || continue
            DMD_SLOTS="$(dmd_normalize_slots "$DMD_RAW_SLOTS" 2>/dev/null || true)"
            [ -n "$DMD_SLOTS" ] || continue
            DMD_LISTENER_PORT="$(dmd_ensure_profile "$DMD_SLOTS" "device $DMD_MAC" 2>/dev/null || true)"
            case "$DMD_LISTENER_PORT" in ''|*[!0-9]*)
                dmd_log "Device $DMD_MAC has no usable DoH profile; it will use the normal LAN DNS path."
                continue
                ;;
            esac

            printf 'iifname "%s" ether saddr %s udp dport 53 redirect to :%s\n' "$DMD_LAN_DEV" "$DMD_MAC" "$DMD_LISTENER_PORT" >> "$DMD_STAGE/nft.rules"
            printf 'iifname "%s" ether saddr %s tcp dport 53 redirect to :%s\n' "$DMD_LAN_DEV" "$DMD_MAC" "$DMD_LISTENER_PORT" >> "$DMD_STAGE/nft.rules"
            DMD_ACTIVE=$((DMD_ACTIVE + 1))
        done < "$DMD_ASSIGNMENTS"
    fi

    if [ "$DMD_ACTIVE" -gt 0 ]; then
        mv "$DMD_STAGE/nft.rules" "$DMD_STAGE/device-rules.nft" || { dmd_cleanup_stage; return 1; }
    else
        rm -f "$DMD_STAGE/nft.rules"
    fi

    rm -rf "$DMD_BASE/profiles.new" "$DMD_BASE/profiles.old" 2>/dev/null || true
    [ ! -d "$DMD_BASE/profiles" ] || mv "$DMD_BASE/profiles" "$DMD_BASE/profiles.old" || { dmd_cleanup_stage; return 1; }
    mv "$DMD_STAGE/profiles" "$DMD_BASE/profiles" || {
        [ ! -d "$DMD_BASE/profiles.old" ] || mv "$DMD_BASE/profiles.old" "$DMD_BASE/profiles" 2>/dev/null || true
        dmd_cleanup_stage
        return 1
    }

    if [ -f "$DMD_STAGE/device-rules.nft" ]; then
        DMD_NFT_TMP="$(mktemp "$DMD_NFT.tmp.XXXXXX" 2>/dev/null)" || { dmd_cleanup_stage; return 1; }
        cp "$DMD_STAGE/device-rules.nft" "$DMD_NFT_TMP" || { rm -f "$DMD_NFT_TMP"; dmd_cleanup_stage; return 1; }
        chmod 0644 "$DMD_NFT_TMP" 2>/dev/null || true
        mv -f "$DMD_NFT_TMP" "$DMD_NFT" || { dmd_cleanup_stage; return 1; }
        dmd_configure_include || { dmd_cleanup_stage; return 1; }
    else
        dmd_remove_include || { dmd_cleanup_stage; return 1; }
    fi

    rm -rf "$DMD_BASE/profiles.old" 2>/dev/null || true
    rm -f "$DMD_STAGE/profiles.map" "$DMD_STAGE/nft.rules" "$DMD_STAGE/fw4-check.nft" 2>/dev/null || true
    dmd_cleanup_stage
    return 0
}

stop_service() {
    # Never leave clients redirected to local ports after these dnsmasq listeners stop.
    dmd_remove_include >/dev/null 2>&1 || true
}

start_service() {
    if ! dmd_build_and_install; then
        dmd_fail_open
        return 1
    fi
    for DMD_PROFILE in "$DMD_BASE"/profiles/profile_*.conf; do
        [ -f "$DMD_PROFILE" ] || continue
        DMD_NAME="${DMD_PROFILE##*/}"
        DMD_NAME="${DMD_NAME%.conf}"
        procd_open_instance "$DMD_NAME"
        procd_set_param command /usr/sbin/dnsmasq --keep-in-foreground --conf-file="$DMD_PROFILE"
        procd_set_param respawn 3600 5 5
        procd_close_instance
    done
}

reload_service() {
    /etc/init.d/dns-manager-device-dns stop >/dev/null 2>&1 || true
    /etc/init.d/dns-manager-device-dns start
}
EOF_DEVICE_DNS_SERVICE
    chmod 0755 /etc/init.d/dns-manager-device-dns || return 1
    /etc/init.d/dns-manager-device-dns enable >/dev/null 2>&1 || return 1
    rm -f /etc/nftables.d/90-dns-manager-device-dns.nft /etc/nftables.d/90-dns-manager-device-dns.nft.tmp.* 2>/dev/null || true
    rm -f /etc/dns-manager/config/device-dns-default.conf 2>/dev/null || true
    /etc/init.d/firewall reload >/dev/null 2>&1 || true
    if ! /etc/init.d/dns-manager-device-dns restart >/dev/null 2>&1; then
        say "ПРЕДУПРЕЖДЕНИЕ: не удалось запустить проверку привязок DNS по устройствам; они остаются без активных правил."
    fi

    _menu_stage="${MENU_FILE}.new.$$"
    cat > "$_menu_stage" <<'EOF_MENU'
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
    "title": "Обзор",
    "order": 10,
    "action": { "type": "view", "path": "dns-manager/dashboard" }
  },
  "admin/services/dns-manager/doh": {
    "title": "Защищённый DNS",
    "order": 20,
    "action": { "type": "view", "path": "dns-manager/doh" }
  },
  "admin/services/dns-manager/slots": {
    "title": "DNS по слотам",
    "order": 25,
    "action": { "type": "view", "path": "dns-manager/slots" }
  },
  "admin/services/dns-manager/devices": {
    "title": "Устройства",
    "order": 27,
    "action": { "type": "view", "path": "dns-manager/devices" }
  },
  "admin/services/dns-manager/network": {
    "title": "Сеть",
    "order": 30,
    "action": { "type": "view", "path": "dns-manager/network" }
  },
  "admin/services/dns-manager/time": {
    "title": "Время",
    "order": 40,
    "action": { "type": "view", "path": "dns-manager/time" }
  },
  "admin/services/dns-manager/catalog": {
    "title": "Каталог DNS",
    "order": 50,
    "action": { "type": "view", "path": "dns-manager/catalog" }
  },
  "admin/services/dns-manager/log": {
    "title": "Журнал",
    "order": 80,
    "action": { "type": "view", "path": "dns-manager/log" }
  }
}
EOF_MENU

    cat > "$ACL_FILE" <<'EOF_ACL'
{
  "luci-app-dns-manager": {
    "description": "DNS Manager native LuCI interface",
    "read": {
      "ubus": {
        "dns_manager": [ "dnscrypt_test", "dnscrypt_log", "system_dns_test", "status", "runtime", "doh_status", "network_status", "lan_devices", "time_status", "page_meta", "catalog", "job", "job_status", "multi", "log", "update_check", "uninstall_status" ]
      }
    },
    "write": {
      "ubus": {
        "dns_manager": [ "dnscrypt_latencies", "dnscrypt_cancel", "test_page", "test_page_cancel", "switch_engine", "set_profile", "set_regional", "reset_dns", "set_slot", "set_slot_domains", "set_device_dns", "set_cache", "add_custom_dns", "delete_custom_dns", "set_setting", "set_bootstrap", "set_watchdog_setting", "set_watchdog_settings", "set_ntp", "set_test_age", "test_all", "test_current", "test_one", "test_system", "test_combined", "update", "update_manager", "update_hdp", "update_catalog", "update_all", "update_background", "uninstall" ]
      }
    }
  }
}
EOF_ACL

    BACKEND_STAGE="${BACKEND_FILE}.new.$$"
    rm -f "$BACKEND_STAGE" 2>/dev/null || true
    cat > "$BACKEND_STAGE" <<'EOF_RPC'
#!/bin/sh
# DNS Manager LuCI rpcd plugin
# Lightweight read path for dashboard; mutations and DNS tests use the
# authoritative /usr/bin/dns-manager backend through a strict allowlist.

MANAGER="/usr/bin/dns-manager"
MANAGER_PATH="$MANAGER"
CONFIG_FILE="/etc/dns-manager/config/manager.conf"
CATALOG_FILE="/etc/dns-manager/config/dns-catalog.conf"
CUSTOM_CATALOG_FILE="/etc/dns-manager/config/dns-custom-catalog.conf"
STATE_DIR="/var/run/dns-manager"
PERSIST_STATE_DIR="/etc/dns-manager/state"
RUNTIME_DIR="/var/run/dns-manager-luci"
JOB_DIR="$RUNTIME_DIR/jobs"
# Hard wall-clock limits for persistent background jobs.
JOB_MAX_AGE_PROFILE=900
JOB_MAX_AGE_TEST_ALL=1800
JOB_MAX_AGE_TEST_CURRENT=300
JOB_MAX_AGE_TEST_ONE=60
CHECK_DIR="$RUNTIME_DIR/checks"
TMP_ROOT="$RUNTIME_DIR/tmp"
UPDATE_STATE="/etc/dns-manager-luci/update.state"
UPDATE_CHECK_CACHE="$RUNTIME_DIR/update-check.cache"
UPDATE_CHECK_LOCK="$RUNTIME_DIR/update-check.lock"
COMPANION_URL="$(sed -n 's/^source=//p' /etc/dns-manager-luci/version 2>/dev/null | head -n1)"
case "$COMPANION_URL" in
    https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/*/dns-manager-luci.sh) _dm_ref="${COMPANION_URL#https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/}"; _dm_ref="${_dm_ref%/dns-manager-luci.sh}";;
    *) _dm_ref=main;;
esac
case "$_dm_ref" in ''|/*|*//*|*..*|*[!A-Za-z0-9._/-]*) _dm_ref=main;; esac
DM_SOURCE_BASE="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/$_dm_ref"
COMPANION_URL="$DM_SOURCE_BASE/dns-manager-luci.sh"
VERSION_FILE="/etc/dns-manager-luci/version"
VIEW_FILE="$VIEW_DIR/dashboard.js"
SELF_VERSION="2.141"

umask 077
if [ "${1:-}" != "call" ] || [ "${2:-}" != "runtime" ]; then
    mkdir -p "$RUNTIME_DIR" "$JOB_DIR" "$CHECK_DIR" "$TMP_ROOT" 2>/dev/null || exit 1
fi

acquire_runtime_lock() {
    _lock="$1"
    _parent="${_lock%/*}"
    mkdir -p "$_parent" 2>/dev/null || return 1
    if mkdir "$_lock" 2>/dev/null; then
        printf '%s\n' "$$" > "$_lock/pid" 2>/dev/null || true
        return 0
    fi
    _pid="$(cat "$_lock/pid" 2>/dev/null)"
    case "$_pid" in ''|*[!0-9]*) _pid="" ;; esac
    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then
        return 1
    fi
    rm -rf "$_lock" 2>/dev/null || true
    mkdir "$_lock" 2>/dev/null || return 1
    printf '%s\n' "$$" > "$_lock/pid" 2>/dev/null || true
    return 0
}
release_runtime_lock() {
    [ -n "${1:-}" ] || return 0
    rm -rf "$1" 2>/dev/null || true
}
json_update_state() {
    case "$1" in
        *'"ok":true,"updated":true'*) printf '%s' updated ;;
        *'"ok":true,"updated":false'*) printf '%s' current ;;
        *'"ok":false'*) printf '%s' error ;;
        *) printf '%s' unknown ;;
    esac
}
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
    sed -n 's/^[[:space:]]*VERSION=["'"'"']\([^"'"'"']*\)["'"'"'][[:space:]]*$/\1/p' "$MANAGER" 2>/dev/null | head -n1
}

manager_const_num() {
    _key="$1"
    _fallback="$2"
    case "$_key" in
        WATCHDOG_FAIL_THRESHOLD) _min=1; _max=5 ;;
        WATCHDOG_REPAIR_COOLDOWN) _min=300; _max=7200 ;;
        WATCHDOG_MAX_RESTARTS) _min=1; _max=5 ;;
        WATCHDOG_GUARD_INTERVAL) _min=900; _max=10800 ;;
        *) printf '%s' "$_fallback"; return 0 ;;
    esac
    _v="$(sed -n "s/^${_key}=\"\([0-9][0-9]*\)\"$/\1/p" "$CONFIG_FILE" 2>/dev/null | head -n1)"
    case "$_v" in
        ''|*[!0-9]*) printf '%s' "$_fallback" ;;
        *)
            if [ "$_v" -ge "$_min" ] 2>/dev/null && [ "$_v" -le "$_max" ] 2>/dev/null; then
                printf '%s' "$_v"
            else
                printf '%s' "$_fallback"
            fi
            ;;
    esac
}

watchdog_service_enabled() {
    grep -Fqx '* * * * * /usr/bin/dns-manager-watchdog >/dev/null 2>&1 # dm-watchdog' /etc/crontabs/root 2>/dev/null || grep -Fqx '*/2 * * * * /usr/bin/dns-manager-watchdog >/dev/null 2>&1 # dm-watchdog' /etc/crontabs/root 2>/dev/null
}
watchdog_service_running() {
    watchdog_service_enabled && /etc/init.d/cron running >/dev/null 2>&1
}
watchdog_loop_running() {
    watchdog_service_running
}

cfg_get() {
    _key="$1"
    [ -r "$CONFIG_FILE" ] || return 0
    awk -v k="$_key" 'BEGIN { q=sprintf("%c",39) } index($0,k"=")==1 { v=substr($0,length(k)+2); sub(/^"/,"",v); sub(/"$/,"",v); sub("^" q,"",v); sub(q "$","",v); print v; exit }' "$CONFIG_FILE" 2>/dev/null
}

catalog_field() {
    _id="$1"; _n="$2"
    for _cf_file in "$CATALOG_FILE" "$CUSTOM_CATALOG_FILE"; do
        [ -r "$_cf_file" ] || continue
        _cf_value="$(awk -F'|' -v id="$_id" -v n="$_n" '$1==id { if (n==2) print $2; else if (n==4) print $4; else if (n==5) print $5; exit }' "$_cf_file" 2>/dev/null)"
        [ -n "$_cf_value" ] && { printf '%s' "$_cf_value"; return 0; }
    done
    return 1
}

catalog_version() { sed -n 's/^# DNSCATVER=//p' "$CATALOG_FILE" 2>/dev/null | head -n1; }
catalog_revision() { sed -n 's/^# DNSCATREV=//p' "$CATALOG_FILE" 2>/dev/null | head -n1; }

catalog_url_normalize() {
    _cun_url="$(printf '%s' "$1" | sed 's/[[:space:]]//g')"
    # Normalize only a slash at the origin root. Keep path-ending slashes.
    case "$_cun_url" in
        https://*/*)
            _cun_authority_path="${_cun_url#https://}"
            _cun_path="${_cun_authority_path#*/}"
            [ -n "$_cun_path" ] || _cun_url="${_cun_url%/}"
            ;;
    esac
    printf '%s' "$_cun_url"
}
catalog_id_for_url() {
    _cui_url="$(catalog_url_normalize "$1")"
    [ -n "$_cui_url" ] || return 1
    for _cui_file in "$CATALOG_FILE" "$CUSTOM_CATALOG_FILE"; do
        [ -r "$_cui_file" ] || continue
        _cui_id="$(awk -F'|' -v u="$_cui_url" '
            function norm_url(x) {
                gsub(/[[:space:]]/, "", x)
                if (x ~ /^https:\/\/[^/]+\/$/) sub(/\/$/, "", x)
                return x
            }
            $1 !~ /^#/ && $1 != "" && $5 != "" && norm_url($5) == u { print $1; exit }
        ' "$_cui_file" 2>/dev/null)"
        [ -n "$_cui_id" ] && { printf '%s' "$_cui_id"; return 0; }
    done
    return 1
}


add_custom_dns_json() {
    if ! acquire_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"; then
        json_error "Список пользовательских DNS уже изменяется"
        return
    fi
    # load_manager() sources backend functions into this shell; keep request values out
    # of its shared underscore-prefixed temporary-variable namespace.
    DNSMGR_ADD_CUSTOM_NAME="$(jget name)"
    DNSMGR_ADD_CUSTOM_URL="$(catalog_url_normalize "$(jget url)")"
    if [ -z "$DNSMGR_ADD_CUSTOM_NAME" ] || [ -z "$DNSMGR_ADD_CUSTOM_URL" ]; then
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Укажите название и HTTPS URL DoH"
        return
    fi
    _name_len="$(printf '%s' "$DNSMGR_ADD_CUSTOM_NAME" | wc -c | tr -d ' ')"
    _url_len="$(printf '%s' "$DNSMGR_ADD_CUSTOM_URL" | wc -c | tr -d ' ')"
    case "$_name_len" in ''|*[!0-9]*) _name_len=999;; esac
    case "$_url_len" in ''|*[!0-9]*) _url_len=999;; esac
    if [ "$_name_len" -gt 80 ] || printf '%s' "$DNSMGR_ADD_CUSTOM_NAME" | LC_ALL=C grep -q '[|[:cntrl:]]'; then
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Название должно быть до 80 байт, без служебных символов и вертикальной черты"
        return
    fi
    if [ "$_url_len" -gt 512 ] || ! printf '%s' "$DNSMGR_ADD_CUSTOM_URL" | LC_ALL=C grep -Eq '^https://[A-Za-z0-9._~:/?#@!$&()*+,;=%-]+$'; then
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Укажите корректный HTTPS URL DoH без пробелов и служебных символов"
        return
    fi
    _authority="$(printf '%s' "$DNSMGR_ADD_CUSTOM_URL" | sed -e 's|^https://||' -e 's|[/#?].*$||')"
    if ! printf '%s' "$_authority" | LC_ALL=C grep -Eq '^([A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?)(:[0-9]{1,5})?$'; then
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "В HTTPS URL указан некорректный адрес сервера"
        return
    fi
    case "$_authority" in
        *:*)
            _port="$(printf '%s' "$_authority" | sed 's/^.*://')"
            case "$_port" in ''|*[!0-9]*) _port=0;; esac
            if [ "$_port" -lt 1 ] 2>/dev/null || [ "$_port" -gt 65535 ] 2>/dev/null; then
                release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
                json_error "Порт в HTTPS URL должен быть от 1 до 65535"
                return
            fi
            ;;
    esac
    load_manager || {
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "DNS Manager недоступен"
        return
    }
    _duplicate="$(catalog_id_for_url "$DNSMGR_ADD_CUSTOM_URL" 2>/dev/null || true)"
    if [ -n "$_duplicate" ]; then
        _duplicate_name="$(catalog_field "$_duplicate" 4 2>/dev/null || true)"
        [ -n "$_duplicate_name" ] || _duplicate_name="$_duplicate"
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Этот DoH URL уже есть в каталоге: $_duplicate_name"
        return
    fi
    mkdir -p "$(dirname "$CUSTOM_CATALOG_FILE")" 2>/dev/null || {
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Не удалось создать каталог пользовательских DNS"
        return
    }
    [ -f "$CUSTOM_CATALOG_FILE" ] || : > "$CUSTOM_CATALOG_FILE"
    chmod 600 "$CUSTOM_CATALOG_FILE" 2>/dev/null || true
    _n=1
    while [ "$_n" -le 999 ]; do
        _id="$(printf 'custom_%03d' "$_n")"
        [ -z "$(dns_cat "$_id" 2>/dev/null || true)" ] && break
        _n=$((_n + 1))
    done
    if [ "$_n" -gt 999 ]; then
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Достигнут лимит пользовательских DNS"
        return
    fi
    _tmp="$(mktemp "$CUSTOM_CATALOG_FILE.tmp.XXXXXX" 2>/dev/null || true)"
    if [ -z "$_tmp" ]; then
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Не удалось подготовить файл пользовательских DNS"
        return
    fi
    cat "$CUSTOM_CATALOG_FILE" > "$_tmp" 2>/dev/null || : > "$_tmp"
    printf '%s|custom|custom|%s|%s|manual|USER\n' "$_id" "$DNSMGR_ADD_CUSTOM_NAME" "$DNSMGR_ADD_CUSTOM_URL" >> "$_tmp" || {
        rm -f "$_tmp" 2>/dev/null || true
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Не удалось записать пользовательский DNS"
        return
    }
    chmod 600 "$_tmp" 2>/dev/null || true
    mv -f "$_tmp" "$CUSTOM_CATALOG_FILE" || {
        rm -f "$_tmp" 2>/dev/null || true
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Не удалось сохранить пользовательский DNS"
        return
    }
    release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
    printf '{"ok":true,"id":'; json_quote "$_id"
    printf ',"name":'; json_quote "$DNSMGR_ADD_CUSTOM_NAME"
    printf ',"url":'; json_quote "$DNSMGR_ADD_CUSTOM_URL"
    printf '}'
}

delete_custom_dns_json() {
    DNSMGR_DCD_ID="$(jget id)"
    case "$DNSMGR_DCD_ID" in custom_[0-9][0-9][0-9]) ;; *) json_error "Можно удалять только пользовательские DNS"; return;; esac
    if ! acquire_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"; then
        json_error "Список пользовательских DNS уже изменяется"
        return
    fi
    load_manager || { release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"; json_error "DNS Manager недоступен"; return; }
    if ! awk -F"|" -v id="$DNSMGR_DCD_ID" '$1==id {found=1} END {exit !found}' "$CUSTOM_CATALOG_FILE" 2>/dev/null; then
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Пользовательский DNS не найден"
        return
    fi
    if ! acquire_test_lock; then
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Проверка DNS выполняется. Дождитесь её завершения и повторите удаление"
        return
    fi
    for DNSMGR_DCD_SLOT in 1 2 3 4 5 6 RU; do
        DNSMGR_DCD_ASSIGNED="$(cfg_get "SLOT_$DNSMGR_DCD_SLOT" 2>/dev/null || true)"
        if [ "$DNSMGR_DCD_ASSIGNED" = "$DNSMGR_DCD_ID" ]; then
            release_test_lock
            release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
            json_error "DNS назначен в слоте $DNSMGR_DCD_SLOT. Сначала замените DNS в этом слоте"
            return
        fi
    done
    DNSMGR_DCD_TMP="$(mktemp "$CUSTOM_CATALOG_FILE.delete.XXXXXX" 2>/dev/null || true)"
    if [ -z "$DNSMGR_DCD_TMP" ]; then
        release_test_lock
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Не удалось подготовить удаление пользовательского DNS"
        return
    fi
    if ! awk -F"|" -v id="$DNSMGR_DCD_ID" '$1!=id {print} $1==id {found=1} END {if(!found) exit 1}' "$CUSTOM_CATALOG_FILE" > "$DNSMGR_DCD_TMP"; then
        rm -f "$DNSMGR_DCD_TMP" 2>/dev/null || true
        release_test_lock
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Не удалось прочитать пользовательский каталог DNS"
        return
    fi
    chmod 600 "$DNSMGR_DCD_TMP" 2>/dev/null || true
    if ! mv -f "$DNSMGR_DCD_TMP" "$CUSTOM_CATALOG_FILE"; then
        rm -f "$DNSMGR_DCD_TMP" 2>/dev/null || true
        release_test_lock
        release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
        json_error "Не удалось сохранить изменения пользовательского каталога DNS"
        return
    fi
    for DNSMGR_DCD_RESULTS in "$STATE_DIR/dns-test-results.conf" "$PERSIST_STATE_DIR/dns-test-results.conf"; do
        [ -f "$DNSMGR_DCD_RESULTS" ] || continue
        DNSMGR_DCD_RESULT_TMP="$(mktemp "$DNSMGR_DCD_RESULTS.tmp.XXXXXX" 2>/dev/null || true)"
        [ -n "$DNSMGR_DCD_RESULT_TMP" ] || continue
        if awk -F"|" -v id="$DNSMGR_DCD_ID" '$1!=id {print}' "$DNSMGR_DCD_RESULTS" > "$DNSMGR_DCD_RESULT_TMP" && mv -f "$DNSMGR_DCD_RESULT_TMP" "$DNSMGR_DCD_RESULTS"; then
            chmod 600 "$DNSMGR_DCD_RESULTS" 2>/dev/null || true
        else
            rm -f "$DNSMGR_DCD_RESULT_TMP" 2>/dev/null || true
        fi
    done
    rm -f "$CHECK_DIR/$DNSMGR_DCD_ID" 2>/dev/null || true
    release_test_lock
    release_runtime_lock "$RUNTIME_DIR/custom-catalog.lock"
    printf '{"ok":true,"id":'; json_quote "$DNSMGR_DCD_ID"; printf '}'
}

read_installed_luci_version() {
    _v=""
    # The view is the code that LuCI actually loads, so it is the authoritative
    # installed-version marker. Persistent markers are only fallbacks for
    # partially migrated/legacy installations.
    [ -r "$VIEW_FILE" ] && _v="$(sed -n 's|^// DNS Manager LuCI version: *||p' "$VIEW_FILE" 2>/dev/null | head -n1)"
    [ -n "$_v" ] || [ ! -r "$VERSION_FILE" ] || _v="$(sed -n 's/^version=//p' "$VERSION_FILE" 2>/dev/null | head -n1)"
    [ -n "$_v" ] || [ ! -r "/etc/dns-manager/config/luci-state.conf" ] || _v="$(sed -n 's/^version=//p' /etc/dns-manager/config/luci-state.conf 2>/dev/null | head -n1)"
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
        curl -fsSL --connect-timeout 4 --max-time 20 -H "Cache-Control: no-cache" -H "Pragma: no-cache" -o "$_out" "$_fetch_url" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 20 --header="Cache-Control: no-cache" --header="Pragma: no-cache" -O "$_out" "$_fetch_url" >/dev/null 2>&1
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
    _cb="$(date +%s 2>/dev/null || printf 0)-$$"
    case "$COMPANION_URL" in
        *\?*) _fetch_url="${COMPANION_URL}&_dmcb=$_cb" ;;
        *) _fetch_url="${COMPANION_URL}?_dmcb=$_cb" ;;
    esac
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 5 --max-time 30 -H 'User-Agent: DNS-Manager-LuCI' -H 'Cache-Control: no-cache' -o "$_out" "$_fetch_url" >/dev/null 2>&1
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 30 --header='User-Agent: DNS-Manager-LuCI' --header='Cache-Control: no-cache' -O "$_out" "$_fetch_url" >/dev/null 2>&1
    elif command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -O "$_out" "$_fetch_url" >/dev/null 2>&1
    else
        return 1
    fi
    [ -s "$_out" ] || return 1
    [ "$(wc -c < "$_out" 2>/dev/null | tr -d ' ')" -le 600000 ] 2>/dev/null || return 1
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
    UPDATE_CHECK_LUCI_OK=0
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
    UPDATE_CHECK_LUCI_OK=1
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

catalog_cached_update_available() {
    # A cached check can predate installation of the very revision it found.
    # Only clear its flag when all published metadata matches the local file.
    if [ "$1" = 1 ] && [ "$2" = 1 ] && [ -n "$3" ] && [ -n "$4" ] &&
       [ "$5" != 0 ] && [ -n "$5" ] && [ "$3" = "$6" ] && [ "$4" = "$7" ] && [ "$5" = "$8" ]; then
        printf 0
    else
        printf '%s' "$1"
    fi
}
component_update_check() {
    UPDATE_CHECK_COMPONENTS_OK=1
    _ts="$(date +%s 2>/dev/null || printf 0)"
    _manager_installed="$(manager_version 2>/dev/null || true)"
    _manager_latest=""; _manager_available=0; _manager_ok=0; _manager_error=""
    _tmp="$TMP_ROOT/manager-check.$$"
    if [ -z "$_manager_installed" ]; then
        _manager_error="DNS Manager не найден на роутере"
        UPDATE_CHECK_COMPONENTS_OK=0
    elif { [ "$(uci -q get dns-manager.global.active_engine 2>/dev/null)" = dnscrypt-proxy2 ] &&
           fetch_raw_url "$_tmp" "$DM_SOURCE_BASE/dns-manager.sh"; } ||
         { [ "$(uci -q get dns-manager.global.active_engine 2>/dev/null)" != dnscrypt-proxy2 ] &&
           fetch_raw_url "$_tmp" "$DM_SOURCE_BASE/dns-manager.sh"; }; then
        _manager_latest="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$_tmp" 2>/dev/null | head -n1)"
        if [ -n "$_manager_latest" ]; then
            _manager_ok=1
            [ "$(version_gt "$_manager_latest" "$_manager_installed")" = 1 ] && _manager_available=1
        else
            _manager_error="в файле DNS Manager не найдена версия"
            UPDATE_CHECK_COMPONENTS_OK=0
        fi
    else
        _manager_error="не удалось получить DNS Manager с GitHub"
        UPDATE_CHECK_COMPONENTS_OK=0
    fi
    rm -f "$_tmp" 2>/dev/null || true

    _catalog_latest=""; _catalog_latest_rev=""; _catalog_latest_total=0; _catalog_available=0; _catalog_ok=0; _catalog_error=""
    _tmp="$TMP_ROOT/catalog-check.$$"
    if fetch_raw_url "$_tmp" "$DM_SOURCE_BASE/catalogs/dns-8.8-FULL-CONFIG-CLEAN.conf"; then
        _catalog_latest="$(sed -n 's/^# DNSCATVER=//p' "$_tmp" 2>/dev/null | head -n1)"
        _catalog_latest_rev="$(sed -n 's/^# DNSCATREV=//p' "$_tmp" 2>/dev/null | head -n1)"
        _catalog_latest_total="$(grep -v '^#' "$_tmp" 2>/dev/null | grep -c '^[^|][^|]*|' 2>/dev/null || printf 0)"
        if [ -n "$_catalog_latest" ]; then
            _catalog_ok=1
        else
            _catalog_error="полученный каталог DNS не содержит версии"
            UPDATE_CHECK_COMPONENTS_OK=0
        fi
        _local_rev="$(sed -n 's/^# DNSCATREV=//p' "$CATALOG_FILE" 2>/dev/null | head -n1)"
        _local_total="$(grep -v '^#' "$CATALOG_FILE" 2>/dev/null | grep -c '^[^|][^|]*|' 2>/dev/null || printf 0)"
        _catalog_same=0
        _remote_body="$TMP_ROOT/catalog-remote-body.$$"
        _local_body="$TMP_ROOT/catalog-local-body.$$"
        sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$_tmp" > "$_remote_body" 2>/dev/null || true
        if [ -r "$CATALOG_FILE" ]; then
            sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$CATALOG_FILE" > "$_local_body" 2>/dev/null || true
            if cmp -s "$_remote_body" "$_local_body" 2>/dev/null; then _catalog_same=1; fi
        fi
        if [ "$_catalog_same" != 1 ] && [ "$_catalog_ok" = 1 ]; then
            [ "$_catalog_latest" != "$(catalog_version)" ] && _catalog_available=1
            [ -n "$_catalog_latest_rev" ] && [ "$_catalog_latest_rev" != "$_local_rev" ] && _catalog_available=1
            [ "$_catalog_latest_total" != "$_local_total" ] && _catalog_available=1
        else
            _catalog_available=0
        fi
        rm -f "$_remote_body" "$_local_body" 2>/dev/null || true
    else
        _catalog_error="не удалось получить каталог DNS с GitHub"
        UPDATE_CHECK_COMPONENTS_OK=0
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
    printf 'manager_error=%s\n' "$_manager_error" >> "$_state_tmp"
    printf 'catalog_latest=%s\n' "$_catalog_latest" >> "$_state_tmp"
    printf 'catalog_latest_rev=%s\n' "$_catalog_latest_rev" >> "$_state_tmp"
    printf 'catalog_latest_total=%s\n' "$_catalog_latest_total" >> "$_state_tmp"
    printf 'catalog_available=%s\n' "$_catalog_available" >> "$_state_tmp"
    printf 'catalog_checked=%s\n' "$_catalog_ok" >> "$_state_tmp"
    printf 'catalog_error=%s\n' "$_catalog_error" >> "$_state_tmp"
    printf 'hdp_latest=%s\n' "$_hdp_latest" >> "$_state_tmp"
    printf 'hdp_available=%s\n' "$_hdp_available" >> "$_state_tmp"
    printf 'hdp_checked=%s\n' "$_hdp_checked" >> "$_state_tmp"
    printf 'components_checked_at=%s\n' "$_ts" >> "$_state_tmp"
    mv "$_state_tmp" "$UPDATE_STATE" 2>/dev/null || rm -f "$_state_tmp" 2>/dev/null || true
}

update_hdp_json() {
    if ! acquire_runtime_lock "$RUNTIME_DIR/hdp-update.lock"; then
        json_error "Обновление https-dns-proxy уже выполняется"; return
    fi
    trap 'release_runtime_lock "$RUNTIME_DIR/hdp-update.lock"' EXIT INT TERM
    _installed="$(package_version https-dns-proxy 2>/dev/null || true)"
    [ -n "$_installed" ] || { json_error "https-dns-proxy не установлен"; return; }
    package_update_index || { json_error "Не удалось обновить индекс пакетов для https-dns-proxy"; return; }
    _candidate="$(package_candidate_version https-dns-proxy 2>/dev/null || true)"
    [ -n "$_candidate" ] || {
        _state_tmp="$UPDATE_STATE.tmp.$$"
        if [ -r "$UPDATE_STATE" ]; then
            sed '/^hdp_latest=/d;/^hdp_available=/d;/^hdp_checked=/d;/^components_checked_at=/d' "$UPDATE_STATE" > "$_state_tmp" 2>/dev/null || true
        else
            : > "$_state_tmp"
        fi
        _ts="$(date +%s 2>/dev/null || printf 0)"
        printf 'hdp_latest=%s\nhdp_available=0\nhdp_checked=1\ncomponents_checked_at=%s\n' "$_installed" "$_ts" >> "$_state_tmp"
        mv "$_state_tmp" "$UPDATE_STATE" 2>/dev/null || rm -f "$_state_tmp" 2>/dev/null || true
        printf '{"ok":true,"updated":false,"version":'; json_quote "$_installed"; printf ',"message":'; json_quote "https-dns-proxy уже актуален"; printf '}'
        return
    }
    if ! package_version_cmp "$_candidate" "$_installed"; then
        _state_tmp="$UPDATE_STATE.tmp.$$"
        if [ -r "$UPDATE_STATE" ]; then
            sed '/^hdp_latest=/d;/^hdp_available=/d;/^hdp_checked=/d;/^components_checked_at=/d' "$UPDATE_STATE" > "$_state_tmp" 2>/dev/null || true
        else
            : > "$_state_tmp"
        fi
        _ts="$(date +%s 2>/dev/null || printf 0)"
        printf 'hdp_latest=%s\nhdp_available=0\nhdp_checked=1\ncomponents_checked_at=%s\n' "$_installed" "$_ts" >> "$_state_tmp"
        mv "$_state_tmp" "$UPDATE_STATE" 2>/dev/null || rm -f "$_state_tmp" 2>/dev/null || true
        printf '{"ok":true,"updated":false,"version":'; json_quote "$_installed"; printf ',"message":'; json_quote "https-dns-proxy уже актуален"; printf '}'
        return
    fi
    if ! package_upgrade_hdp; then
        json_error "https-dns-proxy не удалось обновить"; return
    fi
    _after="$(package_version https-dns-proxy 2>/dev/null || true)"
    [ -n "$_after" ] || { json_error "Не удалось определить версию после обновления"; return; }
    _state_tmp="$UPDATE_STATE.tmp.$$"
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
    if ! acquire_runtime_lock "$RUNTIME_DIR/catalog-update.lock"; then
        json_error "Обновление каталога DNS уже выполняется"
        return
    fi
    _old_v="$(catalog_version 2>/dev/null || true)"
    _old_r="$(catalog_revision 2>/dev/null || true)"
    update_catalog_direct
    _rc=$?
    _new_v="$(catalog_version 2>/dev/null || true)"
    _new_r="$(catalog_revision 2>/dev/null || true)"
    release_runtime_lock "$RUNTIME_DIR/catalog-update.lock"
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
    _force="$(jget force 2>/dev/null || true)"
    [ "$_force" = 1 ] || _force=0

    # Match Zapret Manager behavior: cache remote version data in tmpfs
    # for 30 minutes. A reboot clears the cache and forces a new check.
    if [ "$_force" != 1 ] && [ -f "$UPDATE_CHECK_CACHE" ] && [ -z "$(find "$UPDATE_CHECK_CACHE" -mmin +30 2>/dev/null)" ]; then
        status_json
        return 0
    fi

    # Only one LuCI worker performs the remote check at a time.
    if ! acquire_runtime_lock "$UPDATE_CHECK_LOCK"; then
        status_json
        return 0
    fi

    # Another worker may have completed the check while we acquired the lock.
    if [ "$_force" != 1 ] && [ -f "$UPDATE_CHECK_CACHE" ] && [ -z "$(find "$UPDATE_CHECK_CACHE" -mmin +30 2>/dev/null)" ]; then
        release_runtime_lock "$UPDATE_CHECK_LOCK"
        status_json
        return 0
    fi

    update_check_json_luci >/dev/null 2>&1 || true
    component_update_check || true

    if [ "${UPDATE_CHECK_LUCI_OK:-0}" = 1 ] && [ "${UPDATE_CHECK_COMPONENTS_OK:-0}" = 1 ]; then
        _ts="$(date +%s 2>/dev/null || printf 0)"
        printf '%s\n' "$_ts" > "$UPDATE_CHECK_CACHE" 2>/dev/null || true
    fi
    release_runtime_lock "$UPDATE_CHECK_LOCK"
    status_json
}
update_catalog_direct() {
    _tmp="$TMP_ROOT/catalog-update-all.$$"
    fetch_raw_url "$_tmp" "$DM_SOURCE_BASE/catalogs/dns-8.8-FULL-CONFIG-CLEAN.conf" || { rm -f "$_tmp" 2>/dev/null || true; return 3; }
    _remote_ver="$(sed -n 's/^# DNSCATVER=//p' "$_tmp" 2>/dev/null | head -n1)"
    _remote_rev="$(sed -n 's/^# DNSCATREV=//p' "$_tmp" 2>/dev/null | head -n1)"
    _decl="$(sed -n 's/^# ENTRIES=//p' "$_tmp" 2>/dev/null | head -n1)"
    _count="$(grep -v '^[[:space:]]*#' "$_tmp" 2>/dev/null | grep -v '^[[:space:]]*$' | wc -l | tr -d ' ')"
    case "$_count" in ''|*[!0-9]*) _count=0;; esac
    [ -n "$_remote_ver" ] && [ -n "$_remote_rev" ] && [ "$_decl" = "$_count" ] && [ "$_count" -gt 0 ] || { rm -f "$_tmp" 2>/dev/null || true; return 4; }
    awk -F'|' '/^[[:space:]]*#/ || /^[[:space:]]*$/ {next} {if(NF!=7 || $1=="" || $4=="" || $5 !~ /^https:\/\//) bad=1; if($1 !~ /^[A-Za-z0-9_-]+$/) bad=1; if($2 !~ /^(bypass|clean|security|privacy|adblock|family|gaming|regional)$/) bad=1; ids[$1]++; if(ids[$1]>1) bad=1; n++} END{if(bad || n<1) exit 1}' "$_tmp" >/dev/null 2>&1 || { rm -f "$_tmp" 2>/dev/null || true; return 4; }
    # Never silently downgrade the installed revision when a test branch is
    # ahead of the stable catalog, or when a mirror returns stale content.
    _local_ver="$(catalog_version 2>/dev/null || true)"
    _local_rev="$(catalog_revision 2>/dev/null || true)"
    case "$_remote_rev:$_local_rev" in
        *[!0-9:]*|:*|*:) ;;
        *) if [ "$_remote_ver" = "$_local_ver" ] && [ "$_remote_rev" -lt "$_local_rev" ] 2>/dev/null; then rm -f "$_tmp"; return 2; fi ;;
    esac
    _rb="$TMP_ROOT/catalog-remote-all.$"
    _lb="$TMP_ROOT/catalog-local-all.$"
    _old_shecan_url="$(awk -F'|' '$1=="shecan" {print $5; exit}' "$CATALOG_FILE" 2>/dev/null)"
    _old_astracat_url="$(awk -F'|' '$1=="astracat" {print $5; exit}' "$CATALOG_FILE" 2>/dev/null)"
    _old_magicdns_url="$(awk -F'|' '$1=="magicdns" {print $5; exit}' "$CATALOG_FILE" 2>/dev/null)"
    _old_geohide_url="$(awk -F'|' '$1=="geohide" {print $5; exit}' "$CATALOG_FILE" 2>/dev/null)"
    _new_shecan_url="$(awk -F'|' '$1=="shecan" {print $5; exit}' "$_tmp" 2>/dev/null)"
    _new_astracat_url="$(awk -F'|' '$1=="astracat" {print $5; exit}' "$_tmp" 2>/dev/null)"
    _new_magicdns_url="$(awk -F'|' '$1=="magicdns" {print $5; exit}' "$_tmp" 2>/dev/null)"
    _new_geohide_url="$(awk -F'|' '$1=="geohide" {print $5; exit}' "$_tmp" 2>/dev/null)"
    sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$_tmp" > "$_rb" 2>/dev/null || true
    sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$CATALOG_FILE" > "$_lb" 2>/dev/null || true
    if cmp -s "$_rb" "$_lb" 2>/dev/null; then rm -f "$_tmp" "$_rb" "$_lb" 2>/dev/null || true; return 2; fi
    _config_backup=""
    if [ -f "$CONFIG_FILE" ]; then
        _config_backup="$(mktemp "${CONFIG_FILE}.backup.XXXXXX")" || return 5
        cp -p "$CONFIG_FILE" "$_config_backup" || { rm -f "$_config_backup"; return 5; }
    fi
    "$MANAGER_PATH" __catalog-migrate "$_tmp" >/dev/null 2>&1 || { rm -f "$_tmp" "$_rb" "$_lb" "$_config_backup"; return 5; }
    mv -f "$_tmp" "$CATALOG_FILE" 2>/dev/null || {
        [ -z "$_config_backup" ] || mv -f "$_config_backup" "$CONFIG_FILE"
        rm -f "$_tmp" "$_rb" "$_lb"; return 5
    }
    [ -z "$_config_backup" ] || rm -f "$_config_backup"
    chmod 600 "$CATALOG_FILE" 2>/dev/null || true
    if [ "$_old_shecan_url" != "$_new_shecan_url" ]; then
        for _result_file in "$STATE_DIR/dns-test-results.conf" "$PERSIST_STATE_DIR/dns-test-results.conf"; do
            [ -s "$_result_file" ] || continue
            _result_tmp="${_result_file}.tmp.$"
            awk -F'|' '$1!="shecan" {print}' "$_result_file" > "$_result_tmp" 2>/dev/null &&
                mv -f "$_result_tmp" "$_result_file" 2>/dev/null ||
                rm -f "$_result_tmp" 2>/dev/null || true
        done
        rm -f "$CHECK_DIR/shecan" 2>/dev/null || true
    fi
    if [ "$_old_astracat_url" != "$_new_astracat_url" ]; then
        for _result_file in "$STATE_DIR/dns-test-results.conf" "$PERSIST_STATE_DIR/dns-test-results.conf"; do
            [ -s "$_result_file" ] || continue
            _result_tmp="${_result_file}.tmp.$"
            awk -F'|' '$1!="astracat" {print}' "$_result_file" > "$_result_tmp" 2>/dev/null &&
                mv -f "$_result_tmp" "$_result_file" 2>/dev/null ||
                rm -f "$_result_tmp" 2>/dev/null || true
        done
        rm -f "$CHECK_DIR/astracat" 2>/dev/null || true
    fi
    if [ "$_old_magicdns_url" != "$_new_magicdns_url" ]; then
        for _result_file in "$STATE_DIR/dns-test-results.conf" "$PERSIST_STATE_DIR/dns-test-results.conf"; do
            [ -s "$_result_file" ] || continue
            _result_tmp="${_result_file}.tmp.$"
            awk -F'|' '$1!="magicdns" {print}' "$_result_file" > "$_result_tmp" 2>/dev/null &&
                mv -f "$_result_tmp" "$_result_file" 2>/dev/null ||
                rm -f "$_result_tmp" 2>/dev/null || true
        done
        rm -f "$CHECK_DIR/magicdns" 2>/dev/null || true
    fi
    if [ "$_old_geohide_url" != "$_new_geohide_url" ]; then
        for _result_file in "$STATE_DIR/dns-test-results.conf" "$PERSIST_STATE_DIR/dns-test-results.conf"; do
            [ -s "$_result_file" ] || continue
            _result_tmp="${_result_file}.tmp.$"
            awk -F'|' '$1!="geohide" {print}' "$_result_file" > "$_result_tmp" 2>/dev/null &&
                mv -f "$_result_tmp" "$_result_file" 2>/dev/null ||
                rm -f "$_result_tmp" 2>/dev/null || true
        done
        rm -f "$CHECK_DIR/geohide" 2>/dev/null || true
    fi
    rm -f "$_rb" "$_lb" 2>/dev/null || true
    return 0
}

append_update_message() {
    if [ -n "$_message" ]; then _message="$_message; $1"; else _message="$1"; fi
}

append_failure_message() {
    if [ -n "$_failed" ]; then _failed="$_failed; $1"; else _failed="$1"; fi
}

update_all_json() {
    if ! acquire_runtime_lock "$RUNTIME_DIR/update-all.lock"; then
        json_error "Обновление уже выполняется"
        return
    fi
    _message=""
    _failed=""

    [ "${DM_BACKGROUND_ID:-}" != update ] || job_write update name 'DNS Manager'
    _old_m="$(manager_version 2>/dev/null || true)"
    _mr="$(update_manager_json 2>/dev/null || true)"
    _new_m="$(manager_version 2>/dev/null || true)"
    case "$(json_update_state "$_mr")" in
        updated)
            if [ -n "$_old_m" ] && [ -n "$_new_m" ] && [ "$_new_m" != "$_old_m" ]; then append_update_message "DNS Manager $_old_m → $_new_m"; else append_update_message "DNS Manager обновлён"; fi
            ;;
        current) append_update_message "DNS Manager $_old_m · актуален" ;;
        *) _detail="$(printf '%s' "$_mr" | jsonfilter -e '@.error' 2>/dev/null)"; append_failure_message "DNS Manager: ${_detail:-не удалось обновить}" ;;
    esac

    # DNSCrypt uses its own static pool. Do not update or restart HTTPS DNS Proxy
    # or replace its catalog while updating the manager in this mode.
    if [ "$(uci -q get dns-manager.global.active_engine 2>/dev/null)" != dnscrypt-proxy2 ]; then
        [ "${DM_BACKGROUND_ID:-}" != update ] || job_write update name 'Защищённый DNS'
        _old_h="$(package_version https-dns-proxy 2>/dev/null || true)"
        _hr="$(update_hdp_json 2>/dev/null || true)"
        _new_h="$(package_version https-dns-proxy 2>/dev/null || true)"
        case "$(json_update_state "$_hr")" in
            updated)
                if [ -n "$_old_h" ] && [ -n "$_new_h" ] && [ "$_new_h" != "$_old_h" ]; then append_update_message "Защищённый DNS $_old_h → $_new_h"; else append_update_message "Защищённый DNS обновлён"; fi
                ;;
            current) append_update_message "Защищённый DNS $_old_h · актуален" ;;
            *) _detail="$(printf '%s' "$_hr" | jsonfilter -e '@.error' 2>/dev/null)"; append_failure_message "Защищённый DNS: ${_detail:-не удалось обновить}" ;;
        esac

        [ "${DM_BACKGROUND_ID:-}" != update ] || job_write update name 'Каталог DNS'
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

    fi

    [ "${DM_BACKGROUND_ID:-}" != update ] || job_write update name 'LuCI'
    _old_l="$(read_installed_luci_version)"
    _lr="$(update_json 2>/dev/null || true)"
    _new_l="$(read_installed_luci_version)"
    case "$(json_update_state "$_lr")" in
        updated)
            if [ -n "$_old_l" ] && [ -n "$_new_l" ] && [ "$_new_l" != "$_old_l" ]; then append_update_message "LuCI $_old_l → $_new_l"; else append_update_message "LuCI обновлена"; fi
            ;;
        current) append_update_message "LuCI $_old_l · актуальна" ;;
        *) _detail="$(printf '%s' "$_lr" | jsonfilter -e '@.error' 2>/dev/null)"; append_failure_message "LuCI: ${_detail:-не удалось обновить}" ;;
    esac

    release_runtime_lock "$RUNTIME_DIR/update-all.lock"
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
    if ! acquire_runtime_lock "$RUNTIME_DIR/manager-update.lock"; then
        json_error "Обновление DNS Manager уже выполняется"; return
    fi
    trap 'release_runtime_lock "$RUNTIME_DIR/manager-update.lock"' EXIT INT TERM
    _installed="$(manager_version 2>/dev/null || true)"
    [ -n "$_installed" ] || { json_error "DNS Manager не найден"; return; }
    if [ "$(uci -q get dns-manager.global.active_engine 2>/dev/null)" = dnscrypt-proxy2 ]; then
        _candidate="$TMP_ROOT/dnscrypt-manager-update.$$"
        _staged="${MANAGER_PATH}.new.$$"
        if ! fetch_raw_url "$_candidate" "$DM_SOURCE_BASE/dns-manager.sh" ||
           ! sh -n "$_candidate"; then
            rm -f "$_candidate"
            json_error "Не удалось загрузить корректный DNS Manager из выбранной ветки"; return
        fi
        _latest="$(sed -n 's/^VERSION="\([^"]*\)"$/\1/p' "$_candidate" | head -n1)"
        case "$_latest" in ''|*[!0-9.]*) rm -f "$_candidate"; json_error "Не удалось определить версию DNS Manager"; return;; esac
        if { [ "$_latest" = "$_installed" ] && cmp -s "$_candidate" "$MANAGER_PATH"; } ||
           { [ "$_latest" != "$_installed" ] && [ "$(version_gt "$_latest" "$_installed")" != 1 ]; }; then
            rm -f "$_candidate"
            DNS_MANAGER_NO_UPDATE=1 "$MANAGER_PATH" __watchdog-migrate >/dev/null 2>&1 || { json_error "Перенос проверки DNS не завершён"; return; }
            printf '{"ok":true,"updated":false,"version":'; json_quote "$_installed"; printf '}'
            return
        fi
        if ! cp "$_candidate" "$_staged" || ! chmod 755 "$_staged" || ! mv -f "$_staged" "$MANAGER_PATH"; then
            rm -f "$_candidate" "$_staged"
            json_error "Не удалось установить DNS Manager"; return
        fi
        rm -f "$_candidate"
        DNS_MANAGER_NO_UPDATE=1 "$MANAGER_PATH" __watchdog-migrate >/dev/null 2>&1 || { json_error "DNS Manager обновлён, но перенос проверки DNS не завершён"; return; }
        printf '{"ok":true,"updated":true,"version":'; json_quote "$_latest"; printf '}'
        return
    fi
    _out="$TMP_ROOT/manager-update.log"
    rm -f "$_out" 2>/dev/null || true
    _rc=0
    DNS_MANAGER_FORCE_UPDATE=1 DNS_MANAGER_UPDATE_NO_EXEC=1 "$MANAGER_PATH" update-check >"$_out" 2>&1 || _rc=$?
    _after="$(manager_version 2>/dev/null || true)"
    if [ "$_rc" = 0 ] || [ "$_rc" = 2 ]; then
        DNS_MANAGER_NO_UPDATE=1 "$MANAGER_PATH" __watchdog-migrate >>"$_out" 2>&1 || _rc=1
    fi
    case "$_rc" in
        0)
            [ -n "$_after" ] || _after="$_installed"
            printf '{"ok":true,"updated":true,"version":'; json_quote "$_after"; printf '}'
            rm -f "$_out" 2>/dev/null || true
            return
            ;;
        2)
            printf '{"ok":true,"updated":false,"version":'; json_quote "$_installed"; printf ',"message":'; json_quote "DNS Manager уже актуален"; printf '}'
            rm -f "$_out" 2>/dev/null || true
            return
            ;;
    esac
    _detail="$(tail -n 8 "$_out" 2>/dev/null | awk 'BEGIN{ORS=" "} {print}' | cut -c1-700)"
    rm -f "$_out" 2>/dev/null || true
    [ -n "$_detail" ] || _detail="Не удалось обновить DNS Manager."
    json_error "$_detail"
}
update_json() {
    if ! acquire_runtime_lock "$RUNTIME_DIR/update.lock"; then
        json_error "Обновление LuCI уже выполняется"; return
    fi
    trap 'release_runtime_lock "$RUNTIME_DIR/update.lock"' EXIT INT TERM
    _installed="$(read_installed_luci_version)"
    _tmp="$TMP_ROOT/companion-update.$$"
    if ! fetch_url "$_tmp" || ! validate_candidate "$_tmp"; then
        rm -f "$_tmp" 2>/dev/null || true
        json_error "Новая версия не прошла проверку"; return
    fi
    _latest="$(sed -n 's/^# Version:[[:space:]]*//p' "$_tmp" 2>/dev/null | head -n1)"
    if [ -z "$_latest" ] || [ "$(version_gt "$_latest" "$_installed")" != 1 ]; then
        rm -f "$_tmp" 2>/dev/null || true
        printf '{"ok":true,"updated":false,"version":'; json_quote "$_installed"; printf ',"message":'; json_quote "DNS Manager LuCI уже актуальна"; printf '}'
        return
    fi
    _log="$TMP_ROOT/companion-update.log"
    rm -f "$_log" 2>/dev/null || true
    if ! DNS_MANAGER_SOURCE_REF="$_dm_ref" DNS_MANAGER_LUCI_SKIP_RPC_RELOAD=1 sh "$_tmp" update >"$_log" 2>&1; then
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
}

result_for_id() {
    _id="$1"
    [ -s "$STATE_DIR/dns-test-results.conf" ] || [ -s "$PERSIST_STATE_DIR/dns-test-results.conf" ] || return 1
    _f="$STATE_DIR/dns-test-results.conf"
    [ -s "$_f" ] || _f="$PERSIST_STATE_DIR/dns-test-results.conf"
    awk -F'|' -v id="$_id" '$1==id {print; found=1; exit} END {if(!found) exit 1}' "$_f" 2>/dev/null
}

system_result_id() {
    _sri_url="$1"; _sri_port="$2"; _sri_index="$3"
    _sri_url="$(catalog_url_normalize "$_sri_url")"
    _sri_cat_id="$(catalog_id_for_url "$_sri_url" 2>/dev/null || true)"
    if [ -n "$_sri_cat_id" ]; then
        printf '%s' "$_sri_cat_id"
        return 0
    fi
    case "$_sri_port" in
        ''|*[!0-9]*) printf 'system_%s' "$_sri_index" ;;
        *) printf 'system_port_%s' "$_sri_port" ;;
    esac
}

last_check_for_id() {
    _id="$1"
    [ -n "$_id" ] || return 1

    _luci_ts="$(cat "$CHECK_DIR/$_id" 2>/dev/null | head -n1)"
    case "$_luci_ts" in ''|*[!0-9]*) _luci_ts="";; esac

    _manager_meta="$STATE_DIR/dns-test-results.meta"
    [ -r "$_manager_meta" ] || _manager_meta="$PERSIST_STATE_DIR/dns-test-results.meta"
    _manager_ts="$(sed -n 's/^timestamp=//p' "$_manager_meta" 2>/dev/null | head -n1)"
    case "$_manager_ts" in ''|*[!0-9]*) _manager_ts="";; esac

    result_for_id "$_id" >/dev/null 2>&1 || return 0
    if [ -n "$_luci_ts" ] && [ -n "$_manager_ts" ]; then
        if [ "$_manager_ts" -gt "$_luci_ts" ] 2>/dev/null; then
            printf '%s' "$_manager_ts"
        else
            printf '%s' "$_luci_ts"
        fi
        return 0
    fi
    [ -n "$_luci_ts" ] && { printf '%s' "$_luci_ts"; return 0; }
    [ -n "$_manager_ts" ] && printf '%s' "$_manager_ts"
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
package_update_index() {
    if command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1
    elif command -v opkg >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1
    else
        return 1
    fi
}
package_upgrade_hdp() {
    if command -v apk >/dev/null 2>&1; then
        apk upgrade https-dns-proxy >/dev/null 2>&1
    elif command -v opkg >/dev/null 2>&1; then
        opkg upgrade https-dns-proxy >/dev/null 2>&1
    else
        return 1
    fi
    /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || return 1
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

force_readback_json() {
    detect_runtime_force_state
    detect_steer_dns_runtime >/dev/null 2>&1 || true

    _fr_force="$(cfg_get FORCE_DOH)"; [ -n "$_fr_force" ] || _fr_force=0
    _fr_external="${FORCE_RUNTIME_EXTERNAL:-0}"
    _fr_owner=none
    _fr_status=off
    _fr_source=none

    if [ "$_fr_external" = 1 ]; then
        _fr_owner=external
        _fr_status=external
        _fr_source="${FORCE_RUNTIME_SOURCE:-внешний сервис}"
    elif [ "${STEER_DNS_ACTIVE:-0}" = 1 ]; then
        _fr_owner=steer
        _fr_source=Steer
        if [ "$_fr_force" = 1 ]; then
            _fr_status=steer
        else
            _fr_status=other
        fi
    elif [ "${FORCE_RUNTIME_ACTIVE:-0}" = 1 ]; then
        _fr_owner=manager
        _fr_status=manager
        _fr_source=DNS Manager
    fi

    _fr_manager=0
    [ "$_fr_owner" = manager ] && _fr_manager=1
    _fr_state=0
    [ "$_fr_manager" = 1 ] && _fr_state=1
    [ "$_fr_owner" = steer ] && [ "$_fr_force" = 1 ] && _fr_state=1
    [ "$_fr_owner" = steer ] && [ "$_fr_force" != 1 ] && _fr_state=2
    [ "$_fr_external" = 1 ] && _fr_state=2

    printf '{"ok":true,"force":'; json_quote "$_fr_force"
    printf ',"force_external":'; json_quote "$_fr_external"
    printf ',"force_owner":'; json_quote "$_fr_owner"
    printf ',"force_manager":%s,"force_both":0' "$_fr_manager"
    printf ',"force_source":'; json_quote "$_fr_source"
    printf ',"force_targets":'; json_quote "${FORCE_RUNTIME_TARGETS:-}"
    printf ',"force_state":%s' "$_fr_state"
    printf ',"force_status":'; json_quote "$_fr_status"
    printf ',"steer_dns_active":%s' "${STEER_DNS_ACTIVE:-0}"
    printf ',"force_notrack":'; json_quote "$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null || true)"
    printf ',"force_update":'; json_quote "$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null || true)"
    printf ',"force_family":'; json_quote "$(uci -q get https-dns-proxy.config.force_ip_family 2>/dev/null || true)"
    printf ',"force_ports":'; json_quote "$(uci -q get https-dns-proxy.config.force_dns_port 2>/dev/null || true)"
    printf ',"force_src":'; json_quote "$(uci -q get https-dns-proxy.config.force_dns_src_interface 2>/dev/null || true)"
    printf ',"force_canary_icloud":'; json_quote "$(uci -q get https-dns-proxy.config.canary_domains_icloud 2>/dev/null || true)"
    printf ',"force_canary_mozilla":'; json_quote "$(uci -q get https-dns-proxy.config.canary_domains_mozilla 2>/dev/null || true)"
    printf ',"force_procd_trigger_wan6":'; json_quote "$(uci -q get https-dns-proxy.config.procd_trigger_wan6 2>/dev/null || true)"
    printf ',"force_heartbeat_domain":'; json_quote "$(uci -q get https-dns-proxy.config.heartbeat_domain 2>/dev/null || true)"
    printf ',"force_heartbeat_sleep":'; json_quote "$(uci -q get https-dns-proxy.config.heartbeat_sleep_timeout 2>/dev/null || true)"
    printf ',"force_heartbeat_wait":'; json_quote "$(uci -q get https-dns-proxy.config.heartbeat_wait_timeout 2>/dev/null || true)"
    printf ',"force_user":'; json_quote "$(uci -q get https-dns-proxy.config.user 2>/dev/null || true)"
    printf ',"force_group":'; json_quote "$(uci -q get https-dns-proxy.config.group 2>/dev/null || true)"
    printf ',"force_listen":'; json_quote "$(uci -q get https-dns-proxy.config.listen_addr 2>/dev/null || true)"
    printf ',"force_consistent":%s' "$([ "$_fr_manager" = 1 ] && printf 1 || [ "$_fr_owner" = steer ] && [ "$_fr_force" = 1 ] && printf 1 || printf 0)"
    printf ',"force_owner_label":'; case "$_fr_owner" in manager) json_quote "DNS Manager";; steer) json_quote "Steer";; external) json_quote "внешний";; *) json_quote "нет";; esac
    printf ',"zapret_running":%s}\n' "$(runtime_zapret_running && printf 1 || printf 0)"
}


device_model() {
    _model="$(cat /tmp/sysinfo/model 2>/dev/null | tr -d "\000\r\n" || true)"
    [ -n "$_model" ] || _model="$(cat /sys/firmware/devicetree/base/model 2>/dev/null | tr -d "\000\r\n" || true)"
    [ -n "$_model" ] || _model="$(cat /proc/device-tree/model 2>/dev/null | tr -d "\000\r\n" || true)"
    [ -n "$_model" ] || _model="неизвестно"
    printf "%s" "$_model"
}

openwrt_release() { sed -n "s/^DISTRIB_RELEASE='\([^']*\)'.*/\1/p" /etc/openwrt_release 2>/dev/null | head -n1; }

cpu_stat() {
    awk '/^cpu / { t=0; for(i=2;i<=NF;i++) t+=$i; print t, $5+$6; exit }' /proc/stat 2>/dev/null
}
cpu_load_percent() {
    local f="$RUNTIME_DIR/cpu.stat" now prev t1 i1 t2 i2
    [ -d "$RUNTIME_DIR" ] || mkdir -p "$RUNTIME_DIR" 2>/dev/null || return 0
    now="$(cpu_stat)"
    [ -n "$now" ] || return 0
    if [ -s "$f" ]; then
        prev="$(cat "$f" 2>/dev/null || true)"
    else
        printf '%s\n' "$now" > "$f" 2>/dev/null || true
        printf '0'
        printf '%s\n' '0' > "$f.pct" 2>/dev/null || true
        return 0
    fi
    set -- $prev $now
    t1=$1; i1=$2; t2=$3; i2=$4
    if [ -z "$t1" ] || [ -z "$i1" ] || [ -z "$t2" ] || [ -z "$i2" ]; then
        printf '0'
        return 0
    fi
    if [ $((t2 - t1)) -lt 50 ] 2>/dev/null && [ -s "$f.pct" ]; then
        cat "$f.pct" 2>/dev/null
        return 0
    fi
    [ "$t2" -gt "$t1" ] 2>/dev/null || { printf '0'; return 0; }
    printf '%s\n' "$now" > "$f" 2>/dev/null || true
    printf '%s\n' "$(( (100 * ((t2-t1) - (i2-i1)) + (t2-t1)/2) / (t2-t1) ))" | tee "$f.pct"
}

runtime_uptime_seconds() {
    _u="$(awk 'NR==1 {v=int($1); if(v>=0) print v; exit}' /proc/uptime 2>/dev/null || true)"
    case "$_u" in ''|*[!0-9]*) return 1;; esac
    printf '%s' "$_u"
}

runtime_json() {
    _uptime="$(runtime_uptime_seconds 2>/dev/null || true)"
    [ -n "$_uptime" ] || _uptime=0
    _load="$(cpu_load_percent)"
    _mem_t="$(awk '/MemTotal:/ {print $2;exit}' /proc/meminfo 2>/dev/null || true)"; [ -n "$_mem_t" ] || _mem_t=0
    _mem_a="$(awk '/MemAvailable:/ {print $2;exit}' /proc/meminfo 2>/dev/null || true)"; [ -n "$_mem_a" ] || _mem_a=0
    printf '{"ok":true,"uptime":'; json_quote "$_uptime"
    printf ',"cpu_load":%s,"memory_total_kb":%s,"memory_available_kb":%s}' "$_load" "$_mem_t" "$_mem_a"
}
detect_steer_dns_runtime() {
    STEER_DNS_ACTIVE=0
    STEER_DNS_SOURCE="none"
    # Steer is optional. Absence of Steer is the normal standalone mode.
    if [ -x /etc/init.d/steer ] && /etc/init.d/steer running >/dev/null 2>&1; then
        :
    elif ps w 2>/dev/null | grep -Eq '[s]teer(d)?([[:space:]]|/)' ; then
        :
    else
        return 0
    fi
    _lan_dev="$(uci -q get network.lan.device 2>/dev/null)"
    _lan_if="$(uci -q get network.lan.ifname 2>/dev/null)"
    if command -v nft >/dev/null 2>&1 && nft -a list chain inet steer prerouting_dns 2>/dev/null |
        awk '/dport[[:space:]]+53/ && /redirect[[:space:]]+to[[:space:]]*:5300([[:space:]]|$)/ { found=1 } END { exit(found ? 0 : 1) }'; then
        STEER_DNS_ACTIVE=1
        STEER_DNS_SOURCE="Steer"
        return 0
    fi
    if command -v nft >/dev/null 2>&1 && nft -a list ruleset 2>/dev/null | awk -v ld="$_lan_dev" -v li="$_lan_if" '
        /dport[[:space:]]+53/ && /5300/ && /(redirect[[:space:]]+to|dnat[[:space:]]+to)/ {
            ok=0
            if ($0 ~ /iifname[[:space:]]+"br-lan"/) ok=1
            if (ld != "" && index($0,"iifname \"" ld "\"")>0) ok=1
            if (li != "" && index($0,"iifname \"" li "\"")>0) ok=1
            if (ok) found=1
        }
        END { exit(found ? 0 : 1) }
    ' >/dev/null 2>&1; then
        STEER_DNS_ACTIVE=1
        STEER_DNS_SOURCE="Steer"
    elif command -v iptables >/dev/null 2>&1; then
        _rules=""
        if command -v iptables-save >/dev/null 2>&1; then
            _rules="$(iptables-save -t nat 2>/dev/null || true)"
        else
            _rules="$(iptables -t nat -S PREROUTING 2>/dev/null || true)"
        fi
        if [ -n "$_rules" ] && printf '%s\n' "$_rules" | awk -v ld="$_lan_dev" -v li="$_lan_if" '
            function has_input_dev(    i) {
                for (i=1; i<NF; i++) if ($i=="-i" && $(i+1)!="") {
                    if ($(i+1)=="br-lan" || (ld!="" && $(i+1)==ld) || (li!="" && $(i+1)==li)) return 1
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
    fi
    return 0
}
steer_service_present() {
    [ -x /etc/init.d/steer ]
}
steer_service_running() {
    [ -x /etc/init.d/steer ] && /etc/init.d/steer running >/dev/null 2>&1
}


page_header_json() {
    _ph_meta="$STATE_DIR/dns-test-results.meta"
    [ -r "$_ph_meta" ] || _ph_meta="$PERSIST_STATE_DIR/dns-test-results.meta"
    _ph_last="$(sed -n 's/^timestamp=//p' "$_ph_meta" 2>/dev/null | head -n1)"
    _ph_scope="$(sed -n 's/^test_scope=//p' "$_ph_meta" 2>/dev/null | head -n1)"
    [ -n "$_ph_scope" ] || _ph_scope=all
    _ph_lv="$(read_installed_luci_version)"
    printf ',"luci_version":'; json_quote "$_ph_lv"
    printf ',"last_full_test":'; json_quote "$_ph_last"
    printf ',"last_full_test_scope":'; json_quote "$_ph_scope"
    _ph_watchdog_file="$STATE_DIR/dns-watchdog-check-results.conf"
    _ph_watchdog_at="$(sed -n 's/^timestamp=//p' "$_ph_watchdog_file" 2>/dev/null | head -n1)"
    _ph_watchdog_cat="$(sed -n 's/^category=//p' "$_ph_watchdog_file" 2>/dev/null | head -n1)"
    case "$_ph_watchdog_at" in ''|*[!0-9]*) _ph_watchdog_at=0;; esac
    [ -n "$_ph_watchdog_cat" ] || _ph_watchdog_cat=unknown
    printf ',"watchdog_last_check":%s,"watchdog_last_category":' "$_ph_watchdog_at"; json_quote "$_ph_watchdog_cat"
    _ph_dnscrypt_status="$(awk -F'|' '$1=="record" && $3=="dnscrypt_pool" {print $6; exit}' "$_ph_watchdog_file" 2>/dev/null)"
    case "$_ph_dnscrypt_status" in OK|FAIL) ;; *) _ph_dnscrypt_status=unknown;; esac
    printf ',"watchdog_dnscrypt_status":'; json_quote "$_ph_dnscrypt_status"
    _ph_regional="$(cfg_get REGIONAL_MODE)"
    case "$_ph_regional" in doh|legacy|yandex|isp) ;; *) [ -n "$(cfg_get SLOT_RU)" ] && _ph_regional=legacy || _ph_regional=doh;; esac
    printf ',"regional_mode":'; json_quote "$_ph_regional"
    printf ',"regional_isp_ips":'; json_quote "$(cfg_get REGIONAL_ISP_IPS)"
    printf ',"bootstrap_selected":'; json_quote "$(cfg_get BOOTSTRAP_DNS_SELECTED)"
    printf ',"bootstrap_preset_ids":'; json_quote "$(cfg_get BOOTSTRAP_PRESET_IDS)"
    printf ',"bootstrap_extra":'; json_quote "$(cfg_get BOOTSTRAP_EXTRA)"
    printf ',"bootstrap_metadata_snapshot":'; json_quote "$(cfg_get BOOTSTRAP_METADATA_SNAPSHOT)"
}

lan_devices_json() {
    _ld_tmp="$(mktemp /tmp/dns-manager-lan-devices.XXXXXX 2>/dev/null)" || {
        printf '{"ok":false,"error":"Не удалось создать временный файл","devices":[]}\n'
        return 0
    }
    _ld_merged="$_ld_tmp.merged"
    : > "$_ld_tmp"

    # Active DHCP leases known to dnsmasq.
    if [ -r /tmp/dhcp.leases ]; then
        awk -F '[[:space:]]+' '
            NF >= 3 &&
            $2 ~ /^[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]$/ &&
            $3 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {
                name = (NF >= 4 && $4 != "*" ? $4 : "")
                gsub(/[|\t\r\n]/, " ", name)
                printf "%s|%s|%s|DHCP|1\n", tolower($2), $3, name
            }
        ' /tmp/dhcp.leases >> "$_ld_tmp" 2>/dev/null || true
    fi

    # IPv4 neighbours on the LAN bridge, including recent statically addressed clients.
    _ld_dev="$(uci -q get network.lan.device 2>/dev/null || true)"
    [ -n "$_ld_dev" ] || _ld_dev=br-lan
    if [ -r /proc/net/arp ]; then
        awk -v dev="$_ld_dev" '
            NR > 1 && $3 == "0x2" &&
            $4 ~ /^[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]$/ &&
            ($6 == "br-lan" || $6 == dev) {
                printf "%s|%s||ARP|1\n", tolower($4), $1
            }
        ' /proc/net/arp >> "$_ld_tmp" 2>/dev/null || true
    fi

    # IPv6 neighbours are discovered from the Linux NDP table when iproute2 is available.
    if command -v ip >/dev/null 2>&1; then
        ip -6 neigh show dev "$_ld_dev" 2>/dev/null | awk '
            $1 ~ /:/ && $0 !~ /[[:space:]](FAILED|INCOMPLETE)([[:space:]]|$)/ {
                mac = ""
                for (i = 2; i < NF; i++) if ($i == "lladdr") mac = tolower($(i + 1))
                if (mac ~ /^[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]$/)
                    printf "%s|%s||NDP|1\n", mac, $1
            }
        ' >> "$_ld_tmp" 2>/dev/null || true
    fi

    # Static DHCP host entries remain visible while their devices are offline.
    _ld_hosts="$(uci -q show dhcp 2>/dev/null | sed -n 's/^dhcp\.\([^.=]*\)=host$/\1/p')"
    for _ld_sec in $_ld_hosts; do
        _ld_macs="$(uci -q get "dhcp.$_ld_sec.mac" 2>/dev/null || true)"
        _ld_ip="$(uci -q get "dhcp.$_ld_sec.ip" 2>/dev/null || true)"
        _ld_name="$(uci -q get "dhcp.$_ld_sec.name" 2>/dev/null || true)"
        case "$_ld_ip" in ignore|*:* ) _ld_ip="" ;; esac
        case "$_ld_ip" in *[!0-9.]* ) _ld_ip="" ;; esac
        _ld_name="$(printf '%s' "$_ld_name" | tr '\011\012\015|' '    ')"
        for _ld_mac in $_ld_macs; do
            printf '%s|%s|%s|static DHCP|0\n' "$(printf '%s' "$_ld_mac" | tr 'A-F' 'a-f')" "$_ld_ip" "$_ld_name" >> "$_ld_tmp"
        done
    done

    # Keep saved individual bindings visible after devices go offline.
    if [ -r /etc/dns-manager/config/device-dns.conf ]; then
        awk -F '|' '
            NF >= 2 && $2 ~ /^[1-6](,[1-6])*$/ &&
            $1 ~ /^[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]$/ {
                printf "%s|||ASSIGN|0|%s\n", tolower($1), $2
            }
        ' /etc/dns-manager/config/device-dns.conf >> "$_ld_tmp" 2>/dev/null || true
    fi

    # Merge records by MAC; quote every value via json_quote after aggregation.
    awk -F '|' '
        function ismac(m) {
            return m ~ /^[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]$/
        }
        {
            mac = tolower($1)
            if (!ismac(mac)) next
            if (!(mac in seen)) { seen[mac] = 1; order[++n] = mac }
            if ($2 != "" && $2 != "ignore" && ip[mac] == "") ip[mac] = $2
            if ($3 != "" && $3 != "*" && name[mac] == "") name[mac] = $3
            if ($4 == "DHCP") source[mac] = "DHCP"
            else if ($4 == "ARP" && source[mac] != "DHCP") source[mac] = "ARP"
            else if ($4 == "NDP" && source[mac] != "DHCP" && source[mac] != "ARP") source[mac] = "NDP"
            else if ($4 == "static DHCP" && source[mac] == "") source[mac] = "static DHCP"
            else if ($4 == "ASSIGN" && source[mac] == "") source[mac] = "ASSIGN"
            if ($6 != "") assigned[mac] = $6
            if ($5 == "1") online[mac] = 1
        }
        END {
            for (i = 1; i <= n; i++) {
                mac = order[i]
                printf "%s|%s|%s|%s|%s|%s\n", mac, ip[mac], name[mac], source[mac], (online[mac] ? 1 : 0), assigned[mac]
            }
        }
    ' "$_ld_tmp" | sort -t '|' -k1,1 > "$_ld_merged"

    printf '{"ok":true,"devices":['
    _ld_sep=""
    while IFS='|' read -r _ld_mac _ld_ip _ld_name _ld_source _ld_online _ld_assigned_slots; do
        [ -n "$_ld_mac" ] || continue
        printf '%s{"mac":' "$_ld_sep"; json_quote "$_ld_mac"
        printf ',"ip":'; json_quote "$_ld_ip"
        printf ',"name":'; json_quote "$_ld_name"
        printf ',"source":'; json_quote "$_ld_source"
        printf ',"online":%s' "$([ "$_ld_online" = 1 ] && printf 1 || printf 0)"
        printf ',"assigned_slots":'; json_quote "$_ld_assigned_slots"
        printf '}'
        _ld_sep=","
    done < "$_ld_merged"
    printf ']}\n'
    rm -f "$_ld_tmp" "$_ld_merged" 2>/dev/null || true
}

network_status_json() {
    _profile="$(cfg_get DNS_PROFILE)"; [ -n "$_profile" ] || _profile=none
    _mode="$(cfg_get DNS_SELECTION_MODE)"; [ -n "$_mode" ] || _mode=none
    _selection_category="$(cfg_get DNS_SELECTION_CATEGORY)"; [ -n "$_selection_category" ] || _selection_category=none
    _watchdog="$(cfg_get WATCHDOG_ENABLED)"; [ -n "$_watchdog" ] || _watchdog=0
    _watchdog_autoreplace="$(cfg_get WATCHDOG_AUTOREPLACE)"
    case "$_watchdog_autoreplace" in 0|1) ;; *) _watchdog_autoreplace="$_watchdog";; esac
    _watchdog_interval="$(cfg_get WATCHDOG_INTERVAL 2>/dev/null || printf 120)"
    case "$_watchdog_interval" in ''|*[!0-9]*) _watchdog_interval=120;; esac
    _watchdog_backend=cron
    _watchdog_threshold="$(cfg_get WATCHDOG_FAIL_THRESHOLD 2>/dev/null || printf 2)"
    case "$_watchdog_threshold" in ''|*[!0-9]*) _watchdog_threshold=2;; esac
    _watchdog_repair_cooldown="$(manager_const_num WATCHDOG_REPAIR_COOLDOWN 300)"
    _watchdog_max_restarts="$(manager_const_num WATCHDOG_MAX_RESTARTS 2)"
    _watchdog_guard_interval="$(manager_const_num WATCHDOG_GUARD_INTERVAL 3600)"
    _cache_cur="$(uci -q get dhcp.@dnsmasq[0].cachesize 2>/dev/null || true)"
    _cache_stock=""
    if [ -r /rom/etc/config/dhcp ]; then _cache_stock="$(uci -q -c /rom/etc/config get dhcp.@dnsmasq[0].cachesize 2>/dev/null || true)"; fi
    [ -n "$_cache_stock" ] || _cache_stock=1000
    if [ "$_cache_cur" = "$_cache_stock" ]; then _cache_state=0
    elif [ "$_cache_cur" = 4096 ]; then _cache_state=1
    else _cache_state=2
    fi
    _ws=0; watchdog_service_enabled && _ws=1 || true
    _wr=0; watchdog_service_running && _wr=1 || true
    _wl=0; watchdog_loop_running && _wl=1 || true
    printf '{"ok":true'; page_header_json
    printf ',"watchdog":'; json_quote "$_watchdog"
    printf ',"profile":'; json_quote "$_profile"; printf ',"profile_mode":'; json_quote "$_mode"; printf ',"selection_category":'; json_quote "$_selection_category"
    printf ',"watchdog_backend":'; json_quote "$_watchdog_backend"
    printf ',"watchdog_interval":%s,"watchdog_service":%s,"watchdog_service_enabled":%s,"watchdog_loop":%s' "$_watchdog_interval" "$_wr" "$_ws" "$_wl"
    printf ',"watchdog_autoreplace":%s' "$_watchdog_autoreplace"
    printf ',"watchdog_fail_threshold":%s,"watchdog_repair_cooldown":%s,"watchdog_max_restarts":%s,"watchdog_guard_interval":%s' "$_watchdog_threshold" "$_watchdog_repair_cooldown" "$_watchdog_max_restarts" "$_watchdog_guard_interval"
    _watchdog_check_file="$STATE_DIR/dns-watchdog-check-results.conf"
    _watchdog_last_check="$(sed -n 's/^timestamp=//p' "$_watchdog_check_file" 2>/dev/null | head -n1)"
    _watchdog_last_checked="$(sed -n 's/^checked=//p' "$_watchdog_check_file" 2>/dev/null | head -n1)"
    _watchdog_last_failed="$(sed -n 's/^failed=//p' "$_watchdog_check_file" 2>/dev/null | head -n1)"
    _watchdog_last_category="$(sed -n 's/^category=//p' "$_watchdog_check_file" 2>/dev/null | head -n1)"
    case "$_watchdog_last_check" in ''|*[!0-9]*) _watchdog_last_check=0;; esac
    case "$_watchdog_last_checked" in ''|*[!0-9]*) _watchdog_last_checked=0;; esac
    case "$_watchdog_last_failed" in ''|*[!0-9]*) _watchdog_last_failed=0;; esac
    [ -n "$_watchdog_last_category" ] || _watchdog_last_category=unknown
    printf ',"watchdog_last_check":%s,"watchdog_last_checked":%s,"watchdog_last_failed":%s' "$_watchdog_last_check" "$_watchdog_last_checked" "$_watchdog_last_failed"
    printf ',"watchdog_last_records":['
    _wd_rec_sep=""
    if [ -r "$_watchdog_check_file" ]; then
        while IFS='|' read -r _wd_rec_tag _wd_rec_slot _wd_rec_id _wd_rec_cat _wd_rec_name _wd_rec_status; do
            [ "$_wd_rec_tag" = record ] || continue
            case "$_wd_rec_status" in OK|FAIL|NO_LISTENER|SKIPPED) ;; *) _wd_rec_status=SKIPPED;; esac
            [ -n "$_wd_rec_name" ] || _wd_rec_name="DNS $_wd_rec_slot"
            printf '%s{"slot":' "$_wd_rec_sep"; json_quote "$_wd_rec_slot"
            printf ',"id":'; json_quote "$_wd_rec_id"
            printf ',"name":'; json_quote "$_wd_rec_name"
            printf ',"category":'; json_quote "$_wd_rec_cat"
            printf ',"status":'; json_quote "$_wd_rec_status"
            printf '}'
            _wd_rec_sep=","
        done < "$_watchdog_check_file"
    fi
    printf ']'
    _cache_total="${_cache_cur:-1000}"
    _cache_ttl="$(uci -q get 'dhcp.@dnsmasq[0].min_cache_ttl' 2>/dev/null || true)"
    case "$_cache_total" in ''|*[!0-9]*|0[0-9]*) _cache_total=1000;; esac
    case "$_cache_ttl" in ''|*[!0-9]*|0[0-9]*) _cache_ttl=0;; esac
    printf ',"dnsmasq_perf_state":%s,"cache_total":%s,"cache_ttl":%s}' "$_cache_state" "$_cache_total" "$_cache_ttl"
}

time_status_json() {
    _ntp_preset="$(cfg_get NTP_PRESET)"
    _ntp_servers="$(uci -q get system.ntp.server 2>/dev/null || true)"
    printf '{"ok":true'; page_header_json
    printf ',"ntp_preset":'; json_quote "$_ntp_preset"
    printf ',"ntp_servers":'; json_quote "$_ntp_servers"
    printf '}'
}

page_meta_json() {
    _age="$(cfg_get TEST_RESULTS_MAX_AGE)"
    case "$_age" in ''|*[!0-9]*) _hours=6;; *) _hours=$((_age/3600)); [ "$_hours" -ge 1 ] || _hours=1;; esac
    printf '{"ok":true,"test_age_common":%s}' "$_hours"
}

doh_status_json() {
    _force="$(cfg_get FORCE_DOH)"; [ -n "$_force" ] || _force=0
    _encrypted_dns="$(cfg_get BLOCK_EXTERNAL_DNS)"
    [ -n "$_encrypted_dns" ] || _encrypted_dns="$_force"
    case "$_encrypted_dns" in 0|1) ;; *) _encrypted_dns=0 ;; esac
    _force_cfg="$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null || true)"
    _force_notrack="$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null || true)"
    _force_state="$("$MANAGER_PATH" --force-state 2>/dev/null || true)"
    _force_manager=0
    case "$_force_state" in 1) _force_manager=1;; esac
    [ "$_force_manager" = 1 ] || { [ "$_force" = 1 ] && [ "$_force_cfg" = 1 ] && [ "$_force_notrack" = 1 ] && _force_manager=1; }

    _steer_installed=0; steer_service_present && _steer_installed=1 || true
    _steer_running=0; steer_service_running && _steer_running=1 || true
    STEER_DNS_ACTIVE=0; STEER_DNS_SOURCE=none
    detect_steer_dns_runtime >/dev/null 2>&1 || true

    _force_external=0; _force_source=none
    _fw_secs="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=redirect$/\1/p')"
    for _sec in $_fw_secs; do
        [ "$(uci -q get firewall.$_sec.disabled 2>/dev/null)" = 1 ] && continue
        runtime_lan_input_match "$(uci -q get firewall.$_sec.src 2>/dev/null || true)" || continue
        _sd="$(uci -q get firewall.$_sec.src_dport 2>/dev/null || true)"
        printf '%s\n' "$_sd" | tr ' ' '\n' | grep -qxF 53 2>/dev/null || continue
        _target="$(uci -q get firewall.$_sec.target 2>/dev/null || true)"
        case "$_target" in DNAT|dnat|REDIRECT|redirect) ;; *) continue;; esac
        _dp="$(uci -q get firewall.$_sec.dest_port 2>/dev/null || true)"
        [ -n "$_dp" ] || continue
        case "$_dp" in 53|53-53) continue;; esac
        if [ "$_force_manager" != 1 ] && { [ "$STEER_DNS_ACTIVE" != 1 ] || [ "$_dp" != 5300 ]; }; then
            _force_external=1
            _force_source="$_dp"
        fi
    done
    _zapret_running=0
    ps w 2>/dev/null | grep -Eq '[z]ms([[:space:]]|/)|[z]apret([[:space:]]|/)|[z]apret2([[:space:]]|/)|[z]aproxy2([[:space:]]|/)' && _zapret_running=1

    _force_owner=none; _force_status=off
    if [ "$_force_external" = 1 ]; then
        _force_owner=external; _force_status=external
        [ "$_zapret_running" = 1 ] && _force_source='Zapret / внешний' || _force_source='внешний сервис'
    elif [ "$STEER_DNS_ACTIVE" = 1 ]; then
        _force_owner=steer; _force_source=Steer
        [ "$_force" = 1 ] && _force_status=steer || _force_status=other
    elif [ "$_force_manager" = 1 ]; then
        _force_owner=manager; _force_status=manager; _force_source='DNS Manager'
    fi
    _force_both=0; [ "$_force_manager" = 1 ] && [ "$_force_external" = 1 ] && _force_both=1

    _listen="$(ss -lnt 2>/dev/null || netstat -lnt 2>/dev/null || true)"
    _doh_total=0; _doh_running=0; _system_dns_total=0; _doh_instances=""; _doh_first=1
    _i=0
    while uci -q get https-dns-proxy.@https-dns-proxy[$_i] >/dev/null 2>&1; do
        _p="$(uci -q get https-dns-proxy.@https-dns-proxy[$_i].listen_port 2>/dev/null || true)"
        _a="$(uci -q get https-dns-proxy.@https-dns-proxy[$_i].listen_addr 2>/dev/null || true)"
        _u="$(catalog_url_normalize "$(uci -q get https-dns-proxy.@https-dns-proxy[$_i].resolver_url 2>/dev/null || true)")"
        _n="$(uci -q get https-dns-proxy.@https-dns-proxy[$_i].name 2>/dev/null || true)"
        if [ -z "$_n" ] && [ -n "$_u" ]; then _lookup_id="$(catalog_id_for_url "$_u" 2>/dev/null || true)"; [ -n "$_lookup_id" ] && _n="$(catalog_field "$_lookup_id" 4 2>/dev/null || true)"; fi
        case "$_u" in
            https://cloudflare-dns.com/dns-query) [ "$_n" = Cloudflare ] && _n='Cloudflare (Стандарт)';;
            https://dns.google/dns-query) [ "$_n" = 'Google Public DNS' ] && _n='Google';;
        esac
        [ -n "$_n" ] || _n='Пользовательский DNS'
        _run=0
        [ -n "$_p" ] && printf '%s\n' "$_listen" | grep -qE "(^|[[:space:]])[^[:space:]]*:$_p([[:space:]]|$)" && _run=1
        [ "$_run" = 1 ] && _doh_running=$((_doh_running+1))
        _doh_total=$((_doh_total+1))
        _instance_id="$(catalog_id_for_url "$_u" 2>/dev/null || true)"
        _slot=""
        for _s in 1 2 3 4 5 6 RU; do
            _sid="$(cfg_get SLOT_"$_s")"; _sport="$(cfg_get PORT_"$_s")"
            [ -n "$_sid" ] || continue
            [ -n "$_instance_id" ] && [ "$_sid" = "$_instance_id" ] && { _slot="$_s"; break; }
            [ -n "$_sport" ] && [ "$_sport" = "$_p" ] && { _slot="$_s"; break; }
        done
        _result_id="$_instance_id"
        if [ -z "$_slot" ] && [ -n "$_u" ] && [ -n "$_p" ]; then _system_dns_total=$((_system_dns_total+1)); _result_id="$(system_result_id "$_u" "$_p" "$_i")"; fi
        _r=""; [ -n "$_result_id" ] && _r="$(result_for_id "$_result_id" 2>/dev/null || true)"
        _ms="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $4;exit}')"
        _rawst="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"
        case "$_rawst" in OK) _result_status=OK;; '') _result_status="";; *) _result_status=FAIL;; esac
        [ "$_doh_first" = 1 ] || _doh_instances="$_doh_instances,"
        _doh_first=0
        _last_check=""; [ -n "$_result_id" ] && _last_check="$(last_check_for_id "$_result_id")"
        _obj='{"index":'$(($_i+1))',"id":'$(json_quote "$_instance_id")',"name":'$(json_quote "$_n")',"port":'$(json_quote "$_p")',"listen_addr":'$(json_quote "$_a")',"url":'$(json_quote "$_u")',"running":'$_run',"slot":'$(json_quote "$_slot")',"ping":'$(json_quote "$_ms")',"status":'$(json_quote "$_result_status")',"last_check":'$(json_quote "$_last_check")'}'
        _doh_instances="$_doh_instances$_obj"
        _i=$((_i+1))
    done

    _expected=0; _match=0
    for _s in 1 2 3 4 5 6 RU; do
        _id="$(cfg_get SLOT_"$_s")"; _port="$(cfg_get PORT_"$_s")"
        [ -n "$_id" ] && [ -n "$_port" ] || continue
        _expected=$((_expected+1))
        _url="$(catalog_field "$_id" 5 2>/dev/null || true)"
        [ -n "$_url" ] || continue
        _url_cmp="$(catalog_url_normalize "$_url")"
        _j=0
        while uci -q get https-dns-proxy.@https-dns-proxy[$_j] >/dev/null 2>&1; do
            _up="$(uci -q get https-dns-proxy.@https-dns-proxy[$_j].listen_port 2>/dev/null || true)"
            _uu="$(catalog_url_normalize "$(uci -q get https-dns-proxy.@https-dns-proxy[$_j].resolver_url 2>/dev/null || true)")"
            [ "$_up" = "$_port" ] && [ "$_uu" = "$_url_cmp" ] && { _match=$((_match+1)); break; }
            _j=$((_j+1))
        done
    done
    _mode_cfg="$(cfg_get DNS_SELECTION_MODE)"; _selection_category_cfg="$(cfg_get DNS_SELECTION_CATEGORY)"
    _profile=none; _mode=none; _selection_category=none
    if [ "$_doh_total" -gt 0 ] && [ "$_doh_total" -eq "$_expected" ] && [ "$_match" -eq "$_expected" ]; then
        case "$_mode_cfg:$_selection_category_cfg" in
            quick:bypass|profile:bypass|profile:clean|profile:security|profile:privacy|profile:adblock|profile:family|profile:dnssec) _profile=hybrid; _mode="$_mode_cfg"; _selection_category="$_selection_category_cfg";;
            *) _profile=custom; _mode=manual;;
        esac
    fi

    _pjs=""; _pjr=""; _pjp=""; _pjsd=""; _pjf=""; _pjm=""
    if [ -r "$JOB_DIR/profile/state" ]; then
        _pjs="$(sed -n 's/^status=//p' "$JOB_DIR/profile/state" 2>/dev/null | tail -n1)"
        _pjr="$(sed -n 's/^result=//p' "$JOB_DIR/profile/state" 2>/dev/null | tail -n1)"
        _pjp="$(sed -n 's/^profile=//p' "$JOB_DIR/profile/state" 2>/dev/null | head -n1)"
        _pjsd="$(sed -n 's/^started=//p' "$JOB_DIR/profile/state" 2>/dev/null | head -n1)"
        _pjf="$(sed -n 's/^finished=//p' "$JOB_DIR/profile/state" 2>/dev/null | tail -n1)"
        _pjm="$(tail -n 12 "$JOB_DIR/profile/output" 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -n1 | tr '\r\t' '  ' | cut -c1-360)"
    fi

    printf '{"ok":true'; page_header_json
    if command -v https-dns-proxy >/dev/null 2>&1; then printf ',"engine_installed":1'; else printf ',"engine_installed":0'; fi
    printf ',"doh_total":%s,"doh":' "$_doh_total"; json_quote "$([ "$_doh_running" -gt 0 ] && printf yes || printf no)"
    printf ',"force":'; json_quote "$_force"
    printf ',"force_manager":%s,"force_external":%s,"force_owner":' "$_force_manager" "$_force_external"; json_quote "$_force_owner"
    printf ',"force_status":'; json_quote "$_force_status"; printf ',"force_source":'; json_quote "$_force_source"; printf ',"force_both":%s' "$_force_both"
    printf ',"steer_installed":%s,"steer_running":%s,"steer_dns_active":%s,"steer_dns_source":' "$_steer_installed" "$_steer_running" "$STEER_DNS_ACTIVE"; json_quote "$STEER_DNS_SOURCE"
    printf ',"profile":'; json_quote "$_profile"; printf ',"profile_mode":'; json_quote "$_mode"; printf ',"selection_category":'; json_quote "$_selection_category"
    printf ',"doh_instances":[%s],"slots":[' "$_doh_instances"
    _first=1
    for _s in 1 2 3 4 5 6 RU; do
        _id="$(cfg_get SLOT_"$_s")"; _cat="$(catalog_field "$_id" 2>/dev/null || true)"; _port="$(cfg_get PORT_"$_s")"; _domains="$(cfg_get "SLOT_${_s}_DOMAINS")"
        [ -n "$_cat" ] || [ -z "$_id" ] || _cat="$(cfg_get SLOT_"$_s"_CAT)"
        _name="$(catalog_field "$_id" 4 2>/dev/null || true)"; [ -n "$_name" ] || _name='Не задан'
        _r="$(result_for_id "$_id" 2>/dev/null || true)"
        _ms="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $4;exit}')"
        _rawst="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"
        _st=""; case "$_rawst" in OK) _st=OK;; RUNNING) _st=RUNNING;; '') ;; *) _st=FAIL;; esac
        [ "$_first" = 1 ] || printf ','; _first=0
        printf '{"slot":'; json_quote "$_s"; printf ',"id":'; json_quote "$_id"; printf ',"name":'; json_quote "$_name"; printf ',"category":'; json_quote "$_cat"; printf ',"port":'; json_quote "$_port"; printf ',"ping":'; json_quote "$_ms"; printf ',"status":'; json_quote "$_st"; printf ',"last_check":'; json_quote "$(last_check_for_id "$_id")"; printf ',"domains":'; json_quote "$_domains"; printf '}'
    done
    printf '],"system_dns_count":%s' "$_system_dns_total"
    printf ',"profile_job_status":'; json_quote "$_pjs"; printf ',"profile_job_result":'; json_quote "$_pjr"; printf ',"profile_job_profile":'; json_quote "$_pjp"; printf ',"profile_job_started":'; json_quote "$_pjsd"; printf ',"profile_job_finished":'; json_quote "$_pjf"; printf ',"profile_job_message":'; json_quote "$_pjm"
    printf ',"encrypted_dns":%s' "$_encrypted_dns"
    _browser_dns=0; _browser_loaded=0
    if [ -f /etc/dnsmasq.d/91-dns-manager-browser.conf ] && [ "$(sed -n '1p' /etc/dnsmasq.d/91-dns-manager-browser.conf 2>/dev/null)" = '# DNS Manager browser DNS hints' ]; then
        _browser_dns=1
        _browser_sec=''
        for _browser_candidate in $(uci show dhcp 2>/dev/null | sed -n 's/^dhcp\.\([^. =]*\)=dnsmasq$/\1/p'); do
            [ -n "$_browser_sec" ] || _browser_sec="$_browser_candidate"
            [ "$(uci -q get "dhcp.$_browser_candidate.interface" 2>/dev/null)" != lan ] || { _browser_sec="$_browser_candidate"; break; }
        done
        [ -n "$_browser_sec" ] && uci -q get "dhcp.$_browser_sec.confdir" 2>/dev/null | tr ' ' '\n' | grep -Fxq /etc/dnsmasq.d && _browser_loaded=1
    fi
    printf ',"browser_dns":%s,"browser_dns_loaded":%s' "$_browser_dns" "$_browser_loaded"
    printf '}'
}

status_json() {
    _mv="$(manager_version 2>/dev/null || true)"
    # Do not use load_config() defaults here. An untouched OpenWrt router must
    # remain "not selected", not appear as the Manager's default bypass profile.
    _profile_cfg="$(cfg_get DNS_PROFILE)"
    _mode_cfg="$(cfg_get DNS_SELECTION_MODE)"
    _selection_category_cfg="$(cfg_get DNS_SELECTION_CATEGORY)"
    _profile=none
    _mode=none
    _selection_category=none
    _watchdog="$(cfg_get WATCHDOG_ENABLED)"; [ -n "$_watchdog" ] || _watchdog=0
    _watchdog_autoreplace="$(cfg_get WATCHDOG_AUTOREPLACE)"
    case "$_watchdog_autoreplace" in 0|1) ;; *) _watchdog_autoreplace="$_watchdog";; esac
    _watchdog_interval="$(cfg_get WATCHDOG_INTERVAL 2>/dev/null || printf 120)"
    case "$_watchdog_interval" in ''|*[!0-9]*) _watchdog_interval=120;; esac
    _watchdog_backend=cron
    _watchdog_threshold="$(cfg_get WATCHDOG_FAIL_THRESHOLD 2>/dev/null || printf 2)"
    case "$_watchdog_threshold" in ''|*[!0-9]*) _watchdog_threshold=2;; esac
    _watchdog_repair_cooldown="$(manager_const_num WATCHDOG_REPAIR_COOLDOWN 300)"
    _watchdog_max_restarts="$(manager_const_num WATCHDOG_MAX_RESTARTS 2)"
    _watchdog_guard_interval="$(manager_const_num WATCHDOG_GUARD_INTERVAL 3600)"

    # DNS cache tuning changes only dnsmasq cachesize. Do not let the
    # manager config flag or unrelated dnsmasq options distort the state.
    _dnsmasq_cache_cur="$(uci -q get "dhcp.@dnsmasq[0].cachesize" 2>/dev/null || true)"
    _dnsmasq_cache_stock=""
    if [ -r /rom/etc/config/dhcp ]; then
        _dnsmasq_cache_stock="$(uci -q -c /rom/etc/config get "dhcp.@dnsmasq[0].cachesize" 2>/dev/null || true)"
    fi
    [ -n "$_dnsmasq_cache_stock" ] || _dnsmasq_cache_stock=1000
    _dnsmasq_cache_desired=4096
    if [ "$_dnsmasq_cache_cur" = "$_dnsmasq_cache_stock" ]; then
        _dnsmasq_perf_state=0
    elif [ "$_dnsmasq_cache_cur" = "$_dnsmasq_cache_desired" ]; then
        _dnsmasq_perf_state=1
    else
        _dnsmasq_perf_state=2
    fi
    _force="$(cfg_get FORCE_DOH)"; [ -n "$_force" ] || _force=0
    _force_cfg="$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null || true)"
    _force_notrack="$(uci -q get https-dns-proxy.config.notrack_dns 2>/dev/null || true)"
    # Prefer the DNS Manager authoritative check when supported by the installed manager.
    # Older Manager versions remain fully supported by the legacy exact UCI/runtime check below.
    _force_state="$("$MANAGER_PATH" --force-state 2>/dev/null || true)"
    _force_manager=0
    [ "$_force_state" = 1 ] && _force_manager=1
    [ "$_force_manager" = 1 ] || { [ "$_force" = 1 ] && [ "$_force_cfg" = 1 ] && [ "$_force_notrack" = 1 ] && _force_manager=1; }
    _steer_installed=0
    _steer_running=0
    steer_service_present && _steer_installed=1 || true
    steer_service_running && _steer_running=1 || true
    detect_steer_dns_runtime >/dev/null 2>&1 || true

    _force_external=0
    _force_targets=""
    _fw_secs="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.\([^.=]*\)=redirect$/\1/p')"
    for _sec in $_fw_secs; do
        [ "$(uci -q get "firewall.$_sec.disabled" 2>/dev/null)" = 1 ] && continue
        runtime_lan_input_match "$(uci -q get "firewall.$_sec.src" 2>/dev/null || true)" || continue
        _sd="$(uci -q get "firewall.$_sec.src_dport" 2>/dev/null || true)"
        printf '%s\n' "$_sd" | tr ' ' '\n' | grep -qxF 53 2>/dev/null || continue
        _target="$(uci -q get "firewall.$_sec.target" 2>/dev/null || true)"
        case "$_target" in DNAT|dnat|REDIRECT|redirect) ;; *) continue;; esac
        _dp="$(uci -q get "firewall.$_sec.dest_port" 2>/dev/null || true)"
        [ -n "$_dp" ] || continue
        case "$_dp" in 53|53-53) continue;; esac
        if [ "$_force_manager" != 1 ] && { [ "${STEER_DNS_ACTIVE:-0}" != 1 ] || [ "$_dp" != 5300 ]; }; then
            _force_external=1
            _force_targets="$_force_targets $_dp"
        fi
    done

    _zapret_running=0
    ps w 2>/dev/null | grep -Eq '[z]ms([[:space:]]|/)|[z]apret([[:space:]]|/)|[z]apret2([[:space:]]|/)|[z]aproxy2([[:space:]]|/)' && _zapret_running=1

    _force_owner=none
    _force_status=off
    _force_source=none
    if [ "$_force_external" = 1 ]; then
        _force_external=1
        _force_owner=external
        _force_status=external
        [ "$_zapret_running" = 1 ] && _force_source='Zapret / внешний' || _force_source='внешний сервис'
    elif [ "${STEER_DNS_ACTIVE:-0}" = 1 ]; then
        _force_owner=steer
        _force_source='Steer'
        if [ "$_force" = 1 ]; then
            _force_status=steer
        else
            _force_status=other
        fi
    elif [ "$_force_manager" = 1 ]; then
        _force_owner=manager
        _force_status=manager
        _force_source='DNS Manager'
    fi
    _force_targets="$(printf '%s\n' "$_force_targets" | tr ' ' '\n' | sed '/^$/d' | sort -n -u | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    _force_both=0
    [ "$_force_manager" = 1 ] && [ "$_force_external" = 1 ] && _force_both=1

    _doh_total=0
    _doh_running=0
    _listen="$(ss -lnt 2>/dev/null || netstat -lnt 2>/dev/null || true)"
    _i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$_i]" >/dev/null 2>&1; do
        _doh_total=$((_doh_total + 1))
        _p="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].listen_port" 2>/dev/null || true)"
        if [ -n "$_p" ] && printf '%s\n' "$_listen" | grep -qE "(^|[[:space:]])[^[:space:]]*:${_p}([[:space:]]|$)"; then _doh_running=$((_doh_running + 1)); fi
        _i=$((_i + 1))
    done
    _doh=no; [ "$_doh_running" -gt 0 ] && _doh=yes

    _expected=0
    for _s in 1 2 3 4 5 6 RU; do [ -n "$(cfg_get "SLOT_${_s}")" ] && _expected=$((_expected + 1)); done
    _match=0
    for _s in 1 2 3 4 5 6 RU; do
        _id="$(cfg_get "SLOT_${_s}")"; _port="$(cfg_get "PORT_${_s}")"
        [ -n "$_id" ] && [ -n "$_port" ] || continue
        _url="$(catalog_field "$_id" 5 2>/dev/null || true)"
        [ -n "$_url" ] || continue
        _url_cmp="$(catalog_url_normalize "$_url")"
        _j=0
        while uci -q get "https-dns-proxy.@https-dns-proxy[$_j]" >/dev/null 2>&1; do
            _up="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_j].listen_port" 2>/dev/null || true)"
            _uu="$(catalog_url_normalize "$(uci -q get "https-dns-proxy.@https-dns-proxy[$_j].resolver_url" 2>/dev/null || true)")"
            if [ "$_up" = "$_port" ] && [ "$_uu" = "$_url_cmp" ]; then _match=$((_match + 1)); break; fi
            _j=$((_j + 1))
        done
    done

    # A profile is active only when the real DoH scheme matches completely.
    if [ "$_doh_total" -gt 0 ] 2>/dev/null && [ "$_doh_total" -eq "$_expected" ] 2>/dev/null && [ "$_match" -eq "$_expected" ] 2>/dev/null; then
        # The saved profile category is the intended category. A runtime clean
        # fallback does not turn a profile into a custom selection.
        case "${_mode_cfg}:${_selection_category_cfg}" in
            quick:bypass|profile:bypass|profile:clean|profile:security|profile:privacy|profile:adblock|profile:family|profile:dnssec)
                _profile=hybrid
                _mode="${_mode_cfg}"
                _selection_category="${_selection_category_cfg}"
                ;;
            *)
                _profile=custom
                _mode=manual
                _selection_category=none
                ;;
        esac
    fi

    _ipv4=no; ip -4 route show default 2>/dev/null | grep -q . && _ipv4=yes
    _ipv6=no; ip -6 route show default 2>/dev/null | grep -q . && _ipv6=yes
    _dnsmasq=no; pgrep -x dnsmasq >/dev/null 2>&1 && _dnsmasq=yes
    _fw=unknown; command -v fw4 >/dev/null 2>&1 && _fw=fw4; command -v fw3 >/dev/null 2>&1 && [ "$_fw" = unknown ] && _fw=fw3
    _lan="$(uci -q get network.lan.ipaddr 2>/dev/null | cut -d/ -f1 | head -n1)"; [ -n "$_lan" ] || _lan=—
    _model="$(device_model)"
    _arch="$(sed -n "s/^DISTRIB_ARCH='\([^']*\)'.*/\1/p" /etc/openwrt_release 2>/dev/null | head -n1)"
    _target="$(sed -n "s/^DISTRIB_TARGET='\([^']*\)'.*/\1/p" /etc/openwrt_release 2>/dev/null | head -n1)"
    _host="$(uci -q get system.@system[0].hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || true)"
    _uptime="$(awk '{printf "%s",int($1)}' /proc/uptime 2>/dev/null || true)"
    _load="$(awk '{printf "%s",$1}' /proc/loadavg 2>/dev/null || true)"
    _mem_t="$(awk '/MemTotal:/ {print $2;exit}' /proc/meminfo 2>/dev/null || true)"; [ -n "$_mem_t" ] || _mem_t=0
    _mem_a="$(awk '/MemAvailable:/ {print $2;exit}' /proc/meminfo 2>/dev/null || true)"; [ -n "$_mem_a" ] || _mem_a=0
    _cpu_count="$(awk '/^processor[[:space:]]*:/ {n++} END {print n+0}' /proc/cpuinfo 2>/dev/null)"; case "$_cpu_count" in ''|*[!0-9]*|0) _cpu_count=1;; esac

    _last=""; _test_scope="all"; _meta="$STATE_DIR/dns-test-results.meta"; [ -r "$_meta" ] || _meta="$PERSIST_STATE_DIR/dns-test-results.meta"; _last="$(sed -n 's/^timestamp=//p' "$_meta" 2>/dev/null | head -n1)"; _test_scope="$(sed -n 's/^test_scope=//p' "$_meta" 2>/dev/null | head -n1)"; [ -n "$_test_scope" ] || _test_scope=all
    _watchdog_check_file="$STATE_DIR/dns-watchdog-check-results.conf"
    _watchdog_cron_last_run="$(jsonfilter -i /var/run/dns-manager-watchdog.json -e '@.last_check' 2>/dev/null || true)"
    case "$_watchdog_cron_last_run" in ''|*[!0-9]*) _watchdog_cron_last_run=0;; esac
    _watchdog_last_check="$(sed -n 's/^timestamp=//p' "$_watchdog_check_file" 2>/dev/null | head -n1)"
    _watchdog_last_checked="$(sed -n 's/^checked=//p' "$_watchdog_check_file" 2>/dev/null | head -n1)"
    _watchdog_last_failed="$(sed -n 's/^failed=//p' "$_watchdog_check_file" 2>/dev/null | head -n1)"
    _watchdog_last_category="$(sed -n 's/^category=//p' "$_watchdog_check_file" 2>/dev/null | head -n1)"
    case "$_watchdog_last_check" in ''|*[!0-9]*) _watchdog_last_check=0;; esac
    case "$_watchdog_last_checked" in ''|*[!0-9]*) _watchdog_last_checked=0;; esac
    case "$_watchdog_last_failed" in ''|*[!0-9]*) _watchdog_last_failed=0;; esac
    [ -n "$_watchdog_last_category" ] || _watchdog_last_category=unknown
    _cat_total="$(grep -v '^#' "$CATALOG_FILE" 2>/dev/null | grep -c '^[^|][^|]*|' 2>/dev/null || printf 0)"

    _luciv="$(read_installed_luci_version)"
    _luci_latest="$(sed -n 's/^latest=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _luci_avail="$(sed -n 's/^available=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_luci_avail" ] || _luci_avail=0
    _luci_checked_at="$(sed -n 's/^checked_at=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_luci_checked_at" ] || _luci_checked_at=0
    _luci_error="$(sed -n 's/^error=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _luci_checked=0; [ "$_luci_checked_at" -gt 0 ] 2>/dev/null && _luci_checked=1 || true
    _manager_latest="$(sed -n 's/^manager_latest=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _manager_avail="$(sed -n 's/^manager_available=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_manager_avail" ] || _manager_avail=0
    _manager_checked="$(sed -n 's/^manager_checked=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_manager_checked" ] || _manager_checked=0
    _manager_error="$(sed -n 's/^manager_error=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    [ -n "$_manager_latest" ] && [ "$_manager_latest" = "$_mv" ] && _manager_avail=0
    _catalog_latest="$(sed -n 's/^catalog_latest=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _catalog_latest_rev="$(sed -n 's/^catalog_latest_rev=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _catalog_latest_total="$(sed -n 's/^catalog_latest_total=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_catalog_latest_total" ] || _catalog_latest_total=0
    _catalog_avail="$(sed -n 's/^catalog_available=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_catalog_avail" ] || _catalog_avail=0
    _catalog_checked="$(sed -n 's/^catalog_checked=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_catalog_checked" ] || _catalog_checked=0
    _catalog_error="$(sed -n 's/^catalog_error=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    if [ "$_catalog_avail" = 1 ]; then
        _catalog_avail="$(catalog_cached_update_available "$_catalog_avail" "$_catalog_checked" "$_catalog_latest" "$_catalog_latest_rev" "$_catalog_latest_total" "$(catalog_version)" "$(catalog_revision)" "$_cat_total")"
    fi
    _engine_package=https-dns-proxy
    [ "$(uci -q get dns-manager.global.active_engine 2>/dev/null)" = dnscrypt-proxy2 ] && _engine_package=dnscrypt-proxy2
    _hdp_installed="$(package_version "$_engine_package" 2>/dev/null || true)"
    _hdp_latest="$(sed -n 's/^hdp_latest=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _hdp_avail="$(sed -n 's/^hdp_available=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_hdp_avail" ] || _hdp_avail=0
    _hdp_checked="$(sed -n 's/^hdp_checked=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"; [ -n "$_hdp_checked" ] || _hdp_checked=0
    _components_checked_at="$(sed -n 's/^components_checked_at=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    _ntp_enabled="$(uci -q get system.ntp.enabled 2>/dev/null || true)"; [ -n "$_ntp_enabled" ] || _ntp_enabled=0
    _ntp_use_dhcp="$(uci -q get system.ntp.use_dhcp 2>/dev/null || true)"; [ -n "$_ntp_use_dhcp" ] || _ntp_use_dhcp=0
    _ntp_preset="$(cfg_get NTP_PRESET)"
    _ntp_servers="$(uci -q get system.ntp.server 2>/dev/null || true)"
    _test_age_v="$(cfg_get TEST_RESULTS_MAX_AGE)"
    case "$_test_age_v" in ''|*[!0-9]*) _test_age_h=6;; *) _test_age_h=$((_test_age_v/3600)); [ "$_test_age_h" -ge 1 ] || _test_age_h=1;; esac

    # Keep the most recent background DNS operation visible after LuCI is closed and reopened.
    _last_job_id=""; _last_job_status=""; _last_job_result=""; _last_job_mode=""; _last_job_profile=""; _last_job_dns_id=""; _last_job_started=""; _last_job_finished=""; _last_job_message=""
    for _last_kind in profile test_all test_current test_one; do
        _last_state="$JOB_DIR/$_last_kind/state"
        [ -r "$_last_state" ] || continue
        _ls="$(sed -n 's/^status=//p' "$_last_state" 2>/dev/null | tail -n1)"
        _lr="$(sed -n 's/^result=//p' "$_last_state" 2>/dev/null | tail -n1)"
        _lm="$(sed -n 's/^mode=//p' "$_last_state" 2>/dev/null | head -n1)"
        _lp="$(sed -n 's/^profile=//p' "$_last_state" 2>/dev/null | head -n1)"
        _ld="$(sed -n 's/^dns_id=//p' "$_last_state" 2>/dev/null | head -n1)"
        _lst="$(sed -n 's/^started=//p' "$_last_state" 2>/dev/null | head -n1)"
        _lfi="$(sed -n 's/^finished=//p' "$_last_state" 2>/dev/null | tail -n1)"
        case "$_lst" in ''|*[!0-9]*) continue;; esac
        case "$_last_job_started" in
            ''|*[!0-9]*) _take=1;;
            *) [ "$_lst" -ge "$_last_job_started" ] 2>/dev/null && _take=1 || _take=0;;
        esac
        [ "$_take" = 1 ] || continue
        _last_job_id="$_last_kind"
        _last_job_status="$_ls"; _last_job_result="$_lr"; _last_job_mode="$_lm"
        _last_job_profile="$_lp"; _last_job_dns_id="$_ld"
        _last_job_started="$_lst"; _last_job_finished="$_lfi"
        _last_job_message="$(tail -n 12 "$JOB_DIR/$_last_kind/output" 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -n1 | tr '\r\t' '  ' | cut -c1-360)"
    done

    # Keep dedicated profile fields for the profile page; the generic fields above
    # additionally cover long-running DNS checks and single resolver tests.
    _profile_job_status=""; _profile_job_result=""; _profile_job_profile=""; _profile_job_started=""; _profile_job_finished=""; _profile_job_message=""
    if [ -r "$JOB_DIR/profile/state" ]; then
        _profile_job_status="$(sed -n 's/^status=//p' "$JOB_DIR/profile/state" 2>/dev/null | tail -n1)"
        _profile_job_result="$(sed -n 's/^result=//p' "$JOB_DIR/profile/state" 2>/dev/null | tail -n1)"
        _profile_job_profile="$(sed -n 's/^profile=//p' "$JOB_DIR/profile/state" 2>/dev/null | head -n1)"
        _profile_job_started="$(sed -n 's/^started=//p' "$JOB_DIR/profile/state" 2>/dev/null | head -n1)"
        _profile_job_finished="$(sed -n 's/^finished=//p' "$JOB_DIR/profile/state" 2>/dev/null | tail -n1)"
        _profile_job_message="$(tail -n 12 "$JOB_DIR/profile/output" 2>/dev/null | sed '/^[[:space:]]*$/d' | tail -n1 | tr '\r\t' '  ' | cut -c1-360)"
    fi

    printf '{"ok":true,"manager_version":'; json_quote "$_mv"
    _engine_running=0
    /etc/init.d/https-dns-proxy running >/dev/null 2>&1 && _engine_running=1 || true
    printf ',"engine_running":%s,"watchdog_cron_last_run":%s' "$_engine_running" "$_watchdog_cron_last_run"
    if command -v https-dns-proxy >/dev/null 2>&1; then printf ',"engine_installed":1'; else printf ',"engine_installed":0'; fi
    printf ',"luci_version":'; json_quote "$_luciv"; printf ',"luci_latest_version":'; json_quote "$_luci_latest"
    printf ',"luci_update_available":%s,"luci_update_checked":%s,"luci_update_checked_at":%s' "$_luci_avail" "$_luci_checked" "$_luci_checked_at"
    printf ',"luci_update_error":'; json_quote "$_luci_error"
    printf ',"manager_latest_version":'; json_quote "$_manager_latest"; printf ',"manager_update_available":%s,"manager_check_ok":%s' "$_manager_avail" "$_manager_checked"; printf ',"manager_update_error":'; json_quote "$_manager_error"
    printf ',"catalog_latest_version":'; json_quote "$_catalog_latest"; printf ',"catalog_latest_rev":'; json_quote "$_catalog_latest_rev"; printf ',"catalog_latest_total":%s,"catalog_update_available":%s,"catalog_check_ok":%s' "$_catalog_latest_total" "$_catalog_avail" "$_catalog_checked"; printf ',"catalog_update_error":'; json_quote "$_catalog_error"
    printf ',"model":'; json_quote "$_model"; printf ',"arch":'; json_quote "$_arch"; printf ',"target":'; json_quote "$_target"; printf ',"ipv4":'; json_quote "$_ipv4"; printf ',"ipv6":'; json_quote "$_ipv6"; printf ',"dnsmasq":'; json_quote "$_dnsmasq"; printf ',"doh":'; json_quote "$_doh"; printf ',"firewall":'; json_quote "$_fw"; printf ',"openwrt":'; json_quote "$(openwrt_release)"; printf ',"lan":'; json_quote "$_lan"
    printf ',"profile":'; json_quote "$_profile"; printf ',"profile_mode":'; json_quote "$_mode"; printf ',"selection_category":'; json_quote "$_selection_category"
    printf ',"last_job_id":'; json_quote "$_last_job_id"; printf ',"last_job_status":'; json_quote "$_last_job_status"; printf ',"last_job_result":'; json_quote "$_last_job_result"; printf ',"last_job_mode":'; json_quote "$_last_job_mode"
    printf ',"last_job_profile":'; json_quote "$_last_job_profile"; printf ',"last_job_dns_id":'; json_quote "$_last_job_dns_id"; printf ',"last_job_started":'; json_quote "$_last_job_started"; printf ',"last_job_finished":'; json_quote "$_last_job_finished"; printf ',"last_job_message":'; json_quote "$_last_job_message"
    printf ',"profile_job_status":'; json_quote "$_profile_job_status"; printf ',"profile_job_result":'; json_quote "$_profile_job_result"
    printf ',"profile_job_profile":'; json_quote "$_profile_job_profile"; printf ',"profile_job_started":'; json_quote "$_profile_job_started"; printf ',"profile_job_finished":'; json_quote "$_profile_job_finished"; printf ',"profile_job_message":'; json_quote "$_profile_job_message"
    printf ',"watchdog":'; json_quote "$_watchdog"; printf ',"watchdog_backend":'; json_quote "$_watchdog_backend"
    _watchdog_service_enabled=0; watchdog_service_enabled && _watchdog_service_enabled=1 || true
    _watchdog_service_running=0; watchdog_service_running && _watchdog_service_running=1 || true
    _watchdog_loop_running=0; watchdog_loop_running && _watchdog_loop_running=1 || true
    printf ',"watchdog_interval":%s,"watchdog_service":%s,"watchdog_service_enabled":%s,"watchdog_loop":%s,"watchdog_fail_threshold":%s,"watchdog_repair_cooldown":%s,"watchdog_max_restarts":%s,"watchdog_guard_interval":%s,"watchdog_autoreplace":%s' "$_watchdog_interval" "$_watchdog_service_running" "$_watchdog_service_enabled" "$_watchdog_loop_running" "$_watchdog_threshold" "$_watchdog_repair_cooldown" "$_watchdog_max_restarts" "$_watchdog_guard_interval" "$_watchdog_autoreplace"
     printf ',"watchdog_last_check":%s,"watchdog_last_checked":%s,"watchdog_last_failed":%s,"watchdog_last_category":' "$_watchdog_last_check" "$_watchdog_last_checked" "$_watchdog_last_failed"
     json_quote "$_watchdog_last_category"
     _watchdog_dnscrypt_status="$(awk -F'|' '$1=="record" && $3=="dnscrypt_pool" {print $6; exit}' "$_watchdog_check_file" 2>/dev/null)"
     case "$_watchdog_dnscrypt_status" in OK|FAIL) ;; *) _watchdog_dnscrypt_status=unknown;; esac
     printf ',"watchdog_dnscrypt_status":'; json_quote "$_watchdog_dnscrypt_status"
     printf ',"watchdog_last_records":['
     _wd_rec_sep=""
     if [ -r "$_watchdog_check_file" ]; then
         while IFS='|' read -r _wr_tag _wr_slot _wr_id _wr_cat _wr_name _wr_status; do
             [ "$_wr_tag" = record ] || continue
             case "$_wr_status" in OK|FAIL|NO_LISTENER|SKIPPED) ;; *) _wr_status=SKIPPED;; esac
             [ -n "$_wr_name" ] || _wr_name="DNS $_wr_slot"
             printf '%s{"slot":' "$_wd_rec_sep"; json_quote "$_wr_slot"
             printf ',"id":'; json_quote "$_wr_id"
             printf ',"name":'; json_quote "$_wr_name"
             printf ',"category":'; json_quote "$_wr_cat"
             printf ',"status":'; json_quote "$_wr_status"
             printf '}'
             _wd_rec_sep=","
         done < "$_watchdog_check_file"
     fi
     printf ']'
     printf ',"dnsmasq_perf_state":%s' "$_dnsmasq_perf_state"
     printf ',"dnsmasq_cache_size":'; json_quote "$_dnsmasq_cache_cur"
    printf ',"ntp_enabled":%s,"ntp_use_dhcp":%s' "$_ntp_enabled" "$_ntp_use_dhcp"
    printf ',"ntp_preset":'; json_quote "$_ntp_preset"
    printf ',"ntp_servers":'; json_quote "$_ntp_servers"
    printf ',"test_age_common":%s' "$_test_age_h"
    printf ',"force":'; json_quote "$_force"; printf ',"force_external":'; json_quote "$_force_external"; printf ',"force_owner":'; json_quote "$_force_owner"; printf ',"force_manager":%s,"force_both":%s' "$_force_manager" "$_force_both"
    printf ',"force_source":'; json_quote "$_force_source"; printf ',"force_targets":'; json_quote "$_force_targets"
    printf ',"force_notrack":'; json_quote "$_force_notrack"; printf ',"force_update":'; json_quote "$(uci -q get https-dns-proxy.config.dnsmasq_config_update 2>/dev/null || true)"
    printf ',"force_family":'; json_quote "$(uci -q get https-dns-proxy.config.force_ip_family 2>/dev/null || true)"; printf ',"force_ports":'; json_quote "$(uci -q get https-dns-proxy.config.force_dns_port 2>/dev/null || true)"
    printf ',"force_src":'; json_quote "$(uci -q get https-dns-proxy.config.force_dns_src_interface 2>/dev/null || true)"; printf ',"force_canary_icloud":'; json_quote "$(uci -q get https-dns-proxy.config.canary_domains_icloud 2>/dev/null || true)"
    printf ',"force_canary_mozilla":'; json_quote "$(uci -q get https-dns-proxy.config.canary_domains_mozilla 2>/dev/null || true)"; printf ',"force_procd_trigger_wan6":'; json_quote "$(uci -q get https-dns-proxy.config.procd_trigger_wan6 2>/dev/null || true)"
    printf ',"force_heartbeat_domain":'; json_quote "$(uci -q get https-dns-proxy.config.heartbeat_domain 2>/dev/null || true)"; printf ',"force_heartbeat_sleep":'; json_quote "$(uci -q get https-dns-proxy.config.heartbeat_sleep_timeout 2>/dev/null || true)"
    printf ',"force_heartbeat_wait":'; json_quote "$(uci -q get https-dns-proxy.config.heartbeat_wait_timeout 2>/dev/null || true)"; printf ',"force_user":'; json_quote "$(uci -q get https-dns-proxy.config.user 2>/dev/null || true)"
    printf ',"force_group":'; json_quote "$(uci -q get https-dns-proxy.config.group 2>/dev/null || true)"; printf ',"force_listen":'; json_quote "$(uci -q get https-dns-proxy.config.listen_addr 2>/dev/null || true)"
    printf ',"steer_installed":%s,"steer_running":%s,"steer_dns_active":%s,"steer_dns_source":' "$_steer_installed" "$_steer_running" "${STEER_DNS_ACTIVE:-0}"; json_quote "${STEER_DNS_SOURCE:-none}"
    printf ',"force_consistent":%s' "$([ "$_force_manager" = 1 ] && printf 1 || [ "$_force_owner" = steer ] && [ "$_force" = 1 ] && printf 1 || printf 0)"
    printf ',"force_state":%s' "$([ "$_force_manager" = 1 ] && printf 1 || [ "$_force_owner" = steer ] && [ "$_force" = 1 ] && printf 1 || [ "$_force_owner" = steer ] && printf 2 || [ "$_force_external" = 1 ] && printf 2 || printf 0)"
    printf ',"force_status":'; json_quote "$_force_status"
    _owner_label=нет; [ "$_force_owner" = manager ] && _owner_label='DNS Manager'; [ "$_force_owner" = steer ] && _owner_label='Steer'; [ "$_force_owner" = external ] && _owner_label=внешний
    printf ',"force_owner_label":'; json_quote "$_owner_label"; printf ',"zapret_running":%s' "$_zapret_running"
    _system_dns_total=0
    _test_lock=0
    if [ -r "$STATE_DIR/dns-test.lock/pid" ]; then _test_pid="$(cat "$STATE_DIR/dns-test.lock/pid" 2>/dev/null || true)"; case "$_test_pid" in ''|*[!0-9]*) ;; *) kill -0 "$_test_pid" 2>/dev/null && _test_lock=1;; esac; fi
    printf ',"doh_total":%s,"doh_match":%s,"configured_dns":%s' "$_doh_total" "$_match" "$_expected"
    printf ",\"test_lock\":%s" "$_test_lock"
    printf ',"last_full_test":'; json_quote "$_last"; printf ',"last_full_test_scope":'; json_quote "$_test_scope"; printf ',"components_checked_at":'; json_quote "$_components_checked_at"
    printf ',"hostname":'; json_quote "$_host"; printf ',"uptime":'; json_quote "$_uptime"; printf ',"load1":'; json_quote "$_load"
    printf ',"cpu_count":%s,"memory_total_kb":%s,"memory_available_kb":%s' "$_cpu_count" "$_mem_t" "$_mem_a"
    printf ',"catalog_total":%s,"catalog_version":' "$_cat_total"; json_quote "$(catalog_version)"; printf ',"catalog_revision":'; json_quote "$(catalog_revision)"
    printf ',"hdp_version":'; json_quote "$_hdp_installed"; printf ',"hdp_latest_version":'; json_quote "$_hdp_latest"; printf ',"hdp_update_available":%s,"hdp_check_ok":%s' "$_hdp_avail" "$_hdp_checked"
    printf ',"doh_instances":['
    _doh_first=1
    _i=0
    while uci -q get "https-dns-proxy.@https-dns-proxy[$_i]" >/dev/null 2>&1; do
        _p="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].listen_port" 2>/dev/null || true)"
        _a="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].listen_addr" 2>/dev/null || true)"
        _u="$(catalog_url_normalize "$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].resolver_url" 2>/dev/null || true)")"
        _n="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].name" 2>/dev/null || true)"
        if [ -z "$_n" ] && [ -n "$_u" ]; then
            _lookup_id="$(catalog_id_for_url "$_u" 2>/dev/null || true)"
            [ -n "$_lookup_id" ] && _n="$(catalog_field "$_lookup_id" 4 2>/dev/null || true)"
        fi
        case "$_u" in
            https://cloudflare-dns.com/dns-query) [ -n "$_n" ] && [ "$_n" = "Cloudflare" ] && _n="Cloudflare (Стандарт)" ;;
            https://dns.google/dns-query) [ -n "$_n" ] && [ "$_n" = "Google Public DNS" ] && _n="Google" ;;
        esac
        [ -n "$_n" ] || _n="Пользовательский DNS"
        _run=0
        [ -n "$_p" ] && printf '%s\n' "$_listen" | grep -qE "(^|[[:space:]])[^[:space:]]*:$_p([[:space:]]|$)" && _run=1
        _slot=""
        _instance_id="$(catalog_id_for_url "$_u" 2>/dev/null || true)"
        for _s in 1 2 3 4 5 6 RU; do
            _sid="$(cfg_get "SLOT_$_s")"; _sport="$(cfg_get "PORT_$_s")"
            [ -n "$_sid" ] || continue
            if [ -n "$_instance_id" ] && [ "$_sid" = "$_instance_id" ]; then
                _slot="$_s"
                break
            fi
            if [ -n "$_sport" ] && [ "$_sport" = "$_p" ]; then
                _slot="$_s"
                break
            fi
        done
        _r=""
        _ms=""
        _rawst=""
        _system_ts=""
        _result_id="$_instance_id"
        if [ -z "$_slot" ] && [ -n "$_u" ] && [ -n "$_p" ]; then
            _system_dns_total=$((_system_dns_total + 1))
            _result_id="$(system_result_id "$_u" "$_p" "$_i")"
        fi
        [ -n "$_result_id" ] && _r="$(result_for_id "$_result_id" 2>/dev/null || true)"
        if [ -n "$_r" ]; then
            _ms="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $4;exit}')"
            _rawst="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"
        fi
        case "$_rawst" in
            OK) _result_status=OK ;;
            '')
                _result_status=""
                ;;
            *)
                _result_status=FAIL
                ;;
        esac
        [ "$_doh_first" = 1 ] || printf ','
        _doh_first=0
        printf '{"index":%s,"id":' "$((_i + 1))"; json_quote "$_instance_id"
        printf ',"name":'; json_quote "$_n"
        printf ',"port":'; json_quote "$_p"
        printf ',"listen_addr":'; json_quote "$_a"
        printf ',"url":'; json_quote "$_u"
        printf ',"running":%s,"slot":' "$_run"; json_quote "$_slot"
        printf ',"ping":'; json_quote "$_ms"
        printf ',"status":'; json_quote "$_result_status"
        if [ -z "$_system_ts" ] && [ -n "$_result_id" ]; then _system_ts="$(last_check_for_id "$_result_id")"; fi
        printf ',"last_check":'; json_quote "$_system_ts"; printf '}'
        _i=$((_i + 1))
    done
    printf ']'
    printf ",\"system_dns_count\":%s" "$_system_dns_total"
    printf ',"slots":['
    _first=1
    for _s in 1 2 3 4 5 6 RU; do
        _id="$(cfg_get "SLOT_${_s}")"; _cat="$(catalog_field "$_id" 2>/dev/null || true)"; _port="$(cfg_get "PORT_${_s}")"; _domains="$(cfg_get "SLOT_${_s}_DOMAINS")"
        [ -n "$_cat" ] || [ -z "$_id" ] || _cat="$(cfg_get "SLOT_${_s}_CAT")"
        _name="$(catalog_field "$_id" 4 2>/dev/null || true)"; [ -n "$_name" ] || _name='Не задан'
        _r="$(result_for_id "$_id" 2>/dev/null || true)"
        _ms="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $4;exit}')"; _rawst="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"
        _st=""; case "$_rawst" in OK) _st=OK;; RUNNING) _st=RUNNING;; '') ;; *) _st=FAIL;; esac
        [ "$_first" = 1 ] || printf ','; _first=0
        printf '{"slot":'; json_quote "$_s"; printf ',"id":'; json_quote "$_id"; printf ',"name":'; json_quote "$_name"; printf ',"category":'; json_quote "$_cat"; printf ',"port":'; json_quote "$_port"; printf ',"ping":'; json_quote "$_ms"; printf ',"status":'; json_quote "$_st"; printf ',"last_check":'; json_quote "$(last_check_for_id "$_id")"; printf ',"domains":'; json_quote "$_domains"; printf '}'
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
system_instance_slot() {
    _url="$(catalog_url_normalize "$(normalize_url "$1" 2>/dev/null || true)")"; _port="$2"
    _catalog_id="$(catalog_id_for_url "$_url" 2>/dev/null || true)"
    for _s in 1 2 3 4 5 6 RU; do
        _sid="$(cfg_get "SLOT_$_s")"; _sport="$(cfg_get "PORT_$_s")"
        [ -n "$_sid" ] && [ -n "$_catalog_id" ] && [ "$_sid" = "$_catalog_id" ] && return 0
        [ -n "$_sport" ] && [ -n "$_port" ] && [ "$_sport" = "$_port" ] && return 0
    done
    return 1
}

job_execute_test_system() {
    _jid="$(new_job_id test_system)"
    printf 'status=running\nstarted=%s\nmode=system\n' "$(date +%s)" > "$JOB_DIR/$_jid/state"
    (
        exec >>"$JOB_DIR/$_jid/output" 2>&1
        if ! load_manager; then
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"; exit 1
        fi
        if ! acquire_test_lock; then
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"
            printf '%s\n' "Другая проверка DNS уже выполняется." >> "$JOB_DIR/$_jid/output"
            exit 1
        fi
        _saved_catalog="$DNS_CATALOG"; _saved_bootstrap="$BOOTSTRAP_DNS"
        _system_catalog="$TMP_ROOT/system-catalog-$$"
        _total=0; _done=0; _fail=0; _i=0
        while uci -q get "https-dns-proxy.@https-dns-proxy[$_i]" >/dev/null 2>&1; do
            _u="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].resolver_url" 2>/dev/null || true)"
            _p="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].listen_port" 2>/dev/null || true)"
            if [ -n "$_u" ] && [ -n "$_p" ] && ! system_instance_slot "$_u" "$_p"; then
                _total=$((_total+1))
                _sid="$(system_result_id "$_u" "$_p" "$_i")"
                _norm_url="$(normalize_url "$_u" 2>/dev/null || true)"
                printf '%s|system|System DNS|System DNS|%s\n' "$_sid" "$_norm_url" > "$_system_catalog"
                DNS_CATALOG="$_system_catalog"; BOOTSTRAP_DNS="$(uci -q get "https-dns-proxy.@https-dns-proxy[$_i].bootstrap_dns" 2>/dev/null || true)"
                rm -f "$TMP_DIR/t.$_sid" 2>/dev/null || true
                test_one_dns "$_sid" >/dev/null 2>&1 || true
                _rf="$TMP_DIR/t.$_sid"
                if [ -s "$_rf" ]; then
                    _line="$(head -n1 "$_rf")"
                    _ms="$(printf '%s' "$_line" | awk -F'|' 'NF>=5 {print $4;exit}')"
                    _st="$(printf '%s' "$_line" | awk -F'|' 'NF>=5 {print $5;exit}')"
                    case "$_ms" in ''|*[!0-9]*) _ms=-1;; esac
                else
                    _ms=-1
                    _st="TEST_NO_RESULT"
                fi

                if [ -n "$_st" ] && [ "$_st" != "TEST_NO_RESULT" ]; then
                    job_write "$_jid" ping "$_ms"
                    job_write "$_jid" dns_status "$_st"
                    if ! commit_single_test_result "$_sid" "$_rf"; then
                        job_write "$_jid" status failed
                        job_write "$_jid" result fail
                        job_write "$_jid" finished "$(date +%s)"
                        job_write "$_jid" error "Не удалось сохранить результат проверки системного DNS."
                        rm -f "$_rf" "$_system_catalog" 2>/dev/null || true
                        DNS_CATALOG="$_saved_catalog"; BOOTSTRAP_DNS="$_saved_bootstrap"
                        release_test_lock
                        exit 1
                    fi
                    set_check_stamp "$_sid" "$(date +%s)" || true
                    [ "$_st" = OK ] || _fail=$((_fail+1))
                else
                    _fail=$((_fail+1))
                fi

                rm -f "$_rf" 2>/dev/null || true
                _done=$((_done+1))
                job_write "$_jid" progress_done "$_done"
                job_write "$_jid" progress_total "$_total"
                job_write "$_jid" progress_fail "$_fail"
            fi
            _i=$((_i+1))
        done
        DNS_CATALOG="$_saved_catalog"; BOOTSTRAP_DNS="$_saved_bootstrap"
        rm -f "$_system_catalog" 2>/dev/null || true
        release_test_lock
        _now="$(date +%s)"
        if [ "$_total" -gt 0 ] && [ "$_fail" -eq 0 ]; then
            job_write "$_jid" status done; job_write "$_jid" result ok
        elif [ "$_total" -eq 0 ]; then
            job_write "$_jid" status failed; job_write "$_jid" result fail
            printf '%s\n' "Системных DNS без привязки к слотам не найдено." >> "$JOB_DIR/$_jid/output"
        else
            job_write "$_jid" status done; job_write "$_jid" result fail
        fi
        job_write "$_jid" finished "$_now"
    ) &
    _job_pid=$!; job_record_pid "$_jid" "$_job_pid"
    printf '{"ok":true,"job":'; json_quote "$_jid"; printf '}'
}

watchdog_apply_values() {
    _ni="$1"; _nt="$2"; _nrc="$3"; _nms="$4"; _ngi="$5"

    case "$_ni" in ''|*[!0-9]*) json_error "Интервал проверки: значение должно быть целым числом"; return 1;; esac
    case "$_nt" in ''|*[!0-9]*) json_error "Порог сбоя: значение должно быть целым числом"; return 1;; esac
    case "$_nrc" in ''|*[!0-9]*) json_error "Пауза между заменами: значение должно быть целым числом"; return 1;; esac
    case "$_nms" in ''|*[!0-9]*) json_error "Перезапуски DNS: значение должно быть целым числом"; return 1;; esac
    case "$_ngi" in ''|*[!0-9]*) json_error "Полная сверка: значение должно быть целым числом"; return 1;; esac

    [ "$_ni" -ge 60 ] 2>/dev/null && [ "$_ni" -le 3600 ] 2>/dev/null || { json_error "Интервал проверки должен быть от 60 до 3600 с"; return 1; }
    [ "$_nt" -ge 1 ] 2>/dev/null && [ "$_nt" -le 5 ] 2>/dev/null || { json_error "Порог сбоя должен быть от 1 до 5 проверок"; return 1; }
    [ "$_nrc" -ge 300 ] 2>/dev/null && [ "$_nrc" -le 7200 ] 2>/dev/null || { json_error "Пауза между заменами должна быть от 300 до 7200 с"; return 1; }
    [ "$_nms" -ge 1 ] 2>/dev/null && [ "$_nms" -le 5 ] 2>/dev/null || { json_error "Перезапусков DNS должно быть от 1 до 5"; return 1; }
    [ "$_ngi" -ge 900 ] 2>/dev/null && [ "$_ngi" -le 10800 ] 2>/dev/null || { json_error "Полная сверка должна быть от 900 до 10800 с"; return 1; }

    _old_interval="$WATCHDOG_INTERVAL"
    _old_threshold="$WATCHDOG_FAIL_THRESHOLD"
    _old_repair_cooldown="$WATCHDOG_REPAIR_COOLDOWN"
    _old_max_restarts="$WATCHDOG_MAX_RESTARTS"
    _old_guard_interval="$WATCHDOG_GUARD_INTERVAL"

    if [ "$_old_interval" = "$_ni" ] &&
       [ "$_old_threshold" = "$_nt" ] &&
       [ "$_old_repair_cooldown" = "$_nrc" ] &&
       [ "$_old_max_restarts" = "$_nms" ] &&
       [ "$_old_guard_interval" = "$_ngi" ]; then
        json_ok
        return 0
    fi

    _old_service_enabled=0; watchdog_service_enabled && _old_service_enabled=1 || true
    _old_service_running=0; watchdog_service_running && _old_service_running=1 || true

    if [ -x /etc/init.d/dns-watchdog ]; then
        watchdog_service_stop_disable >/dev/null 2>&1 || {
            json_error "Не удалось безопасно остановить watchdog; настройки не изменены"
            return 1
        }
    fi

    WATCHDOG_INTERVAL="$_ni"
    WATCHDOG_FAIL_THRESHOLD="$_nt"
    WATCHDOG_REPAIR_COOLDOWN="$_nrc"
    WATCHDOG_MAX_RESTARTS="$_nms"
    WATCHDOG_GUARD_INTERVAL="$_ngi"

    watchdog_restore_values() {
        WATCHDOG_INTERVAL="$_old_interval"
        WATCHDOG_FAIL_THRESHOLD="$_old_threshold"
        WATCHDOG_REPAIR_COOLDOWN="$_old_repair_cooldown"
        WATCHDOG_MAX_RESTARTS="$_old_max_restarts"
        WATCHDOG_GUARD_INTERVAL="$_old_guard_interval"
        save_config >/dev/null 2>&1 || true
        watchdog_restore_service_state "$_old_service_enabled" "$_old_service_running" >/dev/null 2>&1 || true
    }

    if ! save_config >/dev/null 2>&1; then
        watchdog_restore_values
        json_error "Не удалось сохранить настройки watchdog; прежние значения восстановлены"
        return 1
    fi

    [ "$(cfg_get WATCHDOG_INTERVAL)" = "$_ni" ] &&
    [ "$(cfg_get WATCHDOG_FAIL_THRESHOLD)" = "$_nt" ] &&
    [ "$(cfg_get WATCHDOG_REPAIR_COOLDOWN)" = "$_nrc" ] &&
    [ "$(cfg_get WATCHDOG_MAX_RESTARTS)" = "$_nms" ] &&
    [ "$(cfg_get WATCHDOG_GUARD_INTERVAL)" = "$_ngi" ] || {
        watchdog_restore_values
        json_error "Настройки watchdog не прошли проверку после сохранения; прежние значения восстановлены"
        return 1
    }

    if [ "${WATCHDOG_ENABLED:-0}" = 1 ]; then
        if ! watchdog_service_start_enable >/dev/null 2>&1; then
            watchdog_restore_values
            json_error "Watchdog не удалось перезапустить; прежние настройки восстановлены"
            return 1
        fi
    fi

    if ! watchdog_cron_remove_owned_block >/dev/null 2>&1; then
        [ -x /etc/init.d/dns-watchdog ] && watchdog_service_stop_disable >/dev/null 2>&1 || true
        watchdog_restore_values
        json_error "Не удалось убрать старый manager-owned cron watchdog; изменение отменено"
        return 1
    fi

    json_ok
    return 0
}

watchdog_apply_single() {
    _name="$1"; _value="$2"
    case "$_name" in
        interval) _key=WATCHDOG_INTERVAL ;;
        threshold) _key=WATCHDOG_FAIL_THRESHOLD ;;
        repair_cooldown) _key=WATCHDOG_REPAIR_COOLDOWN ;;
        max_restarts) _key=WATCHDOG_MAX_RESTARTS ;;
        guard_interval) _key=WATCHDOG_GUARD_INTERVAL ;;
        *) json_error "Недопустимый параметр watchdog"; return 1 ;;
    esac
    case "$_value" in ''|*[!0-9]*) json_error "Значение watchdog должно быть целым числом"; return 1;; esac

    load_manager || { json_error "DNS Manager недоступен"; return 1; }
    _interval="$WATCHDOG_INTERVAL"
    _threshold="$WATCHDOG_FAIL_THRESHOLD"
    _repair_cooldown="$WATCHDOG_REPAIR_COOLDOWN"
    _max_restarts="$WATCHDOG_MAX_RESTARTS"
    _guard_interval="$WATCHDOG_GUARD_INTERVAL"
    case "$_key" in
        WATCHDOG_INTERVAL) _min=60; _max=3600; _interval="$_value" ;;
        WATCHDOG_FAIL_THRESHOLD) _min=1; _max=5; _threshold="$_value" ;;
        WATCHDOG_REPAIR_COOLDOWN) _min=300; _max=7200; _repair_cooldown="$_value" ;;
        WATCHDOG_MAX_RESTARTS) _min=1; _max=5; _max_restarts="$_value" ;;
        WATCHDOG_GUARD_INTERVAL) _min=900; _max=10800; _guard_interval="$_value" ;;
    esac
    [ "$_value" -ge "$_min" ] 2>/dev/null && [ "$_value" -le "$_max" ] 2>/dev/null || {
        json_error "Значение вне допустимого диапазона ($_min–$_max)"
        return 1
    }
    watchdog_apply_values "$_interval" "$_threshold" "$_repair_cooldown" "$_max_restarts" "$_guard_interval"
}

watchdog_apply_batch() {
    _interval="$(jget interval)"
    _threshold="$(jget threshold)"
    _repair_cooldown="$(jget repair_cooldown)"
    _max_restarts="$(jget max_restarts)"
    _guard_interval="$(jget guard_interval)"
    load_manager || { json_error "DNS Manager недоступен"; return 1; }
    watchdog_apply_values "$_interval" "$_threshold" "$_repair_cooldown" "$_max_restarts" "$_guard_interval"
}


set_check_stamp() {
    _id="$1"; _ts="$2"; _previous_stamp=""
    case "$_id" in ''|*[!A-Za-z0-9_-]*) return 1;; esac
    case "$_ts" in ''|*[!0-9]*) return 1;; esac
    if [ -r "$CHECK_DIR/$_id" ]; then IFS= read -r _previous_stamp < "$CHECK_DIR/$_id" || true; fi
    case "$_previous_stamp" in ''|*[!0-9]*) _previous_stamp=0;; esac
    [ "$_previous_stamp" -le "$_ts" ] 2>/dev/null || return 0
    printf '%s\n' "$_ts" > "$CHECK_DIR/$_id" 2>/dev/null
}
commit_single_test_result() {
    _id="$1"
    _result_file="$2"
    [ -n "$_id" ] && [ -s "$_result_file" ] || return 1

    # Accept exactly one fresh result line for this DNS. A failed/incomplete
    # write must never be reported as a successful test, otherwise the next
    # LuCI page load falls back to the previous common-test result.
    _line="$(awk -F"|" -v id="$_id" '$1==id && NF>=5 {print;exit}' "$_result_file" 2>/dev/null || true)"
    [ -n "$_line" ] || return 1

    _tmp="$(mktemp "$STATE_DIR/dns-test-results.single.XXXXXX" 2>/dev/null || true)"
    [ -n "$_tmp" ] || return 1

    if [ -s "$TEST_RESULTS" ]; then
        awk -F"|" -v id="$_id" '$1!=id {print}' "$TEST_RESULTS" > "$_tmp" 2>/dev/null || {
            rm -f "$_tmp" 2>/dev/null || true
            return 1
        }
    fi
    printf '%s\n' "$_line" >> "$_tmp" || {
        rm -f "$_tmp" 2>/dev/null || true
        return 1
    }

    # Atomic replacement on the same filesystem. Do not hide a failure.
    mv -f "$_tmp" "$TEST_RESULTS" 2>/dev/null || {
        rm -f "$_tmp" 2>/dev/null || true
        return 1
    }

    # Read back the exact ID. This is the result that future status/catalog
    # requests will consume after LuCI is closed and opened again.
    _saved_line="$(awk -F"|" -v id="$_id" '$1==id && NF>=5 {print;exit}' "$TEST_RESULTS" 2>/dev/null || true)"
    [ "$_saved_line" = "$_line" ] || return 1
    return 0
}
# Assigned DNS checks use the real local listener port. Unassigned catalog DNS
# keeps the remote DoH check until the DNS is assigned to a slot.
new_job_id() {
    case "${1:-}" in
        profile) printf 'profile' ;;
        regional) printf 'regional' ;;
        test_all) printf 'test_all' ;;
        test_page) printf 'test_page' ;;
        test_current) printf 'test_current' ;;
        test_one) printf 'test_one' ;;
        test_system) printf 'test_system' ;;
        *) printf 'job' ;;
    esac
}
job_active() {
    _id="$1"
    [ -r "$JOB_DIR/$_id/state" ] || return 1
    [ "$(sed -n 's/^status=//p' "$JOB_DIR/$_id/state" 2>/dev/null | tail -n1)" = running ]
}
job_prepare() {
    _id="$1"
    mkdir -p "$JOB_DIR/$_id" 2>/dev/null || return 1
    : > "$JOB_DIR/$_id/state" || return 1
    : > "$JOB_DIR/$_id/output" || return 1
}
job_write() { _id="$1"; _key="$2"; _value="$3"; mkdir -p "$JOB_DIR/$_id" 2>/dev/null || return 1; printf '%s=%s\n' "$_key" "$_value" >> "$JOB_DIR/$_id/state" 2>/dev/null; }

job_pid_start_token() {
    _pid="$1"
    case "$_pid" in ''|*[!0-9]*) return 1;; esac
    [ -r "/proc/$_pid/stat" ] || return 1
    awk '{print $22}' "/proc/$_pid/stat" 2>/dev/null | head -n1
}
job_max_age() {
    _mode="$1"
    case "$_mode" in
        profile) printf '%s\n' "$JOB_MAX_AGE_PROFILE" ;;
        regional) printf '%s\n' "$JOB_MAX_AGE_PROFILE" ;;
        all) printf '%s\n' "$JOB_MAX_AGE_TEST_ALL" ;;
        current) printf '%s\n' "$JOB_MAX_AGE_TEST_CURRENT" ;;
        combined) printf '%s\n' 900 ;;
        update) printf '%s\n' 1800 ;;
        one) printf '%s\n' "$JOB_MAX_AGE_TEST_ONE" ;;
        *) printf '%s\n' 300 ;;
    esac
}
job_mark_failed() {
    _id="$1"
    _d="$JOB_DIR/$_id"
    _now="$2"
    _msg="$3"
    # The worker can finish between the first state read and the PID check.
    # Never overwrite a result it has already recorded.
    [ "$(job_state_value "$_d/state" status)" = running ] || return 0
    [ -n "$_now" ] || _now="$(date +%s 2>/dev/null || printf 0)"
    job_write "$_id" status failed
    job_write "$_id" result fail
    job_write "$_id" finished "$_now"
    printf '%s\n' "$_msg" >> "$_d/output" 2>/dev/null || true
}
job_record_pid() {
    _id="$1"
    _pid="$2"
    job_write "$_id" pid "$_pid"
    _token="$(job_pid_start_token "$_pid" 2>/dev/null || true)"
    [ -n "$_token" ] && job_write "$_id" pid_start "$_token"
}
job_terminate_pid() {
    _pid="$1"
    case "$_pid" in ''|*[!0-9]*) return 0;; esac
    kill "$_pid" 2>/dev/null || true
    for _n in 1 2 3; do
        kill -0 "$_pid" 2>/dev/null || return 0
        sleep 1
    done
    kill -9 "$_pid" 2>/dev/null || true
}

job_state_value() {
    _file="$1"; _key="$2"; _last="$3"
    [ -n "$_last" ] || _last=tail
    [ -r "$_file" ] || return 0
    case "$_last" in
        head) sed -n "s/^$_key=//p" "$_file" 2>/dev/null | head -n1 ;;
        *) sed -n "s/^$_key=//p" "$_file" 2>/dev/null | tail -n1 ;;
    esac
}
job_process_alive() {
    _d="$1"; _state="$_d/state"
    [ -r "$_state" ] || return 1
    [ "$(job_state_value "$_state" status)" = running ] || return 1

    _id="$(basename "$_d")"
    _mode="$(job_state_value "$_state" mode head)"
    _pid="$(job_state_value "$_state" pid)"
    case "$_pid" in ''|*[!0-9]*) _pid="";; esac
    _started="$(job_state_value "$_state" started head)"
    case "$_started" in ''|*[!0-9]*) _started="";; esac
    _now="$(date +%s 2>/dev/null || printf 0)"
    case "$_now" in ''|*[!0-9]*) _now="";; esac

    # Verify process identity to avoid PID reuse turning an old job into a
    # permanently "running" job.
    if [ -n "$_pid" ]; then
        _stored_token="$(job_state_value "$_state" pid_start)"
        _current_token="$(job_pid_start_token "$_pid" 2>/dev/null || true)"
        if [ -n "$_stored_token" ] && [ -n "$_current_token" ] && [ "$_stored_token" != "$_current_token" ]; then
            job_mark_failed "$_id" "$_now" "Фоновая задача DNS Manager стала недействительной: сохранённый PID уже принадлежит другому процессу."
            return 1
        fi
    fi

    _max_age="$(job_max_age "$_mode")"
    case "$_max_age" in ''|*[!0-9]*) _max_age=300;; esac
    if [ -n "$_started" ] && [ -n "$_now" ] && [ "$_now" -ge "$_started" ] 2>/dev/null; then
        _age=$((_now-_started))
        if [ "$_age" -ge "$_max_age" ] 2>/dev/null; then
            # Do not interrupt live state changes merely because a page polled late.
            case "$_mode" in
                update|profile|regional|action|setting|version)
                    if [ -n "$_pid" ] && kill -0 "$_pid" 2>/dev/null; then return 0; fi ;;
            esac
            if [ -n "$_pid" ]; then
                _safe_to_kill=1
                if [ -n "$_stored_token" ] && [ -n "$_current_token" ]; then
                    [ "$_stored_token" = "$_current_token" ] || _safe_to_kill=0
                fi
                [ "$_safe_to_kill" = 1 ] && job_terminate_pid "$_pid"
            fi
            job_mark_failed "$_id" "$_now" "Фоновая задача DNS Manager превышает допустимое время выполнения ($_max_age с) и была остановлена."
            return 1
        fi
    fi

    if [ -z "$_pid" ]; then
        # procd starts the worker asynchronously; allow it time to record PID.
        if { [ "$_mode" = update ] || [ "$_mode" = combined ] || [ "$_mode" = profile ] || [ "$_mode" = action ] || [ "$_mode" = setting ] || [ "$_mode" = regional ] || [ "$_mode" = version ] || [ "$_mode" = all ] || [ "$_mode" = current ] || [ "$_mode" = one ] || [ "$_mode" = system ]; } &&
           [ -n "$_started" ] && [ -n "$_now" ] && [ "$_now" -ge "$_started" ] &&
           [ $((_now-_started)) -lt 30 ]; then
            return 0
        fi
        job_mark_failed "$_id" "$_now" "Фоновая задача DNS Manager не имеет рабочего PID."
        return 1
    fi

    if kill -0 "$_pid" 2>/dev/null; then
        return 0
    fi

    job_mark_failed "$_id" "$_now" "Фоновая задача DNS Manager завершена аварийно: рабочий процесс больше не существует."
    return 1
}

profile_job_running() {
    PROFILE_RUNNING_JOB=""
    PROFILE_RUNNING_PROFILE=""
    for _jd in "$JOB_DIR"/*; do
        [ -d "$_jd" ] || continue
        _state="$_jd/state"
        _st="$(job_state_value "$_state" status)"
        _mode="$(job_state_value "$_state" mode head)"
        if [ "$_mode" = "profile" ] && [ "$_st" = "running" ]; then
            if job_process_alive "$_jd"; then
                PROFILE_RUNNING_JOB="$(basename "$_jd")"
                PROFILE_RUNNING_PROFILE="$(job_state_value "$_state" profile head)"
                return 0
            fi
        fi
    done
    return 1
}

# Operations that span multiple RPC calls must be owned by procd rather than
# by a browser page or rpcd. The worker writes its result to the normal job
# directory so another page (or a new browser session) can read it.
background_start() {
    case "$1" in update|combined) DM_BACKGROUND_ID="$1";; *) json_error "Недопустимая задача"; return;; esac
    DM_BACKGROUND_SERVICE="dns-manager-job-$DM_BACKGROUND_ID"
    acquire_runtime_lock "$RUNTIME_DIR/$DM_BACKGROUND_ID-start.lock" || { json_error "Задача уже запускается"; return; }
    if job_active "$DM_BACKGROUND_ID" && job_process_alive "$JOB_DIR/$DM_BACKGROUND_ID"; then
        release_runtime_lock "$RUNTIME_DIR/$DM_BACKGROUND_ID-start.lock"
        printf '{"ok":true,"job":'; json_quote "$DM_BACKGROUND_ID"; printf ',"resumed":true}'
        return
    fi
    if ubus call service list "{\"name\":\"$DM_BACKGROUND_SERVICE\"}" 2>/dev/null | grep -qE '"running"[[:space:]]*:[[:space:]]*true'; then
        release_runtime_lock "$RUNTIME_DIR/$DM_BACKGROUND_ID-start.lock"
        json_error "Предыдущая задача ещё завершается"
        return
    fi
    ubus call service delete "{\"name\":\"$DM_BACKGROUND_SERVICE\"}" >/dev/null 2>&1 || true
    job_prepare "$DM_BACKGROUND_ID" || { release_runtime_lock "$RUNTIME_DIR/$DM_BACKGROUND_ID-start.lock"; json_error "Не удалось подготовить задачу"; return; }
    printf 'status=running\nstarted=%s\nmode=%s\n' "$(date +%s)" "$DM_BACKGROUND_ID" > "$JOB_DIR/$DM_BACKGROUND_ID/state"
    DM_BACKGROUND_REQUEST="{\"name\":\"$DM_BACKGROUND_SERVICE\",\"instances\":{\"main\":{\"command\":[\"/bin/sh\",\"/usr/lib/dns-manager-luci/backend.sh\",\"worker\",\"$DM_BACKGROUND_ID\"]}}}"
    if ! ubus call service set "$DM_BACKGROUND_REQUEST" >/dev/null 2>&1; then
        job_write "$DM_BACKGROUND_ID" result fail
        job_write "$DM_BACKGROUND_ID" finished "$(date +%s)"
        job_write "$DM_BACKGROUND_ID" status failed
        release_runtime_lock "$RUNTIME_DIR/$DM_BACKGROUND_ID-start.lock"
        json_error "Не удалось запустить фоновую задачу"
        return
    fi
    release_runtime_lock "$RUNTIME_DIR/$DM_BACKGROUND_ID-start.lock"
    printf '{"ok":true,"job":'; json_quote "$DM_BACKGROUND_ID"; printf '}'
}

background_wait_test() {
    DM_WAIT_ID="$1"
    DM_WAIT_START="$(date +%s)"
    while :; do
        DM_WAIT_STATUS="$(job_state_value "$JOB_DIR/$DM_WAIT_ID/state" status)"
        DM_WAIT_FINISHED="$(job_state_value "$JOB_DIR/$DM_WAIT_ID/state" finished)"
        if [ -n "$DM_WAIT_FINISHED" ]; then
            [ "$DM_WAIT_STATUS" = done ] && [ "$(job_state_value "$JOB_DIR/$DM_WAIT_ID/state" result)" = ok ]
            return $?
        fi
        DM_WAIT_NOW="$(date +%s)"
        [ $((DM_WAIT_NOW-DM_WAIT_START)) -lt 600 ] || return 1
        case "$DM_WAIT_STATUS" in done|failed) sleep 1; continue;; esac
        if ! (job_process_alive "$JOB_DIR/$DM_WAIT_ID") >/dev/null 2>&1; then return 1; fi
        sleep 1
    done
}

background_worker() {
    case "$1" in update|combined) DM_BACKGROUND_ID="$1";; *) exit 1;; esac
    job_record_pid "$DM_BACKGROUND_ID" "$$"
    if [ "$DM_BACKGROUND_ID" = update ]; then
        update_all_json > "$JOB_DIR/update/output" 2>&1
        if grep -q '"ok":true' "$JOB_DIR/update/output"; then DM_BACKGROUND_RESULT=ok; else DM_BACKGROUND_RESULT=fail; fi
    else
        DM_BACKGROUND_RESULT=ok
        DM_BACKGROUND_SLOTS=0
        load_manager || DM_BACKGROUND_RESULT=fail
        for DM_BACKGROUND_SLOT in 1 2 3 4 5 6 RU; do
            [ -z "$(cfg_get "SLOT_$DM_BACKGROUND_SLOT" 2>/dev/null)" ] || DM_BACKGROUND_SLOTS=1
        done
        DM_BACKGROUND_SYSTEM=0
        DM_BACKGROUND_INDEX=0
        while uci -q get "https-dns-proxy.@https-dns-proxy[$DM_BACKGROUND_INDEX]" >/dev/null 2>&1; do
            DM_BACKGROUND_URL="$(uci -q get "https-dns-proxy.@https-dns-proxy[$DM_BACKGROUND_INDEX].resolver_url" 2>/dev/null)"
            DM_BACKGROUND_PORT="$(uci -q get "https-dns-proxy.@https-dns-proxy[$DM_BACKGROUND_INDEX].listen_port" 2>/dev/null)"
            if [ -n "$DM_BACKGROUND_URL" ] && [ -n "$DM_BACKGROUND_PORT" ] && ! system_instance_slot "$DM_BACKGROUND_URL" "$DM_BACKGROUND_PORT"; then DM_BACKGROUND_SYSTEM=1; fi
            DM_BACKGROUND_INDEX=$((DM_BACKGROUND_INDEX+1))
        done
        if [ "$DM_BACKGROUND_SLOTS" = 1 ]; then
            printf '%s\n' 'Проверяю DNS в слотах…' >> "$JOB_DIR/combined/output"
            DM_BACKGROUND_REPLY="$(job_start_test_current)"
            case "$DM_BACKGROUND_REPLY" in *'"ok":true'*) background_wait_test test_current || DM_BACKGROUND_RESULT=fail;; *) DM_BACKGROUND_RESULT=fail;; esac
        fi
        if [ "$DM_BACKGROUND_SYSTEM" = 1 ]; then
            printf '%s\n' 'Проверяю системные DNS…' >> "$JOB_DIR/combined/output"
            DM_BACKGROUND_REPLY="$(job_start_test_system)"
            case "$DM_BACKGROUND_REPLY" in *'"ok":true'*) background_wait_test test_system || DM_BACKGROUND_RESULT=fail;; *) DM_BACKGROUND_RESULT=fail;; esac
        fi
        [ "$DM_BACKGROUND_SLOTS$DM_BACKGROUND_SYSTEM" != 00 ] || DM_BACKGROUND_RESULT=fail
    fi
    job_write "$DM_BACKGROUND_ID" result "$DM_BACKGROUND_RESULT"
    job_write "$DM_BACKGROUND_ID" finished "$(date +%s)"
    if [ "$DM_BACKGROUND_RESULT" = ok ]; then
        job_write "$DM_BACKGROUND_ID" status done
        printf '\n__DONE__ 0\n' >> "$JOB_DIR/$DM_BACKGROUND_ID/output"
    else
        job_write "$DM_BACKGROUND_ID" status failed
        printf '\n__DONE__ 1\n' >> "$JOB_DIR/$DM_BACKGROUND_ID/output"
    fi
}

# Check the old service before clearing its previous result.
bg_service_idle() {
    DNSMGR_BG_SERVICE="dns-manager-job-$1"
    DNSMGR_BG_REPLY="$(ubus -t 5 call service list "{\"name\":\"$DNSMGR_BG_SERVICE\"}" 2>/dev/null)" || { json_error "Служба фоновых задач недоступна"; return 1; }
    if printf '%s' "$DNSMGR_BG_REPLY" | grep -qE '"running"[[:space:]]*:[[:space:]]*true'; then
        json_error "Предыдущее действие ещё выполняется"; return 1
    fi
}

# Start a worker under procd so it survives rpcd and browser disconnects.
run_bg_job() {
    DNSMGR_BG_JOB="$1"; DNSMGR_BG_KIND="$2"; DNSMGR_BG_ARG="$3"
    DNSMGR_BG_SERVICE="dns-manager-job-$DNSMGR_BG_JOB"
    if ubus call service list "{\"name\":\"$DNSMGR_BG_SERVICE\"}" 2>/dev/null | grep -qE '"running"[[:space:]]*:[[:space:]]*true'; then
        json_error "Предыдущее действие ещё выполняется"; return 1
    fi
    ubus call service delete "{\"name\":\"$DNSMGR_BG_SERVICE\"}" >/dev/null 2>&1 || true
    # setsid is optional in OpenWrt builds; procd already owns the worker.
    if command -v setsid >/dev/null 2>&1; then
        DNSMGR_BG_COMMAND="\"$(command -v setsid)\",\"/bin/sh\""
    else
        DNSMGR_BG_COMMAND='"/bin/sh"'
    fi
    if [ "$DNSMGR_BG_KIND" = test ]; then DNSMGR_BG_ENTRY=test_worker; DNSMGR_BG_ARGS="\"$DNSMGR_BG_JOB\",\"$DNSMGR_BG_ARG\""; else DNSMGR_BG_ENTRY=mutation_worker; DNSMGR_BG_ARGS="\"$DNSMGR_BG_JOB\",\"$DNSMGR_BG_KIND\",\"$DNSMGR_BG_ARG\""; fi
    DNSMGR_BG_REQUEST="{\"name\":\"$DNSMGR_BG_SERVICE\",\"instances\":{\"main\":{\"command\":[$DNSMGR_BG_COMMAND,\"/usr/lib/dns-manager-luci/backend.sh\",\"$DNSMGR_BG_ENTRY\",$DNSMGR_BG_ARGS]}}}"
    if ! ubus call service set "$DNSMGR_BG_REQUEST" >/dev/null 2>&1; then
        job_write "$DNSMGR_BG_JOB" result fail; job_write "$DNSMGR_BG_JOB" status failed; job_write "$DNSMGR_BG_JOB" finished "$(date +%s)"
        json_error "Не удалось запустить фоновую задачу"; return 1
    fi
    return 0
}

mutation_worker() {
    DNSMGR_WORK_JOB="$1"; DNSMGR_WORK_KIND="$2"; DNSMGR_WORK_ARG="$3"
    case "$DNSMGR_WORK_JOB:$DNSMGR_WORK_KIND" in action:action|setting:setting|profile:profile|regional:regional|version:version) ;; *) return 1;; esac
    job_record_pid "$DNSMGR_WORK_JOB" "$$"
    exec >>"$JOB_DIR/$DNSMGR_WORK_JOB/output" 2>&1 </dev/null
    DNSMGR_WORK_RC=1
    case "$DNSMGR_WORK_KIND" in
        action|setting)
            INPUT="$(cat "$JOB_DIR/$DNSMGR_WORK_JOB/input" 2>/dev/null)"
            RPC_METHOD="$DNSMGR_WORK_ARG"
            DNSMGR_ACTION_WORKER=1; DNSMGR_SETTING_WORKER=1
            run_action
            grep -q '"ok"[[:space:]]*:[[:space:]]*true' "$JOB_DIR/$DNSMGR_WORK_JOB/output" && DNSMGR_WORK_RC=0
            ;;
        version)
            INPUT="{\"force\":$DNSMGR_WORK_ARG}"
            update_check_json
            grep -q '"ok"[[:space:]]*:[[:space:]]*true' "$JOB_DIR/$DNSMGR_WORK_JOB/output" && DNSMGR_WORK_RC=0
            ;;
        profile)
            if load_manager; then
                DNS_MANAGER_NO_UPDATE=1 SILENT_APPLY=1 HYBRID_SELECTION_QUIET=1 PROFILE_APPLY=1 apply_profile_now "$DNSMGR_WORK_ARG" && DNSMGR_WORK_RC=0
            else printf '%s\n' 'DNS Manager недоступен.'; fi
            ;;
        regional) load_manager && DNS_MANAGER_NO_UPDATE=1 regional_apply_toggle "$DNSMGR_WORK_ARG" && DNSMGR_WORK_RC=0;;
    esac
    rm -f "$JOB_DIR/$DNSMGR_WORK_JOB/input"
    if [ "$DNSMGR_WORK_RC" = 0 ]; then
        job_write "$DNSMGR_WORK_JOB" result ok; job_write "$DNSMGR_WORK_JOB" status done
    else
        job_write "$DNSMGR_WORK_JOB" result fail; job_write "$DNSMGR_WORK_JOB" status failed
    fi
    job_write "$DNSMGR_WORK_JOB" finished "$(date +%s)"
    printf '\n__DONE__ %s\n' "$DNSMGR_WORK_RC"
}

job_start_action() {
    DNSMGR_ACTION_METHOD="$1"
    case "$DNSMGR_ACTION_METHOD" in set_slot|set_slot_domains|set_device_dns|set_cache|reset_dns|set_ntp|set_bootstrap|add_custom_dns|delete_custom_dns|set_watchdog_setting|set_watchdog_settings|set_test_age) ;; *) json_error "Неверное действие"; return;; esac
    acquire_runtime_lock "$RUNTIME_DIR/action-start.lock" || { json_error "Другое действие уже запускается"; return; }
    if job_active action && job_process_alive "$JOB_DIR/action"; then release_runtime_lock "$RUNTIME_DIR/action-start.lock"; json_error "Другое действие уже выполняется"; return; fi
    bg_service_idle action || { release_runtime_lock "$RUNTIME_DIR/action-start.lock"; return; }
    job_prepare action && printf '%s' "$INPUT" > "$JOB_DIR/action/input" || { release_runtime_lock "$RUNTIME_DIR/action-start.lock"; json_error "Не удалось подготовить задачу"; return; }
    printf 'status=running\nstarted=%s\nmode=action\nname=%s\n' "$(date +%s)" "$DNSMGR_ACTION_METHOD" > "$JOB_DIR/action/state"
    if run_bg_job action action "$DNSMGR_ACTION_METHOD"; then printf '{"ok":true,"job":"action"}'; fi
    release_runtime_lock "$RUNTIME_DIR/action-start.lock"
}

job_start_version_check() {
    DNSMGR_VERSION_FORCE="$(jget force 2>/dev/null || true)"
    [ "$DNSMGR_VERSION_FORCE" = 1 ] || DNSMGR_VERSION_FORCE=0
    acquire_runtime_lock "$RUNTIME_DIR/version-start.lock" || { json_error "Проверка версий уже запускается"; return; }
    if job_active version && job_process_alive "$JOB_DIR/version"; then
        release_runtime_lock "$RUNTIME_DIR/version-start.lock"
        printf '{"ok":true,"job":"version","resumed":true}'
        return
    fi
    bg_service_idle version || { release_runtime_lock "$RUNTIME_DIR/version-start.lock"; return; }
    job_prepare version || { release_runtime_lock "$RUNTIME_DIR/version-start.lock"; json_error "Не удалось подготовить проверку версий"; return; }
    printf 'status=running\nstarted=%s\nmode=version\n' "$(date +%s)" > "$JOB_DIR/version/state"
    if run_bg_job version version "$DNSMGR_VERSION_FORCE"; then printf '{"ok":true,"job":"version"}'; fi
    release_runtime_lock "$RUNTIME_DIR/version-start.lock"
}

job_start_setting() {
    DNSMGR_SETTING_NAME="$1"; DNSMGR_SETTING_VALUE="$2"
    case "$DNSMGR_SETTING_NAME:$DNSMGR_SETTING_VALUE" in force:0|force:1|encrypted_dns:0|encrypted_dns:1|browser_dns:0|browser_dns:1|watchdog:0|watchdog:1|watchdog_autoreplace:0|watchdog_autoreplace:1|dnsmasq_perf:0|dnsmasq_perf:1) ;; *) json_error "Неверная настройка"; return;; esac
    acquire_runtime_lock "$RUNTIME_DIR/setting-start.lock" || { json_error "Другая настройка уже запускается"; return; }
    if job_active setting && job_process_alive "$JOB_DIR/setting"; then release_runtime_lock "$RUNTIME_DIR/setting-start.lock"; json_error "Другая настройка уже применяется"; return; fi
    bg_service_idle setting || { release_runtime_lock "$RUNTIME_DIR/setting-start.lock"; return; }
    job_prepare setting && printf '%s' "$INPUT" > "$JOB_DIR/setting/input" || { release_runtime_lock "$RUNTIME_DIR/setting-start.lock"; json_error "Не удалось подготовить задачу"; return; }
    printf 'status=running\nstarted=%s\nmode=setting\nname=%s\nenabled=%s\n' "$(date +%s)" "$DNSMGR_SETTING_NAME" "$DNSMGR_SETTING_VALUE" > "$JOB_DIR/setting/state"
    if run_bg_job setting setting set_setting; then printf '{"ok":true,"job":"setting"}'; fi
    release_runtime_lock "$RUNTIME_DIR/setting-start.lock"
}

job_start_regional() {
    DNSMGR_REGIONAL_ENABLED="$1"
    case "$DNSMGR_REGIONAL_ENABLED" in 0|1|2|3) ;; *) json_error "Неверное состояние регионального DNS"; return;; esac
    acquire_runtime_lock "$RUNTIME_DIR/regional-start.lock" || { json_error "Настройка уже запускается"; return; }
    if job_active regional && job_process_alive "$JOB_DIR/regional"; then release_runtime_lock "$RUNTIME_DIR/regional-start.lock"; json_error "Региональный DNS уже изменяется"; return; fi
    bg_service_idle regional || { release_runtime_lock "$RUNTIME_DIR/regional-start.lock"; return; }
    job_prepare regional || { release_runtime_lock "$RUNTIME_DIR/regional-start.lock"; json_error "Не удалось подготовить задачу"; return; }
    printf 'status=running\nstarted=%s\nmode=regional\nenabled=%s\n' "$(date +%s)" "$DNSMGR_REGIONAL_ENABLED" > "$JOB_DIR/regional/state"
    if run_bg_job regional regional "$DNSMGR_REGIONAL_ENABLED"; then printf '{"ok":true,"job":"regional"}'; fi
    release_runtime_lock "$RUNTIME_DIR/regional-start.lock"
}

job_start_profile() {
    DNSMGR_PROFILE_REQUEST="$1"
    case "$DNSMGR_PROFILE_REQUEST" in clean2) DNSMGR_PROFILE_REQUEST=clean;; bypass|clean|security|privacy|adblock|family|all|dnssec) ;; *) json_error "Неверный профиль"; return;; esac
    acquire_runtime_lock "$RUNTIME_DIR/profile-start.lock" || { json_error "Профиль уже запускается"; return; }
    if profile_job_running; then
        if [ "$PROFILE_RUNNING_PROFILE" = "$DNSMGR_PROFILE_REQUEST" ]; then
            printf '{"ok":true,"job":"profile","resumed":true,"profile":'; json_quote "$DNSMGR_PROFILE_REQUEST"; printf '}'
        else json_error "Сейчас уже применяется другой профиль."; fi
        release_runtime_lock "$RUNTIME_DIR/profile-start.lock"; return
    fi
    bg_service_idle profile || { release_runtime_lock "$RUNTIME_DIR/profile-start.lock"; return; }
    job_prepare profile || { release_runtime_lock "$RUNTIME_DIR/profile-start.lock"; json_error "Не удалось подготовить задачу"; return; }
    printf 'status=running\nstarted=%s\nmode=profile\nprofile=%s\n' "$(date +%s)" "$DNSMGR_PROFILE_REQUEST" > "$JOB_DIR/profile/state"
    if run_bg_job profile profile "$DNSMGR_PROFILE_REQUEST"; then printf '{"ok":true,"job":"profile"}'; fi
    release_runtime_lock "$RUNTIME_DIR/profile-start.lock"
}

# Catalog tests are launched by procd, not by the rpcd request process.
job_start_test() {
    DNSMGR_TEST_ID="$1"; DNSMGR_TEST_ARG="${2:-}"
    case "$DNSMGR_TEST_ID" in test_all|test_current|test_system) ;; test_page) case "$DNSMGR_TEST_ARG" in ''|*[!A-Za-z0-9_,-]*) json_error "Неверный список DNS"; return;; esac ;; test_one) case "$DNSMGR_TEST_ARG" in ''|*[!A-Za-z0-9_-]*) json_error "Неверный ID DNS"; return;; esac ;; *) json_error "Неверная проверка"; return;; esac
    acquire_runtime_lock "$RUNTIME_DIR/$DNSMGR_TEST_ID-start.lock" || { json_error "Проверка уже запускается"; return; }
    if job_active "$DNSMGR_TEST_ID" && job_process_alive "$JOB_DIR/$DNSMGR_TEST_ID"; then release_runtime_lock "$RUNTIME_DIR/$DNSMGR_TEST_ID-start.lock"; json_error "Проверка уже выполняется"; return; fi
    bg_service_idle "$DNSMGR_TEST_ID" || { release_runtime_lock "$RUNTIME_DIR/$DNSMGR_TEST_ID-start.lock"; return; }
    job_prepare "$DNSMGR_TEST_ID" || { release_runtime_lock "$RUNTIME_DIR/$DNSMGR_TEST_ID-start.lock"; json_error "Не удалось подготовить проверку"; return; }
    case "$DNSMGR_TEST_ID" in test_all|test_page) DNSMGR_TEST_MODE=all;; test_current) DNSMGR_TEST_MODE=current;; test_one) DNSMGR_TEST_MODE=one;; test_system) DNSMGR_TEST_MODE=system;; esac
    printf 'status=running\nstarted=%s\nmode=%s\n' "$(date +%s)" "$DNSMGR_TEST_MODE" > "$JOB_DIR/$DNSMGR_TEST_ID/state"
    [ "$DNSMGR_TEST_ID" != test_page ] || rm -f "$JOB_DIR/test_page/cancel"
    [ "$DNSMGR_TEST_ID" != test_one ] || job_write "$DNSMGR_TEST_ID" dns_id "$DNSMGR_TEST_ARG"
    if run_bg_job "$DNSMGR_TEST_ID" test "$DNSMGR_TEST_ARG"; then printf '{"ok":true,"job":'; json_quote "$DNSMGR_TEST_ID"; printf '}'; fi
    release_runtime_lock "$RUNTIME_DIR/$DNSMGR_TEST_ID-start.lock"
}
job_start_test_all() { job_start_test test_all; }
job_start_test_current() { job_start_test test_current; }
job_start_test_one() { job_start_test test_one "$1"; }
job_start_test_system() { job_start_test test_system; }

test_worker() {
    DM_TEST_ID="$1"; DM_TEST_ARG="${2:-}"
    case "$DM_TEST_ID" in
        test_all) job_execute_test_all >/dev/null ;;
        test_current) job_execute_test_current >/dev/null ;;
        test_page) job_execute_test_page "$DM_TEST_ARG" >/dev/null ;;
        test_system) job_execute_test_system >/dev/null ;;
        test_one) job_execute_test_one "$DM_TEST_ARG" >/dev/null ;;
        *) exit 1 ;;
    esac
    while [ "$(job_state_value "$JOB_DIR/$DM_TEST_ID/state" status)" = running ]; do
        if ! (job_process_alive "$JOB_DIR/$DM_TEST_ID") >/dev/null 2>&1; then break; fi
        sleep 1
    done
    if [ "$(job_state_value "$JOB_DIR/$DM_TEST_ID/state" status)" = done ]; then
        printf '\n__DONE__ 0\n' >> "$JOB_DIR/$DM_TEST_ID/output"
    else
        printf '\n__DONE__ 1\n' >> "$JOB_DIR/$DM_TEST_ID/output"
    fi
}

job_execute_test_all() {
    _jid="$(new_job_id test_all)"
    printf 'status=running\nstarted=%s\nmode=all\n' "$(date +%s)" > "$JOB_DIR/$_jid/state"
    (
        exec >>"$JOB_DIR/$_jid/output" 2>&1
        trap 'job_write "$_jid" status failed; job_write "$_jid" finished "$(date +%s)"; exit 1' INT TERM
        if load_manager && SILENT_APPLY=1 test_dns_catalog; then
            _final_total="$(wc -l < "$TEST_RESULTS" 2>/dev/null | tr -d ' ')"
            _final_ok="$(grep -c '|OK$' "$TEST_RESULTS" 2>/dev/null || printf 0)"
            case "$_final_total" in ''|*[!0-9]*) _final_total=0;; esac
            case "$_final_ok" in ''|*[!0-9]*) _final_ok=0;; esac
            [ "$_final_ok" -le "$_final_total" ] 2>/dev/null || _final_ok=0
            _final_fail=$((_final_total-_final_ok))
            job_write "$_jid" progress_done "$_final_total"
            job_write "$_jid" progress_total "$_final_total"
            job_write "$_jid" progress_ok "$_final_ok"
            job_write "$_jid" progress_fail "$_final_fail"
            now="$(date +%s)"
            _full_stamp="$(sed -n 's/^timestamp=//p' "$TEST_RESULTS_META" 2>/dev/null | head -n1)"
            case "$_full_stamp" in ''|*[!0-9]*) _full_stamp="$now";; esac
            while IFS='|' read -r _id _rest; do [ -n "$_id" ] && set_check_stamp "$_id" "$_full_stamp"; done < "$TEST_RESULTS"
            job_write "$_jid" status done; job_write "$_jid" result ok; job_write "$_jid" finished "$now"
        else
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"
        fi
    ) &
    _job_pid=$!
    job_record_pid "$_jid" "$_job_pid"
    printf '{"ok":true,"job":'; json_quote "$_jid"; printf '}'
}

job_execute_test_current() {
    _jid="$(new_job_id test_current)"
    printf 'status=running\nstarted=%s\nmode=current\n' "$(date +%s)" > "$JOB_DIR/$_jid/state"
    (
        exec >>"$JOB_DIR/$_jid/output" 2>&1
        if ! load_manager; then
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"; exit 1
        fi
        if ! acquire_test_lock; then
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"; exit 1
        fi

        _ids="$TMP_ROOT/current-dns-ids.$$"
        _results="$TMP_ROOT/current-test-results.$$"
        _merged="$TMP_ROOT/current-merged.$$"
        : > "$_ids"
        : > "$_results"
        rm -f "$TMP_DIR/t."* 2>/dev/null || true

        _total=0
        _done=0
        _fail=0
        for _s in 1 2 3 4 5 6 RU; do
            _id="$(cfg_get "SLOT_$_s" 2>/dev/null || true)"
            [ -n "$_id" ] || continue
            printf "%s\n" "$_id" >> "$_ids"
            _total=$((_total+1))
        done

        if [ "$_total" -eq 0 ]; then
            release_test_lock
            rm -f "$_ids" "$_results" "$_merged"
            job_write "$_jid" status failed
            job_write "$_jid" result fail
            job_write "$_jid" finished "$(date +%s)"
            exit 1
        fi

        # test_one_dns workers share this immutable packet. Create it here
        # before forking, exactly as the full catalog test does.
        q="$TMP_DIR/dns_query.bin"
        if ! printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$q" 2>/dev/null; then
            rm -f "$q" "$_ids" "$_results" "$_merged" 2>/dev/null || true
            release_test_lock
            job_write "$_jid" status failed
            job_write "$_jid" result fail
            job_write "$_jid" finished "$(date +%s)"
            job_write "$_jid" error "Не удалось создать общий DNS-тестовый пакет."
            exit 1
        fi

        _batch="${TEST_BATCH:-${TEST_BATCH_DEFAULT:-4}}"
        case "$_batch" in ''|*[!0-9]*) _batch=4;; esac
        [ "$_batch" -ge 1 ] 2>/dev/null || _batch=1
        [ "$_batch" -le 4 ] 2>/dev/null || _batch=4

        _batch_pids=""
        _batch_ids=""
        _batch_n=0
        collect_current_batch() {
            for _wp in $_batch_pids; do
                wait "$_wp" 2>/dev/null || true
            done
            for _cid in $_batch_ids; do
                _rfile="$TMP_DIR/t.$_cid"
                if [ -s "$_rfile" ]; then
                    cat "$_rfile" >> "$_results" 2>/dev/null || true
                    grep -q '|OK$' "$_rfile" 2>/dev/null || _fail=$((_fail+1))
                else
                    printf '%s|%s|%s|-1|TEST_NO_RESULT\n' "$_cid" "$(dns_cat "$_cid" 2>/dev/null || printf unknown)" "$(dns_name "$_cid" 2>/dev/null || printf "%s" "$_cid")" >> "$_results"
                    _fail=$((_fail+1))
                fi
                _done=$((_done+1))
            done
            printf "Проверка выбранных DNS: %s из %s | ошибки %s\n" "$_done" "$_total" "$_fail"
            _batch_pids=""
            _batch_ids=""
            _batch_n=0
        }

        while IFS= read -r _id; do
            [ -n "$_id" ] || continue
            printf "Проверяю DoH: %s\n" "$_id"
            (trap - EXIT; test_one_dns "$_id") &
            _batch_pids="$_batch_pids $!"
            _batch_ids="$_batch_ids $_id"
            _batch_n=$((_batch_n+1))
            if [ "$_batch_n" -ge "$_batch" ]; then
                collect_current_batch
            fi
        done < "$_ids"
        [ -n "$_batch_pids" ] && collect_current_batch

        : > "$_merged"
        if [ -s "$TEST_RESULTS" ]; then
            awk -F"|" -v ids_file="$_ids" 'BEGIN { while ((getline x < ids_file)>0) ids[x]=1 } !($1 in ids) { print }' "$TEST_RESULTS" > "$_merged" 2>/dev/null || true
        fi
        [ -s "$_results" ] && cat "$_results" >> "$_merged"
        mv -f "$_merged" "$TEST_RESULTS" 2>/dev/null || {
            release_test_lock
            rm -f "$_ids" "$_results" "$_merged"
            job_write "$_jid" status failed
            job_write "$_jid" result fail
            job_write "$_jid" finished "$(date +%s)"
            exit 1
        }

        _stamp="$(date +%s)"
        while IFS="|" read -r _id _rest; do
            [ -n "$_id" ] && set_check_stamp "$_id" "$_stamp"
        done < "$_results"

        rm -f "$_ids" "$_results" "$_merged" "$TMP_DIR/t."* "$TMP_DIR/dns_query.bin" 2>/dev/null || true
        release_test_lock

        job_write "$_jid" status done
        if [ "$_fail" -eq 0 ]; then
            job_write "$_jid" result ok
        else
            job_write "$_jid" result fail
        fi
        job_write "$_jid" finished "$_stamp"
    ) &
    _job_pid=$!
    job_record_pid "$_jid" "$_job_pid"
    printf '{"ok":true,"job":'; json_quote "$_jid"; printf '}'
}
job_execute_test_page() {
    _page_ids="$1"
    _jid="$(new_job_id test_page)"
    printf 'status=running\nstarted=%s\nmode=current\n' "$(date +%s)" > "$JOB_DIR/$_jid/state"
    (
        exec >>"$JOB_DIR/$_jid/output" 2>&1
        if ! load_manager; then
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"; exit 1
        fi
        if ! acquire_test_lock; then
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"; exit 1
        fi

        _ids="$TMP_ROOT/current-dns-ids.$$"
        _results="$TMP_ROOT/current-test-results.$$"
        _merged="$TMP_ROOT/current-merged.$$"
        : > "$_ids"
        : > "$_results"
        rm -f "$TMP_DIR/t."* 2>/dev/null || true

        _total=0
        _done=0
        _fail=0
        printf '%s\n' "$_page_ids" | tr ',' '\n' | awk 'NF && !seen[$0]++ {print}' > "$_ids"
        _total=$(wc -l < "$_ids" | tr -d ' ')
        [ "$_total" -le 48 ] || _total=0
        job_write "$_jid" progress_total "$_total"

        if [ "$_total" -eq 0 ]; then
            release_test_lock
            rm -f "$_ids" "$_results" "$_merged"
            job_write "$_jid" status failed
            job_write "$_jid" result fail
            job_write "$_jid" finished "$(date +%s)"
            exit 1
        fi

        # test_one_dns workers share this immutable packet. Create it here
        # before forking, exactly as the full catalog test does.
        q="$TMP_DIR/dns_query.bin"
        if ! printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$q" 2>/dev/null; then
            rm -f "$q" "$_ids" "$_results" "$_merged" 2>/dev/null || true
            release_test_lock
            job_write "$_jid" status failed
            job_write "$_jid" result fail
            job_write "$_jid" finished "$(date +%s)"
            job_write "$_jid" error "Не удалось создать общий DNS-тестовый пакет."
            exit 1
        fi

        _batch="${TEST_BATCH:-${TEST_BATCH_DEFAULT:-4}}"
        case "$_batch" in ''|*[!0-9]*) _batch=4;; esac
        [ "$_batch" -ge 1 ] 2>/dev/null || _batch=1
        [ "$_batch" -le 4 ] 2>/dev/null || _batch=4

        _batch_pids=""
        _batch_ids=""
        _batch_n=0
        collect_current_batch() {
            for _wp in $_batch_pids; do
                wait "$_wp" 2>/dev/null || true
            done
            for _cid in $_batch_ids; do
                _rfile="$TMP_DIR/t.$_cid"
                if [ -s "$_rfile" ]; then
                    cat "$_rfile" >> "$_results" 2>/dev/null || true
                    grep -q '|OK$' "$_rfile" 2>/dev/null || _fail=$((_fail+1))
                else
                    printf '%s|%s|%s|-1|TEST_NO_RESULT\n' "$_cid" "$(dns_cat "$_cid" 2>/dev/null || printf unknown)" "$(dns_name "$_cid" 2>/dev/null || printf "%s" "$_cid")" >> "$_results"
                    _fail=$((_fail+1))
                fi
                _done=$((_done+1))
            done
            job_write "$_jid" progress_done "$_done"
            job_write "$_jid" progress_ok "$((_done-_fail))"
            job_write "$_jid" progress_fail "$_fail"
            printf "Проверка выбранных DNS: %s из %s | ошибки %s\n" "$_done" "$_total" "$_fail"
            _batch_pids=""
            _batch_ids=""
            _batch_n=0
        }

        while IFS= read -r _id; do
            [ ! -f "$JOB_DIR/test_page/cancel" ] || break
            [ -n "$_id" ] || continue
            printf "Проверяю DoH: %s\n" "$_id"
            (trap - EXIT; test_one_dns "$_id") &
            _batch_pids="$_batch_pids $!"
            _batch_ids="$_batch_ids $_id"
            _batch_n=$((_batch_n+1))
            if [ "$_batch_n" -ge "$_batch" ]; then
                collect_current_batch
            fi
        done < "$_ids"
        [ -n "$_batch_pids" ] && collect_current_batch

        : > "$_merged"
        if [ -s "$TEST_RESULTS" ]; then
            awk -F"|" -v ids_file="$_results" 'BEGIN { while ((getline x < ids_file)>0) { split(x, fields, "|"); ids[fields[1]]=1 } } !($1 in ids) { print }' "$TEST_RESULTS" > "$_merged" 2>/dev/null || true
        fi
        [ -s "$_results" ] && cat "$_results" >> "$_merged"
        mv -f "$_merged" "$TEST_RESULTS" 2>/dev/null || {
            release_test_lock
            rm -f "$_ids" "$_results" "$_merged"
            job_write "$_jid" status failed
            job_write "$_jid" result fail
            job_write "$_jid" finished "$(date +%s)"
            exit 1
        }

        _stamp="$(date +%s)"
        while IFS="|" read -r _id _rest; do
            [ -n "$_id" ] && set_check_stamp "$_id" "$_stamp"
        done < "$_results"

        rm -f "$_ids" "$_results" "$_merged" "$TMP_DIR/t."* "$TMP_DIR/dns_query.bin" 2>/dev/null || true
        release_test_lock

        [ ! -f "$JOB_DIR/test_page/cancel" ] || job_write "$_jid" cancelled 1
        job_write "$_jid" status done
        job_write "$_jid" result ok
        job_write "$_jid" finished "$_stamp"
    ) &
    _job_pid=$!
    job_record_pid "$_jid" "$_job_pid"
    printf '{"ok":true,"job":'; json_quote "$_jid"; printf '}'
}
job_execute_test_one() {
    # Keep the requested DNS ID separate from helpers such as job_active(),
    # job_prepare() and job_write(), which reuse the global variable _id.
    DNSMGR_SINGLE_TEST_DNS_ID="$1"
    case "$DNSMGR_SINGLE_TEST_DNS_ID" in ''|*[!A-Za-z0-9_-]*) json_error "Неверный ID DNS"; return;; esac
    DNSMGR_SINGLE_TEST_JOB_ID="$(new_job_id test_one)"
    printf 'status=running\nstarted=%s\nmode=one\n' "$(date +%s)" > "$JOB_DIR/$DNSMGR_SINGLE_TEST_JOB_ID/state"
    job_write "$DNSMGR_SINGLE_TEST_JOB_ID" dns_id "$DNSMGR_SINGLE_TEST_DNS_ID"
    (
        exec >>"$JOB_DIR/$DNSMGR_SINGLE_TEST_JOB_ID/output" 2>&1
        if ! load_manager; then
            job_write "$DNSMGR_SINGLE_TEST_JOB_ID" status failed; job_write "$DNSMGR_SINGLE_TEST_JOB_ID" result fail; job_write "$DNSMGR_SINGLE_TEST_JOB_ID" finished "$(date +%s)"; exit 1
        fi
        if ! acquire_test_lock; then
            job_write "$DNSMGR_SINGLE_TEST_JOB_ID" status failed; job_write "$DNSMGR_SINGLE_TEST_JOB_ID" result fail; job_write "$DNSMGR_SINGLE_TEST_JOB_ID" finished "$(date +%s)"; exit 1
        fi
        # Keep single-DNS checks identical to the full/selected catalog test path.
        printf "Проверяю реальный DoH endpoint: %s.\n" "$DNSMGR_SINGLE_TEST_DNS_ID"
        rm -f "$TMP_DIR/t.$DNSMGR_SINGLE_TEST_DNS_ID" 2>/dev/null || true
        test_one_dns "$DNSMGR_SINGLE_TEST_DNS_ID" || true
        DNSMGR_SINGLE_TEST_RESULT_FILE="$TMP_DIR/t.$DNSMGR_SINGLE_TEST_DNS_ID"
        if [ -s "$DNSMGR_SINGLE_TEST_RESULT_FILE" ]; then
            DNSMGR_SINGLE_TEST_MS="$(awk -F"|" -v id="$DNSMGR_SINGLE_TEST_DNS_ID" '$1==id && NF>=5 {print $4;exit}' "$DNSMGR_SINGLE_TEST_RESULT_FILE" 2>/dev/null || true)"
            DNSMGR_SINGLE_TEST_STATUS="$(awk -F"|" -v id="$DNSMGR_SINGLE_TEST_DNS_ID" '$1==id && NF>=5 {print $5;exit}' "$DNSMGR_SINGLE_TEST_RESULT_FILE" 2>/dev/null || true)"
        else
            DNSMGR_SINGLE_TEST_MS=""
            DNSMGR_SINGLE_TEST_STATUS="TEST_NO_RESULT"
        fi
        if [ -n "$DNSMGR_SINGLE_TEST_STATUS" ] && [ "$DNSMGR_SINGLE_TEST_STATUS" != "TEST_NO_RESULT" ]; then
            job_write "$DNSMGR_SINGLE_TEST_JOB_ID" ping "$DNSMGR_SINGLE_TEST_MS"
            job_write "$DNSMGR_SINGLE_TEST_JOB_ID" dns_status "$DNSMGR_SINGLE_TEST_STATUS"
            if ! commit_single_test_result "$DNSMGR_SINGLE_TEST_DNS_ID" "$DNSMGR_SINGLE_TEST_RESULT_FILE"; then
                job_write "$DNSMGR_SINGLE_TEST_JOB_ID" status failed
                job_write "$DNSMGR_SINGLE_TEST_JOB_ID" result fail
                job_write "$DNSMGR_SINGLE_TEST_JOB_ID" finished "$(date +%s)"
                job_write "$DNSMGR_SINGLE_TEST_JOB_ID" error "Не удалось сохранить результат одиночной проверки в общий журнал DNS."
                rm -f "$DNSMGR_SINGLE_TEST_RESULT_FILE" 2>/dev/null || true
                release_test_lock
                exit 1
            fi
            # Only after the common result was verified do we advance the
            # per-DNS freshness stamp used by LuCI.
            DNSMGR_SINGLE_TEST_STAMP="$(date +%s)"
            set_check_stamp "$DNSMGR_SINGLE_TEST_DNS_ID" "$DNSMGR_SINGLE_TEST_STAMP" || true
            rm -f "$DNSMGR_SINGLE_TEST_RESULT_FILE" 2>/dev/null || true
            release_test_lock
            job_write "$DNSMGR_SINGLE_TEST_JOB_ID" status done
            if [ "$DNSMGR_SINGLE_TEST_STATUS" = "OK" ]; then
                job_write "$DNSMGR_SINGLE_TEST_JOB_ID" result ok
            else
                job_write "$DNSMGR_SINGLE_TEST_JOB_ID" result fail
            fi
            job_write "$DNSMGR_SINGLE_TEST_JOB_ID" finished "$DNSMGR_SINGLE_TEST_STAMP"
            exit 0
        fi
        release_test_lock
        job_write "$DNSMGR_SINGLE_TEST_JOB_ID" status failed
        job_write "$DNSMGR_SINGLE_TEST_JOB_ID" result fail
        job_write "$DNSMGR_SINGLE_TEST_JOB_ID" finished "$(date +%s)"
    ) &
    DNSMGR_SINGLE_TEST_PID=$!
    job_record_pid "$DNSMGR_SINGLE_TEST_JOB_ID" "$DNSMGR_SINGLE_TEST_PID"
    printf '{"ok":true,"job":'; json_quote "$DNSMGR_SINGLE_TEST_JOB_ID"; printf '}'
}
job_json() {
    _jid="$1"; case "$_jid" in ''|*[!A-Za-z0-9_-]*) json_error "Неверный job ID"; return;; esac
    _d="$JOB_DIR/$_jid"; [ -d "$_d" ] || { json_error "Задача не найдена"; return; }
    if [ "$(job_state_value "$_d/state" status)" = running ]; then
        job_process_alive "$_d" >/dev/null 2>&1 || true
    fi
    printf '{"ok":true,"job":'; json_quote "$_jid"
    _job_status="$(sed -n 's/^status=//p' "$_d/state" 2>/dev/null | tail -n1)"
    _job_result="$(sed -n 's/^result=//p' "$_d/state" 2>/dev/null | tail -n1)"
    # New workers finish with a marker; older workers remain compatible.
    if [ -z "$_job_status" ] || [ "$_job_status" = running ]; then
        case "$(tail -n1 "$_d/output" 2>/dev/null)" in
            '__DONE__ 0') _job_status=done; _job_result=ok;;
            '__DONE__ 1') _job_status=failed; _job_result=fail;;
        esac
    fi
    printf ',"status":'; json_quote "$_job_status"
    printf ',"result":'; json_quote "$_job_result"
    printf ',"mode":'; json_quote "$(sed -n 's/^mode=//p' "$_d/state" 2>/dev/null | head -n1)"
    printf ',"enabled":'; json_quote "$(sed -n 's/^enabled=//p' "$_d/state" 2>/dev/null | head -n1)"
    printf ',"name":'; json_quote "$(sed -n 's/^name=//p' "$_d/state" 2>/dev/null | tail -n1)"
    printf ',"profile":'; json_quote "$(sed -n 's/^profile=//p' "$_d/state" 2>/dev/null | head -n1)"
    printf ',"dns_id":'; json_quote "$(sed -n 's/^dns_id=//p' "$_d/state" 2>/dev/null | head -n1)"
    printf ',"phase":'; json_quote "$(sed -n 's/^phase=//p' "$_d/state" 2>/dev/null | tail -n1)"
    printf ',"progress_done":'; json_quote "$(sed -n 's/^progress_done=//p' "$_d/state" 2>/dev/null | tail -n1)"
    printf ',"progress_total":'; json_quote "$(sed -n 's/^progress_total=//p' "$_d/state" 2>/dev/null | tail -n1)"
    printf ',"progress_ok":'; json_quote "$(sed -n 's/^progress_ok=//p' "$_d/state" 2>/dev/null | tail -n1)"
    printf ',"progress_fail":'; json_quote "$(sed -n 's/^progress_fail=//p' "$_d/state" 2>/dev/null | tail -n1)"
    printf ',"cancelled":'; json_quote "$(sed -n 's/^cancelled=//p' "$_d/state" 2>/dev/null | tail -n1)"
    _job_mode="$(sed -n 's/^mode=//p' "$_d/state" 2>/dev/null | head -n1)"
    _job_dns_id="$(sed -n 's/^dns_id=//p' "$_d/state" 2>/dev/null | head -n1)"
    if [ "$_job_mode" = "one" ] && [ -n "$_job_dns_id" ]; then
        _jms="$(sed -n 's/^ping=//p' "$_d/state" 2>/dev/null | tail -n1)"
        _jst="$(sed -n 's/^dns_status=//p' "$_d/state" 2>/dev/null | tail -n1)"
        if [ -z "$_jst" ]; then
            _jr="$(result_for_id "$_job_dns_id" 2>/dev/null || true)"
            _jms="$(printf '%s' "$_jr" | awk -F'|' 'NF>=5 {print $4;exit}')"
            _jst="$(printf '%s' "$_jr" | awk -F'|' 'NF>=5 {print $5;exit}')"
        fi
        printf ',"ping":'; json_quote "$_jms"
        printf ',"dns_status":'; json_quote "$_jst"
    fi
    printf ',"started":'; json_quote "$(sed -n 's/^started=//p' "$_d/state" 2>/dev/null | head -n1)"
    printf ',"finished":'; json_quote "$(sed -n 's/^finished=//p' "$_d/state" 2>/dev/null | tail -n1)"
    printf ',"error":'; json_quote "$(sed -n 's/^error=//p' "$_d/state" 2>/dev/null | tail -n1)"
    printf ',"output":'; printf '"'; tail -n 80 "$_d/output" 2>/dev/null | sed '/^__DONE__ [01]$/d' | sed 's/\\/\\\\/g; s/"/\\"/g; s/\r/ /g; s/\t/\\t/g' | awk 'NR>1 {printf "\\n"} {printf "%s", $0}'; printf '"'
    printf '}' 
}
log_json() {
    _n="$1"; case "$_n" in ''|*[!0-9]*) _n=80;; esac
    [ "$_n" -gt 300 ] && _n=300
    _manager_log="$(awk '
        !/^\[[^]]+\] (Автоматическое подтверждение:|Текущая DNS-схема отличается;|Останавливаю текущие экземпляры |Текущие экземпляры https-dns-proxy остановлены|Пересобираю DNS-секции |Удаляется DNS-секция:|Старых DNS-секций удалено:|Конфигурация https-dns-proxy сохранена|Обновляю конфигурацию dnsmasq|Конфигурация dnsmasq обновлена|Включаю одновременный опрос DNS|Запускаю https-dns-proxy с выбранными экземплярами|Перезапускаю dnsmasq|Вывод команды перезапуска dnsmasq:|Перезапуск dnsmasq: udhcpc: (started|broadcasting discover)|Повторно проверяю параметры dnsmasq|Обновляю правила firewall|Firewall обновлён|Выполняю итоговое обнаружение|Итоговое обнаружение завершено|Проверяю dnsmasq, все локальные|Все локальные проверки после применения пройдены)/ {print}
    ' /var/log/dns-manager.log 2>/dev/null | tail -n "$_n" || true)"
    _system_log=""
    if command -v logread >/dev/null 2>&1; then
        _system_log="$(logread -e 'dns-manager:' 2>/dev/null | grep -vE 'dns-manager: Проверка DNS: проверено [0-9]+, проблем: 0\.$' | tail -n "$_n" || true)"
    fi
    _log_text=""
    [ -z "$_manager_log" ] || _log_text="Журнал DNS Manager:
$_manager_log"
    if [ -n "$_system_log" ]; then
        [ -z "$_log_text" ] || _log_text="$_log_text

"
        _log_text="${_log_text}Фоновая проверка и события DNS Manager:
$_system_log"
    fi
    printf '{"ok":true'; page_header_json
    printf ',"log":'; json_quote "$_log_text"; printf '}'
}

catalog_json() {
    _category="$(jget category)"; _offset="$(jget offset)"; _limit="$(jget limit)"; _only_ok="$(jget only_ok)"
    _protocol=all
    case "$_category" in native:*) _protocol=native; _category=${_category#native:};; doh:*) _protocol=doh; _category=${_category#doh:};; esac
    case "$_offset" in ''|*[!0-9]*) _offset=0;; esac; case "$_limit" in ''|*[!0-9]*) _limit=18;; esac; [ "$_limit" -gt 48 ] && _limit=48; [ -n "$_category" ] || _category=all
    case "$_category" in all|bypass|security|privacy|adblock|family|clean|gaming|regional|custom) ;; *) json_error "Неверная категория DNS"; return;; esac
    case "$_only_ok" in 1|0) ;; *) _only_ok=0;; esac
    [ -s "$CATALOG_FILE" ] || [ -s "$CUSTOM_CATALOG_FILE" ] || { json_error "Каталог DNS недоступен"; return; }
    _filtered="$TMP_ROOT/catalog-filtered.$$"; _paged="$TMP_ROOT/catalog-page.$$"; : > "$_filtered"; : > "$_paged"
    _native_catalog=''
    if [ "$(uci -q get dns-manager.global.active_engine 2>/dev/null)" = dnscrypt-proxy2 ]; then
        _native_catalog=/etc/dns-manager/config/dnscrypt-native-catalog.conf
        [ -r "$_native_catalog" ] || _native_catalog=/usr/lib/dns-manager-luci/dnscrypt/dns-manager-dnscrypt-catalog.conf
    fi
    for _catalog_source in "$CATALOG_FILE" "$CUSTOM_CATALOG_FILE" "$_native_catalog"; do
        [ -r "$_catalog_source" ] || continue
        while IFS='|' read -r _id _cat _prof _name _url _region _status; do
            case "$_id" in ''|\#*) continue;; esac
            [ "$_category" = all ] || [ "$_cat" = "$_category" ] || continue
            case "$_protocol:$_url" in native:sdns://*|doh:https://*|all:*) ;; *) continue;; esac
            if [ "$_only_ok" = 1 ]; then _r="$(result_for_id "$_id" 2>/dev/null || true)"; _st="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"; [ "$_st" = OK ] || continue; fi
            printf '%s|%s|%s|%s|%s|%s|%s\n' "$_id" "$_cat" "$_prof" "$_name" "$_url" "$_region" "$_status" >> "$_filtered"
        done < "$_catalog_source"
    done
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

device_dns_slot_id() {
    case "$1" in
        1) printf '%s' "${SLOT_1:-}" ;; 2) printf '%s' "${SLOT_2:-}" ;;
        3) printf '%s' "${SLOT_3:-}" ;; 4) printf '%s' "${SLOT_4:-}" ;;
        5) printf '%s' "${SLOT_5:-}" ;; 6) printf '%s' "${SLOT_6:-}" ;;
        *) return 1 ;;
    esac
}
device_dns_slot_port() {
    case "$1" in
        1) printf '%s' "${PORT_1:-}" ;; 2) printf '%s' "${PORT_2:-}" ;;
        3) printf '%s' "${PORT_3:-}" ;; 4) printf '%s' "${PORT_4:-}" ;;
        5) printf '%s' "${PORT_5:-}" ;; 6) printf '%s' "${PORT_6:-}" ;;
        *) return 1 ;;
    esac
}

set_device_dns_json() {
    DMD_RPC_MAC="$(printf '%s' "${1:-}" | tr 'A-F' 'a-f')"
    DMD_RPC_RAW_SLOTS="${2:-}"
    if [ -n "$DMD_RPC_RAW_SLOTS" ]; then
        printf '%s' "$DMD_RPC_RAW_SLOTS" | awk '
            { gsub(/[[:space:]]/, ""); if ($0 !~ /^[1-6](,[1-6])*$/) bad=1 }
            END { exit bad ? 1 : 0 }
        ' || { json_error "Список DNS должен содержать номера слотов 1–6 через запятую"; return; }
    fi
    printf '%s\n' "$DMD_RPC_MAC" | awk '
        /^[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]:[[:xdigit:]][[:xdigit:]]$/ { ok=1 }
        END { exit ok ? 0 : 1 }
    ' || { json_error "Неверный MAC-адрес устройства"; return; }

    DMD_RPC_SLOTS=""
    for DMD_RPC_SLOT in $(printf '%s' "$DMD_RPC_RAW_SLOTS" | tr ',' ' '); do
        case "$DMD_RPC_SLOT" in 1|2|3|4|5|6) ;; *) json_error "Выберите DNS 1–6"; return ;; esac
        case " $DMD_RPC_SLOTS " in
            *" $DMD_RPC_SLOT "*) ;;
            *) DMD_RPC_SLOTS="${DMD_RPC_SLOTS:+$DMD_RPC_SLOTS }$DMD_RPC_SLOT" ;;
        esac
    done
    if [ -n "$DMD_RPC_SLOTS" ]; then
        DMD_RPC_SLOTS="$(printf '%s\n' $DMD_RPC_SLOTS | sort -n -u | tr '\n' ',' | sed 's/,$//')"
    fi

    load_manager || { json_error "DNS Manager недоступен"; return; }
    for DMD_RPC_SLOT in $(printf '%s' "$DMD_RPC_SLOTS" | tr ',' ' '); do
        DMD_RPC_ID="$(device_dns_slot_id "$DMD_RPC_SLOT" 2>/dev/null || true)"
        DMD_RPC_PORT="$(device_dns_slot_port "$DMD_RPC_SLOT" 2>/dev/null || true)"
        [ -n "$DMD_RPC_ID" ] && [ -n "$DMD_RPC_PORT" ] || {
            json_error "Сначала назначьте DNS в выбранный слот: DNS $DMD_RPC_SLOT"
            return
        }
        listener_port_exists "$DMD_RPC_PORT" || {
            json_error "Выбранный DNS $DMD_RPC_SLOT сейчас не слушает порт $DMD_RPC_PORT. Проверьте DoH и повторите."
            return
        }
    done

    acquire_mutation_lock || { json_error "Другая операция DNS Manager уже выполняется"; return; }
    load_manager || {
        release_mutation_lock
        json_error "Не удалось перечитать выбранные DNS"
        return
    }
    for DMD_RPC_SLOT in $(printf '%s' "$DMD_RPC_SLOTS" | tr ',' ' '); do
        DMD_RPC_ID="$(device_dns_slot_id "$DMD_RPC_SLOT" 2>/dev/null || true)"
        DMD_RPC_PORT="$(device_dns_slot_port "$DMD_RPC_SLOT" 2>/dev/null || true)"
        [ -n "$DMD_RPC_ID" ] && [ -n "$DMD_RPC_PORT" ] && listener_port_exists "$DMD_RPC_PORT" || {
            release_mutation_lock
            json_error "Слот DNS $DMD_RPC_SLOT изменился или его DoH не слушает порт. Обновите страницу и повторите."
            return
        }
    done

    DMD_RPC_FILE="/etc/dns-manager/config/device-dns.conf"
    mkdir -p "$(dirname "$DMD_RPC_FILE")" || {
        release_mutation_lock
        json_error "Не удалось создать каталог привязок"
        return
    }
    DMD_RPC_TMP="$(mktemp "$DMD_RPC_FILE.tmp.XXXXXX" 2>/dev/null)" || { release_mutation_lock; json_error "Не удалось создать временный файл привязок"; return; }
    DMD_RPC_BACKUP="$(mktemp "$DMD_RPC_FILE.backup.XXXXXX" 2>/dev/null)" || { rm -f "$DMD_RPC_TMP"; release_mutation_lock; json_error "Не удалось создать резервную копию привязок"; return; }
    DMD_RPC_HAD_FILE=0
    if [ -f "$DMD_RPC_FILE" ]; then
        DMD_RPC_HAD_FILE=1
        cp -p "$DMD_RPC_FILE" "$DMD_RPC_BACKUP" || {
            rm -f "$DMD_RPC_TMP" "$DMD_RPC_BACKUP"
            release_mutation_lock
            json_error "Не удалось сохранить прежние привязки"
            return
        }
    else
        : > "$DMD_RPC_BACKUP"
    fi
    : > "$DMD_RPC_TMP" || {
        rm -f "$DMD_RPC_BACKUP"
        release_mutation_lock
        json_error "Не удалось подготовить файл привязок"
        return
    }
    if [ -r "$DMD_RPC_FILE" ]; then
        awk -F '|' -v mac="$DMD_RPC_MAC" '$1 != mac {print}' "$DMD_RPC_FILE" > "$DMD_RPC_TMP" || {
            rm -f "$DMD_RPC_TMP" "$DMD_RPC_BACKUP"
            release_mutation_lock
            json_error "Не удалось прочитать прежние привязки"
            return
        }
    fi
    if [ -n "$DMD_RPC_SLOTS" ]; then
        printf '%s|%s\n' "$DMD_RPC_MAC" "$DMD_RPC_SLOTS" >> "$DMD_RPC_TMP"
    fi
    sort -t '|' -k1,1 "$DMD_RPC_TMP" -o "$DMD_RPC_TMP" || {
        rm -f "$DMD_RPC_TMP" "$DMD_RPC_BACKUP"
        release_mutation_lock
        json_error "Не удалось отсортировать привязки"
        return
    }
    chmod 0600 "$DMD_RPC_TMP" 2>/dev/null || true
    mv -f "$DMD_RPC_TMP" "$DMD_RPC_FILE" || {
        rm -f "$DMD_RPC_TMP" "$DMD_RPC_BACKUP"
        release_mutation_lock
        json_error "Не удалось сохранить привязку"
        return
    }

    if [ ! -x /etc/init.d/dns-manager-device-dns ] || ! /etc/init.d/dns-manager-device-dns restart >/dev/null 2>&1; then
        if [ "$DMD_RPC_HAD_FILE" = 1 ]; then
            mv -f "$DMD_RPC_BACKUP" "$DMD_RPC_FILE" 2>/dev/null || true
        else
            rm -f "$DMD_RPC_FILE" "$DMD_RPC_BACKUP" 2>/dev/null || true
        fi
        [ ! -x /etc/init.d/dns-manager-device-dns ] || /etc/init.d/dns-manager-device-dns restart >/dev/null 2>&1 || true
        release_mutation_lock
        json_error "Привязку не удалось применить. Устройство оставлено на обычном DNS-маршруте."
        return
    fi
    rm -f "$DMD_RPC_BACKUP"
    release_mutation_lock
    json_ok
}

uninstall_status_json() {
    _un_result="/var/run/dns-manager-uninstall/result"
    if [ -r "$_un_result" ]; then
        _un_code="$(cat "$_un_result" 2>/dev/null)"
        case "$_un_code" in 0) _un_state=done ;; *) _un_state=failed ;; esac
    else
        _un_state=running
    fi
    printf '{"ok":true,"status":'
    json_quote "$_un_state"
    printf ',"output":'
    json_quote "$(tail -n 30 /var/run/dns-manager-uninstall/output 2>/dev/null | tr '\n' ' ' || true)"
    printf ',"phase":'
    json_quote "$(cat /var/run/dns-manager-uninstall/phase 2>/dev/null || true)"
    printf '}'
}

uninstall_start_json() {
    [ -x "$MANAGER" ] || { json_error "DNS Manager недоступен"; return; }
    if ubus call service list '{"name":"dns-manager-uninstall"}' 2>/dev/null | grep -qE '"running"[[:space:]]*:[[:space:]]*true'; then
        json_error "Удаление уже выполняется"
        return
    fi
    _un_dir="/var/run/dns-manager-uninstall"
    [ ! -L "$_un_dir" ] || { json_error "Недопустимый каталог удаления"; return; }
    mkdir -p "$_un_dir" && chmod 0700 "$_un_dir" || { json_error "Не удалось подготовить удаление"; return; }
    rm -f "$_un_dir/result" "$_un_dir/output" "$_un_dir/phase" || { json_error "Не удалось подготовить журнал удаления"; return; }
    _un_web_dir="$(mktemp -d /www/dns-manager-uninstall.XXXXXX)" || { json_error "Не удалось подготовить отображение результата удаления"; return; }
    if ! chmod 0755 "$_un_web_dir" || ! printf '%s\n' '{"status":"running"}' > "$_un_web_dir/status.json" || ! chmod 0644 "$_un_web_dir/status.json"; then
        rm -f "$_un_web_dir/status.json"; rmdir "$_un_web_dir" 2>/dev/null
        json_error "Не удалось подготовить отображение результата удаления"
        return
    fi
    # The worker is a separate procd service so it survives rpcd reload while
    # its own LuCI plugin is being removed. No user input enters the command.
    _un_command='sleep 2; DNS_MANAGER_UNINSTALL_PROGRESS=1 SILENT_APPLY=1 /usr/bin/dns-manager --uninstall > /var/run/dns-manager-uninstall/output 2>&1; rc=$?; echo "$rc" > /var/run/dns-manager-uninstall/result; if [ "$rc" = 0 ]; then printf "%s\\n" "{\"status\":\"done\"}" > "$1/status.json"; else printf "%s\\n" "{\"status\":\"failed\"}" > "$1/status.json"; fi; sleep 120; rm -f "$1/status.json"; rmdir "$1" 2>/dev/null; ubus call service delete "{\"name\":\"dns-manager-uninstall\"}" >/dev/null 2>&1'
    _un_request="$(printf '%s' '{"name":"dns-manager-uninstall","instances":{"main":{"command":["/bin/sh","-c",'; json_quote "$_un_command"; printf '%s' ',"dns-manager-uninstall",'; json_quote "$_un_web_dir"; printf '%s' ']}}}')"
    if ! ubus call service set "$_un_request" >/dev/null 2>&1; then
        rm -f "$_un_web_dir/status.json"; rmdir "$_un_web_dir" 2>/dev/null
        json_error "Не удалось запустить удаление"
        return
    fi
    printf '{"ok":true,"status_url":'
    json_quote "/${_un_web_dir##*/}/status.json"
    printf '}'
}

apply_live_setting() {
    local _als_name _als_value _als_rc
    _als_name="$1"; _als_value="$2"; _als_rc=0
    acquire_mutation_lock || return 1
    if ! load_config >/dev/null 2>&1; then
        release_mutation_lock
        return 1
    fi
    case "$_als_name" in
        force)
            if [ "$_als_value" = 0 ] && [ "${FORCE_DOH:-0}" != 1 ]; then release_mutation_lock; return 0; fi
            FORCE_DOH="$_als_value" ;;
        encrypted_dns) BLOCK_EXTERNAL_DNS="$_als_value" ;;
        browser_dns) set_browser_dns_hint "$_als_value" || _als_rc=$?; release_mutation_lock; return "$_als_rc" ;;
        *) release_mutation_lock; return 1 ;;
    esac
    SILENT_APPLY=1 _apply_extras_now_impl "$_als_name" >/dev/null 2>&1 || _als_rc=$?
    release_mutation_lock
    return "$_als_rc"
}

run_action() {
    _profile="$(jget profile)"
    if [ "${DNSMGR_ACTION_WORKER:-0}" != 1 ]; then
        case "${RPC_METHOD:-}" in set_slot|set_slot_domains|set_device_dns|set_cache|reset_dns|set_ntp|set_bootstrap|add_custom_dns|delete_custom_dns|set_watchdog_setting|set_watchdog_settings|set_test_age) job_start_action "$RPC_METHOD"; return;; esac
    fi
    case "${RPC_METHOD:-}" in
        set_bootstrap)
            DNSMGR_BOOTSTRAP_MODE="$(jget mode)"; DNSMGR_BOOTSTRAP_INPUT="$(jget addresses)"
            DNSMGR_BOOTSTRAP_IDS="$(jget preset_ids)"; DNSMGR_BOOTSTRAP_EXTRA="$(jget extra_addresses)"
            case "$DNSMGR_BOOTSTRAP_MODE" in
                default) DNSMGR_BOOTSTRAP_INPUT=''; DNSMGR_BOOTSTRAP_IDS=''; DNSMGR_BOOTSTRAP_EXTRA='' ;;
                cloudflare) DNSMGR_BOOTSTRAP_IDS=cloudflare; DNSMGR_BOOTSTRAP_EXTRA=''; DNSMGR_BOOTSTRAP_INPUT='1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001' ;;
                google) DNSMGR_BOOTSTRAP_IDS=google; DNSMGR_BOOTSTRAP_EXTRA=''; DNSMGR_BOOTSTRAP_INPUT='8.8.8.8,8.8.4.4,2001:4860:4860::8888,2001:4860:4860::8844' ;;
                quad9) DNSMGR_BOOTSTRAP_IDS=quad9; DNSMGR_BOOTSTRAP_EXTRA=''; DNSMGR_BOOTSTRAP_INPUT='9.9.9.9,149.112.112.112,2620:fe::fe,2620:fe::9' ;;
                custom) [ -n "$DNSMGR_BOOTSTRAP_INPUT" ] || { json_error 'Введите IP-адреса bootstrap DNS'; return; } ;;
                *) json_error 'Неверный набор bootstrap DNS'; return ;;
            esac
            load_manager || { json_error 'DNS Manager недоступен'; return; }
            type bootstrap_metadata_supported >/dev/null 2>&1 || { json_error 'Обновите backend DNS Manager для сохранения выбранных наборов'; return; }
            acquire_mutation_lock || { json_error 'Другая операция DNS Manager уже выполняется'; return; }
            load_config >/dev/null 2>&1 || { release_mutation_lock; json_error 'Не удалось загрузить настройки'; return; }
            if bootstrap_apply_selection "$DNSMGR_BOOTSTRAP_INPUT" "$DNSMGR_BOOTSTRAP_IDS" "$DNSMGR_BOOTSTRAP_EXTRA" >/dev/null 2>&1; then
                release_mutation_lock; json_ok
            else
                DNSMGR_BOOTSTRAP_ERROR="${BOOTSTRAP_ERROR:-Не удалось применить bootstrap DNS}"
                release_mutation_lock; json_error "$DNSMGR_BOOTSTRAP_ERROR"
            fi
            ;;
        add_custom_dns)
            add_custom_dns_json
            ;;
        delete_custom_dns)
            delete_custom_dns_json
            ;;
        set_cache)
            CACHE_REQUEST_TOTAL="$(jget total)"; CACHE_REQUEST_TTL="$(jget ttl)"
            for CACHE_N in "$CACHE_REQUEST_TOTAL" "$CACHE_REQUEST_TTL"; do
                case "$CACHE_N" in ''|*[!0-9]*|0[0-9]*) json_error 'Введите целые значения кэша и TTL'; return;; esac
                [ "${#CACHE_N}" -le 5 ] || { json_error 'Значение слишком велико'; return; }
            done
            [ "$CACHE_REQUEST_TOTAL" -le 10000 ] && [ "$CACHE_REQUEST_TTL" -le 3600 ] || { json_error 'Кэш: 0–10000 записей, TTL: 0–3600 секунд'; return; }
            load_manager || { json_error 'DNS Manager недоступен'; return; }
            type dns_cache_total_supported >/dev/null 2>&1 || { json_error 'Для настройки кэша обновите backend DNS Manager из тестовой ветки'; return; }
            acquire_mutation_lock || { json_error 'Другая операция DNS Manager уже выполняется'; return; }
            CACHE_GUARD=/usr/lib/dns-manager-luci/cache/uci-read-guard.sh
            CACHE_TX=/usr/lib/dns-manager-luci/cache/cache-transaction.sh
            if ! sh "$CACHE_GUARD" dhcp /bin/true >/dev/null 2>&1; then
                release_mutation_lock; json_error 'Есть несохранённые изменения DHCP. Завершите их применение и повторите.'; return
            fi
            CACHE_FILE=/etc/dns-manager/config/cache.conf
            mkdir -p /etc/dns-manager/config || { release_mutation_lock; json_error 'Не удалось создать каталог настроек'; return; }
            CACHE_TMP="$(mktemp "$CACHE_FILE.tmp.XXXXXX")" || { release_mutation_lock; json_error 'Не удалось подготовить настройки'; return; }
            CACHE_BACK="$(mktemp "$CACHE_FILE.backup.XXXXXX")" || { rm -f "$CACHE_TMP"; release_mutation_lock; json_error 'Не удалось сохранить прежние настройки'; return; }
            CACHE_HAD=0
            if [ -f "$CACHE_FILE" ]; then CACHE_HAD=1; cp -p "$CACHE_FILE" "$CACHE_BACK" || { rm -f "$CACHE_TMP" "$CACHE_BACK"; release_mutation_lock; json_error 'Не удалось сохранить прежние настройки'; return; }; fi
            printf 'total=%s\nttl=%s\n' "$CACHE_REQUEST_TOTAL" "$CACHE_REQUEST_TTL" > "$CACHE_TMP"
            chmod 0600 "$CACHE_TMP" && mv -f "$CACHE_TMP" "$CACHE_FILE" || { rm -f "$CACHE_TMP" "$CACHE_BACK"; release_mutation_lock; json_error 'Не удалось записать настройки'; return; }
            if ! CACHE_OUTPUT="$(sh "$CACHE_TX" '@dnsmasq[0]' "$CACHE_REQUEST_TOTAL" "$CACHE_REQUEST_TTL" "$CACHE_GUARD" /etc/init.d/dnsmasq restart 2>&1)"; then
                if [ "$CACHE_HAD" = 1 ]; then mv -f "$CACHE_BACK" "$CACHE_FILE"; else rm -f "$CACHE_FILE" "$CACHE_BACK"; fi
                release_mutation_lock; json_error 'Не удалось применить кэш. Проверьте состояние dnsmasq и незавершённые изменения DHCP.'; return
            fi
            rm -f "$CACHE_BACK"
            release_mutation_lock; json_ok
            ;;
        set_device_dns)
            set_device_dns_json "$(jget mac)" "$(jget slots)"
            ;;
        set_profile)
            case "$_profile" in clean2) _profile=clean;; bypass|clean|security|privacy|adblock|family|all|dnssec) ;; *) json_error "Неверный профиль"; return;; esac
            job_start_profile "$_profile"
            ;;
        set_regional)
            job_start_regional "$(jget enabled)"
            ;;
        reset_dns)
            load_manager || { json_error "DNS Manager недоступен"; return; }
            _reset_mode="$(jget mode)"
            case "$_reset_mode" in
                disable) if disable_https_dns >/dev/null 2>&1; then json_ok; else json_error "Не удалось отключить защищённый DNS"; fi ;;
                ''|default) if SILENT_APPLY=1 restore_dns_core >/dev/null 2>&1 && /etc/init.d/https-dns-proxy enable >/dev/null 2>&1; then json_ok; else json_error "Не удалось восстановить стандартные DNS"; fi ;;
                *) json_error "Неверное действие" ;;
            esac
            ;;
        uninstall)
            uninstall_start_json
            ;;
        set_slot)
            RPC_SLOT="$(jget slot)"; RPC_ID="$(jget id)"; RPC_EXPECTED="$(jget expected)"
            case "$RPC_SLOT" in 1|2|3|4|5|6|RU) ;; *) json_error "Неверный слот"; return;; esac
            case "$RPC_ID" in *[!A-Za-z0-9_-]*) json_error "Неверный DNS ID"; return;; esac
            load_manager || { json_error "DNS Manager недоступен"; return; }
            acquire_mutation_lock || { json_error "Другая операция DNS Manager уже выполняется"; return; }
            load_config >/dev/null 2>&1 || { release_mutation_lock; json_error "Не удалось загрузить настройки"; return; }
            _slot="$RPC_SLOT"; _id="$RPC_ID"
            if [ -z "$RPC_ID" ]; then
                case "$RPC_SLOT" in RU) release_mutation_lock; json_error "Региональный DNS меняется в настройках регионального DNS"; return;; esac
                eval "_remove_id=\${SLOT_${RPC_SLOT}:-}"
                [ -n "$_remove_id" ] || { release_mutation_lock; json_error "Слот уже пуст"; return; }
                [ -n "$RPC_EXPECTED" ] && [ "$RPC_EXPECTED" = "$_remove_id" ] || { release_mutation_lock; json_error "DNS в слоте изменился. Обновите страницу и повторите."; return; }
                _remaining=0
                for _check_slot in 1 2 3 4 5 6; do
                    [ "$_check_slot" = "$RPC_SLOT" ] && continue
                    eval "_check_id=\${SLOT_${_check_slot}:-}"
                    [ -z "$_check_id" ] || _remaining=$((_remaining+1))
                done
                [ "$_remaining" -gt 0 ] || { release_mutation_lock; json_error "Последний общий DNS удалить нельзя. Для отключения используйте восстановление стандартной настройки DNS."; return; }
                for _bindings in /etc/dns-manager/config/device-dns.conf /etc/dns-manager/config/device-dns-default.conf; do
                    [ -r "$_bindings" ] || continue
                    if awk -F '[|,[:space:]]+' -v slot="$RPC_SLOT" '{for (i=2;i<=NF;i++) if ($i==slot) found=1} END {exit !found}' "$_bindings"; then
                        release_mutation_lock; json_error "Слот используется в привязке устройств. Сначала измените привязку."; return
                    fi
                done
                eval "SLOT_${RPC_SLOT}=''"
                slot_cat_set "$RPC_SLOT" "" || { release_mutation_lock; json_error "Не удалось освободить слот"; return; }
                _old_hybrid_stage_skip="${HYBRID_STAGE_SKIP:-0}"
                [ "$DNS_PROFILE" = hybrid ] && HYBRID_STAGE_SKIP=1
                _rc=0
                if SILENT_APPLY=1 CORE_ONLY=1 SKIP_POST_APPLY_VERIFY=1 DNS_MANAGER_NO_UPDATE=1 _apply_settings_impl >/dev/null 2>&1; then _rc=0; else _rc=$?; fi
                HYBRID_STAGE_SKIP="$_old_hybrid_stage_skip"
                release_mutation_lock
                [ "$_rc" -eq 0 ] && json_ok || json_error "Не удалось удалить DNS из слота"
                return
            fi
            _cat="$(dns_cat "$RPC_ID" 2>/dev/null || true)"; [ -n "$_cat" ] || { release_mutation_lock; json_error "DNS не найден в каталоге"; return; }
            for _check_slot in 1 2 3 4 5 6 RU; do
                [ "$_check_slot" = "$RPC_SLOT" ] && continue
                _check_id="$(cfg_get "SLOT_$_check_slot")"
                if [ -n "$_check_id" ] && [ "$_check_id" = "$RPC_ID" ]; then
                    release_mutation_lock
                    json_error "DNS уже назначен в слоте $_check_slot"
                    return
                fi
            done
            case "$RPC_SLOT" in RU) [ "$_cat" = regional ] || { release_mutation_lock; json_error "Этот DNS нельзя поставить в региональный слот"; return; } ;; *) [ "$_cat" != regional ] || { release_mutation_lock; json_error "Региональный DNS нельзя поставить в общий слот"; return; } ;; esac
            eval "SLOT_${RPC_SLOT}=\"$RPC_ID\""
            slot_cat_set "$RPC_SLOT" "$_cat" || { release_mutation_lock; json_error "Не удалось сохранить категорию DNS"; return; }
            if [ "$RPC_SLOT" = RU ]; then SLOT_RU_CAT=regional; REGIONAL_MODE=legacy; fi
            sync_profile_from_selected_categories >/dev/null
            _old_hybrid_stage_skip="${HYBRID_STAGE_SKIP:-0}"
            [ "$DNS_PROFILE" = hybrid ] && HYBRID_STAGE_SKIP=1
            _rc=0
            if install_missing_dependencies >/dev/null 2>&1; then _rc=0; else _rc=$?; fi
            if [ "$_rc" -eq 0 ]; then
                if SILENT_APPLY=1 CORE_ONLY=1 SKIP_POST_APPLY_VERIFY=1 DNS_MANAGER_NO_UPDATE=1 _apply_settings_impl >/dev/null 2>&1; then _rc=0; else _rc=$?; fi
            fi
            HYBRID_STAGE_SKIP="$_old_hybrid_stage_skip"
            release_mutation_lock
            [ "$_rc" -eq 0 ] && json_ok || json_error "DNS не удалось применить"
            ;;
        set_slot_domains)
            RPC_SLOT="$(jget slot)"; RPC_DOMAINS="$(jget domains)"
            case "$RPC_SLOT" in 1|2|3|4|5|6) ;; *) json_error "Неверный слот DNS"; return;; esac
            load_manager || { json_error "DNS Manager недоступен"; return; }
            if slot_domains_apply "$RPC_SLOT" "$RPC_DOMAINS"; then
                json_ok
            else
                json_error "${SLOT_DOMAINS_ERROR:-Не удалось применить список доменов}"
            fi
            ;;
        set_ntp)
            _preset="$(jget preset)"
            case "$_preset" in
                vniiftri_moscow|nist_ip|cf_ip|google_ip) ;;
                *) json_error "Неверный набор серверов точного времени"; return;;
            esac
            DNSMGR_NTP_REQUEST="$_preset"
            load_manager || { json_error "DNS Manager недоступен"; return; }
            acquire_mutation_lock || { json_error "Другая операция DNS Manager уже выполняется"; return; }
            load_config >/dev/null 2>&1 || { release_mutation_lock; json_error "Не удалось загрузить настройки"; return; }
            NTP_PRESET="$DNSMGR_NTP_REQUEST"
            if apply_ntp_ip_fallback >/dev/null 2>&1; then
                NTP_PRESET_USER_SET=1
                save_config >/dev/null 2>&1 || { release_mutation_lock; json_error "Набор серверов времени применён, но выбор не удалось сохранить"; return; }
                release_mutation_lock
                json_ok
            else
                release_mutation_lock
                json_error "Не удалось применить выбранный набор серверов времени"
            fi
            ;;
        set_test_age)
            _category="$(jget category)"; _hours="$(jget hours)"
            case "$_category" in all|bypass|clean|security|privacy|adblock|family|gaming|regional) ;; *) json_error "Неверная категория DNS"; return;; esac
            case "$_hours" in ''|*[!0-9]*) json_error "Неверный срок проверки"; return;; esac
            [ "$_hours" -ge 1 ] 2>/dev/null && [ "$_hours" -le 168 ] 2>/dev/null || { json_error "Срок проверки должен быть от 1 до 168 часов"; return; }
            DNSMGR_AGE_CATEGORY="$_category"; DNSMGR_AGE_HOURS="$_hours"
            load_manager || { json_error "DNS Manager недоступен"; return; }
            acquire_mutation_lock || { json_error "Другая операция DNS Manager уже выполняется"; return; }
            load_config >/dev/null 2>&1 || { release_mutation_lock; json_error "Не удалось загрузить настройки"; return; }
            _category="$DNSMGR_AGE_CATEGORY"; _hours="$DNSMGR_AGE_HOURS"
            _expected="$((_hours*3600))"
            if [ "$_category" = all ]; then
                TEST_RESULTS_MAX_AGE="$_expected"
                for _age_var in TEST_RESULTS_MAX_AGE_BYPASS TEST_RESULTS_MAX_AGE_CLEAN TEST_RESULTS_MAX_AGE_SECURITY TEST_RESULTS_MAX_AGE_PRIVACY TEST_RESULTS_MAX_AGE_ADBLOCK TEST_RESULTS_MAX_AGE_FAMILY TEST_RESULTS_MAX_AGE_GAMING TEST_RESULTS_MAX_AGE_REGIONAL; do
                    eval "$_age_var=$_expected"
                done
                save_config >/dev/null 2>&1 || { release_mutation_lock; json_error "Срок проверки не удалось сохранить"; return; }
                _saved="$(cfg_get TEST_RESULTS_MAX_AGE)"
            else
                _var="TEST_RESULTS_MAX_AGE_$(printf '%s' "$_category" | tr '[:lower:]' '[:upper:]')"
                eval "$_var=$_expected"
                save_config >/dev/null 2>&1 || { release_mutation_lock; json_error "Срок проверки не удалось сохранить"; return; }
                _saved="$(cfg_get "$_var")"
            fi
            [ "$_saved" = "$_expected" ] || { release_mutation_lock; json_error "Срок проверки не сохранился"; return; }
            release_mutation_lock
            json_ok
            ;;
        set_setting)
            _name="$(jget name)"
            _enabled="$(jget enabled)"
            case "$_enabled" in
                0|1) ;;
                *) json_error "Неверное значение enabled"; return;;
            esac
            case "$_name" in
                watchdog|watchdog_autoreplace|force|encrypted_dns|browser_dns|dnsmasq_perf) ;;
                *) json_error "Недопустимая настройка"; return;;
            esac
            if [ "${DNSMGR_SETTING_WORKER:-0}" != 1 ]; then
                job_start_setting "$_name" "$_enabled"; return
            fi
            DNSMGR_SETTING_REQUEST_NAME="$_name"
            DNSMGR_SETTING_REQUEST_VALUE="$_enabled"
            load_manager || { json_error "DNS Manager недоступен"; return; }
            _name="$DNSMGR_SETTING_REQUEST_NAME"
            _enabled="$DNSMGR_SETTING_REQUEST_VALUE"
            _rc=0
            case "$_name" in
                watchdog|watchdog_autoreplace)
                    # Serialize the controls with Watchdog recovery and other
                    # DNS changes, then decide using the current configuration.
                    DNSMGR_WD_REQUEST_NAME="$_name"
                    DNSMGR_WD_REQUEST_VALUE="$_enabled"
                    if ! acquire_mutation_lock; then
                        _rc=1
                    else
                        if ! load_config >/dev/null 2>&1; then
                            _rc=1
                        elif [ "$DNSMGR_WD_REQUEST_NAME" = watchdog ]; then
                            SILENT_APPLY=1 watchdog_apply_toggle "$DNSMGR_WD_REQUEST_VALUE" >/dev/null 2>&1 || _rc=$?
                        else
                            watchdog_apply_autoreplace_toggle "$DNSMGR_WD_REQUEST_VALUE" >/dev/null 2>&1 || _rc=$?
                        fi
                        release_mutation_lock
                    fi
                    ;;
                force)
                    if apply_live_setting force "$DNSMGR_SETTING_REQUEST_VALUE"; then _rc=0; else _rc=$?; fi
                    if [ "$_rc" -eq 0 ]; then
                        force_readback_json
                        return
                    fi
                    if [ "$DNSMGR_SETTING_REQUEST_VALUE" = 1 ]; then
                        detect_steer_dns_path >/dev/null 2>&1 || true
                        if [ "${STEER_DNS_ACTIVE:-0}" = 1 ] && [ -n "${SLOT_1:-}${SLOT_2:-}${SLOT_3:-}${SLOT_4:-}${SLOT_5:-}${SLOT_6:-}${SLOT_RU:-}" ] && ! (steer_dns_upstream_ready); then
                            json_error "Steer активен, но текущие DNS-серверы dnsmasq не совпадают с выбранными в DNS Manager. Проверьте применённый DNS-профиль."
                            return
                        fi
                    fi
                    ;;
                encrypted_dns)
                    if apply_live_setting encrypted_dns "$DNSMGR_SETTING_REQUEST_VALUE"; then _rc=0; else _rc=$?; fi
                    ;;
                browser_dns)
                    if apply_live_setting browser_dns "$DNSMGR_SETTING_REQUEST_VALUE"; then _rc=0; else _rc=$?; fi
                    ;;
                dnsmasq_perf)
                    if [ -f /etc/dns-manager/config/cache.conf ]; then json_error 'Используйте настройки кэша на вкладке «Сеть»'; return; fi
                    DNSMASQ_PERF="$_enabled"
                    SILENT_APPLY=1 apply_extras_now dnsmasq_perf >/dev/null 2>&1 || _rc=$?
                    ;;
            esac
            [ "$_rc" -eq 0 ] || { json_error "Настройку «$_name» не удалось применить"; return; }
            json_ok
            ;;
        set_watchdog_setting)
            _name="$(jget name)"
            _value="$(jget value)"
            watchdog_apply_single "$_name" "$_value"
            ;;
        set_watchdog_settings)
            watchdog_apply_batch
            ;;
        *) json_error "Недопустимый метод";;
    esac
}

watchdog_restore_service_state() {
    if [ "$1" = 1 ]; then watchdog_service_start_enable; else watchdog_service_stop_disable; fi
}

# Batch only methods already available to the read-only ACL. Dispatch through
# the installed rpcd executable so engine-specific status stays authoritative.
multi_json() {
    _multi_calls="$(jget calls)"
    _multi_count=0
    for _multi_method in $_multi_calls; do
        case "$_multi_method" in status|runtime|doh_status|network_status|time_status|page_meta) ;; *) json_error "Недопустимый метод"; return;; esac
        _multi_count=$((_multi_count + 1))
        [ "$_multi_count" -le 4 ] || { json_error "Слишком много методов"; return; }
    done
    [ "$_multi_count" -gt 0 ] || { json_error "Не указаны методы"; return; }
    printf '{"ok":true,"results":{'
    _multi_sep=''
    for _multi_method in $_multi_calls; do
        _multi_result="$(printf '%s' '{}' | /usr/libexec/rpcd/dns_manager call "$_multi_method" 2>/dev/null)" || _multi_result=''
        case "$_multi_result" in \{*\}) ;; *) _multi_result='{"ok":false}';; esac
        printf '%s"%s":%s' "$_multi_sep" "$_multi_method" "$_multi_result"
        _multi_sep=','
    done
    printf '}}'
}
test_json() { case "${RPC_METHOD:-}" in test_all) job_start_test_all;; test_page) job_start_test test_page "$(jget ids)";; test_current) job_start_test_current;; test_one) job_start_test_one "$(jget id)";; test_system) job_start_test_system;; *) json_error "Недопустимый метод проверки";; esac; }

case "${1:-}" in
    worker) background_worker "$2";;
    mutation_worker) mutation_worker "$2" "$3" "$4";;
    test_worker) test_worker "$2" "$3";;
    list)
        printf '{"status":{},"runtime":{},"doh_status":{},"network_status":{},"lan_devices":{},"set_device_dns":{"mac":"String","slots":"String"},"set_cache":{"total":0,"ttl":0},"time_status":{},"page_meta":{},"catalog":{"category":"String","offset":0,"limit":0,"only_ok":0},"update_check":{"force":0},"update":{},"update_manager":{},"update_hdp":{},"update_catalog":{},"update_all":{},"update_background":{},"test_combined":{},"switch_engine":{"target_engine":"String"},"dnscrypt_test":{},"dnscrypt_latencies":{"ids":"String"},"dnscrypt_cancel":{},"test_page":{"ids":"String"},"test_page_cancel":{},"dnscrypt_log":{},"system_dns_test":{},"set_profile":{"profile":"String"},"set_regional":{"enabled":0},"reset_dns":{"mode":"String"},"uninstall":{},"uninstall_status":{},"set_slot":{"slot":"String","id":"String","expected":"String"},"set_slot_domains":{"slot":"String","domains":"String"},"add_custom_dns":{"name":"String","url":"String"},"delete_custom_dns":{"id":"String"},"set_setting":{"name":"String","enabled":0},"set_bootstrap":{"mode":"String","addresses":"String","preset_ids":"String","extra_addresses":"String"},"set_watchdog_setting":{"name":"String","value":0},"set_watchdog_settings":{"interval":0,"threshold":0,"repair_cooldown":0,"max_restarts":0,"guard_interval":0},"set_ntp":{"preset":"String"},"set_test_age":{"category":"String","hours":0},"test_all":{},"test_current":{},"test_one":{"id":"String"},"test_system":{},"job":{"id":"String"},"job_status":{"id":"String"},"multi":{"calls":"String"},"log":{"lines":0}}\n'
        ;;
    call)
        case "${2:-}" in
            status) INPUT="$(cat 2>/dev/null || true)"; status_json;;
            doh_status) doh_status_json;;
            network_status) network_status_json;;
            lan_devices) lan_devices_json;;
            time_status) time_status_json;;
            page_meta) page_meta_json;;
            runtime) runtime_json;;
            catalog) INPUT="$(cat 2>/dev/null || true)"; catalog_json;;
            update_check) INPUT="$(cat 2>/dev/null || true)"; job_start_version_check;;            update_catalog) update_catalog_json;;            update_all) update_all_json;;            update) update_json;;            update_manager) update_manager_json;;            update_hdp) update_hdp_json;;
            update_background) background_start update;;
            test_combined) background_start combined;;
            add_custom_dns|delete_custom_dns|set_device_dns|set_cache|reset_dns|uninstall|set_profile|set_regional|set_slot|set_slot_domains|set_setting|set_bootstrap|set_watchdog_setting|set_watchdog_settings|set_ntp|set_test_age) INPUT="$(cat 2>/dev/null || true)"; RPC_METHOD="$2"; run_action;;
            uninstall_status) uninstall_status_json;;
            test_page_cancel) cat >/dev/null; if job_active test_page; then : > "$JOB_DIR/test_page/cancel"; fi; printf '{"ok":true}\n';;
            test_all|test_page|test_current|test_one|test_system) INPUT="$(cat 2>/dev/null || true)"; RPC_METHOD="$2"; test_json;;
            job|job_status) INPUT="$(cat 2>/dev/null || true)"; job_json "$(jget id)";;
            multi) INPUT="$(cat 2>/dev/null || true)"; multi_json;;
            log) INPUT="$(cat 2>/dev/null || true)"; log_json "$(jget lines)";;
            *) json_error "Недопустимый метод";;
        esac
        ;;
    *) exit 1;;
esac
EOF_RPC
    if ! sh -n "$BACKEND_STAGE" >/dev/null 2>&1; then
        rm -f "$BACKEND_STAGE" 2>/dev/null || true
        err "Сгенерированный LuCI backend не прошёл shell-проверку."
        return 1
    fi
    chmod 0755 "$BACKEND_STAGE"
    mv -f "$BACKEND_STAGE" "$BACKEND_FILE" || {
        rm -f "$BACKEND_STAGE" 2>/dev/null || true
        err "Не удалось заменить LuCI backend."
        return 1
    }
    RPC_STAGE="${RPC_PLUGIN}.new.$$"
    rm -f "$RPC_STAGE" 2>/dev/null || true
    cat > "$RPC_STAGE" <<'EOF_RPC_WRAPPER'
#!/bin/sh
# DNS Manager LuCI rpcd plugin
# Fail closed if the selected engine has no backend; do not run the other one.
if [ "${1:-}" = call ] && { [ "${2:-}" = switch_engine ] || [ "${2:-}" = system_dns_test ]; }; then
    exec /usr/lib/dns-manager-luci/backend-dnscrypt.sh "$@"
fi
ENGINE_FILE="/etc/dns-manager/config/dnscrypt-engine"
ENGINE='https-dns-proxy'
if [ -e "$ENGINE_FILE" ] || [ -L "$ENGINE_FILE" ]; then
    [ -r "$ENGINE_FILE" ] || { printf '{"ok":false,"error":"DNS engine selection is unreadable"}'; exit 1; }
    ENGINE="$(cat "$ENGINE_FILE")" || { printf '{"ok":false,"error":"DNS engine selection is unreadable"}'; exit 1; }
fi
case "$ENGINE" in
    https-dns-proxy) BACKEND="/usr/lib/dns-manager-luci/backend.sh" ;;
    dnscrypt-proxy2) BACKEND="/usr/lib/dns-manager-luci/backend-dnscrypt.sh" ;;
    *) printf '{"ok":false,"error":"Unknown DNS engine"}'; exit 1 ;;
esac
[ -x "$BACKEND" ] || { printf '{"ok":false,"error":"Selected DNS engine backend not found"}'; exit 1; }
exec "$BACKEND" "$@"
EOF_RPC_WRAPPER
    chmod 0755 "$RPC_STAGE"
    mv -f "$RPC_STAGE" "$RPC_PLUGIN" || {
        rm -f "$RPC_STAGE" 2>/dev/null || true
        err "Не удалось заменить LuCI RPC plugin."
        return 1
    }

    COMMON_STAGE="$COMMON_FILE.new.$$"
    rm -f "$COMMON_STAGE" 2>/dev/null || true
    cat > "$COMMON_STAGE" <<'EOF_COMMON'
'use strict';
'require baseclass';
'require rpc';
'require ui';
'require session';

// DNS Manager LuCI common module version: 2.78
function dmRpc(o){
  var fn=rpc.declare(o);
  return function(){
    var self=this,args=arguments,left=6;
    function go(){
      return fn.apply(self,args).catch(function(e){
        var msg=String((e&&e.message)||e||'');
        if(left-- > 0 && /Object not found/i.test(msg))
          return new Promise(function(resolve){setTimeout(resolve,1500);}).then(go);
        throw e;
      });
    }
    return go();
  };
}
var callStatus = dmRpc({ object:'dns_manager', method:'status', params:['detail'], expect:{} });
var callDohStatus = dmRpc({ object:'dns_manager', method:'doh_status', expect:{} });
var callMulti = dmRpc({ object:'dns_manager', method:'multi', params:['calls'], expect:{} });
var callNetworkStatus = dmRpc({ object:'dns_manager', method:'network_status', expect:{} });
var callLanDevices = dmRpc({ object:'dns_manager', method:'lan_devices', expect:{} });
var callSetDeviceDns = dmRpc({ object:'dns_manager', method:'set_device_dns', params:['mac','slots'], expect:{} });
var callSetCache = dmRpc({ object:'dns_manager', method:'set_cache', params:['total','ttl'], expect:{} });
var callTimeStatus = dmRpc({ object:'dns_manager', method:'time_status', expect:{} });
var callPageMeta = dmRpc({ object:'dns_manager', method:'page_meta', expect:{} });
var callBoardInfo = rpc.declare({ object:'system', method:'info', expect:{} });
var callRuntime = dmRpc({ object:'dns_manager', method:'runtime', expect:{} });
function statusDetail(){return currentRoute()==='network'?1:0;}
var callCatalog = dmRpc({ object:'dns_manager', method:'catalog', params:['category','offset','limit','only_ok'], expect:{} });
var callUpdateCheck = dmRpc({ object:'dns_manager', method:'update_check', params:['force'], expect:{} });
var callBackgroundUpdate = dmRpc({ object:'dns_manager', method:'update_background', expect:{} });
var callCombinedTest = dmRpc({ object:'dns_manager', method:'test_combined', expect:{} });
var callUpdate = dmRpc({ object:'dns_manager', method:'update', expect:{} });
var callManagerUpdate = dmRpc({ object:'dns_manager', method:'update_manager', expect:{} });
var callHdpUpdate = dmRpc({ object:'dns_manager', method:'update_hdp', expect:{} });
var callUpdateCatalog = dmRpc({ object:'dns_manager', method:'update_catalog', expect:{} });
var callProfile = dmRpc({ object:'dns_manager', method:'set_profile', params:['profile'], expect:{} });
var callRegional = dmRpc({ object:'dns_manager', method:'set_regional', params:['enabled'], expect:{} });
var callResetDns = dmRpc({ object:'dns_manager', method:'reset_dns', params:['mode'], expect:{} });
var callSystemDnsTest = dmRpc({ object:'dns_manager', method:'system_dns_test', expect:{} });
var callDnscryptTest = dmRpc({ object:'dns_manager', method:'dnscrypt_test', expect:{} });
var callDnscryptLatencies = dmRpc({ object:'dns_manager', method:'dnscrypt_latencies', params:['ids'], expect:{} });
var callDnscryptLog = dmRpc({ object:'dns_manager', method:'dnscrypt_log', expect:{} });
var callSwitchEngine = dmRpc({ object:'dns_manager', method:'switch_engine', params:['target_engine'], expect:{} });
var callUninstall = dmRpc({ object:'dns_manager', method:'uninstall', expect:{} });
var callUninstallStatus = rpc.declare({ object:'dns_manager', method:'uninstall_status', expect:{} });
var callSlot = dmRpc({ object:'dns_manager', method:'set_slot', params:['slot','id','expected'], expect:{} });
var callSlotDomains = dmRpc({ object:'dns_manager', method:'set_slot_domains', params:['slot','domains'], expect:{} });
var callAddCustomDns = dmRpc({ object:'dns_manager', method:'add_custom_dns', params:['name','url'], expect:{} });
var callDeleteCustomDns = dmRpc({ object:'dns_manager', method:'delete_custom_dns', params:['id'], expect:{} });
var callSetting = dmRpc({ object:'dns_manager', method:'set_setting', params:['name','enabled'], expect:{} });
var callBootstrap = dmRpc({ object:'dns_manager', method:'set_bootstrap', params:['mode','addresses','preset_ids','extra_addresses'], expect:{} });
var callWatchdogSettings = dmRpc({ object:'dns_manager', method:'set_watchdog_settings', params:['interval','threshold','repair_cooldown','max_restarts','guard_interval'], expect:{} });
var callNtp = dmRpc({ object:'dns_manager', method:'set_ntp', params:['preset'], expect:{} });
var callTestAge = dmRpc({ object:'dns_manager', method:'set_test_age', params:['category','hours'], expect:{} });
var callDnscryptCancel = dmRpc({ object:'dns_manager', method:'dnscrypt_cancel', expect:{} });
var callTestPage = dmRpc({ object:'dns_manager', method:'test_page', params:['ids'], expect:{} });
var callTestPageCancel = dmRpc({ object:'dns_manager', method:'test_page_cancel', expect:{} });
var callTestAll = dmRpc({ object:'dns_manager', method:'test_all', expect:{} });
var callTestCurrent = dmRpc({ object:'dns_manager', method:'test_current', expect:{} });
var callTestOne = dmRpc({ object:'dns_manager', method:'test_one', params:['id'], expect:{} });
var callTestSystem = dmRpc({ object:'dns_manager', method:'test_system', expect:{} });
var callJob = dmRpc({ object:'dns_manager', method:'job_status', params:['id'], expect:{} });
var callLog = dmRpc({ object:'dns_manager', method:'log', params:['lines'], expect:{} });

var PROFILE = [
  ['bypass','Обход геоблока'], ['clean','Без фильтрации'],
  ['security','Защита от угроз'], ['privacy','Конфиденциальность'],
  ['adblock','Блокировка рекламы'], ['family','Семейная фильтрация'], ['dnssec','DNSSEC']
];
var CATEGORY = [
  ['all','Все DNS'], ['bypass','Обход геоблока'], ['security','Защита от угроз'], ['privacy','Конфиденциальность'],
  ['adblock','Блокировка рекламы'], ['family','Семейная фильтрация'], ['clean','Без фильтрации'], ['gaming','Игровые DNS'], ['regional','Региональные DNS'], ['custom','Мои DNS']
];
var state = { slotPickerCheck:null, slotPickerRequest:0, lanDevicesLoading:false, lanDevicesMessage:'', luciUpdateReloadTimer:null, hdpUpdating:false, managerUpdating:false, updatingAll:false, category:'all', catalogProtocol:'native', offset:0, limit:18, catalogLoaded:false, catalogLoading:false, advanced:true, logLoaded:false, logLoading:false, busy:false, busySetting:'', settingMessage:'', settingMessageType:'', settingMessageKey:'', pageNotice:{}, statusError:'', activeTab:'dashboard', jobRunning:false, lastJob:null, checking:{}, fullTest:null, catalogProgress:null, profileProgress:null, profileOutput:'', versionCheck:null, lastAction:null, runtimeCpuLoad:null, runtimeMemoryTotal:null, runtimeMemoryAvailable:null, boardInfo:null, systemPollBusy:false, profileResumeStarted:false };

function profileName(p){
  if(String(p||'').indexOf('options:')===0)p=String(p).split(':').slice(3).join(':');
  var x=PROFILE.filter(function(v){return v[0]===p;})[0];
  return x?x[1]:(p==='default'?'DNS по умолчанию':p==='hybrid'?'Обход геоблока':p==='custom'?'Собственный выбор':p==='none'?'Не выбран':(p||'—'));
}
function isProfileId(p){
  for(var i=0;i<PROFILE.length;i++)if(PROFILE[i][0]===p)return true;
  return false;
}
function activeProfileId(st){
  st=st||{};
  if(st.dnscrypt_engine==='dnscrypt-proxy2')return isProfileId(st.dnscrypt_profile)?st.dnscrypt_profile:'';
  var mode=String(st.profile_mode||'').toLowerCase();
  var category=String(st.selection_category||'').toLowerCase();
  if(mode==='profile' && isProfileId(category))return category;
  var profile=String(st.profile||'').toLowerCase();
  if(isProfileId(profile))return profile;
  if(profile==='hybrid' && category==='bypass')return 'bypass';
  return '';
}
function activeProfileLabel(st){
  st=st||{};
  var id=activeProfileId(st);
  if(id)return profileName(id);
  if(st.dnscrypt_engine==='dnscrypt-proxy2')return st.dnscrypt_selected_server?dnscryptServerName(st,st.dnscrypt_selected_server):profileName('none');
  if(String(st.profile_mode||'').toLowerCase()==='profile'){
    var category=String(st.selection_category||'').toLowerCase();
    if(category==='all')return 'Все категории';
  }
  return profileName(st.profile);
}
function catName(c){ if(c==='unknown')return 'DNSCrypt'; var x=CATEGORY.filter(function(v){return v[0]===c;})[0]; return x?x[1]:(c||'—'); }
function ping(v){ return v && /^\d+$/.test(String(v)) ? v+' мс' : '—'; }
function uptime(sec){
  var n=Number(sec);
  if(!isFinite(n)||n<0)return '—';
  n=Math.floor(n);
  var d=Math.floor(n/86400);n%=86400;
  var h=Math.floor(n/3600);n%=3600;
  var m=Math.floor(n/60);var s=Math.floor(n%60);
  return (d?d+' дн ':'')+(d||h?h+' ч ':'')+m+' мин '+s+' с';
}
function memory(total,avail){ var t=Number(total||0),a=Number(avail||0); if(!t)return '—'; return Math.max(0,Math.round((t-a)/1024))+' / '+Math.round(t/1024)+' МБ'; }
function memoryPercent(total,avail){
  var t=Number(total||0),a=Number(avail||0);
  if(!isFinite(t)||t<=0||!isFinite(a))return null;
  var p=Math.round(((t-Math.max(0,a))/t)*100);
  return Math.max(0,Math.min(100,p));
}
function loadPercent(load1,cores){
  var n=Number(load1),c=Number(cores||1);
  if(!isFinite(n)||n<0||!isFinite(c)||c<1)return null;
  var p=Math.round((n/c)*100);
  return Math.max(0,Math.min(100,p));
}
function badge(kind,text){ return E('span',{'class':'dm-badge '+kind},[E('span',{'class':'dm-dot'}),text]); }
function btn(label,cls,fn,extra){ var a={'class':'cbi-button '+(cls||''),'type':'button','click':function(ev){ if(ev&&ev.preventDefault)ev.preventDefault(); return fn?fn.call(this,ev):undefined; }}; Object.keys(extra||{}).forEach(function(k){ if(k==='disabled'){ if(extra[k]) a.disabled=true; } else { a[k]=extra[k]; } }); return E('button',a,label); }
function row(label,node){ return E('div',{'class':'dm-row'},[E('span',{'class':'dm-label'},label),E('span',{'class':'dm-row-value'},node)]); }
function card(title,children,cls){ return E('div',{'class':'dm-card '+(cls||'')},[E('h3',{},title)].concat(children||[])); }
function forceMode(st){
  if(st.force!==undefined && st.force!==null)return yes(st.force)?'auto':'off';
  return (st.force_status==='manager'||st.force_status==='steer')?'auto':'off';
}
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
function setSettingFeedback(key,msg,type){
  state.settingMessageKey=String(key||'');
  state.settingMessage=String(msg||'');
  state.settingMessageType=type||'info';
}
function clearSettingFeedback(){
  state.settingMessageKey='';
  state.settingMessage='';
  state.settingMessageType='';
}
function settingFeedback(label,key){
  if(String(state.settingMessageKey||'')!==String(key||''))return null;
  var msg=String(state.settingMessage||'');
  if(!msg)return null;
  return E('span',{'class':'dm-setting-feedback '+(state.settingMessageType||'info')},msg);
}
function setAction(ok,text,kind){state.lastAction={ok:!!ok,text:String(text||''),kind:String(kind||((ok===true)?'ok':'error'))};}
function renderActionStatus(){
  var action=state.lastAction&&state.lastAction.text?{
    kind:state.lastAction.kind||((state.lastAction.ok===true)?'ok':'error'),
    text:state.lastAction.text
  }:null;
  if(!action)return null;
  return E('div',{'class':'dm-applied '+action.kind},[
    E('strong',{},action.kind==='running'?'Выполняется':(action.kind==='ok'?'Успешно':'Ошибка')),
    E('span',{},action.text)
  ]);
}
function stripAnsi(s){
  return String(s||'')
    .replace(/\x1B\[[0-?]*[ -\/]*[@-~]/g,'')
    .replace(/\[[0-9;?]*[ -\/]*[@-~]/g,'')
    .replace(/[0-9]+(?:;[0-9]+)*m/g,'')
    .replace(/\r/g,'');
}
function rpcErrorText(err){
  var msg='';
  if(err){
    if(typeof err==='string')msg=err;
    else msg=err.message||err.error||err.description||'';
    if(!msg&&err.code!==undefined)msg='код '+err.code;
  }
  msg=stripAnsi(msg).replace(/\s+/g,' ').trim();
  return msg.length>220?msg.slice(0,217)+'…':msg;
}
function withRpcError(fallback,err){
  var d=rpcErrorText(err);
  return d?fallback+' '+d:fallback;
}
function hasPing(v){ return /^\d+$/.test(String(v===undefined||v===null?'':v)); }
function stateBadge(status,pingValue){
  var s=String(status||'').toUpperCase();
  if(s==='RUNNING')return badge('dm-warn','проверяется…');
  if(!s)return badge('dm-off','нет данных');
  if(s==='OK')return badge('dm-ok',hasPing(pingValue)?ping(pingValue)+' · доступен':'ответ получен');
  return badge('dm-bad','недоступен');
}
function settingName(n){ var m={watchdog:'Проверка DNS',watchdog_autoreplace:'Автозамена DNS',force:'Принудительный DNS',browser_dns:'Подсказка браузерам',encrypted_dns:'Не давать устройствам обходить блокировку',dnsmasq_perf:'Увеличенный кэш DNS',dc_cache:'Кэш DNSCrypt',dc_cache_size:'Размер кэша DNSCrypt',dc_cache_ttl:'Время хранения DNSCrypt',dc_force_tcp:'Только TCP',dc_block_ipv6:'Блокировать IPv6-ответы',dc_block_unqualified:'Блокировать короткие имена',dc_block_undelegated:'Блокировать локальные домены',dc_query_log:'Журнал запросов'}; return m[n]||n; }
function settingModuleState(st,key){
  var raw=st[key+'_state'];
  if(raw===undefined||raw===null||raw==='')return -1;
  var n=Number(raw);
  return n===1?1:n===2?2:0;
}
function settingStateView(st,key){
  var ms=settingModuleState(st,key);
  if(ms===1)return {kind:'dm-ok',text:'включено'};
  if(ms===2)return {kind:'dm-bad',text:'другое'};
  if(ms===0)return {kind:'dm-off',text:'выключено'};
  return yes(st[key])?{kind:'dm-ok',text:'включено'}:{kind:'dm-off',text:'выключено'};
}
function versionState(v,available,latest,checked,okWord,pending,error){
  if(pending)return badge('dm-warn','проверяется…');
  if(!v)return badge('dm-bad','не установлена');
  if(error)return E('span',{'class':'dm-version-error'},[badge('dm-bad','ошибка'),E('span',{'class':'dm-version-error-text'},String(error).slice(0,180))]);
  if(yes(checked)&&yes(available))return badge('dm-warn',shortVal(v)+' → '+shortVal(latest||'новая версия')+' · неактуальна');
  if(yes(checked))return badge('dm-ok',shortVal(v)+' · '+okWord);
  return badge('dm-off',shortVal(v)+' · проверка не выполнена');
}
function catalogVersionState(v,rev,total,available,latest,latestRev,checked,pending,error){
  if(pending)return badge('dm-warn','проверяется…');
  if(!v)return badge('dm-bad','не установлен');
  if(error)return E('span',{'class':'dm-version-error'},[badge('dm-bad','ошибка'),E('span',{'class':'dm-version-error-text'},String(error).slice(0,180))]);
  var local=shortVal(v)+(rev?' rev.'+shortVal(rev):'');
  if(yes(checked)&&yes(available)){
    var tail=latest?shortVal(latest):'новая версия';
    if(latestRev)tail+=' rev.'+shortVal(latestRev);
    return badge('dm-warn',local+' → '+tail+' · неактуален');
  }
  if(yes(checked)&&latest)return badge('dm-ok',local+' · актуален');
  return badge('dm-off',local+' · проверка не выполнена');
}

function hasAvailableUpdates(st){
  return (yes(st.manager_check_ok)&&!st.manager_update_error&&yes(st.manager_update_available)) ||
    (yes(st.luci_update_checked)&&!st.luci_update_error&&yes(st.luci_update_available)) ||
    (yes(st.catalog_check_ok)&&!st.catalog_update_error&&yes(st.catalog_update_available)) ||
    (st.dnscrypt_engine!=='dnscrypt-proxy2'&&yes(st.hdp_check_ok)&&yes(st.hdp_update_available));
}

function injectStyle(root){
  var css = ''+
  '.dm-wrap{display:flex;flex-direction:column;gap:12px;width:100%;max-width:none;box-sizing:border-box;padding-bottom:28px}'+
  '.dm-header{display:flex;align-items:center;gap:9px;flex-wrap:wrap}.dm-header h2{margin:0;font-size:13px;font-weight:600}.dm-header-by{font-size:13px;opacity:.60}.dm-header-actions{display:flex;gap:7px;margin-left:auto;flex-wrap:wrap}.dm-header-actions .cbi-button{padding:5px 11px;font-size:12.5px}'+
  '.dm-load-wrap{min-width:220px;max-width:430px;width:100%}.dm-load-line{display:flex;align-items:center;gap:9px}.dm-load-track{height:8px;flex:1;min-width:120px;border-radius:999px;background:rgba(110,118,129,.16);overflow:hidden}.dm-load-fill{height:100%;border-radius:999px;background:#1a7f37;transition:width .25s ease}.dm-load-value{min-width:38px;font-size:12px;font-weight:700;text-align:right}.dm-load-meta{font-size:10.5px;opacity:.58;margin-top:3px}'+
  '.dm-mem-wrap{min-width:220px;max-width:430px;width:100%}.dm-mem-line{display:flex;align-items:center;gap:9px}.dm-mem-track{height:8px;flex:1;min-width:120px;border-radius:999px;background:rgba(110,118,129,.16);overflow:hidden}.dm-mem-fill{height:100%;border-radius:999px;background:#1a7f37;transition:width .25s ease}.dm-mem-value{font-size:12px;font-weight:700;white-space:nowrap}.dm-mem-meta{font-size:10.5px;opacity:.58;margin-top:3px}'+
  ".dm-test-age-list{display:flex;flex-direction:column;gap:0;margin:0;padding:0}.dm-test-age-row{display:grid;grid-template-columns:minmax(0,1fr) 90px 20px;align-items:center;gap:8px;min-height:36px;margin:0;padding:3px 0;border:0!important}.dm-test-age-label{font-size:13px;font-weight:600;white-space:nowrap}.dm-test-age-unit,.dm-watchdog-unit{font-size:12px;opacity:.62;white-space:nowrap}.dm-test-age-common{display:flex;align-items:center;gap:8px;flex-wrap:wrap}.dm-test-age-common .dm-input{width:60px!important;min-width:60px!important;margin:0;box-sizing:border-box}.dm-test-age-common .cbi-button{margin:0}.dm-test-age-row .dm-input{width:90px!important;margin:0;box-sizing:border-box}.dm-test-age-list + .dm-actions{margin-top:10px}.dm-watchdog-list{display:flex;flex-direction:column;gap:1px;margin-top:5px}.dm-watchdog-row{display:grid;grid-template-columns:minmax(180px,1fr) 105px 90px;align-items:center;gap:9px;min-height:36px;padding:3px 0}.dm-watchdog-row .dm-setting-title{font-size:12.5px}.dm-setting-range{font-size:11px;opacity:.55;white-space:nowrap}.dm-watchdog-row .dm-input{width:105px!important;margin:0;box-sizing:border-box}.dm-watchdog-save{display:flex;align-items:center;gap:9px;flex-wrap:wrap;margin-top:12px}.dm-watchdog-save .cbi-button{padding:5px 12px;font-size:12.5px}.dm-watchdog-advanced{margin-top:8px;border-top:1px solid rgba(110,118,129,.14);padding-top:8px}.dm-watchdog-advanced>summary{cursor:pointer;font-size:12.5px;font-weight:600;opacity:.72;list-style:none}.dm-watchdog-advanced>summary::-webkit-details-marker{display:none}.dm-watchdog-advanced>summary:before{content:'▸';display:inline-block;margin-right:6px;transition:transform .15s ease}.dm-watchdog-advanced[open]>summary:before{transform:rotate(90deg)}.dm-setting-feedback{font-size:11.5px;line-height:1.3;white-space:nowrap}.dm-setting-feedback.ok{color:#1a7f37}.dm-setting-feedback.error{color:#cf222e}.dm-setting-feedback.info{opacity:.65}"+
  '.dm-card{min-width:0;box-sizing:border-box;background:var(--background-color-medium,#fff);border:1px solid rgba(0,0,0,.08);border-radius:11px;padding:15px 18px;box-shadow:0 1px 3px rgba(0,0,0,.04),0 1px 2px rgba(0,0,0,.03);overflow-wrap:break-word}.dm-card:hover{box-shadow:0 2px 7px rgba(0,0,0,.06)}'+
  'html[data-darkmode="true"] .dm-card{background:#1c2128;border-color:rgba(255,255,255,.10);box-shadow:0 1px 3px rgba(0,0,0,.22)}'+
  '.dm-version-action{display:flex;align-items:center;gap:7px;flex-wrap:wrap}.dm-version-action .cbi-button{padding:4px 9px;font-size:12px}.dm-version-error{display:inline-flex;align-items:center;gap:7px;flex-wrap:wrap}.dm-version-error-text{font-size:11.5px;opacity:.72}.dm-version-line{display:flex;align-items:center;gap:9px;margin:7px 0;flex-wrap:wrap}.dm-version-name{font-size:13px;font-weight:600;flex:0 1 160px;min-width:135px}.dm-version-state{min-width:0;flex:1 1 auto}.dm-card h3{margin:0 0 10px;font-size:15px;font-weight:600;display:flex;align-items:center;gap:7px;flex-wrap:wrap}.dm-doh-profile{display:inline-flex;align-items:center;gap:5px;margin-left:auto;padding:4px 9px;border:1px solid rgba(110,118,129,.18);border-radius:999px;background:rgba(110,118,129,.06);font-size:11.5px;font-weight:500;white-space:nowrap}.dm-doh-profile-label{opacity:.62}.dm-doh-profile-value{font-weight:650}.dm-row{display:flex;align-items:center;gap:10px;margin:6px 0;font-size:13px;flex-wrap:wrap}.dm-label{opacity:.65;flex-shrink:0}.dm-row-value{overflow-wrap:anywhere}'+
  '.dm-badge{display:inline-flex;align-items:center;gap:6px;padding:3px 10px;border-radius:999px;font-size:12px;font-weight:600;white-space:nowrap}.dm-dot{width:8px;height:8px;border-radius:50%;display:inline-block;flex-shrink:0}'+
  '.dm-ok{background:rgba(46,160,67,.12);color:#1a7f37}.dm-ok .dm-dot{background:#1a7f37}.dm-bad{background:rgba(207,34,46,.10);color:#cf222e}.dm-bad .dm-dot{background:#cf222e}.dm-warn{background:rgba(191,135,0,.12);color:#9a6700}.dm-warn .dm-dot{background:#9a6700}.dm-off{background:rgba(9,105,218,.10);color:#0969da}.dm-off .dm-dot{background:#0969da}.dm-muted{background:transparent;color:inherit;opacity:.6}.dm-muted .dm-dot{background:currentColor}'+
  '.dm-engine-choices{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,240px),1fr));gap:12px;margin:14px 0}.dm-engine-choice{display:flex;flex-direction:column;align-items:flex-start;gap:10px;padding:16px;border:1px solid rgba(110,118,129,.24);border-radius:12px;background:rgba(110,118,129,.04)}.dm-engine-choice-head{display:flex;align-items:center;gap:8px;flex-wrap:wrap}.dm-engine-choice{width:100%;text-align:left;color:inherit;font:inherit;cursor:pointer;transition:border-color .18s,background-color .18s,box-shadow .18s}.dm-engine-choice:hover:not(:disabled){border-color:rgba(35,134,54,.7);background:rgba(35,134,54,.08)}.dm-engine-choice:focus-visible{outline:2px solid #238636;outline-offset:2px}.dm-engine-choice:disabled{cursor:default;opacity:1}.dm-engine-choice-head{width:100%;justify-content:space-between}.dm-engine-choice-action{color:#35a86a;font-size:.85em}.dm-engine-selected{border-color:rgba(35,134,54,.55);background:rgba(35,134,54,.06)}'+
  '.dm-grid2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.dm-system-card{margin-bottom:0}.dm-system-layout{display:flex;flex-direction:column;gap:10px}.dm-system-rows{min-width:0}.dm-system-meters{min-width:0;width:100%}.dm-system-meter{padding:7px 0}.dm-system-meter-head{display:flex;align-items:center;justify-content:space-between;gap:10px;font-size:12.5px}.dm-system-meter-head strong{font-size:12px;white-space:nowrap}.dm-system-meter-track{height:8px;margin-top:6px;border-radius:999px;background:rgba(110,118,129,.16);overflow:hidden}.dm-system-meter-track i{display:block;height:100%;border-radius:999px;background:#1a7f37;transition:width .25s ease}.dm-system-hint{font-size:10.5px;opacity:.58;margin-top:3px}.dm-grid3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}.dm-grid4{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}'+
  '.dm-actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:11px}.dm-slot-picker-categories{gap:5px;margin:0 0 9px}.dm-slot-picker-categories .cbi-button{padding:4px 8px;font-size:11.5px}.dm-picker-list{display:flex;flex-direction:column;gap:7px;max-height:60vh;overflow:auto}.dm-picker-item{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:8px 0;border-bottom:1px solid rgba(110,118,129,.14)}.dm-picker-main{min-width:0;flex:1}.dm-picker-name{font-size:13px;font-weight:600;overflow-wrap:anywhere}.dm-picker-meta{display:flex;align-items:center;gap:6px;flex-wrap:wrap;margin-top:3px}.dm-picker-actions{display:flex;gap:6px;flex-shrink:0;flex-wrap:wrap}.dm-component-item{padding:8px 0;border-bottom:1px solid rgba(110,118,129,.14)}.dm-component-group{padding:8px 0;border-bottom:1px solid rgba(110,118,129,.14)}.dm-component-dns-list{margin-top:6px;display:flex;flex-direction:column;gap:5px}.dm-component-dns{display:flex;align-items:center;justify-content:space-between;gap:10px;padding:6px 0;border-top:1px solid rgba(110,118,129,.08);flex-wrap:wrap}.dm-component-dns:first-child{border-top:0}.dm-component-dns-main{display:flex;align-items:center;gap:8px;min-width:0;flex:1 1 260px}.dm-component-dns-slot{font-size:11.5px;font-weight:700;opacity:.62;min-width:118px}.dm-component-dns-name{font-size:12.5px;font-weight:600;overflow-wrap:anywhere}.dm-component-dns-meta{display:flex;align-items:center;gap:9px;font-size:11.5px;opacity:.78;flex:0 0 auto}.dm-component-dns-ping{font-size:12px;white-space:nowrap;opacity:.8}.dm-component-item:last-of-type{border-bottom:0}.dm-component-head{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap}.dm-component-title{font-size:13px;font-weight:600}.dm-component-details{font-size:11.5px;line-height:1.45;opacity:.66;margin-top:3px;overflow-wrap:anywhere}.dm-component-date{font-size:12.5px;opacity:.82}.dm-profile-progress{margin-top:11px}.dm-profile-progress-status{font-size:12.5px;font-weight:600;margin-top:8px}.dm-profile-progress-detail{font-size:11px;opacity:.62;margin-top:4px;overflow-wrap:anywhere}'+'.dm-actions .cbi-button{margin:0;padding:5px 11px;font-size:12.5px}'+
  '.dm-hint{font-size:12.5px;opacity:.68;line-height:1.5;margin:0 0 8px}.dm-mini{font-size:11px;opacity:.62}.dm-meta{font-size:11px;line-height:1.45;opacity:.66}.dm-update{padding:8px 10px;border-radius:8px;background:rgba(26,127,55,.08);border:1px solid rgba(26,127,55,.18);font-size:12.5px;display:flex;gap:8px;align-items:center;flex-wrap:wrap}'+
  '.dm-seg{display:flex;flex-wrap:wrap;gap:6px;margin:5px 0}.dm-profile-seg{flex-wrap:wrap}.dm-seg .cbi-button{padding:5px 11px;border-radius:7px;font-size:12.5px;font-weight:600}'+
  '.dm-force-note{font-size:12px;line-height:1.56;opacity:.72}.dm-inline-msg{display:block;margin:8px 0 0;padding:7px 10px;border-radius:7px;font-size:12px;line-height:1.4}.dm-inline-msg.info{background:rgba(9,105,218,.08);border:1px solid rgba(9,105,218,.16)}.dm-inline-msg.ok{background:rgba(26,127,55,.08);border:1px solid rgba(26,127,55,.16)}.dm-inline-msg.error{background:rgba(207,34,46,.08);border:1px solid rgba(207,34,46,.16)}.dm-applied{display:flex;align-items:center;gap:9px;padding:9px 11px;border-radius:8px;font-size:12.5px;line-height:1.45}.dm-applied.ok{background:rgba(26,127,55,.08);border:1px solid rgba(26,127,55,.18)}.dm-applied.running{background:rgba(191,135,0,.08);border:1px solid rgba(191,135,0,.18)}.dm-applied.error{background:rgba(207,34,46,.08);border:1px solid rgba(207,34,46,.18)}.dm-applied strong{font-weight:700}.dm-confirm-body{min-width:min(440px,calc(100vw - 70px))}.dm-setting{padding:11px 12px}.dm-setting-title{font-size:13px;font-weight:600}.dm-setting-desc{font-size:11.5px;line-height:1.45;opacity:.68;margin-top:3px}.dm-setting-line{display:flex;align-items:center;justify-content:space-between;gap:10px}.dm-setting-text{min-width:0}.dm-setting-controls{display:flex;align-items:center;justify-content:flex-end;gap:7px;margin-top:9px}.dm-setting-actions{display:flex;align-items:center;gap:7px;flex-shrink:0}.dm-setting-actions .cbi-button{padding:4px 9px;font-size:12px}.dm-setting-saving{opacity:.7}.dm-force-external{padding:8px 10px;border-radius:8px;background:rgba(191,135,0,.10);border:1px solid rgba(191,135,0,.22);font-size:12.5px;line-height:1.5;margin-top:8px}'+
  '.dm-doh-list{display:flex;flex-direction:column}.dm-doh-row{display:grid;grid-template-columns:max-content minmax(0,max-content) max-content max-content minmax(0,1fr);gap:8px;align-items:center;padding:7px 0;border-top:1px solid rgba(0,0,0,.07);font-size:13px}.dm-doh-row:first-child{border-top:0}.dm-doh-slot{font-size:12px;white-space:nowrap;opacity:.7}.dm-doh-name{font-weight:600;min-width:0;max-width:260px;overflow-wrap:anywhere}.dm-doh-url{overflow-wrap:anywhere;opacity:.88}.dm-doh-state{white-space:nowrap}.dm-doh-port,.dm-doh-ping{font-size:12px;opacity:.7;white-space:nowrap}.dm-doh-actions{display:flex;gap:6px;justify-content:flex-start;flex-wrap:wrap}.dm-doh-actions .cbi-button{padding:4px 8px;font-size:12px}'+
  '.dm-device-dns-options{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px;margin-top:3px}.dm-device-dns-option{display:flex;align-items:flex-start;gap:9px;min-width:0;min-height:56px;padding:10px;border:1px solid rgba(110,118,129,.24);border-radius:9px;background:rgba(110,118,129,.035);cursor:pointer;font-size:12px;transition:border-color .15s,background .15s}.dm-device-dns-option.is-selected{border-color:var(--primary-color,#0069c7);background:rgba(31,111,235,.07)}.dm-device-dns-option.is-empty{opacity:.55;cursor:default}.dm-device-dns-checkbox{flex:0 0 auto;width:16px;height:16px;margin:2px 0 0;accent-color:var(--primary-color,#0069c7)}.dm-device-dns-option-content{display:flex;flex-direction:column;gap:3px;min-width:0}.dm-device-dns-option-slot{font-size:10.5px;font-weight:700;letter-spacing:.04em;opacity:.68}.dm-device-dns-option-name{font-size:12px;font-weight:600;line-height:1.35;overflow-wrap:anywhere}.dm-slot-entry.dm-device-dns-entry{gap:12px;padding:14px;margin:8px 0 0;border:1px solid rgba(110,118,129,.22);border-radius:11px;background:rgba(110,118,129,.025)}.dm-device-dns-head{display:flex;align-items:center;justify-content:space-between;gap:12px;min-width:0}.dm-device-dns-name{font-size:15px;font-weight:700;line-height:1.35;overflow-wrap:anywhere}.dm-device-dns-status{flex:0 0 auto;padding:4px 8px;border-radius:999px;font-size:10.5px;font-weight:700;white-space:nowrap}.dm-device-dns-status.is-online{color:var(--success-color,#238636);background:rgba(35,134,54,.1)}.dm-device-dns-status.is-offline{color:var(--text-color-high,#666);background:rgba(110,118,129,.1)}.dm-device-dns-meta{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}.dm-device-dns-meta-item{display:flex;flex-direction:column;gap:3px;min-width:0;padding:8px 10px;border-radius:7px;background:rgba(110,118,129,.055)}.dm-device-dns-meta-label{font-size:10.5px;font-weight:700;letter-spacing:.035em;opacity:.62;text-transform:uppercase}.dm-device-dns-meta-value{font-size:12px;line-height:1.4;overflow-wrap:anywhere}.dm-device-dns-mac{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:11.5px}.dm-device-dns-current{display:flex;align-items:flex-start;gap:8px;flex-wrap:wrap;padding:9px 11px;border-radius:8px;background:rgba(110,118,129,.07)}.dm-device-dns-current.has-selection{background:rgba(35,134,54,.075)}.dm-device-dns-current-label{flex:0 0 auto;font-size:11px;font-weight:700;opacity:.75}.dm-device-dns-current-value{min-width:0;font-size:12px;line-height:1.45;overflow-wrap:anywhere}.dm-device-dns-section-title{font-size:12.5px;font-weight:700;margin-bottom:-7px}.dm-device-dns-section-help{font-size:11.5px;opacity:.65;margin-top:-6px}.dm-device-dns-actions{display:flex;justify-content:flex-end;margin-top:1px}.dm-device-dns-save{padding:7px 14px;font-weight:600}.dm-device-dns-note{padding:11px 13px;margin-top:12px;border:1px solid rgba(110,118,129,.18);border-radius:9px;background:rgba(110,118,129,.045)}.dm-device-dns-note-title{font-size:12px;font-weight:700;margin-bottom:5px}.dm-device-dns-note-text{font-size:11.5px;line-height:1.5;opacity:.78;margin-top:3px}.dm-slot-table{display:flex;flex-direction:column}.dm-slot-entry{display:flex;flex-direction:column;gap:4px;border-top:1px solid rgba(0,0,0,.07);padding:6px 0}.dm-slot-entry:first-child{border-top:0}.dm-slot-domain-panel{display:flex;flex-direction:column;gap:5px;padding:0 0 10px 68px}.dm-slot-domains-heading{font-size:12px;font-weight:600}.dm-slot-domains-help{font-size:12px;opacity:.72}.dm-slot-domain-controls{display:flex;align-items:stretch;gap:8px}.dm-slot-domains-input{width:100%;min-width:0;min-height:48px;resize:vertical}.dm-slot-domain-controls .cbi-button{align-self:flex-start;white-space:nowrap}@media(max-width:560px){.dm-slot-domain-panel{padding-left:0}.dm-slot-domain-controls{flex-direction:column}.dm-slot-domain-controls .cbi-button{align-self:flex-start}}.dm-slot-row{display:grid;grid-template-columns:42px minmax(0,max-content) max-content max-content max-content minmax(175px,auto);gap:8px;align-items:center;padding:7px 0;border-top:1px solid rgba(0,0,0,.07);font-size:13px}.dm-slot-row:first-child{border-top:0}.dm-slot-id{font-weight:700;opacity:.62;white-space:nowrap}.dm-slot-name{font-weight:600;min-width:0;max-width:220px;overflow-wrap:anywhere}.dm-slot-endpoint,.dm-slot-ping{font-size:12px;opacity:.72;white-space:nowrap}.dm-inline{display:flex;gap:6px;justify-content:flex-end}.dm-inline .cbi-button{padding:4px 9px;font-size:12px}.dm-assign-list{display:flex;flex-direction:column;gap:7px;min-width:min(430px,calc(100vw - 70px))}.dm-assign-item{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:9px 10px;border:1px solid rgba(0,0,0,.08);border-radius:8px}.dm-assign-info{min-width:0;flex:1}.dm-assign-slot{font-weight:700}.dm-assign-current{font-size:12px;opacity:.7;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}'+
  '.dm-catalog{display:grid;grid-template-columns:repeat(3,minmax(210px,1fr));gap:9px;margin-top:8px}.dm-catalog-item{padding:11px 12px}.dm-catalog-item-custom{grid-column:auto}.dm-catalog-item h4{margin:0 0 4px;font-size:13px;line-height:1.35}.dm-catalog-controls{display:flex;flex-direction:column;gap:8px;margin-top:8px;min-width:0}.dm-catalog-controls-custom{display:flex;flex-direction:row;align-items:center;min-width:0}.dm-catalog-toolbar{display:flex;align-items:center;justify-content:flex-start;gap:8px;min-width:0}.dm-catalog-controls-custom .dm-assign-inline{display:flex;align-items:center;gap:6px;min-width:0;flex-wrap:nowrap;width:100%;flex:1 1 auto}.dm-catalog-controls-custom .dm-assign-inline select{height:30px;min-width:0;width:auto;max-width:100%;flex:1 1 160px;padding:3px 8px;border-radius:7px;border:1px solid rgba(110,118,129,.32);background:var(--background-color-medium,#fff);color:inherit;font-size:12px;box-shadow:none}.dm-assign-inline select:focus{outline:none;box-shadow:none}.dm-assign-inline .cbi-button{padding:5px 10px;font-size:12px;flex:0 0 auto}.dm-page{display:flex;justify-content:center;align-items:center;gap:7px;margin-top:9px}.dm-log{white-space:pre-wrap;max-height:360px;overflow:auto;font:11px/1.45 monospace;padding:10px;background:#111820;color:#dbe4ec;border-radius:8px;margin-top:8px}'+
  '.dm-page-nav{position:sticky;top:0;z-index:20;padding:7px 0;background:var(--background-color-base,#fff);border-bottom:1px solid rgba(0,0,0,.08)}.dm-page-nav::before,.dm-page-nav::after{content:"";position:absolute;left:0;right:0;height:7px;background:var(--background-color-base,#fff);pointer-events:none}.dm-page-nav::before{top:-7px}.dm-page-nav::after{bottom:-7px}.dm-page-tabs{display:flex;align-items:stretch;gap:4px;overflow-x:auto;scrollbar-width:none;padding:0 2px}.dm-page-tabs::-webkit-scrollbar{display:none}.dm-page-tab{flex:0 0 auto;padding:7px 12px!important;border-radius:8px 8px 0 0!important;font-size:12.5px!important;font-weight:600!important;border:1px solid transparent!important;background:transparent!important;box-shadow:none!important}.dm-page-tab:hover{background:rgba(0,0,0,.05)!important}.dm-page-tab.active{background:var(--background-color-medium,#fff)!important;border-color:rgba(0,0,0,.12)!important;border-bottom-color:var(--background-color-medium,#fff)!important}.dm-page-nav-title{display:none}.dm-wrap>section{scroll-margin-top:58px}'+
  '.dm-section-title{font-size:12px;letter-spacing:.02em;text-transform:none;opacity:.62;margin:3px 0 0;padding:0 2px}'+
  '@media(max-width:850px){.dm-test-age-common{flex-wrap:wrap}.dm-grid2{grid-template-columns:1fr}.dm-grid4{grid-template-columns:repeat(2,minmax(0,1fr))}.dm-doh-row{grid-template-columns:max-content minmax(0,max-content) max-content max-content minmax(0,1fr);gap:7px}.dm-doh-name{max-width:220px}.dm-doh-ping{display:block}.dm-slot-row{grid-template-columns:40px minmax(0,max-content) max-content max-content max-content minmax(140px,auto);gap:7px}.dm-slot-name{max-width:190px}.dm-catalog{grid-template-columns:repeat(2,minmax(0,1fr))}}'+
  '@media(max-width:560px){.dm-grid3,.dm-grid4,.dm-catalog{grid-template-columns:1fr}.dm-catalog-item-custom{grid-column:auto}.dm-catalog-controls-custom{flex-direction:column;align-items:stretch}.dm-catalog-controls-custom .dm-assign-inline{flex-wrap:wrap}.dm-catalog-controls-custom .dm-assign-inline select{flex:1 1 100%;width:100%}.dm-header-actions{margin-left:0}.dm-doh-row{grid-template-columns:max-content minmax(0,1fr) max-content max-content;gap:6px}.dm-doh-name{max-width:180px}.dm-doh-actions{grid-column:1/5;justify-content:flex-start}.dm-doh-url{grid-column:1/3}.dm-doh-port{grid-column:1}.dm-slot-row{grid-template-columns:40px minmax(0,1fr) auto}.dm-slot-endpoint{display:none}.dm-slot-state{display:none}.dm-inline{grid-column:2/4;justify-content:flex-start}.dm-device-dns-meta{grid-template-columns:minmax(0,1fr)}.dm-device-dns-options{grid-template-columns:repeat(2,minmax(0,1fr));gap:6px}.dm-device-dns-option{padding:8px;min-height:52px;gap:7px}.dm-device-dns-head{align-items:flex-start}.dm-device-dns-name{font-size:14px}.dm-slot-entry.dm-device-dns-entry{padding:11px;gap:10px}.dm-device-dns-current{flex-direction:column;gap:3px}.dm-device-dns-actions{justify-content:stretch}.dm-device-dns-save{width:100%}}'+
  '.dm-wrap{gap:15px;padding-bottom:32px}'+
  '.dm-wrap .dm-header{align-items:center;gap:8px;padding:13px 15px;border:1px solid rgba(110,118,129,.2);border-radius:13px;background:linear-gradient(135deg,rgba(110,118,129,.075),rgba(110,118,129,.02))}'+
  '.dm-wrap .dm-header h2{font-size:18px;line-height:1.25;font-weight:750;letter-spacing:-.025em;margin-right:3px}'+
  '.dm-wrap .dm-header-by{display:inline-flex;align-items:center;max-width:100%;padding:4px 8px;border:1px solid rgba(110,118,129,.17);border-radius:7px;background:rgba(110,118,129,.055);font-size:11.5px;line-height:1.4;opacity:.82;overflow-wrap:anywhere}'+
  '.dm-wrap .dm-header-by:last-child{flex-basis:100%;padding:0;border:0;border-radius:0;background:transparent;font-size:11.5px;opacity:.67}'+
  '.dm-wrap .dm-card{padding:18px;border:1px solid rgba(110,118,129,.2);border-radius:14px;box-shadow:0 2px 9px rgba(15,23,42,.045);transition:border-color .18s ease,box-shadow .18s ease}'+
  '.dm-wrap .dm-card:hover{border-color:rgba(110,118,129,.3);box-shadow:0 4px 14px rgba(15,23,42,.065)}'+
  '.dm-wrap .dm-card>h3{display:flex;align-items:center;gap:8px;margin:0 0 14px;padding:0 0 11px;border-bottom:1px solid rgba(110,118,129,.16);font-size:14px;line-height:1.4;font-weight:750;letter-spacing:-.012em}'+
  '.dm-wrap .dm-card>h3:before{content:"";display:inline-block;flex:0 0 3px;width:3px;height:15px;border-radius:99px;background:var(--primary-color,#238636)}'+
  '.dm-wrap .dm-grid2,.dm-wrap .dm-grid3,.dm-wrap .dm-grid4{gap:12px}'+
  '.dm-wrap .dm-row{gap:12px;margin:0;padding:9px 0;border-bottom:1px solid rgba(110,118,129,.12);line-height:1.45}'+
  '.dm-wrap .dm-label{font-size:12px;font-weight:650;opacity:.67}'+
  '.dm-wrap .dm-row-value{font-weight:550;min-width:0}'+
  '.dm-wrap .dm-hint{padding:10px 12px;margin:0 0 10px;border-left:3px solid rgba(110,118,129,.28);border-radius:8px;background:rgba(110,118,129,.055);font-size:12px;line-height:1.55;opacity:.82}'+
  '.dm-wrap .dm-mini{font-size:11.5px;line-height:1.5}'+
  '.dm-wrap .dm-section-title{font-size:12px;font-weight:750;letter-spacing:.015em;opacity:.7;margin:15px 0 7px;padding:0 1px}'+
  '.dm-wrap .dm-badge{padding:4px 9px;border-radius:7px;font-size:11px;line-height:1.35;letter-spacing:.005em}'+
  '.dm-wrap .dm-inline-msg{margin-top:10px;padding:10px 12px;border-radius:9px;font-size:12px;line-height:1.5}'+
  '.dm-wrap .dm-applied{gap:10px;padding:11px 13px;margin-bottom:10px;border-radius:10px}'+
  '.dm-wrap .cbi-button{min-height:30px;border-radius:8px;font-weight:650;transition:filter .15s ease,border-color .15s ease,box-shadow .15s ease}'+
  '.dm-wrap .cbi-button-neutral{border:1px solid rgba(110,118,129,.30);background:rgba(110,118,129,.05);color:inherit;box-shadow:none}'+
  '.dm-wrap .cbi-button-neutral:hover:not(:disabled){background:rgba(110,118,129,.11);border-color:rgba(110,118,129,.55)}'+
  '.dm-wrap .cbi-button:hover:not(:disabled){filter:brightness(.98);box-shadow:0 1px 4px rgba(15,23,42,.07)}'+
  '.dm-wrap .cbi-button:focus-visible{outline:2px solid var(--primary-color,#0969da);outline-offset:2px}'+
  '.dm-wrap .cbi-button:disabled{opacity:.48;cursor:not-allowed;box-shadow:none}'+
  '.dm-wrap .dm-seg{gap:7px;margin:8px 0}.dm-wrap .dm-force-seg .cbi-button.active:disabled{opacity:1;cursor:default}'+
  '.dm-custom-dns-content{margin-top:10px}.dm-bootstrap-options{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:7px;margin:10px 0}.dm-bootstrap-option{display:flex;align-items:center;gap:7px;font-size:12px}.dm-bootstrap-option input{flex:none}'+
  '.dm-fold>summary{cursor:pointer;list-style:none;font-size:12px;font-weight:600}.dm-fold>summary::-webkit-details-marker{display:none}.dm-fold>summary:before{content:"▸";display:inline-block;margin-right:7px;transition:transform .15s}.dm-fold[open]>summary:before{transform:rotate(90deg)}.dm-device-fold>summary{display:flex;align-items:center;gap:7px}.dm-device-fold>summary .dm-device-dns-head{flex:1;min-width:0}.dm-device-fold-body{display:flex;flex-direction:column;gap:12px;margin-top:12px}'+
  '.dm-pool-heading{display:flex;align-items:center;justify-content:space-between;gap:12px;margin:4px 0 10px}.dm-pool-heading .dm-mini{margin:0}.dm-pool-actions{margin-top:12px}.dm-pool-manual{padding-top:8px}'+
  '.dm-dnscrypt-server{display:flex;align-items:center;gap:10px;justify-content:space-between;padding:10px 12px;margin-top:6px;border:1px solid rgba(110,118,129,.22);border-radius:9px;background:rgba(110,118,129,.035);font-weight:600}.dm-dnscrypt-result{margin-top:12px}.dm-dnscrypt-result .dm-fold{margin-top:8px}.dm-dnscrypt-result .dm-log{margin-top:8px}'+
  '.dm-wrap .dm-pool-row{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:11px 14px;border:1px solid rgba(110,118,129,.25);border-radius:10px;background:rgba(110,118,129,.04)}.dm-wrap .dm-pool-list{display:grid;gap:7px}.dm-wrap .dm-pool-identity{display:flex;align-items:center;gap:10px;min-width:0}.dm-wrap .dm-pool-number{display:grid;place-items:center;flex:0 0 28px;height:28px;border-radius:8px;background:rgba(110,118,129,.12);font-size:11px;opacity:.75}.dm-wrap .dm-pool-name{font-weight:650;overflow-wrap:anywhere}.dm-wrap .dm-pool-side{display:flex;align-items:center;justify-content:flex-end;gap:10px;flex-wrap:wrap}.dm-wrap .dm-pool-controls{display:flex;gap:5px}.dm-wrap .dm-pool-controls .cbi-button{margin:0;min-width:32px}.dm-wrap .dm-pool-note{margin:10px 0 2px}.dm-wrap .dm-pool-pending{margin-top:12px}.dm-wrap .dm-pool-buttons{display:flex;gap:8px;flex-wrap:wrap;margin-top:14px}.dm-wrap .dm-pool-buttons .cbi-button{margin:0}@media(max-width:600px){.dm-wrap .dm-pool-row{align-items:flex-start;flex-direction:column}.dm-wrap .dm-pool-side{width:100%;justify-content:space-between}.dm-wrap .dm-pool-controls{margin-left:auto}}'+
  '.dm-wrap .dm-seg .cbi-button{min-height:32px;padding:7px 12px;border-radius:9px}'+
  '.dm-seg .cbi-button{border:1px solid rgba(110,118,129,.30)!important;border-radius:10px!important;background:rgba(110,118,129,.05)!important;color:inherit!important;box-shadow:none!important;white-space:normal;text-align:center;transition:background .15s ease,border-color .15s ease,box-shadow .15s ease}'+
  '.dm-seg .cbi-button:hover:not(:disabled){background:rgba(110,118,129,.11)!important;border-color:rgba(110,118,129,.55)!important}'+
  '.dm-seg .cbi-button.active{border-color:rgba(35,134,54,.65)!important;background:rgba(35,134,54,.10)!important;color:inherit!important}'+
  '.dm-seg .cbi-button.active::before{content:"";display:inline-block;width:7px;height:7px;margin-right:7px;border-radius:50%;background:#2da44e;vertical-align:middle}'+
  '.dm-seg .cbi-button:focus-visible{outline:2px solid var(--primary-color,#0969da);outline-offset:2px}.dm-seg .cbi-button:disabled{opacity:.5;cursor:not-allowed}'+
  '.dm-wrap .dm-input,.dm-wrap input:not([type=checkbox]):not([type=radio]),.dm-wrap select,.dm-wrap textarea{max-width:100%;border:1px solid rgba(110,118,129,.28);border-radius:8px;background:var(--background-color-medium,#fff);color:inherit;box-shadow:none}'+
  'html[data-darkmode="true"] .dm-wrap .dm-input,html[data-darkmode="true"] .dm-wrap input:not([type=checkbox]):not([type=radio]),html[data-darkmode="true"] .dm-wrap select,html[data-darkmode="true"] .dm-wrap textarea{background:#22272e;color:#e6edf3;border-color:#545d68;color-scheme:dark}'+
  'html[data-darkmode="true"] .dm-wrap input::placeholder,html[data-darkmode="true"] .dm-wrap textarea::placeholder{color:#a5adb7;opacity:1}'+
  '.dm-wrap .dm-input:focus,.dm-wrap input:not([type=checkbox]):not([type=radio]):focus,.dm-wrap select:focus,.dm-wrap textarea:focus{outline:none;border-color:var(--primary-color,#0969da);box-shadow:0 0 0 3px rgba(9,105,218,.1)}'+
  '.dm-wrap .dm-setting{margin-top:8px;padding:13px;border:1px solid rgba(110,118,129,.18);border-radius:10px;background:rgba(110,118,129,.035)}'+
  '.dm-wrap .dm-setting-title{font-size:12.5px;font-weight:750;line-height:1.4}'+
  '.dm-wrap .dm-setting-desc{font-size:11.5px;line-height:1.55;opacity:.73}'+
  '.dm-wrap .dm-setting-line{align-items:center;flex-wrap:wrap;gap:12px}'+
  '.dm-wrap .dm-setting-controls,.dm-wrap .dm-setting-actions{flex-wrap:wrap}'+
  '.dm-wrap .dm-setting-saving{opacity:1;border-color:rgba(35,134,54,.3);background:rgba(35,134,54,.055)}'+
  '.dm-wrap .dm-component-item,.dm-wrap .dm-component-group{margin-top:8px;padding:12px;border:1px solid rgba(110,118,129,.18);border-radius:10px;background:rgba(110,118,129,.035)}'+
  '.dm-wrap .dm-component-item:last-of-type{border-bottom:1px solid rgba(110,118,129,.18)}'+
  '.dm-wrap .dm-component-dns-list{gap:7px;margin-top:8px}'+
  '.dm-wrap .dm-component-dns{gap:10px;padding:10px 11px;border:1px solid rgba(110,118,129,.17);border-radius:9px;background:rgba(110,118,129,.035)}'+
  '.dm-wrap .dm-component-dns:first-child{border-top:1px solid rgba(110,118,129,.17)}'+
  '.dm-wrap .dm-component-dns-slot{min-width:0;padding:4px 7px;border-radius:6px;background:rgba(110,118,129,.07);opacity:.8}'+
  '.dm-wrap .dm-doh-list{gap:7px}'+
  '.dm-wrap .dm-doh-row{grid-template-columns:max-content minmax(0,1fr) minmax(0,max-content) max-content;gap:10px;padding:11px 12px;border:1px solid rgba(110,118,129,.17);border-radius:10px;background:rgba(110,118,129,.03)}'+
  '.dm-wrap .dm-doh-row:first-child{border-top:1px solid rgba(110,118,129,.17)}'+
  '.dm-wrap .dm-doh-slot{padding:4px 7px;border-radius:6px;background:rgba(110,118,129,.07);font-size:11px;font-weight:700;opacity:.8}'+
  '.dm-wrap .dm-doh-name{font-size:12.5px;line-height:1.4}'+
  '.dm-wrap .dm-doh-actions .cbi-button{min-height:28px;border-radius:7px}'+
  '.dm-wrap .dm-slot-row{grid-template-columns:42px minmax(0,1fr) max-content max-content max-content;gap:10px}'+
  '.dm-wrap .dm-slot-table>.dm-slot-entry:not(.dm-device-dns-entry){margin:8px 0 0;padding:12px;border:1px solid rgba(110,118,129,.18);border-radius:10px;background:rgba(110,118,129,.025)}'+
  '.dm-wrap .dm-slot-entry:not(.dm-device-dns-entry) .dm-slot-row{padding:3px 0;border:0}'+
  '.dm-wrap .dm-slot-entry:not(.dm-device-dns-entry) .dm-slot-domain-panel{padding:10px 0 0;margin-top:5px;border-top:1px solid rgba(110,118,129,.14)}'+
  '.dm-wrap .dm-slot-domains-heading{font-size:12.5px;font-weight:750}'+
  '.dm-wrap .dm-slot-domains-help{font-size:11.5px;line-height:1.55}'+
  '.dm-wrap .dm-slot-domains-input{padding:9px 10px;line-height:1.5}'+
  '.dm-wrap .dm-picker-list{gap:8px;padding:2px;border-radius:10px}'+
  '.dm-wrap .dm-picker-item{gap:12px;padding:11px;border:1px solid rgba(110,118,129,.18);border-radius:10px;background:rgba(110,118,129,.025)}'+
  '.dm-wrap .dm-picker-item:last-child{border-bottom:1px solid rgba(110,118,129,.18)}'+
  '.dm-wrap .dm-picker-name{font-size:13px;line-height:1.45}'+
  '.dm-wrap .dm-picker-meta{gap:7px;margin-top:5px}'+
  '.dm-wrap .dm-slot-picker-categories{gap:6px;margin:8px 0 12px}'+
  '.dm-wrap .dm-slot-picker-categories .cbi-button{border-radius:8px;padding:6px 9px}'+
  '.dm-wrap .dm-catalog-family{width:100%;min-width:0;display:flex;align-items:center;justify-content:space-between;gap:12px;text-align:left;cursor:pointer;color:inherit}.dm-wrap .dm-catalog-family-main{display:flex;min-width:0;flex-direction:column;gap:5px}.dm-wrap .dm-catalog-family.is-open{border-color:rgba(35,134,54,.55);background:rgba(35,134,54,.07)}.dm-wrap .dm-catalog-family-panel{grid-column:1/-1;min-width:0;padding:12px;border:1px solid rgba(35,134,54,.3);border-radius:12px;background:rgba(35,134,54,.04)}.dm-wrap .dm-catalog-family-head{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-bottom:10px}.dm-wrap .dm-catalog-family-items{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:9px}.dm-wrap .dm-catalog-family:focus-visible{outline:2px solid var(--primary-color,#0969da);outline-offset:2px}@media(max-width:850px){.dm-wrap .dm-catalog-family-items{grid-template-columns:repeat(2,minmax(0,1fr))}}@media(max-width:560px){.dm-wrap .dm-catalog-family-items{grid-template-columns:minmax(0,1fr)}}'+
  '.dm-wrap .dm-catalog{gap:12px;margin-top:12px}'+
  '.dm-wrap .dm-catalog-item{gap:9px;padding:14px;border:1px solid rgba(110,118,129,.19);border-radius:12px;background:var(--background-color-medium,#fff);box-shadow:0 1px 4px rgba(15,23,42,.035);transition:border-color .18s ease,box-shadow .18s ease}'+
  '.dm-wrap .dm-catalog-item:hover{border-color:rgba(110,118,129,.34);box-shadow:0 4px 12px rgba(15,23,42,.065)}'+
  '.dm-wrap .dm-catalog-item h4{font-size:14px;font-weight:750;line-height:1.45;overflow-wrap:anywhere}'+
  '.dm-wrap .dm-catalog-item{display:flex;flex-direction:column;gap:7px;min-width:0;padding:12px}.dm-wrap .dm-catalog-item h4{margin:0;font-size:13px}.dm-wrap .dm-catalog-address{font-size:11px;line-height:1.4;opacity:.65;overflow-wrap:anywhere}.dm-wrap .dm-catalog-status{min-height:18px}.dm-wrap .dm-catalog-item .dm-catalog-controls{margin-top:auto}.dm-wrap .dm-catalog-item .cbi-button{margin:0}.dm-wrap .dm-catalog-item .dm-catalog-controls-custom{flex-wrap:wrap}'+
  '.dm-wrap .dm-catalog-item>.dm-meta{display:inline-flex;align-self:flex-start;padding:4px 8px;border-radius:6px;background:rgba(110,118,129,.075);font-size:10.5px;opacity:.82}'+
  '.dm-wrap .dm-catalog-item .dm-catalog-controls{margin-top:auto;padding-top:2px}'+
  '.dm-wrap .dm-catalog-assign{display:flex;align-items:center;gap:8px;flex-wrap:wrap;min-width:0}'+
  '.dm-wrap .dm-catalog-controls-custom .dm-catalog-assign>.cbi-button-negative{flex:0 0 auto}'+
  '.dm-catalog-slot-picker{display:flex;flex-direction:column;gap:8px;min-width:min(460px,calc(100vw - 64px));margin-top:10px}'+
  '.dm-catalog-slot-option{display:grid;grid-template-columns:minmax(0,1fr) auto;align-items:center;gap:12px;padding:11px 12px;border:1px solid rgba(110,118,129,.18);border-radius:10px;background:rgba(110,118,129,.035)}'+
  '.dm-catalog-slot-option.is-current{border-color:rgba(35,134,54,.3);background:rgba(35,134,54,.06)}'+
  '.dm-catalog-slot-option.is-occupied{border-color:rgba(191,135,0,.22)}'+
  '.dm-catalog-slot-main{display:flex;flex-direction:column;gap:4px;min-width:0}'+
  '.dm-catalog-slot-title{font-size:12px;font-weight:750;letter-spacing:.015em;opacity:.75}'+
  '.dm-catalog-slot-current{font-size:12.5px;font-weight:600;line-height:1.45;overflow-wrap:anywhere}'+
  '.dm-catalog-slot-status{margin-top:1px}'+
  '.dm-catalog-slot-port{font-size:10.5px;opacity:.6}'+
  'html[data-darkmode="true"] .dm-catalog-slot-option{background:rgba(255,255,255,.025);border-color:rgba(255,255,255,.1)}'+
  '@media(max-width:560px){.dm-catalog-slot-picker{min-width:0;width:100%}.dm-catalog-slot-option{grid-template-columns:minmax(0,1fr);gap:8px}.dm-catalog-slot-option>.cbi-button{width:100%}.dm-wrap .dm-catalog-assign>.cbi-button{max-width:100%}}'+
  '.dm-wrap .dm-custom-dns-form{display:grid;grid-template-columns:minmax(180px,1fr) minmax(240px,1.4fr) auto;align-items:end;gap:12px;margin:12px 0}'+
  '.dm-wrap .dm-custom-dns-form>div{display:flex;flex-direction:column;gap:6px;min-width:0}'+
  '.dm-wrap .dm-custom-dns-form>.cbi-button{justify-self:start}'+
  '.dm-wrap .dm-test-age-row{min-height:40px;border-bottom:1px solid rgba(110,118,129,.1)}'+
  '.dm-wrap .dm-watchdog-row{min-height:42px;padding:6px 0;border-bottom:1px solid rgba(110,118,129,.1)}'+
   '.dm-wrap .dm-toggle-card{width:100%;display:flex;align-items:center;justify-content:space-between;gap:16px;text-align:left;color:inherit;font:inherit;padding:14px 16px;border:1px solid rgba(110,118,129,.25);border-radius:11px;background:rgba(110,118,129,.035);cursor:pointer;transition:border-color .16s,background .16s,box-shadow .16s}.dm-wrap .dm-toggle-card:hover:not(:disabled){background:rgba(110,118,129,.08);border-color:rgba(110,118,129,.5)}.dm-wrap .dm-toggle-card:focus-visible{outline:2px solid var(--primary-color,#0969da);outline-offset:2px}.dm-wrap .dm-toggle-card.is-on{border-color:rgba(35,134,54,.55);background:rgba(35,134,54,.07)}.dm-wrap .dm-toggle-card:disabled{cursor:not-allowed;opacity:.65}.dm-wrap .dm-toggle-main{min-width:0;flex:1}.dm-wrap .dm-toggle-main .dm-setting-title,.dm-wrap .dm-toggle-main .dm-setting-desc{display:block}.dm-wrap .dm-toggle-side{display:flex;align-items:flex-end;flex-direction:column;gap:5px;flex-shrink:0}.dm-wrap .dm-toggle-action{font-size:11px;opacity:.67}.dm-wrap .dm-toggle-feedback{margin:5px 2px 0}@media(max-width:480px){.dm-wrap .dm-toggle-card{gap:8px;padding:12px}.dm-wrap .dm-toggle-side{align-items:flex-end}}'+
   '.dm-wrap .dm-watchdog-card{display:flex;flex-direction:column;gap:14px;padding:2px 0 15px;border-bottom:1px solid rgba(110,118,129,.18)}'+
   '.dm-wrap .dm-watchdog-status{gap:10px}'+
   '.dm-wrap .dm-watchdog-status .dm-row{min-width:0;padding:11px 12px;border:1px solid rgba(110,118,129,.16);border-radius:9px;background:rgba(110,118,129,.035)}'+
   '.dm-wrap .dm-watchdog-lastcheck{display:flex;flex-direction:column;gap:9px;padding:12px;border:1px solid rgba(110,118,129,.18);border-radius:11px;background:rgba(110,118,129,.035)}'+
   '.dm-wrap .dm-watchdog-lastcheck-head{display:flex;align-items:center;justify-content:space-between;gap:10px;flex-wrap:wrap;font-size:12px}'+
   '.dm-wrap .dm-watchdog-lastcheck-head strong{font-size:12.5px;font-weight:750}'+
   '.dm-wrap .dm-watchdog-lastcheck-head span{font-size:11px;opacity:.72}'+
   '.dm-wrap .dm-watchdog-records{display:flex;flex-direction:column;gap:6px}'+
   '.dm-wrap .dm-watchdog-record{display:grid;grid-template-columns:58px minmax(0,1fr) auto;align-items:center;gap:10px;padding:8px 9px;border:1px solid rgba(110,118,129,.12);border-radius:8px;background:var(--background-color-medium,#fff)}'+
   '.dm-wrap .dm-watchdog-record-slot{font-size:11px;font-weight:750;opacity:.75}'+
   '.dm-wrap .dm-watchdog-record-main{display:flex;flex-direction:column;gap:2px;min-width:0}'+
   '.dm-wrap .dm-watchdog-record-name{font-size:12px;line-height:1.4;overflow-wrap:anywhere}'+
   '.dm-wrap .dm-watchdog-record-category{font-size:10.5px;opacity:.68}'+
   'html[data-darkmode="true"] .dm-wrap .dm-watchdog-status .dm-row,html[data-darkmode="true"] .dm-wrap .dm-watchdog-lastcheck{border-color:rgba(255,255,255,.1);background:rgba(255,255,255,.025)}'+
   'html[data-darkmode="true"] .dm-wrap .dm-watchdog-record{border-color:rgba(255,255,255,.08);background:rgba(255,255,255,.025)}'+
   '@media(max-width:560px){.dm-wrap .dm-watchdog-record{grid-template-columns:48px minmax(0,1fr);gap:7px}.dm-wrap .dm-watchdog-record>.dm-badge{grid-column:2;justify-self:start}.dm-wrap .dm-watchdog-lastcheck-head{align-items:flex-start;flex-direction:column;gap:4px}}'+

  '.dm-wrap .dm-watchdog-row:last-child{border-bottom:0}'+
  '.dm-wrap .dm-profile-progress{padding:13px;border:1px solid rgba(110,118,129,.19);border-radius:10px;background:rgba(110,118,129,.04)}'+
  '.dm-wrap .dm-page-nav{padding:5px;border:1px solid rgba(110,118,129,.17);border-radius:11px;background:var(--background-color-base,#fff);box-shadow:0 2px 8px rgba(15,23,42,.035)}'+
  '.dm-wrap .dm-page-tabs{gap:5px;padding:0}'+
  '.dm-wrap .dm-page-tab{border-radius:8px!important;padding:8px 12px!important}'+
  '.dm-wrap .dm-page-tab.active{box-shadow:0 1px 3px rgba(15,23,42,.05)!important}'+
  '.dm-wrap .dm-page{gap:8px;margin-top:14px;padding-top:10px;border-top:1px solid rgba(110,118,129,.14)}'+
  '.dm-wrap .dm-log{padding:13px;border:1px solid rgba(255,255,255,.08);border-radius:10px;line-height:1.6;box-shadow:inset 0 1px 4px rgba(0,0,0,.16)}'+
  '.dm-wrap .dm-confirm-body{display:flex;flex-direction:column;gap:4px;padding:2px}'+
  '.dm-wrap .dm-confirm-body .dm-row{padding:9px 10px;border:1px solid rgba(110,118,129,.15);border-radius:8px;background:rgba(110,118,129,.035)}'+
  'html[data-darkmode="true"] .dm-wrap .dm-header{border-color:rgba(255,255,255,.1);background:linear-gradient(135deg,rgba(255,255,255,.055),rgba(255,255,255,.015))}'+
  'html[data-darkmode="true"] .dm-wrap .dm-card{background:#1c2128;border-color:rgba(255,255,255,.1);box-shadow:0 2px 9px rgba(0,0,0,.2)}'+
  'html[data-darkmode="true"] .dm-wrap .dm-card:hover{border-color:rgba(255,255,255,.18);box-shadow:0 4px 14px rgba(0,0,0,.25)}'+
  'html[data-darkmode="true"] .dm-wrap .dm-card>h3{border-bottom-color:rgba(255,255,255,.1)}'+
  'html[data-darkmode="true"] .dm-wrap .dm-hint{background:rgba(255,255,255,.035);border-left-color:rgba(255,255,255,.2)}'+
  'html[data-darkmode="true"] .dm-wrap .dm-setting,html[data-darkmode="true"] .dm-wrap .dm-component-item,html[data-darkmode="true"] .dm-wrap .dm-component-group,html[data-darkmode="true"] .dm-wrap .dm-component-dns,html[data-darkmode="true"] .dm-wrap .dm-doh-row,html[data-darkmode="true"] .dm-wrap .dm-slot-table>.dm-slot-entry:not(.dm-device-dns-entry),html[data-darkmode="true"] .dm-wrap .dm-picker-item{background:rgba(255,255,255,.025);border-color:rgba(255,255,255,.09)}'+
  'html[data-darkmode="true"] .dm-wrap .dm-catalog-item{background:#1c2128;border-color:rgba(255,255,255,.1);box-shadow:0 1px 4px rgba(0,0,0,.2)}'+
  'html[data-darkmode="true"] .dm-wrap .dm-page-nav{border-color:rgba(255,255,255,.1);box-shadow:0 2px 8px rgba(0,0,0,.2)}'+
  'html[data-darkmode="true"] .dm-wrap .dm-page-tab.active{border-color:rgba(255,255,255,.13)!important;border-bottom-color:#1c2128!important;background:#1c2128!important}'+
  '@media(max-width:850px){.dm-wrap .dm-custom-dns-form{grid-template-columns:repeat(2,minmax(0,1fr))}.dm-wrap .dm-custom-dns-form>.cbi-button{grid-column:1/-1}.dm-wrap .dm-doh-row{grid-template-columns:minmax(0,1fr) max-content}.dm-wrap .dm-doh-slot{grid-column:1;grid-row:1}.dm-wrap .dm-doh-name{grid-column:1;grid-row:2;max-width:none}.dm-wrap .dm-doh-state{grid-column:2;grid-row:2;justify-self:end}.dm-wrap .dm-doh-actions{grid-column:1/-1;grid-row:3;justify-content:flex-start}.dm-wrap .dm-slot-row{grid-template-columns:40px minmax(0,1fr) auto}.dm-wrap .dm-slot-endpoint{display:none}.dm-wrap .dm-slot-state{grid-column:2/4;grid-row:2;display:block}.dm-wrap .dm-inline{grid-column:2/4;grid-row:3;justify-content:flex-start}}'+
  '@media(max-width:560px){.dm-wrap{gap:11px}.dm-wrap .dm-header{padding:11px 12px;border-radius:11px}.dm-wrap .dm-header h2{font-size:16px}.dm-wrap .dm-card{padding:13px;border-radius:12px}.dm-wrap .dm-card>h3{margin-bottom:11px;padding-bottom:9px;font-size:13.5px}.dm-wrap .dm-card>h3:before{height:14px}.dm-wrap .dm-grid2,.dm-wrap .dm-grid3,.dm-wrap .dm-grid4{gap:9px}.dm-wrap .dm-row{align-items:flex-start;gap:7px}.dm-wrap .dm-hint{padding:9px 10px}.dm-wrap .dm-doh-row{gap:7px;padding:9px}.dm-wrap .dm-catalog{grid-template-columns:minmax(0,1fr);gap:9px}.dm-wrap .dm-catalog-item{padding:12px}.dm-wrap .dm-custom-dns-form{grid-template-columns:minmax(0,1fr)}.dm-wrap .dm-custom-dns-form>.cbi-button{grid-column:auto;width:100%}.dm-wrap .dm-setting-line{align-items:flex-start}.dm-wrap .dm-setting-controls{justify-content:flex-start}.dm-wrap .dm-watchdog-row{grid-template-columns:minmax(0,1fr) 82px auto;gap:7px}.dm-wrap .dm-watchdog-row .dm-input{width:82px!important}.dm-wrap .dm-picker-item{align-items:flex-start;flex-direction:column}.dm-wrap .dm-picker-actions{width:100%}.dm-wrap .dm-picker-actions .cbi-button{flex:1 1 auto}.dm-wrap .dm-page-tabs{gap:3px}.dm-wrap .dm-page-tab{padding:7px 9px!important;font-size:11.5px!important}.dm-wrap .dm-page-nav{top:0}.dm-wrap .dm-page{margin-top:10px}}';
  root.appendChild(E('style',{},css));
}

function rootAlive(root){return !!root&&!!document&&!!document.documentElement&&document.documentElement.contains(root);}
function globalUpdateNotice(msg,type){state.updateNotice=msg?{text:String(msg),type:type||'info'}:null;}
function renderHeader(root,st){
  var notice=arguments[2];
  var e=root.querySelector('#dm-header');if(!e)return;e.innerHTML='';
  var fullAt=Number(st.last_full_test||0),watchdogAt=Number(st.watchdog_last_check||0);
  var useWatchdog=watchdogAt>0&&watchdogAt>=fullAt;
  var lastTest=dateText(useWatchdog?st.watchdog_last_check:st.last_full_test);
  var scope=String(useWatchdog?st.watchdog_last_category:(st.last_full_test_scope||'all'));
  var scopeNames={all:'весь каталог',bypass:'Обход геоблока',clean:'Без фильтрации',security:'Защита от угроз',privacy:'Конфиденциальность',adblock:'Блокировка рекламы',family:'Семейная фильтрация',gaming:'Игры',regional:'Региональный DNS',custom:'Пользовательский DNS',mixed:'Несколько категорий',unknown:'DNS'};
  var scopeLabel=scopeNames[scope]||scope;
  var dnscryptCheck=useWatchdog&&scope==='dnscrypt';
  var testKind=useWatchdog?(dnscryptCheck?'Автопроверка DNSCrypt':'Автопроверка слотов'):(scope==='all'?'Проверка всего каталога':'Проверка категории');
  var dnscryptResult=st.watchdog_dnscrypt_status==='OK'?' · отвечает':st.watchdog_dnscrypt_status==='FAIL'?' · нет ответа':' · нет данных';
  var testText=lastTest==='—'?'Проверка DNS: не выполнялась':testKind+': '+lastTest+(dnscryptCheck?dnscryptResult:(scope==='all'&&!useWatchdog?'':' · '+scopeLabel));
  var items=[
    E('h2',{},'DNS Manager LUCI'),
    E('span',{'class':'dm-header-by'},'by PoTuStoronu222')
  ];
  if(st.luci_version)items.push(E('span',{'class':'dm-header-by'},'v'+shortVal(st.luci_version)));
  items.push(E('span',{'class':'dm-header-by'},notice||'· '+testText));
  e.appendChild(E('div',{'class':'dm-header'},items));
}
function setActiveTab(root,name){
  var groups={
    dashboard:['overview','test-inline'],
    doh:['doh','profiles'],
    slots:['slots'],
    devices:['devices'],
    network:['network'],
    time:['time'],
    catalog:['catalog'],
    log:['log']
  };
  var nextTab=groups[name]?name:'dashboard';
  if(state.activeTab!==nextTab)state.lastAction=null;
  state.activeTab=nextTab;
  ['overview','doh','slots','devices','profiles','network','time','job','catalog','log','test-inline'].forEach(function(id){
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
function currentRoute(){
  var p=String((window.location&&window.location.pathname)||'');
  var m=p.match(/\/admin\/services\/dns-manager\/([^/?#]+)/);
  return m&&m[1]?m[1]:'dashboard';
}
function checkKey(id,d){
  if(id)return String(id);
  if(d&&d.index!==undefined&&d.index!==null)return 'system:'+String(d.index);
  return 'system:'+(d&&d.port?String(d.port):(d&&d.url?String(d.url):'unknown'));
}
function checkInfo(id,d){
  var key=checkKey(id,d);
  var x=state.checking&&state.checking[key];
  if(x&&String(x.status||'').toUpperCase()==='RUNNING')return {status:'RUNNING',ping:''};
  var r={status:d&&d.status?d.status:'',ping:d&&d.ping?d.ping:''};
  return r;
}
function resolverAvailable(ci){
  return String(ci&&ci.status||'').toUpperCase()==='OK';
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
function forceComponentItem(st){
  if(st.dnscrypt_engine==='dnscrypt-proxy2'){
    var dnscryptForce=Number(st.dnscrypt_forced_dns)===1;
    var steerActive=Number(st.steer_dns_active)===1;
    return componentItem('Принудительный DNS для устройств',badge(dnscryptForce||steerActive?'dm-ok':'dm-muted',dnscryptForce?'DNS Manager':steerActive?'Steer':'выключен'));
  }
  st=st||{};
  var busy=!!state.busy;
  var mode=String(st.force_status||'off');
  var owner=String(st.force_owner||'none');
  var both=yes(st.force_both);
  var active=(mode==='manager'||mode==='steer');
  var unavailable=st.dnscrypt_engine==='dnscrypt-proxy2'&&!active&&!both&&owner==='none'&&mode==='off';
  var stateKind=unavailable?'dm-muted':active?'dm-ok':(both||mode==='external'||owner==='external'||mode==='other'?'dm-bad':'dm-off');
  var stateText=unavailable?'недоступен в DNSCrypt':both?'DNS Manager + внешний'
    :owner==='external'?'внешний сервис'
    :owner==='steer'&&mode==='other'?'ДРУГОЕ • Steer'
    :owner==='steer'&&mode==='steer'?'включён • Steer'
    :owner==='manager'?'DNS Manager'
    :'выключен';
  return componentItem('Принудительный DNS для устройств',
    badge(busy?'dm-warn':stateKind,busy?'изменение':stateText)
  );
}
function dnscryptAutoCheckBadge(st){
  var status=st.watchdog_last_category==='dnscrypt'?String(st.watchdog_dnscrypt_status||''):'';
  var label=status==='OK'?'отвечает':status==='FAIL'?'нет ответа':'нет данных';
  return badge(status==='OK'?'dm-ok':status==='FAIL'?'dm-bad':'dm-muted',label);
}
function dnscryptAutoCheckNode(st){
  return E('span',{'data-dm-dnscrypt-check':'1'},[dnscryptAutoCheckBadge(st)]);
}
function watchdogComponentItem(st,wd,wdDetails){
  return componentItem(st.dnscrypt_engine==='dnscrypt-proxy2'?'Автопроверка DNSCrypt':'Проверка DNS',
    wd,
    E('div',{'class':'dm-component-details'},wdDetails)
  );
}
function watchdogReplacementComponentItem(wd,wdDetails){
  return componentItem('Автозамена DNS',
    wd,
    E('div',{'class':'dm-component-details'},wdDetails)
  );
}

function boardMemoryKb(board,key){
  var m=board&&board.memory||{},v=m[key];
  if(v===undefined||v===null||v==='')return null;
  v=Number(v);
  return isFinite(v)&&v>=0?v/1024:null;
}
function boardMemoryAvailableKb(board){
  var m=board&&board.memory||{},v=m.available;
  if(v===undefined||v===null||v==='')v=(Number(m.free)||0)+(Number(m.buffered)||0)+(Number(m.cached)||0);
  v=Number(v);
  return isFinite(v)&&v>=0?v/1024:null;
}
function systemMeter(label,val,pct){
  var p=Number(pct);
  if(!isFinite(p))p=0;
  p=Math.max(0,Math.min(100,Math.round(p)));
  return E('div',{'class':'dm-system-meter'},[
    E('div',{'class':'dm-system-meter-head'},[
      E('span',{},label),
      E('strong',{},val)
    ]),
    E('div',{'class':'dm-system-meter-track'},[E('i',{'style':'width:'+p+'%'})])
  ]);
}
function buildSystemCard(st){
  st=st||{};
  var b=state.boardInfo||{};
  var memTotal=boardMemoryKb(b,'total');
  var memAvail=boardMemoryAvailableKb(b);
  if(memTotal===null&&st.memory_total_kb!==undefined)memTotal=Number(st.memory_total_kb);
  if(memAvail===null&&st.memory_available_kb!==undefined)memAvail=Number(st.memory_available_kb);
  var up=(b&&b.uptime!==undefined&&b.uptime!==null)?Number(b.uptime):Number(st.uptime);
  var cpu=isFinite(state.runtimeCpuLoad)?state.runtimeCpuLoad:loadPercent(st.load1,st.cpu_count);
  var ipv4=st.ipv4==='yes'?badge('dm-ok','есть'):badge('dm-bad','нет');
  var ipv6=st.ipv6==='yes'?badge('dm-ok','есть'):badge('dm-off','выключен');
  var left=[
    row('Модель',shortVal(st.model)),
    row('Архитектура',shortVal(st.arch)),
    row('Платформа',shortVal(st.target)),
    row('OpenWrt',shortVal(st.openwrt)),
    row('Время работы',E('span',{'id':'dm-runtime-uptime','class':'dm-uptime'},uptime(up))),
    row('IPv4',E('span',{'id':'dm-runtime-ipv4'},ipv4)),
    row('IPv6',E('span',{'id':'dm-runtime-ipv6'},ipv6)),
    row('LAN',shortVal(st.lan))
  ];
  var meters=[];
  if(isFinite(cpu))meters.push(systemMeter('Нагрузка ЦП',Math.round(cpu)+'%',cpu));
  if(isFinite(memTotal)&&memTotal>0&&isFinite(memAvail)){
    var mp=memoryPercent(memTotal,memAvail);
    if(mp!==null)meters.push(systemMeter('ОЗУ',memory(memTotal,memAvail),mp));
  }
  if(!meters.length)meters.push(E('div',{'class':'dm-system-hint'},'Системные метрики пока недоступны.'));
  return E('div',{'class':'dm-card dm-system-card','id':'dm-system-card'},[
    E('h3',{},'Система'),
    E('div',{'class':'dm-system-layout'},[
      E('div',{'class':'dm-system-rows'},left),
      E('div',{'class':'dm-system-meters'},meters)
    ])
  ]);
}
function renderSystemCard(root){
  if(!rootAlive(root))return;
  var old=root.querySelector('#dm-system-card');
  if(!old)return;
  old.replaceWith(buildSystemCard(window.dmState||{}));
  tickLocalUptime(root);
}
/* The saved slot configuration is authoritative for selected DNS. Live https-dns-proxy
 * instances are supplementary: port/name detection can fail on a partially migrated
 * router, but that must not hide a DNS already assigned to a slot. */
function dnscryptServerName(st,id){return String((st.dnscrypt_server_names||{})[id]||id);}
function displayDnsRows(st){
  st=st||{};
  if(st.dnscrypt_engine==='dnscrypt-proxy2')return (Array.isArray(st.dnscrypt_servers)?st.dnscrypt_servers:[]).map(function(id){return {id:String(id),name:dnscryptServerName(st,id),slot:'',running:Number(st.dnscrypt_running)===1};});
  var slots=Array.isArray(st.slots)?st.slots:[];
  var instances=Array.isArray(st.doh_instances)?st.doh_instances:[];
  var rows=[];
  slots.forEach(function(slot){
    if(!slot||!String(slot.id||''))return;
    var slotKey=String(slot.slot||'');
    var id=String(slot.id);
    var instance=null;
    instances.some(function(candidate){
      if(!candidate)return false;
      var sameSlot=!!(slotKey&&String(candidate.slot||'')===slotKey);
      var sameId=String(candidate.id||'')===id;
      var samePort=!!(slot.port&&candidate.port&&String(slot.port)===String(candidate.port));
      if(sameSlot||sameId||samePort){instance=candidate;return true;}
      return false;
    });
    var ci=checkInfo(id,slot);
    var name=String(slot.name||'').trim();
    if(!name||name==='Не задан')name=String(instance&&instance.name||'').trim()||id;
    rows.push({
      slot:slotKey,
      id:id,
      name:name,
      port:String(slot.port||(instance&&instance.port)||''),
      url:String((instance&&instance.url)||''),
      status:String(ci.status||slot.status||(instance&&instance.status)||''),
      ping:String(ci.ping||slot.ping||(instance&&instance.ping)||''),
      last_check:String(slot.last_check||(instance&&instance.last_check)||''),
      running:instance?instance.running:0
    });
  });
  instances.forEach(function(instance){
    if(!instance)return;
    var represented=rows.some(function(row){
      return !!((instance.slot&&row.slot&&String(instance.slot)===row.slot)||
        (instance.id&&row.id&&String(instance.id)===row.id)||
        (instance.port&&row.port&&String(instance.port)===row.port));
    });
    if(represented)return;
    var ci=checkInfo(instance.id,instance);
    rows.push({
      slot:'',
      id:String(instance.id||''),
      index:instance.index,
      name:String(instance.name||instance.url||'Пользовательский DNS'),
      port:String(instance.port||''),
      url:String(instance.url||''),
      status:String(ci.status||instance.status||''),
      ping:String(ci.ping||instance.ping||''),
      last_check:String(instance.last_check||''),
      running:instance.running
    });
  });
  return rows;
}

function renderOverview(root,st){
  var e=root.querySelector('#dm-overview');if(!e)return;e.innerHTML='';
  var applied=renderActionStatus();if(applied)e.appendChild(applied);
  if(state.statusError&&!state.statusFromCache)e.appendChild(E('div',{'class':'dm-inline-msg error'},state.statusError+' Проверьте: ubus call dns_manager status.'));

  var noEngine=st.dnscrypt_engine!=='dnscrypt-proxy2'&&Number(st.engine_installed)===0;
  var dohState=st.dnscrypt_engine==='dnscrypt-proxy2'?(Number(st.dnscrypt_running)===1?'ok':'down'):(String(st.doh||'').toLowerCase()==='yes'?'ok':'down');
  var doh=dohState==='ok'
    ? badge('dm-ok','работает')
    : dohState==='down'
      ? badge('dm-bad','не работает')
      : badge('dm-off','не проверено');

  var force=yes(st.force_both)?badge('dm-bad','DNS Manager + внешний')
    :st.force_owner==='external'?badge('dm-bad','внешний сервис')
    :st.force_owner==='steer'&&st.force_status==='other'?badge('dm-bad','ДРУГОЕ • Steer')
    :st.force_owner==='steer'&&st.force_status==='steer'?badge('dm-ok','включён • Steer')
    :yes(st.force_manager)?badge('dm-ok','DNS Manager')
    :badge('dm-off','выключен');

  var watchdogEnabled=yes(st.watchdog);
  var watchdogService=Number(st.watchdog_service||0)===1;
  var watchdogScheduled=Number(st.watchdog_service_enabled||0)===1;
  var watchdogAutoReplace=yes(st.watchdog_autoreplace);
  var wd=watchdogEnabled?(watchdogService?badge('dm-ok','cron работает'):badge('dm-warn',watchdogScheduled?'cron не запущен':'задание cron отсутствует')):badge('dm-muted','выключена');
  if(st.dnscrypt_engine==='dnscrypt-proxy2'&&watchdogEnabled&&watchdogService)wd=dnscryptAutoCheckNode(st);
  var isDnscrypt=st.dnscrypt_engine==='dnscrypt-proxy2';
  var currentCheck=Number(st.watchdog_last_check)>0 && (isDnscrypt?st.watchdog_last_category==='dnscrypt':st.watchdog_last_category!=='dnscrypt');
  var wdDetails=!watchdogEnabled?'Периодическая проверка выключена.':
    !currentCheck?'Интервал проверки: '+Number(st.watchdog_interval||120)+' сек. Результатов пока нет.':
    'Последняя проверка: '+dateText(st.watchdog_last_check)+'.';
  if(watchdogEnabled&&currentCheck&&!isDnscrypt)wdDetails+=' Проверено: '+Number(st.watchdog_last_checked||0)+', ошибок: '+Number(st.watchdog_last_failed||0)+'.';
  var wdAuto=!watchdogEnabled?badge('dm-muted','проверка выключена'):watchdogAutoReplace?(watchdogService?badge('dm-ok','включена'):badge('dm-warn','проверка не работает')):badge('dm-muted','выключена');
  var wdAutoDetails='Замена после '+(Number(st.watchdog_fail_threshold)||3)+' последовательных сбоев.';

  var dnsItems=[];
  displayDnsRows(st).forEach(function(d,index){
    var slot=d.slot?slotLabel(d.slot):(st.dnscrypt_engine==='dnscrypt-proxy2'?'Общий пул':'системный DNS');
    var name=d.name||'Пользовательский DNS';
    var ci=checkInfo(d.id,d);
    var statusNode=st.dnscrypt_engine==='dnscrypt-proxy2'?dnscryptLatencyBadge(st,index):stateBadge(ci.status||d.status,ci.ping||d.ping);
    dnsItems.push(E('div',{'class':'dm-component-dns'},[
      E('div',{'class':'dm-component-dns-main'},[
        E('span',{'class':'dm-component-dns-slot'},slot),
        E('span',{'class':'dm-component-dns-name'},name)
      ]),
      E('div',{'class':'dm-component-dns-meta'},[
        statusNode,
        E('span',{'class':'dm-watchdog-slot-result','data-dns-slot':String(d.slot||('system_'+d.port)),'data-dns-id':String(d.slot?d.id:('system_'+d.port))},[watchdogSlotResult(st,d.slot||('system_'+d.port),d.slot?d.id:('system_'+d.port))].filter(Boolean))
      ])
    ]));
  });
  if(!dnsItems.length)dnsItems.push(E('div',{'class':'dm-hint'},'DNS в слоты не назначены.'));
  var components=card('Компоненты',[
    componentItem('DNS-движок',st.dnscrypt_engine==='dnscrypt-proxy2'?badge(Number(st.dnscrypt_running)===1?'dm-ok':'dm-bad','DNSCrypt Proxy 2 · '+(Number(st.dnscrypt_running)===1?'работает':'остановлен')):Number(st.engine_installed)===0?badge('dm-off','не выбран'):badge(Number(st.engine_running)===1?'dm-ok':'dm-bad','HTTPS DNS Proxy · '+(Number(st.engine_running)===1?'работает':'остановлен'))),
    st.dnscrypt_engine==='dnscrypt-proxy2'?componentItem('Выбор сервера',st.dnscrypt_selected_server?badge('dm-ok',dnscryptServerName(st,st.dnscrypt_selected_server)):badge('dm-muted',Array.isArray(st.dnscrypt_servers)&&st.dnscrypt_servers.length?'автоматически из пула':'серверы не настроены')):null,
    st.dnscrypt_engine==='dnscrypt-proxy2'&&st.dnscrypt_cache_entries!=null?componentItem('Кэш DNSCrypt',badge('dm-ok',String(st.dnscrypt_cache_entries)+' записей')):null,
    st.dnscrypt_engine==='dnscrypt-proxy2'&&st.dnscrypt_avg_response_ms!=null?componentItem('Среднее время ответа DNS',badge('dm-ok',String(st.dnscrypt_avg_response_ms)+' мс')):null,
    watchdogComponentItem(st,wd,wdDetails),
    st.dnscrypt_engine==='dnscrypt-proxy2'?null:watchdogReplacementComponentItem(wdAuto,wdAutoDetails),
    forceComponentItem(st),
    st.dnscrypt_engine==='dnscrypt-proxy2'?null:componentItem('Кэш DNS',badge(st.dnsmasq_cache_size==null||String(st.dnsmasq_cache_size)===''||Number(st.dnsmasq_cache_size)===0?'dm-off':'dm-ok',st.dnsmasq_cache_size==null||String(st.dnsmasq_cache_size)===''?'неизвестно':String(st.dnsmasq_cache_size)+' записей')),
  ].filter(Boolean));

  var dnsSlotsCard=E('div',{'class':'dm-card'},[
    E('h3',{},[
      E('span',{},st.dnscrypt_engine==='dnscrypt-proxy2'?'DNSCrypt Proxy 2':'DNS over HTTPS'),
      doh,
      E('span',{'class':'dm-doh-profile'},[
        E('span',{'class':'dm-doh-profile-label'},'Профиль DNS'),
        E('span',{'class':'dm-doh-profile-value'},activeProfileLabel(st))
      ])
    ]),
    E('div',{'class':'dm-component-dns-list'},dnsItems)
  ].filter(Boolean));

  var verCard=card('Версии',[
    E('div',{'class':'dm-version-line'},[
      E('span',{'class':'dm-version-name'},'DNS Manager'),
      E('span',{'class':'dm-version-state'},versionState(st.manager_version,st.manager_update_available,st.manager_latest_version,st.manager_check_ok,'актуальна',state.versionCheck&&state.versionCheck.manager==='running',st.manager_update_error))
    ]),
    E('div',{'class':'dm-version-line'},[
      E('span',{'class':'dm-version-name'},'LuCI'),
      E('span',{'class':'dm-version-state'},versionState(st.luci_version,st.luci_update_available,st.luci_latest_version,st.luci_update_checked,'актуальна',state.versionCheck&&state.versionCheck.luci==='running',st.luci_update_error))
    ]),
    E('div',{'class':'dm-version-line'},[
      E('span',{'class':'dm-version-name'},st.dnscrypt_engine==='dnscrypt-proxy2'?'DNSCrypt Proxy 2':'HTTPS DNS Proxy'),
      E('span',{'class':'dm-version-state'},st.hdp_version?badge('dm-muted',shortVal(st.hdp_version)+' · установлен'):badge('dm-muted','не установлен'))
    ]),
    E('div',{'class':'dm-version-line'},[
      E('span',{'class':'dm-version-name'},'Каталог DNS'),
      E('span',{'class':'dm-version-state'},catalogVersionState(st.catalog_version,st.catalog_revision,st.catalog_total,st.catalog_update_available,st.catalog_latest_version,st.catalog_latest_rev,st.catalog_check_ok,state.versionCheck&&state.versionCheck.catalog==='running',st.catalog_update_error))
    ]),
    row('Проверено',dateText(st.components_checked_at)),
    E('div',{'class':'dm-actions'},[
      btn(state.versionCheck&&state.versionCheck.running?'Проверяю актуальность…':'Проверить актуальность','cbi-button-neutral',function(){checkUpdate(root,true);},{disabled:!!state.updatingAll||!!(state.versionCheck&&state.versionCheck.running)}),
      (state.updatingAll||hasAvailableUpdates(st)) ?
        btn(state.updatingAll?'Обновляю…':'Обновить','cbi-button-positive',function(){updateAll(root);},{disabled:!!state.updatingAll||!!state.busy||!!(state.versionCheck&&state.versionCheck.running)}) :
        null
    ].filter(Boolean)),
    state.updateNotice?E('div',{'class':'dm-inline-msg '+state.updateNotice.type},state.updateNotice.text):null,
    state.pageNotice.overview?E('div',{'class':'dm-inline-msg error'},state.pageNotice.overview):null
  ].filter(Boolean));

  var sysCard=buildSystemCard(st);
  e.appendChild(E('div',{'class':'dm-grid2'},[sysCard,verCard]));
  if(noEngine)e.appendChild(card('Начало работы',[E('p',{'class':'dm-hint'},'Выберите DNS-движок, чтобы настроить защищённый DNS.'),btn('Выбрать DNS-движок','cbi-button-action',function(){window.location.href=L.url('admin/services/dns-manager/doh');})]));
  else e.appendChild(dnsSlotsCard);
  e.appendChild(components);


  var fullState='';
  if(state.fullTest&&state.fullTest.status==='RUNNING')fullState=E('div',{'class':'dm-inline-msg info'},'Полная проверка DNS выполняется. Интерфейс обновляется автоматически.');
  else if(state.fullTest&&state.fullTest.status==='DONE')fullState=E('div',{'class':'dm-inline-msg ok'},'Полная проверка DNS завершена.');
  else if(state.fullTest&&state.fullTest.status==='FAILED')fullState=E('div',{'class':'dm-inline-msg error'},'Полная проверка DNS завершилась с ошибкой.');
  if(fullState)e.appendChild(fullState);
}
function resolverRows(st,root){
  var out=[],rows=displayDnsRows(st);
  rows.forEach(function(d){
    var slot=d.slot?slotLabel(d.slot):'системный DNS';
    var name=d.name||'Пользовательский DNS';
    var ci=checkInfo(d.id,d);
    var status=String(ci.status||d.status||'').toUpperCase();
    var statusNode=stateBadge(status,ci.ping||d.ping);
    var actions=[];
    if(/^[1-6]$/.test(String(d.slot||'')) && d.id && (st.slots||[]).some(function(s){return s&&String(s.slot)===String(d.slot)&&String(s.id||'')===String(d.id);})){
      actions.push(btn('Заменить','cbi-button-neutral',function(){openSlotPicker(d.slot,root);},{disabled:!!state.busy||!!state.jobRunning}));
      actions.push(btn('Удалить','cbi-button-negative',function(){removeSelectedSlot(d,root);},{disabled:!!state.busy||!!state.jobRunning}));
    }
    out.push(E('div',{'class':'dm-doh-row'},[
      E('span',{'class':'dm-doh-slot'},slot),
      E('span',{'class':'dm-doh-name'},name),
      E('span',{'class':'dm-doh-state'},statusNode),
      E('span',{'class':'dm-doh-actions'},actions)
    ]));
  });
  return [out,rows.length];
}
function removeSelectedSlot(d,root){
  if(state.busy||state.jobRunning||!d||!/^[1-6]$/.test(String(d.slot||'')))return;
  confirmAction('Удалить DNS из слота?',[['Слот',slotLabel(d.slot)],['DNS',d.name||d.id],['Домены','Маршруты слота перестанут действовать до назначения другого DNS.']],function(){
    state.busy=true;state.pageNotice.doh='Удаляю DNS из '+slotLabel(d.slot)+'…';renderDoH(root,window.dmState||{});
    callSlot(String(d.slot),'',String(d.id)).then(awaitSettingResult).then(function(r){
      state.busy=false;
      state.pageNotice.doh=r&&r.ok?'DNS удалён из '+slotLabel(d.slot)+'.':((r&&r.error)||'Не удалось удалить DNS.');
      setAction(!!(r&&r.ok),state.pageNotice.doh);return refresh(root,true);
    }).catch(function(err){state.busy=false;state.pageNotice.doh=withRpcError('Не удалось удалить DNS.',err);setAction(false,state.pageNotice.doh);return refresh(root,true);});
  });
}
// Public resolver addresses checked against provider documentation on 2026-10-30:
// https://developers.cloudflare.com/1.1.1.1/ip-addresses/
// https://developers.google.com/speed/public-dns/docs/using
// https://docs.quad9.net/services/ | https://dns.yandex.com/
// https://adguard-dns.io/kb/general/dns-providers/ | https://docs.controld.com/docs/free-dns
// https://www.opendns.com/setupguide/ | https://cleanbrowsing.org/filters
// https://www.cira.ca/en/canadian-shield/configure/summary-cira-canadian-shield-dns-resolver-addresses/
var bootstrapPresets=[
  {id:'cloudflare',name:'Cloudflare',ips:'1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001'},
  {id:'google',name:'Google',ips:'8.8.8.8,8.8.4.4,2001:4860:4860::8888,2001:4860:4860::8844'},
  {id:'quad9',name:'Quad9 Secure',ips:'9.9.9.9,149.112.112.112,2620:fe::fe,2620:fe::9'},
  {id:'quad9plain',name:'Quad9 (9.9.9.10)',ips:'9.9.9.10,149.112.112.10,2620:fe::10,2620:fe::fe:10'},
  {id:'yandex',name:'Яндекс DNS',ips:'77.88.8.8,77.88.8.1,2a02:6b8::feed:0ff,2a02:6b8:0:1::feed:0ff'},
  {id:'adguardplain',name:'AdGuard DNS (94.140.14.140)',ips:'94.140.14.140,94.140.14.141,2a10:50c0::1:ff,2a10:50c0::2:ff'},
  {id:'adguard',name:'AdGuard Default',ips:'94.140.14.14,94.140.15.15,2a10:50c0::ad1:ff,2a10:50c0::ad2:ff'},
  {id:'controld',name:'Control D (76.76.2.0)',ips:'76.76.2.0,76.76.10.0,2606:1a40::0,2606:1a40:1::0'},
  {id:'controlduncensored',name:'Control D (76.76.2.5)',ips:'76.76.2.5,76.76.10.5,2606:1a40::5,2606:1a40:1::5'},
  {id:'opendns',name:'OpenDNS',ips:'208.67.222.222,208.67.220.220'},
  {id:'cira',name:'CIRA Canadian Shield Private',ips:'149.112.121.10,149.112.122.10,2620:10a:80bb::10,2620:10a:80bc::10'},
  {id:'cleanbrowsing',name:'CleanBrowsing Security',ips:'185.228.168.9,185.228.169.9,2a0d:2a00:1::2,2a0d:2a00:2::2'}
];
// Historical 2.07 snapshot: never edit these entries when updating providers.
// Existing installations saved only IPs, so this recovers their selected IDs.
var bootstrapLegacyPresets=[
  {id:'cloudflare',ips:'1.1.1.1,1.0.0.1,2606:4700:4700::1111,2606:4700:4700::1001'},
  {id:'google',ips:'8.8.8.8,8.8.4.4,2001:4860:4860::8888,2001:4860:4860::8844'},
  {id:'quad9',ips:'9.9.9.9,149.112.112.112,2620:fe::fe,2620:fe::9'},
  {id:'quad9plain',ips:'9.9.9.10,149.112.112.10,2620:fe::10,2620:fe::fe:10'},
  {id:'yandex',ips:'77.88.8.8,77.88.8.1,2a02:6b8::feed:0ff,2a02:6b8:0:1::feed:0ff'},
  {id:'adguardplain',ips:'94.140.14.140,94.140.14.141,2a10:50c0::1:ff,2a10:50c0::2:ff'},
  {id:'adguard',ips:'94.140.14.14,94.140.15.15,2a10:50c0::ad1:ff,2a10:50c0::ad2:ff'},
  {id:'controld',ips:'76.76.2.0,76.76.10.0,2606:1a40::0,2606:1a40:1::0'},
  {id:'controlduncensored',ips:'76.76.2.5,76.76.10.5,2606:1a40::5,2606:1a40:1::5'},
  {id:'opendns',ips:'208.67.222.222,208.67.220.220'},
  {id:'cira',ips:'149.112.121.10,149.112.122.10,2620:10a:80bb::10,2620:10a:80bc::10'},
  {id:'cleanbrowsing',ips:'185.228.168.9,185.228.169.9,2a0d:2a00:1::2,2a0d:2a00:2::2'}
];
function bootstrapSplitSelection(selected,storedIds,storedExtra,snapshot){
  if(selected&&snapshot===selected)return {mode:'choose',ids:String(storedIds||'').split(',').filter(Boolean),addresses:String(storedExtra||'')};
  var remaining=String(selected||'').split(',').filter(Boolean),ids=[];
  bootstrapLegacyPresets.concat(bootstrapPresets).forEach(function(p){var parts=p.ips.split(',');if(ids.indexOf(p.id)<0&&parts.every(function(x){return remaining.indexOf(x)>=0;})){ids.push(p.id);parts.forEach(function(x){remaining.splice(remaining.indexOf(x),1);});}});
  return {mode:selected?'choose':'default',ids:ids,addresses:remaining.join(', ')};
}
function bootstrapComposeSelection(ids,extra){
  var out=[],seen=Object.create(null);
  bootstrapPresets.forEach(function(p){if(ids.indexOf(p.id)>=0)p.ips.split(',').forEach(add);});
  String(extra||'').split(/[\s,]+/).filter(Boolean).forEach(add);
  function add(x){var key=x.toLowerCase();if(!seen[key]){seen[key]=true;out.push(key);}}
  return out.join(',');
}
function renderBootstrap(root,st){
  var selected=String(st.bootstrap_selected||''),saved=bootstrapSplitSelection(selected,st.bootstrap_preset_ids,st.bootstrap_extra,st.bootstrap_metadata_snapshot),draft=state.bootstrapDraft||saved;
  var knownIds=bootstrapPresets.map(function(p){return p.id;});
  var missingIds=draft.ids.filter(function(id){return knownIds.indexOf(id)<0;});
  var current=bootstrapComposeSelection(saved.ids,saved.addresses), changed=selected&&current.split(',').sort().join(',')!==selected.split(',').sort().join(',');
  var select=E('select',{'class':'dm-input'},[E('option',{'value':'default'},'По умолчанию'),E('option',{'value':'choose'},'Выбрать наборы и свои адреса')]);
  select.value=draft.mode;
  var input=E('input',{'class':'dm-input','type':'text','placeholder':'Свои IP-адреса через запятую'});
  input.value=draft.addresses||'';
  var controls=[], options=bootstrapPresets.map(function(p){
    var attrs={'type':'checkbox','value':p.id};if(draft.ids.indexOf(p.id)>=0)attrs.checked='';
    var checkbox=E('input',attrs);controls.push(checkbox);
    checkbox.addEventListener('change',remember);
    return E('label',{'class':'dm-bootstrap-option'},[checkbox,E('span',{},p.name)]);
  });
  missingIds.forEach(function(id){
    var checkbox=E('input',{'type':'checkbox','value':id,'checked':''});controls.push(checkbox);checkbox.addEventListener('change',remember);
    options.push(E('label',{'class':'dm-bootstrap-option'},[checkbox,E('span',{},'Недоступный набор: '+id)]));
  });
  function remember(){state.bootstrapDraft={mode:select.value,ids:controls.filter(function(c){return c.checked;}).map(function(c){return c.value;}),addresses:input.value};}
  function toggle(){var disabled=select.value!=='choose';input.disabled=disabled;controls.forEach(function(c){c.disabled=disabled;});}
  select.addEventListener('change',function(){toggle();remember();});input.addEventListener('input',remember);toggle();
  var button=btn(state.busySetting==='bootstrap'?'Применяю…':'Применить','cbi-button-action',function(){
    if(state.busy)return;
    remember();var value=select.value,addresses=bootstrapComposeSelection(state.bootstrapDraft.ids,input.value);
    if(value==='choose'&&state.bootstrapDraft.ids.some(function(id){return knownIds.indexOf(id)<0;})){state.bootstrapNotice={type:'error',text:'Снимите отметку с недоступных наборов перед применением.'};renderDoH(root,window.dmState||{});return;}
    if(value==='choose'&&!addresses){state.bootstrapNotice={type:'error',text:'Выберите набор или укажите свои IP-адреса.'};renderDoH(root,window.dmState||{});return;}
    if(value==='choose'&&addresses&&addresses.split(',').length>48){state.bootstrapNotice={type:'error',text:'Можно выбрать не более 48 разных IP-адресов.'};renderDoH(root,window.dmState||{});return;}
    state.busy=true;state.busySetting='bootstrap';
    state.bootstrapNotice={type:'info',text:'Применяю bootstrap DNS и проверяю выбранные DNS…'};renderDoH(root,window.dmState||{});
    callBootstrap(value==='default'?'default':'custom',addresses,state.bootstrapDraft.ids.join(','),bootstrapComposeSelection([],input.value)).then(awaitSettingResult).then(function(r){
      state.busy=false;state.busySetting='';
      if(r&&r.ok){state.bootstrapDraft=null;state.bootstrapNotice={type:'ok',text:'Bootstrap DNS сохранён.'};}
      else state.bootstrapNotice={type:'error',text:(r&&r.error)||'Не удалось применить bootstrap DNS.'};
      return refresh(root,true);
    }).catch(function(err){state.busy=false;state.busySetting='';state.bootstrapNotice={type:'error',text:withRpcError('Не удалось получить результат bootstrap DNS.',err)};renderDoH(root,window.dmState||{});});
  },{disabled:!!state.busy||!!state.jobRunning});
  return card('Bootstrap DNS',[foldSection('bootstrap','Настроить bootstrap DNS',E('div',{'class':'dm-custom-dns-content'},[
    E('p',{'class':'dm-hint'},'Bootstrap DNS определяет IP-адреса DoH-серверов до установления защищённого соединения. Эти начальные DNS-запросы не шифруются. Изменение не выбирает DNS-профиль.'),
    E('div',{'class':'dm-mini'},'Сейчас: '+(selected||'по умолчанию')),
    changed?E('div',{'class':'dm-inline-msg info'},'Адреса выбранных наборов изменились. Сейчас используются прежние адреса; нажмите «Применить», чтобы перейти на новые.'):null,
    E('div',{'class':'dm-actions'},[select]),
    E('div',{'class':'dm-bootstrap-options'},options),
    E('div',{'class':'dm-mini'},'Можно объединить несколько наборов и добавить свои IP. Максимум 48 адресов. Фильтрующие серверы могут блокировать домены DoH; доступность IPv6 зависит от сети.'),
    E('div',{'class':'dm-actions'},[input,button]),
    state.bootstrapNotice?E('div',{'class':'dm-inline-msg '+state.bootstrapNotice.type},state.bootstrapNotice.text):null
  ].filter(Boolean)))]);
}
function appendUninstall(ch,root){
  var un=state.uninstall;
  if(un){
    ch.push(E('div',{'class':'dm-inline-msg '+(un.status==='failed'?'error':'info')},[
      E('strong',{},un.status==='confirm'?'Удаление DNS Manager':un.status==='done'?'Удаление завершено':un.status==='failed'?'Удаление не завершено':'Удаление DNS Manager'),
      E('p',{},un.message),
      un.output?E('pre',{},un.output):null
    ].filter(Boolean)));
  }
  ch.push(E('div',{'class':'dm-actions'},un&&un.status==='confirm'?[
    btn('Подтвердить удаление','cbi-button-negative',function(){uninstallManager(root);}),
    btn('Отмена','cbi-button-neutral',function(){state.uninstall=null;renderDoH(root,window.dmState||{});})
  ]:un&&un.status==='done'?[
    btn('Открыть LuCI','cbi-button-action',function(){window.location.href=L.url('admin/status/overview');})
  ]:[
    btn('Удалить DNS Manager','cbi-button-negative',function(){
      state.uninstall={status:'confirm',message:'Функции менеджера будут отключены, стандартный DNS восстановлен, затем удалятся интерфейс и установленные менеджером пакеты, если они не используются сторонними настройками.'};
      renderDoH(root,window.dmState||{});
    },{disabled:!!state.busy})
  ]));
}
function dnscryptLatencyBadge(st,index){
  if(state.busy&&state.dnscryptDiagnosticKind==='test'&&!state.dnscryptDiagnosticResult)return badge('dm-off','Проверяю DNS…');
  var id=(st.dnscrypt_servers||[])[index], check=(st.dnscrypt_server_checks||{})[id];
  var checked=Number((st.dnscrypt_server_check_times||{})[id]||0), now=Number(st.dnscrypt_check_now||0);
  if(Number(st.dnscrypt_running)===1&&check&&checked>0){
    var fresh=now>=checked&&now-checked<=300, when=dateText(checked);
    if(check==='fail')return badge(fresh?'dm-bad':'dm-muted',(fresh?'недоступен':'не ответил')+' · проверено '+when);
    if(/^OK:[0-9]+$/.test(String(check)))return badge(fresh?'dm-ok':'dm-muted',String(check).slice(3)+' мс'+(fresh?' · доступен':'')+' · проверено '+when);
  }
  var values=st.dnscrypt_server_latency||{}, value=values['manager-'+(index+1)];
  var time=(st.dnscrypt_server_latency_times||{})['manager-'+(index+1)];
  return Number(st.dnscrypt_running)===1&&value!=null&&/^\d+$/.test(String(value))
    ? badge('dm-muted',String(value)+' мс · замер DNSCrypt'+(time?' '+String(time).replace(',',', '):' · время неизвестно'))
    : badge('dm-muted','нет данных');
}
function dnscryptCurrentPool(st){
  var servers=Array.isArray(st.dnscrypt_servers)?st.dnscrypt_servers:[];
  return servers.length?E('div',{'class':'dm-doh-list'},servers.map(function(id,index){
    return E('div',{'class':'dm-dnscrypt-server'},[E('span',{},dnscryptServerName(st,id)),dnscryptLatencyBadge(st,index)]);
  })):E('div',{'class':'dm-hint'},'DNS ещё не выбраны: примените профиль.');
}
function dnscryptOptions(st){
  return {protocol:state.dnscryptProtocol||st.dnscrypt_protocol||'mixed',strategy:state.dnscryptStrategy||st.dnscrypt_strategy||'p2'};
}
function dnscryptOptionsChanged(st){
  var o=dnscryptOptions(st);
  return o.protocol!==(st.dnscrypt_protocol||'mixed')||o.strategy!==(st.dnscrypt_strategy||'p2');
}
function dnscryptGoal(goal,st){
  var o=dnscryptOptions(st);return 'options:'+o.protocol+':'+o.strategy+':'+goal;
}
function dnscryptOptionsControls(root,st,render){
  var o=dnscryptOptions(st);
  function select(label,key,items,value){
    return E('label',{'class':'dm-mini'},[label,E('select',{'class':'cbi-input-select','change':function(ev){
      state[key]=ev.target.value;render(root,st);
    }},items.map(function(item){var attrs={'value':item[0]};if(item[0]===value)attrs.selected='selected';return E('option',attrs,item[1]);}))]);
  }
  var descriptions={wp2:'Для каждого запроса сравниваются два случайных сервера: учитываются скорость и успешность ответов.',p2:'Случайный выбор из двух самых быстрых серверов.',p3:'Случайный выбор из трёх самых быстрых серверов.',p4:'Случайный выбор из четырёх самых быстрых серверов.',p5:'Случайный выбор из пяти самых быстрых серверов.',p6:'Случайный выбор из шести самых быстрых серверов.',ph:'Случайный выбор из быстрой половины доступных серверов.',first:'Запрос направляется самому быстрому доступному серверу по оценке DNSCrypt.',random:'Случайный выбор из всех доступных серверов.'};
  function chooseStrategy(value){state.dnscryptStrategy=value;render(root,st);}
  return E('div',{'class':'dm-hint'},[
    select('Протокол: ','dnscryptProtocol',[['mixed','DNSCrypt и DoH'],['native','Только DNSCrypt']],o.protocol),
    E('div',{'class':'dm-setting-title'},'Как выбирать DNS-сервер'),
    E('div',{'class':'dm-seg'},[
      btn('Умный выбор','cbi-button'+(o.strategy==='wp2'?' active':''),function(){chooseStrategy('wp2');},{disabled:o.strategy==='wp2'||!!state.busy||!!state.jobRunning,'aria-pressed':o.strategy==='wp2'?'true':'false'}),
      btn('Самый быстрый','cbi-button'+(o.strategy==='first'?' active':''),function(){chooseStrategy('first');},{disabled:o.strategy==='first'||!!state.busy||!!state.jobRunning,'aria-pressed':o.strategy==='first'?'true':'false'})
    ]),
    select('Другие варианты: ','dnscryptStrategy',[['wp2','Умный выбор из двух'],['p2','Случайно из 2 быстрых'],['p3','Случайно из 3 быстрых'],['p4','Случайно из 4 быстрых'],['p5','Случайно из 5 быстрых'],['p6','Случайно из 6 быстрых'],['ph','Случайно из быстрой половины'],['first','Самый быстрый'],['random','Случайно из всех']],o.strategy),
    E('div',{'class':'dm-mini'},descriptions[o.strategy]||''),
    E('div',{'class':'dm-mini'},'Порядок в списке не определяет приоритет: DNSCrypt не поддерживает последовательный выбор по списку. Изменения сохраняются при применении набора или профиля.')
  ]);
}
function dnscryptPoolDraft(st){
  var current=Array.isArray(st.dnscrypt_servers)?st.dnscrypt_servers:[], base=current.join(','), draft;
  try{draft=JSON.parse(window.sessionStorage.getItem('dm-dnscrypt-pool')||'null');}catch(e){draft=state.dnscryptPoolDraft;}
  if(!draft||draft.base!==base||!Array.isArray(draft.items))draft={base:base,items:current.map(function(id){return {id:id,name:dnscryptServerName(st,id)};})};
  return draft;
}
function saveDnscryptPoolDraft(draft){state.dnscryptPoolDraft=draft;try{window.sessionStorage.setItem('dm-dnscrypt-pool',JSON.stringify(draft));}catch(e){}}
function dnscryptPoolRows(st,root){
  var draft=dnscryptPoolDraft(st),items=draft.items,active=Array.isArray(st.dnscrypt_servers)?st.dnscrypt_servers:[];
  if(!items.length)return E('p',{'class':'dm-mini'},'Добавьте серверы из каталога.');
  return E('div',{'class':'dm-pool-list'},items.map(function(item,index){
    function change(action){if(action==='remove')items.splice(index,1);else{var other=index+action,tmp=items[other];items[other]=items[index];items[index]=tmp;}saveDnscryptPoolDraft(draft);renderSlots(root,st);}
    var activeIndex=active.indexOf(item.id), result=activeIndex<0?badge('dm-muted','ещё не применён'):dnscryptLatencyBadge(st,activeIndex);
    return E('div',{'class':'dm-pool-row'},[
      E('div',{'class':'dm-pool-identity'},[E('span',{'class':'dm-pool-number'},String(index+1)),E('span',{'class':'dm-pool-name'},item.name)]),
      E('div',{'class':'dm-pool-side'},[result,E('div',{'class':'dm-pool-controls'},[
        btn('↑','cbi-button-neutral',function(){change(-1);},{disabled:index===0||!!state.busy||!!state.jobRunning,'aria-label':'Переместить '+item.name+' выше'}),
        btn('↓','cbi-button-neutral',function(){change(1);},{disabled:index===items.length-1||!!state.busy||!!state.jobRunning,'aria-label':'Переместить '+item.name+' ниже'}),
        btn('Убрать','cbi-button-neutral',function(){change('remove');},{disabled:!!state.busy||!!state.jobRunning,'aria-label':'Убрать '+item.name})])])]);
  }));
}
function applyDnscryptPool(root,st){
  var ids=dnscryptPoolDraft(st).items.map(function(x){return x.id;});
  if(!ids.length||state.busy||state.jobRunning)return;
  state.busy=true;state.dnscryptDiagnostic='Применяю набор DNS…';state.dnscryptDiagnosticKind='action';renderSlots(root,st);
  callProfile(dnscryptGoal('pool:'+ids.join(','),st)).then(function(r){
    if(!r||!r.ok||r.job!=='profile')throw new Error((r&&r.error)||'Не удалось запустить применение.');
    state.jobRunning=true;pollJob(root,r.job,{mode:'server',origin:'slots'},function(ns,j){
      var ok=j&&j.status==='done'&&j.result==='ok';
      if(ok){try{window.sessionStorage.removeItem('dm-dnscrypt-pool');}catch(e){}state.dnscryptPoolDraft=null;}
      state.busy=false;state.dnscryptDiagnostic=ok?'Набор DNS применён.':('Не удалось применить набор. '+stripAnsi(String(j&&j.output||'')));
      state.dnscryptDiagnosticKind='action';renderSlots(root,ns||window.dmState||{});
    });
  }).catch(function(err){state.busy=false;state.dnscryptDiagnostic=withRpcError('Не удалось применить набор.',err);renderSlots(root,window.dmState||{});});
}
function renderDoH(root,st){
  var e=root.querySelector('#dm-doh');if(!e)return;e.innerHTML='';
  var uninstall=root.querySelector('#dm-uninstall');
  if(uninstall){uninstall.innerHTML='';var danger=[];appendUninstall(danger,root);uninstall.appendChild(card('Удаление DNS Manager',danger));}
  var engine=st.dnscrypt_engine==='dnscrypt-proxy2'?'dnscrypt-proxy2':(Number(st.engine_installed)===0?'none':'https-dns-proxy');
  function engineChoice(id,title,description){
    var selected=engine===id;
    var attrs={'type':'button','class':'dm-engine-choice'+(selected?' dm-engine-selected':''),'aria-pressed':selected?'true':'false','click':function(){if(!selected&&!state.busy&&!state.jobRunning)switchEngine(id,root);}};
    if(selected||state.busy||state.jobRunning)attrs.disabled=true;
    return E('button',attrs,[
      E('span',{'class':'dm-engine-choice-head'},[E('strong',{},title),selected?badge('dm-ok','выбран'):E('span',{'class':'dm-engine-choice-action'},engine==='none'?'Установить':'Выбрать')]),
      E('span',{'class':'dm-mini'},description)
    ]);
  }
  e.appendChild(card('DNS-движок',[
    E('p',{'class':'dm-hint'},engine==='none'?'Выберите и установите DNS-движок, затем настройте профиль.':'При смене движка профили, слоты и привязки сбрасываются.'),
    E('div',{'class':'dm-engine-choices'},[
      engineChoice('https-dns-proxy','HTTPS DNS Proxy','Отдельные DNS-слоты и привязки устройств.'),
      engineChoice('dnscrypt-proxy2','DNSCrypt Proxy 2','Один процесс и общий набор DNS-серверов.')
    ]),
    state.engineNotice?E('div',{'class':'dm-inline-msg '+(state.engineNoticeType||'info')},state.engineNotice):null
  ].filter(Boolean)));
  resumeEngine(root);
  if(engine==='none'){
    return;
  }
  if(st.dnscrypt_engine==='dnscrypt-proxy2'){
    var servers=Array.isArray(st.dnscrypt_servers)?st.dnscrypt_servers:[];
    var selectedServer=String(st.dnscrypt_selected_server||'');
    var details=[row('Движок',E('span',{},'DNSCrypt Proxy 2')),row('Служба',Number(st.dnscrypt_running)===1?badge('dm-ok','работает'):badge('dm-bad','остановлена')),yes(st.watchdog)?row('Автопроверка DNSCrypt',dnscryptAutoCheckNode(st)):null,selectedServer?row('Режим',E('span',{},'Один сервер выбран вручную')):row('Профиль',!activeProfileId(st)?badge('dm-muted','не выбран'):E('span',{},activeProfileLabel(st)))];
    details=details.filter(Boolean);
    if(!activeProfileId(st)&&!selectedServer)details.push(E('p',{'class':'dm-hint'},servers.length?'Используется начальный набор DNS. При необходимости выберите профиль ниже.':'Выберите профиль ниже, чтобы настроить DNS.'));
    details.push(E('div',{'class':'dm-row'},[E('span',{'class':'dm-label'},servers.length===1?'Сейчас используется':'Сейчас используются')]));
    details.push(dnscryptCurrentPool(st));
    details.push(E('p',{'class':'dm-hint'},selectedServer?'Используется один выбранный вручную сервер.':'DNSCrypt автоматически выбирает сервер из этого набора.'));
    details.push(E('div',{'class':'dm-actions'},[
      btn('Вернуть начальные серверы','cbi-button-neutral',function(){applyProfile('default',root);},{disabled:!!state.busy}),
      btn('Проверить DNS','cbi-button-neutral',function(){dnscryptDiagnostic(root,false);},{disabled:!!state.busy})
    ]));
    if(state.dnscryptDiagnostic){var diagnosticView=dnscryptDiagnosticView();if(diagnosticView)details.push(diagnosticView);}
    e.appendChild(card('DNSCrypt Proxy 2',details));
    return;
  }
  var rr=resolverRows(st,root), rows=rr[0], count=rr[1];
  var ch=[];
  ch.push(row('Пакет',Number(st.engine_installed)!==0?badge('dm-ok','установлен'):badge('dm-off','не установлен')));
  ch.push(row('Служба',st.doh==='yes'?badge('dm-ok','включена'):st.doh_total>0?badge('dm-bad','остановлена'):badge('dm-off','не установлена')));
  if(count){
    ch.push(E('div',{'class':'dm-row'},[E('span',{'class':'dm-label'},count>1?'Сейчас используются':'Сейчас используется')]));
    ch.push(E('div',{'class':'dm-doh-list'},rows));
  } else ch.push(row('Сейчас используется',E('span',{},'резолверы не настроены')));
  ch.push(E('div',{'class':'dm-actions'},[
    btn('Вернуть начальные серверы','cbi-button-neutral',function(){resetDnsCore(root,'default');},{disabled:!!state.busy||!!state.jobRunning}),
    btn(state.currentTest&&state.currentTest.status==='RUNNING'?'Проверяю…':'Проверить текущие DNS','cbi-button-action',function(){testCurrent(root);},{disabled:!!state.busy||!!state.jobRunning})
  ]));
  if(state.currentTest && !(state.currentTest.status==='DONE' && (!state.currentTest.result || state.currentTest.result==='ok')))ch.push(E('div',{'class':'dm-inline-msg '+(state.currentTest.status==='RUNNING'?'info':'error')},
    state.currentTest.status==='RUNNING'?'Проверка текущих DNS выполняется…':state.currentTest.status==='UNKNOWN'?'Результат проверки пока неизвестен.':state.currentTest.total===0?'Текущих DNS для проверки нет.':'Проверка текущих DNS завершилась с ошибками.'));

  var fm=forceMode(st);
  var forceEnabled=fm==='auto';
  var forceButtons=E('div',{'class':'dm-seg dm-force-seg'},[
    btn('Авто (рекомендуется)',fm==='auto'?'active cbi-button':'cbi-button',function(){setForceMode('auto',root);},{disabled:!!state.busy||!!state.jobRunning||fm==='auto','aria-pressed':fm==='auto'?'true':'false'}),
    btn('Выключено',fm==='off'?'active cbi-button':'cbi-button',function(){setForceMode('off',root);},{disabled:!!state.busy||!!state.jobRunning||fm==='off','aria-pressed':fm==='off'?'true':'false'})
  ]);
  var encryptedEnabled=yes(st.encrypted_dns);
  var encryptedButtons=E('div',{'class':'dm-seg dm-force-seg'},[
    btn('Включено',encryptedEnabled?'active cbi-button':'cbi-button',function(){setSetting('encrypted_dns',1,root);},{disabled:!!state.busy||!!state.jobRunning||encryptedEnabled,'aria-pressed':encryptedEnabled?'true':'false'}),
    btn('Выключено',!encryptedEnabled?'active cbi-button':'cbi-button',function(){setSetting('encrypted_dns',0,root);},{disabled:!!state.busy||!!state.jobRunning||!encryptedEnabled,'aria-pressed':!encryptedEnabled?'true':'false'})
  ]);
  var steer=st.force_owner==='steer';
  ch.push(E('div',{'style':'margin-top:9px'},[
    E('div',{'class':'dm-row'},[
      E('span',{'class':'dm-label'},'Принудительный DNS'),
      badge(st.force_status==='external'||st.force_status==='other'?'dm-bad':(st.force_status==='manager'||st.force_status==='steer')?'dm-ok':'dm-off',st.force_status==='external'?'внешний':st.force_status==='other'?'другое':st.force_status==='steer'?'включён • Steer':st.force_status==='manager'?'включён':'выключен')
    ]),
    E('p',{'class':'dm-hint'},'Направляет обычные DNS-запросы устройств на DNS роутера. В конфигурации https-dns-proxy задействованы порты 53 и 853.'),
    forceButtons
  ].filter(Boolean)));
  ch.push(E('div',{'style':'margin-top:14px'},[
    E('div',{'class':'dm-row'},[
      E('span',{'class':'dm-label'},'Не давать устройствам обходить блокировку'),
      badge(encryptedEnabled?'dm-ok':'dm-off',encryptedEnabled?'включено':'выключено')
    ]),
    E('p',{'class':'dm-hint'},'Дополнительно ограничивает использование сторонних зашифрованных DNS-сервисов, через которые устройство может обходить DNS-фильтрацию роутера.'),
    encryptedButtons,
    settingFeedback('','encrypted_dns'),
    E('p',{'class':'dm-hint'},'Эта настройка отклоняет соединения LAN → WAN на порту 853. При принудительном DNS без Steer DNS Manager также добавляет canary-ответы для автоматического DoH браузеров. Сторонние правила сохраняются. Произвольный DoH поверх HTTPS/443 эта настройка не гарантированно блокирует.')
  ].filter(Boolean)));
  if(st.force_both){
    ch.push(E('div',{'class':'dm-force-external'},'Принудительный DNS обнаружен одновременно с внешним перехватом. Источник: '+shortVal(st.force_source)+'. При переключении DNS Manager приведёт общую конфигурацию forced-DNS к своей схеме.'));
  } else if(st.force_owner==='external'){
    ch.push(E('div',{'class':'dm-force-external'},'Обнаружен '+shortVal(st.force_source)+'. Переключение выше может заменить его общей конфигурацией forced-DNS DNS Manager.'));
  } else if(steer){
    ch.push(E('div',{'class':'dm-inline-msg info'},'Steer перехватывает DNS :53. DNS Manager не создаёт второй перехват. Выключение настройки DNS Manager не отключает перехват Steer.'));
  } else if(Number(st.steer_running)===1 && Number(st.steer_dns_active)!==1){
    ch.push(E('div',{'class':'dm-inline-msg info'},'Steer запущен, но активный перехват DNS :53→:5300 не обнаружен. Поэтому DNS Manager не считает Steer владельцем forced-DNS и сохраняет обычную схему принудительного DNS.'));
  }
  if(state.pageNotice.doh && state.pageNotice.doh!=='Проверка текущих DNS завершена.' && !(state.currentTest && ['Текущих DNS для проверки нет.','Проверяю текущие DNS…','Проверяю системные DNS…','Проверка текущих DNS завершена с ошибками.'].indexOf(state.pageNotice.doh)!==-1))ch.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.doh));
  e.appendChild(card('DNS over HTTPS',ch));
  e.appendChild(renderBootstrap(root,st));
}

function slotLabel(slot){var m={'1':'DNS 1','2':'DNS 2','3':'DNS 3','4':'DNS 4','5':'DNS 5','6':'DNS 6','RU':'Региональный DNS'};return m[slot]||('DNS '+slot);}
function slotCurrentName(slot){var st=window.dmState||{};for(var i=0;i<(st.slots||[]).length;i++){if(String(st.slots[i].slot)===String(slot))return st.slots[i].name||st.slots[i].id||'не назначен';}return 'не назначен';}
function assignedSlotInfo(id,excludeSlot){
  var st=window.dmState||{},out=null;
  (st.slots||[]).forEach(function(d){
    if(d&&d.id===id&&String(d.slot)!==String(excludeSlot))out={slot:String(d.slot||''),name:d.name||id,port:String(d.port||'')};
  });
  return out;
}
function assign(id,slot,root,nextName){
  if(state.busy)return;
  var noticeKey=currentRoute()==='doh'?'doh':'slots';
  var occupied=assignedSlotInfo(id,slot);
  if(occupied){
    state.pageNotice[noticeKey]='DNS «'+(nextName||id)+'» уже назначен в '+slotLabel(occupied.slot)+(occupied.port?' · 127.0.0.1:'+occupied.port:'')+'. Сначала освободите тот слот.';
    render(root,window.dmState||{});
    return;
  }
  var current=slotCurrentName(slot),next=nextName||id;
  if(current===next)return;
  confirmAction('Подтвердить назначение DNS',[['Слот',slotLabel(slot)],['Сейчас',current],['Новый DNS',next]],function(){
    state.busy=true;state.pageNotice[noticeKey]='Назначаю «'+slotLabel(slot)+'»…';render(root,window.dmState||{});
    callSlot(slot,id).then(awaitSettingResult).then(function(r){
      state.busy=false;
      if(r&&r.ok){setAction(true,slotLabel(slot)+': «'+next+'».');state.pageNotice[noticeKey]='DNS назначен в '+slotLabel(slot)+'.';}
      else{setAction(false,(r&&r.error)||'DNS не удалось применить.');state.pageNotice[noticeKey]=(r&&r.error)||'DNS не удалось применить.';}
      refresh(root,true);
    }).catch(function(){state.busy=false;setAction(false,'DNS не удалось применить.');state.pageNotice[noticeKey]='DNS не удалось применить.';refresh(root,true);});
  });
}
function saveSlotDomains(slot,input,root){
  if(state.busy||!input)return;
  var raw=String(input.value||'');
  var value=raw.replace(/\r/g,'').split(/[\s,]+/).filter(Boolean).join(',');
  state.slotDomainDrafts=state.slotDomainDrafts||{};
  state.slotDomainDrafts[String(slot)]=raw;
  state.busy=true;
  state.pageNotice.slots='Применяю список доменов для '+slotLabel(slot)+'…';
  renderSlots(root,window.dmState||{});
  callSlotDomains(slot,value).then(awaitSettingResult).then(function(r){
    state.busy=false;
    if(r&&r.ok){
      delete state.slotDomainDrafts[String(slot)];
      setAction(true,'Домены для '+slotLabel(slot)+' сохранены.');
      state.pageNotice.slots='Маршруты доменов для '+slotLabel(slot)+' обновлены.';
    }else{
      var msg=(r&&r.error)||'Не удалось применить домены.';
      setAction(false,msg);state.pageNotice.slots=msg;
    }
    refresh(root,true);
  }).catch(function(err){
    state.busy=false;
    var msg=withRpcError('Не удалось применить домены.',err);
    setAction(false,msg);state.pageNotice.slots=msg;refresh(root,true);
  });
}
function refreshDeviceDnsPanels(root){
  return callLanDevices().then(function(v){
    if(!v||v.ok===false)throw new Error((v&&v.error)||'список устройств недоступен');
    window.dmLanDevices=v;
    state.lanDevicesMessage='';
    renderDeviceDns(root,window.dmState||{});
  }).catch(function(err){
    state.lanDevicesMessage=withRpcError('Не удалось обновить список устройств.',err);
    renderDeviceDns(root,window.dmState);
  });
}
function saveDeviceDns(mac,controls,root){
  if(state.busy||state.jobRunning||!controls)return;
  var selected=[];
  var inputs=controls.querySelectorAll('input.dm-device-dns-checkbox');
  Array.prototype.forEach.call(inputs,function(input){
    if(input.checked&&input.getAttribute('data-available')==='1')selected.push(String(input.value));
  });
  selected.sort(function(a,b){return Number(a)-Number(b);});
  state.busy=true;
  state.pageNotice.slots='Сохраняю привязку DNS для '+mac+'…';
  renderDeviceDns(root,window.dmState||{});
  callSetDeviceDns(String(mac||''),selected.join(',')).then(awaitSettingResult).then(function(r){
    state.busy=false;
    if(r&&r.ok){
      if(state.deviceDnsDrafts)delete state.deviceDnsDrafts[String(mac||'')];
      state.pageNotice.slots=selected.length
        ? 'Для устройства '+mac+' сохранены DNS '+selected.join(', ')+'.'
        : 'Индивидуальная привязка для '+mac+' удалена; устройство использует обычный DNS роутера.';
      setAction(true,selected.length?'Индивидуальная привязка DNS сохранена.':'Индивидуальная привязка удалена.');
    }else{
      var msg=(r&&r.error)||'Не удалось применить DNS для устройства.';
      state.pageNotice.slots=msg;setAction(false,msg);
    }
    return refreshDeviceDnsPanels(root);
  }).catch(function(err){
    state.busy=false;
    var msg=withRpcError('Не удалось применить DNS для устройства.',err);
    state.pageNotice.slots=msg;setAction(false,msg);
    renderDeviceDns(root,window.dmState||{});
  });
}

function slotOptionsForCatalog(cat){
  return String(cat||'').toLowerCase()==='regional'?['RU']:['1','2','3','4','5','6'];
}
function slotCatalogInfo(slot){
  var st=window.dmState||{},d=null;
  (st.slots||[]).forEach(function(x){if(x&&String(x.slot)===String(slot))d=x;});
  if(!d||!d.id)return {id:'',port:'',name:'не назначен',status:'',ping:''};
  var ci=checkInfo(d.id,d);
  return {id:String(d.id),port:String(d.port||''),name:d.name||d.id,status:String(ci.status||d.status||''),ping:String(ci.ping||d.ping||'')};
}
function slotCatalogOptionLabel(slot){
  var x=slotCatalogInfo(slot);
  if(x.name==='не назначен')return slotLabel(slot)+' — не назначен';
  var s=String(x.status||'').toUpperCase();
  var avail=(s==='OK')?'доступен':(s==='RUNNING'?'проверяется':'недоступен');
  var tm=hasPing(x.ping)?' · '+x.ping+' мс':'';
  return slotLabel(slot)+' — '+x.name+' · '+avail+tm;
}
function assignDirect(id,slot,root,nextName,nextUrl){
  if(state.busy||!id||!slot)return;
  var occupied=assignedSlotInfo(id,slot);
  if(occupied){
    state.pageNotice.catalog='«'+(nextName||id)+'» уже назначен в '+slotLabel(occupied.slot)+(occupied.port?' · 127.0.0.1:'+occupied.port:'')+'. Дублирование не разрешено.';
    renderCatalog(root);
    return;
  }
  var current=slotCurrentName(slot),next=nextName||id,activeUrl='';
  (window.dmState&&window.dmState.doh_instances||[]).forEach(function(x){
    if(x&&String(x.slot)===String(slot))activeUrl=String(x.url||'');
  });
  var normalizeUrl=function(u){u=String(u||'');return u.replace(/^(https:\/\/[^/]+)\/+$/i,'$1');};
  if(current===next&&normalizeUrl(activeUrl)===normalizeUrl(nextUrl))return;
  state.busy=true;
  state.pageNotice.catalog='Назначаю «'+next+'» в '+slotLabel(slot)+'…';
  renderCatalog(root);
  callSlot(slot,id).then(awaitSettingResult).then(function(r){
    state.busy=false;
    if(r&&r.ok){
      setAction(true,slotLabel(slot)+': «'+next+'».');
      state.pageNotice.catalog='«'+next+'» назначен в '+slotLabel(slot)+'.';
    }else{
      setAction(false,(r&&r.error)||'DNS не удалось назначить.');
      state.pageNotice.catalog=(r&&r.error)||'DNS не удалось назначить.';
    }
    refresh(root,true);
  }).catch(function(){
    state.busy=false;
    setAction(false,'DNS не удалось назначить.');
    state.pageNotice.catalog='DNS не удалось назначить.';
    refresh(root,true);
  });
}
function renderCatalogAssign(d,root){
  var ci=checkInfo(d.id,d);
  var checking=String(ci.status||'').toUpperCase()==='RUNNING';
  var unavailable=!checking&&!resolverAvailable(ci);
  return E('div',{'class':'dm-catalog-assign'},unavailable||checking?[]:[
    btn('Выбрать','cbi-button-neutral',function(){
      if(unavailable||checking)return;
      openCatalogSlotPicker(d,root);
    },{disabled:!!state.busy||!!state.jobRunning||unavailable||checking,title:unavailable?'DNS не прошёл последнюю проверку. Повторите проверку после восстановления.':''})
  ]);
}
function openCatalogSlotPicker(d,root){
  if(state.busy||state.jobRunning||!d)return;
  var ci=checkInfo(d.id,d);
  var checking=String(ci.status||'').toUpperCase()==='RUNNING';
  if(checking||!resolverAvailable(ci))return;
  var slots=slotOptionsForCatalog(d.category);
  var name=d.name||d.id;
  var children=[
    E('div',{'class':'dm-mini'},'Выберите слот для «'+name+'». Если слот занят другим DNS, кнопка будет помечена «Заменить».'),
    E('div',{'class':'dm-catalog-slot-picker'},[])
  ];
  var list=children[1];
  slots.forEach(function(slot){
    var info=slotCatalogInfo(slot);
    var current=String(info.id||'')===String(d.id);
    var elsewhere=assignedSlotInfo(d.id,slot);
    var occupied=!!info.id&&!current;
    var buttonText=current?'Уже назначен':(elsewhere?'Уже в '+slotLabel(elsewhere.slot):(occupied?'Заменить':'Назначить'));
    var disabled=!!state.busy||!!state.jobRunning||current||!!elsewhere;
    var main=[
      E('div',{'class':'dm-catalog-slot-title'},slotLabel(slot)),
      E('div',{'class':'dm-catalog-slot-current'},info.name==='не назначен'?'Не назначен':info.name)
    ];
    if(info.id&&info.status){
      main.push(E('div',{'class':'dm-catalog-slot-status'},stateBadge(info.status,info.ping)));
    }
    if(info.port){
      main.push(E('div',{'class':'dm-catalog-slot-port'},'127.0.0.1:'+info.port));
    }
    list.appendChild(E('div',{'class':'dm-catalog-slot-option'+(current?' is-current':'')+(occupied?' is-occupied':'')},[
      E('div',{'class':'dm-catalog-slot-main'},main),
      btn(buttonText,'cbi-button-'+(occupied?'negative':'action'),function(){
        if(disabled||state.busy||state.jobRunning)return;
        ui.hideModal();
        assignDirect(d.id,slot,root,name,d.url);
      },{disabled:disabled,title:elsewhere?'Этот DNS уже назначен в '+slotLabel(elsewhere.slot)+'. Дублирование не разрешено.':(current?'Этот DNS уже назначен в выбранный слот.':'')})
    ]));
  });
  children.push(E('div',{'class':'right'},[btn('Отмена','cbi-button-negative',ui.hideModal)]));
  ui.showModal('Назначить «'+name+'»',children);
}

function openSlotPicker(slot,root,requestedCategory,requestedOffset,preserveScroll){
  if(state.busy)return;
  var pickerScrollTop=0;
  if(preserveScroll){
    var activePickerList=document.querySelector('.dm-picker-list');
    if(activePickerList)pickerScrollTop=activePickerList.scrollTop||0;
  }
  var pickerRequest=(Number(state.slotPickerRequest)||0)+1;
  state.slotPickerRequest=pickerRequest;
  var st=window.dmState||{};
  var currentSlot=null;
  (st.slots||[]).forEach(function(d){if(String(d.slot)===String(slot))currentSlot=d;});
  var regional=String(slot)==='RU';
  var currentCategory=String(currentSlot&&currentSlot.category||'').toLowerCase();
  var selectedCategory=String(st.selection_category||'').toLowerCase();
  function selectableCategory(value){
    value=String(value||'').toLowerCase();
    return value!=='all'&&value!=='regional'&&CATEGORY.some(function(x){return x[0]===value;});
  }
  var askedCategory=String(requestedCategory||'').toLowerCase();
  var category=regional
    ? 'regional'
    : (selectableCategory(askedCategory)
      ? askedCategory
      : (selectableCategory(currentCategory)
        ? currentCategory
        : (selectableCategory(selectedCategory)?selectedCategory:'bypass')));
  var offset=Number(requestedOffset);
  if(!isFinite(offset)||offset<0)offset=0;
  offset=Math.floor(offset/48)*48;
  if(regional)offset=0;
  var profile=profileName(st.profile);
  callCatalog(category,offset,48,0).then(function(d){
    if(pickerRequest!==state.slotPickerRequest)return;
    var rows=d&&d.servers||[];
    var total=Number(d&&d.total||0);
    var cur=currentSlot&&currentSlot.name?currentSlot.name:slotCurrentName(slot);
    var list=E('div',{'class':'dm-picker-list'});
    if(!rows.length){
      list.appendChild(E('div',{'class':'dm-hint'},'В этой категории DNS не найдены.'));
    }else{
      rows.forEach(function(x){
        var ci=checkInfo(x.id,x);
        var pickerChecking=!!(state.slotPickerCheck&&String(state.slotPickerCheck.id)===String(x.id)&&String(state.slotPickerCheck.slot)===String(slot));
        var checking=pickerChecking||String(ci.status||'').toUpperCase()==='RUNNING';
        var status=checking?badge('dm-warn','проверяется…'):stateBadge(ci.status,ci.ping);
        var currentMark=x.name===cur?badge('dm-ok','выбран'):null;
        var assignedSlot='',assignedPort='';
        (st.slots||[]).forEach(function(sd){
          if(sd&&sd.id===x.id){
            assignedSlot=String(sd.slot||'');
            assignedPort=String(sd.port||'');
          }
        });
        var elsewhere=assignedSlot && assignedSlot!==String(slot);
        var occupiedMark=elsewhere
          ? badge('dm-warn','занят в '+slotLabel(assignedSlot)+(assignedPort?' · 127.0.0.1:'+assignedPort:''))
          : null;
        var unavailable=!checking&&!resolverAvailable(ci);
        var actionLabel=elsewhere?('Уже в '+slotLabel(assignedSlot)):((x.name===cur)?'Выбран':(checking?'Проверяется…':(unavailable?'Недоступен':'Выбрать')));
        var action=btn(actionLabel,'cbi-button-neutral',function(){
          if(elsewhere||unavailable||checking)return;
          if(x.name===cur){ui.hideModal();return;}
          ui.hideModal();
          assign(x.id,slot,root,x.name);
        },{disabled:!!state.busy||!!state.jobRunning||!!elsewhere||checking||(unavailable&&x.name!==cur),title:unavailable?'DNS не прошёл проверку или нет результатов. Нажмите «Проверить» перед назначением.':''});
        var check=btn(checking?'Проверяется…':'Проверить','cbi-button-neutral',function(){
          if(state.jobRunning||state.busy)return;
          state.slotPickerCheck={id:String(x.id),slot:String(slot)};
          openSlotPicker(slot,root,category,offset,true);
          testOne(x.id,root,'doh',function(){
            if(state.slotPickerCheck&&String(state.slotPickerCheck.id)===String(x.id)&&String(state.slotPickerCheck.slot)===String(slot))
              state.slotPickerCheck=null;
            openSlotPicker(slot,root,category,offset,true);
          });
        },{disabled:checking||!!state.busy||!!state.jobRunning});
        var mainChildren=[
          E('div',{'class':'dm-picker-name'},x.name||x.id),
          E('div',{'class':'dm-picker-meta'},[
            status,
            occupiedMark||currentMark||E('span',{})
          ])
        ];
        list.appendChild(E('div',{'class':'dm-picker-item'},[
          E('div',{'class':'dm-picker-main'},mainChildren),
          E('div',{'class':'dm-picker-actions'},[check,action])
        ]));
      });
    }

    var categoryControls=E('div',{'class':'dm-seg dm-slot-picker-categories'},[]);
    if(!regional){
      CATEGORY.forEach(function(c){
        if(c[0]==='all'||c[0]==='regional')return;
        categoryControls.appendChild(btn(c[1],c[0]===category?'active cbi-button':'cbi-button',function(){
          openSlotPicker(slot,root,c[0],0);
        },{disabled:!!state.busy||!!state.jobRunning}));
      });
    }
    var slotPort=currentSlot&&currentSlot.port?currentSlot.port:'';
    var occupied=currentSlot&&currentSlot.id;
    var slotInfo=occupied
      ? 'Слот '+slotLabel(slot)+' занят: '+cur+(slotPort?' · 127.0.0.1:'+slotPort:'')
      : 'Слот '+slotLabel(slot)+' свободен';
    var modalChildren=[
      E('div',{'class':'dm-slot-occupied-note'},slotInfo)
    ];
    if(!regional){
      modalChildren.push(E('div',{'class':'dm-mini'},'Выберите категорию, затем DNS из неё. Доступны все обычные категории каталога; региональные DNS назначаются только в слот RU.'));
      modalChildren.push(categoryControls);
    }else{
      modalChildren.push(E('div',{'class':'dm-mini'},'Категория: '+catName(category)));
    }
    modalChildren.push(list);
    if(!regional&&total>48){
      modalChildren.push(E('div',{'class':'dm-page'},[
        btn('←','cbi-button-neutral',function(){openSlotPicker(slot,root,category,Math.max(0,offset-48));},{disabled:offset<=0||!!state.busy||!!state.jobRunning}),
        E('span',{'class':'dm-mini'},(Math.floor(offset/48)+1)+' / '+Math.max(1,Math.ceil(total/48))+' · '+total+' DNS'),
        btn('→','cbi-button-neutral',function(){openSlotPicker(slot,root,category,offset+48);},{disabled:offset+48>=total||!!state.busy||!!state.jobRunning})
      ]));
    }
    modalChildren.push(E('div',{'class':'right'},[btn('Закрыть','cbi-button-negative',ui.hideModal)]));
    ui.showModal('Выбор DNS · '+slotLabel(slot),modalChildren);
    if(preserveScroll){
      var updatedPickerList=document.querySelector('.dm-picker-list');
      if(updatedPickerList)updatedPickerList.scrollTop=pickerScrollTop;
    }
  }).catch(function(){
    if(pickerRequest!==state.slotPickerRequest)return;
    state.pageNotice.slots='Не удалось открыть список DNS.';
    renderSlots(root,window.dmState||{});
  });
}

function profileProgressUpdate(j){
  var out=stripAnsi(j&&j.output||''), text=String(out||'');
  var stages=[
    {p:8,keys:['Запускаю применение','Подготавливаю новый набор'],label:'Подготавливаю профиль и новый набор DNS'},
    {p:16,keys:['Автоматически выбран набор DNS','подтверждено только','Проверяю DNS для профиля'],label:'Выбираю DNS из свежих результатов'},
    {p:28,keys:['Текущая DNS-схема','Текущих DNS-секций'],label:'Сверяю текущую DNS-схему'},
    {p:38,keys:['Останавливаю текущие экземпляры'],label:'Останавливаю старые экземпляры DNS'},
    {p:48,keys:['Конфигурация https-dns-proxy сохранена'],label:'Сохраняю конфигурацию DoH'},
    {p:56,keys:['Обновляю конфигурацию dnsmasq'],label:'Обновляю dnsmasq'},
    {p:64,keys:['Включаю одновременный опрос DNS'],label:'Включаю одновременный опрос DNS'},
    {p:73,keys:['Запускаю https-dns-proxy'],label:'Запускаю выбранные DoH-серверы'},
    {p:77,keys:['Перезапускаю dnsmasq'],label:'Перезапускаю dnsmasq'},
    {p:84,keys:['Обновляю правила firewall'],label:'Обновляю сетевые правила'},
    {p:89,keys:['итоговое обнаружение состояния системы','Итоговое обнаружение завершено'],label:'Проверяю итоговое состояние роутера'},
    {p:95,keys:['Проверяю dnsmasq, все локальные DoH-порты'],label:'Проверяю выбранные DNS'},
    {p:98,keys:['Все локальные проверки после применения'],label:'Проверка применения завершена'}
  ];
  var best={p:0,label:'Подготавливаю применение профиля…',detail:''};
  var mlines=text.split('\n'),mprog='';
  for(var mi=mlines.length-1;mi>=0;mi--){
    if(mlines[mi].indexOf('Промежуточный результат:')>=0){mprog=String(mlines[mi]);break;}
  }
  var mp=mprog.match(/Промежуточный результат:\s*проверено\s+(\d+)\s+из\s+(\d+)\s*\|\s*работают\s+(\d+)\s*\|\s*ошибки\s+(\d+)/i);
  if(mp){
    var md=Number(mp[1]||0),mt=Number(mp[2]||0),mo=Number(mp[3]||0),mf=Number(mp[4]||0);
    var mpp=mt>0?8+Math.round(md*14/mt):8;
    best={p:Math.max(8,Math.min(22,mpp)),label:'Проверяю DNS выбранного профиля — проверено '+md+' из '+mt,detail:''};
  }
  stages.forEach(function(s){
    var hit=false,at=-1;
    s.keys.forEach(function(k){var x=text.lastIndexOf(k);if(x>at){at=x;hit=x>=0;}});
    if(hit&&s.p>=best.p){
      best={p:s.p,label:s.label,detail:''};
    }
  });
  var done=String(j&&j.status||'').toUpperCase()==='DONE', ok=String(j&&j.result||'')==='ok';
  if(done&&ok)best={p:100,label:'Профиль применён.',detail:''};
  state.profileProgress=best;
}
function renderProfileProgress(root){
  if(!state.profileProgress)return null;
  var p=state.profileProgress||{},pct=Math.max(0,Math.min(100,Number(p.p||0)));
  var running=!!state.busy&&!!state.jobRunning;
  var title=running?'Применение профиля выполняется':(pct>=100?'Применение завершено':'Результат применения профиля');
  var body=[
    E('div',{'class':'dm-mini'},title),
    E('div',{'class':'dm-mem-line'},[
      E('div',{'class':'dm-mem-track'},[E('div',{'class':'dm-mem-fill','style':'width:'+pct+'%'})]),
      E('span',{'class':'dm-mem-value'},pct+'%')
    ]),
    E('div',{'class':'dm-profile-progress-status'},p.label||'Выполняю…')
  ];
  if(p.detail)body.push(E('div',{'class':'dm-profile-progress-detail'},p.detail));
  var out=String(state.profileOutput||'').trim();
  if(out){
    var lines=out.split('\n').filter(function(x){return String(x||'').trim();});
    body.push(E('pre',{'class':'dm-profile-output','style':'max-height:260px;overflow:auto;white-space:pre-wrap;word-break:break-word;padding:9px;border:1px solid rgba(127,127,127,.18);border-radius:7px;margin-top:8px;font:11px/1.45 ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,monospace;background:rgba(0,0,0,.04)'},lines.slice(-40).join('\n')));
  }
  return card('Ход применения',body);
}

function renderProfiles(root,st){
  var e=root.querySelector('#dm-profiles');if(!e)return;
  var oldOut=e.querySelector('.dm-profile-output');
  var oldScrollTop=oldOut?oldOut.scrollTop:0;
  var oldAtBottom=oldOut?((oldOut.scrollHeight-oldOut.clientHeight-oldOut.scrollTop)<=8):false;
  e.innerHTML='';
  if(st.dnscrypt_engine!=='dnscrypt-proxy2'&&Number(st.engine_installed)===0)return;
  var g=E('div',{'class':'dm-seg dm-profile-seg'});
  var currentId=activeProfileId(st);
  var chosenProfile=state.pendingProfile||currentId;
  var candidates=st.dnscrypt_engine==='dnscrypt-proxy2'?st.dnscrypt_profile_candidates:null;
  var nativeOnly=st.dnscrypt_engine==='dnscrypt-proxy2'&&dnscryptOptions(st).protocol==='native';
  PROFILE.forEach(function(p){
    var n=candidates&&Object.prototype.hasOwnProperty.call(candidates,p[0])?Number(candidates[p[0]]):null;
    var label=p[1]+(n===null?'':n>0?' · DNSCrypt: '+n:' · DNSCrypt нет');
    var unavailable=nativeOnly&&n===0;
    g.appendChild(btn(label,chosenProfile===p[0]?'active cbi-button':'cbi-button',function(){
      state.pendingProfile=p[0]===currentId?'':p[0];renderProfiles(root,st);
    },{disabled:unavailable||!!state.busy||!!state.jobRunning||(st.dnscrypt_engine!=='dnscrypt-proxy2'&&Number(st.engine_installed)===0),'aria-pressed':chosenProfile===p[0]?'true':'false'}));
  });
  var profileAction=((state.pendingProfile&&state.pendingProfile!==currentId)||(st.dnscrypt_engine==='dnscrypt-proxy2'&&currentId&&dnscryptOptionsChanged(st)))?E('div',{'class':'dm-actions'},[
    btn('Применить изменения','cbi-button-action',function(){var selected=state.pendingProfile||currentId;state.pendingProfile='';applyProfile(selected,root,true);},{disabled:!!state.busy||!!state.jobRunning||(nativeOnly&&candidates&&Number(candidates[state.pendingProfile||currentId])===0)})
  ]):null;
  var current=activeProfileLabel(st);
  var pch=[
    row('Работает сейчас',badge(currentId?'dm-ok':'dm-muted',current)),
    g,
    st.dnscrypt_engine==='dnscrypt-proxy2'?dnscryptOptionsControls(root,st,renderProfiles):null,
    profileAction,
    E('div',{'class':'dm-mini'},candidates?'Число DNSCrypt — серверы в каталоге, не результат проверки. В DNSSEC показаны кандидаты, которые дополнительно проверяются. В смешанном режиме также используются DoH-серверы.':'Профиль определяет схему выбора DNS.')
  ].filter(Boolean);
  if(currentId==='dnssec')pch.push(E('div',{'class':'dm-hint'},'DNSSEC проверяется выбранными серверами; фильтрация может различаться.'+(st.dnscrypt_engine==='dnscrypt-proxy2'?'':' Региональный DNS, Steer и привязки устройств работают по своим правилам.')));
  var regionalSlot=(st.slots||[]).filter(function(s){return String(s.slot)==='RU';})[0]||{};
  var regionalMode=String(st.dnscrypt_engine==='dnscrypt-proxy2'?(st.dnscrypt_regional_mode||'doh'):(st.regional_mode|| (regionalSlot.id?'legacy':'doh')));
  var hasGeneral=st.dnscrypt_engine==='dnscrypt-proxy2'?Number(st.dnscrypt_running)===1:(st.slots||[]).some(function(s){return String(s.slot)!=='RU'&&!!s.id;});
  pch.push(E('div',{'class':'dm-row','style':'margin-top:14px'},[E('span',{'class':'dm-label'},'Российские сайты и сайты СНГ')]));
  pch.push(E('p',{'class':'dm-hint'},'DNS для .ru, .su, .рф, .by, .kz и отдельных ресурсов маркетплейсов и Яндекса. Смена профиля не меняет этот выбор.'));
  var regionalChoices=E('div',{'class':'dm-seg'});
  var regionalOptions=[['doh',st.dnscrypt_engine==='dnscrypt-proxy2'?'Через DNSCrypt':'Через DoH',0],['yandex','Яндекс DNS',2],['isp','DNS провайдера',3]];
  var appliedRegional=regionalMode==='yandex'?2:regionalMode==='isp'?3:regionalMode==='legacy'?1:0;
  var regionalSelected=state.pendingRegional==null?appliedRegional:state.pendingRegional;
  regionalOptions.forEach(function(choice){
    regionalChoices.appendChild(btn(choice[1],regionalSelected===choice[2]?'active cbi-button':'cbi-button',function(){
      state.pendingRegional=choice[2]===appliedRegional?null:choice[2];renderProfiles(root,st);
    },{disabled:!!state.busy||!!state.jobRunning||!hasGeneral,'aria-pressed':regionalSelected===choice[2]?'true':'false'}));
  });
  pch.push(regionalChoices);
  if(state.pendingRegional!=null&&state.pendingRegional!==appliedRegional)pch.push(E('div',{'class':'dm-actions'},[
    btn('Применить изменения','cbi-button-action',function(){var selected=state.pendingRegional;state.pendingRegional=null;setRegional(selected,root);},{disabled:!!state.busy||!!state.jobRunning||!hasGeneral})
  ]));
  pch.push(E('p',{'class':'dm-hint'},regionalMode==='legacy'
    ? 'Сейчас выбран региональный DoH: '+String(regionalSlot.name||regionalSlot.id)+'. Он сохранён после обновления; новый режим включится только после выбора.'
    : regionalMode==='doh' ? (st.dnscrypt_engine==='dnscrypt-proxy2'?'Сейчас все сайты используют общие DNSCrypt-серверы.':'Сейчас все сайты используют общие DoH-серверы.')
    : regionalMode==='yandex' ? 'Сейчас указанные домены используют Яндекс DNS (77.88.8.8, 77.88.8.1) напрямую, без шифрования.'
    : 'Сейчас указанные домены используют DNS провайдера напрямую, без шифрования: '+String((st.dnscrypt_engine==='dnscrypt-proxy2'?st.dnscrypt_regional_ips:st.regional_isp_ips)||'—')+'.'));
  if(Number(st.steer_dns_active)===1)pch.push(E('p',{'class':'dm-hint'},'Правила DNS в Steer могут обрабатывать отдельные запросы до dnsmasq.'));
  if(!hasGeneral)pch.push(E('div',{'class':'dm-inline-msg info'},'Сначала примените основной DNS-профиль.'));
  if(state.regionalNotice)pch.push(E('div',{'class':'dm-inline-msg '+(state.regionalNoticeType||'info')},state.regionalNotice));

  var pj=String(st.profile_job_status||'').toLowerCase();
  var pp=String(st.profile_job_profile||'');
  if(pp.indexOf('server:')===0)pj='';
  var pr=String(st.profile_job_result||'').toLowerCase();
  var pm=stripAnsi(String(st.profile_job_message||'')).trim();
  var pf=String(st.profile_job_finished||'');
  var localProfileRunning=!!(state.busy&&state.profileProgress);
  if(!localProfileRunning&&pj==='running'){
    pch.push(E('div',{'class':'dm-inline-msg info'},'⟳ Сейчас выполняется: профиль «'+(pp?profileName(pp):'DNS')+'». Закрытие LuCI не останавливает операцию; при открытии она продолжится здесь.'));
  }else if(!localProfileRunning&&pf&&Number(pf)>0&&Date.now()/1000>=Number(pf)&&Date.now()/1000-Number(pf)<600&&pj==='failed'){
    var failText='✗ Последняя операция: профиль «'+(pp?profileName(pp):'DNS')+'» не применён.';
    if(pm)failText+=' Причина: '+pm;
    pch.push(E('div',{'class':'dm-inline-msg error'},failText+(pf?' · '+dateText(pf):'')));
  }

  pch.push(btn('Отключить защищённый DNS','cbi-button-negative',function(){resetDnsCore(root,'disable');},{disabled:!!state.busy}));
  if(state.profileProgress){
    var pp=renderProfileProgress(root);
    if(pp)pch.push(pp);
  }
  if(state.pageNotice.profiles)pch.push(E('div',{'class':'dm-inline-msg '+(state.profileNoticeType||'info')},state.pageNotice.profiles));
  e.appendChild(card('Профили DNS',pch));
  var newOut=e.querySelector('.dm-profile-output');
  if(newOut){
    if(oldAtBottom)newOut.scrollTop=newOut.scrollHeight;
    else newOut.scrollTop=Math.min(oldScrollTop,newOut.scrollHeight);
  }
}

function foldSection(key,summary,content,classes){
  state.openSections=state.openSections||{};
  var attrs={'class':'dm-fold '+(classes||'')};
  if(state.openSections[key])attrs.open='';
  var details=E('details',attrs,[E('summary',{},summary),content]);
  details.addEventListener('toggle',function(){state.openSections[key]=details.open;});
  return details;
}

function renderSlots(root,st){
  var e=root.querySelector('#dm-slots');if(!e)return;e.innerHTML='';
  if(st.dnscrypt_engine==='dnscrypt-proxy2'){
    var draft=dnscryptPoolDraft(st), changed=draft.items.map(function(x){return x.id;}).join(',')!==draft.base||dnscryptOptionsChanged(st);
    var poolContent=[E('p',{'class':'dm-mini'},'Выберите до шести DNS в каталоге. DNSCrypt автоматически использует доступные серверы.'),
      dnscryptOptionsControls(root,st,renderSlots),
      E('div',{'class':'dm-pool-heading'},[E('strong',{},'Ваш набор DNS'),E('span',{'class':'dm-mini'},draft.items.length+' из 6')]),dnscryptPoolRows(st,root),
      E('p',{'class':'dm-mini dm-pool-note'},'DNSCrypt выбирает рабочий сервер автоматически; порядок списка не задаёт приоритет.'),
      E('div',{'class':'dm-pool-buttons'},[btn('Выбрать в каталоге','cbi-button-neutral',function(){window.location.href=L.url('admin/services/dns-manager/catalog');}),btn('Проверить DNS','cbi-button-neutral',function(){dnscryptDiagnostic(root,false);},{disabled:!!state.busy||!!state.jobRunning})])];
    if(changed){poolContent.push(E('div',{'class':'dm-hint dm-pool-pending'},'Есть неприменённые изменения. Проверка показывает доступность только текущих серверов.'));poolContent.push(E('div',{'class':'dm-pool-buttons'},[btn('Применить набор','cbi-button-action',function(){applyDnscryptPool(root,st);},{disabled:!draft.items.length||!!state.busy||!!state.jobRunning}),btn('Отменить изменения','cbi-button-neutral',function(){try{window.sessionStorage.removeItem('dm-dnscrypt-pool');}catch(e){}state.dnscryptPoolDraft=null;state.dnscryptProtocol=null;state.dnscryptStrategy=null;renderSlots(root,st);},{disabled:!!state.busy})]));}
    if(state.dnscryptDiagnostic){var diagnosticView=dnscryptDiagnosticView();if(diagnosticView)poolContent.push(diagnosticView);}
    e.appendChild(card('DNS-серверы',poolContent));
    return;
  }
  var rows=[];
  (st.slots||[]).forEach(function(d){
    var assigned=!!d.id;
    var checking=assigned&&state.checking&&state.checking[d.id];
    var running=checking&&String(checking.status||'').toUpperCase()==='RUNNING';
    var shownStatus=running?'RUNNING':d.status;
    var shownPing=running?'':d.ping;
    var rowNode=E('div',{'class':'dm-slot-row '+(running?'dm-slot-checking':'')},[
      E('span',{'class':'dm-slot-id'},d.slot),
      E('span',{'class':'dm-slot-name'},assigned?(d.name||d.id):'Не назначен'),
      E('span',{'class':'dm-slot-endpoint'},d.port?'127.0.0.1:'+d.port:'—'),
      E('span',{'class':'dm-slot-state'},running?badge('dm-warn','проверяется…'):(assigned?stateBadge(shownStatus,shownPing):badge('dm-off','не назначен'))),
      E('span',{'class':'dm-inline'},[
        btn('Выбрать','cbi-button-neutral',function(){openSlotPicker(d.slot,root);},{disabled:running||!!state.busy||!!state.jobRunning}),
        btn(running?'Проверяю…':'Проверить','cbi-button-neutral',function(){if(assigned)testOne(d.id,root);},{disabled:!assigned||running||!!state.busy||!!state.jobRunning})
      ])
    ]);
    var children=[rowNode];
    if(String(d.slot)==='RU'){
      children.push(foldSection('slot-RU','Что направляется через региональный DNS',E('div',{'class':'dm-slot-domain-panel dm-slot-regional-panel'},[
        E('div',{'class':'dm-slot-domains-help'},assigned
          ? 'После применения настроек запросы к зонам .ru, .su и .рф направляются через назначенный здесь DNS. Правило действует и при ручной настройке DNS 1–6.'
          : 'Слот RU не назначен: отдельного маршрута для .ru, .su и .рф нет. Настройка DNS 1–6 вручную его не включает.')
      ])));
    }else{
      var initial=state.slotDomainDrafts&&Object.prototype.hasOwnProperty.call(state.slotDomainDrafts,String(d.slot))
        ? state.slotDomainDrafts[String(d.slot)] : String(d.domains||'').trim().split(/\s+/).filter(Boolean).join('\n');
      var domainAttrs={'class':'dm-slot-domains-input','rows':'2','spellcheck':'false','placeholder':'youtube.com\nexample.org'};
      if(!assigned)domainAttrs.disabled='';
      var domainInput=E('textarea',domainAttrs);
      domainInput.value=initial;
      domainInput.addEventListener('input',function(){state.slotDomainDrafts=state.slotDomainDrafts||{};state.slotDomainDrafts[String(d.slot)]=domainInput.value;});
      children.push(foldSection('slot-'+d.slot,'Домены только через '+slotLabel(d.slot),E('div',{'class':'dm-slot-domain-panel'},[
        E('div',{'class':'dm-slot-domains-help'},assigned
          ? 'Один домен на строку. Поддомены тоже пойдут через этот DNS; остальные запросы останутся в общей схеме. Для доменов на кириллице используйте Punycode.'
          : 'Чтобы привязать сайты к этому DNS, сначала нажмите «Выбрать» и назначьте резолвер в слот.'),
        E('div',{'class':'dm-slot-domain-controls'},[
          domainInput,
          btn(state.busy?'Применяю…':'Сохранить домены','cbi-button-neutral',function(){saveSlotDomains(d.slot,domainInput,root);},{disabled:!assigned||!!state.busy||!!state.jobRunning})
        ])
      ])));
    }
    rows.push(E('div',{'class':'dm-slot-entry'},children));
  });
  if(!rows.length)rows.push(E('div',{'class':'dm-hint'},'DNS пока не настроены.'));
  var sch=[
    E('div',{'class':'dm-mini'},'DNS 1–6 — общие слоты; указанные ниже домены и их поддомены пойдут через соответствующий слот. RU — отдельный региональный слот: в него выбирается DNS из категории «Региональные DNS».'),
    E('div',{'class':'dm-slot-table'},rows)
  ];
  if(state.pageNotice.slots)sch.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.slots));
  e.appendChild(card('DNS по слотам и маршруты доменов',sch));

}

function renderDeviceDns(root,st){
  var e=root.querySelector('#dm-devices');if(!e)return;e.innerHTML='';
  if(st.dnscrypt_engine==='dnscrypt-proxy2'){
    var inventory=window.dmLanDevices||{}, devices=Array.isArray(inventory.devices)?inventory.devices:[];
    var content=[E('p',{'class':'dm-hint'},'Устройства используют DNS роутера. Для отдельных DNS настройте адрес DNS на устройстве или в DHCP OpenWrt; DNSCrypt использует один общий пул.')];
    if(!inventory.ok)content.push(E('p',{'class':'dm-hint'},'Не удалось получить список устройств LAN.'));
    else if(!devices.length)content.push(E('p',{'class':'dm-hint'},'Роутер пока не обнаружил устройства LAN.'));
    else devices.forEach(function(d){content.push(E('div',{'class':'dm-row'},[E('strong',{},String(d.name||'Устройство без имени')),E('span',{},String(d.ip||'—')+' · '+String(d.mac||'—'))]));});
    content.push(btn('Обновить список','cbi-button-neutral',function(){refresh(root,true);},{disabled:!!state.busy}));
    e.appendChild(card('Устройства LAN',content));
    return;
  }
  var deviceChildren=[];
  var inventory=window.dmLanDevices||{};
  var available={};
  var slotNames={};
  (st.slots||[]).forEach(function(x){
    var n=String(x&&x.slot||'');
    if(/^[1-6]$/.test(n)){
      available[n]=!!(x.id&&x.port);
      slotNames[n]=String(x.name||x.id||'');
    }
  });
  if(state.lanDevicesMessage){
    deviceChildren.push(E('div',{'class':'dm-inline-msg info'},state.lanDevicesMessage));
  }
  if(state.pageNotice.slots)deviceChildren.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.slots));
  var devices=Array.isArray(inventory.devices)?inventory.devices:[];
  if(!inventory.ok){
    deviceChildren.push(E('div',{'class':'dm-hint'},'Не удалось получить список устройств LAN.'));
  }else if(!devices.length){
    deviceChildren.push(E('div',{'class':'dm-hint'},'Роутер пока не обнаружил устройства LAN.'));
  }else{
    var deviceRows=[];
    devices.forEach(function(d){
      var active=String(d.online)==='1';
      var name=String(d.name||'').trim()||'Устройство без имени';
      var source=String(d.source||'');
      var sourceLabel=source==='DHCP'?'DHCP-аренда':(source==='ARP'?'ARP-кэш':(source==='NDP'?'IPv6-сосед (NDP)':(source==='ASSIGN'?'сохранённая привязка':'статическая DHCP-запись')));
      var chosen=String(d.assigned_slots||'').split(',').filter(Boolean);
      var draft=state.deviceDnsDrafts&&state.deviceDnsDrafts[String(d.mac||'')];
      var selectedSlots=Array.isArray(draft)?draft:chosen;
      var options=[];
      for(var i=1;i<=6;i++){
        var key=String(i);
        var selected=selectedSlots.indexOf(key)>=0;
        var usable=available[key]===true;
        var cbAttrs={'type':'checkbox','class':'dm-device-dns-checkbox','value':key,'data-available':usable?'1':'0'};
        if(selected)cbAttrs.checked='';
        if(!usable&&!selected)cbAttrs.disabled='';
        var cb=E('input',cbAttrs);
        var optionClass='dm-device-dns-option'+(selected?' is-selected':'')+(usable?' is-available':' is-empty');
        options.push(E('label',{'class':optionClass},[
          cb,
          E('span',{'class':'dm-device-dns-option-content'},[
            E('span',{'class':'dm-device-dns-option-slot'},'DNS '+key),
            E('span',{'class':'dm-device-dns-option-name'},usable?(slotNames[key]||'Назначен'):'Слот пуст')
          ])
        ]));
      }
      var controls=E('div',{'class':'dm-device-dns-options'},options);
      controls.addEventListener('change',function(){
        state.deviceDnsDrafts=state.deviceDnsDrafts||{};
        state.deviceDnsDrafts[String(d.mac||'')]=Array.prototype.filter.call(controls.querySelectorAll('input.dm-device-dns-checkbox'),function(input){return input.checked;}).map(function(input){return String(input.value);});
      });
      var statusText=active?'В сети':(source==='ASSIGN'?'Не в сети · привязка сохранена':'Неактивно');
      var effectiveText=chosen.length
        ? 'DNS '+chosen.join(', ')+' назначены этому устройству.'
        : 'Индивидуальная привязка не задана; используется обычный DNS-маршрут роутера.';
      var savedWarning=chosen.some(function(n){return available[n]!==true;})
        ? E('div',{'class':'dm-inline-msg info'},'В привязке есть слот, который сейчас не назначен. При сохранении он будет удалён из выбора.')
        : null;
      var deviceHeading=E('span',{'class':'dm-device-dns-head'},[
          E('div',{'class':'dm-device-dns-name'},name),
          E('span',{'class':'dm-device-dns-status '+(active?'is-online':'is-offline')},statusText)
        ]);
      var children=[
        E('div',{'class':'dm-device-dns-meta'},[
          E('div',{'class':'dm-device-dns-meta-item'},[
            E('span',{'class':'dm-device-dns-meta-label'},'IP'),
            E('span',{'class':'dm-device-dns-meta-value'},d.ip||'—')
          ]),
          E('div',{'class':'dm-device-dns-meta-item'},[
            E('span',{'class':'dm-device-dns-meta-label'},'MAC'),
            E('span',{'class':'dm-device-dns-meta-value dm-device-dns-mac'},d.mac||'—')
          ]),
          E('div',{'class':'dm-device-dns-meta-item'},[
            E('span',{'class':'dm-device-dns-meta-label'},'Источник'),
            E('span',{'class':'dm-device-dns-meta-value'},sourceLabel)
          ])
        ]),
        E('div',{'class':'dm-device-dns-current '+(chosen.length?'has-selection':'')},[
          E('span',{'class':'dm-device-dns-current-label'},chosen.length?'Индивидуальный выбор':'Общий маршрут'),
          E('span',{'class':'dm-device-dns-current-value'},effectiveText)
        ]),
        E('div',{'class':'dm-device-dns-section-title'},'Использовать DoH'),
        E('div',{'class':'dm-device-dns-section-help'},'Отметьте один или несколько назначенных DNS-слотов.'),
        controls
      ];
      if(savedWarning)children.push(savedWarning);
      children.push(E('div',{'class':'dm-device-dns-actions'},[
        btn(state.busy?'Сохраняю…':'Сохранить привязку','cbi-button-apply dm-device-dns-save',function(){saveDeviceDns(d.mac,controls,root);},{disabled:!!state.busy||!!state.jobRunning})
      ]));
      deviceRows.push(E('div',{'class':'dm-slot-entry dm-device-dns-entry'},[
        foldSection('device-'+String(d.mac||''),deviceHeading,E('div',{'class':'dm-device-fold-body'},children),'dm-device-fold')
      ]));
    });

    deviceChildren.push(E('div',{'class':'dm-slot-table'},deviceRows));
  }
  deviceChildren.push(E('div',{'class':'dm-device-dns-note'},[
    E('div',{'class':'dm-device-dns-note-title'},'ⓘ О привязке устройств'),
    E('div',{'class':'dm-device-dns-note-text'},'Список объединяет DHCP-аренды, IPv4 ARP, IPv6 NDP и статические DHCP-записи.'),
    E('div',{'class':'dm-device-dns-note-text'},'Привязка действует для обычного DNS на порту 53. Собственный DoH через HTTPS/443 и DoT на порту 853 не перенаправляются.'),
    E('div',{'class':'dm-device-dns-note-text'},'После подключения нового устройства нажмите «Обновить список устройств».')
  ]));
  deviceChildren.push(E('div',{'class':'dm-actions'},[
    btn(state.lanDevicesLoading?'Обновляю список…':'Обновить список устройств','cbi-button-neutral',function(){
      if(state.lanDevicesLoading||state.busy||state.jobRunning)return;
      state.lanDevicesLoading=true;
      state.lanDevicesMessage='Обновляю список устройств LAN… Пожалуйста, подождите.';
      renderDeviceDns(root,window.dmState||{});
      callLanDevices().then(function(r){
        window.dmLanDevices=r||{ok:false,devices:[]};
        state.lanDevicesLoading=false;
        if(window.dmLanDevices.ok){
          var count=Array.isArray(window.dmLanDevices.devices)?window.dmLanDevices.devices.length:0;
          state.lanDevicesMessage=count
            ? 'Список обновлён. Найдено устройств: '+count+'.'
            : 'Список обновлён, но устройства LAN не обнаружены. Проверьте DHCP-аренды и таблицу соседей роутера.';
        }else{
          state.lanDevicesMessage=(window.dmLanDevices.error||'Не удалось получить список устройств LAN.');
        }
        renderDeviceDns(root,window.dmState||{});
      }).catch(function(err){
        state.lanDevicesLoading=false;
        state.lanDevicesMessage=withRpcError('Не удалось обновить список устройств.',err);
        renderDeviceDns(root,window.dmState||{});
      });
    },{disabled:!!state.lanDevicesLoading||!!state.busy||!!state.jobRunning})
  ]));
  e.appendChild(card('Устройства LAN — привязка к DoH',deviceChildren));
}

function settingCard(root,x,st){
  var en=yes(st[x[0]]),busy=state.busySetting===x[0],feedback=settingFeedback(x[1],x[0]),sv=settingStateView(st,x[0]);
  var active=(settingModuleState(st,x[0])===1)||((settingModuleState(st,x[0])===-1)&&en);
  var actionLabel=sv.text==='другое'?'Исправить':(active?'Выключить':'Включить');
  var actionEnabled=sv.text==='другое'?1:(active?0:1);
  var actions=[
    badge(busy?'dm-warn':sv.kind,busy?'изменение':sv.text),
    btn(busy?'Сохраняю…':actionLabel,busy?'cbi-button-neutral':(actionEnabled?'cbi-button-add':'cbi-button-remove'),function(){setSetting(x[0],actionEnabled,root);},{disabled:!!state.busy})
  ];
  if(feedback)actions.push(feedback);
  return E('div',{'class':'dm-card dm-setting '+(busy?'dm-setting-saving':'')},[
    E('div',{'class':'dm-setting-text'},[
      E('div',{'class':'dm-setting-title'},x[1]),
      E('div',{'class':'dm-setting-desc'},x[2])
    ]),
    E('div',{'class':'dm-setting-controls'},[
      E('div',{'class':'dm-setting-actions'},actions)
    ])
  ]);
}
function watchdogSlotResult(st,slot,id){
  if(!slot||!id)return null;
  var records=Array.isArray(st.watchdog_last_records)?st.watchdog_last_records:[];
  var record=records.filter(function(d){return String(d.slot||'')===String(slot)&&String(d.id||'')===String(id);})[0];
  if(!record)return null;
  var status=String(record.status||'SKIPPED');
  var kind=status==='OK'?'dm-ok':(status==='SKIPPED'?'dm-off':'dm-bad');
  var label=status==='OK'?'доступен':status==='FAIL'?'не отвечает':status==='NO_LISTENER'?'нет локального порта':'не проверен';
  return badge(kind,'Авто: '+label);
}

function settingToggle(root,title,desc,enabled,key,disabled,disabledReason,statusText){
  var saving=state.busySetting===key;
  var locked=!!state.busy||!!state.jobRunning||!!disabled;
  var attrs={'type':'button','class':'dm-toggle-card'+(enabled?' is-on':''),'aria-pressed':enabled?'true':'false','click':function(){if(!locked)setSetting(key,enabled?0:1,root);}};
  if(locked)attrs.disabled=true;
  var status=saving?'изменение':(statusText||(enabled?'включено':'выключено'));
  var action=saving?'Применяется…':(disabledReason|| (enabled?'Нажмите, чтобы выключить':'Нажмите, чтобы включить'));
  var feedback=settingFeedback('',key);
  return E('div',{'class':'dm-toggle-wrap'},[
    E('button',attrs,[
      E('span',{'class':'dm-toggle-main'},[E('span',{'class':'dm-setting-title'},title),E('span',{'class':'dm-setting-desc'},desc)]),
      E('span',{'class':'dm-toggle-side'},[badge(saving?'dm-warn':(enabled?'dm-ok':'dm-muted'),status),E('span',{'class':'dm-toggle-action'},action)])
    ]),
    feedback?E('div',{'class':'dm-toggle-feedback'},[feedback]):null
  ].filter(Boolean));
}
function watchdogCard(root,st){
  var en=yes(st.watchdog);
  var auto=yes(st.watchdog_autoreplace);
  var busy=state.busySetting==='watchdog' || state.busySetting==='watchdog_autoreplace' || state.busySetting==='watchdog_batch';
  var service=Number(st.watchdog_service||0)===1;
  var loop=Number(st.watchdog_loop||0)===1;
  var inputs={};

  function minuteValue(seconds,fallback){
    var n=Number(seconds);
    if(!isFinite(n)||n<=0)n=fallback;
    return Math.max(1,Math.round(n/60));
  }
  function param(name,title,min,max,unit,desc,minutes){
    var value=minutes?minuteValue(st[name],min):Number(st[name]||min);
    var input=E('input',{'type':'number','min':String(min),'max':String(max),'step':'1','value':String(state.watchdogCooldownDraft==null?value:state.watchdogCooldownDraft),'class':'dm-input'});
    input.addEventListener('input',function(){state.watchdogCooldownDraft=input.value;save.style.display=String(input.value)===String(value)?'none':'';});
    inputs[name]=input;
    return E('div',{'class':'dm-watchdog-row'},[
      E('div',{},[
        E('div',{'class':'dm-setting-title'},title),
        E('div',{'class':'dm-setting-desc'},desc)
      ]),
      input,
      E('span',{'class':'dm-setting-range'},min+'–'+max+' '+unit)
    ]);
  }

  var intervalMinutes=2;
  var failThreshold=3;
  var cooldownMinutes=minuteValue(st.watchdog_repair_cooldown,5);
  var spec=[
    ['watchdog_repair_cooldown','Пауза между попытками восстановления DNS',5,120,'мин','Минимальная пауза перед следующей попыткой восстановления или замены того же слота.',true]
  ];
  var save=btn(busy?'Сохраняю…':'Сохранить настройки','cbi-button-apply',function(){
    if(state.busy)return;
    var values=[],invalid='';
    spec.forEach(function(x){
      var raw=String(inputs[x[0]].value||'').trim(),n=Number(raw);
      var valid=raw!==''&&isFinite(n)&&n>=x[2]&&n<=x[3]&&(x[6]||/^\d+$/.test(raw));
      if(!valid){if(!invalid)invalid=x[1]+': от '+x[2]+' до '+x[3]+' '+x[4]+'.';return;}
      values.push(x[6]?Math.round(n*60):Math.round(n));
    });
    if(invalid){
      setSettingFeedback('watchdog_batch',invalid,'error');
      renderNetwork(root,window.dmState||{});
      return;
    }
    var restarts=Number(st.watchdog_max_restarts||2);
    if(!isFinite(restarts)||restarts<1||restarts>5)restarts=2;
    var guard=Number(st.watchdog_guard_interval||3600);
    if(!isFinite(guard)||guard<900||guard>10800)guard=3600;
    clearSettingFeedback();
    state.busy=true;state.busySetting='watchdog_batch';
    renderNetwork(root,window.dmState||{});
    callWatchdogSettings(120,3,values[0],Math.round(restarts),Math.round(guard)).then(awaitSettingResult).then(function(r){
      state.busy=false;state.busySetting='';
      if(r&&r.ok)state.watchdogCooldownDraft=null;
      setSettingFeedback('watchdog_batch',r&&r.ok?'Настройки проверки сохранены.':((r&&r.error)||'Не удалось сохранить настройки контроля.'),r&&r.ok?'ok':'error');
      refresh(root,true);
    }).catch(function(err){
      state.busy=false;state.busySetting='';
      setSettingFeedback('watchdog_batch',withRpcError('Не удалось сохранить настройки контроля.',err),'error');
      refresh(root,true);
    });
  },{disabled:!!state.busy});

  save.style.display=state.watchdogCooldownDraft!=null&&String(state.watchdogCooldownDraft)!==String(cooldownMinutes)?'':'none';

  function toggleRow(title,desc,enabled,key,disabled){
    return settingToggle(root,title,desc,enabled,key,disabled,disabled?'Сначала включите проверку DNS.':'');
  }

  var feedback=settingFeedback('','watchdog_batch')||E('span',{'class':'dm-setting-feedback'});
  return E('div',{'class':'dm-watchdog-card'},[
    E('div',{'class':'dm-section-title'},'Контроль текущих DNS'),
    E('div',{'class':'dm-setting-desc'},'Контроль выполняется каждые '+intervalMinutes+' мин: проверяется локальный порт назначенного DoH и DNS-ответ на запрос example.com (для слота RU — yandex.ru). Это проверка рабочего пути, а не полный тест каталога DNS. Профиль не требуется.'),
    toggleRow('Проверка DNS','Проверяет DoH в слотах или системные DoH, если слоты не заданы.',en,'watchdog',false),
    toggleRow('Автозамена DNS','После '+failThreshold+' ошибок подряд ищет рабочий DNS той же категории. При общем сбое замену откладывает; повторная попытка — не раньше чем через '+cooldownMinutes+' мин. Системные и пользовательские DoH не заменяются.',auto,'watchdog_autoreplace',!en),
    E('div',{'class':'dm-hint'},'Разовая проверка текущих DoH и дополнительных системных экземпляров доступна на вкладке «Защищённый DNS» кнопкой «Проверить текущие DNS». Она проверяет реальные DoH-endpoint’ы и не включает периодический контроль.'),
    E('details',{'class':'dm-watchdog-advanced'},[
      E('summary',{},'Дополнительные параметры'),
      E('div',{'class':'dm-watchdog-list'},spec.map(function(x){return param(x[0],x[1],x[2],x[3],x[4],x[5],x[6]);})),
      E('div',{'class':'dm-watchdog-save'},[save,feedback])
    ])
  ]);
}

function renderTestAgeCommon(root,st){
  var current=Number(st.test_age_common)||6;
  var locked=!!state.busy||!!state.jobRunning;
  var presets=[[1,'1 час'],[6,'6 часов'],[12,'12 часов'],[24,'1 день'],[72,'3 дня'],[168,'7 дней']];
  if(!presets.some(function(p){return p[0]===current;}))presets.push([current,current+' ч · текущий']);
  var choices=E('div',{'class':'dm-seg'});
  presets.forEach(function(p){
    var active=current===p[0];
    choices.appendChild(btn(p[1],active?'active cbi-button':'cbi-button',function(){
      if(locked||active)return;
      state.busy=true;state.busySetting='testages';clearSettingFeedback();
      setSettingFeedback('testages','Сохраняю срок результатов…','info');renderCatalog(root);
      callTestAge('all',p[0]).then(awaitSettingResult).then(function(r){
        state.busy=false;state.busySetting='';
        if(r&&r.ok)setSettingFeedback('testages','Срок результатов проверки сохранён.','ok');
        else setSettingFeedback('testages',(r&&r.error)||'Срок результатов проверки не удалось сохранить.','error');
        return refresh(root,true);
      }).catch(function(err){
        state.busy=false;state.busySetting='';setSettingFeedback('testages',withRpcError('Срок результатов проверки не удалось сохранить.',err),'error');refresh(root,true);
      });
    },{disabled:locked,'aria-pressed':active?'true':'false'}));
  });
  return card('Срок результатов проверки',[
    E('div',{'class':'dm-setting-desc'},'Как долго считать результаты проверки DNS актуальными.'),
    choices,settingFeedback('','testages')
  ].filter(Boolean));
}

function cacheCard(root,st){
  var currentTotal=Number(st.cache_total==null?1000:st.cache_total), currentTtl=Number(st.cache_ttl)||0;
  var values=state.cacheDraft||{total:currentTotal,ttl:currentTtl}, locked=!!state.busy||!!state.jobRunning;
  var sizes=[[1000,'Стандартный','1 000 записей'],[4096,'Расширенный','4 096 записей'],[10000,'Большой','10 000 записей']];
  var times=[[0,'Как у DNS-сервера'],[300,'5 минут'],[900,'15 минут'],[1800,'30 минут']];
  function apply(key,value){
    if(state.busy||state.jobRunning||values[key]===value)return;
    var next={total:currentTotal,ttl:currentTtl};next[key]=value;
    state.cacheDraft=next;state.busy=true;state.busySetting='dns_cache';
    setSettingFeedback('dns_cache','Применяю настройки…','info');renderNetwork(root,st);
    callSetCache(next.total,next.ttl).then(awaitSettingResult).then(function(r){
      state.cacheDraft=null;
      setSettingFeedback('dns_cache',r&&r.ok?'Настройки кэша сохранены.':((r&&r.error)||'Не удалось применить кэш.'),r&&r.ok?'ok':'error');
      return refresh(root,true);
    }).catch(function(e){state.cacheDraft=null;setSettingFeedback('dns_cache',withRpcError('Не удалось применить кэш.',e),'error');return refresh(root,true);}).finally(function(){
      state.busy=false;state.busySetting='';renderNetwork(root,window.dmState||st);
    });
  }
  function choices(items,key){
    var group=E('div',{'class':'dm-seg'});
    items.forEach(function(x){
      var active=values[key]===x[0];
      group.appendChild(btn(x[1]+(x[2]?' · '+x[2]:''),active?'active cbi-button':'cbi-button',function(){apply(key,x[0]);},{disabled:locked||active,'aria-pressed':active?'true':'false'}));
    });
    if(!items.some(function(x){return x[0]===values[key];}))group.appendChild(E('span',{'class':'dm-setting-desc'},'Текущее значение: '+values[key]+(key==='total'?' записей':' сек.')));
    return group;
  }
  return E('div',{'class':'dm-card'},[
    E('div',{'class':'dm-section-title'},'Кэш DNS'),
    E('div',{'class':'dm-setting-desc'},'Кэш основного DNS роутера. Для привязанных устройств кэш отключён. Кэш Steer настраивается отдельно.'),
    E('div',{'class':'dm-section-title'},'Размер кэша'),choices(sizes,'total'),
    E('div',{'class':'dm-section-title'},'Минимальное время хранения'),choices(times,'ttl'),
    E('div',{'class':'dm-setting-desc'},'Если DNS-сервер задал больший срок, он сохраняется. Увеличение срока может сохранять устаревшие адреса.'),
    settingFeedback('','dns_cache')
  ].filter(Boolean));
}
function renderNetwork(root,st){
  var e=root.querySelector('#dm-network');if(!e)return;e.innerHTML='';
  var body=st.dnscrypt_engine==='dnscrypt-proxy2'
    ? [E('div',{'class':'dm-watchdog-card'},[
        settingToggle(root,'Проверка DNS','Каждые 2 минуты проверяется ответ локального DNSCrypt. Ответ может быть из кэша. При сбое настройки DNS не изменяются.',yes(st.watchdog),'watchdog',false),
        yes(st.watchdog)&&Number(st.watchdog_last_failed)>0&&(st.watchdog_last_records||[]).some(function(r){return r.id==='dnscrypt_pool'&&r.status==='FAIL';})?E('div',{'class':'dm-inline-msg error'},'DNSCrypt не ответил при последней проверке ('+dateText(st.watchdog_last_check)+'). Проверьте подключение и DNS-серверы.'):null,
        E('div',{'class':'dm-setting-desc'},'DNSCrypt автоматически выбирает доступные серверы из выбранного набора. Профиль не меняется.'),
        settingToggle(root,'Принудительный DNS','Направляет обычные DNS-запросы устройств на DNS роутера через dnsmasq. При активном перехвате Steer используется его правило.',Number(st.dnscrypt_forced_dns)===1,'force',Number(st.steer_dns_active)===1&&Number(st.dnscrypt_forced_dns)!==1,Number(st.steer_dns_active)===1&&Number(st.dnscrypt_forced_dns)!==1?'Управляется Steer.':'',Number(st.dnscrypt_forced_dns)===1?'включён':Number(st.steer_dns_active)===1?'работает Steer':'выключен')
      ].filter(Boolean))]
    : [watchdogCard(root,st), cacheCard(root,st)];
  e.appendChild(card('Сетевой тюнинг',body));
  if(st.dnscrypt_engine==='dnscrypt-proxy2'){
    var noPool=!(st.dnscrypt_servers||[]).length;
    var why=noPool?'Сначала настройте набор DNS-серверов.':'';
    var cacheLocked=noPool||!yes(st.dc_cache)||!!state.busy||!!state.jobRunning;
    function cacheOptions(key,current,options){
      return E('div',{'class':'dm-seg'},options.map(function(option){
        var selected=Number(current)===option[0];
        return btn(option[1],selected?'active cbi-button':'cbi-button',function(){setSetting(key,option[0],root);},{disabled:cacheLocked||selected,'aria-pressed':selected?'true':'false'});
      }));
    }
    e.appendChild(card('Настройки DNSCrypt',[
      settingToggle(root,'Кэш DNSCrypt','Сохраняет ответы DNS до истечения срока их действия.',yes(st.dc_cache),'dc_cache',noPool,why),
      E('div',{'class':'dm-section-title'},'Размер кэша'),
      cacheOptions('dc_cache_size',st.dc_cache_size==null?4096:st.dc_cache_size,[[1000,'Стандартный · 1 000'],[4096,'Расширенный · 4 096'],[10000,'Большой · 10 000']]),
      settingFeedback('','dc_cache_size'),
      E('div',{'class':'dm-section-title'},'Минимальное время хранения'),
      cacheOptions('dc_cache_ttl',st.dc_cache_ttl==null?0:st.dc_cache_ttl,[[0,'Как у DNS-сервера'],[300,'5 минут'],[900,'15 минут'],[1800,'30 минут']]),
      E('div',{'class':'dm-setting-desc'},'Увеличение срока может сохранять устаревшие адреса.'),
      settingFeedback('','dc_cache_ttl'),
      settingToggle(root,'Только TCP','Использовать TCP для связи с серверами. Некоторые серверы могут не поддерживать этот режим.',yes(st.dc_force_tcp),'dc_force_tcp',noPool,why),
      settingToggle(root,'Блокировать IPv6-ответы','Возвращать пустой ответ на запросы адресов IPv6 (AAAA).',yes(st.dc_block_ipv6),'dc_block_ipv6',noPool,why),
      settingToggle(root,'Блокировать короткие имена','Не отправлять в интернет запросы имён без точки.',yes(st.dc_block_unqualified),'dc_block_unqualified',noPool,why),
      settingToggle(root,'Блокировать локальные домены','Не отправлять в интернет запросы служебных и локальных доменных зон.',yes(st.dc_block_undelegated),'dc_block_undelegated',noPool,why),
      settingToggle(root,'Журнал запросов','Записывает запрошенные домены во временную память роутера. Содержимое удаляется после перезагрузки.',yes(st.dc_query_log),'dc_query_log',noPool,why)
    ]));
  }
  var browserEnabled=yes(st.browser_dns), browserLoaded=yes(st.browser_dns_loaded);
  e.appendChild(card('Браузеры и DNS',[
    E('div',{'class':'dm-row'},[E('span',{'class':'dm-label'},'Предлагать браузерам использовать DNS роутера'),badge(browserEnabled?(browserLoaded?'dm-ok':'dm-bad'):'dm-off',browserEnabled?(browserLoaded?'настроено':'не применено'):'выключено')]),
    E('p',{'class':'dm-mini'},'Подсказывает Firefox и Частному узлу iCloud не включать собственный DNS автоматически. Ручные настройки браузеров могут это игнорировать.'),
    E('div',{'class':'dm-seg'},[
      btn('Включено',browserEnabled?'active cbi-button':'cbi-button',function(){setSetting('browser_dns',1,root);},{disabled:!!state.busy||!!state.jobRunning||(browserEnabled&&browserLoaded),'aria-pressed':browserEnabled?'true':'false'}),
      btn('Выключено',!browserEnabled?'active cbi-button':'cbi-button',function(){setSetting('browser_dns',0,root);},{disabled:!!state.busy||!!state.jobRunning||!browserEnabled,'aria-pressed':!browserEnabled?'true':'false'})
    ]),
    settingFeedback('','browser_dns'),
    E('div',{'class':'dm-mini'},'После выключения те же подсказки могут остаться из-за других настроек. Правила Steer и DNS отдельных устройств также могут обрабатывать запросы отдельно.')
  ].filter(Boolean)));
}
function ntpPresetName(p){
  var map={
    vniiftri_moscow:'ВНИИФТРИ',
    nist_ip:'NIST',
    cf_ip:'Cloudflare',
    google_ip:'Google',
    openwrt_default:'Стандарт OpenWrt',
    other:'ДРУГОЕ'
  };
  return map[String(p||'')]||'Не выбран';
}
function ntpPresetServers(p){
  var map={
    vniiftri_moscow:'89.109.251.21, 89.109.251.22, 89.109.251.23, 89.109.251.24, 89.109.251.25',
    nist_ip:'129.6.15.28, 129.6.15.29, 129.6.15.30, 129.6.15.27, 129.6.15.26',
    cf_ip:'162.159.200.1, 162.159.200.123',
    google_ip:'216.239.35.0, 216.239.35.4, 216.239.35.8, 216.239.35.12'
  };
  return map[String(p||'')]||'';
}
function ntpActualPreset(servers){
  var cur=String(servers||'').trim().split(/\s+/).filter(function(x){return x;}).join(' ');
  if(!cur)return 'none';
  if(cur==='0.openwrt.pool.ntp.org 1.openwrt.pool.ntp.org 2.openwrt.pool.ntp.org 3.openwrt.pool.ntp.org')return 'openwrt_default';
  var ids=['vniiftri_moscow','nist_ip','cf_ip','google_ip'];
  for(var i=0;i<ids.length;i++){
    var expected=String(ntpPresetServers(ids[i])||'').split(',').map(function(x){return String(x).trim();}).filter(function(x){return x;}).join(' ');
    if(cur===expected)return ids[i];
  }
  return 'other';
}
function renderTime(root,st){
  var e=root.querySelector('#dm-time');if(!e)return;e.innerHTML='';
  var preset=String(st.ntp_preset||'');
  var servers=String(st.ntp_servers||'').trim();
  preset=ntpActualPreset(servers);
  var selected=ntpPresetName(preset);
  var body=[];
  body.push(E('div',{'class':'dm-hint'},'Настройка серверов точного времени роутера через стандартный system.ntp/sysntpd.'));
  body.push(E('div',{'class':'dm-grid2'},[
    row('Выбранный набор',selected)
  ]));
  body.push(E('div',{'class':'dm-section-title'},'Текущие серверы времени'));
  if(servers){
    body.push(E('div',{'class':'dm-log','style':'max-height:none;overflow:visible'},servers.split(/\s+/).filter(function(x){return x;}).map(function(x){return x;}).join('\n')));
  }else{
    body.push(E('div',{'class':'dm-hint'},'Серверы времени не настроены.'));
  }
  var presets=[
    ['vniiftri_moscow','ВНИИФТРИ','Российские серверы времени по IP'],
    ['nist_ip','NIST','Серверы NIST по IP'],
    ['cf_ip','Cloudflare','Серверы Cloudflare по IP'],
    ['google_ip','Google','Серверы Google по IP']
  ];
  body.push(E('div',{'class':'dm-section-title'},'Наборы серверов'));
  presets.forEach(function(x){
    var active=preset===x[0];
    var locked=!!state.busy||!!state.jobRunning;
    var attrs={'type':'button','class':'dm-toggle-card'+(active?' is-on':''),'aria-pressed':active?'true':'false','click':function(){
      if(locked||active)return;
      state.busy=true;state.busySetting='ntp';state.pageNotice.time='Применяю набор серверов времени…';state.timeNoticeType='info';
      renderTime(root,window.dmState||{});
      callNtp(x[0]).then(awaitSettingResult).then(function(r){
        state.busy=false;state.busySetting='';
        if(r&&r.ok){
          state.timeNoticeType='ok';state.pageNotice.time='Набор серверов времени «'+x[1]+'» применён.';
          return refresh(root,true);
        }
        state.timeNoticeType='error';state.pageNotice.time=(r&&r.error)||'Не удалось применить набор серверов времени.';
        renderTime(root,window.dmState||{});
      }).catch(function(err){
        state.busy=false;state.busySetting='';state.timeNoticeType='error';
        state.pageNotice.time=withRpcError('Не удалось применить серверы точного времени.',err);
        renderTime(root,window.dmState||{});
      });
    }};
    if(locked)attrs.disabled=true;
    body.push(E('div',{'style':'margin-bottom:8px'},[E('button',attrs,[
      E('span',{'class':'dm-toggle-main'},[E('span',{'class':'dm-setting-title'},x[1]),E('span',{'class':'dm-setting-desc'},x[2]+' · '+ntpPresetServers(x[0]))]),
      E('span',{'class':'dm-toggle-side'},[badge(active?'dm-ok':'dm-muted',active?'выбрано':'выбрать')])
    ])]));
  });
  if(state.pageNotice.time)body.unshift(E('div',{'class':'dm-inline-msg '+(state.timeNoticeType||'info')},state.pageNotice.time));
  e.appendChild(card('Серверы точного времени',body));
}

function saveCustomDns(nameInput,urlInput,root){
  if(state.busy||!nameInput||!urlInput)return;
  var name=String(nameInput.value||'').trim();
  var url=String(urlInput.value||'').trim();
  state.customDnsDraft={name:name,url:url};
  if(!name||!url){
    state.customDnsNotice={type:'error',text:'Заполните название DNS и HTTPS URL DoH.'};
    renderCatalog(root);
    return;
  }
  state.busy=true;
  state.customDnsNotice={type:'info',text:'Сохраняю пользовательский DoH…'};
  renderCatalog(root);
  callAddCustomDns(name,url).then(awaitSettingResult).then(function(r){
    state.busy=false;
    if(r&&r.ok){
      state.category='custom';
      state.offset=0;
      window.dmCatalog=null;
      state.catalogLoaded=false;
      state.customDnsDraft={name:'',url:''};
      state.customDnsNotice={type:'ok',text:'DNS «'+(r.name||name)+'» добавлен. Откройте «Мои DNS», проверьте его и назначьте в слот.'};
      setAction(true,'Пользовательский DoH добавлен.');
      refresh(root,true);
    }else{
      var msg=(r&&r.error)||'Не удалось сохранить пользовательский DoH.';
      state.customDnsNotice={type:'error',text:msg};
      renderCatalog(root);
    }
  }).catch(function(err){
    state.busy=false;
    var msg=withRpcError('Не удалось сохранить пользовательский DoH.',err);
    state.customDnsNotice={type:'error',text:msg};
    renderCatalog(root);
  });
}

// Use the current official display names even when an older catalog is installed.
var CATALOG_DISPLAY_NAMES={"quic_best":"QUIC DNS [RU/EU]","semqka":"Semqka DNS [RU/EU]","tamaev":"Tamaev DNS [RU/EU]","mafioznik":"Mafioznik DNS [RU/EU]","mafioznik_xyz":"Mafioznik DNS XYZ [RU/EU]","astracat":"AstraCat DNS [RU/EU]","malw_link":"Malw.link [Global]","malw_cloudflare":"Malw.link Cloudflare [Global]","geohide":"GeoHide DNS [RU]","geohide_8443":"GeoHide DNS :8443 [RU]","geohide_eu":"GeoHide EU [EU]","geohide_us":"GeoHide US [US]","comss_bypass":"Comss.one [RU/EU]","dns_ai_ru":"DNS-AI.RU [RU/EU]","magicdns":"MagicDNS [RU/EU]","wlrus":"Wlrus DNS [RU/EU]","geodema":"Geodema DNS [RU/EU]","bezmezhau":"Bezmezhau DNS [RU/EU]","dagami":"Dagami DNS [RU/EU]","webshift":"WebShift DNS [RU/EU]","yo1nk":"YO1NK DNS [RU/EU]","zapret_moe":"Zapret.moe DNS [RU/EU]","shecan":"Shecan [Asia]","nulls_proxy":"NullsProxy DNS [Global]","xbox_dns":"Xbox DNS [RU/EU]","bebas_unfiltered":"BebasDNS Unfiltered [Asia]","dns4all":"DNS4all [EU]","dns4eu_unfiltered":"DNS4EU Unfiltered [EU]","cloudflare_clean":"Cloudflare [Global]","google_clean":"Google Public DNS [Global]","quad9_unfiltered":"Quad9 Unsecured [Global]","adguard_unfiltered":"AdGuard Unfiltered [Global]","controld_p0":"Control D Unfiltered [Global]","controld_uncensored":"Control D Uncensored [Global]","he_public":"Hurricane Electric Public Recursor [US]","18bit_cn":"18Bit DNS [Asia]","aa_dns":"Andrews & Arnold [EU]","aquilenet":"Aquilenet DNS [EU]","belnet":"Belnet DNS [EU]","cynthia":"CynthiaLabs DNS [Global]","digitalsize":"DigitalSize DNS [EU]","dnshome":"DNSHome [EU]","one_dns_pure":"OneDNS Pure [Asia]","dns_pub":"DNSPod Public DNS [Asia]","dns_fdn0":"FDN DNS 0 [EU]","dns_fdn1":"FDN DNS 1 [EU]","doh_lacontrevoie":"LaContreVoie DNS [EU]","doh_seby":"Seby DNS [Global]","dns_surfshark":"Surfshark DNS [Global]","hostux":"Hostux DNS [EU]","nextdns_fast":"NextDNS [Global]","nextdns_anycast":"NextDNS Anycast [Global]","dns_sb":"DNS.SB [Global]","cubedns":"CubeDNS [Global]","applied_privacy":"Applied Privacy [EU]","cznic_odvr":"CZ.NIC ODVR [EU]","digitale_gesellschaft":"Digitale Gesellschaft [EU]","cira_private":"CIRA Private [US]","wikimedia":"Wikimedia DNS [Global]","pumplex":"PumpleX [EU]","ffmuc":"FFMUC [EU]","ahadns":"AhaDNS [EU]","rethinkdns":"RethinkDNS [Asia]","libredns_clean":"LibreDNS [EU]","njalla":"Njalla [EU]","cloudflare_security":"Cloudflare Security [Global]","quad9_secure":"Quad9 Secure [Global]","quad9_ecs":"Quad9 Secure ECS [Global]","controld_p1":"Control D Malware [Global]","opendns_standard":"OpenDNS Standard [Global]","cleanbrowsing_security":"CleanBrowsing Security [Global]","dns4eu_protective":"DNS4EU Protective [EU]","cert_ee":"CERT-EE [EU]","cira_protected":"CIRA Protected [US]","one_dns_block":"OneDNS Block [Asia]","hagezi_root":"HaGeZi Root [EU]","hagezi_wurzn":"HaGeZi Wurzn [EU]","hagezi_juuri":"HaGeZi Juuri [EU]","hagezi_ctif":"HaGeZi CTIF [EU]","openbld_ada":"OpenBLD ADA [EU]","openbld_ric":"OpenBLD RIC [EU]","dnsforge_strict":"dnsforge Strict [EU]","dnsbunker":"DNSBUNKER Pro+TIF [EU]","nsec_arnor":"arnor.org [EU]","switch_ch":"SWITCH DNS [EU]","dynx":"DynX DNS Adblock [EU]","paesa":"Paesa DNS [EU]","anon_no":"Anon.no DNS [EU]","adguard_default":"AdGuard DNS [Global]","controld_p2":"Control D Ads+Tracking [Global]","dns4eu_noads":"DNS4EU No Ads [EU]","libredns_ads":"LibreDNS Ads [EU]","dnsguard":"DNSGuard [EU]","nwps_standard":"NWPS.fi Standard [EU]","oszx":"OSZX DNS [EU]","angry_im":"Angry.im [Global]","dns_bebas_default":"BebasDNS [Asia]","blokada":"Blokada DNS [Global]","comss_adblock_bypass":"Comss Router · без рекламы [RU/EU]","dnsforge":"dnsforge [EU]","meatdns":"MeatDNS [EU]","cloudflare_family":"Cloudflare Family [Global]","adguard_family":"AdGuard Family [Global]","controld_family":"Control D Family [Global]","opendns_family":"OpenDNS FamilyShield [Global]","cleanbrowsing_adult":"CleanBrowsing Adult [Global]","cleanbrowsing_family":"CleanBrowsing Family [Global]","dns4eu_child":"DNS4EU Child [EU]","dns4eu_child_noads":"DNS4EU Child No Ads [EU]","dns_for_family":"DNS for Family [EU]","cira_family":"CIRA Family [US]","nwps_kids":"NWPS.fi Kids [EU]","dnsforge_youth":"dnsforge Youth Protection [EU]","yandex_ru":"Yandex RU [RU]","yandex_safe":"Yandex Safe [RU]","yandex_family":"Yandex Family [RU]","iijjp":"IIJ Public DNS [Asia]","comss_ru":"Comss DNS RU","cznic_odvr_doh":"CZ.NIC ODVR (тот же адрес)","cznic_odvr_query":"CZ.NIC ODVR Query","mullvad_family":"Mullvad Family (сменить до 02.11.2026)","mullvad_all":"Mullvad All (сменить до 02.11.2026)"};
function catalogDisplayName(d){
  var name=String((!isUserDnsRecord(d)&&CATALOG_DISPLAY_NAMES[d.id])||d.name||d.id||'');
  if(/^sdns:\/\//.test(String(d.url||'')))name=name.replace(/\s*\(DNSCrypt\)/i,'');
  var region=String(d.region||'').trim();
  if(/^sdns:\/\//.test(String(d.url||'')) && /^[a-z]{2}$/i.test(region) && !/\[[^\]]+\]$/.test(name))name+=' ['+region.toUpperCase()+']';
  return name;
}
function isUserDnsRecord(d){
  return !!(d&&d.category==='custom'&&/^custom_[0-9]{3}$/.test(String(d.id||'')));
}
function deleteCustomDns(d,root){
  if(state.busy||state.jobRunning||!isUserDnsRecord(d))return;
  confirmAction('Удалить пользовательский DNS?',[['Название',d.name||d.id],['URL DoH',d.url||'—'],['Важно','Удалится только эта пользовательская запись. Встроенные DNS не затрагиваются.']],function(){
    state.busy=true;
    state.pageNotice.catalog='Удаляю пользовательский DNS…';
    renderCatalog(root);
    callDeleteCustomDns(d.id).then(awaitSettingResult).then(function(r){
      state.busy=false;
      if(r&&r.ok){
        state.category='custom';state.offset=0;window.dmCatalog=null;state.catalogLoaded=false;
        state.pageNotice.catalog='Пользовательский DNS «'+(d.name||d.id)+'» удалён.';
        setAction(true,'Пользовательский DNS удалён.');
        refresh(root,true);
      }else{
        var msg=(r&&r.error)||'Не удалось удалить пользовательский DNS.';
        state.pageNotice.catalog=msg;setAction(false,msg);renderCatalog(root);
      }
    }).catch(function(err){
      state.busy=false;
      var msg=withRpcError('Не удалось удалить пользовательский DNS.',err);
      state.pageNotice.catalog=msg;setAction(false,msg);renderCatalog(root);
    });
  });
}

function dnscryptCatalogBadge(st,id){
  var latency=dnscryptCatalogLatency(st,id);
  if(latency===-1)return badge('dm-bad','недоступен');
  if(latency===-2)return badge('dm-muted','не удалось проверить');
  return latency!==null&&latency>=0
    ? badge('dm-ok',String(latency)+' мс · последний замер')
    : badge('dm-muted','нет данных');
}
function dnscryptCatalogLatency(st,id){
  var results={};try{results=JSON.parse(st.dnscrypt_catalog_results||'{}');}catch(e){}
  var latency=results[String(id)];
  return latency!=null&&/^-?\d+$/.test(String(latency))?Number(latency):null;
}
function updateDnscryptCatalogProgress(root,j){
  state.dnscryptCatalogProgress={done:Number(j.progress_done)||0,total:Number(j.progress_total)||0,ok:Number(j.progress_ok)||0,fail:Number(j.progress_fail)||0,phase:String(j.phase||'')};
  renderCatalog(root);
}
function catalogPageIds(){return ((window.dmCatalog||{}).servers||[]).map(function(d){return d.id;}).filter(function(id){return /^[A-Za-z0-9_-]+$/.test(id);}).join(',');}
function stopCatalogCheck(root,crypt){
  state.catalogStopping=true;renderCatalog(root);
  (crypt?callDnscryptCancel():callTestPageCancel()).then(function(r){if(r&&r.ok===false)throw new Error(r.error||'Ошибка остановки');}).catch(function(err){state.catalogStopping=false;state.pageNotice.catalog=withRpcError('Не удалось остановить проверку.',err);}).then(function(){renderCatalog(root);});
}
function refreshDnscryptCatalogLatency(root,id){
  if(state.busy||state.jobRunning)return;
  state.catalogStopping=false;state.busy=true;state.dnscryptCatalogChecking=true;state.dnscryptCatalogId=id||'';state.dnscryptCatalogProgress=null;state.pageNotice.catalog='';renderCatalog(root);
  callDnscryptLatencies(id||catalogPageIds()).then(function(r){return waitDnsHealth(r,true,function(j){
    updateDnscryptCatalogProgress(root,j);
  });}).then(function(result){
    if(!result.ok)throw new Error(result.output||'Не удалось получить замеры DNSCrypt.');
    state.busy=false;state.dnscryptCatalogChecking=false;state.dnscryptCatalogId='';return refresh(root,true);
  }).catch(function(err){
    state.busy=false;state.dnscryptCatalogChecking=false;state.dnscryptCatalogId='';
    state.pageNotice.catalog=(err&&err.message)||'Не удалось получить замеры DNSCrypt.';renderCatalog(root);
  });
}
function dnscryptCatalogCard(d,root,draft,nativeOnly){
  var index=draft.items.findIndex(function(x){return x.id===d.id;}),chosen=index>=0;
  var checking=state.dnscryptCatalogChecking&&state.dnscryptCatalogId===d.id;
  var latency=dnscryptCatalogLatency(window.dmState||{},d.id);
  var actions=[btn(checking?'Проверяю…':'Проверить','cbi-button-neutral',function(){refreshDnscryptCatalogLatency(root,d.id);},{disabled:!!state.busy||!!state.jobRunning})];
  if(chosen||(!checking&&latency!==null&&latency>=0))actions.push(btn(chosen?'Убрать из набора':'Добавить в набор','cbi-button-neutral'+(chosen?' active':''),function(){if(chosen)draft.items.splice(index,1);else draft.items.push({id:d.id,name:catalogDisplayName(d)});saveDnscryptPoolDraft(draft);renderCatalog(root);},{disabled:!!state.busy||!!state.jobRunning||(!chosen&&(draft.items.length>=6||(nativeOnly&&!/^sdns:\/\//.test(String(d.url||'')))))}));
  return E('div',{'class':'dm-card dm-catalog-item'},[E('h4',{},catalogDisplayName(d)),E('div',{'class':'dm-meta'},catName(d.category)),E('div',{'class':'dm-catalog-address'},(/^sdns:\/\//.test(String(d.url||''))?'Протокол DNSCrypt':String(d.url||'').replace(/^https?:\/\//,''))),E('div',{'class':'dm-catalog-status'},[checking?badge('dm-muted','проверяю…'):dnscryptCatalogBadge(window.dmState||{},d.id)]),E('div',{'class':'dm-catalog-controls'},actions)]);
}
function resumeDnscryptCatalogLatency(root){
  if(state.dnscryptCatalogChecking||(window.dmState||{}).dnscrypt_engine!=='dnscrypt-proxy2')return;
  callJob('health').then(function(j){
    if(!j||j.name!=='dnscrypt_catalog'||j.status!=='running'||state.dnscryptCatalogChecking)return;
    state.busy=true;state.dnscryptCatalogChecking=true;renderCatalog(root);
    return waitDnsHealth({ok:true,job:'health'},true,function(progress){
      updateDnscryptCatalogProgress(root,progress);
    }).then(function(result){
      state.busy=false;state.dnscryptCatalogChecking=false;
      if(!result.ok)state.pageNotice.catalog=result.output||'Не удалось проверить каталог DNS.';
      return refresh(root,true);
    }).catch(function(err){state.busy=false;state.dnscryptCatalogChecking=false;state.pageNotice.catalog=(err&&err.message)||'Не удалось получить результат проверки.';renderCatalog(root);});
  }).catch(function(){});
}
function renderCatalog(root){
  var e=root.querySelector('#dm-catalog');if(!e)return;e.innerHTML='';
  if((window.dmState||{}).dnscrypt_engine==='dnscrypt-proxy2'){
    var data=window.dmCatalog||{}, controls=E('div',{'class':'dm-seg'});
    e.appendChild(E('div',{'class':'dm-actions'},[state.dnscryptCatalogChecking?btn(state.catalogStopping?'Останавливаю…':'Остановить','cbi-button-neutral',function(){stopCatalogCheck(root,true);},{disabled:!!state.catalogStopping}):btn('Проверить эту страницу','cbi-button-action',function(){refreshDnscryptCatalogLatency(root);},{disabled:!!state.busy||!!state.jobRunning||!catalogPageIds()})]));
    if(state.dnscryptCatalogChecking){
      var progress=state.dnscryptCatalogProgress||{}, done=progress.done||0, total=progress.total||0;
      var pct=total>0?Math.max(0,Math.min(100,Math.round(done*100/total))):0;
      var summary=total?'Проверено '+done+' из '+total+' · доступно: '+progress.ok+' · не ответили: '+progress.fail+(done-progress.ok-progress.fail>0?' · не удалось проверить: '+(done-progress.ok-progress.fail):''):'Подготавливаю список DNS-серверов…';
      var progressItems=[
        E('div',{'class':'dm-mini'},'Проверка каталога DNS'),
        E('div',{'class':'dm-mem-line'},[
          E('div',{'class':'dm-mem-track','role':'progressbar','aria-label':'Проверено серверов DNS','aria-valuemin':'0','aria-valuemax':'100','aria-valuenow':String(pct)},[E('div',{'class':'dm-mem-fill','style':'width:'+pct+'%'})]),
          E('span',{'class':'dm-mem-value'},pct+'%')
        ]),
        E('div',{'class':'dm-mem-meta'},summary)
      ];
      if(progress.phase)progressItems.push(E('div',{'class':'dm-mini'},'Сейчас проверяются: '+progress.phase));
      progressItems.push(E('div',{'class':'dm-mini'},'Проверяются серверы выбранной страницы. Можно закрыть страницу — проверка продолжится.'));
      e.appendChild(card('Ход проверки',progressItems));
    }
    var protocols=E('div',{'class':'dm-seg'});
    [['native','DNSCrypt'],['doh','DNS over HTTPS']].forEach(function(p){
      protocols.appendChild(btn(p[1],state.catalogProtocol===p[0]?'active cbi-button':'cbi-button',function(){
        if(state.catalogLoading)return;state.catalogProtocol=p[0];state.offset=0;window.dmCatalog=null;loadCatalog(root);
      },{disabled:!!state.catalogLoading,'aria-pressed':state.catalogProtocol===p[0]?'true':'false'}));
    });
    CATEGORY.forEach(function(c){controls.appendChild(btn(c[1],c[0]===state.category?'active cbi-button':'cbi-button',function(){if(state.catalogLoading)return;state.category=c[0];state.offset=0;loadCatalog(root);},{disabled:!!state.catalogLoading,'aria-pressed':c[0]===state.category?'true':'false'}));});
    var draft=dnscryptPoolDraft(window.dmState||{});
    var nativeOnly=dnscryptOptions(window.dmState||{}).protocol==='native';
    var rows=catalogGroups(data.servers||[],function(d){return dnscryptCatalogCard(d,root,draft,nativeOnly);},function(){renderCatalog(root);});
    var shown=E('div',{'class':'dm-mini'},'Серверы '+(data.total?state.offset+1:0)+'–'+(state.offset+(data.servers||[]).length)+' из '+(data.total||0)+'. Варианты одного провайдера собраны вместе.');
    e.appendChild(E('div',{'class':'dm-hint'},[E('span',{},'В наборе: '+draft.items.length+' из 6. '),E('a',{'href':L.url('admin/services/dns-manager/slots')},'Открыть набор и применить')]));
    e.appendChild(card('Каталог DNS',[E('div',{'class':'dm-hint'},nativeOnly&&state.catalogProtocol==='doh'?'Выбран режим только DNSCrypt: DoH можно просматривать, но добавить в набор нельзя.':'Выберите протокол и категорию. Проверка не меняет текущие DNS.'),protocols,controls,shown,state.pageNotice.catalog?E('div',{'class':'dm-inline-msg error'},state.pageNotice.catalog):null,state.catalogLoading?E('div',{'class':'dm-hint'},'Загрузка каталога DNS…'):null,E('div',{'class':'dm-catalog'},rows),E('div',{'class':'dm-page'},[btn('←','cbi-button-neutral',function(){if(!state.catalogLoading&&state.offset>0){state.offset=Math.max(0,state.offset-state.limit);loadCatalog(root);}},{disabled:!!state.catalogLoading||state.offset<=0,'aria-label':'Предыдущая страница'}),E('span',{'class':'dm-mini'},(Math.floor(state.offset/state.limit)+1)+' / '+Math.max(1,Math.ceil((data.total||0)/state.limit))),btn('→','cbi-button-neutral',function(){if(!state.catalogLoading&&state.offset+state.limit<(data.total||0)){state.offset+=state.limit;loadCatalog(root);}},{disabled:!!state.catalogLoading||state.offset+state.limit>=(data.total||0),'aria-label':'Следующая страница'})])].filter(Boolean)));
    return;
  }
  var ageCard=renderTestAgeCommon(root,window.dmState||{});
  var body=E('div',{'id':'dm-cat-body'});
  if(!window.dmCatalog&&!state.pageNotice.catalog)body.appendChild(E('div',{'class':'dm-hint'},state.catalogLoading?'Загрузка каталога DNS…':'Каталог DNS недоступен.'));
  var ch=[
    E('div',{'class':'dm-mini'},'Каталог DNS отображается постоянно. Выбор категории и назначение доступны ниже.'),
    E('div',{'class':'dm-actions'},[
      state.jobRunning&&state.fullTest&&state.fullTest.origin==='catalog'?btn(state.catalogStopping?'Останавливаю…':'Остановить','cbi-button-neutral',function(){stopCatalogCheck(root,false);},{disabled:!!state.catalogStopping}):btn('Проверить эту страницу','cbi-button-action',function(){testAll(root,'catalog');},{disabled:!!state.busy||!!state.jobRunning||!catalogPageIds()})
    ])
  ];

  var customName=E('input',{'class':'dm-input','type':'text','maxlength':'80','placeholder':'Например, Мой DNS'});
  var customUrl=E('input',{'class':'dm-input','type':'url','maxlength':'512','placeholder':'https://dns.example/dns-query'});
  var customDraft=state.customDnsDraft||{};
  customName.value=customDraft.name||'';customUrl.value=customDraft.url||'';
  function rememberCustomDns(){state.customDnsDraft={name:customName.value,url:customUrl.value};}
  customName.addEventListener('input',rememberCustomDns);customUrl.addEventListener('input',rememberCustomDns);
  e.appendChild(card('Добавить свой DoH',[foldSection('custom-doh','Форма добавления',E('div',{'class':'dm-custom-dns-content'},[
    E('div',{'class':'dm-mini'},'Добавь собственный HTTPS-адрес DNS over HTTPS. Он сохранится отдельно от официального каталога и не исчезнет при обновлении каталога.'),
    E('div',{'class':'dm-custom-dns-form'},[
      E('div',{},[
        E('div',{'class':'dm-setting-title'},'Название'),
        customName
      ]),
      E('div',{},[
        E('div',{'class':'dm-setting-title'},'URL DoH'),
        customUrl
      ]),
      btn(state.busy?'Сохраняю…':'Добавить DNS','cbi-button-action',function(){saveCustomDns(customName,customUrl,root);},{disabled:!!state.busy||!!state.jobRunning})
    ]),
    state.customDnsNotice?E('div',{'class':'dm-inline-msg '+state.customDnsNotice.type},state.customDnsNotice.text):null,
    E('div',{'class':'dm-mini'},'После добавления выбери «Мои DNS», нажми «Проверить», затем назначь сервер в слот DNS 1–6.')
  ].filter(Boolean)))]));

  if(state.fullTest&&state.fullTest.origin==='catalog'&&state.catalogProgress){
    var p=state.catalogProgress;
    var total=Number(p.total||0),done=Number(p.done||0),okn=Number(p.ok||0),failn=Number(p.fail||0);
    var pct=total>0?Math.max(0,Math.min(100,Math.round(done*100/total))):0;
    var running=state.jobRunning&&state.fullTest.status==='RUNNING';
    var failed=state.fullTest.status==='FAILED';
    var title=running?'Проверка страницы':(state.catalogCancelled?'Проверка остановлена':(failed?'Проверка не завершена':'Проверка страницы завершена'));
    var summary=total>0
      ? (running?'Проверено '+done+' из '+total:'Проверено: '+done+' из '+total)+' · доступно: '+okn+' · не ответили: '+failn
      : (running?'Подготавливаю список DNS-серверов…':'Сведения о количестве проверенных серверов недоступны.');
    var detail=String(p.detail||'').trim();
    if(running||!failed)detail='';
    var method=[
      E('div',{'class':'dm-mini'},title),
      E('div',{'class':'dm-mem-line'},[
        E('div',{'class':'dm-mem-track'},[E('div',{'class':'dm-mem-fill','style':'width:'+pct+'%'})]),
        E('span',{'class':'dm-mem-value'},pct+'%')
      ]),
      E('div',{'class':'dm-mem-meta'},summary)
    ];
    if(detail)method.push(E('div',{'class':'dm-inline-msg error'},detail));
    ch.push(card(running?'Ход проверки':'Результат проверки',method));
  }

  ch.push(ageCard);
  ch.push(body);
  if(state.pageNotice.catalog)ch.push(E('div',{'class':'dm-inline-msg '+(state.fullTest&&state.fullTest.status==='FAILED'?'error':'info')},state.pageNotice.catalog));
  e.appendChild(card('Каталог DNS',ch));
  if(window.dmCatalog)renderCatalogBody(root,window.dmCatalog);
}

// Group only known catalog entries on the current page; IDs and category filters stay unchanged.
function catalogGroups(servers,renderItem,rerender){
  var families={cloudflare:'Cloudflare',quad9:'Quad9',controld:'Control D',dns4eu:'DNS4EU',yandex:'Яндекс',geohide:'GeoHide',adguard:'AdGuard DNS',cleanbrowsing:'CleanBrowsing',cryptostorm:'CryptoStorm',scaleway:'Scaleway'};
  function familyKey(d){
    if(isUserDnsRecord(d))return '';
    var id=String(d.id||''), name=catalogDisplayName(d).toLowerCase();
    var keys=Object.keys(families);
    for(var i=0;i<keys.length;i++){var k=keys[i];if(id===k||id.indexOf(k+'_')===0||id.indexOf('native_'+k+'_')===0||(/^sdns:\/\//.test(String(d.url||''))&&name.indexOf(families[k].toLowerCase())===0))return k;}
    return '';
  }
  var members={}, result=[], emitted={};
  servers.forEach(function(d){
    if(isUserDnsRecord(d))return;
    var key=familyKey(d);
    if(families[key])(members[key]=members[key]||[]).push(d);
  });
  state.catalogOpenGroups=state.catalogOpenGroups||{};
  servers.forEach(function(d){
    var key=familyKey(d), group=members[key];
    if(isUserDnsRecord(d)||!group||group.length<2){result.push(renderItem(d));return;}
    if(emitted[key])return;
    emitted[key]=true;
    var open=!!state.catalogOpenGroups[key];
    var toggle=E('button',{'type':'button','class':'dm-card dm-catalog-family'+(open?' is-open':''),'aria-expanded':open?'true':'false','click':function(){state.catalogOpenGroups[key]=!open;rerender();}},[
      E('span',{'class':'dm-catalog-family-main'},[E('strong',{},families[key]),E('span',{'class':'dm-mini'},group.length+' варианта на странице')]),E('span',{'aria-hidden':'true'},open?'⌃':'›')
    ]);
    result.push(toggle);
    if(open)result.push(E('div',{'class':'dm-catalog-family-panel'},[
      E('div',{'class':'dm-catalog-family-head'},[E('strong',{},families[key]+' — выберите вариант'),btn('Закрыть','cbi-button-neutral',function(){state.catalogOpenGroups[key]=false;rerender();},{'aria-label':'Закрыть варианты '+families[key]})]),
      E('div',{'class':'dm-catalog-family-items'},group.map(renderItem))
    ]));
  });
  return result;
}

function renderCatalogBody(root,data){
  var b=root.querySelector('#dm-cat-body');if(!b)return;b.innerHTML='';
  var f=E('div',{'class':'dm-seg'});
  CATEGORY.forEach(function(c){f.appendChild(btn(c[1],c[0]===state.category?'active cbi-button':'cbi-button',function(){if(state.catalogLoading)return;state.category=c[0];state.offset=0;loadCatalog(root);},{disabled:!!state.catalogLoading,'aria-pressed':c[0]===state.category?'true':'false'}));});
  b.appendChild(f);
  b.appendChild(E('div',{'class':'dm-mini'},'Серверы '+(data.total?state.offset+1:0)+'–'+(state.offset+(data.servers||[]).length)+' из '+(data.total||0)+'. Варианты одного провайдера собраны вместе.'));
  var g=E('div',{'class':'dm-catalog'});
  catalogGroups(data.servers||[],function(d){
    var ci=checkInfo(d.id,d);
    var statusText=stateBadge(ci.status,ci.ping);
    return E('div',{'class':'dm-card dm-catalog-item'+(isUserDnsRecord(d)?' dm-catalog-item-custom':'')},[
      E('h4',{},catalogDisplayName(d)),
      E('div',{'class':'dm-meta'},catName(d.category)),
      E('div',{'class':'dm-catalog-address'},String(d.url||'').replace(/^https?:\/\//,'')),
      E('div',{'class':'dm-catalog-status'},[statusText]),
      E('div',{'class':'dm-catalog-controls'+(isUserDnsRecord(d)?' dm-catalog-controls-custom':'' )},(function(){
        var assignment=renderCatalogAssign(d,root);
        assignment.insertBefore(btn(ci.status==='RUNNING'?'Проверяю…':'Проверить','cbi-button-neutral',function(){testOne(d.id,root,'catalog');},{disabled:ci.status==='RUNNING'||!!state.busy||!!state.jobRunning}),assignment.firstChild);
        if(isUserDnsRecord(d)){
          assignment.appendChild(btn('Удалить','cbi-button-negative',function(){deleteCustomDns(d,root);},{disabled:!!state.busy||!!state.jobRunning}));
          return [assignment];
        }
        return [E('div',{'class':'dm-catalog-toolbar'},[assignment])];
      })())
    ]);
  },function(){renderCatalogBody(root,data);}).forEach(function(item){g.appendChild(item);});
  b.appendChild(g);
  b.appendChild(E('div',{'class':'dm-page'},[
    btn('←','cbi-button-neutral',function(){if(!state.catalogLoading&&state.offset>0){state.offset=Math.max(0,state.offset-state.limit);loadCatalog(root);}},{disabled:!!state.catalogLoading||state.offset<=0,'aria-label':'Предыдущая страница'}),
    E('span',{'class':'dm-mini'},(Math.floor(state.offset/state.limit)+1)+' / '+Math.max(1,Math.ceil((data.total||0)/state.limit))),
    btn('→','cbi-button-neutral',function(){if(!state.catalogLoading&&state.offset+state.limit<(data.total||0)){state.offset+=state.limit;loadCatalog(root);}},{disabled:!!state.catalogLoading||state.offset+state.limit>=(data.total||0),'aria-label':'Следующая страница'})
  ]));
}

function renderLog(root){
  var e=root.querySelector('#dm-log');if(!e)return;
  var previous=e.querySelector('.dm-log'),oldTop=previous?previous.scrollTop:0;
  var follow=!previous||previous.scrollHeight-previous.clientHeight-oldTop<20;
  e.innerHTML='';
  var ch=[];if(state.pageNotice.log)ch.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.log));
  if(state.logLoaded)ch.push(E('pre',{'class':'dm-log'},stripAnsi(state.logText||'')));
  else ch.push(E('div',{'class':'dm-hint'},'Журнал загружается автоматически при открытии этой вкладки.'));
  e.appendChild(card('Журнал',ch));
  var log=e.querySelector('.dm-log');
  if(log)window.setTimeout(function(){if(e.querySelector('.dm-log')===log)log.scrollTop=follow?log.scrollHeight:oldTop;},0);
}

function renderJobIdle(root,st){
  var e=root.querySelector('#dm-job');if(!e)return;e.innerHTML='';
}
function render(root,st){
  document.querySelectorAll('a[href*="/dns-manager/slots"]').forEach(function(link){
    link.textContent=st.dnscrypt_engine==='dnscrypt-proxy2'?'DNS-серверы':'DNS по слотам';
  });
  renderHeader(root,st,state.statusFromCache?(state.statusError||'Обновляю данные…'):null);
  state.activeTab=currentRoute();
  switch(state.activeTab){
    case 'doh':
      renderDoH(root,st);
      renderProfiles(root,st);
      break;
    case 'slots':
      renderSlots(root,st);
      break;
    case 'devices':
      renderDeviceDns(root,st);
      break;
    case 'network':
      renderNetwork(root,st);
      break;
    case 'time':
      renderTime(root,st);
      break;
    case 'catalog':
      renderCatalog(root);
      break;
    case 'log':
      renderLog(root);
      break;
    default:
      state.activeTab='dashboard';
      renderOverview(root,st);
      break;
  }
  setActiveTab(root,state.activeTab);
  if(state.statusFromCache){
    var header=root.querySelector('#dm-header');
    if(header&&state.statusError)header.querySelector('.dm-header').appendChild(btn('Повторить','cbi-button-neutral',function(){state.statusError='';render(root,st);scheduleBackgroundStatus(root);}));
    root.querySelectorAll('button,input,select,textarea').forEach(function(el){el.disabled=true;});
  }
}
function routeStatusCall(){
  var route=arguments[0]||currentRoute();
  switch(route){
    case 'doh':
    case 'slots':
      return callDohStatus();
    case 'devices':
      return Promise.all([
        callDohStatus(),
        callLanDevices().catch(function(){return {ok:false,devices:[]};})
      ]).then(function(v){window.dmLanDevices=v[1]||{};return v[0]||{};});
    case 'network': return callNetworkStatus();
    case 'time': return callTimeStatus();
    case 'catalog':
      var requestedCategory=state.category, requestedProtocol=state.catalogProtocol, requestedOffset=state.offset, requestedLimit=state.limit;
      return Promise.all([
        callCatalog((window.dmState||{}).dnscrypt_engine==='dnscrypt-proxy2'?requestedProtocol+':'+requestedCategory:requestedCategory,requestedOffset,requestedLimit,0),
        Promise.all([callDohStatus(),callPageMeta()])
      ]).then(function(v){
        if(state.category!==requestedCategory||state.catalogProtocol!==requestedProtocol||state.offset!==requestedOffset||state.limit!==requestedLimit)return Object.assign({},v[1][0]||{},v[1][1]||{});
        if(!v[0]||v[0].ok===false){
          window.dmCatalog=null;state.catalogLoaded=false;state.catalogLoadFailed=true;
          state.pageNotice.catalog=(v[0]&&v[0].error)||'Не удалось загрузить каталог DNS.';
        }else{window.dmCatalog=v[0];state.catalogLoaded=true;if(state.catalogLoadFailed)state.pageNotice.catalog='';state.catalogLoadFailed=false;}
        var st=v[1][0]||{};
        var meta=v[1][1]||{};
        Object.keys(meta).forEach(function(k){st[k]=meta[k];});
        return st;
      });
    case 'log':
      return callLog(160).then(function(r){
        if(!r||r.ok===false){state.logLoaded=false;state.pageNotice.log=(r&&r.error)||'Не удалось загрузить журнал.';return {ok:true};}
        state.logLoaded=true;
        state.logText=stripAnsi((r&&r.log)||'');
        var st=Object.assign({},r);delete st.log;return st;
      });
    case 'dashboard':
      return callStatus(0);
    default:
      return callStatus(0);
  }
}
function ensureStatusPromise(){
  var route=arguments[0]||currentRoute(),promiseKey=statusCacheKey(route)||route;
  var generation=window.dmCacheGeneration||0;
  window.dmStatusPromises=window.dmStatusPromises||Object.create(null);
  if(window.dmStatusPromises[promiseKey])return window.dmStatusPromises[promiseKey];
  var promise=routeStatusCall(route).then(function(st){
    if(generation!==(window.dmCacheGeneration||0))throw new Error('Состояние устарело после переключения движка');
    if(!st||st.ok!==true)throw new Error((st&&st.error)||'Пустой ответ состояния');
    var key=statusCacheKey(route);
    var aux=routeCacheAux(route);
    if(key&&aux!==false)saveRouteCache(key,st,aux);
    return st;
  }).catch(function(err){
    window.dmStatusError=err;
    throw err;
  }).then(function(st){
    if(window.dmStatusPromises[promiseKey]===promise)delete window.dmStatusPromises[promiseKey];
    return st;
  },function(err){
    if(window.dmStatusPromises[promiseKey]===promise)delete window.dmStatusPromises[promiseKey];
    throw err;
  });
  window.dmStatusPromises[promiseKey]=promise;
  return promise;
}

function statusCacheKey(route){
  if(route==='doh'||route==='slots')return 'doh';
  return ['dashboard','network','time','devices','catalog','log'].indexOf(route)>=0?route:'';
}
function saveRouteCache(key,st,aux){
  try{
    window.dmRouteCache=window.dmRouteCache||Object.create(null);
    var entry=JSON.parse(JSON.stringify({ts:Date.now(),data:st,aux:aux}));
    window.dmRouteCache[key]=entry;
    if(typeof session!=='undefined'&&session.setLocalData)
      session.setLocalData('dns-manager-route-2.78-'+key,entry);
  }catch(e){}
}
function clearEngineUiState(){
  window.dmCacheGeneration=(window.dmCacheGeneration||0)+1;
  window.dmRouteCache=Object.create(null);
  window.dmStatusPromises=Object.create(null);
  ['dashboard','doh','network','time','devices','catalog','log'].forEach(function(key){
    try{if(typeof session!=='undefined'&&session.setLocalData)session.setLocalData('dns-manager-route-2.78-'+key,null);}catch(e){}
  });
  state.dnscryptProtocol=null;state.dnscryptStrategy=null;state.dnscryptPoolDraft=null;
  state.pageNotice={};state.profileProgress=null;state.profileOutput='';state.profileResumeStarted=false;
  state.regionalNotice='';state.pendingProfile='';state.pendingRegional=null;state.pendingDnscryptServer='';state.dnscryptDiagnostic='';state.dnscryptDiagnosticKind='';state.dnscryptDiagnosticResult='';
  state.lastAction=null;state.lastJob=null;state.checking={};state.fullTest=null;state.catalogProgress=null;
  if(window.dmState){
    ['profile_job_status','profile_job_result','profile_job_profile','profile_job_started','profile_job_finished','profile_job_message'].forEach(function(key){delete window.dmState[key];});
  }
}
function routeCacheEntry(key){
  var entry=key&&window.dmRouteCache&&window.dmRouteCache[key];
  if(!entry&&key){
    try{if(typeof session!=='undefined'&&session.getLocalData)entry=session.getLocalData('dns-manager-route-2.78-'+key);}catch(e){}
  }
  if(!entry||typeof entry.ts!=='number'||Date.now()-entry.ts<0||Date.now()-entry.ts>300000||!entry.data||entry.data.ok!==true)return null;
  return entry;
}
function routeCacheAux(route){
  if(route==='devices')return window.dmLanDevices&&window.dmLanDevices.ok?{devices:window.dmLanDevices}:false;
  if(route==='catalog')return state.catalogLoaded&&state.category==='all'&&state.offset===0&&window.dmCatalog?{catalog:window.dmCatalog,limit:state.limit}:false;
  if(route==='log')return state.logLoaded?{log:String(state.logText||'').slice(-131072)}:false;
  return null;
}
function restoreRouteAux(route,aux){
  if(route==='devices'){
    if(!aux||!aux.devices||aux.devices.ok!==true||!Array.isArray(aux.devices.devices))return false;
    window.dmLanDevices=aux.devices;
  }else if(route==='catalog'){
    if(!aux||!aux.catalog||aux.catalog.ok===false||!Array.isArray(aux.catalog.servers)||aux.limit!==state.limit||state.category!=='all'||state.offset!==0)return false;
    window.dmCatalog=aux.catalog;state.catalogLoaded=true;state.catalogLoadFailed=false;
  }else if(route==='log'){
    if(!aux||typeof aux.log!=='string'||aux.log.length>131072)return false;
    state.logText=aux.log;state.logLoaded=true;
  }
  return true;
}
function cachedRouteStatus(route){
  var key=statusCacheKey(route),entry=routeCacheEntry(key);
  if(!entry)return null;
  try{
    var copy=JSON.parse(JSON.stringify(entry));
    if(!restoreRouteAux(route,copy.aux))return null;
    var st=copy.data;st.__dmCachedRoute=route;st.__dmCacheFresh=Date.now()-copy.ts<=15000;return st;
  }catch(e){return null;}
}
function cachedHeaderStatus(){
  var keys=['dashboard','doh','network','time','devices','catalog','log'];
  for(var i=0;i<keys.length;i++){
    var entry=routeCacheEntry(keys[i]);
    if(entry&&entry.data.luci_version)return {luci_version:entry.data.luci_version};
  }
  return {};
}
function applyStatusToCurrentRoot(st,route){
  if(route&&currentRoute()!==route)return;
  var root=window.dmCurrentRoot;
  if(!rootAlive(root))return;
  state.statusError='';
  state.statusFromCache=false;
  var loading=root.querySelector&&root.querySelector('#dm-initial-loading');if(loading)loading.remove();
  window.dmState=st||{};
  render(root,st||{});
}
function refresh(root,keepPosition){
  if(!rootAlive(root))root=window.dmCurrentRoot;
  if(!rootAlive(root))return Promise.resolve();
  var route=currentRoute();
  return ensureStatusPromise(route).then(function(st){
    if(window.dmCurrentRoot!==root)return;
    applyStatusToCurrentRoot(st,route);
  }).catch(function(err){
    if(!rootAlive(root)||window.dmCurrentRoot!==root||currentRoute()!==route)return;
    state.statusError=withRpcError('Не удалось получить состояние DNS Manager через RPC (status).',err);
    window.dmState=window.dmState||{};
    render(root,window.dmState||{});
  });
}
function scheduleBackgroundStatus(root,initial){
  var route=currentRoute();
  if(window.dmStatusRefreshTimer)window.clearTimeout(window.dmStatusRefreshTimer);
  window.dmStatusRefreshTimer=window.setTimeout(function(){
    window.dmStatusRefreshTimer=null;
    if(!rootAlive(root)||window.dmCurrentRoot!==root||currentRoute()!==route)return;
    ensureStatusPromise(route).then(function(st){
      if(window.dmCurrentRoot===root&&(initial||(!state.busy&&!state.jobRunning&&!state.catalogLoading&&!(root.contains(document.activeElement)&&/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName))))){applyStatusToCurrentRoot(st,route);if(initial)scheduleRouteWarmup(root);}
    }).catch(function(err){
      if(!rootAlive(root)||window.dmCurrentRoot!==root||currentRoute()!==route)return;
      state.statusError=withRpcError('Не удалось загрузить состояние DNS Manager.',err);
      if(initial){
        var loading=root.querySelector('#dm-initial-loading');
        if(loading){renderHeader(root,cachedHeaderStatus(),state.statusError);root.querySelector('#dm-header .dm-header').appendChild(btn('Повторить','cbi-button-neutral',function(){renderHeader(root,cachedHeaderStatus(),'Загружаю данные…');scheduleBackgroundStatus(root,true);}));}
      }else render(root,window.dmState||{});
    });
  },0);
}
// Warm one read-only request at a time, only while this page is idle.
function warmupFetch(route,allowed){
  function get(fn){if(!allowed())return Promise.reject(new Error('warmup stopped'));return fn();}
  if(route==='dashboard')return get(function(){return callStatus(0);}).then(function(st){return {data:st,aux:null};});
  if(route==='doh')return get(callDohStatus).then(function(st){return {data:st,aux:null};});
  if(route==='network')return get(callNetworkStatus).then(function(st){return {data:st,aux:null};});
  if(route==='time')return get(callTimeStatus).then(function(st){return {data:st,aux:null};});
  if(route==='log')return get(function(){return callLog(160);}).then(function(log){
    if(!log||log.ok!==true)throw new Error('log unavailable');
    var st=Object.assign({},log);delete st.log;
    return {data:st,aux:{log:stripAnsi(String(log.log||'')).slice(-131072)}};
  });
  if(route==='devices')return get(callDohStatus).then(function(st){
    return get(callLanDevices).then(function(devices){
      if(!devices||devices.ok!==true||!Array.isArray(devices.devices))throw new Error('devices unavailable');
      return {data:st,aux:{devices:devices}};
    });
  });
  if(route==='catalog')return get(function(){return callCatalog('all',0,18,0);}).then(function(catalog){
    if(!catalog||catalog.ok!==true||!Array.isArray(catalog.servers))throw new Error('catalog unavailable');
    return get(callDohStatus).then(function(st){return get(callPageMeta).then(function(meta){
      if(!st||st.ok!==true||!meta||meta.ok!==true)throw new Error('catalog status unavailable');
      var result=Object.assign({},st,meta);
      return {data:result,aux:{catalog:catalog,limit:18}};
    });});
  });
  return Promise.reject(new Error('unsupported warmup'));
}
function setupTabPrefetch(root){
  if(window.dmTabPrefetchCleanup)window.dmTabPrefetchCleanup();
  var timer=null,pending=false,generation=window.dmCacheGeneration||0;
  function allowed(){
    return generation===(window.dmCacheGeneration||0)&&rootAlive(root)&&window.dmCurrentRoot===root&&!document.hidden&&
      !state.statusFromCache&&!state.busy&&!state.jobRunning&&!state.catalogLoading&&!state.logLoading&&!state.lanDevicesLoading&&
      !state.updatingAll&&!state.managerUpdating&&!state.hdpUpdating&&!(state.versionCheck&&state.versionCheck.running)&&
      !Object.keys(window.dmStatusPromises||{}).length;
  }
  function prefetch(ev){
    var link=ev.target&&ev.target.closest&&ev.target.closest('a[href*="/dns-manager/"]');
    var match=link&&String(link.getAttribute('href')||'').match(/\/dns-manager\/(dashboard|doh|slots|devices|network|time|catalog|log)(?:[?#]|$)/);
    if(!match||match[1]===currentRoute()||pending||window.dmWarmupBusy)return;
    var route=match[1]==='slots'?'doh':match[1],key=statusCacheKey(route);
    if(routeCacheEntry(key)||!allowed())return;
    if(timer)window.clearTimeout(timer);
    timer=window.setTimeout(function(){
      timer=null;if(!allowed()||routeCacheEntry(key)||window.dmWarmupBusy)return;
      pending=true;window.dmWarmupBusy=true;
      callRuntime().then(function(rt){
        if(!allowed()||!rt||rt.ok!==true||rt.memory_available_kb==null||!isFinite(Number(rt.memory_available_kb))||Number(rt.memory_available_kb)<32768||
           rt.cpu_load==null||!isFinite(Number(rt.cpu_load))||Number(rt.cpu_load)>75)return null;
        return warmupFetch(route,allowed);
      }).then(function(v){
        if(allowed()&&v&&v.data&&v.data.ok===true&&!routeCacheEntry(key))saveRouteCache(key,v.data,v.aux);
      }).catch(function(){}).then(function(){pending=false;window.dmWarmupBusy=false;});
    },100);
  }
  ['mouseover','focusin','touchstart'].forEach(function(name){document.addEventListener(name,prefetch,true);});
  window.dmTabPrefetchCleanup=function(){
    if(timer)window.clearTimeout(timer);
    ['mouseover','focusin','touchstart'].forEach(function(name){document.removeEventListener(name,prefetch,true);});
    window.dmTabPrefetchCleanup=null;
  };
}
function scheduleRouteWarmup(root){
  var routes=['doh','network','time','dashboard','devices','catalog','log'],index=0;
  var originalRoute=currentRoute(),generation=window.dmCacheGeneration||0;
  function allowed(){
    return generation===(window.dmCacheGeneration||0)&&rootAlive(root)&&window.dmCurrentRoot===root&&currentRoute()===originalRoute&&!document.hidden&&
      !state.statusFromCache&&!state.busy&&!state.jobRunning&&!state.catalogLoading&&!state.logLoading&&!state.lanDevicesLoading&&
      !state.updatingAll&&!state.managerUpdating&&!state.hdpUpdating&&!(state.versionCheck&&state.versionCheck.running)&&
      !Object.keys(window.dmStatusPromises||{}).length;
  }
  function next(){
    if(generation!==(window.dmCacheGeneration||0)||!rootAlive(root)||window.dmCurrentRoot!==root||currentRoute()!==originalRoute||index>=routes.length)return;
    if(!allowed()||window.dmWarmupBusy){window.setTimeout(next,10000);return;}
    var route=routes[index++],key=statusCacheKey(route);
    if(routeCacheEntry(key)){window.setTimeout(next,1000);return;}
    window.dmWarmupBusy=true;
    callRuntime().then(function(rt){
      if(!allowed()||!rt||rt.ok!==true||rt.memory_available_kb==null||!isFinite(Number(rt.memory_available_kb))||Number(rt.memory_available_kb)<32768||
         rt.cpu_load==null||!isFinite(Number(rt.cpu_load))||Number(rt.cpu_load)>75)return null;
      return warmupFetch(route,allowed);
    }).then(function(v){
      if(allowed()&&v&&v.data&&v.data.ok===true&&!routeCacheEntry(key))saveRouteCache(key,v.data,v.aux);
    }).catch(function(){}).then(function(){window.dmWarmupBusy=false;window.setTimeout(next,3000);});
  }
  window.setTimeout(next,3000);
}
function checkUpdate(root,force){
  if(state.updatingAll||(state.versionCheck&&state.versionCheck.running))return;
  globalUpdateNotice('', 'info');
  state.versionCheck={running:true,manager:'running',luci:'running',hdp:'running',catalog:'running',started:Date.now(),job:''};
  renderOverview(root,window.dmState||{});
  callUpdateCheck(force?1:0).then(awaitSettingResult).then(function(r){
    state.versionCheck.manager='done';
    state.versionCheck.luci='done';
    state.versionCheck.hdp='done';
    state.versionCheck.catalog='done';
    state.versionCheck.running=false;
    state.versionCheck.error=!(r&&r.ok);
    if(r&&r.ok){
      state.pageNotice.overview='';
      return refresh(root,true);
    }else{
      state.pageNotice.overview=(r&&r.error)||'Проверка актуальности не выполнена.';
      renderOverview(root,window.dmState||{});
    }
  }).catch(function(err){
    state.versionCheck.manager='done';
    state.versionCheck.luci='done';
    state.versionCheck.hdp='done';
    state.versionCheck.catalog='done';
    state.versionCheck.running=false;
    state.versionCheck.error=true;
    state.pageNotice.overview=withRpcError('Проверка актуальности не выполнена.',err);
    renderOverview(root,window.dmState||{});
  });
}

function resumeVersionCheck(root){
  if(state.versionResumeStarted||!rootAlive(root))return;
  state.versionResumeStarted=true;
  callJob('version').then(function(j){
    if(!j||!j.ok||j.status!=='running'||state.updatingAll||(state.versionCheck&&state.versionCheck.running))return;
    state.versionCheck={running:true,manager:'running',luci:'running',hdp:'running',catalog:'running',job:'version'};
    renderOverview(root,window.dmState||{});
    return awaitSettingResult({ok:true,job:'version'}).then(function(r){
      state.versionCheck.running=false;
      if(!r||!r.ok)state.pageNotice.overview=(r&&r.error)||'Проверка актуальности не выполнена.';
      return refresh(root,true);
    }).catch(function(err){
      state.versionCheck.running=false;
      state.pageNotice.overview=withRpcError('Результат проверки версий неизвестен.',err);
      if(rootAlive(root))renderOverview(root,window.dmState||{});
    });
  }).catch(function(){});
}

function backgroundRequest(fn){
  var timer;
  var timeout=new Promise(function(resolve,reject){timer=setTimeout(function(){reject(new Error('Время ожидания ответа истекло'));},20000);});
  return Promise.race([Promise.resolve().then(fn),timeout]).then(function(v){clearTimeout(timer);return v;},function(e){clearTimeout(timer);throw e;});
}
function showUpdateResult(root,job,msg){
  var key='dns-manager-update-'+String(job.started||'')+'-'+String(job.finished||'');
  var finished=Number(job.finished||0), age=finished?Date.now()/1000-finished:0;
  try { if(sessionStorage.getItem(key)==='seen')return; } catch(e) {}
  if(age>300){try {sessionStorage.setItem(key,'seen');} catch(e) {} return;}
  globalUpdateNotice(msg,'ok');
  var notice=state.updateNotice;
  window.setTimeout(function(){
    try {sessionStorage.setItem(key,'seen');} catch(e) {}
    if(state.updateNotice===notice){state.updateNotice=null;if(rootAlive(root))renderOverview(root,window.dmState||{});}
  },8000);
}
function watchBackground(root,id){
  if(!rootAlive(root)||root.__dmBackgroundWatch===id)return;
  root.__dmBackgroundWatch=id;
  var errors=0;
  function poll(){
    if(!rootAlive(root)){root.__dmBackgroundWatch=null;return;}
    backgroundRequest(function(){return callJob(id);}).then(function(j){
      if(!rootAlive(root)){root.__dmBackgroundWatch=null;return;}
      if(!j||!j.ok){root.__dmBackgroundWatch=null;if(id==='update'&&state.updatingAll){state.updatingAll=false;globalUpdateNotice('Не удалось получить состояние обновления; проверьте версии перед повтором.','error');renderOverview(root,window.dmState||{});}else if(id==='combined'&&state.jobRunning){state.jobRunning=false;state.currentTest={status:'UNKNOWN'};state.pageNotice.doh='Не удалось получить состояние проверки; она может продолжаться.';renderDoH(root,window.dmState||{});}return;}
      errors=0;var running=String(j.status||'')==='running';
      if(id==='update'){
        state.updatingAll=running;
        var msg=j.name?'Обновляю: '+j.name+'…':'Обновление выполняется на роутере…';
        if(!running){try {var result=JSON.parse(j.output||'{}');msg=result.message||result.error||'Обновление завершено.';}catch(e){msg=j.result==='ok'?'Обновление завершено.':'Не удалось завершить обновление.';}if(j.result==='ok')msg+=' Обновите страницу для загрузки нового интерфейса.';}
        if(running)globalUpdateNotice(msg,'info');
        else if(j.result==='ok')showUpdateResult(root,j,msg);
        else globalUpdateNotice(msg,'error');
        renderOverview(root,window.dmState||{});
      }else{
        state.jobRunning=running;state.currentTest={status:running?'RUNNING':(j.result==='ok'?'DONE':'FAILED'),result:j.result||''};
        state.pageNotice.doh=running?'Проверка текущих DNS выполняется на роутере…':(j.result==='ok'?'':'Проверка текущих DNS завершилась с ошибками.');renderDoH(root,window.dmState||{});
      }
      if(running)window.setTimeout(poll,1500);else{root.__dmBackgroundWatch=null;refresh(root,true);}
    }).catch(function(){
      if(!rootAlive(root)){root.__dmBackgroundWatch=null;return;}
      if(++errors<5){window.setTimeout(poll,1500);return;}
      root.__dmBackgroundWatch=null;
      if(id==='update'){state.updatingAll=false;globalUpdateNotice('Не удалось получить состояние обновления. Оно может продолжаться на роутере.','error');renderOverview(root,window.dmState||{});}
      else{state.jobRunning=false;state.currentTest={status:'UNKNOWN'};state.pageNotice.doh='Не удалось получить состояние проверки. Она может продолжаться на роутере.';renderDoH(root,window.dmState||{});}
    });
  }poll();
}
function updateAll(root){
  if(state.updatingAll||state.busy||(state.versionCheck&&state.versionCheck.running))return;
  state.updatingAll=true;globalUpdateNotice('Запускаю обновление на роутере…','info');renderOverview(root,window.dmState||{});
  return backgroundRequest(callBackgroundUpdate).then(function(r){
    if(r&&r.ok){watchBackground(root,'update');return;}
    state.updatingAll=false;globalUpdateNotice((r&&r.error)||'Не удалось запустить обновление.','error');renderOverview(root,window.dmState||{});
  }).catch(function(){state.updatingAll=false;globalUpdateNotice('Ответ о запуске не получен. Проверяю состояние задачи.','info');watchBackground(root,'update');});
}
function uninstallManager(root){
  if(state.busy)return;
  state.busy=true;
  state.uninstall={status:'running',message:'Запускаю удаление…'};
  renderDoH(root,window.dmState||{});
  callUninstall().then(function(r){
    if(!r||!r.ok||!r.status_url)throw new Error((r&&r.error)||'Не удалось запустить удаление.');
    var attempts=0, started=Date.now();
    function show(status,message,output){
      state.uninstall={status:status,message:message,output:output||''};
      if(status==='failed')state.busy=false;
      renderDoH(root,window.dmState||{});
    }
    function poll(){
      if(++attempts>90||Date.now()-started>=180000){
        show('failed','Не удалось получить окончательный результат. Удаление может продолжаться; проверьте главную страницу LuCI.');
        return;
      }
      var controller=typeof AbortController==='function'?new AbortController():null;
      var options={cache:'no-store'};if(controller)options.signal=controller.signal;
      var timer;
      var request=fetch(r.status_url,options).then(function(response){
        if(!response.ok)throw new Error('status unavailable');
        return response.json();
      });
      var timeout=new Promise(function(resolve,reject){timer=window.setTimeout(function(){if(controller)controller.abort();reject(new Error('status timeout'));},10000);});
      Promise.race([request,timeout]).then(function(result){
        window.clearTimeout(timer);
        if(result.status==='done'){
          show('done','Функции отключены, системный DNS восстановлен, файлы менеджера удалены.');
        }else if(result.status==='failed'){
          callUninstallStatus().then(function(detail){
            show('failed','Проверьте сообщение ниже и повторите попытку.',detail&&detail.output);
          }).catch(function(){show('failed','Проверьте состояние DNS Manager в LuCI.');});
        }else{
          callUninstallStatus().then(function(detail){
            show('running',(detail&&detail.phase)||'Подготавливаю удаление…');
          }).catch(function(){
            show('running','Завершаю удаление интерфейса и служебных файлов…');
          }).then(function(){window.setTimeout(poll,2000);});
        }
      }).catch(function(){window.clearTimeout(timer);window.setTimeout(poll,2000);});
    }
    window.setTimeout(poll,1000);
  }).catch(function(err){
    state.busy=false;
    state.uninstall={status:'failed',message:withRpcError('Не удалось запустить удаление.',err)};
    renderDoH(root,window.dmState||{});
  });
}
function watchEngine(root){
  if(state.engineWatching)return;
  state.engineWatching=true;
  var errors=0;
  function poll(){
    callJob('engine').then(function(j){
      errors=0;
      if(j&&j.status==='running'){state.engineNotice=String(j.phase||'Переключение выполняется на роутере…');renderDoH(root,window.dmState||{});window.setTimeout(poll,2000);return;}
      state.engineWatching=false;state.busy=false;
      var ok=j&&j.status==='done'&&j.result==='ok';
      if(ok)clearEngineUiState();
      state.engineNoticeType=ok?'ok':'error';
      state.engineNotice=ok?'':((j&&j.output&&stripAnsi(j.output).split('\n').filter(function(x){return String(x||'').trim();}).pop())||'Не удалось подтвердить переключение. Проверьте DNS перед повтором.');
      refresh(root,true);
    }).catch(function(){
      if(++errors<3){window.setTimeout(poll,2000);return;}
      state.engineWatching=false;state.busy=false;state.engineNoticeType='error';
      state.engineNotice='Не удалось получить состояние. Операция может продолжаться на роутере.';
      renderDoH(root,window.dmState||{});
    });
  }
  poll();
}
function resumeEngine(root){
  if(state.engineResumeStarted)return;
  state.engineResumeStarted=true;
  callJob('engine').then(function(j){
    if(!j||!j.ok)return;
    if(j.status==='running'){
      clearEngineUiState();
      state.busy=true;state.engineNoticeType='info';state.engineNotice=String(j.phase||'Переключение выполняется на роутере…');
      renderDoH(root,window.dmState||{});watchEngine(root);
    }else if(j.status==='done'||j.status==='failed'){
      var ok=j.status==='done'&&j.result==='ok';
      state.engineNoticeType=ok?'ok':'error';
      state.engineNotice=ok?'':((j.output&&stripAnsi(j.output).split('\n').filter(function(x){return String(x||'').trim();}).pop())||'Переключение завершилось с ошибкой.');
      renderDoH(root,window.dmState||{});
    }
  }).catch(function(){});
}
function waitDnsHealth(r,longJob,onProgress){
  if(!r||!r.ok||r.job!=='health')return Promise.reject(new Error((r&&r.error)||'Не удалось запустить проверку DNS.'));
  var tries=0;
  function poll(){return callJob('health').then(function(j){
    if(j&&j.status==='running'&&tries++<(longJob?7200:120)){if(onProgress)onProgress(j);return new Promise(function(resolve){window.setTimeout(resolve,1000);}).then(poll);}
    if(!j||j.status!=='done')throw new Error('Не удалось получить результат проверки DNS.');
    return {ok:j.result==='ok',output:j.output};
  });}
  return poll();
}
function renderDnscryptDiagnostic(root){if(currentRoute()==='slots')renderSlots(root,window.dmState||{});else renderDoH(root,window.dmState||{});}
function dnscryptDiagnosticView(){
  if(state.dnscryptDiagnosticKind==='log')return E('pre',{'class':'dm-log'},state.dnscryptDiagnostic);
  if(state.dnscryptDiagnosticKind==='test'&&!state.dnscryptDiagnosticResult)return null;
  if(state.dnscryptDiagnosticKind!=='test')return E('div',{'class':'dm-inline-msg info'},state.dnscryptDiagnostic);
  var result=state.dnscryptDiagnosticResult;
  if(result==='ok')return null;
  return E('div',{'class':'dm-inline-msg '+(result==='waiting'?'info':'error')},result==='waiting'?'Ожидание подключения к сети.':(state.dnscryptDiagnostic==='Не удалось проверить серверы DNSCrypt.'?state.dnscryptDiagnostic:'Не удалось проверить DNS роутера.'));
}
function dnscryptDiagnostic(root,log){
  if(state.busy)return;
  state.busy=true;state.dnscryptDiagnosticKind=log?'log':'test';state.dnscryptDiagnosticResult='';state.dnscryptDiagnostic=log?'Загружаю журнал…':'Проверяю DNS…';renderDnscryptDiagnostic(root);
  (log?callDnscryptLog():callDnscryptTest().then(waitDnsHealth)).then(function(r){
    state.dnscryptDiagnosticResult=r&&r.ok?(String(r.output||'').trim()==='Ожидание подключения к сети.'?'waiting':'ok'):'error';
    state.dnscryptDiagnostic=String(r&&r.output||(log?'Записей пока нет.':'Нет данных.'));
    if(log&&(!r||!r.ok))state.dnscryptDiagnostic='Не удалось получить журнал.\n'+state.dnscryptDiagnostic;
  }).catch(function(err){state.dnscryptDiagnosticResult='error';state.dnscryptDiagnostic=withRpcError('Не удалось выполнить действие.',err);}).then(function(){state.busy=false;if(log)renderDnscryptDiagnostic(root);else refresh(root,true);});
}
function switchEngine(target,root){
  if(state.busy||state.jobRunning)return;
  var st=window.dmState||{};
  var firstInstall=st.dnscrypt_engine!=='dnscrypt-proxy2'&&Number(st.engine_installed)===0&&!displayDnsRows(st).length&&(!st.profile||st.profile==='none');
  var message=firstInstall?'Установить выбранный DNS-движок? DNS роутера будет возвращён к стандартным настройкам OpenWrt. Сохранённые настройки DNS Manager, если они есть, будут сброшены.':'Внимание! Переключение движка полностью сбросит текущие профили, слоты и привязки. Продолжить?';
  confirmAction(message,
    [['DNS-движок',target==='dnscrypt-proxy2'?'DNSCrypt Proxy 2':'HTTPS DNS Proxy']],function(){
      clearEngineUiState();
      state.busy=true;state.engineNoticeType='info';state.engineNotice='Запускаю настройку DNS-движка…';
      renderDoH(root,window.dmState||{});
      callSwitchEngine(target).then(function(r){
        if(!r||!r.ok||r.job!=='engine')throw new Error((r&&r.error)||'Не удалось запустить переключение.');
        state.engineNotice='Переключение выполняется на роутере…';renderDoH(root,window.dmState||{});watchEngine(root);
      }).catch(function(err){state.busy=false;state.engineNoticeType='error';state.engineNotice=withRpcError('Не удалось запустить переключение.',err);renderDoH(root,window.dmState||{});});
    });
}
function resetDnsCore(root,mode){
  if(state.busy)return;
  var disable=mode==='disable', dnscrypt=(window.dmState||{}).dnscrypt_engine==='dnscrypt-proxy2';
  confirmAction(disable?'Отключить защищённый DNS':'Вернуть начальные серверы',[
    ['Действие',disable?(dnscrypt?'Остановить DNSCrypt и вернуть обычный DNS роутера':'Остановить HTTPS DNS Proxy и вернуть обычный DNS роутера'):'Сбросить настройки DNS Manager и вернуть Cloudflare и Google']
  ],function(){
    state.busy=true;
    state.profileNoticeType='info';
    state.pageNotice.profiles=disable?'Отключаю защищённый DNS…':'Восстанавливаю начальные серверы…';
    renderProfiles(root,window.dmState||{});
    callResetDns(disable?'disable':'default').then(awaitSettingResult).then(function(r){
      state.busy=false;
      if(r&&r.ok){
        state.profileNoticeType='ok';
        setAction(true,(disable?'Защищённый DNS отключён.':'Начальные серверы восстановлены.'));
        state.pageNotice.profiles=(disable?'Защищённый DNS отключён.':'Начальные серверы восстановлены.');
      }else{
        state.profileNoticeType='error';
        setAction(false,(r&&r.error)||(disable?'Не удалось отключить защищённый DNS.':'Не удалось восстановить начальные серверы.'));
        state.pageNotice.profiles=(r&&r.error)||(disable?'Не удалось отключить защищённый DNS.':'Не удалось восстановить начальные серверы.');
      }
      refresh(root,true);
    }).catch(function(err){
      state.busy=false;
      state.profileNoticeType='error';
      setAction(false,withRpcError((disable?'Не удалось отключить защищённый DNS.':'Не удалось восстановить начальные серверы.'),err));
      state.pageNotice.profiles=withRpcError((disable?'Не удалось отключить защищённый DNS.':'Не удалось восстановить начальные серверы.'),err);
      refresh(root,true);
    });
  });
}
function setRegional(enabled,root){
  if(state.busy)return;
  state.busy=true;
  state.regionalNotice='Применяю региональный DNS…';
  state.regionalNoticeType='info';
  renderProfiles(root,window.dmState||{});
  callRegional(enabled).then(function(r){
    if(!r||!r.ok||!r.job)throw new Error((r&&r.error)||'Не удалось запустить изменение.');
    watchRegional(r.job,enabled,root);
  }).catch(function(err){
    state.busy=false;
    state.regionalNoticeType='error';
    state.regionalNotice=withRpcError('Не удалось запустить изменение.',err);
    renderProfiles(root,window.dmState||{});
  });
}
function watchRegional(job,enabled,root){
    var attempts=0,errors=0,started=Date.now();
    function poll(){
      callJob(job).then(function(j){
        errors=0;
        if(j&&j.status==='running'&&++attempts<450&&Date.now()-started<930000){window.setTimeout(poll,2000);return;}
        state.busy=false;
        var ok=j&&j.status==='done'&&j.result==='ok';
        state.regionalNoticeType=ok?'ok':'error';
        state.regionalNotice=ok?'Настройка российских сайтов применена.':
          ((j&&j.status==='running')?'Результат неизвестен: операция может продолжаться. Проверьте состояние перед повтором.':((j&&j.output&&stripAnsi(j.output).split('\n').filter(function(x){return String(x||'').trim();}).pop())||'Не удалось подтвердить изменение регионального DNS.'));
        refresh(root,true);
      }).catch(function(err){
        if(++errors<3&&Date.now()-started<930000){window.setTimeout(poll,2000);return;}
        state.busy=false;
        state.regionalNoticeType='error';
        state.regionalNotice=withRpcError('Результат неизвестен: операция может продолжаться. Проверьте состояние перед повтором.',err);
        renderProfiles(root,window.dmState||{});
      });
    }
    poll();
}
function resumeRegional(root){
  if(state.regionalResumeStarted||!rootAlive(root))return;
  state.regionalResumeStarted=true;
  callJob('regional').then(function(j){
    if(!j||!j.ok||j.status!=='running'||state.busy)return;
    state.busy=true;
    state.regionalNotice='Применяю региональный DNS…';
    state.regionalNoticeType='info';
    renderProfiles(root,window.dmState||{});
    watchRegional('regional',Number(j.enabled),root);
  }).catch(function(){});
}
function selectDnscryptServer(id,root){
  if(state.busy||state.jobRunning||!/^[A-Za-z0-9_-]+$/.test(String(id)))return;
  state.busy=true;state.dnscryptDiagnostic='Применяю выбранный сервер…';state.dnscryptDiagnosticKind='action';
  renderDnscryptDiagnostic(root);
  callProfile(dnscryptGoal('server:'+id,window.dmState||{})).then(function(r){
    if(!r||!r.ok||r.job!=='profile')throw new Error((r&&r.error)||'Не удалось начать применение сервера.');
    state.jobRunning=true;
    pollJob(root,r.job,{mode:'server',origin:'doh'},function(ns,j){
      var ok=j&&j.status==='done'&&j.result==='ok';
      if(ok)clearEngineUiState();
      state.busy=false;state.dnscryptDiagnostic=ok?(j.status_error?'Сервер выбран, но состояние не обновилось. Обновите страницу.':'Сервер выбран.'):(j&&j.unknown?'Результат неизвестен: операция может продолжаться. Проверьте состояние перед повтором.':('Не удалось применить сервер. '+stripAnsi(String(j&&j.output||''))));
      state.dnscryptDiagnosticKind='action';renderDnscryptDiagnostic(root);
    });
  }).catch(function(err){state.busy=false;state.dnscryptDiagnostic=withRpcError('Не удалось применить сервер.',err);renderDnscryptDiagnostic(root);});
}
function applyProfile(name,root,confirmed){
  if(state.busy)return;
  var st=window.dmState||{};
  var currentId=activeProfileId(st),current=currentId?profileName(currentId):activeProfileLabel(st),next=profileName(name);
  var repeat=currentId===name;
  function startProfile(){
    state.busy=true;
    state.profileProgress={p:5,label:'Подготавливаю профиль…',detail:''};
    state.profileOutput='';
    state.pageNotice.profiles='';
    renderProfiles(root,window.dmState||{});
    callProfile(st.dnscrypt_engine==='dnscrypt-proxy2'?dnscryptGoal(name,st):name).then(function(r){
      if(r&&r.ok&&r.job){
        pollJob(root,r.job,{mode:'profile',profile:name});
        return;
      }
      state.busy=false;
      if(r&&r.ok){
        state.profileProgress={p:100,label:'Профиль применён.',detail:''};
        state.pageNotice.profiles='';
      }else{
        state.profileNoticeType='error';
        setAction(false,(r&&r.error)||'Профиль не удалось запустить.');
        state.pageNotice.profiles=(r&&r.error)||'Профиль не удалось запустить.';
      }
      refresh(root,true);
    }).catch(function(err){
      state.busy=false;
      state.profileProgress=null;
      state.profileNoticeType='error';
      setAction(false,withRpcError('Не удалось запустить применение профиля.',err));
      state.pageNotice.profiles=withRpcError('Не удалось запустить применение профиля.',err);
      refresh(root,true);
    });
  }
  if(confirmed)startProfile();
  else if(name==='default'&&st.dnscrypt_engine==='dnscrypt-proxy2')confirmAction('Вернуть начальные серверы',[['DNS',dnscryptOptions(st).protocol==='native'?'AdGuard и Quad9 (DNSCrypt)':'Cloudflare и Google'],['Профиль','Текущий выбор будет сброшен']],startProfile);
  else confirmAction(repeat?'Повторно применить профиль':'Подтвердить изменение профиля',[['Сейчас',current],[repeat?'Профиль':'Новый профиль',next]],startProfile);
}
function awaitSettingResult(reply){
  if(!reply||!reply.ok||!reply.job)return Promise.resolve(reply);
  var attempts=0,errors=0,started=Date.now();
  return new Promise(function(resolve,reject){
    function poll(){
      callJob(reply.job).then(function(j){
        errors=0;
        if(j&&j.status==='running'&&attempts++<200&&Date.now()-started<330000){window.setTimeout(poll,1500);return;}
        if(j&&(j.status==='done'||j.status==='failed')){
          var result;
          try{result=JSON.parse(String(j.output||'').trim());}catch(e){result=null;}
          if(j.status==='done'&&j.result==='ok'&&result&&result.ok){resolve(result);return;}
          resolve({ok:false,error:(result&&result.error)||String(j.output||'').trim()||'Не удалось подтвердить результат настройки.'});
          return;
        }
        reject(new Error('Результат неизвестен: операция может продолжаться. Проверьте состояние перед повтором.'));
      }).catch(function(err){if(++errors<3&&Date.now()-started<330000){window.setTimeout(poll,1500);return;}reject(new Error('Результат неизвестен: операция может продолжаться. Проверьте состояние перед повтором.'));});
    }
    poll();
  });
}
function setSetting(name,en,root){
  if(state.busy)return;
  clearSettingFeedback();
  state.busy=true;state.busySetting=name;
  setSettingFeedback(name,'Применяю настройку…','info');
  if(state.activeTab==='network')renderNetwork(root,window.dmState||{});
  else if(state.activeTab==='doh')renderDoH(root,window.dmState||{});
  else if(state.activeTab==='catalog')renderCatalog(root);
  callSetting(name,en).then(awaitSettingResult).then(function(r){
    state.busy=false;state.busySetting='';
    if(r&&r.ok){
      if(window.dmState)window.dmState[name]=String(en);
      setSettingFeedback(name,'Настройка «'+settingName(name)+'»: '+(name==='dc_cache_size'||name==='dc_cache_ttl'?'сохранена.':(en?'включена.':'выключена.')),'ok');
    }else{
      setSettingFeedback(name,'Настройка «'+settingName(name)+'»: '+((r&&r.error)||'не удалось изменить.'),'error');
    }
    refresh(root,true);
  }).catch(function(err){
    state.busy=false;state.busySetting='';
    setSettingFeedback(name,'Настройка «'+settingName(name)+'»: '+withRpcError('не удалось изменить.',err),'error');
    refresh(root,true);
  });
}
function setForceMode(mode,root){
  if(state.busy)return;
  var en=mode==='auto'?1:0;
  state.busy=true;
  state.busySetting='force';
  state.pageNotice.doh='Изменение перехвата DNS…';
  renderDoH(root,window.dmState||{});
  callSetting('force',en).then(awaitSettingResult).then(function(r){
    state.busy=false;state.busySetting='';
    if(r&&r.ok){
      window.dmState=window.dmState||{};
      [
        'force','force_external','force_owner','force_manager','force_both',
        'force_source','force_targets','force_state','force_status',
        'force_notrack','force_update','force_family','force_ports','force_src',
        'force_canary_icloud','force_canary_mozilla','force_procd_trigger_wan6',
        'force_heartbeat_domain','force_heartbeat_sleep','force_heartbeat_wait',
        'force_user','force_group','force_listen','force_consistent',
        'force_owner_label','zapret_running','steer_dns_active'
      ].forEach(function(k){if(Object.prototype.hasOwnProperty.call(r,k))window.dmState[k]=r[k];});
      state.pageNotice.doh=en?(r.force_status==='manager'||r.force_status==='steer'?'Принудительный DNS включён.':'Настройка сохранена, но перехват DNS не обнаружен. Проверьте службу DNS и правила сети.'):(r.force_owner==='steer'?'Настройка DNS Manager выключена; перехват Steer продолжает работать.':yes(r.force_external)?'Настройка DNS Manager выключена; внешний перехват может продолжать работать.':'Настройка принудительного DNS Manager выключена.');
      renderDoH(root,window.dmState);
    }else{
      state.pageNotice.doh=(r&&r.error)||'Не удалось изменить перехват DNS.';
      renderDoH(root,window.dmState||{});
    }
  }).catch(function(err){
    state.busy=false;state.busySetting='';
    state.pageNotice.doh=withRpcError('Не удалось изменить перехват DNS.',err);
    renderDoH(root,window.dmState||{});
  });
}
function resumeSetting(root){
  if(state.settingResumeStarted||!rootAlive(root))return;
  state.settingResumeStarted=true;
  callJob('setting').then(function(j){
    if(!j||!j.ok||j.status!=='running'||state.busy)return;
    var name=String(j.name||'');
    if(['force','encrypted_dns','browser_dns','watchdog','watchdog_autoreplace','dnsmasq_perf'].indexOf(name)<0)return;
    state.busy=true;state.busySetting=name;
    if(name==='force')state.pageNotice.doh='Изменение перехвата DNS…';
    else setSettingFeedback(name,'Применяю настройку…','info');
    render(root,window.dmState||{});
    return awaitSettingResult({ok:true,job:'setting'}).then(function(r){
      state.busy=false;state.busySetting='';
      var message=(r&&r.ok)?'Настройка применена.':((r&&r.error)||'Не удалось подтвердить результат настройки.');
      if(name==='force')state.pageNotice.doh=message;
      else setSettingFeedback(name,message,r&&r.ok?'ok':'error');
      return refresh(root,true);
    }).catch(function(err){
      state.busy=false;state.busySetting='';
      var message=withRpcError('Не удалось получить результат настройки.',err);
      if(name==='force')state.pageNotice.doh=message;else setSettingFeedback(name,message,'error');
      render(root,window.dmState||{});
    });
  }).catch(function(){});
}
function resumeAction(root){
  if(state.actionResumeStarted||!rootAlive(root))return;
  state.actionResumeStarted=true;
  callJob('action').then(function(j){
    if(!j||!j.ok||j.status!=='running'||state.busy){state.actionResumeStarted=false;return;}
    var route=currentRoute(),name=String(j.name||'');
    var applies=(name==='set_slot'&&(route==='slots'||route==='catalog'||route==='doh'))||
      (name==='set_slot_domains'&&route==='slots')||(name==='set_device_dns'&&route==='devices')||
      (name==='set_ntp'&&route==='time')||((name==='set_cache'||name==='set_watchdog_setting'||name==='set_watchdog_settings')&&route==='network')||((name==='add_custom_dns'||name==='delete_custom_dns'||name==='set_test_age')&&route==='catalog')||((name==='reset_dns'||name==='set_bootstrap')&&route==='doh');
    if(!applies){state.actionResumeStarted=false;return;}
    var key=route==='devices'?'slots':route==='doh'?(name==='set_slot'?'doh':'profiles'):route;
    state.busy=true;state.pageNotice[key]='Операция выполняется…';
    if(name==='set_bootstrap'){state.busySetting='bootstrap';state.bootstrapNotice={type:'info',text:'Применяю bootstrap DNS…'};state.pageNotice[key]='';}
    if(name==='set_cache'){state.busySetting='dns_cache';setSettingFeedback('dns_cache','Применяю настройки…','info');state.pageNotice[key]='';}
    if(route==='doh')state.profileNoticeType='info';
    if(route==='time')state.timeNoticeType='info';
    render(root,window.dmState||{});
    return awaitSettingResult({ok:true,job:'action'}).then(function(r){
      state.busy=false;state.actionResumeStarted=false;
      state.pageNotice[key]=r&&r.ok?'Операция выполнена.':((r&&r.error)||'Не удалось подтвердить результат.');
      if(name==='set_bootstrap'){state.busySetting='';state.bootstrapNotice={type:r&&r.ok?'ok':'error',text:state.pageNotice[key]};state.pageNotice[key]='';if(r&&r.ok)state.bootstrapDraft=null;}
      if(name==='set_cache'){state.busySetting='';if(r&&r.ok)state.cacheDraft=null;setSettingFeedback('dns_cache',state.pageNotice[key],r&&r.ok?'ok':'error');state.pageNotice[key]='';}
      if(route==='doh')state.profileNoticeType=r&&r.ok?'ok':'error';
      if(route==='time')state.timeNoticeType=r&&r.ok?'ok':'error';
      return refresh(root,true);
    }).catch(function(err){
      state.busy=false;state.actionResumeStarted=false;state.pageNotice[key]=withRpcError('Не удалось получить результат операции.',err);
      if(name==='set_bootstrap'){state.busySetting='';state.bootstrapNotice={type:'error',text:state.pageNotice[key]};state.pageNotice[key]='';}
      if(name==='set_cache'){state.busySetting='';setSettingFeedback('dns_cache',state.pageNotice[key],'error');state.pageNotice[key]='';}
      if(route==='doh')state.profileNoticeType='error';
      if(route==='time')state.timeNoticeType='error';
      return refresh(root,true);
    });
  }).catch(function(){state.actionResumeStarted=false;});
}
function resumeCatalogTest(root){
  if(!rootAlive(root)||root.__dmCatalogResumed||state.jobRunning)return;
  root.__dmCatalogResumed=true;
  backgroundRequest(function(){return callJob('test_page');}).then(function(j){
    if(!rootAlive(root)||!j||!j.ok||state.jobRunning)return;
    if(j.status==='running'){
      state.jobRunning=true;state.fullTest={status:'RUNNING',origin:'catalog'};
      state.pageNotice.catalog='';
      renderCatalog(root);pollJob(root,'test_page',{mode:'all',origin:'catalog'});
    }else if(j.status==='done'||j.status==='failed'){
      var ok=j.status==='done'&&j.result==='ok';
      state.catalogCancelled=j.cancelled==='1';state.fullTest={status:ok?'DONE':'FAILED',result:j.result||'fail',origin:'catalog'};
      state.catalogProgress={done:Number(j.progress_done||0),total:Number(j.progress_total||0),ok:Number(j.progress_ok||0),fail:Number(j.progress_fail||0),detail:ok?'':'Полная проверка DNS завершилась с ошибкой.'};
      state.pageNotice.catalog='';
      renderCatalog(root);
    }
  }).catch(function(){root.__dmCatalogResumed=false;});
}
function testAll(root,origin){
  if(state.jobRunning||state.busy)return;
  var from=origin||state.activeTab||'overview';
  state.jobRunning=true;
  state.fullTest={status:'RUNNING',origin:from,started:Date.now()};
  if(from==='catalog'){
    state.catalogProgress={
      done:0,
      total:0,
      ok:0,
      fail:0,
      detail:'Проверяю серверы на этой странице…'
    };
  }
  if(from==='catalog')state.pageNotice.catalog='';
  if(from==='catalog')renderCatalog(root);else renderOverview(root,window.dmState||{});
  state.catalogStopping=false;
  state.catalogCancelled=false;
  (from==='catalog'?callTestPage(catalogPageIds()):callTestAll()).then(function(r){
    if(r&&r.ok)pollJob(root,r.job,{mode:'all',origin:from});
    else{
      state.fullTest={status:'FAILED',origin:from};
      state.jobRunning=false;
      if(from==='catalog')state.catalogProgress.detail=(r&&r.error)||'Полная проверка DNS не запущена.';
      refresh(root,true);
    }
  }).catch(function(err){
    state.fullTest={status:'FAILED',origin:from};
    state.jobRunning=false;
    if(from==='catalog')state.catalogProgress.detail=withRpcError('Не удалось запустить полную проверку DNS.',err);
    refresh(root,true);
  });
}
function testOne(id,root,origin,done){
  if(state.jobRunning||state.busy||!id)return;
  state.lastJob=null;state.jobRunning=true;
  state.checking[id]={status:'RUNNING',ping:'',started:Date.now()};
  render(root,window.dmState||{});
  callTestOne(id).then(function(r){
    if(r&&r.ok){
      var onDone=done?function(ns){
        // The modal picker callback replaces only the modal. Re-render the page
        // first so controls disabled by jobRunning are enabled without F5.
        render(root,ns||window.dmState||{});
        done(ns||window.dmState||{});
      }:undefined;
      pollJob(root,r.job,{mode:'one',dns_id:id,origin:origin||''},onDone);
    }else{
      delete state.checking[id];
      state.jobRunning=false;
      var msg=(r&&r.error)||'Не удалось запустить проверку DNS.';
      setAction(false,msg);
      if(origin==='catalog')state.pageNotice.catalog=msg;else state.pageNotice.slots=msg;
      refresh(root,true);
      if(done)done(window.dmState||{});
    }
  }).catch(function(err){
    delete state.checking[id];
    state.jobRunning=false;
    var msg=withRpcError('Не удалось запустить проверку DNS.',err);
    setAction(false,msg);
    if(origin==='catalog')state.pageNotice.catalog=msg;else state.pageNotice.slots=msg;
    refresh(root,true);
    if(done)done(window.dmState||{});
  });
}
function testCurrent(root){
  if(state.jobRunning||state.busy)return;
  var targets=displayDnsRows(window.dmState||{}).filter(function(d){return d&&((d.slot&&d.id)||(!d.slot&&d.url&&d.port));});
  if(!targets.length){
    state.busy=true;state.currentTest=null;state.pageNotice.doh='Проверяю системный DNS…';renderDoH(root,window.dmState||{});
    return callSystemDnsTest().then(waitDnsHealth).then(function(r){state.pageNotice.doh=r&&r.ok?(String(r.output||'').trim()==='Ожидание подключения к сети.'?'Ожидание подключения к сети.':''):((r&&r.output)||'Не удалось проверить системный DNS.');})
      .catch(function(err){state.pageNotice.doh=withRpcError('Не удалось проверить системный DNS.',err);})
      .then(function(){state.busy=false;renderDoH(root,window.dmState||{});});
  }
  state.jobRunning=true;state.currentTest={status:'RUNNING'};state.pageNotice.doh='Запускаю проверку на роутере…';renderDoH(root,window.dmState||{});
  return backgroundRequest(callCombinedTest).then(function(r){
    if(r&&r.ok){watchBackground(root,'combined');return;}
    state.jobRunning=false;state.currentTest={status:'FAILED'};state.pageNotice.doh=(r&&r.error)||'Не удалось запустить проверку.';renderDoH(root,window.dmState||{});
  }).catch(function(){state.jobRunning=false;state.pageNotice.doh='Ответ о запуске не получен. Проверяю состояние задачи.';watchBackground(root,'combined');});
}
function pollJob(root,job,meta,done){
  var jobId=(typeof job==='string')?job:(job&&job.id)||'';
  if(!jobId){
    state.jobRunning=false;
    var noJob='Фоновая задача DNS Manager не вернула идентификатор.';
    setAction(false,noJob);
    if(meta&&meta.mode==='profile'){state.busy=false;state.profileProgress=null;state.profileNoticeType='error';state.pageNotice.profiles=noJob;}
    if(meta&&meta.mode==='one'&&meta.dns_id)delete state.checking[meta.dns_id];
    if(meta&&meta.mode==='all')state.fullTest={status:'FAILED',result:'fail',origin:meta.origin||''};
    if(done)done(window.dmState||{},{status:'failed',result:'fail'});
    else render(root,window.dmState||{});
    return;
  }
  var ticks=0, errors=0;
  var maxTicks=(meta&&meta.mode==='profile')?900:((meta&&meta.mode==='all')?1600:180);
  var maxErrors=(meta&&meta.mode==='profile')?30:8;
  function profileFinish(j){
    if(!meta||meta.mode!=='profile')return;
    var label=profileName(meta.profile||'');
    var ok=String(j&&j.status||'').toUpperCase()==='DONE' && String(j&&j.result||'')==='ok';
    state.busy=false;
    if(ok){
      state.profileProgress=null;
      state.profileNoticeType='ok';
      setAction(true,'Профиль: «'+label+'».');
      state.pageNotice.profiles='';
    }else{
      state.profileNoticeType='error';
      var out=stripAnsi(j&&j.output||'').trim().split('\n').filter(function(x){return String(x||'').trim();});
      var detail=out.length?String(out[out.length-1]).trim():'';
      if(detail.length>360)detail=detail.slice(0,357)+'…';
      var msg=j&&j.unknown?'Не удалось получить результат применения профиля «'+label+'». Операция может продолжаться; проверьте состояние перед повтором.':'Профиль «'+label+'» не удалось применить.';
      if(detail)msg+=' '+detail;
      state.profileProgress=null;
      setAction(false,msg);
      state.pageNotice.profiles=msg;
    }
  }
  function finish(j){
    if(meta&&meta.mode==='profile'){
      profileFinish(j);
    }
    (meta&&((['profile','server','current','system'].indexOf(meta.mode)!==-1&&currentRoute()==='doh')||(meta.mode==='server'&&currentRoute()==='slots'))?callDohStatus():callStatus(statusDetail())).then(function(ns){
      ns=ns||{};if((!window.dmCurrentRoot||window.dmCurrentRoot===root)&&(!root.__dmRoute||currentRoute()===root.__dmRoute))window.dmState=ns;
      if(meta&&meta.mode==='one'&&meta.dns_id)delete state.checking[meta.dns_id];
      if(meta&&meta.mode==='current')state.checking={};
      state.jobRunning=false;
      if(done)done(ns,j);
      else{
        if(meta&&meta.mode==='one'&&meta.origin==='catalog'&&window.dmCatalog){
          return callCatalog(catalogCategory(),state.offset,state.limit,0).then(function(cd){
            window.dmCatalog=cd||{};
            render(root,ns);
          }).catch(function(){render(root,ns);});
        }
        if(meta&&meta.mode==='all'){
          state.catalogCancelled=j.cancelled==='1';
          var allOk=String(j.status||'').toUpperCase()==='DONE'&&j.result==='ok';
          state.fullTest={status:allOk?'DONE':'FAILED',result:j.result||'fail',finished:Date.now(),origin:meta.origin||''};
          if(meta.origin==='catalog'){
            if(!state.catalogProgress)state.catalogProgress={done:0,total:0,ok:0,fail:0,detail:''};
            if(j.progress_done!==''&&j.progress_done!=null)state.catalogProgress.done=Number(j.progress_done);
            if(j.progress_total!==''&&j.progress_total!=null)state.catalogProgress.total=Number(j.progress_total);
            if(j.progress_ok!==''&&j.progress_ok!=null)state.catalogProgress.ok=Number(j.progress_ok);
            if(j.progress_fail!==''&&j.progress_fail!=null)state.catalogProgress.fail=Number(j.progress_fail);
            state.catalogProgress.detail=allOk?'':((j.output&&stripAnsi(j.output).split('\n').filter(function(x){return String(x||'').trim();}).pop())||'Полная проверка DNS завершилась с ошибкой.');
            state.pageNotice.catalog='';
            window.dmCatalog=null;
            state.catalogLoaded=false;
          }
        }
        if(meta&&meta.mode==='current')state.currentTest={status:String(j.status||'').toUpperCase()==='DONE'?'DONE':'FAILED',result:j.result||'fail',finished:Date.now()};
        if(meta&&meta.mode==='system'){var systemOk=String(j.status||'').toUpperCase()==='DONE'&&j.result==='ok';state.currentSystemTest={status:systemOk?'DONE':'FAILED',result:j.result||'fail',finished:Date.now()};state.pageNotice.doh=systemOk?'Проверка системных DNS завершена.':'Проверка системных DNS завершена с ошибками.';}
        render(root,ns);
        if(meta&&meta.mode==='all'&&meta.origin==='catalog'&&state.activeTab==='catalog'){
          loadCatalog(root);
        }
      }
    }).catch(function(err){
      if(meta&&meta.mode==='profile'){
        state.busy=false;
        state.profileProgress=null;
        state.profileNoticeType='error';
        setAction(false,'Применение профиля завершилось, но состояние роутера не удалось обновить.');
        state.pageNotice.profiles='Применение профиля завершилось, но состояние роутера не удалось обновить.';
      }
      if(meta&&meta.mode==='one'&&meta.dns_id)delete state.checking[meta.dns_id];
      var jobErr=rpcErrorText(err);
      if(jobErr){
        if(meta.origin==='doh')state.pageNotice.doh='Проверка DNS не выполнена: '+jobErr;
      }
      if(meta&&meta.mode==='current')state.checking={};
      state.jobRunning=false;
      if(meta&&meta.mode==='all'&&!done){
        var allOk=String(j&&j.status||'').toUpperCase()==='DONE'&&j.result==='ok';
        state.fullTest={status:allOk?'DONE':'FAILED',result:j.result||'fail',finished:Date.now(),origin:meta.origin||''};
        if(meta.origin==='catalog'){
          if(!state.catalogProgress)state.catalogProgress={done:0,total:0,ok:0,fail:0,detail:''};
          ['done','total','ok','fail'].forEach(function(k){var v=j['progress_'+k];if(v!==''&&v!=null)state.catalogProgress[k]=Number(v);});
          state.catalogProgress.detail=allOk?'': 'Проверка завершилась с ошибкой.';
          state.pageNotice.catalog=allOk?'Проверка завершена, но состояние роутера не удалось обновить.':'';
          window.dmCatalog=null;state.catalogLoaded=false;
        }
        render(root,window.dmState||{});
        if(meta.origin==='catalog'&&state.activeTab==='catalog')loadCatalog(root);
        return;
      }
      if(done)done(window.dmState||{},meta&&meta.mode==='server'?Object.assign({},j,{status_error:true}):{status:'failed',result:'fail'});
      else{if(meta&&meta.mode==='all')state.fullTest={status:'FAILED',result:'fail'};if(meta&&meta.mode==='current')state.currentTest={status:'FAILED',result:'fail'};render(root,window.dmState||{});}
    });
  }
  function poll(){
    callJob(jobId).then(function(j){
      j=j||{};
      if(j.ok===false)throw new Error(j.error||'RPC задачи недоступен');
      errors=0;
      if(meta&&meta.mode==='profile'){
        state.profileOutput=stripAnsi(j.output||'');
        profileProgressUpdate(j);
        renderProfiles(root,window.dmState||{});
      }
      if(meta&&meta.mode==='all'&&meta.origin==='catalog'){
        var pout=stripAnsi(j.output||'');
        var lines=pout.split('\n').filter(function(x){return String(x||'').trim();});
        var lastProgress='';
        var pd=0,pt=0,po=0,pf=0;
        for(var pi=lines.length-1;pi>=0;pi--){
          var pl=String(lines[pi]||'').trim();
          if(pl.indexOf('Промежуточный результат:')>=0){
            lastProgress=pl;
            var pm=pl.match(/Промежуточный результат:\s*проверено\s+(\d+)\s+из\s+(\d+)\s*\|\s*работают\s+(\d+)\s*\|\s*ошибки\s+(\d+)/i);
            if(pm){pd=Number(pm[1]||0);pt=Number(pm[2]||0);po=Number(pm[3]||0);pf=Number(pm[4]||0);}
            break;
          }
        }
        state.catalogProgress={
          done:pd||Number(j.progress_done||0),
          total:pt||Number(j.progress_total||0),
          ok:po||Number(j.progress_ok||0),
          fail:pf||Number(j.progress_fail||0),
          detail:''
        };
        renderCatalog(root);
      }
      var s=String(j.status||'running').toUpperCase();
      if(s==='RUNNING'){
        var startedTs=Number(j.started||0);
        var maxSeconds=(meta&&meta.mode==='profile')?900:((meta&&meta.mode==='all')?1800:((meta&&meta.mode==='one')?60:300));
        if(startedTs>0&&Math.floor(Date.now()/1000)-startedTs>=maxSeconds){
          finish({status:'FAILED',result:'fail',unknown:true,started:j.started,output:'Операция может продолжаться на роутере. Проверьте состояние перед повтором.'});
          return;
        }
      }
      if(s==='DONE'||s==='FAILED'){finish(j);return;}
      if(ticks++>maxTicks){finish({status:'FAILED',result:'fail',unknown:true,output:'Превышено время ожидания фоновой задачи; её результат неизвестен.'});return;}
      setTimeout(poll,1200);
    }).catch(function(){
      if(++errors>maxErrors){finish({status:'FAILED',result:'fail',unknown:true,output:'RPC задачи недоступен; её результат неизвестен.'});return;}
      setTimeout(poll,1200);
    });
  }
  poll();
}

// Recover the most recent operation when a page is opened again.
function showRecentJob(root){
  var ids=['profile','regional','action','setting','engine','update','version','test_all','test_current','test_one','test_system'];
  var labels={profile:'Применение профиля',regional:'Региональный DNS',action:'Изменение настроек',setting:'Изменение настройки',engine:'Смена DNS-движка',update:'Обновление',version:'Проверка версий',test_all:'Проверка каталога DNS',test_current:'Проверка выбранных DNS',test_one:'Проверка DNS',test_system:'Проверка системных DNS'};
  function read(id){return callJob(id).catch(function(){return null;});}
  function display(j){
    if(!rootAlive(root)||!j)return;
    var running=j.status==='running',ok=j.status==='done'&&j.result==='ok';
    var key='dns-manager-job-'+j.job+'-'+j.started;
    var age=Date.now()/1000-Number(j.finished||0);
    if(!running&&(age<0||age>300))return;
    try{if(!running&&window.sessionStorage.getItem(key))return;}catch(e){}
    var text=(labels[j.job]||'Операция')+': '+(running?'выполняется…':ok?'выполнено':'ошибка');
    if(!running&&!ok){
      var detail=String(j.error||'');
      if(!detail){try{detail=String(JSON.parse(String(j.output||'')).error||'');}catch(e){}}
      if(detail)text+=' — '+detail;
    }
    var old=root.querySelector('.dm-job-recovery');if(old)old.remove();
    var box=E('div',{'class':'dm-job-recovery'},[badge(running?'dm-warn':ok?'dm-ok':'dm-bad',text)]);
    root.insertBefore(box,root.children[1]||null);
    if(running){
      window.setTimeout(function(){read(j.job).then(display);},1000);
    }else{
      try{window.sessionStorage.setItem(key,'1');}catch(e){}
      window.setTimeout(function(){if(box.parentNode)box.remove();},8000);
    }
  }
  Promise.all(ids.map(read)).then(function(jobs){
    var recent=jobs.filter(function(j){return j&&j.ok&&(j.status==='running'||j.status==='done'||j.status==='failed');});
    recent.sort(function(a,b){return Number(b.started||0)-Number(a.started||0);});
    if(recent.length)display(recent[0]);
  });
}

function resumeRunningProfile(root){
  if(state.profileResumeStarted||!rootAlive(root))return;
  state.profileResumeStarted=true;
  callJob('profile').then(function(j){
    var st=String(j&&j.status||'').toLowerCase();
    if(st!=='running')return;
    var p=String(j.profile||'');
    state.busy=true;
    state.jobRunning=true;
    state.lastJob='profile';
    state.profileProgress={p:5,label:'Профиль уже применяется…',detail:'Связь с задачей восстановлена. Продолжаю отслеживание.'};
    setAction(true,p?'Профиль «'+profileName(p)+'» уже применяется. Связь восстановлена.':'Применение профиля уже выполняется. Связь восстановлена.','running');
    if(rootAlive(root))renderProfiles(root,window.dmState||{});
    pollJob(root,'profile',{mode:'profile',profile:p});
  }).catch(function(err){
    var msg=rpcErrorText(err);
    if(msg&&/задач[ау] не найден|not found/i.test(msg))return;
    if(rootAlive(root)&&msg)state.pageNotice.profiles='Проверил незавершённую операцию: '+msg;
  });
}
function removeLegacyCbiActions(){
  var nodes=document.querySelectorAll('.cbi-page-actions');
  Array.prototype.forEach.call(nodes,function(n){
    if(n.closest && n.closest('.dm-wrap'))return;
    var t=String(n.textContent||'').replace(/\s+/g,' ').trim();
    if(/(Применить|Сохранить|Сброс|Save & Apply|Save|Reset)/i.test(t))n.remove();
  });
}

function catalogCategory(){
  return (window.dmState||{}).dnscrypt_engine==='dnscrypt-proxy2'?state.catalogProtocol+':'+state.category:state.category;
}
function loadCatalog(root){
  if(state.catalogLoading)return Promise.resolve();
  state.catalogLoading=true;renderCatalog(root);
  return callCatalog(catalogCategory(),state.offset,state.limit,0).then(function(d){
    if(!d||d.ok===false)throw new Error((d&&d.error)||'Каталог DNS недоступен.');
    if(state.catalogLoadFailed)state.pageNotice.catalog='';state.catalogLoadFailed=false;
    state.catalogLoading=false;state.catalogLoaded=true;window.dmCatalog=d||{};renderCatalog(root);renderCatalogBody(root,window.dmCatalog);
  }).catch(function(err){
    state.catalogLoading=false;state.catalogLoaded=false;state.catalogLoadFailed=true;window.dmCatalog=null;state.pageNotice.catalog=withRpcError('Не удалось загрузить каталог DNS.',err);renderCatalog(root);
  });
}
function showLog(root){
  if(state.logLoading)return Promise.resolve();
  state.logLoading=true;
  return callLog(160).then(function(r){if(!r||r.ok===false)throw new Error((r&&r.error)||'Журнал недоступен.');state.logLoading=false;state.logLoaded=true;state.logText=stripAnsi(r.log||'');renderLog(root);}).catch(function(err){state.logLoading=false;state.pageNotice.log=withRpcError('Не удалось загрузить журнал.',err);renderLog(root);});
}

var autoStatusTimer=null;
var uptimeTimer=null;
var fullStatusTimer=null;
var dashboardPollTimer=null;
function stopAutoStatus(){
  if(autoStatusTimer){clearInterval(autoStatusTimer);autoStatusTimer=null;}
  if(uptimeTimer){clearInterval(uptimeTimer);uptimeTimer=null;}
  if(fullStatusTimer){clearInterval(fullStatusTimer);fullStatusTimer=null;}
  if(dashboardPollTimer){clearInterval(dashboardPollTimer);dashboardPollTimer=null;}
}
function syncLocalUptime(root,sec){
  var n=Number(sec);
  if(!isFinite(n)||n<0)return;
  state.runtimeUptimeBase=Math.floor(n);
  state.runtimeUptimeAt=Date.now();
  var node=root&&root.querySelector?root.querySelector('#dm-runtime-uptime'):null;
  if(node)node.textContent=uptime(state.runtimeUptimeBase);
}
function tickLocalUptime(root){
  if(!rootAlive(root)||!state.runtimeUptimeAt)return;
  var elapsed=Math.max(0,Math.floor((Date.now()-state.runtimeUptimeAt)/1000));
  var value=state.runtimeUptimeBase+elapsed;
  var node=root.querySelector('#dm-runtime-uptime');
  if(node)node.textContent=uptime(value);
}
function applyRuntime(rt){
  if(!rt)return;
  var cl=Number(rt.cpu_load);
  if(isFinite(cl))state.runtimeCpuLoad=Math.max(0,Math.min(100,cl));
}
function applyBoardInfo(root,b){
  if(!b||typeof b!=='object')return;
  state.boardInfo=b;
  var up=Number(b.uptime);
  if(isFinite(up)&&up>=0)syncLocalUptime(root,up);
  var totalKb=boardMemoryKb(b,'total'),availKb=boardMemoryAvailableKb(b);
  if(isFinite(totalKb)&&totalKb>0)state.runtimeMemoryTotal=totalKb;
  if(isFinite(availKb)&&availKb>=0)state.runtimeMemoryAvailable=availKb;
}
function pollSystem(root){
  if(!rootAlive(root)||document.hidden||currentRoute()!=='dashboard'||state.systemPollBusy)return Promise.resolve();
  state.systemPollBusy=true;
  return Promise.all([
    callBoardInfo().catch(function(){return null;}),
    callRuntime().catch(function(){return null;})
  ]).then(function(v){
    if(!rootAlive(root))return;
    if(v[0])applyBoardInfo(root,v[0]);
    if(v[1])applyRuntime(v[1]);
    renderSystemCard(root);
  }).catch(function(){}).then(function(){
    state.systemPollBusy=false;
  });
}
function startAutoStatus(root){
  stopAutoStatus();
  state.systemPollBusy=false;
  var tick=0;
  var watchdogPollBusy=false;
  if(currentRoute()==='dashboard')pollSystem(root);
  dashboardPollTimer=setInterval(function(){
    if(!rootAlive(root)){
      stopAutoStatus();
      return;
    }
    var route=currentRoute();
    if(document.hidden||(route!=='dashboard'&&route!=='doh'))return;
    tick++;
    if(route==='dashboard')tickLocalUptime(root);
    if(route==='dashboard'&&tick%5===0){
      pollSystem(root);
    }
    if(tick%30===0&&!watchdogPollBusy){
      watchdogPollBusy=true;
      callNetworkStatus().then(function(st){
        if(!rootAlive(root)||currentRoute()!==route||!st||!st.ok)return;
        var combined=Object.assign({},window.dmState||{},st);
        renderHeader(root,combined);
        root.querySelectorAll('[data-dm-dnscrypt-check]').forEach(function(el){el.innerHTML='';el.appendChild(dnscryptAutoCheckBadge(combined));});
        root.querySelectorAll('.dm-watchdog-slot-result').forEach(function(el){
          var result=watchdogSlotResult(st,el.getAttribute('data-dns-slot'),el.getAttribute('data-dns-id'));
          el.innerHTML='';
          if(result)el.appendChild(result);
        });
      }).catch(function(){}).then(function(){watchdogPollBusy=false;});
    }
  },1000);
}
return baseclass.extend({
  load:function(){
    var route=currentRoute(),cached=cachedRouteStatus(route);
    return Promise.resolve(cached||{__dmLoading:true});
  },
  render:function(st){
    var root=E('div',{'class':'dm-wrap'});
    var route=currentRoute();
    root.__dmRoute=route;
    var cached=!!(st&&st.__dmCachedRoute===route);
    state.statusFromCache=cached&&!st.__dmCacheFresh;
    state.statusRefreshAfterRender=cached;
    state.statusError='';
    if(st&&st.__dmCachedRoute){delete st.__dmCachedRoute;delete st.__dmCacheFresh;}
    root.addEventListener('click',function(ev){if(state.statusFromCache){ev.preventDefault();ev.stopPropagation();}},true);
    root.addEventListener('keydown',function(ev){if(state.statusFromCache&&(ev.key==='Enter'||ev.key===' '||/^(INPUT|TEXTAREA|SELECT)$/.test(String(ev.target&&ev.target.tagName||'')))){ev.preventDefault();ev.stopPropagation();}},true);
    root.addEventListener('beforeinput',function(ev){if(state.statusFromCache){ev.preventDefault();ev.stopPropagation();}},true);
    var ids={
      dashboard:['dm-header','dm-overview'],
      doh:['dm-header','dm-doh','dm-profiles','dm-uninstall'],
      slots:['dm-header','dm-slots'],
      devices:['dm-header','dm-devices'],
      network:['dm-header','dm-network'],
      time:['dm-header','dm-time'],
      catalog:['dm-header','dm-catalog'],
      log:['dm-header','dm-log']
    }[route]||['dm-header','dm-overview'];
    ids.forEach(function(id){root.appendChild(E('section',{'id':id}));});
    injectStyle(root);window.dmState=st||{};state.activeTab=route;window.dmCurrentRoot=root;setupTabPrefetch(root);
    if(st&&st.__dmLoading){
      renderHeader(root,cachedHeaderStatus(),'Загружаю данные…');
      var loading=E('div',{'id':'dm-initial-loading'});
      root.appendChild(loading);
      scheduleBackgroundStatus(root,true);
    }else render(root,st||{});
    removeLegacyCbiActions();if(window.setTimeout)window.setTimeout(removeLegacyCbiActions,0);
    if(route==='dashboard'||route==='doh')startAutoStatus(root);else stopAutoStatus();
    if(state.statusRefreshAfterRender){
      state.statusRefreshAfterRender=false;
      scheduleBackgroundStatus(root);
    }
    if(!(st&&st.__dmLoading))scheduleRouteWarmup(root);
    window.setTimeout(function(){if(rootAlive(root))showRecentJob(root);},0);
    if(route==='dashboard')window.setTimeout(function(){watchBackground(root,'update');resumeVersionCheck(root);},0);
    if(route==='doh')window.setTimeout(function(){watchBackground(root,'combined');},0);
    if(route==='catalog')window.setTimeout(function(){resumeCatalogTest(root);resumeDnscryptCatalogLatency(root);},0);
    if(!state.profileResumeStarted&&route==='doh')window.setTimeout(function(){
      if(rootAlive(root))resumeRunningProfile(root);
    },0);
    if(!state.regionalResumeStarted&&route==='doh')window.setTimeout(function(){
      if(rootAlive(root))resumeRegional(root);
    },0);
    if(!state.settingResumeStarted&&(route==='doh'||route==='network'))window.setTimeout(function(){
      if(rootAlive(root))resumeSetting(root);
    },0);
    if(!state.actionResumeStarted)window.setTimeout(function(){
      if(rootAlive(root))resumeAction(root);
    },0);
    return root;
  },
  remove:function(){stopAutoStatus();if(window.dmTabPrefetchCleanup)window.dmTabPrefetchCleanup();}
});
EOF_COMMON
    chmod 0644 "$COMMON_STAGE"
    mv -f "$COMMON_STAGE" "$COMMON_FILE" || {
        rm -f "$COMMON_STAGE" 2>/dev/null || true
        err "Не удалось заменить общий модуль DNS Manager LuCI."
        return 1
    }

    rm -f "$VIEW_DIR/overview.js" 2>/dev/null || true
    for _page in dashboard doh slots devices network time catalog log; do
        _page_stage="/tmp/dns-manager-luci-${_page}.$$"
        rm -f "$_page_stage" 2>/dev/null || true
        cat > "${_page_stage}" <<'EOF_PAGE'
'use strict';
'require view';
'require dns-manager.common as DM';
// DNS Manager LuCI version: 2.78
return view.extend({
  load: DM.load,
  render: DM.render,
  remove: DM.remove
});
EOF_PAGE
        [ -s "$_page_stage" ] || {
            rm -f "$_page_stage" 2>/dev/null || true
            err "Не удалось создать страницу DNS Manager LuCI: ${_page}."
            return 1
        }
        chmod 0644 "$_page_stage"
        mv -f "$_page_stage" "$VIEW_DIR/${_page}.js" || {
            rm -f "$_page_stage" 2>/dev/null || true
            err "Не удалось заменить страницу DNS Manager LuCI: ${_page}."
            return 1
        }
    done
    publish_versioned_assets || return 1
    chmod 0644 "$MENU_FILE" "$ACL_FILE"

    # The current native LuCI page is a JavaScript view and no longer uses
    # the former dns_manager Lua controller. Remove only that DNS Manager-owned
    # controller so an old CBI/redirect route cannot shadow the native view.
    if [ -f /usr/lib/lua/luci/controller/dns_manager.lua ] && grep -q 'module("luci.controller.dns_manager"' /usr/lib/lua/luci/controller/dns_manager.lua 2>/dev/null; then
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
    if [ "${DNS_MANAGER_LUCI_SKIP_RPC_RELOAD:-0}" = 1 ]; then
        # This installer is invoked from the current rpcd request during a
        # self-update. Restart rpcd only after the update response can return.
        # Keeping this here also fixes upgrades from older LuCI versions whose
        # own update_json() did not schedule a restart.
        if [ -x /etc/init.d/rpcd ]; then
            (sleep 2; /etc/init.d/rpcd restart >/dev/null 2>&1 || true) >/dev/null 2>&1 </dev/null &
        fi
    elif [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
        if command -v ubus >/dev/null 2>&1; then
            _rpcd_ok=0
            _rpcd_i=0
            while [ "$_rpcd_i" -lt 10 ]; do
                if ubus -t 5 list dns_manager >/dev/null 2>&1; then
                    _rpcd_ok=1
                    break
                fi
                sleep 1
                _rpcd_i=$((_rpcd_i + 1))
            done
            if [ "$_rpcd_ok" != 1 ]; then
                /etc/init.d/rpcd restart >/dev/null 2>&1 || true
                _rpcd_i=0
                while [ "$_rpcd_i" -lt 15 ]; do
                    if ubus -t 5 list dns_manager >/dev/null 2>&1; then
                        _rpcd_ok=1
                        break
                    fi
                    sleep 1
                    _rpcd_i=$((_rpcd_i + 1))
                done
            fi
            [ "$_rpcd_ok" = 1 ] || say "ПРЕДУПРЕЖДЕНИЕ: rpcd не зарегистрировал DNS Manager. Выполните: /etc/init.d/rpcd restart"
        fi
    fi
    say "DNS Manager LuCI $VERSION обновлён/установлен."
    say "Меню: LuCI → Службы → DNS Manager"
}

uninstall_files() {
    # Refuse to remove a similarly named include if it is not exactly ours.
    if uci -q get firewall.dns_manager_device_dns >/dev/null 2>&1; then
        if [ "$(uci -q get firewall.dns_manager_device_dns 2>/dev/null || true)" != include ] ||
           [ "$(uci -q get firewall.dns_manager_device_dns.type 2>/dev/null || true)" != nftables ] ||
           [ "$(uci -q get firewall.dns_manager_device_dns.path 2>/dev/null || true)" != /etc/dns-manager/device-dns/redirects.nft ] ||
           [ "$(uci -q get firewall.dns_manager_device_dns.position 2>/dev/null || true)" != chain-pre ] ||
           [ "$(uci -q get firewall.dns_manager_device_dns.chain 2>/dev/null || true)" != dstnat_lan ]; then
            err "Найден чужой firewall include с именем dns_manager_device_dns; ничего не удалено."
            return 1
        fi
        uci -q delete firewall.dns_manager_device_dns || return 1
        uci commit firewall || return 1
    fi
    if [ -x /etc/init.d/dns-manager-device-dns ]; then
        /etc/init.d/dns-manager-device-dns stop >/dev/null 2>&1 || true
        /etc/init.d/dns-manager-device-dns disable >/dev/null 2>&1 || true
    fi
    if [ -f /etc/hotplug.d/iface/95-dns-manager-regional ] && grep -Fqx '# DNS_MANAGER_REGIONAL_HOOK=1' /etc/hotplug.d/iface/95-dns-manager-regional; then
        rm -f /etc/hotplug.d/iface/95-dns-manager-regional || return 1
    fi
    if [ -f /etc/init.d/dns-manager-regional ] && grep -Fqx '# DNS_MANAGER_REGIONAL_SERVICE=1' /etc/init.d/dns-manager-regional; then
        /etc/init.d/dns-manager-regional stop >/dev/null 2>&1 || true
        /etc/init.d/dns-manager-regional disable >/dev/null 2>&1 || true
        rm -f /etc/init.d/dns-manager-regional /usr/lib/dns-manager-luci/regional-watch.sh || return 1
    fi
    rm -f /etc/nftables.d/90-dns-manager-device-dns.nft /etc/nftables.d/90-dns-manager-device-dns.nft.tmp.* 2>/dev/null || true
    rm -f /etc/init.d/dns-manager-device-dns /etc/dns-manager/config/device-dns.conf /etc/dns-manager/config/device-dns-default.conf /etc/dns-manager/device-dns/redirects.nft /etc/dns-manager/device-dns/redirects.nft.tmp.* 2>/dev/null || true
    rm -rf /etc/dns-manager/device-dns 2>/dev/null || true
    /etc/init.d/firewall reload >/dev/null 2>&1 || return 1
    rm -f "$RPC_PLUGIN" "$BACKEND_FILE" "$ACL_FILE" "$MENU_FILE" "$VIEW_FILE" 2>/dev/null || true
    rm -rf "$VIEW_DIR" "$RESOURCE_DIR" "$RUNTIME_DIR" "$BACKUP_DIR" 2>/dev/null || true
    rm -f "$STATE_FILE" 2>/dev/null || true
    # the former dns_manager Lua controller. Remove only that DNS Manager-owned
    # controller so an old CBI/redirect route cannot shadow the native view.
    if [ -f /usr/lib/lua/luci/controller/dns_manager.lua ] && grep -q 'module("luci.controller.dns_manager"' /usr/lib/lua/luci/controller/dns_manager.lua 2>/dev/null; then
        rm -f /usr/lib/lua/luci/controller/dns_manager.lua
    fi
    rm -rf /tmp/luci-* /tmp/luci-indexcache* /tmp/luci-modulecache* 2>/dev/null || true
    [ -x /etc/init.d/rpcd ] && /etc/init.d/rpcd reload >/dev/null 2>&1 || true
    say "DNS Manager LuCI удалён. Основной /usr/bin/dns-manager не изменён."
}

case "${1:-install}" in
    install|bootstrap)
        full_install
        ;;
    update)
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
