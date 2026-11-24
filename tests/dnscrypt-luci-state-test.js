'use strict';
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const script = fs.readFileSync('dns-manager-luci.sh', 'utf8');
const common = script.split("<<'EOF_COMMON'\n")[1].split('\nEOF_COMMON\n')[0];
new Function(common); // LuCI module is wrapped by the loader.
function section(start, end) {
  const a = common.indexOf(start), b = common.indexOf(end, a);
  assert(a >= 0 && b > a);
  return common.slice(a, b);
}
const ctx = { PROFILE: [['clean', 'Без фильтрации']], checkInfo: () => ({}) };
vm.createContext(ctx);
vm.runInContext(section('function profileName(', 'function catName(') + section('function dnscryptServerName(', 'function renderOverview('), ctx);
const current = { dnscrypt_engine:'dnscrypt-proxy2', dnscrypt_profile:'clean', dnscrypt_running:1,
  dnscrypt_servers:['cloudflare','google'], profile:'family', profile_mode:'profile', selection_category:'family',
  slots:[{id:'stale',slot:'1'}], doh_instances:[] };
assert.equal(ctx.activeProfileId(current), 'clean');
assert.equal(ctx.activeProfileLabel(current), 'Без фильтрации');
assert.equal(Array.from(ctx.displayDnsRows(current), x => x.id).join(','), 'cloudflare,google');
assert.equal(ctx.displayDnsRows(current)[0].slot, '');
current.dnscrypt_server_names = {cloudflare:'Cloudflare'};
assert.equal(ctx.displayDnsRows(current)[0].name, 'Cloudflare');
assert.equal(ctx.displayDnsRows(current)[1].name, 'google');
current.dnscrypt_profile = 'none';
assert.equal(ctx.activeProfileId(current), '');
assert.equal(ctx.activeProfileLabel(current), 'Не выбран');
assert.equal(ctx.activeProfileId({profile:'clean'}), 'clean');
assert.equal(ctx.displayDnsRows({slots:[], doh_instances:[]}).length, 0);
ctx.E = (tag, attrs, text) => ({tag, attrs, text});
ctx.card = (title, children) => ({title, children});
ctx.state = {busy:false,openSections:{}};
ctx.badge = (type, text) => ({type,text});
ctx.row = (label, value) => ({label,value});
ctx.foldSection = (key,title,content) => ({key,title,content});
ctx.window = {dmLanDevices:{ok:true,devices:[]}};
ctx.btn = (label, style, action, options) => ({label,style,action,options});
ctx.selectDnscryptServer = (id) => { ctx.selectedServer=id; };
vm.runInContext(section('function dnscryptLatencyBadge(', 'function renderDoH('), ctx);
vm.runInContext(section('function renderSlots(', 'function settingCard('), ctx);
let info=ctx.dnsPoolInfo({dnscrypt_engine:'dnscrypt-proxy2',dnscrypt_servers:['one'],dnscrypt_server_checks:{one:'OK:5'}});
assert.equal(info[0].value.text,'Выбрано в DNS Manager: 1');
assert(info.some(x => x && /резервного сервера/.test(x.text || '')));
info=ctx.dnsPoolInfo({dnscrypt_engine:'dnscrypt-proxy2',dnscrypt_servers:['one','two'],dnscrypt_server_checks:{one:'fail',two:'fail'}});
assert.equal(info[0].value.text,'Выбрано в DNS Manager: 2');
assert(!info.some(x => x && /резервного сервера/.test(x.text || '')));
info=ctx.dnsPoolInfo({slots:[],doh_instances:[{port:'5053'},{port:'5054'}]});
assert.equal(info[0].value.text,'Нет данных о выбранном наборе');
info=ctx.dnsPoolInfo({dnscrypt_engine:'dnscrypt-proxy2'});
assert.equal(info[0].value.text,'Нет данных о выбранном наборе');
info=ctx.dnsPoolInfo({dnscrypt_engine:'dnscrypt-proxy2',dnscrypt_running:0,dnscrypt_servers:['one']});
assert.equal(info[0].value.text,'Выбрано в DNS Manager: 1');
assert(info.some(x => x && /резервного сервера/.test(x.text || '')));
info=ctx.dnsPoolInfo({slots:[{slot:'1',id:'a',port:'5053'},{slot:'2',id:'b',port:'5054'},{slot:'RU',id:'c',port:'5055'}]});
assert.equal(info[0].value.text,'Выбрано в DNS Manager: 2');
assert(!info.some(x => x && /резервного сервера/.test(x.text || '')));
for (const [value,expected] of [['on','включён в настройках dnsmasq'],['off','выключен в настройках dnsmasq'],[undefined,'нет данных']]) {
  info=ctx.dnsPoolInfo({slots:[{slot:'1',id:'a',port:'5053'},{slot:'RU',id:'b',port:'5054'}],dnsmasq_allservers:value});
  assert.equal(info[0].value.text,'Выбрано в DNS Manager: 1');
  assert(info.some(x => x && /резервного сервера/.test(x.text || '')));
  assert.equal(info.find(x=>x.label==='Одновременный опрос DNS').value.text,expected);
}
for (const [fn, selector] of [['renderSlots', '#dm-slots'], ['renderDeviceDns', '#dm-devices']]) {
  const panel = {innerHTML:'old', children:[], appendChild(node) { this.children.push(node); }};
  const root = {querySelector(value) { assert.equal(value, selector); return panel; }};
  const status = {dnscrypt_engine:'dnscrypt-proxy2', get slots() { throw Error('legacy slots read'); }};
  ctx[fn](root, status);
  assert.equal(panel.innerHTML, '');
  assert.equal(panel.children.length, 1);
  if(fn==='renderSlots') {
    assert.equal(panel.children[0].title, 'DNS-серверы');
    assert(panel.children[0].children.some(x => x.attrs && x.attrs.class==='dm-pool-buttons'));
  } else {
    assert.match(panel.children[0].children[0].text, /DNS роутера/);
    assert(panel.children[0].children.some(x => x.label === 'Обновить список'));
  }
}
console.log('PASS: DNSCrypt profile and pooled servers do not inherit legacy slots');

