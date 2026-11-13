#!/usr/bin/env python3
"""Exercise experimental service lifecycle using isolated fake init scripts."""
import os
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
helper = root / 'libexec/dns-manager-engine-services.sh'

with tempfile.TemporaryDirectory(prefix='engine-services-test-') as tmp:
    directory = pathlib.Path(tmp)
    for service in ('https-dns-proxy', 'dnscrypt-proxy', 'dns-manager-dnscrypt'):
        script = directory / service
        script.write_text('''#!/bin/sh
dir=$(dirname "$0"); name=$(basename "$0")
echo "$name $1" >> "$dir/log"
case "$1" in
  stop) [ ! -e "$dir/$name.fail-stop" ] || exit 1; [ -e "$dir/$name.running" ] || exit 1; rm -f "$dir/$name.running" ;;
  disable) rm -f "$dir/$name.enabled" ;;
  enable) touch "$dir/$name.enabled" ;;
  enabled) [ -e "$dir/$name.enabled" ] ;;
  running) [ -e "$dir/$name.running" ] ;;
  check) [ ! -e "$dir/$name.fail-check" ] ;;
  start) [ ! -e "$dir/$name.fail-start" ] || exit 1; [ -e "$dir/$name.false-start" ] || touch "$dir/$name.running" ;;
  *) exit 2 ;;
esac
''')
        script.chmod(0o755)
    ubus = directory / 'ubus'
    ubus.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['DNS_MANAGER_INIT_DIR'])
if (root / 'ubus.fail').exists(): sys.exit(1)
if (root / 'ubus.invalid').exists(): print('invalid'); sys.exit(0)
name = json.loads(sys.argv[-1])['name']
print(json.dumps({name: {}} if (root / (name + '.running')).exists() else {}))
''')
    ubus.chmod(0o755)
    jsonfilter = directory / 'jsonfilter'
    jsonfilter.write_text('''#!/usr/bin/env python3
import json, sys
data = json.loads(sys.argv[sys.argv.index('-s') + 1])
expr = sys.argv[sys.argv.index('-e') + 1]
if expr == '@': print(json.dumps(data)); sys.exit(0)
name = expr[3:-2]
if name not in data: sys.exit(1)
print(json.dumps(data[name]))
''')
    jsonfilter.chmod(0o755)
    uci = directory / 'uci'
    uci.write_text("""#!/bin/sh
case "$3" in
  https-dns-proxy.config.force_dns)
    [ ! -e "$DNS_MANAGER_INIT_DIR/force-on" ] || { echo 1; exit 0; }
    [ ! -e "$DNS_MANAGER_INIT_DIR/force-missing" ] || exit 1
    echo 0 ;;
  https-dns-proxy.config.dnsmasq_config_update)
    [ ! -e "$DNS_MANAGER_INIT_DIR/integration-on" ] || { echo '*'; exit 0; }
    echo - ;;
  *) exit 1 ;;
esac
""")
    uci.chmod(0o755)
    binary = directory / 'dnscrypt-binary'
    binary.write_text('#!/bin/sh\n[ ! -e "$DNS_MANAGER_INIT_DIR/fail-check" ]\n')
    binary.chmod(0o755)
    config = directory / 'dnscrypt.toml'
    config.write_text('test\n')
    env = {**os.environ, 'DNS_MANAGER_INIT_DIR': str(directory),
           'DNS_MANAGER_DNSCRYPT_BIN': str(binary), 'DNS_MANAGER_DNSCRYPT_CONFIG': str(config),
           'PATH': str(directory) + os.pathsep + os.environ['PATH']}

    def run(action, engine):
        return subprocess.run(['sh', str(helper), action, engine], env=env, capture_output=True, text=True)

    def state(service, value):
        return (directory / f'{service}.{value}').exists()

    for engine, target, other in [('dnscrypt-proxy2', 'dnscrypt-proxy', 'https-dns-proxy'),
                                   ('https-dns-proxy', 'https-dns-proxy', 'dnscrypt-proxy')]:
        (directory / f'{other}.enabled').touch()
        (directory / f'{other}.running').touch()
        # Starting without quiescing is refused.
        result = run('start', engine)
        assert result.returncode != 0 and not state(target, 'running'), result.stderr
        result = run('quiesce', engine)
        assert result.returncode == 0, result.stderr
        for name in ('https-dns-proxy', 'dnscrypt-proxy', 'dns-manager-dnscrypt'):
            assert not state(name, 'enabled') and not state(name, 'running')
        result = run('start', engine)
        assert result.returncode == 0 and state(target, 'running') and state(target, 'enabled'), result.stderr
        assert run('quiesce', engine).returncode == 0

    for flag in ('force-on', 'force-missing', 'integration-on'):
        (directory / flag).touch()
        result = run('start', 'https-dns-proxy')
        assert result.returncode != 0 and 'integration must be disabled' in result.stderr
        assert not state('https-dns-proxy', 'running') and not state('https-dns-proxy', 'enabled')
        (directory / flag).unlink()

    (directory / 'https-dns-proxy.fail-stop').touch()
    (directory / 'https-dns-proxy.running').touch()
    assert run('quiesce', 'dnscrypt-proxy2').returncode != 0
    assert not state('dnscrypt-proxy', 'enabled')
    (directory / 'https-dns-proxy.fail-stop').unlink()
    (directory / 'https-dns-proxy.running').unlink()
    (directory / 'ubus.fail').touch()
    assert run('quiesce', 'dnscrypt-proxy2').returncode != 0
    assert run('start', 'dnscrypt-proxy2').returncode != 0
    (directory / 'ubus.fail').unlink()
    (directory / 'ubus.invalid').touch()
    assert run('quiesce', 'dnscrypt-proxy2').returncode != 0
    assert run('start', 'dnscrypt-proxy2').returncode != 0
    (directory / 'ubus.invalid').unlink()
    (directory / 'fail-check').touch()
    assert run('start', 'dnscrypt-proxy2').returncode != 0
    assert not state('dnscrypt-proxy', 'enabled')
    (directory / 'fail-check').unlink()
    (directory / 'dnscrypt-proxy.fail-start').touch()
    assert run('start', 'dnscrypt-proxy2').returncode != 0
    assert not state('dnscrypt-proxy', 'enabled')
    (directory / 'dnscrypt-proxy.fail-start').unlink()
    (directory / 'dnscrypt-proxy.false-start').touch()
    result = run('start', 'dnscrypt-proxy2')
    assert result.returncode != 0 and 'did not become ready' in result.stderr
    assert not state('dnscrypt-proxy', 'enabled')
    assert run('start', 'invalid').returncode == 2

print('Experimental service lifecycle checks passed')
