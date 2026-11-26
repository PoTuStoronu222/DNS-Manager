#!/bin/sh
# Experimental RPC backend for the single-process DNSCrypt engine.
# Methods that still depend on individual https-dns-proxy instances are
# rejected until they have an engine-aware implementation.
LEGACY=${DNS_MANAGER_LEGACY_BACKEND:-/usr/lib/dns-manager-luci/backend.sh}
MANAGER=${DNS_MANAGER_MANAGER:-/usr/bin/dns-manager}
HELPERS=${DNS_MANAGER_DNSCRYPT_HELPERS:-/usr/lib/dns-manager-luci/dnscrypt}
CONFIG_DIR=${DNS_MANAGER_DNSCRYPT_CONFIG_DIR:-/etc/dns-manager/config}
NATIVE_CATALOG="$CONFIG_DIR/dnscrypt-native-catalog.conf"
[ -r "$NATIVE_CATALOG" ] || NATIVE_CATALOG="$HELPERS/dns-manager-dnscrypt-catalog.conf"
JOB_DIR=${DNS_MANAGER_DNSCRYPT_JOB_DIR:-/var/run/dns-manager-luci/jobs}
RUNTIME_DIR=${DNS_MANAGER_DNSCRYPT_RUNTIME_DIR:-/var/run/dns-manager-luci}
STATE_FILE="$CONFIG_DIR/dnscrypt-profile.state"
ENGINE_FILE=${DNS_MANAGER_DNSCRYPT_ENGINE_FILE:-$CONFIG_DIR/dnscrypt-engine}
SERVICE=dns-manager-dnscrypt-profile
RESET_SERVICE=dns-manager-dnscrypt-reset
SWITCH_SERVICE=dns-manager-engine-switch
DNSCRYPT_INIT=${DNS_MANAGER_DNSCRYPT_INIT:-/etc/init.d/dnscrypt-proxy}
HDP_INIT=${DNS_MANAGER_HDP_INIT:-/etc/init.d/https-dns-proxy}
umask 077

error() { printf '{"ok":false,"error":"%s"}\n' "$1"; }
valid_profile() (
 case "$1" in
 options:*)
    options=${1#options:}; proto=${options%%:*}; options=${options#*:}
    strategy=${options%%:*}; target=${options#*:}
    case "$proto" in mixed|native) ;; *) return 1;; esac
    case "$strategy" in wp2|p2|p3|p4|p5|p6|ph|first|random) ;; *) return 1;; esac
    set -- "$target";;
 esac
 case "$1" in
 auto:clean|catalog-on|catalog-off) return 0;;
 bypass|clean|security|privacy|adblock|family|all|dnssec|default) return 0;;
 server:*) id=${1#server:}; case "$id" in ''|*[!A-Za-z0-9_-]*) return 1;; esac;;
 pool:*) ids=${1#pool:}; case "$ids" in ''|,*|*,|*,,*|*[!A-Za-z0-9_,-]*) return 1;; esac
 set -f; IFS=,; set -- $ids; [ "$#" -le 6 ] || return 1; seen=,
 for id do case "$seen" in *",$id,"*) return 1;; esac; seen="$seen$id,"; done;;
 *) return 1;; esac
)
# A manually selected server must come from the current pool, never from RPC input.
dnscrypt_pool_records() {
    [ -r "$STATE_FILE" ] || return 1
    if grep -q '^available=' "$STATE_FILE"; then sed -n 's/^available=//p' "$STATE_FILE"
    else sed -n 's/^server=//p' "$STATE_FILE"; fi
}
engine_selected() { [ -r "$ENGINE_FILE" ] && [ "$(cat "$ENGINE_FILE" 2>/dev/null)" = dnscrypt-proxy2 ]; }
dnscrypt_configured_strategy() {
    strategy=$(sed -n 's/^strategy=//p' "$STATE_FILE" 2>/dev/null | head -n1)
    if [ -z "$strategy" ] && engine_selected; then
        strategy=$(awk -F "'" '/^[[:space:]]*lb_strategy[[:space:]]*=/ {print $2; exit}' "${DNS_MANAGER_DNSCRYPT_CONFIG:-/etc/dnscrypt-proxy2/dnscrypt-proxy.toml}" 2>/dev/null)
    fi
    case "$strategy" in wp2|p2|p3|p4|p5|p6|ph|first|random) printf '%s\n' "$strategy";; *) printf '%s\n' wp2;; esac
}
hdp_active() { [ -x "$HDP_INIT" ] && { "$HDP_INIT" enabled >/dev/null 2>&1 || "$HDP_INIT" running >/dev/null 2>&1; }; }
load_manager_functions() {
    local manager_src
    mkdir -p "$RUNTIME_DIR" || return 1
    manager_src=$(mktemp "$RUNTIME_DIR/dnscrypt-manager.XXXXXX") || return 1
    if ! sed '/^case "${1:-}" in$/,$d' "$MANAGER" > "$manager_src" || ! . "$manager_src"; then
        rm -f "$manager_src"
        return 1
    fi
    rm -f "$manager_src"
}
disable_legacy_watchdog() {
    . "$HELPERS/dns-manager-watchdog-common.sh" || return 1
    dns_manager_stop_watchdog || return 1
    if [ "${WATCHDOG_ENABLED:-0}" != 0 ] || [ "${WATCHDOG_AUTOREPLACE:-0}" != 0 ]; then
        WATCHDOG_ENABLED=0
        WATCHDOG_AUTOREPLACE=0
        save_config || return 1
    fi
}
dnscrypt_tuning_apply() (
    name=$1 enabled=$2
    key="dns-manager.global.$name"
    previous=$(uci -q get "$key" 2>/dev/null || :)
    [ -r "$STATE_FILE" ] || return 1
    urls=$(mktemp "$RUNTIME_DIR/dnscrypt-tuning.XXXXXX") || return 1
    trap 'rm -f "$urls"' EXIT HUP INT TERM
    sed -n 's/^server=[^|]*|//p' "$STATE_FILE" > "$urls"
    [ -s "$urls" ] || return 1
    DNS_MANAGER_PROTOCOL=$(sed -n 's/^protocol=//p' "$STATE_FILE" | head -n1)
    DNS_MANAGER_AUTO_CATALOG=$(sed -n 's/^auto_catalog=//p' "$STATE_FILE" | head -n1)
    DNS_MANAGER_SOURCE_CACHE="$CONFIG_DIR/dnscrypt-sources"
    DNS_MANAGER_LB_STRATEGY=$(dnscrypt_configured_strategy)
    case "$DNS_MANAGER_PROTOCOL" in native) ;; *) DNS_MANAGER_PROTOCOL=mixed;; esac
    case "$DNS_MANAGER_LB_STRATEGY" in wp2|p2|p3|p4|p5|p6|ph|first|random) ;; *) DNS_MANAGER_LB_STRATEGY=wp2;; esac
    export DNS_MANAGER_PROTOCOL DNS_MANAGER_LB_STRATEGY DNS_MANAGER_AUTO_CATALOG DNS_MANAGER_SOURCE_CACHE
    uci set "$key=$enabled" && uci commit dns-manager || return 1
    if sh "$HELPERS/dns-manager-dnscrypt-pool-apply.sh" 5053 "$BOOTSTRAP_DNS" < "$urls"; then
        return 0
    fi
    if [ -n "$previous" ]; then uci set "$key=$previous"; else uci -q delete "$key"; fi
    uci commit dns-manager
    return 1
)

dnscrypt_setting_valid() {
    case "$1:$2" in
        watchdog:0|watchdog:1|force:0|force:1|browser_dns:0|browser_dns:1|dc_cache:0|dc_cache:1|dc_force_tcp:0|dc_force_tcp:1|dc_block_ipv6:0|dc_block_ipv6:1|dc_block_unqualified:0|dc_block_unqualified:1|dc_block_undelegated:0|dc_block_undelegated:1|dc_query_log:0|dc_query_log:1|dc_cache_size:1000|dc_cache_size:4096|dc_cache_size:10000|dc_cache_ttl:0|dc_cache_ttl:300|dc_cache_ttl:900|dc_cache_ttl:1800) return 0;;
        *) return 1;;
    esac
}

dnscrypt_set_setting() {
    input=$(cat)
    name=$(printf '%s' "$input" | jsonfilter -e '@.name' 2>/dev/null)
    enabled=$(printf '%s' "$input" | jsonfilter -e '@.enabled' 2>/dev/null)
    dnscrypt_setting_valid "$name" "$enabled" || { error 'Неверное значение настройки'; return; }
    load_manager_functions && load_config && acquire_mutation_lock || { error 'Не удалось применить настройку DNS'; return; }
    rc=0
    if [ "${name#dc_}" != "$name" ]; then
        dnscrypt_tuning_apply "$name" "$enabled" >/dev/null 2>&1 || rc=$?
    elif [ "$name" = browser_dns ]; then
        set_browser_dns_hint "$enabled" >/dev/null 2>&1 || rc=$?
    elif [ "$name" = force ]; then
        dnscrypt_set_force "$enabled" >/dev/null 2>&1 || rc=$?
    else
        watchdog_apply_toggle "$enabled" >/dev/null 2>&1 || rc=$?
    fi
    release_mutation_lock
    [ "$rc" -eq 0 ] || { error "${DNSCRYPT_FORCE_ERROR:-Не удалось применить настройку DNS}"; return; }
    printf '{"ok":true}\n'
}