// The fresh-install screen offers installation without showing DoH controls.
ctx.state = {busy:false,jobRunning:false};
ctx.badge = (type, text) => ({type,text});
ctx.btn = (label, style, action, options) => ({label,style,action,options});
ctx.resumeEngine = () => {};
ctx.appendUninstall = children => children.push({label:'Удалить'});
vm.runInContext(section('function renderDoH(', 'function renderSlots(').split('function renderSlots(')[0], ctx);
const panel = {innerHTML:'', children:[], appendChild(node) { this.children.push(node); }};
const uninstall = {innerHTML:'', children:[], appendChild(node) { this.children.push(node); }};
ctx.renderDoH({querySelector: id => id === '#dm-doh' ? panel : uninstall}, {engine_installed:0, slots:[], doh_instances:[]});
const choices=panel.children[0].children[1].text;
assert.equal(choices.length, 2);
assert.equal(choices[0].text[0].text[1].text, 'Установить');
assert.equal(choices[1].text[0].text[1].text, 'Установить');
assert.equal(panel.children.length, 1);
assert.equal(uninstall.children[0].title, 'Удаление DNS Manager');
assert(common.includes("doh:['dm-header','dm-doh','dm-profiles','dm-uninstall']"));
assert.equal(panel.children[0].title, 'DNS-движок');
console.log('PASS: fresh installation offers engine installation without inactive DoH controls');

ctx.row = (label, value) => ({label,value});
ctx.yes = value => String(value) === '1';
ctx.settingFeedback = () => null;
const panel2 = {innerHTML:'', children:[], appendChild(node) { this.children.push(node); }};
const dnscryptState = {dnscrypt_engine:'dnscrypt-proxy2', dnscrypt_running:1, dnscrypt_servers:['cloudflare'], dnscrypt_server_names:{cloudflare:'Cloudflare'}, dnscrypt_profile:'clean', dnscrypt_server_latency:{'manager-1':48}};
ctx.renderDoH({querySelector: id => id === '#dm-doh' ? panel2 : null}, dnscryptState);
assert.notEqual(panel2.children[1].title, 'Браузеры и DNS');
const details=panel2.children[1].children;
const serverList=details.find(x => x && x.attrs && x.attrs.class==='dm-doh-list');
assert.equal(serverList.text[0].text[0].text,'Cloudflare');
assert.equal(serverList.text[0].text[1].text,'48 мс · замер DNSCrypt · время неизвестно');
const actions=details.find(x => x && x.attrs && x.attrs.class==='dm-actions');
assert(actions.text.some(x => x.label==='Проверить DNS'));
assert(!actions.text.some(x => /журнал/i.test(x.label)));
console.log('PASS: DNSCrypt latency is shown next to the server');
