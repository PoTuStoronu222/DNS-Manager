#!/usr/bin/env python3
"""Check that the manager service registers exactly one validated process."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
source = root / 'libexec/dns-manager-dnscrypt.init'
with tempfile.TemporaryDirectory(prefix='dnscrypt-pool-service-') as tmp:
    path = pathlib.Path(tmp)
    config = path / 'pool.toml'
    marker = path / 'engine'
    binary = path / 'dnscrypt-proxy'
    binary.write_text('#!/bin/sh\n[ "$1" = -config ] && [ "$3" = -check ] && [ "$(cat "$2")" = valid ]\n')
    binary.chmod(0o755)
    service = path / 'service'
    text = source.read_text().replace('PROG=/usr/sbin/dnscrypt-proxy', f'PROG={binary}')
    text = text.replace('CONFIG=/etc/dns-manager/config/dnscrypt-pool.toml', f'CONFIG={config}')
    text = text.replace('ENGINE_FILE=/etc/dns-manager/config/dnscrypt-engine', f'ENGINE_FILE={marker}')
    service.write_text(text)
    runner = path / 'runner'
    runner.write_text(f'''#!/bin/sh
procd_open_instance() {{ printf 'open:%s\\n' "$1"; }}
procd_set_param() {{ printf 'param:%s\\n' "$*"; }}
procd_close_instance() {{ printf 'close\\n'; }}
. '{service}'
start_service
''')

    def run():
        return subprocess.run(['sh', str(runner)], text=True, capture_output=True)

    result = run()
    assert result.returncode != 0 and result.stdout == ''
    marker.write_text('dnscrypt-proxy2\n')
    config.write_text('invalid')
    result = run()
    assert result.returncode != 0 and result.stdout == ''
    config.write_text('valid')
    result = run()
    assert result.returncode == 0, result.stderr
    assert result.stdout.count('open:dns-manager\n') == 1
    assert f'param:command {binary} -config {config}\n' in result.stdout
    assert result.stdout.count('close\n') == 1
    marker.write_text('https-dns-proxy\n')
    result = run()
    assert result.returncode != 0 and result.stdout == ''

print('Single-process procd service validates its configuration before registration')