# The setting worker is managed by procd and survives the RPC connection.
dnscrypt_setting_worker() {
    printf 'pid=%s\n' "$$" >> "$JOB_DIR/setting/state"
    token=$(awk '{print $22}' "/proc/$$/stat" 2>/dev/null || :)
    [ -z "$token" ] || printf 'pid_start=%s\n' "$token" >> "$JOB_DIR/setting/state"
    dnscrypt_set_setting < "$JOB_DIR/setting/input" > "$JOB_DIR/setting/output" 2>&1
    rm -f "$JOB_DIR/setting/input"
    if grep -q '"ok"[[:space:]]*:[[:space:]]*true' "$JOB_DIR/setting/output"; then result=ok; status=done; rc=0; else result=fail; status=failed; rc=1; fi
    printf 'result=%s\nstatus=%s\nfinished=%s\n' "$result" "$status" "$(date +%s)" >> "$JOB_DIR/setting/state"
    printf '\n__DONE__ %s\n' "$rc" >> "$JOB_DIR/setting/output"
}
dnscrypt_setting_start() {
    input=$(cat)
    name=$(printf '%s' "$input" | jsonfilter -e '@.name' 2>/dev/null)
    enabled=$(printf '%s' "$input" | jsonfilter -e '@.enabled' 2>/dev/null)
    dnscrypt_setting_valid "$name" "$enabled" || { error 'Неверная настройка'; return; }
    mkdir -p "$JOB_DIR/setting" "$RUNTIME_DIR" || { error 'Не удалось подготовить задачу'; return; }
    exec 9>"$RUNTIME_DIR/setting-start.lock" || { error 'Не удалось подготовить блокировку'; return; }
    flock -n 9 || { error 'Другая настройка уже запускается'; return; }
    service=dns-manager-dnscrypt-setting
    reply=$(ubus -t 5 call service list "{\"name\":\"$service\"}" 2>/dev/null) || { error 'Служба задач недоступна'; return; }
    if printf '%s' "$reply" | grep -q '"running"[[:space:]]*:[[:space:]]*true'; then error 'Другая настройка уже применяется'; return; fi
    ubus -t 5 call service delete "{\"name\":\"$service\"}" >/dev/null 2>&1 || :
    umask 077
    printf '%s' "$input" > "$JOB_DIR/setting/input" || { error 'Не удалось сохранить запрос'; return; }
    : > "$JOB_DIR/setting/output"
    printf 'status=running\nstarted=%s\nmode=setting\nname=%s\nenabled=%s\n' "$(date +%s)" "$name" "$enabled" > "$JOB_DIR/setting/state"
    request="{\"name\":\"$service\",\"instances\":{\"main\":{\"command\":[\"/bin/sh\",\"/usr/lib/dns-manager-luci/backend-dnscrypt.sh\",\"setting_worker\"]}}}"
    if ! ubus -t 5 call service set "$request" >/dev/null 2>&1; then
        rm -f "$JOB_DIR/setting/input"
        printf 'result=fail\nstatus=failed\nfinished=%s\n' "$(date +%s)" >> "$JOB_DIR/setting/state"
        error 'Не удалось запустить настройку'; return
    fi
    printf '{"ok":true,"job":"setting"}\n'
}

# Keep the LAN redirect in an owned UCI section so firewall reloads retain it.
dnscrypt_set_force() {
    local enabled current owner lan_ip
    enabled=$1
    DNSCRYPT_FORCE_ERROR='Не удалось применить правило принудительного DNS.'
    current=$(uci -q get firewall.dns_forced || :)
    owner=$(uci -q get firewall.dns_forced.name || :)
    [ -z "$current" ] || { [ "$current" = redirect ] && [ "$owner" = Force-DNS-DNSCrypt ]; } || { DNSCRYPT_FORCE_ERROR='Раздел firewall.dns_forced занят другим правилом.'; return 1; }
    [ -z "$(uci -q changes firewall)" ] || { DNSCRYPT_FORCE_ERROR='Сначала примените несохранённые изменения межсетевого экрана в LuCI.'; return 1; }
    if [ "$enabled" = 1 ]; then
        refresh_runtime_capabilities >/dev/null 2>&1 || return 1
        detect_steer_dns_path >/dev/null 2>&1 || return 1
        # A second redirect would compete with Steer's own LAN DNS hook.
        [ "${STEER_DNS_ACTIVE:-0}" != 1 ] || { DNSCRYPT_FORCE_ERROR='Перехват DNS уже выполняет Steer. Второе правило DNS Manager не добавлено.'; return 1; }
        lan_ip=$(uci -q get network.lan.ipaddr | sed 's-/.*$--')
        case "$lan_ip" in ''|*[!0-9.]*) DNSCRYPT_FORCE_ERROR='Не найден IPv4-адрес LAN в настройках сети.'; return 1;; esac
        uci -q delete firewall.dns_forced || :
        uci set firewall.dns_forced=redirect &&
        uci set firewall.dns_forced.name=Force-DNS-DNSCrypt &&
        uci set firewall.dns_forced.src=lan &&
        uci set firewall.dns_forced.src_dport=53 &&
        uci set firewall.dns_forced.dest=lan &&
        uci set "firewall.dns_forced.dest_ip=$lan_ip" &&
        uci set firewall.dns_forced.dest_port=53 &&
        uci set 'firewall.dns_forced.proto=tcp udp' &&
        uci set firewall.dns_forced.target=DNAT || return 1
    elif [ -n "$current" ]; then
        uci -q delete firewall.dns_forced || return 1
    else
        return 0
    fi
    uci commit firewall || { DNSCRYPT_FORCE_ERROR='Не удалось сохранить правило межсетевого экрана.'; return 1; }
    /etc/init.d/firewall reload || { DNSCRYPT_FORCE_ERROR='Правило сохранено, но межсетевой экран не удалось перезагрузить.'; return 1; }
}
job_write() { printf '%s=%s\n' "$1" "$2" >> "$JOB_DIR/profile/state"; }
action_write() { printf '%s=%s\n' "$1" "$2" >> "$JOB_DIR/action/state"; }

switch_start() {
    input=$(cat)
    target=$(printf '%s' "$input" | jsonfilter -e '@.target_engine' 2>/dev/null || true)
    case "$target" in https-dns-proxy|dnscrypt-proxy2) ;; *) error 'Неверный DNS-движок'; return;; esac
    [ -x "$HELPERS/dns-manager-engine-switch.sh" ] || { error 'Файл переключения отсутствует'; return; }
    mkdir -p "$JOB_DIR/engine" "$RUNTIME_DIR" || { error 'Не удалось подготовить задачу'; return; }
    exec 9>"$RUNTIME_DIR/engine-switch-start.lock" || { error 'Не удалось подготовить блокировку'; return; }
    flock -n 9 || { error 'Переключение уже запускается'; return; }
    reply=$(ubus -t 5 call service list "{\"name\":\"$SWITCH_SERVICE\"}" 2>/dev/null) || { error 'Служба задач недоступна'; return; }
    case "$reply" in \{*\}) ;; *) error 'Некорректный ответ службы задач'; return;; esac
    if printf '%s\n' "$reply" | grep -q '"running"[[:space:]]*:[[:space:]]*true'; then
        error 'Переключение уже выполняется'; return
    fi
    ubus -t 5 call service delete "{\"name\":\"$SWITCH_SERVICE\"}" >/dev/null 2>&1 || true
    # A package installation may take longer than a normal action. The job
    # reader must not terminate a live package manager on the action timeout.
    printf 'status=running\nstarted=%s\nmode=update\nname=switch_engine\n' "$(date +%s)" > "$JOB_DIR/engine/state"
    : > "$JOB_DIR/engine/output"
    request="{\"name\":\"$SWITCH_SERVICE\",\"instances\":{\"main\":{\"command\":[\"/bin/sh\",\"/usr/lib/dns-manager-luci/dnscrypt/dns-manager-engine-switch.sh\",\"$target\"]}}}"
    if ! ubus -t 5 call service set "$request" >/dev/null 2>&1; then
        printf 'result=fail\nstatus=failed\nfinished=%s\n' "$(date +%s)" >> "$JOB_DIR/engine/state"
        error 'Не удалось запустить переключение'; return
    fi
    printf '{"ok":true,"job":"engine"}\n'
}

