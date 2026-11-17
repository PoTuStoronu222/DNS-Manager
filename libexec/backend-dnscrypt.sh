#!/bin/sh
# Experimental RPC backend for the single-process DNSCrypt engine.
# Methods that still depend on individual https-dns-proxy instances are
# rejected until they have an engine-aware implementation.
LEGACY=${DNS_MANAGER_LEGACY_BACKEND:-/usr/lib/dns-manager-luci/backend.sh}
MANAGER=${DNS_MANAGER_MANAGER:-/usr/bin/dns-manager}
HELPERS=${DNS_MANAGER_DNSCRYPT_HELPERS:-/usr/lib/dns-manager-luci/dnscrypt}
CONFIG_DIR=${DNS_MANAGER_DNSCRYPT_CONFIG_DIR:-/etc/dns-manager/config}
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
valid_profile() { case "$1" in bypass|clean|security|privacy|adblock|family|all|dnssec|default) return 0;; server:*) id=${1#server:}; case "$id" in ''|*[!A-Za-z0-9_-]*) return 1;; *) return 0;; esac;; *) return 1;; esac; }
# A manually selected server must come from the current pool, never from RPC input.
dnscrypt_pool_records() {
    [ -r "$STATE_FILE" ] || return 1
    if grep -q '^available=' "$STATE_FILE"; then sed -n 's/^available=//p' "$STATE_FILE"
    else sed -n 's/^server=//p' "$STATE_FILE"; fi
}
engine_selected() { [ -r "$ENGINE_FILE" ] && [ "$(cat "$ENGINE_FILE" 2>/dev/null)" = dnscrypt-proxy2 ]; }
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
dnscrypt_set_setting() {
    input=$(cat)
    name=$(printf '%s' "$input" | jsonfilter -e '@.name' 2>/dev/null)
    enabled=$(printf '%s' "$input" | jsonfilter -e '@.enabled' 2>/dev/null)
    case "$name" in watchdog|watchdog_autoreplace|force|browser_dns) ;; *) error 'Эта настройка пока недоступна для DNSCrypt'; return;; esac
    case "$enabled" in 0|1) ;; *) error 'Неверное значение настройки'; return;; esac
    load_manager_functions && load_config && acquire_mutation_lock || { error 'Не удалось применить настройку DNS'; return; }
    rc=0
    if [ "$name" = browser_dns ]; then
        set_browser_dns_hint "$enabled" >/dev/null 2>&1 || rc=$?
    elif [ "$name" = force ]; then
        dnscrypt_set_force "$enabled" >/dev/null 2>&1 || rc=$?
    elif [ "$name" = watchdog ]; then
        watchdog_apply_toggle "$enabled" >/dev/null 2>&1 || rc=$?
    else
        watchdog_apply_autoreplace_toggle "$enabled" >/dev/null 2>&1 || rc=$?
    fi
    release_mutation_lock
    [ "$rc" -eq 0 ] || { error 'Не удалось применить настройку DNS'; return; }
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
    case "$name:$enabled" in watchdog:0|watchdog:1|watchdog_autoreplace:0|watchdog_autoreplace:1|force:0|force:1|browser_dns:0|browser_dns:1) ;; *) error 'Неверная настройка'; return;; esac
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
    current=$(uci -q get firewall.dns_forced || :)
    owner=$(uci -q get firewall.dns_forced.name || :)
    [ -z "$current" ] || { [ "$current" = redirect ] && [ "$owner" = Force-DNS-DNSCrypt ]; } || return 1
    [ -z "$(uci -q changes firewall)" ] || return 1
    if [ "$enabled" = 1 ]; then
        refresh_runtime_capabilities >/dev/null 2>&1 || return 1
        detect_steer_dns_path >/dev/null 2>&1 || return 1
        # A second redirect would compete with Steer's own LAN DNS hook.
        [ "${STEER_DNS_ACTIVE:-0}" != 1 ] || return 1
        lan_ip=$(uci -q get network.lan.ipaddr | sed 's-/.*$--')
        case "$lan_ip" in ''|*[!0-9.]*) return 1;; esac
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
    uci commit firewall && /etc/init.d/firewall reload
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
        restore_persistent_test_results >/dev/null 2>&1 || true
        refresh_runtime_capabilities >/dev/null 2>&1 || true
        if [ -r "$HELPERS/dns-manager-dnscrypt-profile.sh" ] &&
           [ -r "$HELPERS/dns-manager-dnscrypt-profile-apply.sh" ]; then
            . "$HELPERS/dns-manager-dnscrypt-profile.sh"
            . "$HELPERS/dns-manager-dnscrypt-profile-apply.sh"
            records=''; state_tmp=''
            if mkdir -p "$CONFIG_DIR" && records=$(mktemp "$CONFIG_DIR/.dnscrypt-profile.XXXXXX") &&
               state_tmp=$(mktemp "$CONFIG_DIR/.dnscrypt-state.XXXXXX"); then
                printf '%s\n' 'Проверяю DNS и применяю профиль.'
                if (
                    if [ "$goal" = default ]; then
                        dnscrypt_select_profile() {
                            printf '%s\n' 'cloudflare_clean|https://cloudflare-dns.com/dns-query' 'google_clean|https://dns.google/dns-query'
                        }
                    else
                        case "$goal" in server:*)
                            chosen=${goal#server:}
                            dnscrypt_select_profile() {
                                dnscrypt_pool_records | awk -F '|' -v id="$chosen" '$1 == id {print; found=1; exit} END {if (!found) exit 1}'
                            } ;;
                        esac
                    fi
                    DNS_MANAGER_NO_UPDATE=1 SILENT_APPLY=1 dnscrypt_apply_profile_pool "$goal" 5053 "$BOOTSTRAP_DNS"
                ) > "$records"; then
                    state_profile=$goal
                    case "$goal" in default|server:*) state_profile=none;; esac
                    if "$DNSCRYPT_INIT" enable &&
                       { printf 'profile=%s\n' "$state_profile";
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
        json_add_boolean ok 1
    fi
    json_add_string output "$output"
    json_dump
}



