#!/bin/sh
# DNS Manager LuCI companion
# Version: 0.9.4
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
RUNTIME_UPDATE_STATE="$BACKUP_DIR/update.state"
VERSION_FILE="$BACKUP_DIR/version"
VERSION="0.9.4"

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

    command -v jsonfilter >/dev/null 2>&1 || say "ℹ jsonfilter не найден — используется встроенный обработчик RPC-параметров."
    mkdir -p "$VIEW_DIR" /usr/libexec/rpcd /usr/share/rpcd/acl.d /usr/share/luci/menu.d "$RUNTIME_DIR/checks" "$BACKUP_DIR" "$(dirname "$STATE_FILE")" || return 1

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
        "dns_manager": [ "status", "catalog", "job", "log", "update_check" ]
      }
    },
    "write": {
      "ubus": {
        "dns_manager": [ "set_profile", "set_slot", "set_setting", "test_all", "test_one", "update" ]
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
CONFIG_FILE="/etc/dns-manager/config/manager.conf"
CATALOG_FILE="/etc/dns-manager/config/dns-catalog.conf"
STATE_DIR="/var/run/dns-manager"
PERSIST_STATE_DIR="/etc/dns-manager/state"
RUNTIME_DIR="/var/run/dns-manager-luci"
JOB_DIR="$RUNTIME_DIR/jobs"
CHECK_DIR="$RUNTIME_DIR/checks"
TMP_ROOT="$RUNTIME_DIR/tmp"
UPDATE_STATE="/etc/dns-manager-luci/update.state"
COMPANION_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager-luci.sh"
VERSION_FILE="/etc/dns-manager-luci/version"
VIEW_FILE="/www/luci-static/resources/view/dns_manager/overview.js"
SELF_VERSION="0.9.4"

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
    sed -n 's/^VERSION="\([0-9][0-9.]*\)"$/\1/p' "$MANAGER" 2>/dev/null | head -n1
}

cfg_get() {
    _key="$1"
    [ -r "$CONFIG_FILE" ] || return 0
    awk -v k="$_key" 'index($0,k"=")==1 { v=substr($0,length(k)+2); sub(/^\"/,"",v); sub(/\"$/, "", v); sub(/^\047/,"",v); sub(/\047$/, "", v); print v; exit }' "$CONFIG_FILE" 2>/dev/null
}

catalog_field() {
    _id="$1"; _n="$2"
    [ -r "$CATALOG_FILE" ] || return 1
    awk -F'|' -v id="$_id" -v n="$_n" '$1==id { if (n==2) print $2; else if (n==4) print $4; else if (n==5) print $5; exit }' "$CATALOG_FILE" 2>/dev/null
}

catalog_version() { sed -n 's/^# DNSCATVER=//p' "$CATALOG_FILE" 2>/dev/null | head -n1; }

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

fetch_url() {
    _out="$1"
    rm -f "$_out" 2>/dev/null || true
    _url="${COMPANION_URL}?_dmcb=$(date +%s 2>/dev/null || printf 0)-$$"
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
    [ "$(wc -c < "$_out" 2>/dev/null | tr -d ' ')" -le 250000 ] 2>/dev/null || return 1
    return 0
}

validate_candidate() {
    _f="$1"
    head -n1 "$_f" 2>/dev/null | grep -q '^#!/bin/sh$' || return 1
    grep -Fq '# DNS Manager LuCI companion' "$_f" 2>/dev/null || return 1
    grep -Fq '/usr/libexec/rpcd/dns_manager' "$_f" 2>/dev/null || return 1
    grep -Fq 'admin/services/dns_manager' "$_f" 2>/dev/null || return 1
    grep -Fq '"update_check"' "$_f" 2>/dev/null || return 1
    grep -Fq 'Version:' "$_f" 2>/dev/null || return 1
    sh -n "$_f" >/dev/null 2>&1 || return 1
    return 0
}

update_check_json() {
    _installed="$(read_installed_luci_version)"
    _tmp="$TMP_ROOT/companion-check.$$"
    if ! fetch_url "$_tmp" || ! validate_candidate "$_tmp"; then
        rm -f "$_tmp" 2>/dev/null || true
        printf '{"ok":true,"installed_version":'; json_quote "$_installed"; printf ',"latest_version":"","available":false,"checked_at":%s,"error":' "$(date +%s 2>/dev/null || printf 0)"; json_quote "Не удалось проверить новую версию"; printf '}'
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
    } > "${UPDATE_STATE}.tmp.$$" 2>/dev/null || true
    [ -s "${UPDATE_STATE}.tmp.$$" ] && mv "${UPDATE_STATE}.tmp.$$" "$UPDATE_STATE" 2>/dev/null || rm -f "${UPDATE_STATE}.tmp.$$" 2>/dev/null || true
    rm -f "$_tmp" 2>/dev/null || true
    printf '{"ok":true,"installed_version":'; json_quote "$_installed"; printf ',"latest_version":'; json_quote "$_latest"; printf ',"available":%s,"checked_at":%s}' "$_available" "$_ts"
}

maybe_background_update_check() {
    [ -d "$RUNTIME_DIR" ] || return 0
    _now="$(date +%s 2>/dev/null || printf 0)"
    _last="$(sed -n 's/^checked_at=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"
    case "$_last" in ''|*[!0-9]*) _last=0;; esac
    [ "$_now" -gt 0 ] || return 0
    [ $((_now - _last)) -ge 43200 ] || return 0
    mkdir "$RUNTIME_DIR/update-check.lock" 2>/dev/null || return 0
    (
        trap 'rm -rf "$RUNTIME_DIR/update-check.lock" 2>/dev/null || true' EXIT INT TERM
        update_check_json >/dev/null 2>&1 || true
    ) </dev/null >/dev/null 2>&1 &
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
    printf 'installed=%s\nlatest=%s\navailable=0\nchecked_at=%s\n' "$_after" "$_after" "$(date +%s 2>/dev/null || printf 0)" > "$UPDATE_STATE" 2>/dev/null || true
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