profile_worker() {
    goal=$1
    valid_profile "$goal" || exit 1
    DNS_MANAGER_PROTOCOL=mixed
    DNS_MANAGER_LB_STRATEGY=$(dnscrypt_configured_strategy)
    case "$goal" in
        options:*)
            opts=${goal#options:}; DNS_MANAGER_PROTOCOL=${opts%%:*}; opts=${opts#*:}
            DNS_MANAGER_LB_STRATEGY=${opts%%:*}; goal=${opts#*:};;
    esac
    DNS_MANAGER_AUTO_CATALOG=0
    catalog_toggle=0
    case "$goal" in
        auto:clean) DNS_MANAGER_AUTO_CATALOG=1; goal=clean;;
        catalog-on) catalog_toggle=1; DNS_MANAGER_AUTO_CATALOG=1; goal=clean;;
        catalog-off) catalog_toggle=1; goal=clean;;
    esac
    DNS_MANAGER_SOURCE_CACHE="$CONFIG_DIR/dnscrypt-sources"
    export DNS_MANAGER_PROTOCOL DNS_MANAGER_LB_STRATEGY DNS_MANAGER_AUTO_CATALOG DNS_MANAGER_SOURCE_CACHE
    job_write pid "$$"
    token=$(awk '{print $22}' "/proc/$$/stat" 2>/dev/null || true)
    [ -z "$token" ] || job_write pid_start "$token"
    exec >>"$JOB_DIR/profile/output" 2>&1
    if ! engine_selected; then
        printf '%s\n' 'Выбран другой DNS-движок.'
        job_write result fail; job_write status failed; job_write finished "$(date +%s)"
        exit 1
    fi
    load_manager_functions || exit 1
    rc=1
    if preflight_readonly >/dev/null 2>&1 && init_dirs >/dev/null 2>&1 &&
       load_config >/dev/null 2>&1 && acquire_mutation_lock; then
        if ! engine_selected; then
            printf '%s\n' 'DNS-движок изменился до начала применения.'
            release_mutation_lock
            job_write result fail; job_write status failed; job_write finished "$(date +%s)"
            exit 1
        fi
        if hdp_active; then
            printf '%s\n' 'https-dns-proxy ещё работает или включён в автозапуске.'
            release_mutation_lock
            job_write result fail; job_write status failed; job_write finished "$(date +%s)"
            exit 1
        fi
        if [ "$catalog_toggle" = 1 ]; then
            if [ "$(sed -n 's/^profile=//p' "$STATE_FILE" 2>/dev/null | head -n1)" != clean ] || ! dnscrypt_pool_records | grep -q .; then
                printf '%s\n' 'Для автоподбора сначала примените профиль «Без фильтрации».'
                release_mutation_lock
                job_write result fail; job_write status failed; job_write finished "$(date +%s)"
                exit 1
            fi
            DNS_MANAGER_PROTOCOL=$(sed -n 's/^protocol=//p' "$STATE_FILE" | head -n1)
            case "$DNS_MANAGER_PROTOCOL" in native|mixed) ;; *) DNS_MANAGER_PROTOCOL=mixed;; esac
            DNS_MANAGER_LB_STRATEGY=$(dnscrypt_configured_strategy)
            export DNS_MANAGER_PROTOCOL DNS_MANAGER_LB_STRATEGY
        fi
        restore_persistent_test_results >/dev/null 2>&1 || true
        refresh_runtime_capabilities >/dev/null 2>&1 || true
        if [ -r "$HELPERS/dns-manager-dnscrypt-profile.sh" ] &&
           [ -r "$HELPERS/dns-manager-dnscrypt-profile-apply.sh" ]; then
            . "$HELPERS/dns-manager-dnscrypt-profile.sh"
            . "$HELPERS/dns-manager-dnscrypt-profile-apply.sh"
            records=''; state_tmp=''
            if mkdir -p "$CONFIG_DIR" && records=$(mktemp "$CONFIG_DIR/.dnscrypt-profile.XXXXXX") &&
               state_tmp=$(mktemp "$CONFIG_DIR/.dnscrypt-state.XXXXXX"); then
                if [ "$catalog_toggle" = 1 ]; then printf '%s\n' 'Переключаю режим выбора DNSCrypt.'; else printf '%s\n' 'Проверяю DNS и применяю профиль.'; fi
                if (
                    if [ "$catalog_toggle" = 1 ]; then
                        dnscrypt_select_profile() { dnscrypt_pool_records; }
                    elif [ "$goal" = default ]; then
                        dnscrypt_select_profile() {
                            if [ "$DNS_MANAGER_PROTOCOL" = native ]; then
                                awk -F'|' '$1=="native_adguard_unfiltered" || $1=="native_quad9_unfiltered" {print $1 "|" $5; count++} END {if (count != 2) exit 1}' "$NATIVE_CATALOG"
                            else
                                printf '%s\n' 'cloudflare_clean|https://cloudflare-dns.com/dns-query' 'google_clean|https://dns.google/dns-query'
                            fi
                        }
                    else
                        case "$goal" in pool:*)
 dnscrypt_select_profile() (
 set -f; IFS=,; set -- ${goal#pool:}
 for chosen do
 url=$(awk -F '|' -v id="$chosen" '$1==id {print $5; exit}' "$NATIVE_CATALOG" 2>/dev/null)
 [ -n "$url" ] || url=$(normalize_url "$(dns_url "$chosen")")
 case "$url" in https://*|sdns://*) ;; *) return 1;; esac
 case "$url" in *'|'*|*[![:graph:]]*) return 1;; esac
 printf '%s|%s\n' "$chosen" "$url"
 done
 ) ;;
 server:*)
                            chosen=${goal#server:}
                            dnscrypt_select_profile() {
                                dnscrypt_pool_records | awk -F '|' -v id="$chosen" '$1 == id {print; found=1; exit} END {if (!found) exit 1}'
                            } ;;
                        esac
                    fi
                    DNS_MANAGER_KEEP_DNSMASQ=$catalog_toggle DNS_MANAGER_NO_UPDATE=1 SILENT_APPLY=1 dnscrypt_apply_profile_pool "$goal" 5053 "$BOOTSTRAP_DNS"
                ) > "$records"; then
                    state_profile=$goal
                    case "$goal" in default|server:*|pool:*) state_profile=none;; esac
                    if "$DNSCRYPT_INIT" enable &&
                       { printf 'profile=%s\nprotocol=%s\nstrategy=%s\n' "$state_profile" "$DNS_MANAGER_PROTOCOL" "$DNS_MANAGER_LB_STRATEGY";
                         [ "$DNS_MANAGER_AUTO_CATALOG" != 1 ] || printf 'auto_catalog=1\n';
                         case "$goal" in server:*) printf 'selected=%s\n' "${goal#server:}"; dnscrypt_pool_records | sed 's/^/available=/';; esac
                         sed 's/^/server=/' "$records"; } > "$state_tmp" &&
                       chmod 0600 "$state_tmp" && mv -f "$state_tmp" "$STATE_FILE"; then
                        rc=0
                    else
                        printf '%s\n' 'Не удалось включить автозапуск или сохранить профиль. Восстанавливаю стандартный DNS.'
                        if sh "$HELPERS/dns-manager-dnscrypt-dnsmasq.sh" restore 5053; then
                            rm -f "$STATE_FILE"
                            "$DNSCRYPT_INIT" stop >/dev/null 2>&1 || true
                            "$DNSCRYPT_INIT" disable >/dev/null 2>&1 || true
                        else
                            printf '%s\n' 'Не удалось полностью восстановить стандартный DNS.'
                        fi
                    fi
                fi
            else
                printf '%s\n' 'Не удалось подготовить файлы профиля.'
            fi
            [ -z "$records" ] || rm -f "$records"
            [ -z "$state_tmp" ] || rm -f "$state_tmp"
        else
            printf '%s\n' 'Файлы профиля DNSCrypt отсутствуют.'
        fi
        release_mutation_lock
    fi
    now=$(date +%s)
    if [ "$rc" = 0 ]; then job_write result ok; job_write status done
    else job_write result fail; job_write status failed; fi
    job_write finished "$now"
    exit "$rc"
}

profile_start() {
    input=$(cat)
    engine_selected || { error 'Выбран другой DNS-движок'; return; }
    goal=$(printf '%s' "$input" | jsonfilter -e '@.profile' 2>/dev/null || true)
    valid_profile "$goal" || { error 'Неверный профиль'; return; }
    mkdir -p "$JOB_DIR/profile" "$RUNTIME_DIR" || { error 'Не удалось подготовить задачу'; return; }
    lock="$RUNTIME_DIR/dnscrypt-profile-start.lock"
    exec 9>"$lock" || { error 'Не удалось подготовить блокировку'; return; }
    flock -n 9 || { error 'Профиль уже запускается'; return; }
    reply=$(ubus -t 5 call service list "{\"name\":\"$SERVICE\"}" 2>/dev/null) || {
        error 'Служба задач недоступна'; return
    }
    case "$reply" in \{*\}) ;; *) error 'Некорректный ответ службы задач'; return;; esac
    if printf '%s\n' "$reply" | grep -q '"running"[[:space:]]*:[[:space:]]*true'; then
        error 'Профиль уже применяется'; return
    fi
    ubus -t 5 call service delete "{\"name\":\"$SERVICE\"}" >/dev/null 2>&1 || true
    printf 'status=running\nstarted=%s\nmode=profile\nprofile=%s\n' "$(date +%s)" "$goal" > "$JOB_DIR/profile/state"
    : > "$JOB_DIR/profile/output"
    request="{\"name\":\"$SERVICE\",\"instances\":{\"main\":{\"command\":[\"/bin/sh\",\"/usr/lib/dns-manager-luci/backend-dnscrypt.sh\",\"worker\",\"$goal\"]}}}"
    if ! ubus -t 5 call service set "$request" >/dev/null 2>&1; then
        job_write result fail; job_write status failed; job_write finished "$(date +%s)"
        error 'Не удалось запустить задачу профиля'; return
    fi
    printf '{"ok":true,"job":"profile"}\n'
}

reset_worker() {
    action_write pid "$$"
    token=$(awk '{print $22}' "/proc/$$/stat" 2>/dev/null || true)
    [ -z "$token" ] || action_write pid_start "$token"
    rc=1
    if load_manager_functions; then
        if engine_selected && preflight_readonly >/dev/null 2>&1 && init_dirs >/dev/null 2>&1 &&
           load_config >/dev/null 2>&1 && acquire_mutation_lock; then
            : > "$RUNTIME_DIR/dnscrypt-reset.log"
            if engine_selected && ! hdp_active && disable_legacy_watchdog &&
               sh "$HELPERS/dns-manager-device-detach.sh" >> "$RUNTIME_DIR/dnscrypt-reset.log" 2>&1 &&
               sh "$HELPERS/dns-manager-dnscrypt-dnsmasq.sh" restore 5053 >> "$RUNTIME_DIR/dnscrypt-reset.log" 2>&1; then
                # The profile is no longer active once dnsmasq is restored,
                # even if disabling the proxy service fails afterward.
                if rm -f "$STATE_FILE" &&
                   sh "$HELPERS/dns-manager-engine-services.sh" quiesce dnscrypt-proxy2 >> "$RUNTIME_DIR/dnscrypt-reset.log" 2>&1; then
                    uci -q delete dns-manager.global.dnscrypt_regional_mode || :
                    uci -q delete dns-manager.global.dnscrypt_regional_ips || :
                    if uci commit dns-manager; then rc=0; fi
                    /etc/init.d/dns-manager-regional restart >/dev/null 2>&1 || :
                fi
            fi
            release_mutation_lock
        fi
    fi
    if [ "$rc" = 0 ]; then
        printf '{"ok":true}\n' > "$JOB_DIR/action/output"
        action_write result ok; action_write status done
    else
        printf '{"ok":false,"error":"Не удалось восстановить стандартный DNS; проверьте состояние служб и UCI."}\n' > "$JOB_DIR/action/output"
        action_write result fail; action_write status failed
    fi
    action_write finished "$(date +%s)"
    exit "$rc"
}

