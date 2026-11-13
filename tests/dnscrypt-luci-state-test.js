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
vm.runInContext(section('function profileName(', 'function catName(') + section('function displayDnsRows(', 'function renderOverview('), ctx);
const current = { dnscrypt_engine:'dnscrypt-proxy2', dnscrypt_profile:'clean', dnscrypt_running:1,
  dnscrypt_servers:['cloudflare','google'], profile:'family', profile_mode:'profile', selection_category:'family',
  slots:[{id:'stale',slot:'1'}], doh_instances:[] };
assert.equal(ctx.activeProfileId(current), 'clean');
assert.equal(ctx.activeProfileLabel(current), 'Без фильтрации');
assert.equal(Array.from(ctx.displayDnsRows(current), x => x.id).join(','), 'cloudflare,google');
assert.equal(ctx.displayDnsRows(current)[0].slot, '');
current.dnscrypt_profile = 'none';
assert.equal(ctx.activeProfileId(current), '');
assert.equal(ctx.activeProfileLabel(current), 'Не выбран');
assert.equal(ctx.activeProfileId({profile:'clean'}), 'clean');
assert.equal(ctx.displayDnsRows({slots:[], doh_instances:[]}).length, 0);
console.log('PASS: DNSCrypt profile and pooled servers do not inherit legacy slots');