average_selected_ping() {
    _sum=0; _n=0
    for _s in 1 2 3 4 5 6 RU RU_2; do
        _id="$(cfg_get "SLOT_$_s")"
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
    if command -v apk >/dev/null 2>&1; then
        _v="$(apk list --upgradeable "$_pkg" 2>/dev/null | awk -v p="$_pkg" '$1 ~ "^"p"-" {sub("^"p"-","",$1); print $1; exit}')"
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

openwrt_release() { sed -n "s/^DISTRIB_RELEASE='\([^']*\)'.*/\1/p" /etc/openwrt_release 2>/dev/null | head -n1; }

status_json() {
    maybe_background_update_check
    _mv="$(manager_version 2>/dev/null || true)"
    _profile="$(cfg_get DNS_PROFILE)"; [ -n "$_profile" ] || _profile="hybrid"
    _mode="$(cfg_get DNS_SELECTION_MODE)"; [ -n "$_mode" ] || _mode="quick"
    _watchdog="$(cfg_get WATCHDOG_ENABLED)"; [ -n "$_watchdog" ] || _watchdog=0
    _watchdog_interval="$(cfg_get WATCHDOG_INTERVAL)"; [ -n "$_watchdog_interval" ] || _watchdog_interval=90
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
    _force_cfg="$(uci -q get https-dns-proxy.config.force_dns 2>/dev/null || true)"; _external=0
    [ "$_force_cfg" = 1 ] && [ "$_force" != 1 ] && _external=1
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
    _force_ports_norm="$(printf '%s\n' "$_force_ports" | awk '{gsub(/[\"\047,]/," "); for(i=1;i<=NF;i++) print $i}' | sort -n | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
    _force_src_norm="$(printf '%s\n' "$_force_src" | awk '{gsub(/[\"\047,]/," "); for(i=1;i<=NF;i++) print $i}' | sort | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
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
    _luci_checked="$(sed -n 's/^checked_at=//p' "$UPDATE_STATE" 2>/dev/null | head -n1)"

    printf '{"ok":true,"manager_version":'; json_quote "$_mv"; printf ',"luci_version":'; json_quote "$_luciv"; printf ',"luci_latest_version":'; json_quote "$_luci_latest"; printf ',"luci_update_available":%s,"luci_update_checked":%s' "$_luci_avail" "${_luci_checked:-0}"
    printf ',"ipv4":'; json_quote "$_ipv4"; printf ',"ipv6":'; json_quote "$_ipv6"; printf ',"dnsmasq":'; json_quote "$_dnsmasq"; printf ',"doh":'; json_quote "$_doh"; printf ',"firewall":'; json_quote "$_fw"; printf ',"openwrt":'; json_quote "$(openwrt_release)"; printf ',"lan":'; json_quote "$_lan"
    printf ',"profile":'; json_quote "$_profile"; printf ',"profile_mode":'; json_quote "$_mode"; printf ',"watchdog":'; json_quote "$_watchdog"; printf ',"watchdog_service":'; json_quote "$( [ -x /etc/init.d/dns-watchdog ] && /etc/init.d/dns-watchdog running >/dev/null 2>&1 && printf yes || printf no )"; printf ',"watchdog_interval":'; json_quote "$_watchdog_interval"
    printf ',"force":'; json_quote "$_force"; printf ',"force_external":'; json_quote "$_external"; printf ',"force_owner":'; json_quote "$( [ "$_external" = 1 ] && printf external || [ "$_force" = 1 ] && printf manager || printf none )"; printf ',"force_source":'; json_quote "$_force_source"; printf ',"force_notrack":'; json_quote "$_force_notrack"; printf ',"force_update":'; json_quote "$_force_update"; printf ',"force_family":'; json_quote "$_force_family"; printf ',"force_ports":'; json_quote "$_force_ports"; printf ',"force_src":'; json_quote "$_force_src"; printf ',"force_canary_icloud":'; json_quote "$_force_canary_i"; printf ',"force_canary_mozilla":'; json_quote "$_force_canary_m"; printf ',"force_procd_trigger_wan6":'; json_quote "$_force_procd"; printf ',"force_heartbeat_domain":'; json_quote "$_force_heartbeat_domain"; printf ',"force_heartbeat_sleep":'; json_quote "$_force_heartbeat_sleep"; printf ',"force_heartbeat_wait":'; json_quote "$_force_heartbeat_wait"; printf ',"force_user":'; json_quote "$_force_user"; printf ',"force_group":'; json_quote "$_force_group"; printf ',"force_listen":'; json_quote "$_force_listen"; printf ',"force_consistent":%s' "$_force_consistent"; printf ',"mtu":'; json_quote "$_mtu"; printf ',"sysctl":'; json_quote "$_sysctl"; printf ',"sysctl_ext":'; json_quote "$_sysctl_ext"; printf ',"ntp_clients":'; json_quote "$_ntp"; printf ',"dnsmasq_perf":'; json_quote "$_perf"; printf ',"client_fixes":'; json_quote "$_fix"
    printf ',"doh_total":%s,"doh_match":%s,"configured_dns":%s,"average_ping":' "$_doh_total" "$_match" "$_expected"; json_quote "$(average_selected_ping)"; printf ',"last_full_test":'; json_quote "$_last"
    printf ',"hostname":'; json_quote "$_host"; printf ',"uptime":'; json_quote "$_uptime"; printf ',"load1":'; json_quote "$_load"; printf ',"memory_total_kb":%s,"memory_available_kb":%s' "${_mem_t:-0}" "${_mem_a:-0}"
    printf ',"catalog_total":%s,"catalog_version":' "$_cat_total"; json_quote "$(catalog_version)"; printf ',"hdp_version":'; json_quote "$_hdp_installed"; printf ',"hdp_latest_version":'; json_quote "$_hdp_candidate"; printf ',"hdp_update_available":%s' "$_hdp_update"; printf ',"force_status":'; json_quote "$([ "$_external" = 1 ] && printf external || [ "$_force_manager" = 1 ] && printf manager || printf off)"; printf ',"force_owner":'; json_quote "$([ "$_external" = 1 ] && printf 'внешний' || [ "$_force_manager" = 1 ] && printf 'DNS Manager' || printf 'нет')"; printf ',"force_manager":%s,"force_both":%s,"zapret_running":%s' "$_force_manager" "$_force_both" "$_zapret_running"; printf ',"force_source":'; json_quote "$_force_source"; printf ',"slots":['
    _first=1
    for _s in 1 2 3 4 5 6 RU RU_2; do
        _id="$(cfg_get "SLOT_$_s")"; _cat="$(cfg_get "SLOT_${_s}_CAT")"; _port="$(cfg_get "PORT_$_s")"
        [ -n "$_cat" ] || [ -z "$_id" ] || _cat="$(catalog_field "$_id" 2 2>/dev/null || true)"
        _name="$(catalog_field "$_id" 4 2>/dev/null || true)"; [ -n "$_name" ] || _name="Не задан"
        _r="$(result_for_id "$_id" 2>/dev/null || true)"; _ms="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $4;exit}')"; _st="$(printf '%s' "$_r" | awk -F'|' 'NF>=5 {print $5;exit}')"
        [ "$_st" = OK ] || [ "$_st" = FAIL ] || _st=""
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
new_job_id() { printf '%s-%s' "$(date +%s)" "$$"; }
job_write() { _id="$1"; _key="$2"; _value="$3"; mkdir -p "$JOB_DIR/$_id" 2>/dev/null || return 1; printf '%s=%s\n' "$_key" "$_value" >> "$JOB_DIR/$_id/state" 2>/dev/null; }

job_start_test_all() {
    _jid="$(new_job_id)"; mkdir -p "$JOB_DIR/$_jid" 2>/dev/null || { json_error "Не удалось создать задачу"; return; }
    : > "$JOB_DIR/$_jid/state"; printf 'status=running\nstarted=%s\n' "$(date +%s)" > "$JOB_DIR/$_jid/state"
    (
        exec >>"$JOB_DIR/$_jid/output" 2>&1
        trap 'job_write "$_jid" status failed; job_write "$_jid" finished "$(date +%s)"; exit 1' INT TERM
        if load_manager && SILENT_APPLY=1 test_dns_catalog; then
            now="$(date +%s)"; while IFS='|' read -r _id _cat _name _ms _st; do [ -n "$_id" ] && set_check_stamp "$_id" "$now"; done < "$TEST_RESULTS"
            job_write "$_jid" status done; job_write "$_jid" result ok; job_write "$_jid" finished "$now"
        else
            job_write "$_jid" status failed; job_write "$_jid" result fail; job_write "$_jid" finished "$(date +%s)"
        fi
    ) &
    printf '{"ok":true,"job":'; json_quote "$_jid"; printf '}'
}

job_start_test_one() {
    _id="$1"; case "$_id" in ''|*[!A-Za-z0-9_-]*) json_error "Неверный ID DNS"; return;; esac
    _jid="$(new_job_id)"; mkdir -p "$JOB_DIR/$_jid" 2>/dev/null || { json_error "Не удалось создать задачу"; return; }
    : > "$JOB_DIR/$_jid/state"; printf 'status=running\nstarted=%s\n' "$(date +%s)" > "$JOB_DIR/$_jid/state"
    (
        exec >>"$JOB_DIR/$_jid/output" 2>&1
        if load_manager; then
            q="$TMP_ROOT/dns_query.bin"; [ -s "$q" ] || printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$q"
            if acquire_test_lock; then
                if test_one_dns "$_id"; then
                    _tmp="$TMP_ROOT/results.$$"; _stamp="$(date +%s)"; : > "$_tmp"
                    [ -s "$TEST_RESULTS" ] && awk -F'|' -v id="$_id" '$1!=id {print}' "$TEST_RESULTS" > "$_tmp" 2>/dev/null || true
                    cat "$TMP_DIR/t.$_id" >> "$_tmp" 2>/dev/null || true; mv "$_tmp" "$TEST_RESULTS" 2>/dev/null || true
                    save_persistent_test_results >/dev/null 2>&1 || true; set_check_stamp "$_id" "$_stamp"; release_test_lock || true
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
    printf '{"ok":true,"job":'; json_quote "$_jid"; printf ',"status":'; json_quote "$(sed -n 's/^status=//p' "$_d/state" 2>/dev/null | tail -n1)"; printf ',"result":'; json_quote "$(sed -n 's/^result=//p' "$_d/state" 2>/dev/null | tail -n1)"; printf ',"started":'; json_quote "$(sed -n 's/^started=//p' "$_d/state" 2>/dev/null | head -n1)"; printf ',"finished":'; json_quote "$(sed -n 's/^finished=//p' "$_d/state" 2>/dev/null | tail -n1)"; printf ',"output":'; json_quote "$(tail -n 80 "$_d/output" 2>/dev/null || true)"; printf '}'
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

test_json() { case "${RPC_METHOD:-}" in test_all) job_start_test_all;; test_one) job_start_test_one "$(jget id)";; *) json_error "Недопустимый метод проверки";; esac; }

