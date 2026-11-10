#!/bin/sh
# Regression: role hints are presentation-only, catalog IDs/URLs stay intact.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
node <<'EOF_NODE'
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const luci = fs.readFileSync('dns-manager-luci.sh', 'utf8');
const catalog = fs.readFileSync('catalogs/dns-8.7-RU-NOSOCIAL.conf', 'utf8');
const records = catalog.split('\n').filter(x => x && !x.startsWith('#')).map(x => x.split('|'));
assert.strictEqual(records.length, 116, 'catalog entries were removed');
assert.strictEqual(new Set(records.map(x => x[0])).size, 116, 'catalog IDs are no longer unique');
assert.ok(catalog.includes('# DNSCATREV=14'), 'catalog revision changed');
assert.ok(luci.includes(`printf ',"tags":'; json_quote "$_prof"`), 'catalog tags were not exported additively');
assert.ok(luci.includes(`printf ',"category":'; json_quote "$_cat"`), 'legacy catalog category is missing');
assert.ok(luci.includes(`['gaming','Игровые DNS']`), 'existing gaming label contract changed');

const begin = luci.indexOf('var DNS_CATEGORY_HELP='), end = luci.indexOf('function ping(', begin);
assert.ok(begin > 0 && end > begin, 'guidance helper block not found');
const ctx = vm.createContext({
  E: (tag, attrs, children) => ({tag, attrs, children}),
});
vm.runInContext(luci.slice(begin, end), ctx, {timeout: 1000});
const categories = ['all','bypass','clean','security','privacy','adblock','family','gaming','regional','custom'];
for (const c of categories) assert.ok(ctx.dnsCategoryHint(c).length > 24, 'category lacks guidance: ' + c);
for (const c of ['bypass','clean','security','privacy','adblock','family','dnssec'])
  assert.ok(ctx.dnsProfileHint(c).length > 24, 'profile lacks guidance: ' + c);
assert.ok(ctx.dnsTagSummary('ads+tracking+malware').includes('Реклама'), 'tag mapping failed');
assert.ok(ctx.dnsTagSummary('').length === 0, 'old RPC without tags must still work');
assert.ok(ctx.dnsCardNote({id:'mullvad_family'}).includes('02.11.2026'), 'Mullvad warning missing');
assert.ok(ctx.dnsCardNote({id:'mullvad_all'}).includes('02.11.2026'), 'Mullvad warning missing');
assert.ok(ctx.dnsCardNote({category:'bypass',catalog_status:'verified-published-current'}).includes('VPN'), 'bypass warning missing');
const notice = JSON.stringify(ctx.dnsJurisdictionNotice());
for (const term of ['юрисдикцию РФ','ТСПУ','DoH/DoT','политику логирования'])
  assert.ok(notice.includes(term), 'jurisdiction note is incomplete: ' + term);
assert.ok(luci.includes('dnsJurisdictionNotice(),'), 'catalog must display notice');
assert.ok(luci.includes('dnsTagSummary(d.tags)||dnsCategoryHint(d.category)'), 'catalog lacks per-DNS role hints');
assert.ok(luci.includes('dnsTagSummary(x.tags)||dnsCategoryHint(x.category)'), 'slot picker lacks role hints');
console.log('OK: LuCI DNS role guidance, jurisdiction note, backward-compatible tags and catalog count');
EOF_NODE
