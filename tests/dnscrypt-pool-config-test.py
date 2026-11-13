#!/usr/bin/env python3
"""Validate a single-process DNSCrypt configuration for several DoH endpoints."""
import base64
import pathlib
import subprocess
import tomllib

root = pathlib.Path(__file__).resolve().parent.parent
generator = root / 'libexec/dns-manager-dnscrypt-pool.sh'


def generate(urls, bootstrap='1.1.1.1,2606:4700:4700::1111'):
    return subprocess.run(['sh', str(generator), '5053', bootstrap],
                          input=urls, text=True, capture_output=True)


result = generate('https://dns.google/dns-query\nhttps://api.magicdns.ru/sync\n')
assert result.returncode == 0, result.stderr
config = tomllib.loads(result.stdout)
assert config['server_names'] == ['manager-1', 'manager-2']
assert config['listen_addresses'] == ['127.0.0.1:5053']
assert config['cache'] is True
assert config['cache_min_ttl'] == 0 and config['cache_neg_min_ttl'] == 0
assert config['bootstrap_resolvers'] == ['1.1.1.1:53', '[2606:4700:4700::1111]:53']
for name, host, path in [('manager-1', 'dns.google', '/dns-query'),
                         ('manager-2', 'api.magicdns.ru', '/sync')]:
    encoded = config['static'][name]['stamp'][7:]
    wire = base64.urlsafe_b64decode(encoded + '=' * (-len(encoded) % 4))
    n = wire[11]
    assert wire[12:12+n].decode() == host
    m = wire[12+n]
    assert wire[13+n:13+n+m].decode() == path

for urls, bootstrap in [('', '1.1.1.1'),
                        ('https://dns.google/\nhttps://dns.google\n', '1.1.1.1'),
                        ('https://dns.google/dns-query\nhttp://example.com/\n', '1.1.1.1'),
                        ('https://dns.google/dns-query\n', '127.0.0.1'),
                        (''.join(f'https://dns{i}.example/dns-query\n' for i in range(7)), '1.1.1.1')]:
    result = generate(urls, bootstrap)
    assert result.returncode != 0 and result.stdout == '', (urls, result.stdout, result.stderr)

print('Single-process DoH pool configuration and failure checks passed')
