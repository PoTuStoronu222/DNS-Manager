#!/bin/sh
# DNS Manager LuCI 1.0 installer
# Installs only the LuCI layer and leaves DNS configuration untouched.
set -e

MANAGER="/usr/bin/dns-manager"
RPCD="/usr/libexec/rpcd/dns-manager"
ACL="/usr/share/rpcd/acl.d/luci-app-dns-manager.json"
MENU="/usr/share/luci/menu.d/luci-app-dns-manager.json"
VIEWDIR="/www/luci-static/resources/view/dns-manager"
LIBDIR="/www/luci-static/resources/dns-manager"

[ -x "$MANAGER" ] || { echo "ERROR: $MANAGER not found" >&2; exit 1; }

mkdir -p /usr/libexec/rpcd /usr/share/rpcd/acl.d /usr/share/luci/menu.d "$VIEWDIR" "$LIBDIR"

cat > "$RPCD" <<'RPC_EOF'
#!/bin/sh
. /usr/share/libubox/jshn.sh

MANAGER="/usr/bin/dns-manager"
JOBDIR="/tmp/dns-manager-luci"
mkdir -p "$JOBDIR"

json_error() {
    printf '{"ok":false,"error":"%s"}\n' "$1"
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/[[:cntrl:]]/ /g'
}

start_test() {
    local pidfile="$JOBDIR/test.pid" logfile="$JOBDIR/test.log" rcfile="$JOBDIR/test.rc"
    if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile" 2>/dev/null)" 2>/dev/null; then
        printf '{"started":true,"already_running":true}\n'
        return 0
    fi
    : > "$logfile"
    rm -f "$rcfile"
    (
        DNS_MANAGER_NO_UPDATE=1 "$MANAGER" api-test >"$logfile" 2>&1
        printf '%s\n' "$?" > "$rcfile"
        rm -f "$pidfile"
    ) &
    printf '%s\n' "$!" > "$pidfile"
    printf '{"started":true}\n'
}

test_status() {
    local running=false done=false rc=""
    if [ -f "$JOBDIR/test.pid" ] && kill -0 "$(cat "$JOBDIR/test.pid" 2>/dev/null)" 2>/dev/null; then running=true; fi
    [ -f "$JOBDIR/test.rc" ] && done=true && rc="$(cat "$JOBDIR/test.rc" 2>/dev/null)"
    printf '{"running":%s,"done":%s,"rc":"%s"}\n' "$running" "$done" "$(json_escape "$rc")"
}

test_log() {
    [ -f "$JOBDIR/test.log" ] || { printf '{"lines":""}\n'; return; }
    local x
    x="$(tail -n 220 "$JOBDIR/test.log" 2>/dev/null | sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\n/\\n/g;s/[\r\t]/ /g')"
    printf '{"lines":"%s"}\n' "$x"
}

call_method() {
    local method="$1" input
    input="$(cat)"
    json_load "$input" 2>/dev/null || true
    case "$method" in
        status)         "$MANAGER" api-status ;;
        system)         "$MANAGER" api-system ;;
        profiles)       "$MANAGER" api-profiles ;;
        profile_set)
            json_get_var profile profile
            "$MANAGER" api-profile-set "$profile"
            ;;
        watchdog_set)
            json_get_var enabled enabled
            json_get_var interval interval
            "$MANAGER" api-watchdog-set "$enabled" "$interval"
            ;;
        test_start)     start_test ;;
        test_status)    test_status ;;
        test_log)       test_log ;;
        *)              json_error "unknown_method"; return 1 ;;
    esac
}

list_methods() {
    json_init
    json_add_object "status"; json_close_object
    json_add_object "system"; json_close_object
    json_add_object "profiles"; json_close_object
    json_add_object "profile_set"; json_add_string "profile" "string"; json_close_object
    json_add_object "watchdog_set"; json_add_string "enabled" "string"; json_add_string "interval" "string"; json_close_object
    json_add_object "test_start"; json_close_object
    json_add_object "test_status"; json_close_object
    json_add_object "test_log"; json_close_object
    json_dump
}

case "$1" in
    list) list_methods ;;
    call) call_method "$2" ;;
    *) json_error "usage"; exit 1 ;;
esac
RPC_EOF
chmod 0755 "$RPCD"