diagnostic_worker() {
    method=$1
    mkdir -p "$JOB_DIR/health"
    printf 'pid=%s\n' "$$" >> "$JOB_DIR/health/state"
    token=$(awk '{print $22}' "/proc/$$/stat" 2>/dev/null || true)
    [ -z "$token" ] || printf 'pid_start=%s\n' "$token" >> "$JOB_DIR/health/state"
    reply=$(diagnostic "$method" </dev/null)
    result=$(jsonfilter -s "$reply" -e '@.ok' 2>/dev/null)
    jsonfilter -s "$reply" -e '@.output' > "$JOB_DIR/health/output" 2>/dev/null || true
    [ -s "$JOB_DIR/health/output" ] || jsonfilter -s "$reply" -e '@.error' > "$JOB_DIR/health/output" 2>/dev/null || true
    if [ "$result" = true ] || [ "$result" = 1 ]; then result=ok; else result=fail; fi
    printf 'result=%s\nstatus=done\nfinished=%s\n' "$result" "$(date +%s)" >> "$JOB_DIR/health/state"
}

diagnostic_start() {
    method=$1
    cat >/dev/null
    mkdir -p "$JOB_DIR/health" "$RUNTIME_DIR" || { error 'Не удалось подготовить проверку DNS'; return; }
    exec 9>"$RUNTIME_DIR/health-start.lock" || { error 'Не удалось подготовить проверку DNS'; return; }
    flock -n 9 || { error 'Проверка DNS уже запускается'; return; }
    service=dns-manager-health-check
    reply=$(ubus -t 5 call service list "{\"name\":\"$service\"}" 2>/dev/null) || { error 'Служба задач недоступна'; return; }
    if printf '%s\n' "$reply" | grep -q '"running"[[:space:]]*:[[:space:]]*true'; then
        error 'Проверка DNS уже выполняется'; return
    fi
    ubus -t 5 call service delete "{\"name\":\"$service\"}" >/dev/null 2>&1 || true
    printf 'status=running\nstarted=%s\nmode=update\n' "$(date +%s)" > "$JOB_DIR/health/state"
    : > "$JOB_DIR/health/output"
    request="{\"name\":\"$service\",\"instances\":{\"main\":{\"command\":[\"/bin/sh\",\"/usr/lib/dns-manager-luci/backend-dnscrypt.sh\",\"diagnostic_worker\",\"$method\"]}}}"
    if ! ubus -t 5 call service set "$request" >/dev/null 2>&1; then
        printf 'result=fail\nstatus=failed\nfinished=%s\n' "$(date +%s)" >> "$JOB_DIR/health/state"
        error 'Не удалось запустить проверку DNS'; return
    fi
    printf '{"ok":true,"job":"health"}\n'
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
            for (server in latest) delete latest[server]; for (server in pending) latest[server]=pending[server]
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
    force_active=0
    [ "$(uci -q get firewall.dns_forced 2>/dev/null)" = redirect ] &&
        [ "$(uci -q get firewall.dns_forced.name 2>/dev/null)" = Force-DNS-DNSCrypt ] && force_active=1
    json_add_int dnscrypt_forced_dns "$force_active"
    running=0
    "$DNSCRYPT_INIT" running >/dev/null 2>&1 && running=1
    json_add_int dnscrypt_running "$running"
    json_add_object dnscrypt_server_latency
    latency_records=$(dnscrypt_pool_latency "$running")
    while read -r latency_server latency_ms; do
        case "$latency_server:$latency_ms" in manager-[1-6]:*[!0-9]*|manager-[1-6]:|*[!A-Za-z0-9:-]*) continue;; manager-[1-6]:*) json_add_int "$latency_server" "$latency_ms";; esac
    done <<EOF_LATENCY
