#!/bin/sh
# DNS Manager LuCI
# Autonomous, self-contained LuCI installer/updater.
set -e

LUCI_VERSION="1.0.0"
RAW_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager-luci.sh"
MANAGER="/usr/bin/dns-manager"
RPCD="/usr/libexec/rpcd/dns-manager"
ACL="/usr/share/rpcd/acl.d/luci-app-dns-manager.json"
MENU="/usr/share/luci/menu.d/luci-app-dns-manager.json"
VIEWDIR="/www/luci-static/resources/view/dns-manager"
LIBDIR="/www/luci-static/resources/dns-manager"
UPDATER="/usr/libexec/dns-manager-luci-update"
CRON="/etc/crontabs/root"

[ -x "$MANAGER" ] || { echo "ERROR: $MANAGER not found" >&2; exit 1; }

mkdir -p /usr/libexec/rpcd /usr/share/rpcd/acl.d /usr/share/luci/menu.d "$VIEWDIR" "$LIBDIR"

cat > "$RPCD" <<'RPC_EOF'
#!/bin/sh
. /usr/share/libubox/jshn.sh
MANAGER="/usr/bin/dns-manager"

json_error() { printf '{"ok":false,"error":"%s"}\n' "$1"; }

call_method() {
    local method="$1" input
    input="$(cat 2>/dev/null)"
    json_load "$input" 2>/dev/null || true
    case "$method" in
        status) "$MANAGER" api-status ;;
        profiles) "$MANAGER" api-profiles ;;
        dns_catalog) "$MANAGER" api-dns-catalog ;;
        selected_dns) "$MANAGER" api-selected-dns ;;
        profile_set) json_get_var profile profile; "$MANAGER" api-profile-set "$profile" ;;
        slots_set)
            json_get_var s1 s1; json_get_var s2 s2; json_get_var s3 s3; json_get_var s4 s4
            json_get_var s5 s5; json_get_var s6 s6; json_get_var ru ru; json_get_var ru2 ru2
            "$MANAGER" api-slots-set "$s1" "$s2" "$s3" "$s4" "$s5" "$s6" "$ru" "$ru2"
            ;;
        toggle) json_get_var name name; json_get_var enabled enabled; "$MANAGER" api-toggle "$name" "$enabled" ;;
        ntp_set) json_get_var preset preset; "$MANAGER" api-ntp-set "$preset" ;;
        logs) "$MANAGER" api-logs ;;
        test_start) "$MANAGER" api-test-start ;;
        test_status) "$MANAGER" api-test-status ;;
        test_log) "$MANAGER" api-test-log ;;
        rollback) "$MANAGER" api-rollback ;;
        *) json_error "unknown_method"; return 1 ;;
    esac
}

