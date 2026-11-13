#!/usr/bin/env python3
"""Exercise DNSCrypt RPC dispatch and profile-worker state in a sandbox."""
import json
import os
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
backend = root / 'libexec/backend-dnscrypt.sh'
with tempfile.TemporaryDirectory(prefix='dnscrypt-rpc-') as tmp:
    d = pathlib.Path(tmp)
    helpers = d / 'helpers'
    helpers.mkdir()
    jobs = d / 'jobs'
    runtime = d / 'runtime'
    config = d / 'config'
    runtime.mkdir()
    config.mkdir()
    (config / 'dnscrypt-engine').write_text('dnscrypt-proxy2\n')
    init = d / 'dnscrypt-init'
    init.write_text('#!/bin/sh\n[ "$1" = enable ] && [ ! -e "$LAB_ROOT/enable-fail" ]\n')
    init.chmod(0o755)
    hdp = d / 'https-dns-proxy'
    hdp.write_text('#!/bin/sh\n[ -e "$LAB_ROOT/hdp-active" ]\n')
    hdp.chmod(0o755)
    legacy = d / 'legacy'
    legacy.write_text('#!/bin/sh\nprintf "{\\"ok\\":true,\\"method\\":\\"%s\\"}\\n" "$2"\n')
    legacy.chmod(0o755)
    jf = d / 'jsonfilter'
    jf.write_text('#!/usr/bin/env python3\nimport json,sys\nprint(json.load(sys.stdin).get("profile", ""))\n')
    jf.chmod(0o755)
    ubus = d / 'ubus'
    ubus.write_text('''#!/usr/bin/env python3
import os,pathlib,sys
p=pathlib.Path(os.environ['LAB_ROOT'])
if (p/'ubus-fail').exists(): sys.exit(1)
if sys.argv[-2:] == ['service','list']: print('{}'); sys.exit(0)
if 'list' in sys.argv:
 print('{"service":{"instances":{"main":{"running":true}}}}' if (p/'running').exists() else '{}')
elif 'set' in sys.argv:
 (p/'request').write_text(sys.argv[-1]); print('{}')
else: print('{}')
''')
    ubus.chmod(0o755)
    manager = d / 'manager'
    manager.write_text('''#!/bin/sh
preflight_readonly() { :; }
init_dirs() { :; }
load_config() { BOOTSTRAP_DNS=1.1.1.1; }
acquire_mutation_lock() { [ "${LAB_SWITCH:-0}" != 1 ] || printf 'https-dns-proxy\\n' > "$DNS_MANAGER_DNSCRYPT_CONFIG_DIR/dnscrypt-engine"; }
release_mutation_lock() { :; }
restore_persistent_test_results() { :; }
refresh_runtime_capabilities() { :; }
case "${1:-}" in
  *) exit 1;;
esac
''')
    (helpers / 'dns-manager-dnscrypt-profile.sh').write_text('#!/bin/sh\n')
    (helpers / 'dns-manager-dnscrypt-profile-apply.sh').write_text('''#!/bin/sh
dnscrypt_apply_profile_pool() {
    [ "${LAB_FAIL:-0}" != 1 ] || return 1
    printf 'cloudflare|https://cloudflare-dns.com/dns-query\\n'
}
''')
    (helpers / 'dns-manager-dnscrypt-dnsmasq.sh').write_text('#!/bin/sh\nprintf "%s\\n" "$*" > "$LAB_ROOT/restore"\n[ ! -e "$LAB_ROOT/restore-fail" ]\n')
    (helpers / 'dns-manager-engine-services.sh').write_text('#!/bin/sh\n[ ! -e "$LAB_ROOT/quiesce-fail" ]\n')
    env = {**os.environ, 'PATH': str(d) + os.pathsep + os.environ['PATH'],
           'LAB_ROOT': str(d), 'DNS_MANAGER_MANAGER': str(manager),
           'DNS_MANAGER_LEGACY_BACKEND': str(legacy),
           'DNS_MANAGER_DNSCRYPT_HELPERS': str(helpers),
           'DNS_MANAGER_DNSCRYPT_CONFIG_DIR': str(config),
           'DNS_MANAGER_DNSCRYPT_INIT': str(init),
           'DNS_MANAGER_HDP_INIT': str(hdp),
           'DNS_MANAGER_DNSCRYPT_JOB_DIR': str(jobs),
           'DNS_MANAGER_DNSCRYPT_RUNTIME_DIR': str(runtime)}

    def run(*args, input='', extra=None):
        return subprocess.run(['sh', str(backend), *args], input=input, text=True,
                              capture_output=True, env={**env, **(extra or {})})

    assert json.loads(run('call', 'set_slot', input='{}').stdout)['ok'] is False
    assert json.loads(run('call', 'log', input='{}').stdout)['method'] == 'log'
    assert json.loads(run('call', 'set_profile', input='{"profile":"invalid"}').stdout)['ok'] is False
    (config / 'dnscrypt-engine').write_text('https-dns-proxy\n')
    assert json.loads(run('call', 'set_profile', input='{"profile":"clean"}').stdout)['ok'] is False
    (config / 'dnscrypt-engine').write_text('dnscrypt-proxy2\n')
    (d / 'ubus-fail').touch()
    assert json.loads(run('call', 'set_profile', input='{"profile":"clean"}').stdout)['ok'] is False
    (d / 'ubus-fail').unlink()
    (d / 'running').touch()
    assert json.loads(run('call', 'set_profile', input='{"profile":"clean"}').stdout)['ok'] is False
    (d / 'running').unlink()
    assert json.loads(run('call', 'set_profile', input='{"profile":"clean"}').stdout)['job'] == 'profile'
    request = json.loads((d / 'request').read_text())
    assert request['instances']['main']['command'][-2:] == ['worker', 'clean']
    result = run('worker', 'clean')
    assert result.returncode == 0, result.stderr
    state = (config / 'dnscrypt-profile.state').read_text()
    assert state == 'profile=clean\nserver=cloudflare|https://cloudflare-dns.com/dns-query\n'
    assert 'status=done\n' in (jobs / 'profile/state').read_text()
    result = run('worker', 'clean', extra={'LAB_FAIL': '1'})
    assert result.returncode != 0
    assert (config / 'dnscrypt-profile.state').read_text() == state
    assert 'status=failed\n' in (jobs / 'profile/state').read_text()
    (d / 'enable-fail').touch()
    result = run('worker', 'clean')
    assert result.returncode != 0
    assert not (config / 'dnscrypt-profile.state').exists()
    assert (d / 'restore').read_text().startswith('restore 5053 ')
    (d / 'enable-fail').unlink()
    (config / 'dnscrypt-profile.state').write_text(state)
    result = run('worker', 'clean', extra={'LAB_SWITCH': '1'})
    assert result.returncode != 0
    assert (config / 'dnscrypt-profile.state').read_text() == state
    (config / 'dnscrypt-engine').write_text('dnscrypt-proxy2\n')
    (d / 'hdp-active').touch()
    result = run('worker', 'clean')
    assert result.returncode != 0 and (config / 'dnscrypt-profile.state').read_text() == state
    (d / 'hdp-active').unlink()
    assert json.loads(run('call', 'reset_dns', input='{}').stdout)['job'] == 'action'
    request = json.loads((d / 'request').read_text())
    assert request['instances']['main']['command'][-1] == 'reset_worker'
    (d / 'restore-fail').touch()
    result = run('reset_worker')
    assert result.returncode != 0 and (config / 'dnscrypt-profile.state').exists()
    (d / 'restore-fail').unlink()
    (d / 'quiesce-fail').touch()
    result = run('reset_worker')
    assert result.returncode != 0 and not (config / 'dnscrypt-profile.state').exists()
    assert json.loads((jobs / 'action/output').read_text())['ok'] is False
    (d / 'quiesce-fail').unlink()
    result = run('reset_worker')
    assert result.returncode == 0 and not (config / 'dnscrypt-profile.state').exists()
    assert json.loads((jobs / 'action/output').read_text())['ok'] is True

print('DNSCrypt RPC dispatch and profile job use isolated state and reject unsupported actions')
