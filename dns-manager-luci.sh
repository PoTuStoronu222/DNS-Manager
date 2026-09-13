#!/bin/sh
# DNS Manager LuCI — full autonomous installer/updater
set -eu

LUCI_VERSION="2.0.0"
RAW_URL="https://raw.githubusercontent.com/PoTuStoronu222/DNS-Manager/main/dns-manager-luci.sh"
MANAGER="/usr/bin/dns-manager"
ROOT="/usr/lib/dns-manager-luci"
RPCD="/usr/libexec/rpcd/dns-manager"
ACL="/usr/share/rpcd/acl.d/luci-app-dns-manager.json"
MENU="/usr/share/luci/menu.d/luci-app-dns-manager.json"
VIEWDIR="/www/luci-static/resources/view/dns-manager"
LIBDIR="/www/luci-static/resources/dns-manager"
UPDATER="/usr/libexec/dns-manager-luci-update"
INSTALLER="/usr/bin/dns-manager-luci-install"
REMOVER="/usr/bin/dns-manager-luci-remove"
CRON="/etc/crontabs/root"
CRON_BEGIN="# DNS_MANAGER_LUCI_UPDATE_BEGIN"
CRON_END="# DNS_MANAGER_LUCI_UPDATE_END"

[ -x "$MANAGER" ] || { echo "ERROR: $MANAGER not found" >&2; exit 1; }

mkdir -p "$ROOT" /usr/libexec/rpcd /usr/share/rpcd/acl.d /usr/share/luci/menu.d "$VIEWDIR" "$LIBDIR"

cat > "$RPCD" <<'RPC_EOF'
#!/bin/sh
. /usr/share/libubox/jshn.sh
MANAGER="/usr/bin/dns-manager"

call_method() {
    local method="$1" input
    input="$(cat 2>/dev/null)"
    json_load "$input" 2>/dev/null || true
    case "$method" in
        status) "$MANAGER" api-status ;;
        system) "$MANAGER" api-system ;;
        settings) "$MANAGER" api-settings ;;
        profiles) "$MANAGER" api-profiles ;;
        dns_catalog) "$MANAGER" api-dns-catalog ;;
        selected_dns) "$MANAGER" api-selected-dns ;;
        doh) "$MANAGER" api-doh ;;
        profile_set) json_get_var profile profile; "$MANAGER" api-profile-set "$profile" ;;
        slots_set)
            json_get_var s1 s1; json_get_var s2 s2; json_get_var s3 s3; json_get_var s4 s4
            json_get_var s5 s5; json_get_var s6 s6; json_get_var ru ru; json_get_var ru2 ru2
            "$MANAGER" api-slots-set "$s1" "$s2" "$s3" "$s4" "$s5" "$s6" "$ru" "$ru2" ;;
        toggle) json_get_var name name; json_get_var enabled enabled; "$MANAGER" api-toggle "$name" "$enabled" ;;
        ntp_status) "$MANAGER" api-ntp-status ;;
        ntp_set) json_get_var preset preset; "$MANAGER" api-ntp-set "$preset" ;;
        logs) "$MANAGER" api-logs ;;
        test_start) "$MANAGER" api-test-start ;;
        test_status) "$MANAGER" api-test-status ;;
        test_log) "$MANAGER" api-test-log ;;
        test_results) "$MANAGER" api-test-results ;;
        rollback) "$MANAGER" api-rollback ;;
        diagnostics) "$MANAGER" api-diagnostics ;;
        *) printf '%s\n' '{"ok":false,"error":"unknown_method"}'; return 1 ;;
    esac
}

list_methods() {
    json_init
    json_add_object "status"; json_close_object
    json_add_object "system"; json_close_object
    json_add_object "settings"; json_close_object
    json_add_object "profiles"; json_close_object
    json_add_object "dns_catalog"; json_close_object
    json_add_object "selected_dns"; json_close_object
    json_add_object "doh"; json_close_object
    json_add_object "profile_set"; json_add_string "profile" "string"; json_close_object
    json_add_object "slots_set"
      json_add_string "s1" "string"; json_add_string "s2" "string"; json_add_string "s3" "string"; json_add_string "s4" "string"
      json_add_string "s5" "string"; json_add_string "s6" "string"; json_add_string "ru" "string"; json_add_string "ru2" "string"
    json_close_object
    json_add_object "toggle"; json_add_string "name" "string"; json_add_string "enabled" "string"; json_close_object
    json_add_object "ntp_status"; json_close_object
    json_add_object "ntp_set"; json_add_string "preset" "string"; json_close_object
    json_add_object "logs"; json_close_object
    json_add_object "test_start"; json_close_object
    json_add_object "test_status"; json_close_object
    json_add_object "test_log"; json_close_object
    json_add_object "test_results"; json_close_object
    json_add_object "rollback"; json_close_object
    json_add_object "diagnostics"; json_close_object
    json_dump
}