reset_start() {
    cat >/dev/null
    engine_selected || { error 'Выбран другой DNS-движок'; return; }
    mkdir -p "$JOB_DIR/action" "$RUNTIME_DIR" || { error 'Не удалось подготовить задачу'; return; }
    exec 9>"$RUNTIME_DIR/dnscrypt-reset-start.lock" || { error 'Не удалось подготовить блокировку'; return; }
    flock -n 9 || { error 'Восстановление уже запускается'; return; }
    reply=$(ubus -t 5 call service list "{\"name\":\"$RESET_SERVICE\"}" 2>/dev/null) || { error 'Служба задач недоступна'; return; }
    case "$reply" in \{*\}) ;; *) error 'Некорректный ответ службы задач'; return;; esac
    if printf '%s\n' "$reply" | grep -q '"running"[[:space:]]*:[[:space:]]*true'; then
        error 'Восстановление уже выполняется'; return
    fi
    ubus -t 5 call service delete "{\"name\":\"$RESET_SERVICE\"}" >/dev/null 2>&1 || true
    printf 'status=running\nstarted=%s\nmode=action\nname=reset_dns\n' "$(date +%s)" > "$JOB_DIR/action/state"
    : > "$JOB_DIR/action/output"
    request="{\"name\":\"$RESET_SERVICE\",\"instances\":{\"main\":{\"command\":[\"/bin/sh\",\"/usr/lib/dns-manager-luci/backend-dnscrypt.sh\",\"reset_worker\"]}}}"
    if ! ubus -t 5 call service set "$request" >/dev/null 2>&1; then
        action_write result fail; action_write status failed; action_write finished "$(date +%s)"
        error 'Не удалось запустить восстановление'; return
    fi
    printf '{"ok":true,"job":"action"}\n'
}

dnscrypt_native_dnssec_probe() (
    probe_url=$1
    probe_dir=$(mktemp -d "$RUNTIME_DIR/dnssec-probe.XXXXXX") || return 1
    probe_pid=''
    trap '[ -z "$probe_pid" ] || { kill "$probe_pid" 2>/dev/null || :; wait "$probe_pid" 2>/dev/null || :; }; rm -rf "$probe_dir"' EXIT
    trap 'exit 1' HUP INT TERM
    probe_offset=$(printf '%s' "$probe_url" | sha256sum | cut -c1-6)
    probe_offset=$((0x$probe_offset % 12000))
    probe_port=$((49152 + ($$ % 12000 + probe_offset) % 12000))
    sh "$HELPERS/dns-manager-dnscrypt-config.sh" "$probe_port" "$probe_url" "$BOOTSTRAP_DNS" > "$probe_dir/config" || return 1
    awk 'NR==1 {print; print "use_syslog = false"; next} {if ($0 == "cache = true") $0 = "cache = false"; print}' "$probe_dir/config" > "$probe_dir/config-test" || return 1
    dnscrypt-proxy -config "$probe_dir/config-test" -netprobe-timeout 5 > "$probe_dir/log" 2>&1 &
    probe_pid=$!
    probe_wait=0
    while [ "$probe_wait" -lt 15 ] && kill -0 "$probe_pid" 2>/dev/null; do
        if grep -q 'Server with the lowest initial latency:' "$probe_dir/log"; then
            dnssec_probe_local "$probe_port"
            return $?
        fi
        sleep 1
        probe_wait=$((probe_wait + 1))
    done
    return 1
)

