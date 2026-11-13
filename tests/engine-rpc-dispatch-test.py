#!/usr/bin/env python3
"""Exercise the installed RPC bridge without touching system files."""
import json
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
source = (root / 'dns-manager-luci.sh').read_text(encoding='utf-8')
start = "cat > \"$RPC_STAGE\" <<'EOF_RPC_WRAPPER'\n"
body = source.split(start, 1)[1].split('\nEOF_RPC_WRAPPER', 1)[0]

with tempfile.TemporaryDirectory(prefix='engine-rpc-test-') as tmp:
    path = pathlib.Path(tmp)
    marker = path / 'engine'
    old = path / 'backend.sh'
    new = path / 'backend-dnscrypt.sh'
    wrapper = path / 'wrapper.sh'
    body = body.replace('/etc/dns-manager/config/dnscrypt-engine', str(marker))
    body = body.replace('/usr/lib/dns-manager-luci/backend.sh', str(old))
    body = body.replace('/usr/lib/dns-manager-luci/backend-dnscrypt.sh', str(new))
    wrapper.write_text(body, encoding='utf-8')
    old.write_text('#!/bin/sh\nprintf "old:%s:%s\\n" "$1" "$2"\n', encoding='utf-8')
    old.chmod(0o755)

    def call():
        return subprocess.run(['sh', str(wrapper), 'call', 'status'], text=True, capture_output=True)

    result = call()
    assert result.returncode == 0 and result.stdout == 'old:call:status\n'
    marker.write_text('https-dns-proxy\n', encoding='utf-8')
    result = call()
    assert result.returncode == 0 and result.stdout == 'old:call:status\n'
    marker.write_text('dnscrypt-proxy2\n', encoding='utf-8')
    result = call()
    assert result.returncode != 0 and json.loads(result.stdout)['ok'] is False
    new.write_text('#!/bin/sh\nprintf "new:%s:%s\\n" "$1" "$2"\n', encoding='utf-8')
    new.chmod(0o755)
    result = call()
    assert result.returncode == 0 and result.stdout == 'new:call:status\n'
    for invalid in ('', 'invalid', 'dnscrypt-proxy2\nhttps-dns-proxy'):
        marker.write_text(invalid, encoding='utf-8')
        result = call()
        assert result.returncode != 0 and json.loads(result.stdout)['ok'] is False
    marker.unlink()
    marker.symlink_to(path / 'missing')
    result = call()
    assert result.returncode != 0 and json.loads(result.stdout)['ok'] is False

print('RPC bridge selects the matching engine and rejects invalid or missing backends')
