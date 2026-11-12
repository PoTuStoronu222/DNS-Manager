#!/usr/bin/env python3
"""Check the experimental DoH stamp encoder against the published wire format."""
import base64
import pathlib
import subprocess
import urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / 'libexec' / 'dns-manager-doh-stamp.sh'
CATALOG = ROOT / 'catalogs' / 'dns-8.7-RU-NOSOCIAL.conf'


def stamp(url):
    return subprocess.run(['sh', str(SCRIPT), url], text=True, capture_output=True)


def check(url):
    result = stamp(url)
    assert result.returncode == 0, (url, result.stderr)
    assert result.stdout.startswith('sdns://'), result.stdout
    raw = result.stdout.strip()[7:]
    wire = base64.urlsafe_b64decode(raw + '=' * (-len(raw) % 4))
    assert wire[:11] == b'\x02' + b'\x00' * 10, (url, wire)
    n = wire[11]
    host = wire[12:12+n].decode('ascii')
    i = 12+n
    m = wire[i]
    path = wire[i+1:i+1+m].decode('ascii')
    assert i+1+m == len(wire), url
    parsed = urllib.parse.urlsplit(url)
    assert host == parsed.netloc, url
    assert path == (parsed.path or '/'), url


for line in CATALOG.read_text(encoding='utf-8').splitlines():
    fields = line.split('|')
    if len(fields) >= 5 and fields[4].startswith('https://'):
        check(fields[4])

for url in ('https://dns.nextdns.io', 'https://dns.geohide.ru:8443/dns-query',
            'https://api.magicdns.ru/sync', 'https://example.com/a/'):
    check(url)

for url in ('http://example.com/', 'https://example.com/?x=1',
            'https://user@example.com/', 'https://example.com/#fragment',
            'https://example.com:0/', 'https://example.com:65536/',
            'https://example.com/' + 'a'*255, 'https://example.com/\nheader'):
    result = stamp(url)
    assert result.returncode != 0, (url, result.stdout)
    assert not result.stdout, (url, result.stdout)

print('Experimental DoH stamp: catalog and rejection checks passed')