case "${1:-}" in
    list)
        printf '{"status":{},"catalog":{"category":"String","offset":0,"limit":0,"only_ok":0},"update_check":{},"update":{},"set_profile":{"profile":"String"},"set_slot":{"slot":"String","id":"String"},"set_setting":{"name":"String","enabled":0},"test_all":{},"test_one":{"id":"String"},"job":{"id":"String"},"log":{"lines":0}}\n'
        ;;
    call)
        case "${2:-}" in
            status) status_json;;
            catalog) INPUT="$(cat 2>/dev/null || true)"; catalog_json;;
            update_check) update_check_json;;
            update) update_json;;
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

// DNS Manager LuCI version: 0.9.4
var callStatus = rpc.declare({ object:'dns_manager', method:'status', expect:{} });
var callCatalog = rpc.declare({ object:'dns_manager', method:'catalog', params:['category','offset','limit','only_ok'], expect:{} });
var callUpdateCheck = rpc.declare({ object:'dns_manager', method:'update_check', expect:{} });
var callUpdate = rpc.declare({ object:'dns_manager', method:'update', expect:{} });
var callProfile = rpc.declare({ object:'dns_manager', method:'set_profile', params:['profile'], expect:{} });
var callSlot = rpc.declare({ object:'dns_manager', method:'set_slot', params:['slot','id'], expect:{} });
var callSetting = rpc.declare({ object:'dns_manager', method:'set_setting', params:['name','enabled'], expect:{} });
var callTestAll = rpc.declare({ object:'dns_manager', method:'test_all', expect:{} });
var callTestOne = rpc.declare({ object:'dns_manager', method:'test_one', params:['id'], expect:{} });
var callJob = rpc.declare({ object:'dns_manager', method:'job', params:['id'], expect:{} });
var callLog = rpc.declare({ object:'dns_manager', method:'log', params:['lines'], expect:{} });

var PROFILE = [
  ['bypass','Максимальный обход'], ['clean','Максимальная скорость'],
  ['security','Максимальная безопасность'], ['privacy','Максимальная приватность'],
  ['adblock','Блокировка рекламы'], ['all','Выбор по категориям']
];
var CATEGORY = [
  ['all','Все DNS'], ['bypass','Обход блокировок'], ['security','Безопасность'], ['privacy','Приватность'],
  ['adblock','Блокировка рекламы'], ['family','Семейный'], ['clean','Без фильтрации'], ['regional','Региональные']
];
var state = { category:'all', offset:0, limit:18, catalogLoaded:false, advanced:true, logLoaded:false, busy:false, busySetting:'', settingMessage:'', settingMessageType:'', pageNotice:{}, updateKick:false, activeTab:'overview' };