$latency_records
EOF_LATENCY
    json_close_object
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
    selected=$(sed -n 's/^selected=//p' "$STATE_FILE" 2>/dev/null | head -n1)
    case "$selected" in *[!A-Za-z0-9_-]*) selected='';; esac
    json_add_string dnscrypt_selected_server "$selected"
    json_add_array dnscrypt_available_servers
    while IFS='|' read -r id url; do
        case "$id" in ''|*[!A-Za-z0-9_-]*) continue;; esac
        json_add_string '' "$id"
    done <<EOF_POOL
$(dnscrypt_pool_records)
EOF_POOL
    json_close_array
    regional_mode=$(uci -q get dns-manager.global.dnscrypt_regional_mode || :)
    case "$regional_mode" in yandex|isp) ;; *) regional_mode=doh;; esac
    json_add_string dnscrypt_regional_mode "$regional_mode"
    json_add_string dnscrypt_regional_ips "$(uci -q get dns-manager.global.dnscrypt_regional_ips || :)"
    json_add_array dnscrypt_servers
    if [ -r "$STATE_FILE" ]; then
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
            for catalog in "$CONFIG_DIR/dns-catalog.conf" "$CONFIG_DIR/dns-custom-catalog.conf"; do
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
            dnscrypt_test|system_dns_test) diagnostic_start "$2" ;;
            dnscrypt_log) diagnostic "$2" ;;
            status|doh_status|network_status|time_status|log) status_extra "$2" ;;
            runtime|page_meta|catalog|lan_devices|job|job_status|multi|set_ntp|update_check|update_background|uninstall|uninstall_status)
                exec "$LEGACY" "$@" ;;
            *) error 'Действие пока недоступно для dnscrypt-proxy2' ;;
        esac ;;
    *) exit 1 ;;
esac