dnscrypt_catalog_snapshot() (
    probe_scope=${1:-all}
    probe_ids=${2:-}
    load_manager_functions || exit 1
    probe=''; dir=''
    cleanup_catalog_probe() {
        if [ -n "$probe" ]; then kill "$probe" 2>/dev/null || :; wait "$probe" 2>/dev/null || :; fi
        [ -z "$dir" ] || rm -rf "$dir"
        case "${TMP_DIR:-}" in /tmp/dnsmgr.*) rm -rf "$TMP_DIR";; esac
    }
    trap cleanup_catalog_probe EXIT
    trap 'exit 1' HUP INT TERM
    load_config || exit 1
    [ -r "$DNS_CATALOG" ] || { echo 'Каталог DNS недоступен.' >&2; exit 1; }
    command -v dnscrypt-proxy >/dev/null 2>&1 || { echo 'Программа dnscrypt-proxy не найдена.' >&2; exit 1; }
    dir=$(mktemp -d "$RUNTIME_DIR/catalog-probe.XXXXXX") || { echo 'Не удалось создать временный каталог проверки.' >&2; exit 1; }
    catalog_hash=$(sha256sum "$DNS_CATALOG")
    custom_hash=$(sha256sum "$CUSTOM_DNS_CATALOG" 2>/dev/null || :)
    native_hash=$(sha256sum "$NATIVE_CATALOG" 2>/dev/null || :)
    awk -F'|' 'NF >= 5 && $1 !~ /^#/ && $1 ~ /^[A-Za-z0-9_-]+$/ && $5 ~ /^https:\/\// {gsub(/[\r\n]/, " ", $4); print $1 "|" $5 "|" $4}' "$DNS_CATALOG" > "$dir/source"
    if [ -r "$CUSTOM_DNS_CATALOG" ]; then
        awk -F'|' 'NF >= 5 && $1 !~ /^#/ && $1 ~ /^[A-Za-z0-9_-]+$/ && $5 ~ /^https:\/\// {gsub(/[\r\n]/, " ", $4); print $1 "|" $5 "|" $4}' "$CUSTOM_DNS_CATALOG" >> "$dir/source"
    fi
    if [ "$probe_scope" = all ]; then
        mv "$dir/source" "$dir/doh"
    else
        : > "$dir/doh"
        : > "$dir/source"
    fi
    native_catalog="$NATIVE_CATALOG"
    if [ -r "$native_catalog" ]; then
        awk -F'|' -v scope="$probe_scope" 'NF >= 5 && $1 !~ /^#/ && $1 ~ /^[A-Za-z0-9_-]+$/ && $5 ~ /^sdns:\/\// && (scope == "all" || scope == "native" || (scope == "dnssec" && ($2 == "clean" || $2 == "privacy")) || $2 == scope) {print $1 "|" $5 "|" $4}' "$native_catalog" >> "$dir/source"
    fi
    if [ -n "$probe_ids" ]; then
        [ -r "$probe_ids" ] || exit 1
        awk -F'|' 'NR==FNR { if ($1 ~ /^server=/) { sub(/^server=/, "", $1); wanted[$1]=1 } next } $1 in wanted' "$probe_ids" "$dir/source" > "$dir/filtered"
        mv "$dir/filtered" "$dir/source"
    fi
    if [ "$probe_scope" = all ] && [ -s "$JOB_DIR/health/ids" ]; then
        for list in doh source; do
            awk -F'|' 'NR==FNR { wanted[$1]=1; next } $1 in wanted' "$JOB_DIR/health/ids" "$dir/$list" > "$dir/filtered"
            mv "$dir/filtered" "$dir/$list"
        done
    fi
    doh_total=$(wc -l < "$dir/doh" | tr -d ' ')
    native_total=$(wc -l < "$dir/source" | tr -d ' ')
    total=$((doh_total + native_total))
    [ "$total" -gt 0 ] || { [ "$probe_scope" != all ] && exit 0; exit 1; }
    [ "$probe_scope" != all ] || printf 'name=dnscrypt_catalog\nprogress_total=%s\nprogress_done=0\nprogress_ok=0\nprogress_fail=0\n' "$total" >> "$JOB_DIR/health/state"
    if [ "${DNS_MANAGER_PROFILE_PROGRESS:-0}" = 1 ]; then
        printf 'phase=Проверяю серверы DNSCrypt\nprogress_total=%s\nprogress_done=0\n' "$total" >> "$JOB_DIR/profile/state"
    fi
    : > "$dir/results"
    offset=1; success_count=0; failed_count=0; done_count=0
    if [ "$doh_total" -gt 0 ]; then
        # Reuse the same direct DoH check as HTTPS DNS Proxy, in bounded groups.
        printf '\022\064\001\000\000\001\000\000\000\000\000\000\007example\003com\000\000\001\000\001' > "$TMP_DIR/dns_query.bin" || exit 1
        while [ "$offset" -le "$doh_total" ]; do
            [ ! -f "$JOB_DIR/health/cancel" ] || break
            end=$((offset + 3))
            sed -n "${offset},${end}p" "$dir/doh" > "$dir/group"
            names=$(awk -F'|' '{if (NR>1) printf ", "; printf "%s", $3}' "$dir/group")
            printf 'phase=DoH: %s\n' "$names" >> "$JOB_DIR/health/state"
            pids=''
            while IFS='|' read -r id url name; do
                rm -f "$TMP_DIR/t.$id"
                (trap - EXIT; test_one_dns "$id" >/dev/null 2>&1) &
                pids="$pids $!"
            done < "$dir/group"
            for pid in $pids; do wait "$pid" 2>/dev/null || :; done
            while IFS='|' read -r id url name; do
                result=$(cat "$TMP_DIR/t.$id" 2>/dev/null || :)
                latency=$(printf '%s\n' "$result" | awk -F'|' '$5=="OK" && $4 ~ /^[0-9]+$/ {print $4}')
                status=$(printf '%s\n' "$result" | awk -F'|' '{print $5}')
                if [ -n "$latency" ]; then
                    printf '%s|%s\n' "$id" "$latency" >> "$dir/results"; success_count=$((success_count + 1))
                elif [ -n "$status" ] && [ "$status" != INTERNAL_TEST_QUERY_CREATE_FAIL ]; then
                    printf '%s|-1\n' "$id" >> "$dir/results"; failed_count=$((failed_count + 1))
                else
                    printf '%s|-2\n' "$id" >> "$dir/results"
                fi
                rm -f "$TMP_DIR/t.$id"
                done_count=$((done_count + 1))
            done < "$dir/group"
            printf 'progress_done=%s\nprogress_ok=%s\nprogress_fail=%s\n' "$done_count" "$success_count" "$failed_count" >> "$JOB_DIR/health/state"
            offset=$((end + 1))
        done
    fi
    offset=1
    while [ "$offset" -le "$native_total" ]; do
        [ "$probe_scope" != all ] || [ ! -f "$JOB_DIR/health/cancel" ] || break
        end=$((offset + 5))
        sed -n "${offset},${end}p" "$dir/source" > "$dir/group"
        names=$(awk -F'|' '{if (NR>1) printf ", "; printf "%s", ($3 != "" ? $3 : $1)}' "$dir/group")
        [ "$probe_scope" != all ] || printf 'phase=%s\n' "$names" >> "$JOB_DIR/health/state"
        : > "$dir/stamps"; : > "$dir/ids"; : > "$dir/valid"
        while IFS='|' read -r id url name; do
            if ! stamp=$(sh "$HELPERS/dns-manager-doh-stamp.sh" "$url" 2>/dev/null); then
                printf '%s|-2\n' "$id" >> "$dir/results"
                continue
            fi
            printf '%s\n' "$id" >> "$dir/ids"
            printf '%s\n' "$stamp" >> "$dir/stamps"
            printf '%s\n' "$url" >> "$dir/valid"
        done < "$dir/group"
        count=$(wc -l < "$dir/ids" | tr -d ' ')
        if [ "$count" -gt 0 ]; then
            # One temporary process, with a distinct loopback port, tests at most six servers.
            port=$((49152 + ($$ + offset) % 12000))
            first_url=$(sed -n '1p' "$dir/valid")
            sh "$HELPERS/dns-manager-dnscrypt-config.sh" "$port" "$first_url" "$BOOTSTRAP_DNS" > "$dir/base" || exit 1
            {
                printf 'server_names = ['
                n=1; while [ "$n" -le "$count" ]; do [ "$n" -eq 1 ] || printf ', '; printf "'manager-%s'" "$n"; n=$((n + 1)); done
                printf ']\n'
                printf "log_file = '%s'\nuse_syslog = false\n" "$dir/probe.log"
                sed -n '2,/^\[static\./{ /^\[static\./d; p; }' "$dir/base"
                n=1; while IFS= read -r stamp; do printf "[static.manager-%s]\nstamp = '%s'\n" "$n" "$stamp"; n=$((n + 1)); done < "$dir/stamps"
            } > "$dir/probe.toml"
            : > "$dir/probe.log"
            dnscrypt-proxy -config "$dir/probe.toml" -netprobe-timeout 5 > "$dir/process.log" 2>&1 &
            probe=$!
            tries=0
            while kill -0 "$probe" 2>/dev/null && [ "$tries" -lt 45 ]; do
                [ "$probe_scope" != all ] || [ ! -f "$JOB_DIR/health/cancel" ] || break
                grep -q 'Server with the lowest initial latency:' "$dir/probe.log" && break
                # With no live servers dnscrypt-proxy never prints the sorted summary.
                if awk -v expected="$count" '/\[manager-[0-9]+\] (OK .*rtt: [0-9]+ms|TIMEOUT)/ { for (i=1; i<=NF; i++) if ($i ~ /^\[manager-[0-9]+\]$/) done[$i]=1 } END { for (i in done) n++; exit !(n >= expected) }' "$dir/probe.log"; then break; fi
                sleep 1; tries=$((tries + 1))
            done
            kill "$probe" 2>/dev/null || :; wait "$probe" 2>/dev/null || :; probe=''
            if [ "$probe_scope" = all ] && [ -f "$JOB_DIR/health/cancel" ]; then break; fi
            if grep -Eqi 'address already in use|permission denied|failed to listen' "$dir/probe.log" "$dir/process.log"; then exit 1; fi
            if [ ! -s "$dir/probe.log" ]; then
                echo 'DNSCrypt не создал журнал проверки серверов.' >&2
                [ ! -s "$dir/process.log" ] || tail -n 5 "$dir/process.log" >&2
                exit 1
            fi
            completed=0; grep -q 'Server with the lowest initial latency:' "$dir/probe.log" && completed=1
            awk '
                /\[manager-[1-6]\] TIMEOUT/ {
                    for(i=1;i<=NF;i++) if($i ~ /^\[manager-[1-6]\]$/) {
                        server=$i; sub(/^\[/, "", server); sub(/\]$/, "", server); values[server]=-1
                    }
                }
                /\[manager-[1-6]\] OK .*rtt: [0-9]+ms/ {
                    for(i=1;i<=NF;i++) if($i ~ /^\[manager-[1-6]\]$/) {
                        server=$i; sub(/^\[/, "", server); sub(/\]$/, "", server)
                        for(j=i+1;j<NF;j++) if($j=="rtt:") {v=$(j+1); sub(/ms.*/, "", v); if(v ~ /^[0-9]+$/) values[server]=v}
                    }
                }
                /Sorted latencies:/ {collecting=1; next}
                collecting && /ms manager-[1-6]$/ {v=$(NF-1); sub(/ms$/, "", v); if(v ~ /^[0-9]+$/) values[$NF]=v; next}
                /Server with the lowest initial latency:/ {
                    if (!collecting) for(i=1;i<=NF;i++) if($i ~ /^manager-[1-6]$/ && $(i+1)=="(rtt:") {v=$(i+2); sub(/ms\).*/, "", v); if(v ~ /^[0-9]+$/) values[$i]=v}
                    collecting=0
                }
                END {for(k in values) print k, values[k]}' "$dir/probe.log" > "$dir/latencies"
            n=1; while IFS= read -r id; do
                latency=$(awk -v s="manager-$n" '$1==s {print $2; exit}' "$dir/latencies")
                case "$latency" in
                    -1) printf '%s|-1\n' "$id" >> "$dir/results"; failed_count=$((failed_count + 1));;
                    ''|*[!0-9]*)
                        if [ "$completed" = 1 ]; then
                            printf '%s|-1\n' "$id" >> "$dir/results"; failed_count=$((failed_count + 1))
                        else
                            printf '%s|-2\n' "$id" >> "$dir/results"
                        fi ;;
                    *) printf '%s|%s\n' "$id" "$latency" >> "$dir/results"; success_count=$((success_count + 1));;
                esac
                n=$((n + 1))
            done < "$dir/ids"
        fi
        done_count=$((doh_total + end)); [ "$done_count" -le "$total" ] || done_count=$total
        if [ "${DNS_MANAGER_PROFILE_PROGRESS:-0}" = 1 ]; then
            printf 'progress_done=%s\n' "$done_count" >> "$JOB_DIR/profile/state"
        fi
        [ "$probe_scope" != all ] || printf 'progress_done=%s\nprogress_ok=%s\nprogress_fail=%s\n' "$done_count" "$success_count" "$failed_count" >> "$JOB_DIR/health/state"
        offset=$((end + 1))
    done
    [ "$catalog_hash" = "$(sha256sum "$DNS_CATALOG" 2>/dev/null)" ] || exit 1
    [ "$custom_hash" = "$(sha256sum "$CUSTOM_DNS_CATALOG" 2>/dev/null || :)" ] || exit 1
    [ "$native_hash" = "$(sha256sum "$NATIVE_CATALOG" 2>/dev/null || :)" ] || exit 1
    if [ "$probe_scope" != all ]; then cat "$dir/results"; exit 0; fi
    . /usr/share/libubox/jshn.sh
    if [ -s "$JOB_DIR/health/ids" ] && [ -r "$RUNTIME_DIR/dnscrypt-catalog-latencies.json" ] && [ -r "$RUNTIME_DIR/dnscrypt-catalog-checksum" ] && [ "$(cat "$RUNTIME_DIR/dnscrypt-catalog-checksum")" = "$(printf '%s\n%s\n%s\n' "$catalog_hash" "$custom_hash" "$native_hash")" ]; then
        json_load "$(cat "$RUNTIME_DIR/dnscrypt-catalog-latencies.json")" && json_get_keys old_ids
        for id in $old_ids; do
            case "$id" in *[!A-Za-z0-9_-]*|'') continue;; esac
            json_get_var latency "$id"
            case "$latency" in -[0-9]*|[0-9]*) printf '%s|%s\n' "$id" "$latency";; esac
        done > "$dir/old-results"
        cat "$dir/results" >> "$dir/old-results"
        awk -F'|' '{ values[$1]=$2 } END { for (id in values) print id "|" values[id] }' "$dir/old-results" > "$dir/results"
    fi
    json_init
    while IFS='|' read -r id latency; do json_add_int "$id" "$latency"; done < "$dir/results"
    tmp="$RUNTIME_DIR/dnscrypt-catalog-latencies.$$"
    json_dump > "$tmp" || exit 1
    printf '%s\n%s\n%s\n' "$catalog_hash" "$custom_hash" "$native_hash" > "$RUNTIME_DIR/dnscrypt-catalog-checksum"
    mv -f "$tmp" "$RUNTIME_DIR/dnscrypt-catalog-latencies.json"
)