function profileName(p){ var x=PROFILE.filter(function(v){return v[0]===p;})[0]; return x?x[1]:(p||'—'); }
function catName(c){ var x=CATEGORY.filter(function(v){return v[0]===c;})[0]; return x?x[1]:(c||'—'); }
function ping(v){ return v && /^\d+$/.test(String(v)) ? v+' мс' : '—'; }
function uptime(sec){ var n=Number(sec||0); if(!isFinite(n)||n<=0)return '—'; var d=Math.floor(n/86400); n%=86400; var h=Math.floor(n/3600); n%=3600; var m=Math.floor(n/60); return (d?d+' дн ':'')+(d||h?h+' ч ':'')+m+' мин'; }
function memory(total,avail){ var t=Number(total||0),a=Number(avail||0); if(!t)return '—'; return Math.max(0,Math.round((t-a)/1024))+' / '+Math.round(t/1024)+' МБ'; }
function badge(kind,text){ return E('span',{'class':'dm-badge '+kind},[E('span',{'class':'dm-dot'}),text]); }
function btn(label,cls,fn,extra){ var a={'class':'cbi-button '+(cls||''),'click':fn}; Object.keys(extra||{}).forEach(function(k){ if(k==='disabled'){ if(extra[k]) a.disabled=true; } else { a[k]=extra[k]; } }); return E('button',a,label); }
function row(label,node){ return E('div',{'class':'dm-row'},[E('span',{'class':'dm-label'},label),E('span',{'class':'dm-row-value'},node)]); }
function card(title,children,cls){ return E('div',{'class':'dm-card '+(cls||'')},[E('h3',{},title)].concat(children||[])); }
function forceMode(st){ return st.force==='1' ? 'auto' : 'off'; }
function forceModeLabel(m){ return m==='auto' ? 'Авто (рекомендуется)' : 'Не перехватывать'; }
function yes(v){ return v===1 || v==='1' || v===true; }
function dateText(v){ if(!v || !/^\d+$/.test(String(v))) return '—'; try { return new Date(Number(v)*1000).toLocaleString(); } catch(e){ return '—'; } }
function shortVal(v){ return (v===undefined || v===null || v==='') ? '—' : String(v); }
function stripAnsi(s){ return String(s||'').replace(/\x1B(?:[@-_]|\[[0-?]*[ -\/]*[@-~])/g,'').replace(/\r/g,''); }
function stateBadge(status){ var s=String(status||'').toUpperCase(); if(s==='OK')return badge('dm-ok','доступен'); if(s==='RUNNING')return badge('dm-warn','выполняется'); if(s==='FAIL'||s==='FAILED')return badge('dm-bad','ошибка'); return badge('dm-off','нет данных'); }
function settingName(n){ var m={watchdog:'Автопроверка DNS',mtu:'Настройка MTU и MSS',sysctl:'Оптимизация TCP и соединений',sysctl_ext:'Расширенные параметры сети',ntp_clients:'Время для устройств сети',dnsmasq_perf:'Кэш DNS',client_fixes:'Исправления для устройств'}; return m[n]||n; }

function injectStyle(root){
  var css = ''+
  '.dm-wrap{display:flex;flex-direction:column;gap:12px;max-width:1100px;padding-bottom:28px}'+
  '.dm-header{display:flex;align-items:center;gap:9px;flex-wrap:wrap}.dm-header h2{margin:0;font-size:22px;font-weight:700}.dm-header-v{font-size:13px;opacity:.55}.dm-header-actions{display:flex;gap:7px;margin-left:auto;flex-wrap:wrap}.dm-header-actions .cbi-button{padding:5px 11px;font-size:12.5px}'+
  '.dm-card{min-width:0;box-sizing:border-box;background:var(--background-color-medium,#fff);border:1px solid rgba(0,0,0,.08);border-radius:11px;padding:15px 18px;box-shadow:0 1px 3px rgba(0,0,0,.04),0 1px 2px rgba(0,0,0,.03);overflow-wrap:break-word}.dm-card:hover{box-shadow:0 2px 7px rgba(0,0,0,.06)}'+
  'html.dm-theme-dark .dm-card{background:#1c2128;border-color:rgba(255,255,255,.10);box-shadow:0 1px 3px rgba(0,0,0,.22)}'+
  '.dm-card h3{margin:0 0 10px;font-size:15px;font-weight:600;display:flex;align-items:center;gap:7px}.dm-row{display:flex;align-items:center;gap:10px;margin:6px 0;font-size:13px;flex-wrap:wrap}.dm-label{opacity:.65;flex-shrink:0}.dm-row-value{overflow-wrap:anywhere}'+
  '.dm-badge{display:inline-flex;align-items:center;gap:6px;padding:3px 10px;border-radius:999px;font-size:12px;font-weight:600;white-space:nowrap}.dm-dot{width:8px;height:8px;border-radius:50%;display:inline-block;flex-shrink:0}'+
  '.dm-ok{background:rgba(46,160,67,.12);color:#1a7f37}.dm-ok .dm-dot{background:#1a7f37}.dm-bad{background:rgba(207,34,46,.10);color:#cf222e}.dm-bad .dm-dot{background:#cf222e}.dm-warn{background:rgba(191,135,0,.12);color:#9a6700}.dm-warn .dm-dot{background:#9a6700}.dm-off{background:rgba(110,118,129,.12);color:#57606a}.dm-off .dm-dot{background:#57606a}'+
  '.dm-grid2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.dm-grid3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:8px}.dm-grid4{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:8px}'+
  '.dm-actions{display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:11px}.dm-actions .cbi-button{margin:0;padding:5px 11px;font-size:12.5px}'+
  '.dm-hint{font-size:12.5px;opacity:.68;line-height:1.5;margin:0 0 8px}.dm-mini{font-size:11px;opacity:.62}.dm-meta{font-size:11px;line-height:1.45;opacity:.66}.dm-update{padding:8px 10px;border-radius:8px;background:rgba(26,127,55,.08);border:1px solid rgba(26,127,55,.18);font-size:12.5px;display:flex;gap:8px;align-items:center;flex-wrap:wrap}'+
  '.dm-seg{display:flex;flex-wrap:wrap;gap:6px;margin:5px 0}.dm-seg .cbi-button{padding:5px 11px;border-radius:7px;font-size:12.5px;font-weight:600}.dm-seg .active{background:#1a7f37;color:#fff;border-color:#1a7f37}'+
  '.dm-force-note{font-size:12px;line-height:1.55;opacity:.72}.dm-inline-msg{display:block;margin:8px 0 0;padding:7px 10px;border-radius:7px;font-size:12px;line-height:1.4}.dm-inline-msg.info{background:rgba(9,105,218,.08);border:1px solid rgba(9,105,218,.16)}.dm-inline-msg.ok{background:rgba(26,127,55,.08);border:1px solid rgba(26,127,55,.16)}.dm-inline-msg.error{background:rgba(207,34,46,.08);border:1px solid rgba(207,34,46,.16)}.dm-setting{padding:11px 12px}.dm-setting-title{font-size:13px;font-weight:600}.dm-setting-desc{font-size:11.5px;line-height:1.45;opacity:.68;margin-top:3px}.dm-setting-line{display:flex;align-items:center;justify-content:space-between;gap:10px}.dm-setting-actions{display:flex;align-items:center;gap:7px;flex-shrink:0}.dm-setting-actions .cbi-button{padding:4px 9px;font-size:12px}.dm-setting-saving{opacity:.7}.dm-force-external{padding:8px 10px;border-radius:8px;background:rgba(191,135,0,.10);border:1px solid rgba(191,135,0,.22);font-size:12.5px;line-height:1.5;margin-top:8px}'+
  '.dm-doh-list{display:flex;flex-direction:column}.dm-doh-row{display:grid;grid-template-columns:140px minmax(180px,1fr) 80px 100px;gap:10px;align-items:center;padding:7px 0;border-top:1px solid rgba(0,0,0,.07);font-size:13px}.dm-doh-row:first-child{border-top:0}.dm-doh-name{font-weight:600}.dm-doh-url{overflow-wrap:anywhere;opacity:.88}.dm-doh-port,.dm-doh-ping{font-size:12px;opacity:.7;white-space:nowrap}'+
  '.dm-slot-table{display:flex;flex-direction:column}.dm-slot-row{display:grid;grid-template-columns:55px minmax(160px,1fr) 115px 65px 100px auto;gap:9px;align-items:center;padding:7px 0;border-top:1px solid rgba(0,0,0,.07);font-size:13px}.dm-slot-row:first-child{border-top:0}.dm-slot-id{font-weight:700;opacity:.62}.dm-slot-name{font-weight:600;overflow-wrap:anywhere}.dm-slot-endpoint,.dm-slot-ping{font-size:12px;opacity:.72;white-space:nowrap}.dm-inline{display:flex;gap:6px;justify-content:flex-end}.dm-inline .cbi-button{padding:4px 9px;font-size:12px}'+
  '.dm-catalog{display:grid;grid-template-columns:repeat(3,minmax(210px,1fr));gap:8px;margin-top:8px}.dm-catalog-item{padding:10px 11px}.dm-catalog-item h4{margin:0 0 4px;font-size:13px}.dm-page{display:flex;justify-content:center;align-items:center;gap:7px;margin-top:9px}.dm-log{white-space:pre-wrap;max-height:360px;overflow:auto;font:11px/1.45 monospace;padding:10px;background:#111820;color:#dbe4ec;border-radius:8px;margin-top:8px}'+
  '.dm-page-nav{position:sticky;top:0;z-index:20;padding:7px 0;background:var(--background-color-base,#fff);border-bottom:1px solid rgba(0,0,0,.08)}.dm-page-nav::before,.dm-page-nav::after{content:'';position:absolute;left:0;right:0;height:7px;background:var(--background-color-base,#fff);pointer-events:none}.dm-page-nav::before{top:-7px}.dm-page-nav::after{bottom:-7px}.dm-page-tabs{display:flex;align-items:stretch;gap:4px;overflow-x:auto;scrollbar-width:none;padding:0 2px}.dm-page-tabs::-webkit-scrollbar{display:none}.dm-page-tab{flex:0 0 auto;padding:7px 12px!important;border-radius:8px 8px 0 0!important;font-size:12.5px!important;font-weight:600!important;border:1px solid transparent!important;background:transparent!important;box-shadow:none!important}.dm-page-tab:hover{background:rgba(0,0,0,.05)!important}.dm-page-tab.active{background:var(--background-color-medium,#fff)!important;border-color:rgba(0,0,0,.12)!important;border-bottom-color:var(--background-color-medium,#fff)!important}.dm-page-nav-title{display:none}.dm-wrap>section{scroll-margin-top:58px}'+
  '.dm-section-title{font-size:12px;letter-spacing:.02em;text-transform:none;opacity:.62;margin:3px 0 0;padding:0 2px}'+
  '@media(max-width:850px){.dm-grid2{grid-template-columns:1fr}.dm-grid4{grid-template-columns:repeat(2,minmax(0,1fr))}.dm-doh-row{grid-template-columns:120px minmax(140px,1fr) 70px}.dm-doh-ping{display:none}.dm-slot-row{grid-template-columns:48px minmax(130px,1fr) 100px 90px auto}.dm-slot-ping{display:none}.dm-catalog{grid-template-columns:repeat(2,minmax(0,1fr))}}'+
  '@media(max-width:560px){.dm-grid3,.dm-grid4,.dm-catalog{grid-template-columns:1fr}.dm-header-actions{margin-left:0}.dm-doh-row{grid-template-columns:1fr auto}.dm-doh-url{grid-column:1/3}.dm-doh-port{grid-column:1}.dm-slot-row{grid-template-columns:40px minmax(0,1fr) auto}.dm-slot-endpoint{display:none}.dm-slot-state{display:none}.dm-inline{grid-column:2/4;justify-content:flex-start}}';
  root.appendChild(E('style',{},css));
}

function rootAlive(root){return !!root&&!!root.isConnected;}
function globalUpdateNotice(msg,type){var id='dm-global-update-notice',old=document.getElementById(id);if(old)old.remove();if(!msg)return;var n=E('div',{'id':id,'class':'dm-inline-msg '+(type||'info')},msg);n.style.position='fixed';n.style.left='50%';n.style.top='18px';n.style.transform='translateX(-50%)';n.style.zIndex='99999';n.style.maxWidth='min(760px,calc(100vw - 32px))';n.style.boxShadow='0 6px 24px rgba(0,0,0,.18)';document.body.appendChild(n);}
function renderHeader(root,st){
  var e=root.querySelector('#dm-header');if(!e)return;e.innerHTML='';
  e.appendChild(E('div',{'class':'dm-header'},[
    E('h2',{},'DNS Manager'),E('span',{'class':'dm-header-v'},'LuCI v'+shortVal(st.luci_version)),
    E('div',{'class':'dm-header-actions'},[btn('Обновить состояние','cbi-button-neutral',function(){refresh(root,true);})])
  ]));
}
function renderPageNav(root){
  var e=root.querySelector('#dm-page-nav');if(!e)return;e.innerHTML='';
  var tabs=[['overview','Обзор'],['doh','DNS'],['slots','Серверы'],['profiles','Профили'],['settings','Настройки'],['job','Проверка'],['catalog','Каталог'],['log','Журнал']];
  var nav=E('nav',{'class':'dm-page-nav'});
  var bar=E('div',{'class':'dm-page-tabs'});
  tabs.forEach(function(x){
    bar.appendChild(btn(x[1],(state.activeTab===x[0]?'dm-page-tab active':'dm-page-tab'),function(){
      state.activeTab=x[0];
      renderPageNav(root);
      var t=root.querySelector('#dm-'+x[0]);
      if(t){try{t.scrollIntoView({behavior:'smooth',block:'start'});}catch(e){t.scrollIntoView();}}
    }));
  });
  nav.appendChild(bar);
  e.appendChild(nav);
}

function renderOverview(root,st){
  var e=root.querySelector('#dm-overview');if(!e)return;e.innerHTML='';
  var doh = st.doh==='yes' ? badge('dm-ok','включён') : Number(st.doh_total||0)>0 ? badge('dm-bad','остановлен') : badge('dm-off','не установлен');
  var force = yes(st.force_both) ? badge('dm-warn','DNS Manager + внешний') : st.force_owner==='external' ? badge('dm-warn','внешний · '+shortVal(st.force_source)) : yes(st.force_manager) ? badge('dm-ok','DNS Manager') : badge('dm-off','выключен');
  var wd = yes(st.watchdog) ? (st.watchdog_service==='yes' ? badge('dm-ok','включён') : badge('dm-warn','включён')) : badge('dm-off','выключен');
  var stateCard=card('Состояние',[
    row('Профиль',profileName(st.profile)),
    row('Защищённый DNS (DoH)',doh),
    row('DNS',String(st.configured_dns||0)+' · '+String(st.doh_match||0)+' DoH'),
    row('Принудительный DNS',force),
    row('Автопроверка DNS',wd)
  ]);
  var sysCard=card('Система',[
    row('Устройство',shortVal(st.hostname)),
    row('OpenWrt',shortVal(st.openwrt)),
    row('Время работы',uptime(st.uptime)),
    row('Нагрузка',shortVal(st.load1)),
    row('RAM',memory(st.memory_total_kb,st.memory_available_kb)),
    row('LAN',shortVal(st.lan))
  ]);
  var verCard=card('Версии',[
    row('DNS Manager',shortVal(st.manager_version)),
    row('LuCI',shortVal(st.luci_version)),
    row('https-dns-proxy',st.hdp_update_available ? badge('dm-warn',shortVal(st.hdp_version)+' → '+shortVal(st.hdp_latest_version)) : badge('dm-ok',shortVal(st.hdp_version)+' · актуальна')),
    row('Каталог DNS',shortVal(st.catalog_version)+' · '+String(st.catalog_total||0)),
    row('Последняя проверка',dateText(st.last_full_test)),E('div',{'class':'dm-actions'},[btn('Проверить обновления','cbi-button-neutral',function(){checkUpdate(root);}),yes(st.luci_update_available)?btn('Обновить LuCI','cbi-button-positive',function(){doUpdate(root);}):E('span',{},'')]),E('div',{'id':'dm-overview-msg'})
  ]);
  e.appendChild(E('div',{'class':'dm-grid3'},[stateCard,sysCard,verCard]));
}

function resolverRows(st){
  var out=[],seen=0;
  (st.slots||[]).forEach(function(d){if(!d.id)return;seen++;out.push(E('div',{'class':'dm-doh-row'},[
    E('span',{'class':'dm-doh-slot'},d.slot||'—'),E('span',{'class':'dm-doh-name'},d.name||d.id),E('span',{'class':'dm-doh-url'},d.url||'—'),
    E('span',{'class':'dm-doh-port'},d.port?'порт '+d.port:'—'),E('span',{'class':'dm-doh-ping'},ping(d.ping)),E('span',{'class':'dm-doh-state'},stateBadge(d.status))
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
  if(yes(st.zapret_running)){
    ch.push(E('div',{'class':'dm-force-external'},'Zapret: процесс запущен. Это не означает автоматически, что его forced-DNS включён; выше показан фактически обнаруженный путь DNS-перехвата.'));
  }
  ch.push(E('div',{'class':'dm-force-note'},'Схема совместимости: 53/853 · LAN · notrack_dns=1 · dnsmasq_config_update=- · force_ip_family=auto · procd_trigger_wan6=0.'));
  ch.push(E('div',{'class':'dm-actions'},[
    btn('Показать параметры','cbi-button-neutral',function(){openForceDetails(root,st);}),
    btn('Обновить состояние','cbi-button-neutral',function(){refresh(root,true);})
  ]));
  if(state.pageNotice.doh)ch.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.doh));
  e.appendChild(card('DNS over HTTPS',ch));
}

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
    E('span',{'class':'dm-slot-endpoint'},d.port?'127.0.0.1:'+d.port:'—'),E('span',{'class':'dm-slot-ping'},ping(d.ping)),E('span',{'class':'dm-slot-state'},stateBadge(d.status)),
    E('span',{'class':'dm-inline'},[btn('Выбрать','cbi-button-neutral',function(){openSlotPicker(d.slot,root);}),btn('Проверить','cbi-button-neutral',function(){testOne(d.id,root);})])
  ]));});
  if(!rows.length)rows.push(E('div',{'class':'dm-hint'},'DNS пока не настроены.'));
  var sch=[E('div',{'class':'dm-slot-table'},rows)];if(state.pageNotice.slots)sch.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.slots));e.appendChild(card('Выбранные DNS',sch));
}