cat > "$ACL" <<'ACL_EOF'
{
  "luci-app-dns-manager": {
    "description": "DNS Manager LuCI",
    "read": {
      "ubus": {
        "dns-manager": [
          "status",
          "system",
          "profiles",
          "test_status",
          "test_log"
        ]
      }
    },
    "write": {
      "ubus": {
        "dns-manager": [
          "profile_set",
          "watchdog_set",
          "test_start"
        ]
      }
    }
  }
}
ACL_EOF

cat > "$MENU" <<'MENU_EOF'
{
  "admin/services/dns-manager": {
    "title": "DNS Manager",
    "order": 61,
    "action": {
      "type": "alias",
      "path": "admin/services/dns-manager/dashboard"
    }
  },
  "admin/services/dns-manager/dashboard": {
    "title": "Дашборд",
    "order": 10,
    "action": { "type": "view", "path": "dns-manager/dashboard" }
  },
  "admin/services/dns-manager/dns": {
    "title": "DNS",
    "order": 20,
    "action": { "type": "view", "path": "dns-manager/dns" }
  },
  "admin/services/dns-manager/settings": {
    "title": "Настройки",
    "order": 30,
    "action": { "type": "view", "path": "dns-manager/settings" }
  }
}
MENU_EOF

cat > "$LIBDIR/common.js" <<'JS_EOF'
'use strict';
'require baseclass';
'require rpc';
'require ui';

var callStatus = rpc.declare({ object: 'dns-manager', method: 'status', expect: {} });
var callSystem = rpc.declare({ object: 'dns-manager', method: 'system', expect: {} });
var callProfiles = rpc.declare({ object: 'dns-manager', method: 'profiles', expect: {} });
var callProfileSet = rpc.declare({ object: 'dns-manager', method: 'profile_set', params: ['profile'], expect: {} });
var callWatchdogSet = rpc.declare({ object: 'dns-manager', method: 'watchdog_set', params: ['enabled', 'interval'], expect: {} });
var callTestStart = rpc.declare({ object: 'dns-manager', method: 'test_start', expect: {} });
var callTestStatus = rpc.declare({ object: 'dns-manager', method: 'test_status', expect: {} });
var callTestLog = rpc.declare({ object: 'dns-manager', method: 'test_log', expect: {} });

return baseclass.extend({
    status: callStatus,
    system: callSystem,
    profiles: callProfiles,
    profileSet: callProfileSet,
    watchdogSet: callWatchdogSet,
    testStart: callTestStart,
    testStatus: callTestStatus,
    testLog: callTestLog,

    injectCss: function() {
        var href = L.resource('view/dns-manager/style.css');
        if (!document.querySelector('link[data-dns-manager-css="1"]')) {
            var link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = href;
            link.setAttribute('data-dns-manager-css', '1');
            document.head.appendChild(link);
        }
    },

    toast: function(text, type) {
        ui.addNotification(null, E('p', {}, text), type || 'info');
    }
});
JS_EOF

cat > "$VIEWDIR/dashboard.js" <<'JS_EOF'
'use strict';
'require view';
'require ui';
'require dns-manager.common as dm';

