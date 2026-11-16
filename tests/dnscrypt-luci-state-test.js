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
ctx.state = {busy:false};
ctx.window = {dmLanDevices:{ok:true,devices:[]}};
ctx.btn = (label, style, action, options) => ({label,style,action,options});
vm.runInContext(section('function renderSlots(', 'function settingCard('), ctx);
for (const [fn, selector] of [['renderSlots', '#dm-slots'], ['renderDeviceDns', '#dm-devices']]) {
  const panel = {innerHTML:'old', children:[], appendChild(node) { this.children.push(node); }};
  const root = {querySelector(value) { assert.equal(value, selector); return panel; }};
  const status = {dnscrypt_engine:'dnscrypt-proxy2', get slots() { throw Error('legacy slots read'); }};
  ctx[fn](root, status);
  assert.equal(panel.innerHTML, '');
  assert.equal(panel.children.length, 1);
  assert.match(panel.children[0].children[0].text, fn === 'renderSlots' ? /общего набора/ : /DNS роутера/);
  assert(panel.children[0].children.some(x => x.label === (fn === 'renderSlots' ? 'Проверить DNS' : 'Обновить список')));
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
ctx.renderDoH({querySelector: () => panel}, {engine_installed:0, slots:[], doh_instances:[]});
const choices=panel.children[0].children[1].text;
assert.equal(choices.length, 2);
assert.equal(choices[0].text[2].label, 'Установить');
assert.equal(choices[1].text[2].label, 'Установить');
assert.equal(panel.children.length, 2);
assert.equal(panel.children[0].title, 'DNS-движок');
console.log('PASS: fresh installation offers engine installation without inactive DoH controls');

ctx.row = (label, value) => ({label,value});
ctx.state.dnscryptDiagnosticKind='log';
ctx.state.dnscryptDiagnostic='journal';
const panel2 = {innerHTML:'', children:[], appendChild(node) { this.children.push(node); }};
const root2 = {querySelector: () => panel2};
const dnscryptState = {dnscrypt_engine:'dnscrypt-proxy2', dnscrypt_running:1, dnscrypt_servers:['cloudflare'], dnscrypt_server_names:{cloudflare:'Cloudflare'}, dnscrypt_profile:'clean'};
ctx.renderDoH(root2, dnscryptState);
const details=panel2.children[1].children;
const actions=details.find(x => x && x.attrs && x.attrs.class==='dm-actions');
const close=actions.text.find(x => x.label==='Скрыть журнал');
assert(close);
close.action();
assert.equal(ctx.state.dnscryptDiagnostic, '');
assert.equal(ctx.state.dnscryptDiagnosticKind, '');
console.log('PASS: DNSCrypt journal can be closed');
