#!/usr/bin/env python3
"""Exercise both engine transitions and stock-DNS fallback in a sandbox."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
worker = root / 'libexec/dns-manager-engine-switch.sh'
with tempfile.TemporaryDirectory(prefix='engine-switch-') as name:
    d = Path(name)
    helpers = d / 'helpers'; helpers.mkdir()
    init = d / 'init'; init.mkdir()
    config = d / 'config'; config.mkdir()
    runtime = d / 'runtime'; runtime.mkdir()
    jobs = runtime / 'jobs' / 'engine'; jobs.mkdir(parents=True)
    fake = d / 'fake'; fake.mkdir()
    def executable(path, data):
        path.write_text(data, encoding='utf-8'); path.chmod(0o755)
    manager = d / 'manager'
    manager.write_text('''#!/bin/sh
CUSTOM_DNS_CATALOG="$TEST_DIR/custom"
BOOTSTRAP_DNS=1.1.1.1,8.8.8.8
preflight_readonly() { :; }
init_dirs() { :; }
load_config() { :; }
acquire_mutation_lock() { [ ! -f "$TEST_DIR/lock-fail" ]; }
release_mutation_lock() { echo release >> "$TEST_DIR/log"; }
watchdog_service_stop_disable() { echo watchdog >> "$TEST_DIR/log"; }
watchdog_cron_remove_owned_block() { :; }
save_config() { :; }
clear_dns_core_runtime_state() { echo clear-state >> "$TEST_DIR/log"; }
rollback_firewall_targeted() { echo firewall >> "$TEST_DIR/log"; }
restore_hdp_package_defaults() { echo hdp-config >> "$TEST_DIR/log"; }
case "${1:-}" in
esac
''', encoding='utf-8')
    executable(fake / 'uci', '#!/bin/sh\nexit 0\n')
    executable(fake / 'ubus', '#!/bin/sh\n[ ! -f "$TEST_DIR/watchdog-active" ] || { echo "{\\"dns-watchdog\\":{}}"; exit; }\nprintf "{}\\n"\n')
    executable(fake / 'jsonfilter', '#!/bin/sh\ncase "$*" in *dns-watchdog*) [ -f "$TEST_DIR/watchdog-active" ];; *) echo "{}";; esac\n')
    executable(fake / 'apk', '#!/bin/sh\n[ "$1" != add ]\n')
    executable(fake / 'binary', '#!/bin/sh\nexit 0\n')
    executable(init / 'dnscrypt-proxy', '#!/bin/sh\necho "dnscrypt $1" >> "$TEST_DIR/log"\n')
    executable(helpers / 'dns-manager-device-detach.sh', '#!/bin/sh\necho detach >> "$TEST_DIR/log"\n')
    executable(helpers / 'dns-manager-engine-services.sh', '#!/bin/sh\necho "services $*" >> "$TEST_DIR/log"\n')
    executable(helpers / 'dns-manager-dnscrypt-pool-apply.sh', '#!/bin/sh\ncat >/dev/null\necho pool >> "$TEST_DIR/log"\n[ ! -f "$TEST_DIR/pool-fail" ]\n')
    executable(helpers / 'dns-manager-dnscrypt-dnsmasq.sh', '''#!/bin/sh
echo "dnsmasq $1" >> "$TEST_DIR/log"
if [ "$1" != clean ] && [ -f "$TEST_DIR/apply-fail" ]; then exit 1; fi
''')
    env = {**os.environ, 'PATH': str(fake) + os.pathsep + os.environ['PATH'],
           'TEST_DIR': str(d), 'DNS_MANAGER_MANAGER': str(manager),
           'DNS_MANAGER_DNSCRYPT_HELPERS': str(helpers),
           'DNS_MANAGER_DNSCRYPT_RUNTIME_DIR': str(runtime),
           'DNS_MANAGER_DNSCRYPT_CONFIG_DIR': str(config),
           'DNS_MANAGER_ENGINE_UCI_CONFIG': str(d / 'uci-dns-manager'),
           'DNS_MANAGER_INIT_DIR': str(init),
           'DNS_MANAGER_DNSCRYPT_BIN': str(fake / 'binary'),
           'DNS_MANAGER_HDP_BIN': str(fake / 'binary')}
    def run(target):
        (jobs / 'state').write_text('status=running\n')
        (jobs / 'output').write_text('')
        return subprocess.run(['sh', str(worker), target], env=env, capture_output=True, text=True)
    for target in ('dnscrypt-proxy2', 'https-dns-proxy'):
        result = run(target)
        assert result.returncode == 0, (result.stderr, (jobs / 'output').read_text())
        assert (config / 'dnscrypt-engine').read_text().strip() == target
        assert 'status=done' in (jobs / 'state').read_text()
        if target == 'dnscrypt-proxy2':
            assert 'server=cloudflare_clean|' in (config / 'dnscrypt-profile.state').read_text()
        else:
            assert not (config / 'dnscrypt-profile.state').exists()
    (d / 'apply-fail').touch()
    (d / 'log').write_text('')
    result = run('dnscrypt-proxy2')
    assert result.returncode != 0
    assert 'status=failed' in (jobs / 'state').read_text()
    assert (d / 'log').read_text().count('dnsmasq clean') == 2
    assert (config / 'dnscrypt-engine').read_text().strip() == 'https-dns-proxy'
    assert 'release' in (d / 'log').read_text()
    (d / 'apply-fail').unlink()
    (d / 'watchdog-active').touch()
    (d / 'log').write_text('')
    result = run('dnscrypt-proxy2')
    assert result.returncode != 0 and 'detach' not in (d / 'log').read_text()
    (d / 'watchdog-active').unlink()
    env['DNS_MANAGER_DNSCRYPT_BIN'] = str(d / 'missing-binary')
    (d / 'log').write_text('')
    result = run('dnscrypt-proxy2')
    assert result.returncode != 0 and (d / 'log').read_text().count('dnsmasq clean') == 2
print('PASS: switch worker tests both engines and restores stock DNS on failure')