diagnostic() {
    method=$1
    cat >/dev/null
    if [ "$method" != system_dns_test ]; then
        engine_selected || { error 'Выбран другой DNS-движок'; return; }
    fi
    . /usr/share/libubox/jshn.sh
    json_init
    if [ "$method" = system_dns_test ]; then
        output=$(nslookup -type=A -timeout=3 -retry=1 openwrt.org 127.0.0.1 2>&1); rc=$?
        if [ "$rc" -eq 0 ]; then output="Системный DNS работает нормально.
$output"; json_add_boolean ok 1
        elif ! ip -4 route get 8.8.8.8 >/dev/null 2>&1 && ! ip -6 route get 2606:4700:4700::1111 >/dev/null 2>&1; then
            output='Ожидание подключения к сети.'; json_add_boolean ok 1
        else output="Системный DNS не ответил.
$output"; json_add_boolean ok 0; fi
    elif [ "$method" = dnscrypt_latencies ]; then
        if dnscrypt_catalog_snapshot; then
            output='Замеры DNSCrypt обновлены.'; json_add_boolean ok 1
        else
            output='Не удалось получить замеры DNSCrypt.'; json_add_boolean ok 0
        fi
    elif [ "$method" = dnscrypt_test ]; then
        output=$(nslookup -type=A -timeout=3 -retry=1 -port=5053 openwrt.org 127.0.0.1 2>&1); rc=$?
        if [ "$rc" -eq 0 ]; then
            system_output=$(nslookup -type=A -timeout=3 -retry=1 openwrt.org 127.0.0.1 2>&1); rc=$?
            output="DNSCrypt (порт 5053):
$output
dnsmasq (порт 53):
$system_output"
        fi
        if [ "$rc" -eq 0 ]; then
            upstream=0
            for item in $(uci -q get 'dhcp.@dnsmasq[0].server'); do
                [ "$item" != '127.0.0.1#5053' ] || upstream=1
            done
            if [ "$upstream" != 1 ]; then
                rc=1
                output="$output
В dnsmasq не настроена пересылка на 127.0.0.1#5053."
            fi
        fi
        if [ "$rc" -ne 0 ] && ! ip -4 route get 8.8.8.8 >/dev/null 2>&1 && ! ip -6 route get 2606:4700:4700::1111 >/dev/null 2>&1; then
            output='Ожидание подключения к сети.'; rc=0
        fi
        if [ "$rc" -eq 0 ]; then json_add_boolean ok 1; else json_add_boolean ok 0; fi
    else
        output=$(logread -e dnscrypt-proxy 2>&1 | tail -n 80)
        if [ "$(uci -q get dns-manager.global.dc_query_log 2>/dev/null || :)" = 1 ] && [ -r /tmp/dns-manager-dnscrypt-query.log ]; then
            output="$output

Последние DNS-запросы:
$(tail -n 40 /tmp/dns-manager-dnscrypt-query.log)"
        fi
        json_add_boolean ok 1
    fi
    json_add_string output "$output"
    json_dump
}



# Check each configured endpoint independently without changing the running pool.
dnscrypt_check_pool() (
    load_manager_functions || exit 1
    trap - EXIT INT TERM
    trap 'rm -rf "$TMP_DIR"; rm -f "$_checks_tmp"' EXIT
    trap 'exit 1' INT TERM
    load_config || exit 1
    command -v dig >/dev/null 2>&1 && HAS_DIG=yes || HAS_DIG=no
    _checks_tmp="$RUNTIME_DIR/dnscrypt-server-checks.$"
    : > "$_checks_tmp" || exit 1
    while IFS='|' read -r _entry_id _entry_url; do
        case "$_entry_id" in server=*) _entry_id=${_entry_id#server=};; *) continue;; esac
        case "$_entry_id" in ''|*[!A-Za-z0-9_-]*) continue;; esac
        case "$_entry_url" in https://*) ;; *) continue;; esac
        rm -f "$TMP_DIR/t.$_entry_id"
        ( dns_url() { printf '%s' "$_entry_url"; }; dns_name() { printf '%s' "$_entry_id"; }; dns_cat() { printf '%s' dnscrypt; }; test_one_dns "$_entry_id" ) >/dev/null 2>&1 || :
        _check_result=$(awk -F'|' -v id="$_entry_id" '$1==id && NF>=5 {print $4 "|" $5;exit}' "$TMP_DIR/t.$_entry_id" 2>/dev/null)
        case "$_check_result" in *'|'*) printf '%s|%s|%s|%s\n' "$_entry_id" "$_entry_url" "$_check_result" "$(date +%s)" >> "$_checks_tmp" || exit 1;; *) exit 1;; esac
    done < "$STATE_FILE"
    if grep -q '^server=[^|]*|sdns://' "$STATE_FILE"; then
        _native_tmp="$_checks_tmp.native"
        dnscrypt_catalog_snapshot native "$STATE_FILE" > "$_native_tmp" 2>/dev/null || :
        while IFS='|' read -r _entry_id _entry_url; do
            case "$_entry_id:$_entry_url" in server=*:sdns://*) _entry_id=${_entry_id#server=};; *) continue;; esac
            _check_ms=$(awk -F'|' -v id="$_entry_id" '$1==id {print $2; exit}' "$_native_tmp")
            case "$_check_ms" in
                -1) printf '%s|%s|0|FAIL|%s\n' "$_entry_id" "$_entry_url" "$(date +%s)" >> "$_checks_tmp";;
                ''|*[!0-9]*) :;;
                *) printf '%s|%s|%s|OK|%s\n' "$_entry_id" "$_entry_url" "$_check_ms" "$(date +%s)" >> "$_checks_tmp";;
            esac
        done < "$STATE_FILE"
        rm -f "$_native_tmp"
    fi
    [ -s "$_checks_tmp" ] || exit 1
    mv -f "$_checks_tmp" "$RUNTIME_DIR/dnscrypt-server-checks" || exit 1
    rm -rf "$TMP_DIR"
)

diagnostic_worker() {
    method=$1
    mkdir -p "$JOB_DIR/health"
    printf 'pid=%s\n' "$$" >> "$JOB_DIR/health/state"
    token=$(awk '{print $22}' "/proc/$$/stat" 2>/dev/null || true)
    [ -z "$token" ] || printf 'pid_start=%s\n' "$token" >> "$JOB_DIR/health/state"
    reply=$(diagnostic "$method" </dev/null)
    if [ "$method" = dnscrypt_test ] && engine_selected && [ -r "$STATE_FILE" ]; then
        rm -f "$RUNTIME_DIR/dnscrypt-server-checks"
        dnscrypt_check_pool || reply='{"ok":false,"output":"Не удалось проверить серверы DNSCrypt."}'
    fi
    result=$(jsonfilter -s "$reply" -e '@.ok' 2>/dev/null)
    jsonfilter -s "$reply" -e '@.output' > "$JOB_DIR/health/output" 2>/dev/null || true
    [ -s "$JOB_DIR/health/output" ] || jsonfilter -s "$reply" -e '@.error' > "$JOB_DIR/health/output" 2>/dev/null || true
    if [ "$result" = true ] || [ "$result" = 1 ]; then result=ok; else result=fail; fi
    [ "$method" != dnscrypt_latencies ] || [ ! -f "$JOB_DIR/health/cancel" ] || printf 'cancelled=1\n' >> "$JOB_DIR/health/state"
    printf 'result=%s\nstatus=done\nfinished=%s\n' "$result" "$(date +%s)" >> "$JOB_DIR/health/state"
}

diagnostic_start() {
    method=$1
    input=$(cat)
    mkdir -p "$JOB_DIR/health" "$RUNTIME_DIR" || { error 'Не удалось подготовить проверку DNS'; return; }
    exec 9>"$RUNTIME_DIR/health-start.lock" || { error 'Не удалось подготовить проверку DNS'; return; }
    flock -n 9 || { error 'Проверка DNS уже запускается'; return; }
    service=dns-manager-health-check
    reply=$(ubus -t 5 call service list "{\"name\":\"$service\"}" 2>/dev/null) || { error 'Служба задач недоступна'; return; }
    if printf '%s\n' "$reply" | grep -q '"running"[[:space:]]*:[[:space:]]*true'; then
        error 'Проверка DNS уже выполняется'; return
    fi
    ubus -t 5 call service delete "{\"name\":\"$service\"}" >/dev/null 2>&1 || true
    rm -f "$JOB_DIR/health/cancel" "$JOB_DIR/health/ids"
    if [ "$method" = dnscrypt_latencies ]; then
        ids=$(jsonfilter -s "$input" -e '@.ids')
        case "$ids" in ''|*[!A-Za-z0-9_,-]*) error 'Выберите серверы на странице каталога'; return;; esac
        printf '%s\n' "$ids" | tr ',' '\n' | awk 'NF && !seen[$0]++ {print}' > "$JOB_DIR/health/ids"
        [ "$(wc -l < "$JOB_DIR/health/ids")" -le 512 ] || { error 'Слишком много серверов'; return; }
    fi
    printf 'status=running\nstarted=%s\nmode=update\n' "$(date +%s)" > "$JOB_DIR/health/state"
    [ "$method" != dnscrypt_latencies ] || printf 'name=dnscrypt_catalog\n' >> "$JOB_DIR/health/state"
    : > "$JOB_DIR/health/output"
    request="{\"name\":\"$service\",\"instances\":{\"main\":{\"command\":[\"/bin/sh\",\"/usr/lib/dns-manager-luci/backend-dnscrypt.sh\",\"diagnostic_worker\",\"$method\"]}}}"
    if ! ubus -t 5 call service set "$request" >/dev/null 2>&1; then
        printf 'result=fail\nstatus=failed\nfinished=%s\n' "$(date +%s)" >> "$JOB_DIR/health/state"
        error 'Не удалось запустить проверку DNS'; return
    fi
    printf '{"ok":true,"job":"health"}\n'
}

diagnostic_cancel() {
    cat >/dev/null
    if [ "$(sed -n 's/^name=//p' "$JOB_DIR/health/state" 2>/dev/null | tail -n1)" = dnscrypt_catalog ] && [ "$(sed -n 's/^status=//p' "$JOB_DIR/health/state" 2>/dev/null | tail -n1)" = running ]; then
        : > "$JOB_DIR/health/cancel"
    fi
    printf '{"ok":true}\n'
}

