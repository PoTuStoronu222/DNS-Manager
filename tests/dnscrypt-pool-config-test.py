#!/usr/bin/env python3
"""Validate a single-process DNSCrypt configuration for several DoH endpoints."""
import base64
import os
import pathlib
import subprocess
import tempfile
import tomllib

root = pathlib.Path(__file__).resolve().parent.parent
generator = root / 'libexec/dns-manager-dnscrypt-pool.sh'


def generate(urls, bootstrap='1.1.1.1,2606:4700:4700::1111'):
    return subprocess.run(['sh', str(generator), '5053', bootstrap],
                          input=urls, text=True, capture_output=True)


result = generate('https://dns.google/dns-query\nhttps://api.magicdns.ru/sync\n')
assert result.returncode == 0, result.stderr
config = tomllib.loads(result.stdout)
assert config['lb_strategy'] == 'wp2'
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

native = (root / 'libexec/dns-manager-dnscrypt-catalog.conf').read_text().splitlines()[2].split('|')[4]
with tempfile.TemporaryDirectory() as cache:
    env = {**os.environ, 'DNS_MANAGER_AUTO_CATALOG': '1', 'DNS_MANAGER_SOURCE_CACHE': cache}
    result = subprocess.run(['sh', str(generator), '5053', '1.1.1.1'], input=native + '\n',
                            text=True, capture_output=True, env=env)
    assert result.returncode == 0, result.stderr
    auto = tomllib.loads(result.stdout)
    assert auto['server_names'] == [] and auto['require_nofilter'] is True
    assert 'static' not in auto and 'public-resolvers' in auto['sources']
    assert set(auto['disabled_server_names']) == {
        'dnscry.pt-moscow-ipv4', 'dnscry.pt-moscow-ipv6',
        'dnscry.pt-doh-moscow-ipv4', 'dnscry.pt-doh-moscow-ipv6'}
for strategy in ('wp2', 'p2', 'p3', 'p4', 'p5', 'p6', 'ph', 'first', 'random'):
    env = {**os.environ, 'DNS_MANAGER_PROTOCOL': 'native', 'DNS_MANAGER_LB_STRATEGY': strategy}
    result = subprocess.run(['sh', str(generator), '5053', '1.1.1.1'], input=native + '\n',
                            text=True, capture_output=True, env=env)
    assert result.returncode == 0, result.stderr
    config = tomllib.loads(result.stdout)
    assert config['dnscrypt_servers'] is True and config['doh_servers'] is False
    assert config['lb_strategy'] == strategy
print('Single-process DoH and native DNSCrypt pool configuration checks passed')
