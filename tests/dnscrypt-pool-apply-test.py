#!/usr/bin/env python3
"""Verify pool replacement and failure recovery with isolated fake services."""
import os
import pathlib
import subprocess
import tempfile
import tomllib

root = pathlib.Path(__file__).resolve().parent.parent
apply = root / 'libexec/dns-manager-dnscrypt-pool-apply.sh'
with tempfile.TemporaryDirectory(prefix='dnscrypt-pool-apply-') as tmp:
    path = pathlib.Path(tmp)
    config = path / 'pool.toml'
    config.write_text('old config\n')
    binary = path / 'dnscrypt'
    binary.write_text('#!/bin/sh\n[ ! -e "$TEST_ROOT/invalid" ]\n')
    binary.chmod(0o755)
    init = path / 'init'
    init.write_text('''#!/bin/sh
case "$1" in
  restart) echo restart >> "$TEST_ROOT/restarts"; [ ! -e "$TEST_ROOT/restart-fails" ]; ;;
  stop) echo stop >> "$TEST_ROOT/restarts"; exit 0 ;;
  running) exit 0 ;;
  *) exit 1 ;;
esac
''')
    init.chmod(0o755)
    dig = path / 'dig'
    dig.write_text('#!/bin/sh\n[ ! -e "$TEST_ROOT/no-answer" ] && echo 192.0.2.1\n')
    dig.chmod(0o755)
    sleep = path / 'sleep'
    sleep.write_text('#!/bin/sh\nexit 0\n')
    sleep.chmod(0o755)
    env = {**os.environ, 'TEST_ROOT': str(path), 'PATH': str(path) + os.pathsep + os.environ['PATH'],
           'DNS_MANAGER_DNSCRYPT_BIN': str(binary), 'DNS_MANAGER_DNSCRYPT_INIT': str(init),
           'DNS_MANAGER_DNSCRYPT_CONFIG': str(config)}

    def run(url='https://dns.google/dns-query\n'):
        return subprocess.run(['sh', str(apply), '5053', '1.1.1.1'], input=url,
                              env=env, capture_output=True, text=True)

    (path / 'invalid').touch()
    assert run().returncode != 0 and config.read_text() == 'old config\n'
    assert not (path / 'restarts').exists()
    (path / 'invalid').unlink()
    result = run()
    assert result.returncode == 0, result.stderr
    installed = config.read_text()
    assert tomllib.loads(installed)['server_names'] == ['manager-1']
    assert len((path / 'restarts').read_text().splitlines()) == 1
    (path / 'no-answer').touch()
    result = run('https://cloudflare-dns.com/dns-query\n')
    assert result.returncode != 0 and config.read_text() == installed
    assert len((path / 'restarts').read_text().splitlines()) == 3
    assert not list(path.glob('.dnscrypt-pool-*'))
    (path / 'no-answer').unlink()
    (path / 'restart-fails').touch()
    result = run('https://cloudflare-dns.com/dns-query\n')
    assert result.returncode != 0 and config.read_text() == installed
    assert 'Failed to restart restored DNSCrypt config' in result.stderr
    (path / 'restart-fails').unlink()
    config.unlink()
    (path / 'no-answer').touch()
    result = run()
    assert result.returncode != 0 and not config.exists()
    assert (path / 'restarts').read_text().splitlines()[-1] == 'stop'
    assert not list(path.glob('.dnscrypt-pool-*'))
    (path / 'no-answer').unlink()
    result = run()
    assert result.returncode == 0, result.stderr
    assert tomllib.loads(config.read_text())['server_names'] == ['manager-1']
    assert not list(path.glob('.dnscrypt-pool-*'))

print('DNSCrypt pool apply validates first and restores previous config on failed DNS')
