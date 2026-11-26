#!/usr/bin/env python3
"""Check the bundled catalog and DNSCrypt stamp used for QUIC DNS."""
import base64
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parent.parent
installer = (root / 'dns-manager-luci.sh').read_text(encoding='utf-8')
catalog = (root / 'libexec/dns-manager-dnscrypt-catalog.conf').read_text(encoding='utf-8')
embedded = installer.split("<<'EOF_DNSCRYPT_CATALOG'\n", 1)[1].split('\nEOF_DNSCRYPT_CATALOG', 1)[0]
assert embedded == catalog.rstrip('\n'), 'installer and bundled catalog differ'
entry = next(line.split('|') for line in catalog.splitlines() if line.startswith('native_quic_best|'))
assert entry[1:3] == ['bypass', 'dnscrypt']
stamp = entry[4].removeprefix('sdns://')
wire = base64.urlsafe_b64decode(stamp + '=' * (-len(stamp) % 4))
assert wire[0] == 1 and b'192.166.219.30:5353' in wire and b'2.dnscrypt-cert.w.quic.best' in wire
backend = (root / 'libexec/backend-dnscrypt.sh').read_bytes()
assert hashlib.sha256(backend).hexdigest() in installer, 'installer backend hash is stale'
print('DNSCrypt bundled catalog and backend hash checks passed')
