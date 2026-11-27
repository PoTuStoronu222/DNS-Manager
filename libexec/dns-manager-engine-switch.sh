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
# Download DNSCrypt while the current DNS path is still available. Resetting
# dnsmasq first can remove the only resolver able to reach package feeds.
if [ "$target" = dnscrypt-proxy2 ] && [ ! -x "$executable" ]; then
    echo "Устанавливаю $package до сброса текущего DNS."
    package_was_missing=0
    package_is_installed "$package" || package_was_missing=1
    printf 'phase=Загрузка и установка пакета…\n' >> "$job_dir/state"
    if [ "$PKG_MGR" = apk ]; then
        apk add "$package" || { printf 'phase=Обновление списка пакетов…\n' >> "$job_dir/state"; apk update && apk add "$package"; } || install_error="Не удалось установить пакет $package. Текущие настройки DNS сохранены; проверьте интернет и репозитории."
    elif [ "$PKG_MGR" = opkg ]; then
        opkg install "$package" || { printf 'phase=Обновление списка пакетов…\n' >> "$job_dir/state"; opkg update && opkg install "$package"; } || install_error="Не удалось установить пакет $package. Текущие настройки DNS сохранены; проверьте интернет и репозитории."
    else
        install_error='Менеджер пакетов не найден.'
    fi
    [ -z "$install_error" ] || exit 1
    [ -x "$executable" ] || { install_error="Пакет $package установлен, но исполняемый файл не найден."; exit 1; }
    if [ "$package_was_missing" = 1 ]; then
        touch "$PACKAGE_OWNERSHIP" && { grep -Fqx -- "$package" "$PACKAGE_OWNERSHIP" || printf '%s\n' "$package" >> "$PACKAGE_OWNERSHIP"; } || echo 'Не удалось записать установленный пакет.'
    fi
    # Package installation may enable or start its own service.
    if [ -x "$init_dir/dnscrypt-proxy" ]; then
        "$init_dir/dnscrypt-proxy" disable || exit 1
        if "$init_dir/dnscrypt-proxy" running >/dev/null 2>&1; then
            "$init_dir/dnscrypt-proxy" stop || exit 1
        fi
    fi
fi
if [ "$target" = dnscrypt-proxy2 ] && [ "$(uci -q get dns-manager.global.hdp_query_log 2>/dev/null || :)" = 1 ]; then
    sh /usr/lib/dns-manager-luci/backend.sh hdp_query_cleanup || { echo 'Не удалось выключить журнал запросов dnsmasq.'; exit 1; }
fi
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
    uci set 'https-dns-proxy.config.dnsmasq_config_update=*' || exit 1
    uci commit https-dns-proxy || exit 1
    sh "$helpers/dns-manager-engine-services.sh" start https-dns-proxy || exit 1
    [ "$(uci -q get 'dhcp.@dnsmasq[0].noresolv')" = 1 ] || exit 1
    port1=$(uci -q get 'https-dns-proxy.@https-dns-proxy[0].listen_port') || exit 1
    port2=$(uci -q get 'https-dns-proxy.@https-dns-proxy[1].listen_port') || exit 1
    for port in "$port1" "$port2"; do
        case "$port" in ''|*[!0-9]*) exit 1 ;; esac
        case " $(uci -q get 'dhcp.@dnsmasq[0].server') " in *" 127.0.0.1#$port "*) ;; *) exit 1 ;; esac
    done
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
