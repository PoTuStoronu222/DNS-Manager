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
valid_profile() { case "$1" in bypass|clean|security|privacy|adblock|family|all|dnssec|default) return 0;; *) return 1;; esac; }
engine_selected() { [ -r "$ENGINE_FILE" ] && [ "$(cat "$ENGINE_FILE" 2>/dev/null)" = dnscrypt-proxy2 ]; }
hdp_active() { [ -x "$HDP_INIT" ] && { "$HDP_INIT" enabled >/dev/null 2>&1 || "$HDP_INIT" running >/dev/null 2>&1; }; }
disable_legacy_watchdog() {
    watchdog_service_stop_disable || return 1
    # The init file can be missing while procd still owns a running instance.
    # Treat an unavailable or malformed procd response as unknown, not stopped.
    wd_reply=$(ubus -t 5 call service list '{"name":"dns-watchdog"}' 2>/dev/null) || return 1
    wd_root=$(jsonfilter -s "$wd_reply" -e '@' 2>/dev/null) || return 1
    case "$wd_root" in \{*\}) ;; *) return 1 ;; esac
    if jsonfilter -s "$wd_reply" -e "@['dns-watchdog']" >/dev/null 2>&1; then
        return 1
    else
        wd_rc=$?
        [ "$wd_rc" -eq 1 ] || return 1
    fi
    watchdog_cron_remove_owned_block || return 1
    if [ "${WATCHDOG_ENABLED:-0}" != 0 ] || [ "${WATCHDOG_AUTOREPLACE:-0}" != 0 ]; then
        WATCHDOG_ENABLED=0
        WATCHDOG_AUTOREPLACE=0
        save_config || return 1
    fi
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
    src=$(mktemp "$RUNTIME_DIR/dnscrypt-manager.XXXXXX") || exit 1
    sed '/^case "${1:-}" in$/,$d' "$MANAGER" > "$src" || { rm -f "$src"; exit 1; }
    # Manager functions are sourced exactly as in the existing LuCI backend.
    . "$src" || { rm -f "$src"; exit 1; }
    rm -f "$src"
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
                    fi
                    DNS_MANAGER_NO_UPDATE=1 SILENT_APPLY=1 dnscrypt_apply_profile_pool "$goal" 5053 "$BOOTSTRAP_DNS"
                ) > "$records"; then
                    state_profile=$goal
                    [ "$state_profile" != default ] || state_profile=none
                    if "$DNSCRYPT_INIT" enable &&
                       { printf 'profile=%s\n' "$state_profile"; sed 's/^/server=/' "$records"; } > "$state_tmp" &&
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
    src=$(mktemp "$RUNTIME_DIR/dnscrypt-manager.XXXXXX") || exit 1
    if sed '/^case "${1:-}" in$/,$d' "$MANAGER" > "$src" && . "$src"; then
        rm -f "$src"
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
                    rc=0
                fi
            fi
            release_mutation_lock
        fi
    else
        rm -f "$src"
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
    engine_selected || { error 'Выбран другой DNS-движок'; return; }
    . /usr/share/libubox/jshn.sh
    json_init
    if [ "$method" = dnscrypt_test ]; then
        output=$(timeout 12 nslookup -port=5053 ya.ru 127.0.0.1 2>&1); rc=$?
        if [ "$rc" -eq 0 ]; then json_add_boolean ok 1; else json_add_boolean ok 0; fi
    else
        output=$(logread -e dnscrypt-proxy 2>&1 | tail -n 80)
        json_add_boolean ok 1
    fi
    json_add_string output "$output"
    json_dump
}

status_extra() {
    method=$1
    input=$(cat)
    base=$(printf '%s' "$input" | "$LEGACY" call "$method") || { error 'Не удалось получить состояние'; return; }
    case "$base" in \{*\}) ;; *) error 'Некорректное состояние'; return;; esac
    . /usr/share/libubox/jshn.sh
    json_init
    json_add_string dnscrypt_engine dnscrypt-proxy2
    running=0
    "$DNSCRYPT_INIT" running >/dev/null 2>&1 && running=1
    json_add_int dnscrypt_running "$running"
    profile=$(sed -n 's/^profile=//p' "$STATE_FILE" 2>/dev/null | head -n1)
    valid_profile "$profile" || profile=none
    json_add_string dnscrypt_profile "$profile"
    json_add_array dnscrypt_servers
    if [ -r "$STATE_FILE" ]; then
        while IFS='|' read -r id url; do
            case "$id" in server=*) id=${id#server=};; *) continue;; esac
            case "$id" in ''|*[!A-Za-z0-9_-]*) continue;; esac
            json_add_string '' "$id"
        done < "$STATE_FILE"
    fi
    json_close_array
    extra=$(json_dump)
    base=${base%\}}
    extra=${extra#\{}
    printf '%s,%s\n' "$base" "$extra"
}

case "${1:-}" in
    worker) profile_worker "${2:-}" ;;
    reset_worker) reset_worker ;;
    list) exec "$LEGACY" list ;;
    call)
        case "${2:-}" in
            set_profile) profile_start ;;
            reset_dns) reset_start ;;
            switch_engine) switch_start ;;
            dnscrypt_test|dnscrypt_log) diagnostic "$2" ;;
            status|doh_status|network_status) status_extra "$2" ;;
            runtime|time_status|page_meta|catalog|lan_devices|job|log|update_check|uninstall_status)
                exec "$LEGACY" "$@" ;;
            *) error 'Действие пока недоступно для dnscrypt-proxy2' ;;
        esac ;;
    *) exit 1 ;;
esac