case "$1" in
    list) list_methods ;;
    call) call_method "$2" ;;
    *) printf '%s\n' '{"ok":false,"error":"usage"}'; exit 1 ;;
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
          "status", "system", "settings", "profiles", "dns_catalog", "selected_dns", "doh",
          "ntp_status", "logs", "test_status", "test_log", "test_results", "diagnostics"
        ]
      }
    },
    "write": {
      "ubus": {
        "dns-manager": [
          "profile_set", "slots_set", "toggle", "ntp_set", "test_start", "rollback"
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
    "action": { "type": "alias", "path": "admin/services/dns-manager/dashboard" }
  },
  "admin/services/dns-manager/dashboard": {
    "title": "Дашборд",
    "order": 10,
    "action": { "type": "view", "path": "dns-manager/dashboard" }
  },
  "admin/services/dns-manager/dns": {
    "title": "Профили DNS",
    "order": 20,
    "action": { "type": "view", "path": "dns-manager/dns" }
  },
  "admin/services/dns-manager/slots": {
    "title": "Серверы DNS",
    "order": 30,
    "action": { "type": "view", "path": "dns-manager/slots" }
  },
  "admin/services/dns-manager/test": {
    "title": "Проверка DNS",
    "order": 40,
    "action": { "type": "view", "path": "dns-manager/test" }
  },
  "admin/services/dns-manager/ntp": {
    "title": "Точное время (NTP)",
    "order": 50,
    "action": { "type": "view", "path": "dns-manager/ntp" }
  },
  "admin/services/dns-manager/settings": {
    "title": "Настройки",
    "order": 60,
    "action": { "type": "view", "path": "dns-manager/settings" }
  },
  "admin/services/dns-manager/diagnostics": {
    "title": "Диагностика",
    "order": 70,
    "action": { "type": "view", "path": "dns-manager/diagnostics" }
  },
  "admin/services/dns-manager/logs": {
    "title": "Журнал и откат",
    "order": 80,
    "action": { "type": "view", "path": "dns-manager/logs" }
  }
}
MENU_EOF

cat > "$LIBDIR/common.js" <<'JS_EOF'
'use strict';
'require baseclass';
'require rpc';
'require ui';

function decl(method, params) {
    return rpc.declare({ object: 'dns-manager', method: method, params: params || [], expect: {} });
}

var api = {
    status: decl('status'), system: decl('system'), settings: decl('settings'), profiles: decl('profiles'),
    dnsCatalog: decl('dns_catalog'), selectedDns: decl('selected_dns'), doh: decl('doh'),
    profileSet: decl('profile_set', ['profile']), slotsSet: decl('slots_set', ['s1','s2','s3','s4','s5','s6','ru','ru2']),
    toggle: decl('toggle', ['name','enabled']), ntpStatus: decl('ntp_status'), ntpSet: decl('ntp_set', ['preset']),
    logs: decl('logs'), testStart: decl('test_start'), testStatus: decl('test_status'), testLog: decl('test_log'),
    testResults: decl('test_results'), rollback: decl('rollback'), diagnostics: decl('diagnostics')
};

return baseclass.extend({
    status: api.status, system: api.system, settings: api.settings, profiles: api.profiles,
    dnsCatalog: api.dnsCatalog, selectedDns: api.selectedDns, doh: api.doh, profileSet: api.profileSet,
    slotsSet: api.slotsSet, toggle: api.toggle, ntpStatus: api.ntpStatus, ntpSet: api.ntpSet,
    logs: api.logs, testStart: api.testStart, testStatus: api.testStatus, testLog: api.testLog,
    testResults: api.testResults, rollback: api.rollback, diagnostics: api.diagnostics,
    css: function() {
        var href = L.resource('view/dns-manager/style.css');
        if (!document.querySelector('link[data-dns-manager-css="1"]')) {
            var link = document.createElement('link');
            link.rel = 'stylesheet'; link.href = href;
            link.setAttribute('data-dns-manager-css', '1'); document.head.appendChild(link);
        }
    },
    toast: function(text, type) { ui.addNotification(null, E('p', {}, text), type || 'info'); },
    escText: function(x) { return x == null ? '' : String(x); }
});
JS_EOF

cat > "$VIEWDIR/dashboard.js" <<'JS_EOF'
'use strict';
'require view';
'require dns-manager.common as dm';

return view.extend({
    load: function() { dm.css(); return Promise.all([dm.status(), dm.system(), dm.settings(), dm.selectedDns()]); },
    render: function(a) {
        var s=a[0]||{}, sys=a[1]||{}, cfg=a[2]||{}, dns=a[3]||{}, wrap=E('div',{'class':'dm-wrap'});
        var grid=E('div',{'class':'dm-grid'});
        function card(label,val,cl){ return E('div',{'class':'dm-card'},[E('div',{'class':'dm-label'},label),E('div',{'class':cl||'dm-value'},String(val==null?'—':val))]); }
        function sw(v){ return v ? '✓ работает' : '✗ нет'; }
        grid.appendChild(card('Версия менеджера','v'+(s.version||'—')));
        grid.appendChild(card('Профиль',s.profile||'—'));
        grid.appendChild(card('LAN',s.lan_ip||'—'));
        grid.appendChild(card('WAN',sys.wan_proto||'—'));
        grid.appendChild(card('IPv4',sw(s.ipv4),s.ipv4?'dm-good':'dm-bad'));
        grid.appendChild(card('IPv6',sw(s.ipv6),s.ipv6?'dm-good':'dm-muted'));
        grid.appendChild(card('dnsmasq',sw(s.dnsmasq),s.dnsmasq?'dm-good':'dm-bad'));
        grid.appendChild(card('HTTPS DNS Proxy',(s.doh_running?'✓ работает':'✗ нет')+' / '+(s.doh_total||0)));
        grid.appendChild(card('nft',sw(s.nft),s.nft?'dm-good':'dm-bad'));
        grid.appendChild(card('RAM свободно',((Number(s.mem_available_kb)||0)/1024).toFixed(1)+' MB'));
        grid.appendChild(card('Load 1m',s.load1||'—'));
        grid.appendChild(card('Watchdog',s.watchdog?'✓ каждые '+s.watchdog_interval+' мин':'выключен'));
        var cfgRows=E('div',{'class':'dm-card'});
        cfgRows.appendChild(E('h3',{},'Настройки DNS Manager'));
        [['Балансировка DNS',cfg.balancer],['Разделение .ru/.su/.рф',cfg.tld_split],['Блокировка QUIC',cfg.quic],['MSS / сеть',cfg.mtu],['Принудительный DNS',cfg.force_dns],['TCP / Conntrack',cfg.sysctl],['DNS-кэш',cfg.dnsmasq_perf],['NTP для клиентов',cfg.ntp_clients],['Исправления клиентов',cfg.client_fixes],['Web-доступ',cfg.web_access]].forEach(function(x){
            cfgRows.appendChild(E('div',{'class':'dm-row'},[E('span',{},x[0]),E('span',{'class':x[1]?'dm-good':'dm-muted'},x[1]?'✓ включено':'— выключено')]));
        });
        var slots=E('div',{'class':'dm-card'}); slots.appendChild(E('h3',{},'Выбранные DNS'));
        (dns.items||[]).forEach(function(d){ slots.appendChild(E('div',{'class':'dm-row'},[E('span',{'class':'dm-slot'},d.slot),E('span',{},d.name||d.id),E('span',{'class':'dm-muted'},'127.0.0.1:'+d.port)])); });
        wrap.appendChild(E('div',{'class':'dm-head'},[E('h2',{},'DNS Manager'),E('span',{'class':'dm-muted'},sys.model||'OpenWrt')]));
        wrap.appendChild(grid); wrap.appendChild(cfgRows); wrap.appendChild(slots);
        return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/dns.js" <<'JS_EOF'
'use strict';
'require view';
'require dns-manager.common as dm';

return view.extend({
    load:function(){ dm.css(); return Promise.all([dm.status(),dm.profiles()]); },
    render:function(a){
        var s=a[0]||{}, p=a[1]||{}, wrap=E('div',{'class':'dm-wrap'});
        var card=E('div',{'class':'dm-card'},[E('h3',{},'Готовые профили'),E('p',{'class':'dm-muted'},'Выбор профиля использует штатную транзакционную логику DNS Manager.')]);
        var grid=E('div',{'class':'dm-tiles'});
        (p.items||[]).forEach(function(x){ grid.appendChild(E('button',{'class':'cbi-button dm-tile'+(s.profile===x.id?' dm-active':''),'click':function(){
            if(!confirm('Применить профиль «'+x.title+'»?')) return;
            dm.profileSet(x.id).then(function(r){ dm.toast(r.ok?'Профиль применён':'Ошибка применения',r.ok?'info':'error'); setTimeout(function(){location.reload();},600); });
        }},x.title)); });
        card.appendChild(grid); wrap.appendChild(card);
        return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/slots.js" <<'JS_EOF'
'use strict';
'require view';
'require dns-manager.common as dm';

return view.extend({
    load:function(){ dm.css(); return Promise.all([dm.selectedDns(),dm.dnsCatalog()]); },
    render:function(a){
        var cur=a[0]||{}, cat=a[1]||{}, wrap=E('div',{'class':'dm-wrap'}), card=E('div',{'class':'dm-card'});
        card.appendChild(E('h3',{},'Ручная настройка DNS'));
        card.appendChild(E('p',{'class':'dm-muted'},'Слоты 1–6 работают как общий пул Hybrid; RU и RU2 — региональные маршруты.'));
        var values={}; (cur.items||[]).forEach(function(d){ values[d.slot]=d.id; });
        var fields=['1','2','3','4','5','6','RU','RU_2']; var selects={};
        fields.forEach(function(slot){
            var sel=E('select',{'class':'cbi-input-select dm-select'}); selects[slot]=sel;
            sel.appendChild(E('option',{'value':''},'— не выбран —'));
            (cat.items||[]).forEach(function(d){
                var o=E('option',{'value':d.id},d.name+' ['+d.category+']'); if(values[slot]===d.id)o.selected=true; sel.appendChild(o);
            });
            card.appendChild(E('div',{'class':'dm-form-row'},[E('label',{},'Слот '+slot),sel]));
        });
        var buttons=E('div',{'class':'dm-actions'},[
            E('button',{'class':'cbi-button cbi-button-action','click':function(){
                dm.slotsSet(selects['1'].value,selects['2'].value,selects['3'].value,selects['4'].value,selects['5'].value,selects['6'].value,selects['RU'].value,selects['RU_2'].value).then(function(r){ dm.toast(r.ok?'DNS сохранены и применены':'Ошибка применения DNS',r.ok?'info':'error'); });
            }},'Сохранить и применить DNS'),
            E('button',{'class':'cbi-button','click':function(){location.reload();}},'Отменить изменения')
        ]);
        card.appendChild(buttons); wrap.appendChild(card); return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/test.js" <<'JS_EOF'
'use strict';
'require view';
'require dns-manager.common as dm';

return view.extend({
    load:function(){ dm.css(); return Promise.all([dm.testResults(),dm.testStatus(),dm.testLog()]); },
    render:function(a){
        var self=this, wrap=E('div',{'class':'dm-wrap'}), state=a[1]||{}, log=E('pre',{'class':'dm-log'},(a[2]||{}).lines||'');
        var stats=E('div',{'class':'dm-card'}), table=E('div',{'class':'dm-card'});
        function renderResults(r){
            table.innerHTML=''; table.appendChild(E('h3',{},'Результаты'));
            (r.items||[]).forEach(function(x){
                table.appendChild(E('div',{'class':'dm-row'},[E('span',{},x.name),E('span',{},x.category_text),E('span',{},x.ms && x.ms!=='-1'?x.ms+' мс':'—'),E('span',{'class':x.status==='OK'?'dm-good':'dm-bad'},x.status_text)]));
            });
        }
        function refresh(){ Promise.all([dm.testStatus(),dm.testResults(),dm.testLog()]).then(function(x){ state=x[0]||{}; log.textContent=(x[2]||{}).lines||''; var ok=(x[1]&&x[1].items||[]).filter(function(i){return i.status==='OK';}).length; stats.textContent='Состояние: '+(state.running?'проверка выполняется':'готово')+' • OK: '+ok+' / '+((x[1]&&x[1].items||[]).length); renderResults(x[1]||{}); if(state.running)setTimeout(refresh,1500); }); }
        stats.appendChild(E('p',{},state.running?'Проверка выполняется':'Проверка не запущена'));
        stats.appendChild(E('button',{'class':'cbi-button cbi-button-action','click':function(){ dm.testStart().then(function(){dm.toast('Проверка DNS запущена','info'); refresh();}); }},'Запустить полную проверку'));
        table.appendChild(E('h3',{},'Результаты')); renderResults(a[0]||{});
        wrap.appendChild(stats); wrap.appendChild(table); wrap.appendChild(E('div',{'class':'dm-card'},[E('h3',{},'Лог проверки'),log]));
        return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/ntp.js" <<'JS_EOF'
'use strict';
'require view';
'require dns-manager.common as dm';

return view.extend({
    load:function(){ dm.css(); return dm.ntpStatus(); },
    render:function(s){
        var wrap=E('div',{'class':'dm-wrap'}), card=E('div',{'class':'dm-card'});
        card.appendChild(E('h3',{},'Серверы точного времени'));
        card.appendChild(E('p',{},'Текущий набор: '+(s.preset||'не выбран')));
        card.appendChild(E('pre',{'class':'dm-log'},s.servers||'(не настроены)'));
        var grid=E('div',{'class':'dm-tiles'});
        [['cf_ip','Cloudflare'],['nist_ip','NIST'],['vniiftri_moscow','ВНИИФТРИ'],['google_ip','Google']].forEach(function(x){ grid.appendChild(E('button',{'class':'cbi-button dm-tile','click':function(){dm.ntpSet(x[0]).then(function(r){dm.toast(r.ok?'Набор NTP применён':'Ошибка NTP',r.ok?'info':'error');setTimeout(function(){location.reload();},500);});}},x[1])); });
        card.appendChild(grid); wrap.appendChild(card); return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/settings.js" <<'JS_EOF'
'use strict';
'require view';
'require dns-manager.common as dm';

return view.extend({
    load:function(){ dm.css(); return dm.settings(); },
    render:function(c){
        var wrap=E('div',{'class':'dm-wrap'}), card=E('div',{'class':'dm-card'});
        var items=[
          ['quic','Блокировка QUIC'],['mtu','Исправление сетевых параметров / MSS'],['force','Принудительный DNS'],
          ['sysctl','Оптимизация TCP и Conntrack'],['dnsmasq_perf','Кэширование DNS-запросов'],['ntp_clients','Время для устройств сети'],
          ['client_fixes','Исправления телеметрии и связи'],['watchdog','Автоматическая проверка DNS'],['web_access','Доступ из браузера']
        ];
        card.appendChild(E('h3',{},'Настройки DNS Manager'));
        items.forEach(function(x){
            var key=x[0], input=E('input',{'type':'checkbox'}); input.checked=!!c[key];
            if(key==='watchdog' && c.profile==='hybrid') input.checked=true;
            var row=E('div',{'class':'dm-check-row'},[input,E('span',{},x[1])]);
            input.addEventListener('change',function(){ dm.toggle(key,input.checked?'1':'0').then(function(r){ if(!r.ok){input.checked=!input.checked;dm.toast('Не удалось изменить настройку','error');} else dm.toast(x[1]+(input.checked?' включено':' выключено'),'info'); }); });
            card.appendChild(row);
        });
        if(c.profile==='hybrid') card.appendChild(E('p',{'class':'dm-hint'},'Hybrid принудительно держит watchdog включённым штатной логикой DNS Manager.'));
        wrap.appendChild(card); return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/diagnostics.js" <<'JS_EOF'
'use strict';
'require view';
'require dns-manager.common as dm';

return view.extend({
    load:function(){ dm.css(); return Promise.all([dm.system(),dm.diagnostics(),dm.doh()]); },
    render:function(a){
        var s=a[0]||{}, d=a[1]||{}, doh=a[2]||{}, wrap=E('div',{'class':'dm-wrap'}), grid=E('div',{'class':'dm-grid'});
        function c(t,v){return E('div',{'class':'dm-card'},[E('div',{'class':'dm-label'},t),E('div',{},String(v==null?'—':v))]);}
        [['Модель',s.model],['OpenWrt',s.openwrt],['Target',s.target],['Архитектура',s.arch],['Firewall',s.firewall],['LAN',s.lan_ip],['WAN',s.wan_proto],['MemAvailable',((Number(d.mem_available_kb)||0)/1024).toFixed(1)+' MB'],['Load',d.load],['/tmp',d.tmp_kb],['/',d.root_kb],['dnsmasq PID',d.dnsmasq_pids],['https-dns-proxy PID',d.https_dns_proxy_pids],['DNS cron',d.dns_manager_cron_entries]].forEach(function(x){grid.appendChild(c(x[0],x[1]));});
        var dc=E('div',{'class':'dm-card'}); dc.appendChild(E('h3',{},'https-dns-proxy')); (doh.items||[]).forEach(function(x){dc.appendChild(E('div',{'class':'dm-row'},[E('span',{},'port '+x.port),E('span',{},x.url),E('span',{'class':x.running?'dm-good':'dm-bad'},x.running?'✓':'✗')]));});
        wrap.appendChild(grid); wrap.appendChild(dc); return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/logs.js" <<'JS_EOF'
'use strict';
'require view';
'require dns-manager.common as dm';

return view.extend({
    load:function(){dm.css();return dm.logs();},
    render:function(l){
        var wrap=E('div',{'class':'dm-wrap'}), rollback=E('div',{'class':'dm-card'});
        var main=E('pre',{'class':'dm-log'},l.log||''), tx=E('pre',{'class':'dm-log'},l.tx||'');
        rollback.appendChild(E('h3',{},'Откат')); rollback.appendChild(E('p',{'class':'dm-muted'},'Удаляет только изменения, которые находятся под baseline/ownership DNS Manager.'));
        rollback.appendChild(E('button',{'class':'cbi-button cbi-button-negative','click':function(){if(!confirm('Выполнить откат DNS Manager?'))return;dm.rollback().then(function(r){dm.toast(r.ok?'Откат выполнен':'Ошибка отката',r.ok?'info':'error');});}},'Удалить изменения DNS Manager'));
        wrap.appendChild(E('div',{'class':'dm-card'},[E('h3',{},'Основной журнал'),main]));
        wrap.appendChild(E('div',{'class':'dm-card'},[E('h3',{},'Транзакции'),tx])); wrap.appendChild(rollback); return wrap;
    }
});
JS_EOF

cat > "$VIEWDIR/style.css" <<'CSS_EOF'
.dm-wrap{display:flex;flex-direction:column;gap:14px;max-width:1200px}.dm-head{display:flex;justify-content:space-between;align-items:center}.dm-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(185px,1fr));gap:10px}.dm-card{padding:15px;border:1px solid rgba(127,127,127,.28);border-radius:8px;background:var(--background-color,#fff)}.dm-label{font-size:.82rem;opacity:.7;margin-bottom:6px}.dm-value{font-weight:600}.dm-good{font-weight:600}.dm-bad{font-weight:600}.dm-muted{opacity:.7}.dm-row{display:grid;grid-template-columns:minmax(130px,1fr) minmax(180px,2fr) minmax(100px,1fr);gap:10px;padding:8px 0;border-bottom:1px solid rgba(127,127,127,.16);align-items:center}.dm-row:last-child{border-bottom:0}.dm-slot{font-weight:700}.dm-tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(190px,1fr));gap:9px;margin-top:10px}.dm-tile{min-height:48px}.dm-active{font-weight:700;outline:2px solid rgba(127,127,127,.35)}.dm-form-row{display:grid;grid-template-columns:180px 1fr;gap:12px;align-items:center;margin:10px 0}.dm-select{width:100%}.dm-check-row{display:flex;gap:10px;align-items:center;padding:10px 0;border-bottom:1px solid rgba(127,127,127,.16)}.dm-log{max-height:500px;overflow:auto;white-space:pre-wrap;word-break:break-word;font-size:.82rem}.dm-actions{display:flex;flex-wrap:wrap;gap:9px;margin-top:12px}.dm-hint{opacity:.78;font-size:.9rem}
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
fetch(){
    if command -v curl >/dev/null 2>&1; then curl -fsSL --connect-timeout 5 --max-time 25 -o "$TMP" "$RAW_URL";
    elif command -v wget >/dev/null 2>&1; then wget -q -T 25 -O "$TMP" "$RAW_URL";
    else return 1; fi
}
fetch || exit 0
[ -s "$TMP" ] || exit 0
head -n1 "$TMP" | grep -q '^#!/bin/sh$' || exit 0
sh -n "$TMP" >/dev/null 2>&1 || exit 0
if command -v sha256sum >/dev/null 2>&1; then
    NEW="$(sha256sum "$TMP" | awk '{print $1}')"; OLD=""
    [ -f "$TARGET" ] && OLD="$(sha256sum "$TARGET" 2>/dev/null | awk '{print $1}')"
    [ -n "$OLD" ] && [ "$NEW" = "$OLD" ] && exit 0
fi
cp "$TMP" "$TARGET"; chmod 0755 "$TARGET"
DNS_MANAGER_LUCI_UPDATE=1 "$TARGET"
UPD_EOF
chmod 0755 "$UPDATER"

cat > "$REMOVER" <<'RM_EOF'
#!/bin/sh
set -eu
CRON="/etc/crontabs/root"
BEGIN="# DNS_MANAGER_LUCI_UPDATE_BEGIN"; END="# DNS_MANAGER_LUCI_UPDATE_END"
TMP="${CRON}.dns-manager-luci-remove.$$"
# Only remove files owned by DNS Manager LuCI. Never remove /www/luci-static as a whole,
# never remove rpcd itself, and never touch /etc/config/luci or system LuCI packages.
for f in \
  /usr/libexec/rpcd/dns-manager \
  /usr/share/rpcd/acl.d/luci-app-dns-manager.json \
  /usr/share/luci/menu.d/luci-app-dns-manager.json \
  /usr/libexec/dns-manager-luci-update \
  /usr/bin/dns-manager-luci-install \
  /usr/bin/dns-manager-luci-remove; do
  rm -f "$f"
done
rm -rf /usr/lib/dns-manager-luci /www/luci-static/resources/view/dns-manager /www/luci-static/resources/dns-manager /tmp/dns-manager-luci
if [ -f "$CRON" ]; then
  awk -v b="$BEGIN" -v e="$END" ' $0==b{skip=1;next} $0==e{skip=0;next} !skip{print} ' "$CRON" > "$TMP"
  mv "$TMP" "$CRON"
fi
/etc/init.d/rpcd reload >/dev/null 2>&1 || true
rm -f /tmp/luci-indexcache 2>/dev/null || true
exit 0
RM_EOF
chmod 0755 "$REMOVER"

# Keep an exact recovery copy of the installer itself.
cp "$0" "$INSTALLER"
chmod 0755 "$INSTALLER"

# Record ownership explicitly for auditing; this file is inside our private namespace.
cat > "$ROOT/manifest" <<MAN_EOF
/usr/libexec/rpcd/dns-manager
/usr/share/rpcd/acl.d/luci-app-dns-manager.json
/usr/share/luci/menu.d/luci-app-dns-manager.json
/usr/libexec/dns-manager-luci-update
/usr/bin/dns-manager-luci-install
/usr/bin/dns-manager-luci-remove
/usr/lib/dns-manager-luci
/www/luci-static/resources/view/dns-manager
/www/luci-static/resources/dns-manager
MAN_EOF
printf '%s\n' "$LUCI_VERSION" > "$ROOT/version"

# Exactly one updater cron block; unrelated cron entries remain untouched.
mkdir -p /etc/crontabs
[ -f "$CRON" ] || : > "$CRON"
TMP_CRON="${CRON}.dns-manager-luci.$$"
awk -v b="$CRON_BEGIN" -v e="$CRON_END" ' $0==b{skip=1;next} $0==e{skip=0;next} !skip{print} ' "$CRON" > "$TMP_CRON"
{
  printf '%s\n' "$CRON_BEGIN"
  printf '%s\n' '17 */6 * * * /usr/libexec/dns-manager-luci-update >/dev/null 2>&1'
  printf '%s\n' "$CRON_END"
} >> "$TMP_CRON"
mv "$TMP_CRON" "$CRON"

/etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
rm -f /tmp/luci-indexcache 2>/dev/null || true

echo "DNS Manager LuCI ${LUCI_VERSION} installed."