# The regional routes are dnsmasq rules; the encrypted pool remains unchanged.
regional_worker() {
    requested=$1
    refresh=${2:-0}
    rc=1
    load_manager_functions || return 1
    preflight_readonly >/dev/null 2>&1 && init_dirs >/dev/null 2>&1 && load_config >/dev/null 2>&1 && acquire_mutation_lock || return 1
    old_mode=$(uci -q get dns-manager.global.dnscrypt_regional_mode || :)
    old_ips=$(uci -q get dns-manager.global.dnscrypt_regional_ips || :)
    if ! engine_selected || ! "$DNSCRYPT_INIT" running >/dev/null 2>&1; then
        echo 'DNSCrypt не запущен.'
    else
        case "$requested" in 0) mode=doh;; 2) mode=yandex;; 3) mode=isp;; refresh) mode=$old_mode;; *) mode=invalid;; esac
        ips=''
        [ "$mode" != isp ] || ips=$(regional_provider_addresses | tr '\n' ' ' | sed 's/ *$//')
        if [ "$mode" = isp ] && [ -z "$ips" ]; then
            if [ "$refresh" = 1 ]; then release_mutation_lock; return 0; fi
            echo 'Провайдер не предоставил DNS-адреса.'
        elif [ "$mode" = invalid ] || { [ "$refresh" = 1 ] && [ "$mode" != isp ]; }; then
            [ "$refresh" != 1 ] || rc=0
        elif [ "$refresh" = 1 ] && [ "$ips" = "$old_ips" ]; then
            rc=0
        elif uci -q get dns-manager.global >/dev/null 2>&1 &&
             uci set "dns-manager.global.dnscrypt_regional_mode=$mode" &&
             uci set "dns-manager.global.dnscrypt_regional_ips=$ips" && uci commit dns-manager &&
             sh "$HELPERS/dns-manager-dnscrypt-dnsmasq.sh" 5053; then
            rc=0
            echo 'Настройка регионального DNS применена.'
        else
            echo 'Не удалось применить региональный DNS. Восстанавливаю предыдущую настройку.'
            uci set "dns-manager.global.dnscrypt_regional_mode=$old_mode" || :
            uci set "dns-manager.global.dnscrypt_regional_ips=$old_ips" || :
            uci commit dns-manager || :
            sh "$HELPERS/dns-manager-dnscrypt-dnsmasq.sh" 5053 || :
        fi
    fi
    release_mutation_lock
    [ "$refresh" = 1 ] || /etc/init.d/dns-manager-regional restart >/dev/null 2>&1 || :
    return "$rc"
}

regional_job() {
    enabled=$1
    printf 'pid=%s\n' "$$" >> "$JOB_DIR/regional/state"
    token=$(awk '{print $22}' "/proc/$$/stat" 2>/dev/null || :)
    [ -z "$token" ] || printf 'pid_start=%s\n' "$token" >> "$JOB_DIR/regional/state"
    exec >> "$JOB_DIR/regional/output" 2>&1 </dev/null
    if regional_worker "$enabled"; then result=ok; status=done; else result=fail; status=failed; fi
    printf 'result=%s\nstatus=%s\nfinished=%s\n' "$result" "$status" "$(date +%s)" >> "$JOB_DIR/regional/state"
}

regional_start() {
    input=$(cat)
    enabled=$(printf '%s' "$input" | jsonfilter -e '@.enabled' 2>/dev/null || :)
    case "$enabled" in 0|2|3) ;; *) error 'Неверный региональный режим'; return;; esac
    mkdir -p "$JOB_DIR/regional" "$RUNTIME_DIR" || { error 'Не удалось подготовить задачу'; return; }
    exec 9>"$RUNTIME_DIR/dnscrypt-regional-start.lock" || return 1
    flock -n 9 || { error 'Настройка уже запускается'; return; }
    reply=$(ubus -t 5 call service list '{"name":"dns-manager-dnscrypt-regional"}' 2>/dev/null) || { error 'Служба задач недоступна'; return; }
    if printf '%s' "$reply" | grep -q '"running"[[:space:]]*:[[:space:]]*true'; then error 'Настройка уже применяется'; return; fi
    ubus -t 5 call service delete '{"name":"dns-manager-dnscrypt-regional"}' >/dev/null 2>&1 || :
    printf 'status=running\nstarted=%s\nmode=regional\nenabled=%s\n' "$(date +%s)" "$enabled" > "$JOB_DIR/regional/state"
    : > "$JOB_DIR/regional/output"
    request="{\"name\":\"dns-manager-dnscrypt-regional\",\"instances\":{\"main\":{\"command\":[\"/bin/sh\",\"/usr/lib/dns-manager-luci/backend-dnscrypt.sh\",\"regional_worker\",\"$enabled\"]}}}"
    if ! ubus -t 5 call service set "$request" >/dev/null 2>&1; then
        printf 'result=fail\nstatus=failed\nfinished=%s\n' "$(date +%s)" >> "$JOB_DIR/regional/state"
        error 'Не удалось запустить изменение'; return
    fi
    printf '{"ok":true,"job":"regional"}\n'
}

# DNSCrypt logs initial resolver RTTs, not a continuous reachability check.
dnscrypt_pool_latency() {
    [ "$1" = 1 ] || return 0
    pids=$(pidof dnscrypt-proxy 2>/dev/null || :)
    case "$pids" in ''|*[!0-9]*) return 0;; esac
    logread -l 300 -e dnscrypt-proxy 2>/dev/null | awk -v pid="$pids" '
        index($0, "dnscrypt-proxy[" pid "]") == 0 { next }
        /Sorted latencies:/ { for (server in pending) delete pending[server]; collecting=1; next }
        collecting && /ms manager-[0-9]+$/ {
            server=$NF; value=$(NF-1); sub(/ms$/, "", value)
            if (server ~ /^manager-[1-6]$/ && value ~ /^[0-9]+$/) pending[server]=value
            next
        }
        /Server with the lowest initial latency:/ {
            if (!collecting) {
                for (server in pending) delete pending[server]
                for (i=1; i<=NF; i++) if ($i ~ /^manager-[1-6]$/ && $(i+1)=="(rtt:") {
                    value=$(i+2); sub(/ms\).*/, "", value)
                    if (value ~ /^[0-9]+$/) pending[$i]=value
                }
            }
            stamp=""
            months="JanFebMarAprMayJunJulAugSepOctNovDec"
            month=index(months,$2)
            if ($1 ~ /^(Mon|Tue|Wed|Thu|Fri|Sat|Sun)$/ && month>0 && $3 ~ /^[0-9]+$/ && $4 ~ /^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/ && $5 ~ /^[0-9][0-9][0-9][0-9]$/)
                stamp=sprintf("%02d.%02d.%s,%s",$3,(month+2)/3,$5,$4)
            for (server in latest) delete latest[server]; for (server in pending) latest[server]=pending[server] " " stamp
            collecting=0
        }
        END { for (server in latest) print server " " latest[server] }
    '
}

status_extra() {
    method=$1
    input=$(cat)
    base=$(printf '%s' "$input" | "$LEGACY" call "$method") || { error 'Не удалось получить состояние'; return; }
    case "$base" in \{*\}) ;; *) error 'Некорректное состояние'; return;; esac
    . /usr/share/libubox/jshn.sh
    json_init
    json_add_string dnscrypt_engine dnscrypt-proxy2
    # Catalog candidates are not a live availability or DNSSEC result.
    if [ -r "$NATIVE_CATALOG" ]; then
    json_add_object dnscrypt_profile_candidates
    for category in bypass clean security privacy adblock family dnssec; do
        count=$(awk -F'|' -v category="$category" '$1 !~ /^#/ && $3 == "dnscrypt" && ($2 == category || (category == "dnssec" && ($2 == "clean" || $2 == "privacy"))) { n++ } END { print n+0 }' "$NATIVE_CATALOG" 2>/dev/null)
        case "$count" in ''|*[!0-9]*) count=0;; esac
        json_add_int "$category" "$count"
    done
    json_close_object
    fi
    if [ -r "$CONFIG_DIR/dns-catalog.conf" ]; then
        json_add_object dnscrypt_doh_profile_candidates
        for category in bypass clean security privacy adblock family; do
            count=$(cat "$CONFIG_DIR/dns-catalog.conf" "$CONFIG_DIR/dns-custom-catalog.conf" 2>/dev/null | awk -F'|' -v category="$category" 'NF >= 5 && $1 !~ /^#/ && $1 ~ /^[A-Za-z0-9_-]+$/ && $2 == category && $5 ~ /^https:\/\// && !seen[$1]++ { n++ } END { print n+0 }')
            case "$count" in ''|*[!0-9]*) count=0;; esac
            json_add_int "$category" "$count"
        done
        json_close_object
    fi
    force_active=0
    [ "$(uci -q get firewall.dns_forced 2>/dev/null)" = redirect ] &&
        [ "$(uci -q get firewall.dns_forced.name 2>/dev/null)" = Force-DNS-DNSCrypt ] && force_active=1
    json_add_int dnscrypt_forced_dns "$force_active"
    running=0
    "$DNSCRYPT_INIT" running >/dev/null 2>&1 && running=1
    json_add_int dnscrypt_running "$running"
    for setting in cache force_tcp block_ipv6 block_unqualified block_undelegated query_log; do
        value=$(uci -q get "dns-manager.global.dc_$setting" 2>/dev/null || :)
        case "$value" in 0|1) ;; *) case "$setting" in cache|block_unqualified|block_undelegated) value=1;; *) value=0;; esac;; esac
        json_add_int "dc_$setting" "$value"
    done
    value=$(uci -q get dns-manager.global.dc_cache_size 2>/dev/null || :)
    case "$value" in 1000|4096|10000) ;; *) value=4096;; esac
    json_add_int dc_cache_size "$value"
    value=$(uci -q get dns-manager.global.dc_cache_ttl 2>/dev/null || :)
    case "$value" in 0|300|900|1800) ;; *) value=0;; esac
    json_add_int dc_cache_ttl "$value"
    json_add_object dnscrypt_server_latency
    latency_records=$(dnscrypt_pool_latency "$running")
    while read -r latency_server latency_ms latency_time; do
        case "$latency_server:$latency_ms" in manager-[1-6]:*[!0-9]*|manager-[1-6]:|*[!A-Za-z0-9:-]*) continue;; manager-[1-6]:*) json_add_int "$latency_server" "$latency_ms";; esac
    done <<EOF_LATENCY
