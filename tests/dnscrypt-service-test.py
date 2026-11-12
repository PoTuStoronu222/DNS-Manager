#!/usr/bin/env python3
"""Test procd registration preflight without starting services on the host."""
import pathlib
import subprocess
import tempfile

source = pathlib.Path(__file__).resolve().parent.parent / 'libexec/dns-manager-dnscrypt.init'

with tempfile.TemporaryDirectory(prefix='dnscrypt-service-test-') as tmp:
    root = pathlib.Path(tmp)
    configs = root / 'configs'
    configs.mkdir()
    engine = root / 'engine'
    slots = root / 'slots'
    proxy = root / 'proxy'
    proxy.write_text('#!/bin/sh\n[ "$1" = -config ] && [ "$3" = -check ] && [ "$(cat "$2")" = valid ]\n')
    proxy.chmod(0o755)
    text = source.read_text().replace('PROG=/usr/sbin/dnscrypt-proxy', f'PROG={proxy}')
    text = text.replace('ENGINE_FILE=/etc/dns-manager/config/dnscrypt-engine', f'ENGINE_FILE={engine}')
    text = text.replace('SLOTS_FILE=/etc/dns-manager/config/dnscrypt-slots', f'SLOTS_FILE={slots}')
    text = text.replace('CONFIG_DIR=/etc/dns-manager/config/dnscrypt', f'CONFIG_DIR={configs}')
    service = root / 'service'
    service.write_text(text)
    wrapper = root / 'test.sh'
    wrapper.write_text(f'''#!/bin/sh
procd_open_instance() {{ printf 'open:%s\\n' "$1"; }}
procd_set_param() {{ printf 'param:%s\\n' "$*"; }}
procd_close_instance() {{ printf 'close\\n'; }}
. '{service}'
start_service
''')

    def start():
        return subprocess.run(['sh', str(wrapper)], capture_output=True, text=True)

    # No opt-in marker: no process registration and no error.
    result = start()
    assert result.returncode == 0 and not result.stdout
    engine.write_text('dnscrypt-proxy2\n')
    slots.write_text('')
    result = start()
    assert result.returncode == 0 and not result.stdout
    slots.write_text('1\nRU\n')
    (configs / 'slot-1.toml').write_text('valid')
    # A missing or invalid second configuration must prevent all registration.
    result = start()
    assert result.returncode != 0 and not result.stdout
    (configs / 'slot-RU.toml').write_text('invalid')
    result = start()
    assert result.returncode != 0 and not result.stdout
    (configs / 'slot-RU.toml').write_text('valid')
    result = start()
    assert result.returncode == 0, result.stderr
    assert [line for line in result.stdout.splitlines() if line.startswith('open:')] == ['open:slot_1', 'open:slot_RU']
    slots.write_text('1\n1\n')
    result = start()
    assert result.returncode != 0 and not result.stdout
    slots.write_text('../other\n')
    result = start()
    assert result.returncode != 0 and not result.stdout

print('Experimental procd service preflight checks passed')
