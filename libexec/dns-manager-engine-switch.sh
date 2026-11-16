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
cleanup() {
    trap - EXIT HUP INT TERM
    if [ "$success" != 1 ]; then
        if [ "$changed" = 1 ]; then
            echo 'Ошибка переключения. Восстанавливаю стандартный DNS.'
            if ! sh "$helpers/dns-manager-dnscrypt-dnsmasq.sh" clean 5053; then
                echo 'Не удалось подтвердить запуск dnsmasq; проверьте настройки DNS и системный журнал.'
            fi
            rm -f "$config_dir/dnscrypt-profile.state" || true
        fi
        printf 'result=fail\nstatus=failed\n' >> "$job_dir/state"
    else
        printf 'result=ok\nstatus=done\n' >> "$job_dir/state"
    fi
    printf 'finished=%s\n' "$(date +%s)" >> "$job_dir/state"
    [ "$locked" != 1 ] || release_mutation_lock
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
src=$(mktemp "$runtime/engine-manager.XXXXXX") || exit 1
if ! sed '/^case "${1:-}" in$/,$d' "$manager" > "$src"; then rm -f "$src"; exit 1; fi
. "$src" || { rm -f "$src"; exit 1; }
rm -f "$src"
preflight_readonly >/dev/null 2>&1 && init_dirs >/dev/null 2>&1 && load_config >/dev/null 2>&1 || exit 1
acquire_mutation_lock || { echo 'Другая операция DNS Manager уже выполняется.'; exit 1; }
locked=1
# Refuse a global UCI commit when another interface has staged changes.
for package in firewall https-dns-proxy; do
    pending=$(uci -q changes "$package" 2>/dev/null || true)
    [ -z "$pending" ] || { echo "Есть несохранённые изменения UCI: $package"; exit 1; }
done
watchdog_service_stop_disable || exit 1
wd_reply=$(ubus -t 5 call service list '{"name":"dns-watchdog"}' 2>/dev/null) || exit 1
wd_root=$(jsonfilter -s "$wd_reply" -e '@' 2>/dev/null) || exit 1
case "$wd_root" in \{*\}) ;; *) exit 1;; esac
if jsonfilter -s "$wd_reply" -e "@['dns-watchdog']" >/dev/null 2>&1; then
    echo 'DNS Watchdog ещё зарегистрирован в procd.'; exit 1
else
    wd_rc=$?; [ "$wd_rc" -eq 1 ] || exit 1
fi
watchdog_cron_remove_owned_block || exit 1
WATCHDOG_ENABLED=0; WATCHDOG_AUTOREPLACE=0
save_config || exit 1
echo 'Удаляю привязки устройств.'
sh "$helpers/dns-manager-device-detach.sh" || exit 1
changed=1
rollback_firewall_targeted || exit 1
echo 'Останавливаю DNS-службы.'
sh "$helpers/dns-manager-engine-services.sh" quiesce "$target" || exit 1
echo 'Восстанавливаю стандартный DNS.'
sh "$helpers/dns-manager-dnscrypt-dnsmasq.sh" clean 5053 || exit 1
SLOT_1_DOMAINS=''; SLOT_2_DOMAINS=''; SLOT_3_DOMAINS=''; SLOT_4_DOMAINS=''; SLOT_5_DOMAINS=''; SLOT_6_DOMAINS=''
REGIONAL_SAVED_ID=''; FORCE_DOH=0; BLOCK_EXTERNAL_DNS=0
clear_dns_core_runtime_state || exit 1
rm -f "$config_dir/dnscrypt-profile.state" "$CUSTOM_DNS_CATALOG" || exit 1
if [ "$target" = dnscrypt-proxy2 ]; then
    package=dnscrypt-proxy2; executable=${DNS_MANAGER_DNSCRYPT_BIN:-/usr/sbin/dnscrypt-proxy}
else
    package=https-dns-proxy; executable=${DNS_MANAGER_HDP_BIN:-/usr/sbin/https-dns-proxy}
fi
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
    if command -v apk >/dev/null 2>&1; then apk update && apk add "$package" || exit 1
    elif command -v opkg >/dev/null 2>&1; then opkg update && opkg install "$package" || exit 1
    else echo 'Менеджер пакетов не найден.'; exit 1; fi
    sh "$helpers/dns-manager-engine-services.sh" quiesce "$target" || exit 1
fi
if [ "$target" = dnscrypt-proxy2 ]; then
    # Package installation may replace the init script; install our boot guard afterwards.
    [ -r "$helpers/dns-manager-dnscrypt.init" ] || exit 1
    cp "$helpers/dns-manager-dnscrypt.init" "$init_dir/dnscrypt-proxy.new" || exit 1
    chmod 0755 "$init_dir/dnscrypt-proxy.new" && mv -f "$init_dir/dnscrypt-proxy.new" "$init_dir/dnscrypt-proxy" || exit 1
    echo 'Запускаю DNSCrypt и проверяю DNS.'
    bootstrap=$(printf '%s' "$BOOTSTRAP_DNS" | tr ',' '\n' | awk 'NF {if(n++) printf ","; printf "%s", $0; if(n==3) exit}')
    printf '%s\n' 'https://cloudflare-dns.com/dns-query' 'https://dns.google/dns-query' | sh "$helpers/dns-manager-dnscrypt-pool-apply.sh" 5053 "$bootstrap" || exit 1
    "$init_dir/dnscrypt-proxy" enable || exit 1
    sh "$helpers/dns-manager-dnscrypt-dnsmasq.sh" 5053 || exit 1
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
uci set "dns-manager.global.active_engine=$target" || exit 1
uci commit dns-manager || exit 1
tmp=$(mktemp "$config_dir/.dnscrypt-engine.XXXXXX") || exit 1
printf '%s\n' "$target" > "$tmp" && chmod 600 "$tmp" && mv -f "$tmp" "$engine_file" || { rm -f "$tmp"; exit 1; }
echo 'Движок переключён. Выберите DNS-профиль.'
success=1