$latency_records
EOF_LATENCY
    json_close_object
    json_add_object dnscrypt_server_latency_times
    while read -r latency_server latency_ms latency_time; do
        case "$latency_server:$latency_time" in manager-[1-6]:[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9],[0-9][0-9]:[0-9][0-9]:[0-9][0-9]) json_add_string "$latency_server" "$latency_time";; esac
    done <<EOF_LATENCY_TIME
$latency_records
EOF_LATENCY_TIME
    json_close_object
    latency_cache="$RUNTIME_DIR/dnscrypt-catalog-latencies.json"
    if [ -r "$latency_cache" ] && [ -r "$RUNTIME_DIR/dnscrypt-catalog-checksum" ] && [ -r "$CONFIG_DIR/dns-catalog.conf" ]; then
        cache_catalog=$(sed -n '1p' "$RUNTIME_DIR/dnscrypt-catalog-checksum")
        cache_custom=$(sed -n '2p' "$RUNTIME_DIR/dnscrypt-catalog-checksum")
        cache_native=$(sed -n '3p' "$RUNTIME_DIR/dnscrypt-catalog-checksum")
        current_catalog=$(sha256sum "$CONFIG_DIR/dns-catalog.conf")
        current_custom=$(sha256sum "$CONFIG_DIR/dns-custom-catalog.conf" 2>/dev/null || :)
        current_native=$(sha256sum "$NATIVE_CATALOG" 2>/dev/null || :)
        if [ "$cache_catalog" = "$current_catalog" ] && [ "$cache_custom" = "$current_custom" ] && [ "$cache_native" = "$current_native" ]; then
            json_add_string dnscrypt_catalog_results "$(cat "$latency_cache")"
        fi
    fi
    # Monitoring is optional; an unavailable endpoint must not look like zero activity.
    if [ "$method" = status ] && [ "$running" -eq 1 ] && command -v curl >/dev/null 2>&1; then
        metrics=$(curl --noproxy '*' --silent --fail --max-time 1 http://127.0.0.1:9100/api/metrics 2>/dev/null || :)
        if [ -n "$metrics" ]; then
            queries=$(printf '%s' "$metrics" | jsonfilter -e '@.total_queries' 2>/dev/null || :)
            cache_enabled=$(printf '%s' "$metrics" | jsonfilter -e '@.cache_stats.enabled' 2>/dev/null || :)
            capacity=$(printf '%s' "$metrics" | jsonfilter -e '@.cache_stats.capacity' 2>/dev/null || :)
            entries=$(printf '%s' "$metrics" | jsonfilter -e '@.cache_stats.entries' 2>/dev/null || :)
            average=$(printf '%s' "$metrics" | jsonfilter -e '@.avg_response_time' 2>/dev/null || :)
            case "$queries" in ''|*[!0-9]*) queries= ;; esac
            if [ -n "$queries" ]; then
                json_add_int dnscrypt_monitoring_available 1
                case "$capacity:$entries" in *[!0-9:]*|:*|*:) ;; *)
                    if [ "$cache_enabled" = true ] && [ "$capacity" -gt 0 ] 2>/dev/null; then
                        json_add_string dnscrypt_cache_entries "$entries"
                    fi ;;
                esac
                case "$average" in ''|*[!0-9.]*) ;; *)
                    [ "$queries" -eq 0 ] 2>/dev/null || json_add_string dnscrypt_avg_response_ms "$average" ;;
                esac
            fi
        fi
    fi
    profile=$(sed -n 's/^profile=//p' "$STATE_FILE" 2>/dev/null | head -n1)
    valid_profile "$profile" || profile=none
    json_add_string dnscrypt_profile "$profile"
    auto_catalog=$(sed -n 's/^auto_catalog=//p' "$STATE_FILE" 2>/dev/null | head -n1)
    case "$auto_catalog" in 1) ;; *) auto_catalog=0;; esac
    json_add_int dnscrypt_auto_catalog "$auto_catalog"
    protocol=$(sed -n 's/^protocol=//p' "$STATE_FILE" 2>/dev/null | head -n1)
    case "$protocol" in native) ;; *) protocol=mixed;; esac
    strategy=$(dnscrypt_configured_strategy)
    json_add_string dnscrypt_protocol "$protocol"
    json_add_string dnscrypt_strategy "$strategy"
    selected=$(sed -n 's/^selected=//p' "$STATE_FILE" 2>/dev/null | head -n1)
    case "$selected" in *[!A-Za-z0-9_-]*) selected='';; esac
    json_add_string dnscrypt_selected_server "$selected"
    json_add_array dnscrypt_available_servers
    if [ "$auto_catalog" != 1 ]; then
    while IFS='|' read -r id url; do
        case "$id" in ''|*[!A-Za-z0-9_-]*) continue;; esac
        json_add_string '' "$id"
    done <<EOF_POOL
$(dnscrypt_pool_records)
EOF_POOL
    fi
    json_close_array
    regional_mode=$(uci -q get dns-manager.global.dnscrypt_regional_mode || :)
    case "$regional_mode" in yandex|isp) ;; *) regional_mode=doh;; esac
    json_add_string dnscrypt_regional_mode "$regional_mode"
    json_add_string dnscrypt_regional_ips "$(uci -q get dns-manager.global.dnscrypt_regional_ips || :)"
    json_add_object dnscrypt_server_checks
    if [ "$running" -eq 1 ] && [ -r "$STATE_FILE" ] && [ -r "$RUNTIME_DIR/dnscrypt-server-checks" ]; then
        while IFS='|' read -r check_id check_url check_ms check_status check_time; do
            case "$check_id" in ''|*[!A-Za-z0-9_-]*) continue;; esac
            case "$check_time" in ''|*[!0-9]*) continue;; esac
            grep -Fqx "server=$check_id|$check_url" "$STATE_FILE" || continue
            case "$check_status:$check_ms" in OK:*[!0-9]*|OK:) continue;; OK:*) json_add_string "$check_id" "OK:$check_ms";; *) json_add_string "$check_id" fail;; esac
        done < "$RUNTIME_DIR/dnscrypt-server-checks"
    fi
    json_close_object
    json_add_object dnscrypt_server_check_times
    if [ "$running" -eq 1 ] && [ -r "$STATE_FILE" ] && [ -r "$RUNTIME_DIR/dnscrypt-server-checks" ]; then
        while IFS='|' read -r check_id check_url check_ms check_status check_time; do
            case "$check_id" in ''|*[!A-Za-z0-9_-]*) continue;; esac
            case "$check_time" in ''|*[!0-9]*) continue;; esac
            grep -Fqx "server=$check_id|$check_url" "$STATE_FILE" || continue
            case "$check_status:$check_ms" in OK:*[!0-9]*|OK:) continue;; esac
            json_add_int "$check_id" "$check_time"
        done < "$RUNTIME_DIR/dnscrypt-server-checks"
    fi
    json_close_object
    json_add_int dnscrypt_check_now "$(date +%s)"
    json_add_array dnscrypt_servers
    if [ "$auto_catalog" != 1 ] && [ -r "$STATE_FILE" ]; then
        while IFS='|' read -r id url; do
            case "$id" in server=*) id=${id#server=};; *) continue;; esac
            case "$id" in ''|*[!A-Za-z0-9_-]*) continue;; esac
            json_add_string '' "$id"
        done < "$STATE_FILE"
    fi
    json_close_array
    json_add_object dnscrypt_server_names
    if [ -r "$STATE_FILE" ]; then
        while IFS='|' read -r id url; do
            case "$id" in server=*) id=${id#server=};; available=*) id=${id#available=};; *) continue;; esac
            case "$id" in ''|*[!A-Za-z0-9_-]*) continue;; esac
            name=''
            for catalog in "$CONFIG_DIR/dns-catalog.conf" "$CONFIG_DIR/dns-custom-catalog.conf" "$NATIVE_CATALOG"; do
                [ -r "$catalog" ] || continue
                name=$(awk -F '|' -v id="$id" '$1 == id {print $4; exit}' "$catalog")
                [ -z "$name" ] || break
            done
            case "$id:$name" in cloudflare_clean:) name='Cloudflare';; google_clean:) name='Google Public DNS';; esac
            json_add_string "$id" "${name:-$id}"
        done < "$STATE_FILE"
    fi
    json_close_object
    extra=$(json_dump)
    base=${base%\}}
    extra=${extra#\{}
    printf '%s,%s\n' "$base" "$extra"
}

case "${1:-}" in
    setting_worker) dnscrypt_setting_worker ;;
    diagnostic_worker) diagnostic_worker "${2:-}" ;;
    worker) profile_worker "${2:-}" ;;
    reset_worker) reset_worker ;;
    regional_worker) regional_job "${2:-}" ;;
    refresh_regional) regional_worker refresh 1 ;;
    list) exec "$LEGACY" list ;;
    call)
        case "${2:-}" in
            set_profile) profile_start ;;
            set_regional) regional_start ;;
            reset_dns) reset_start ;;
            set_setting) dnscrypt_setting_start ;;
            switch_engine) switch_start ;;
            dnscrypt_test|dnscrypt_latencies|system_dns_test) diagnostic_start "$2" ;;
            dnscrypt_cancel) diagnostic_cancel ;;
            dnscrypt_log) diagnostic "$2" ;;
            status|doh_status|network_status|time_status|log) status_extra "$2" ;;
            runtime|connectivity|page_meta|catalog|lan_devices|job|job_status|multi|set_ntp|update_check|update_hdp|update_background|uninstall|uninstall_status)
                exec "$LEGACY" "$@" ;;
            *) error 'Действие пока недоступно для dnscrypt-proxy2' ;;
        esac ;;
    *) exit 1 ;;
esac