list_methods() {
    json_init
    json_add_object "status"; json_close_object
    json_add_object "profiles"; json_close_object
    json_add_object "dns_catalog"; json_close_object
    json_add_object "selected_dns"; json_close_object
    json_add_object "profile_set"; json_add_string "profile" "string"; json_close_object
    json_add_object "slots_set"
      json_add_string "s1" "string"; json_add_string "s2" "string"; json_add_string "s3" "string"; json_add_string "s4" "string"
      json_add_string "s5" "string"; json_add_string "s6" "string"; json_add_string "ru" "string"; json_add_string "ru2" "string"
    json_close_object
    json_add_object "toggle"; json_add_string "name" "string"; json_add_string "enabled" "string"; json_close_object
    json_add_object "ntp_set"; json_add_string "preset" "string"; json_close_object
    json_add_object "logs"; json_close_object
    json_add_object "test_start"; json_close_object
    json_add_object "test_status"; json_close_object
    json_add_object "test_log"; json_close_object
    json_add_object "rollback"; json_close_object
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
          "profiles",
          "dns_catalog",
          "selected_dns",
          "logs",
          "test_status",
          "test_log"
        ]
      }
    },
    "write": {
      "ubus": {
        "dns-manager": [
          "profile_set",
          "slots_set",
          "toggle",
          "ntp_set",
          "test_start",
          "rollback"
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
  "admin/services/dns-manager/tests": {
    "title": "Проверка DNS",
    "order": 25,
    "action": { "type": "view", "path": "dns-manager/tests" }
  },
  "admin/services/dns-manager/settings": {
    "title": "Настройки",
    "order": 30,
    "action": { "type": "view", "path": "dns-manager/settings" }
  },
  "admin/services/dns-manager/logs": {
    "title": "Журнал и откат",
    "order": 40,
    "action": { "type": "view", "path": "dns-manager/logs" }
  }
}
MENU_EOF

cat > "$LIBDIR/common.js" <<'JS_EOF'
'use strict';
'require baseclass';
'require rpc';
'require ui';

var callStatus = rpc.declare({ object: 'dns-manager', method: 'status', expect: {} });
var callProfiles = rpc.declare({ object: 'dns-manager', method: 'profiles', expect: {} });
var callDnsCatalog = rpc.declare({ object: 'dns-manager', method: 'dns_catalog', expect: {} });
var callSelectedDns = rpc.declare({ object: 'dns-manager', method: 'selected_dns', expect: {} });
var callProfileSet = rpc.declare({ object: 'dns-manager', method: 'profile_set', params: ['profile'], expect: {} });
var callSlotsSet = rpc.declare({ object: 'dns-manager', method: 'slots_set', params: ['s1','s2','s3','s4','s5','s6','ru','ru2'], expect: {} });
var callToggle = rpc.declare({ object: 'dns-manager', method: 'toggle', params: ['name','enabled'], expect: {} });
var callNtpSet = rpc.declare({ object: 'dns-manager', method: 'ntp_set', params: ['preset'], expect: {} });
var callLogs = rpc.declare({ object: 'dns-manager', method: 'logs', expect: {} });
var callTestStart = rpc.declare({ object: 'dns-manager', method: 'test_start', expect: {} });
var callTestStatus = rpc.declare({ object: 'dns-manager', method: 'test_status', expect: {} });
var callTestLog = rpc.declare({ object: 'dns-manager', method: 'test_log', expect: {} });
var callRollback = rpc.declare({ object: 'dns-manager', method: 'rollback', expect: {} });

return baseclass.extend({
    status: callStatus,
    profiles: callProfiles,
    dnsCatalog: callDnsCatalog,
    selectedDns: callSelectedDns,
    profileSet: callProfileSet,
    slotsSet: callSlotsSet,
    toggle: callToggle,
    ntpSet: callNtpSet,
    logs: callLogs,
    testStart: callTestStart,
    testStatus: callTestStatus,
    testLog: callTestLog,
    rollback: callRollback,

    css: function() {
        var href = L.resource('view/dns-manager/style.css');
        if (!document.querySelector('link[data-dns-manager="1"]')) {
            var link = document.createElement('link');
            link.rel = 'stylesheet';
            link.href = href;
            link.setAttribute('data-dns-manager', '1');
            document.head.appendChild(link);
        }
    },

    toast: function(text, type) {
        ui.addNotification(null, E('p', {}, text), type || 'info');
    },

    reload: function() {
        return Promise.all([callStatus(), callSelectedDns()]);
    }
});
JS_EOF

cat > "$VIEWDIR/dashboard.js" <<'JS_EOF'
'use strict';
'require view';
'require dns-manager.common as dm';

return view.extend({
    load: function() {
        dm.css();
        return Promise.all([dm.status(), dm.selectedDns()]);
    },

    render: function(data) {
        var s = data[0] || {}, d = data[1] || {};
        var wrap = E('div', { 'class': 'dm-wrap' });
        var grid = E('div', { 'class': 'dm-grid' });

        function card(label, value, good) {
            return E('div', { 'class': 'dm-card' }, [
                E('div', { 'class': 'dm-label' }, label),
                E('div', { 'class': good ? 'dm-good' : 'dm-warn' }, value)
            ]);
        }

        var profileNames = {
            hybrid: 'Гибридный DNS',
            custom: 'Пользовательский профиль'
        };

        grid.appendChild(card('DNS Manager', 'v' + (s.version || '—'), true));
        grid.appendChild(card('Профиль', profileNames[s.profile] || s.profile || '—', true));
        grid.appendChild(card('LAN', s.lan_ip || '—', !!s.lan_ip));
        grid.appendChild(card('dnsmasq', s.dnsmasq ? '✓ работает' : '✗ нет', !!s.dnsmasq));
        grid.appendChild(card('HTTPS DNS Proxy', s.doh_running ? ('✓ работает • ' + s.doh_total + ' серверов') : '✗ нет', !!s.doh_running));
        grid.appendChild(card('IPv4', s.ipv4 ? '✓ работает' : '✗ нет', !!s.ipv4));
        grid.appendChild(card('IPv6', s.ipv6 ? '✓ включён' : '— выключен', true));
        grid.appendChild(card('QUIC', s.quic ? '✓ включён' : '— выключен', true));
        grid.appendChild(card('Force DNS', s.force_dns ? '✓ включён' : '— выключен', true));
        grid.appendChild(card('Балансировка', s.balancer ? '✓ включена' : '— выключена', true));
        grid.appendChild(card('Watchdog', s.watchdog ? ('✓ каждые ' + s.watchdog_interval + ' мин') : '— выключен', true));
        grid.appendChild(card('RAM', ((Number(s.mem_available_kb) || 0) / 1024).toFixed(1) + ' MB свободно', true));
        grid.appendChild(card('Load 1m', s.load1 || '—', true));
        grid.appendChild(card('nft', s.nft ? '✓ активен' : '—', !!s.nft));

        var slots = E('div', { 'class': 'dm-card' }, [
            E('h3', {}, 'Текущая схема DNS')
        ]);
        (d.items || []).forEach(function(x) {
            slots.appendChild(E('div', { 'class': 'dm-row' }, [
                E('span', { 'class': 'dm-slot' }, x.slot),
                E('span', {}, x.name || x.id),
                E('span', { 'class': 'dm-muted' }, '127.0.0.1:' + x.port)
            ]));
        });
        if (!(d.items || []).length)
            slots.appendChild(E('p', { 'class': 'dm-muted' }, 'DNS-схема пока не определена.'));

        wrap.appendChild(E('div', { 'class': 'dm-head' }, [
            E('h2', {}, 'DNS Manager'),
            E('span', { 'class': 'dm-version' }, 'LuCI ' + '1.0.0')
        ]));
        wrap.appendChild(grid);
        wrap.appendChild(slots);
        return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/dns.js" <<'JS_EOF'
'use strict';
'require view';
'require dns-manager.common as dm';

return view.extend({
    load: function() {
        dm.css();
        return Promise.all([dm.status(), dm.profiles(), dm.dnsCatalog(), dm.selectedDns()]);
    },

    render: function(data) {
        var self = this, s = data[0] || {}, profiles = data[1] || {}, catalog = data[2] || {}, selected = data[3] || {};
        var wrap = E('div', { 'class': 'dm-wrap' });
        var pCard = E('div', { 'class': 'dm-card' }, [E('h3', {}, 'Готовые профили')]);
        var pGrid = E('div', { 'class': 'dm-tiles' });

        (profiles.items || []).forEach(function(p) {
            pGrid.appendChild(E('button', {
                'class': 'cbi-button dm-tile' + ((s.profile === 'hybrid' && p.id === 'bypass') ? ' dm-active' : ''),
                'click': function() {
                    if (!confirm('Применить профиль «' + p.title + '»?')) return;
                    dm.profileSet(p.id).then(function(r) {
                        dm.toast(r.ok ? 'Профиль применён' : 'Не удалось применить профиль', r.ok ? 'info' : 'error');
                        if (r.ok) location.reload();
                    });
                }
            }, p.title));
        });
        pCard.appendChild(pGrid);

        var slotCard = E('div', { 'class': 'dm-card' });
        slotCard.appendChild(E('h3', {}, 'Ручная схема DNS'));
        var rows = {}, current = {};
        (selected.items || []).forEach(function(x) { current[x.slot] = x.id; });

        ['1','2','3','4','5','6','RU','RU_2'].forEach(function(slot) {
            var sel = E('select', { 'class': 'cbi-input-select' });
            var empty = E('option', { 'value': '' }, '— отключено —');
            sel.appendChild(empty);
            (catalog.items || []).forEach(function(x) {
                var opt = E('option', { 'value': x.id }, x.name + ' [' + x.category + ']');
                if (current[slot] === x.id) opt.selected = true;
                sel.appendChild(opt);
            });
            rows[slot] = sel;
            slotCard.appendChild(E('div', { 'class': 'dm-form-row' }, [
                E('label', {}, 'Слот ' + slot),
                sel
            ]));
        });

        var save = E('button', {
            'class': 'cbi-button cbi-button-action',
            'click': function() {
                dm.slotsSet(rows['1'].value, rows['2'].value, rows['3'].value, rows['4'].value,
                            rows['5'].value, rows['6'].value, rows['RU'].value, rows['RU_2'].value).then(function(r) {
                    dm.toast(r.ok ? 'Схема DNS применена' : 'Не удалось применить схему', r.ok ? 'info' : 'error');
                    if (r.ok) setTimeout(function(){ location.reload(); }, 700);
                });
            }
        }, 'Сохранить и применить');

        slotCard.appendChild(save);
        wrap.appendChild(pCard);
        wrap.appendChild(slotCard);
        return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/tests.js" <<'JS_EOF'
'use strict';
'require view';
'require ui';
'require dns-manager.common as dm';

return view.extend({
    load: function() {
        dm.css();
        return Promise.all([dm.status(), dm.testStatus(), dm.testLog()]);
    },

    render: function(data) {
        var status = data[0] || {}, ts = data[1] || {}, log = data[2] || {};
        var wrap = E('div', { 'class': 'dm-wrap' });
        var card = E('div', { 'class': 'dm-card' });
        var logEl = E('pre', { 'class': 'dm-log' }, log.lines || 'Проверка ещё не запускалась.');

        card.appendChild(E('h3', {}, 'Проверка DNS-серверов'));
        card.appendChild(E('p', { 'class': 'dm-muted' },
            'Полный тест использует защитные ограничения 2.06 по CPU/RAM и выполняется в фоне.'));
        card.appendChild(E('p', {}, 'Последний результат: ' +
            (status.test_ok || 0) + ' из ' + (status.test_total || 0)));

        var btn = E('button', {
            'class': 'cbi-button cbi-button-action',
            'click': function() {
                dm.testStart().then(function(r) {
                    dm.toast(r.started ? 'Проверка запущена' : 'Проверка уже выполняется', 'info');
                });
            }
        }, ts.running ? 'Проверка выполняется…' : 'Запустить полную проверку');

        card.appendChild(btn);
        card.appendChild(E('h4', {}, 'Журнал'));
        card.appendChild(logEl);
        wrap.appendChild(card);

        function poll() {
            dm.testStatus().then(function(x) {
                if (!x.running) {
                    dm.testLog().then(function(y) { logEl.textContent = y.lines || ''; });
                    return;
                }
                setTimeout(poll, 1800);
            });
        }
        if (ts.running) poll();
        return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/settings.js" <<'JS_EOF'
'use strict';
'require view';
'require dns-manager.common as dm';

return view.extend({
    load: function() {
        dm.css();
        return dm.status();
    },

    render: function(s) {
        s = s || {};
        var wrap = E('div', { 'class': 'dm-wrap' });

        var toggleNames = [
            ['quic','Блокировка QUIC'],
            ['mtu','Исправление сетевых параметров / MSS'],
            ['force','Принудительный DNS'],
            ['sysctl','Оптимизация TCP и Conntrack'],
            ['dnsmasq_perf','Кэширование DNS-запросов'],
            ['ntp_clients','Время для устройств сети'],
            ['client_fixes','Исправления телеметрии и связи'],
            ['watchdog','Автоматическая проверка DNS'],
            ['web_access','Доступ из браузера']
        ];
        var map = {
            quic:s.quic, mtu:s.mtu, force:s.force_dns, sysctl:s.sysctl,
            dnsmasq_perf:s.dnsmasq_perf, ntp_clients:s.ntp_clients,
            client_fixes:s.client_fixes, watchdog:s.watchdog, web_access:s.web_access
        };

        var card = E('div', { 'class': 'dm-card' }, [E('h3', {}, 'Модули')]);
        toggleNames.forEach(function(pair) {
            var id = pair[0];
            var cb = E('input', { 'type': 'checkbox' });
            cb.checked = !!map[id];
            card.appendChild(E('label', { 'class': 'dm-check-row' }, [
                cb, E('span', {}, pair[1])
            ]));
            cb.addEventListener('change', function() {
                var desired = cb.checked ? '1' : '0';
                dm.toggle(id, desired).then(function(r) {
                    dm.toast(r.ok ? pair[1] + ': обновлено' : pair[1] + ': ошибка',
                             r.ok ? 'info' : 'error');
                    if (!r.ok) cb.checked = !cb.checked;
                });
            });
        });

        var ntp = E('div', { 'class': 'dm-card' }, [
            E('h3', {}, 'Серверы точного времени')
        ]);
        var ntpSel = E('select', { 'class': 'cbi-input-select' });
        [
            ['cf_ip','Cloudflare'],
            ['nist_ip','NIST'],
            ['vniiftri_moscow','ВНИИФТРИ'],
            ['google_ip','Google']
        ].forEach(function(x) {
            var o = E('option', { 'value': x[0] }, x[1]);
            if (s.ntp_preset === x[0]) o.selected = true;
            ntpSel.appendChild(o);
        });
        ntp.appendChild(ntpSel);
        ntp.appendChild(E('button', {
            'class': 'cbi-button',
            'click': function() {
                dm.ntpSet(ntpSel.value).then(function(r) {
                    dm.toast(r.ok ? 'Набор NTP применён' : 'Ошибка NTP', r.ok ? 'info' : 'error');
                });
            }
        }, 'Применить NTP'));

        var upd = E('div', { 'class': 'dm-card' }, [
            E('h3', {}, 'Автоматическое обновление'),
            E('p', { 'class': 'dm-muted' },
              'LuCI-файл проверяется по SHA-256 каждые 6 часов и обновляется только после успешной проверки shell-синтаксиса.'),
            E('p', {}, 'Источник: ' + 'PoTuStoronu222/DNS-Manager'),
            E('p', { 'class': 'dm-muted' }, 'Установленная версия: LuCI 1.0.0')
        ]);

        wrap.appendChild(card);
        wrap.appendChild(ntp);
        wrap.appendChild(upd);
        return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/logs.js" <<'JS_EOF'
'use strict';
'require view';
'require dns-manager.common as dm';

return view.extend({
    load: function() { dm.css(); return dm.logs(); },

    render: function(data) {
        data = data || {};
        var wrap = E('div', { 'class': 'dm-wrap' });
        var log = E('pre', { 'class': 'dm-log' }, data.log || 'Лог пуст.');
        var tx = E('pre', { 'class': 'dm-log' }, data.tx || 'Транзакций нет.');

        var card1 = E('div', { 'class': 'dm-card' }, [
            E('h3', {}, 'Основной журнал'), log
        ]);

        var card2 = E('div', { 'class': 'dm-card' }, [
            E('h3', {}, 'Транзакции'), tx
        ]);

        var rollback = E('button', {
            'class': 'cbi-button cbi-button-negative',
            'click': function() {
                if (!confirm('Удалить изменения DNS Manager и выполнить откат?')) return;
                dm.rollback().then(function(r) {
                    dm.toast(r.ok ? 'Откат выполнен' : 'Откат завершился ошибкой',
                             r.ok ? 'info' : 'error');
                    if (r.ok) setTimeout(function(){ location.reload(); }, 900);
                });
            }
        }, 'Удалить изменения DNS Manager');

        var rb = E('div', { 'class': 'dm-card' }, [
            E('h3', {}, 'Откат'),
            E('p', { 'class': 'dm-muted' }, 'Возвращает исходное состояние в рамках механизма baseline/ownership DNS Manager.'),
            rollback
        ]);

        wrap.appendChild(card1);
        wrap.appendChild(card2);
        wrap.appendChild(rb);
        return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/style.css" <<'CSS_EOF'
.dm-wrap { display:flex; flex-direction:column; gap:16px; max-width:1150px; }
.dm-head { display:flex; align-items:center; justify-content:space-between; gap:12px; }
.dm-version,.dm-muted { opacity:.72; }
.dm-grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(190px,1fr)); gap:10px; }
.dm-card { padding:15px; border:1px solid rgba(127,127,127,.3); border-radius:8px; background:var(--background-color,#fff); box-shadow:0 1px 2px rgba(0,0,0,.05); }
.dm-label { font-size:.86rem; opacity:.72; margin-bottom:7px; }
.dm-good { font-weight:600; }
.dm-warn { font-weight:600; }
.dm-row { display:grid; grid-template-columns:60px 1fr 150px; gap:10px; padding:8px 0; border-bottom:1px solid rgba(127,127,127,.18); }
.dm-row:last-child { border-bottom:0; }
.dm-slot { font-weight:700; }
.dm-tiles { display:grid; grid-template-columns:repeat(auto-fit,minmax(180px,1fr)); gap:9px; margin-top:12px; }
.dm-tile { min-height:48px; }
.dm-active { font-weight:700; outline:2px solid rgba(0,0,0,.2); }
.dm-form-row { display:grid; grid-template-columns:120px 1fr; gap:12px; align-items:center; margin:10px 0; }
.dm-form-row label { font-weight:600; }
.dm-check-row { display:flex; align-items:center; gap:10px; padding:9px 0; border-bottom:1px solid rgba(127,127,127,.16); }
.dm-check-row:last-child { border-bottom:0; }
.dm-log { max-height:500px; overflow:auto; white-space:pre-wrap; word-break:break-word; font-size:.82rem; margin-top:10px; }
CSS_EOF

cat > "$UPDATER" <<'UPD_EOF'
#!/bin/sh
set -eu

RAW_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager-luci.sh"
TARGET="/usr/bin/dns-manager-luci-install"
LOCK="/tmp/dns-manager-luci-update.lock"
TMP="/tmp/dns-manager-luci-update.$$"

if ! mkdir "$LOCK" 2>/dev/null; then exit 0; fi
trap 'rm -rf "$LOCK" "$TMP" 2>/dev/null' EXIT INT TERM

fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 5 --max-time 20 -o "$TMP" "$RAW_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 20 -O "$TMP" "$RAW_URL"
    else
        return 1
    fi
}

fetch || exit 0
[ -s "$TMP" ] || exit 0
head -n1 "$TMP" | grep -q '^#!/bin/sh$' || exit 0
sh -n "$TMP" >/dev/null 2>&1 || exit 0

if command -v sha256sum >/dev/null 2>&1; then
    NEW="$(sha256sum "$TMP" | awk '{print $1}')"
    OLD=""
    [ -f "$TARGET" ] && OLD="$(sha256sum "$TARGET" 2>/dev/null | awk '{print $1}')"
    [ -n "$OLD" ] && [ "$NEW" = "$OLD" ] && exit 0
fi

cp "$TMP" "$TARGET"
chmod 0755 "$TARGET"
DNS_MANAGER_LUCI_UPDATE=1 "$TARGET"
UPD_EOF
chmod 0755 "$UPDATER"

# Keep a callable installer copy for manual recovery.
cp "$0" /usr/bin/dns-manager-luci-install
chmod 0755 /usr/bin/dns-manager-luci-install

# Keep exactly one updater entry. It is deliberately separate from the DNS
# Manager's 15-minute watchdog so a UI update cannot increase watchdog load.
mkdir -p "$(dirname "$CRON")"
[ -f "$CRON" ] || : > "$CRON"
_tmp_cron="${CRON}.dns-manager-luci.$$"
awk '
    /DNS_MANAGER_LUCI_UPDATE_BEGIN/ {skip=1; next}
    /DNS_MANAGER_LUCI_UPDATE_END/ {skip=0; next}
    !skip {print}
' "$CRON" > "$_tmp_cron"
{
    printf '%s\n' '# DNS_MANAGER_LUCI_UPDATE_BEGIN'
    printf '%s\n' '17 */6 * * * /usr/libexec/dns-manager-luci-update >/dev/null 2>&1'
    printf '%s\n' '# DNS_MANAGER_LUCI_UPDATE_END'
} >> "$_tmp_cron"
mv "$_tmp_cron" "$CRON"

rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

echo "DNS Manager LuCI ${LUCI_VERSION} installed."
