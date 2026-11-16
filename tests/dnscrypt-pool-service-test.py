#!/usr/bin/env python3
"""Check the procd command and the saved-engine boot guard."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
source = root / 'libexec/dns-manager-dnscrypt.init'
with tempfile.TemporaryDirectory(prefix='dnscrypt-pool-service-') as tmp:
    path = pathlib.Path(tmp)
    marker = path / 'engine'
    binary = path / 'dnscrypt-proxy'
    config = path / 'dnscrypt-proxy.toml'
    service = path / 'service'
    text = source.read_text().replace('PROG=/usr/sbin/dnscrypt-proxy', f'PROG={binary}')
    text = text.replace('CONFIG=/etc/dnscrypt-proxy2/dnscrypt-proxy.toml', f'CONFIG={config}')
    service.write_text(text)
    runner = path / 'runner'
    runner.write_text(f"""#!/bin/sh
uci() {{ [ -f '{marker}' ] && cat '{marker}'; }}
procd_open_instance() {{ printf 'open:%s\\n' "$1"; }}
procd_set_param() {{ printf 'param:%s\\n' "$*"; }}
procd_close_instance() {{ printf 'close\\n'; }}
start() {{ start_service; }}
. '{service}'
boot
""")

    def run():
        return subprocess.run(['sh', str(runner)], text=True, capture_output=True)

    assert run().stdout == ''
    marker.write_text('https-dns-proxy\n')
    assert run().stdout == ''
    marker.write_text('dnscrypt-proxy2\n')
    result = run()
    assert result.returncode == 0, result.stderr
    assert result.stdout.count('open:dns-manager\n') == 1
    assert f'param:command {binary} -config {config}\n' in result.stdout
    assert result.stdout.count('close\n') == 1

print('DNSCrypt procd service starts at boot only for the selected engine')