function settingCard(x,st){
  var en=yes(st[x[0]]),busy=state.busySetting===x[0];
  return E('div',{'class':'dm-card dm-setting '+(busy?'dm-setting-saving':'')},[
    E('div',{'class':'dm-setting-line'},[
      E('div',{},[E('div',{'class':'dm-setting-title'},x[1]),E('div',{'class':'dm-setting-desc'},x[2])]),
      E('div',{'class':'dm-setting-actions'},[badge(busy?'dm-warn':(en?'dm-ok':'dm-off'),busy?'изменение':(en?'включено':'выключено')),btn(busy?'Сохраняю…':(en?'Выключить':'Включить'),busy?'cbi-button-neutral':(en?'cbi-button-remove':'cbi-button-add'),function(){setSetting(x[0],en?0:1,root);},{disabled:!!state.busy})])
    ])
  ]);
}
function renderSettings(root,st){
  var e=root.querySelector('#dm-settings');if(!e)return;e.innerHTML='';
  var body=[];
  if(state.settingMessage)body.push(E('div',{'class':'dm-inline-msg '+(state.settingMessageType||'info')},state.settingMessage));
  body.push(E('div',{'class':'dm-hint'},'Каждый пункт меняет одну настройку. Результат показывается здесь, без всплывающих сообщений.'));
  var groups=[
    ['Проверка DNS',[['watchdog','Автопроверка DNS','Проверяет доступность DNS через заданный интервал.']]],
    ['Сеть',[['mtu','Настройка MTU и MSS','Изменяет размеры пакетов и TCP-сегментов для соединения.'],['sysctl','Оптимизация TCP и соединений','Изменяет параметры TCP и таблицы соединений.'],['sysctl_ext','Расширенные параметры сети','Добавляет дополнительные системные параметры сети.']]],
    ['Производительность',[['dnsmasq_perf','Кэш DNS','Сохраняет ответы DNS для повторных запросов.']]],
    ['Устройства сети',[['ntp_clients','Время для устройств сети','Передаёт устройствам адрес роутера как сервер времени по DHCP.'],['client_fixes','Исправления для устройств','Добавляет совместимые настройки для отдельных устройств и сервисов.']]]
  ];
  groups.forEach(function(g){
    body.push(E('div',{'class':'dm-section-title'},g[0]));
    var grid=E('div',{'class':'dm-grid2'});
    g[1].forEach(function(x){grid.appendChild(settingCard(x,st));});
    body.push(grid);
  });
  e.appendChild(card('Настройки',body));
}

