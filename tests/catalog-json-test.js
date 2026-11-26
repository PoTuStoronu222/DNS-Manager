'use strict';

const assert = require('assert');
const fs = require('fs');
const { execFileSync } = require('child_process');

const source = fs.readFileSync('dns-manager-luci.sh', 'utf8');
const section = source.slice(source.indexOf('# A grouped page can contain hundreds of variants.'));
const match = section.match(/awk -F'\|' '\n([\s\S]*?)\n\s*' "\$_paged"/);
assert(match, 'grouped catalog JSON encoder not found');

const input = 'id1|clean|profile|DNS "тест" \\ server\tname|sdns://abc|us|active\n' +
  'id2|family|profile|DNS two|https://example.test/dns-query|global|\n';
const output = execFileSync('awk', ['-F|', match[1]], { input, encoding: 'utf8' });
const rows = JSON.parse('[' + output + ']');
assert.deepStrictEqual(rows[0], {
  id: 'id1', category: 'clean', name: 'DNS "тест" \\ server\tname',
  url: 'sdns://abc', region: 'us', catalog_status: 'active',
  ping: '', status: '', last_check: ''
});
assert.strictEqual(rows[1].id, 'id2');
assert.strictEqual(rows[1].catalog_status, '');
assert.strictEqual(rows[1].url, 'https://example.test/dns-query');
console.log('OK: grouped catalog JSON preserves server data and special characters');