return view.extend({
    load: function() {
        dm.injectCss();
        return Promise.all([dm.status(), dm.system()]);
    },

    render: function(all) {
        var self = this;
        var s = all[0] || {}, sys = all[1] || {};
        var wrap = E('div', { 'class': 'dm-wrap' });
        var title = E('div', { 'class': 'dm-head' }, [
            E('h2', {}, 'DNS Manager'),
            E('span', { 'class': 'dm-version' }, 'v' + (s.version || '—'))
        ]);
        var grid = E('div', { 'class': 'dm-grid' });

        function val(ok) { return ok ? '✓ работает' : '✗ нет'; }
        function card(name, value, state) {
            return E('div', { 'class': 'dm-card' }, [
                E('div', { 'class': 'dm-label' }, name),
                E('div', { 'class': state ? 'dm-good' : 'dm-bad' }, value)
            ]);
        }

        grid.appendChild(card('Профиль', s.profile || '—', true));
        grid.appendChild(card('LAN', s.lan_ip || '—', !!s.lan_ip));
        grid.appendChild(card('dnsmasq', val(s.dnsmasq_running), !!s.dnsmasq_running));
        grid.appendChild(card('HTTPS DNS Proxy', s.doh_running ? ('✓ ' + s.doh_total + ' серверов') : '✗ не работает', !!s.doh_running));
        grid.appendChild(card('QUIC', s.quic_applied ? '✓ применено' : '— выключено', true));
        grid.appendChild(card('Принудительный DNS', s.force_dns ? '✓ применено' : '— выключено', true));
        grid.appendChild(card('Балансировка', s.balancer_enabled ? '✓ включена' : '— выключена', true));
        grid.appendChild(card('Watchdog', s.watchdog_enabled ? ('✓ каждые ' + s.watchdog_interval + ' мин') : '— выключен', true));
        grid.appendChild(card('RAM', ((s.mem_available_kb || 0) / 1024).toFixed(1) + ' MB свободно', true));
        grid.appendChild(card('Load 1m', s.load1 || '—', true));
        grid.appendChild(card('DNS тест', (s.test_ok || 0) + ' / ' + (s.test_total || 0), true));
        grid.appendChild(card('nft', val(s.nft_active), !!s.nft_active));

        var actions = E('div', { 'class': 'dm-actions dm-card' }, [
            E('h3', {}, 'Действия'),
            E('button', { 'class': 'cbi-button cbi-button-action', 'click': function() {
                dm.testStart().then(function(r) {
                    dm.toast(r.already_running ? 'Проверка уже выполняется' : 'Проверка DNS запущена', 'info');
                });
            } }, 'Проверить DNS-серверы'),
            E('button', { 'class': 'cbi-button', 'click': function() {
                dm.status().then(function(x) { self.render([x, sys]); });
            } }, 'Обновить состояние')
        ]);

        var testLog = E('pre', { 'class': 'dm-log' }, '');
        var logCard = E('div', { 'class': 'dm-card' }, [E('h3', {}, 'Последняя проверка'), testLog]);
        dm.testLog().then(function(r) { testLog.textContent = r.lines || 'Проверка ещё не запускалась.'; });

        wrap.appendChild(title);
        wrap.appendChild(grid);
        wrap.appendChild(actions);
        wrap.appendChild(logCard);
        return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/dns.js" <<'JS_EOF'
'use strict';
'require view';
'require ui';
'require dns-manager.common as dm';

return view.extend({
    load: function() {
        dm.injectCss();
        return Promise.all([dm.status(), dm.profiles()]);
    },
    render: function(all) {
        var data = all[0] || {}, profiles = all[1] || {};
        var wrap = E('div', { 'class': 'dm-wrap' });
        var card = E('div', { 'class': 'dm-card' });
        var current = E('div', { 'class': 'dm-current' }, 'Текущий профиль: ' + (data.profile || '—'));
        card.appendChild(E('h3', {}, 'Профиль DNS'));
        card.appendChild(current);
        var grid = E('div', { 'class': 'dm-tiles' });
        (profiles.items || []).forEach(function(p) {
            grid.appendChild(E('button', {
                'class': 'cbi-button dm-tile' + (data.profile === p.id ? ' dm-active' : ''),
                'click': function() {
                    if (!confirm('Применить профиль «' + p.title + '»?')) return;
                    dm.profileSet(p.id).then(function(r) {
                        if (r.ok) dm.toast('Профиль применён: ' + p.title, 'info');
                        else dm.toast('Не удалось применить профиль', 'error');
                        window.location.reload();
                    });
                }
            }, p.title));
        });
        card.appendChild(grid);

        var slots = E('div', { 'class': 'dm-card' });
        slots.appendChild(E('h3', {}, 'Выбранные DNS'));
        (data.dns || []).forEach(function(d) {
            slots.appendChild(E('div', { 'class': 'dm-row' }, [
                E('span', { 'class': 'dm-slot' }, d.slot),
                E('span', {}, d.name || d.id),
                E('span', { 'class': 'dm-muted' }, '127.0.0.1:' + d.port)
            ]));
        });
        if (!(data.dns || []).length) slots.appendChild(E('div', { 'class': 'dm-muted' }, 'Выбранные DNS не обнаружены.'));

        wrap.appendChild(card);
        wrap.appendChild(slots);
        return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/settings.js" <<'JS_EOF'
'use strict';
'require view';
'require ui';
'require form';
'require dns-manager.common as dm';

return view.extend({
    load: function() { dm.injectCss(); return dm.status(); },
    render: function(s) {
        var wrap = E('div', { 'class': 'dm-wrap' });
        var card = E('div', { 'class': 'dm-card' });
        var enabled = E('input', { 'type': 'checkbox' });
        enabled.checked = !!s.watchdog_enabled;
        var interval = E('input', { 'type': 'number', 'min': 1, 'max': 59, 'value': s.watchdog_interval || 15, 'class': 'cbi-input-text' });
        var save = E('button', { 'class': 'cbi-button cbi-button-action', 'click': function() {
            dm.watchdogSet(enabled.checked ? '1' : '0', interval.value).then(function(r) {
                if (r.ok) dm.toast('Watchdog синхронизирован', 'info');
                else dm.toast('Не удалось изменить watchdog', 'error');
                setTimeout(function() { window.location.reload(); }, 600);
            });
        } }, 'Сохранить');
        card.appendChild(E('h3', {}, 'Автоматическая проверка DNS'));
        card.appendChild(E('label', { 'class': 'dm-check' }, [enabled, E('span', {}, 'Включена')]));
        card.appendChild(E('div', { 'class': 'dm-field' }, [E('label', {}, 'Интервал, минут'), interval]));
        card.appendChild(E('p', { 'class': 'dm-muted' }, 'Для профиля Hybrid watchdog является обязательной частью профиля и будет включён автоматически.'));
        card.appendChild(save);

        var info = E('div', { 'class': 'dm-card' }, [
            E('h3', {}, 'Системные возможности'),
            E('div', { 'class': 'dm-row' }, [E('span', {}, 'DNS кэш'), E('b', {}, s.dnsmasq_perf ? 'применён' : 'нет')]),
            E('div', { 'class': 'dm-row' }, [E('span', {}, 'NTP клиентов'), E('b', {}, s.ntp_clients ? 'применён' : 'нет')]),
            E('div', { 'class': 'dm-row' }, [E('span', {}, 'Client fixes'), E('b', {}, s.client_fixes ? 'применён' : 'нет')]),
            E('div', { 'class': 'dm-row' }, [E('span', {}, 'MSS/MTU'), E('b', {}, s.mtu_applied ? 'применён' : 'нет')])
        ]);
        wrap.appendChild(card);
        wrap.appendChild(info);
        return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/style.css" <<'CSS_EOF'
.dm-wrap { max-width: 1100px; display: flex; flex-direction: column; gap: 14px; }
.dm-head { display: flex; align-items: baseline; gap: 12px; }
.dm-head h2 { margin: 0; }
.dm-version, .dm-muted { opacity: .65; }
.dm-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); gap: 10px; }
.dm-card { border: 1px solid #bbb; border-radius: 8px; padding: 14px; background: var(--background-color, #fff); }
.dm-label { font-size: 12px; opacity: .65; margin-bottom: 6px; }
.dm-good { font-weight: 700; }
.dm-bad { font-weight: 700; }
.dm-actions { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
.dm-actions h3 { width: 100%; margin: 0 0 4px; }
.dm-log { min-height: 110px; max-height: 360px; overflow: auto; white-space: pre-wrap; font: 12px/1.45 monospace; }
.dm-tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap: 8px; margin-top: 12px; }
.dm-tile { min-height: 44px; white-space: normal; }
.dm-active { box-shadow: inset 0 0 0 2px currentColor; font-weight: 700; }
.dm-current { padding: 8px 10px; border-radius: 6px; background: rgba(128,128,128,.10); }
.dm-row { display: grid; grid-template-columns: 56px 1fr auto; gap: 12px; padding: 8px 0; border-bottom: 1px solid rgba(128,128,128,.18); align-items: center; }
.dm-slot { font-weight: 700; }
.dm-field { display: flex; gap: 10px; align-items: center; margin: 14px 0; }
.dm-field label { min-width: 150px; }
.dm-check { display: flex; gap: 8px; align-items: center; }
.dm-check input { width: 18px; height: 18px; }
@media (max-width: 700px) { .dm-row { grid-template-columns: 40px 1fr; } .dm-row > :last-child { grid-column: 2; } }
CSS_EOF

rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo "DNS Manager LuCI 1.0 installed."
