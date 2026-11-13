#!/bin/sh
# Only inside disposable OpenWrt, with a private PID namespace.
set -eu
[ "${DNSCRYPT_DISPOSABLE_LAB:-0}" = 1 ] || { echo 'Disposable lab required' >&2; exit 2; }
mkdir -p /var/run /var/lock /etc/rc.d
cat > /etc/init.d/dns-watchdog-lab <<'INIT'
#!/bin/sh /etc/rc.common
START=95
USE_PROCD=1
start_service() { procd_open_instance main; procd_set_param command /bin/sleep 1000; procd_close_instance; }
INIT
chmod 755 /etc/init.d/dns-watchdog-lab
/sbin/ubusd >/tmp/watchdog-ubus.log 2>&1 &
sleep 1
/sbin/procd -S >/tmp/watchdog-procd.log 2>&1 &
sleep 2
WATCHDOG_SERVICE_PATH=/etc/init.d/dns-watchdog-lab
export WATCHDOG_SERVICE_PATH
awk '/^watchdog_service_running\(\) \{/{p=1} /^watchdog_remove_legacy_daemon\(\) \{/{p=0} p{print}' /tmp/dns-manager.sh > /tmp/watchdog-functions.sh
. /tmp/watchdog-functions.sh
err_msg() { printf '%s\n' "$*" >&2; }
"$WATCHDOG_SERVICE_PATH" enable
"$WATCHDOG_SERVICE_PATH" start
watchdog_service_running
watchdog_service_enabled
watchdog_service_stop_disable
if watchdog_service_running || watchdog_service_enabled; then
    echo 'ERROR: watchdog service still running or enabled' >&2
    exit 1
fi
watchdog_service_stop_disable
echo 'PASS: procd watchdog stops, leaves autostart and can be stopped again'
