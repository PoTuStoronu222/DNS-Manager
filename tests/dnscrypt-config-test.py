#!/usr/bin/env python3
"""Validate experimental per-slot configuration before service integration."""
import pathlib
import subprocess
import tomllib

root = pathlib.Path(__file__).resolve().parent.parent
script = root / 'libexec' / 'dns-manager-dnscrypt-config.sh'


def run(port, url, bootstrap):
    return subprocess.run(['sh', str(script), port, url, bootstrap], text=True, capture_output=True)


result = run('5059', 'https://dns.geohide.ru:8443/dns-query', '1.1.1.1,2606:4700:4700::1111')
assert result.returncode == 0, result.stderr
config = tomllib.loads(result.stdout)
assert config['listen_addresses'] == ['127.0.0.1:5059']
assert config['server_names'] == ['manager-slot']
assert config['cache'] is False
assert config['ignore_system_dns'] is True
assert config['bootstrap_resolvers'] == ['1.1.1.1:53', '[2606:4700:4700::1111]:53']
assert config['static']['manager-slot']['stamp'].startswith('sdns://')

for port, url, bootstrap in [
    ('0', 'https://dns.google/dns-query', '1.1.1.1'),
    ('65536', 'https://dns.google/dns-query', '1.1.1.1'),
    ('5053', 'http://dns.google/dns-query', '1.1.1.1'),
    ('5053', 'https://dns.google/dns-query', ''),
    ('5053', 'https://dns.google/dns-query', '127.0.0.1'),
    ('5053', 'https://dns.google/dns-query', '1.1.1.1,1.1.1.1'),
    ('5053', 'https://dns.google/dns-query', "1.1.1.1']\ncache = true"),
]:
    result = run(port, url, bootstrap)
    assert result.returncode != 0, (port, url, bootstrap)
    assert result.stdout == '', result.stdout

print('Experimental per-slot config checks passed')