function renderCatalog(root){
  var e=root.querySelector('#dm-catalog');if(!e)return;e.innerHTML='';
  var ch=[E('div',{'class':'dm-row'},[
    E('span',{'class':'dm-label'},'Каталог DNS'),btn(state.catalogLoaded?'Скрыть':'Открыть','cbi-button-neutral',function(){state.catalogLoaded=!state.catalogLoaded;renderCatalog(root);if(state.catalogLoaded)loadCatalog(root);})
  ]),E('div',{'class':'dm-mini'},'Каталог открывается только по кнопке.')];
  if(state.catalogLoaded) ch.push(E('div',{'id':'dm-cat-body'}));
  if(state.pageNotice.catalog)ch.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.catalog));e.appendChild(card('Каталог DNS',ch));
}

function renderCatalogBody(root,data){
  var b=root.querySelector('#dm-cat-body');if(!b)return;b.innerHTML='';
  var f=E('div',{'class':'dm-seg'});CATEGORY.forEach(function(c){f.appendChild(btn(c[1],c[0]===state.category?'active cbi-button':'cbi-button',function(){state.category=c[0];state.offset=0;loadCatalog(root);}));});b.appendChild(f);
  b.appendChild(E('div',{'class':'dm-mini'},'Показано '+(data.servers||[]).length+' из '+(data.total||0)));
  var g=E('div',{'class':'dm-catalog'});
  (data.servers||[]).forEach(function(d){g.appendChild(E('div',{'class':'dm-card dm-catalog-item'},[
    E('h4',{},d.name||d.id),E('div',{'class':'dm-meta'},catName(d.category)+' · '+ping(d.ping)),
    E('div',{'class':'dm-actions'},[btn('Проверить','cbi-button-neutral',function(){testOne(d.id,root);}),btn('Назначить','cbi-button-action',function(){openAssign(d.id,d.category,root);})])
  ]));});
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
  ch.push(E('div',{'class':'dm-actions'},[btn(state.logLoaded?'Скрыть журнал':'Показать журнал','cbi-button-neutral',function(){if(state.logLoaded){state.logLoaded=false;renderLog(root);}else showLog(root);})]));
  if(state.logLoaded)ch.push(E('pre',{'class':'dm-log'},stripAnsi(state.logText||'')));
  e.appendChild(card('Журнал',ch));
}

function renderJob(root,job){
  var e=root.querySelector('#dm-job');e.innerHTML='';state.jobRunning=true;
  var out=E('pre',{'class':'dm-log'},'Подключение к проверке…');
  var stateLine=E('div',{'class':'dm-row'},[E('span',{'class':'dm-label'},'Состояние'),badge('dm-warn','выполняется')]);
  e.appendChild(card('Проверка DNS',[E('p',{'class':'dm-hint'},'Проверка выполняется отдельно от журнала.'),stateLine,out]));
  var ticks=0;
  function poll(){
    callJob(job).then(function(j){j=j||{};out.textContent=stripAnsi(j.output||'Ожидание результата…');var st=String(j.status||'running').toUpperCase();stateLine.replaceChild(stateBadge(st),stateLine.lastChild);
      if(st==='DONE'||st==='FAILED'){state.jobRunning=false;state.pageNotice.job=st==='DONE'?'Проверка завершена.':'Проверка завершилась с ошибкой.';setTimeout(function(){refresh(root,true);},250);return;}
      if(ticks++>180){state.jobRunning=false;state.pageNotice.job='Проверка длится дольше обычного. Состояние можно обновить позже.';refresh(root,true);return;}
      setTimeout(poll,900);
    }).catch(function(){if(ticks++>8){state.jobRunning=false;state.pageNotice.job='Не удалось получить состояние проверки.';refresh(root,true);return;}setTimeout(poll,1000);});
  }
  poll();
}
function renderJobIdle(root,st){
  var e=root.querySelector('#dm-job');e.innerHTML='';
  var ch=[E('p',{'class':'dm-hint'},'Полная проверка проверяет каталог DNS. Для отдельного сервера используйте кнопку «Проверить» в списке.'),E('div',{'class':'dm-actions'},[btn('Проверить все DNS','cbi-button-action',function(){testAll(root);},{disabled:!!state.busy}),E('span',{'class':'dm-mini'},'Последняя проверка: '+(st.last_full_test?dateText(st.last_full_test):'нет'))])];
  if(state.pageNotice.job)ch.push(E('div',{'class':'dm-inline-msg info'},state.pageNotice.job));
  e.appendChild(card('Проверка DNS',ch));
}
function render(root,st){
  renderHeader(root,st);renderPageNav(root);renderOverview(root,st);renderDoH(root,st);renderSlots(root,st);renderProfiles(root,st);renderSettings(root,st);renderCatalog(root);renderLog(root);if(!state.jobRunning)renderJobIdle(root,st);
  if(!state.updateKick && Number(st.luci_update_checked||0)===0){state.updateKick=true;setTimeout(function(){refresh(root,true);},2200);}
}
function refresh(root,keepPosition){if(!rootAlive(root))return Promise.resolve();var y=keepPosition?window.scrollY:0;return callStatus().then(function(st){if(!rootAlive(root))return;window.dmState=st||{};render(root,st||{});if(state.catalogLoaded&&rootAlive(root))loadCatalog(root);if(keepPosition&&rootAlive(root))setTimeout(function(){if(rootAlive(root))window.scrollTo(0,y);},0);}).catch(function(){});}
function toast(msg,type){}
function checkUpdate(root){globalUpdateNotice('Проверяю обновления LuCI…','info');state.pageNotice.overview='Проверяю обновления LuCI…';if(rootAlive(root))renderOverview(root,window.dmState||{});return callUpdateCheck().then(function(r){var ok=!!(r&&r.ok);var msg=!ok?'Проверка обновлений не выполнена.':(yes(r.available)?'Доступна новая версия LuCI: v'+r.latest_version:'Установлена актуальная версия LuCI.');state.pageNotice.overview=msg;globalUpdateNotice(msg,ok?'ok':'error');return refresh(root,true);}).catch(function(){var msg='Проверка обновлений не выполнена.';state.pageNotice.overview=msg;globalUpdateNotice(msg,'error');return refresh(root,true);});}
function doUpdate(root){if(state.busy)return;var v=(window.dmState&&window.dmState.luci_latest_version)||'новой версии';if(!confirm('Обновить только LuCI до v'+v+'? DNS Manager и настройки не изменятся.'))return;state.busy=true;state.pageNotice.overview='Обновляю LuCI…';globalUpdateNotice('Обновляю LuCI до v'+v+'…','info');if(rootAlive(root))renderOverview(root,window.dmState||{});callUpdate().then(function(r){state.busy=false;if(r&&r.ok&&r.updated){var msg='LuCI обновлена до v'+r.version+'. Перезагружаю страницу…';state.pageNotice.overview=msg;globalUpdateNotice(msg,'ok');if(rootAlive(root))renderOverview(root,window.dmState||{});setTimeout(function(){location.reload();},1600);}else{var msg=(r&&r.error)||'LuCI не удалось обновить.';state.pageNotice.overview=msg;globalUpdateNotice(msg,'error');if(rootAlive(root))renderOverview(root,window.dmState||{});}}).catch(function(){state.busy=false;var msg='Не удалось выполнить RPC-обновление LuCI. Попробуйте ещё раз; причина будет показана в сообщении RPC.';state.pageNotice.overview=msg;globalUpdateNotice(msg,'error');if(rootAlive(root))renderOverview(root,window.dmState||{});});}
function applyProfile(name,root){if(state.busy)return;state.busy=true;state.pageNotice.profiles='Применяю профиль «'+profileName(name)+'»…';renderProfiles(root,window.dmState||{});callProfile(name).then(function(r){state.busy=false;state.pageNotice.profiles=(r&&r.ok)?'Профиль «'+profileName(name)+'» применён.':(r&&r.error)||'Профиль не удалось применить.';refresh(root,true);}).catch(function(){state.busy=false;state.pageNotice.profiles='Профиль не удалось применить.';refresh(root,true);});}
function setSetting(name,en,root){if(state.busy)return;state.busy=true;state.busySetting=name;state.settingMessage='Изменение «'+settingName(name)+'»…';state.settingMessageType='info';renderSettings(root,window.dmState||{});callSetting(name,en).then(function(r){state.busy=false;state.busySetting='';state.settingMessage=(r&&r.ok)?('Настройка «'+settingName(name)+'»: '+(en?'включена.':'выключена.')):((r&&r.error)||'Настройку не удалось изменить.');state.settingMessageType=(r&&r.ok)?'ok':'error';refresh(root,true);}).catch(function(){state.busy=false;state.busySetting='';state.settingMessage='Настройку не удалось изменить.';state.settingMessageType='error';refresh(root,true);});}
function setForceMode(mode,root){if(state.busy)return;if(window.dmState&&window.dmState.force_owner==='external'){state.pageNotice.doh='Внешний перехват DNS обнаружен. DNS Manager его не изменяет.';renderDoH(root,window.dmState);return;}var en=mode==='auto'?1:0;state.busy=true;state.busySetting='force';state.pageNotice.doh='Изменение перехвата DNS…';renderDoH(root,window.dmState||{});callSetting('force',en).then(function(r){state.busy=false;state.busySetting='';state.pageNotice.doh=(r&&r.ok)?(en?'Перехват DNS включён.':'Перехват DNS выключен.'):(r&&r.error)||'Не удалось изменить перехват DNS.';refresh(root,true);}).catch(function(){state.busy=false;state.busySetting='';state.pageNotice.doh='Не удалось изменить перехват DNS.';refresh(root,true);});}
function assign(id,slot,root){if(state.busy)return;state.busy=true;state.pageNotice.slots='Назначаю DNS в слот '+slot+'…';renderSlots(root,window.dmState||{});callSlot(slot,id).then(function(r){state.busy=false;state.pageNotice.slots=(r&&r.ok)?'DNS назначен в слот '+slot+'.':(r&&r.error)||'DNS не удалось применить.';refresh(root,true);}).catch(function(){state.busy=false;state.pageNotice.slots='DNS не удалось применить.';refresh(root,true);});}
function openAssign(id,cat,root){var slots=cat==='regional'?['RU','RU_2']:['1','2','3','4','5','6'];var box=E('div',{});slots.forEach(function(slot){box.appendChild(btn(slot,'cbi-button-neutral',function(){ui.hideModal();assign(id,slot,root);}));});ui.showModal('Назначить DNS',[box,E('div',{'class':'right'},[btn('Отмена','cbi-button-negative',ui.hideModal)])]);}
function openSlotPicker(slot,root){if(state.busy)return;var regional=slot==='RU'||slot==='RU_2';callCatalog(regional?'regional':'all',0,48,0).then(function(d){var rows=(d.servers||[]).filter(function(x){return regional?x.category==='regional':x.category!=='regional';});var sel=E('select',{'class':'cbi-input-select'});rows.forEach(function(x){sel.appendChild(E('option',{value:x.id},x.name+' — '+catName(x.category)));});ui.showModal('Выбор DNS для '+slot,[sel,E('div',{'class':'right'},[btn('Отмена','cbi-button-negative',ui.hideModal),btn('Применить','cbi-button-apply',function(){var id=sel.value;ui.hideModal();assign(id,slot,root);})])]);}).catch(function(){state.pageNotice.slots='Не удалось открыть список DNS.';renderSlots(root,window.dmState||{});});}
function testAll(root){if(state.jobRunning||state.busy)return;callTestAll().then(function(r){if(r&&r.ok)renderJob(root,r.job);else{state.pageNotice.job=(r&&r.error)||'Не удалось запустить проверку.';renderJobIdle(root,window.dmState||{});}}).catch(function(){state.pageNotice.job='Не удалось запустить проверку.';renderJobIdle(root,window.dmState||{});});}
function testOne(id,root){if(state.jobRunning||state.busy)return;callTestOne(id).then(function(r){if(r&&r.ok)renderJob(root,r.job);else{state.pageNotice.job=(r&&r.error)||'Не удалось запустить проверку.';renderJobIdle(root,window.dmState||{});}}).catch(function(){state.pageNotice.job='Не удалось запустить проверку.';renderJobIdle(root,window.dmState||{});});}
function loadCatalog(root){return callCatalog(state.category,state.offset,state.limit,0).then(function(d){window.dmCatalog=d||{};renderCatalog(root);renderCatalogBody(root,window.dmCatalog);}).catch(function(){state.pageNotice.catalog='Не удалось загрузить каталог DNS.';renderCatalog(root);});}
function showLog(root){callLog(160).then(function(r){state.logLoaded=true;state.logText=stripAnsi(r.log||'');renderLog(root);}).catch(function(){state.pageNotice.log='Не удалось загрузить журнал.';renderLog(root);});}

return view.extend({
  load:function(){return callStatus().then(function(st){return st||{};});},
  render:function(st){var root=E('div',{'class':'dm-wrap'});['dm-header','dm-page-nav','dm-overview','dm-doh','dm-slots','dm-profiles','dm-settings','dm-job','dm-catalog','dm-log'].forEach(function(id){root.appendChild(E('section',{'id':id}));});injectStyle(root);window.dmState=st||{};render(root,st||{});return root;}
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
