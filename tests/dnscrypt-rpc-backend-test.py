#!/usr/bin/env python3
"""Exercise DNSCrypt RPC dispatch and profile-worker state in a sandbox."""
import json
import os
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
backend_source = root / 'libexec/backend-dnscrypt.sh'
with tempfile.TemporaryDirectory(prefix='dnscrypt-rpc-') as tmp:
    d = pathlib.Path(tmp)
    # OpenWrt supplies jshn through libubox; the local test supplies the same
    # shell interface to exercise status_extra and RPC dispatch off-device.
    backend = d / 'backend-dnscrypt.sh'
    backend.write_text(backend_source.read_text().replace(
        '. /usr/share/libubox/jshn.sh', '. "$LAB_ROOT/jshn.sh"'))
    (d / 'jshn.sh').write_text('''
json_init() { :; }
json_add_string() { :; }
json_add_int() { :; }
json_add_object() { :; }
json_add_array() { :; }
json_close_object() { :; }
json_close_array() { :; }
json_dump() { printf '%s' '{"dnscrypt_engine":"dnscrypt-proxy2"}'; }
''')
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
    jf.write_text('''#!/usr/bin/env python3
import json,sys
if '-s' in sys.argv:
 data=json.loads(sys.argv[sys.argv.index('-s')+1]); expr=sys.argv[sys.argv.index('-e')+1]
 if expr=='@': print(json.dumps(data)); sys.exit(0)
 if 'dns-watchdog' not in data: sys.exit(1)
 print(json.dumps(data['dns-watchdog'])); sys.exit(0)
print(json.load(sys.stdin).get("profile", ""))
''')
    jf.chmod(0o755)
    ubus = d / 'ubus'
    ubus.write_text('''#!/usr/bin/env python3
import os,pathlib,sys
p=pathlib.Path(os.environ['LAB_ROOT'])
if (p/'ubus-fail').exists(): sys.exit(1)
if 'dns-watchdog' in sys.argv[-1]:
 print('{"dns-watchdog":{}}' if (p/'watchdog-still-active').exists() else '{}'); sys.exit(0)
if sys.argv[-2:] == ['service','list']: print('{}'); sys.exit(0)
if 'list' in sys.argv:
 print('{"service":{"instances":{"main":{"running":true}}}}' if (p/'running').exists() else '{}')
elif 'set' in sys.argv:
 (p/'request').write_text(sys.argv[-1]); print('{}')
else: print('{}')
''')
    ubus.chmod(0o755)
    uci = d / 'uci'
    uci.write_text('#!/bin/sh\nexit 0\n')
    uci.chmod(0o755)
    manager = d / 'manager'
    manager.write_text('''#!/bin/sh
preflight_readonly() { :; }
init_dirs() { :; }
load_config() { BOOTSTRAP_DNS=1.1.1.1; WATCHDOG_ENABLED=1; WATCHDOG_AUTOREPLACE=1; }
watchdog_service_stop_disable() { [ ! -e "$LAB_ROOT/watchdog-fail" ]; }
watchdog_cron_remove_owned_block() { [ ! -e "$LAB_ROOT/cron-fail" ]; }
save_config() { [ ! -e "$LAB_ROOT/save-fail" ] && [ "$WATCHDOG_ENABLED:$WATCHDOG_AUTOREPLACE" = 0:0 ] && touch "$LAB_ROOT/watchdog-disabled"; }
acquire_mutation_lock() { [ "${LAB_SWITCH:-0}" != 1 ] || printf 'https-dns-proxy\\n' > "$DNS_MANAGER_DNSCRYPT_CONFIG_DIR/dnscrypt-engine"; }
release_mutation_lock() { :; }
restore_persistent_test_results() { :; }
refresh_runtime_capabilities() { :; }
dns_url() { case "$1" in cloudflare) printf 'https://cloudflare-dns.com/dns-query';; google) printf 'https://dns.google/dns-query';; *) return 1;; esac; }
normalize_url() { printf '%s' "$1"; }
case "${1:-}" in
  *) exit 1;;
esac
''')
    (helpers / 'dns-manager-watchdog-common.sh').write_text((root / 'libexec/dns-manager-watchdog-common.sh').read_text())
    (helpers / 'dns-manager-dnscrypt-profile.sh').write_text('#!/bin/sh\n')
    (helpers / 'dns-manager-dnscrypt-profile-apply.sh').write_text('''#!/bin/sh
dnscrypt_apply_profile_pool() {
    [ "${LAB_FAIL:-0}" != 1 ] || return 1
    case "$1" in server:*|pool:*) dnscrypt_select_profile "$1"; return $?;; esac
    printf 'cloudflare|https://cloudflare-dns.com/dns-query\\n'
}
''')
    (helpers / 'dns-manager-dnscrypt-dnsmasq.sh').write_text('#!/bin/sh\nprintf "%s\\n" "$*" > "$LAB_ROOT/restore"\n[ ! -e "$LAB_ROOT/restore-fail" ]\n')
    (helpers / 'dns-manager-engine-services.sh').write_text('#!/bin/sh\n[ ! -e "$LAB_ROOT/quiesce-fail" ]\n')
    (helpers / 'dns-manager-device-detach.sh').write_text('#!/bin/sh\n[ ! -e "$LAB_ROOT/detach-fail" ]\n')
    env = {**os.environ, 'PATH': str(d) + os.pathsep + os.environ['PATH'],
           'LAB_ROOT': str(d), 'DNS_MANAGER_MANAGER': str(manager),
           'DNS_MANAGER_LEGACY_BACKEND': str(legacy),
           'DNS_MANAGER_DNSCRYPT_HELPERS': str(helpers),
           'DNS_MANAGER_DNSCRYPT_CONFIG_DIR': str(config),
           'DNS_MANAGER_DNSCRYPT_CONFIG': str(d / 'dnscrypt.toml'),
           'DNS_MANAGER_DNSCRYPT_INIT': str(init),
           'DNS_MANAGER_HDP_INIT': str(hdp),
           'DNS_MANAGER_DNSCRYPT_JOB_DIR': str(jobs),
           'DNS_MANAGER_DNSCRYPT_RUNTIME_DIR': str(runtime)}

    def run(*args, input='', extra=None):
        return subprocess.run(['sh', str(backend), *args], input=input, text=True,
                              capture_output=True, env={**env, **(extra or {})})

    assert json.loads(run('call', 'set_slot', input='{}').stdout)['ok'] is False
    log_reply = json.loads(run('call', 'log', input='{}').stdout)
    assert log_reply['method'] == 'log' and log_reply['dnscrypt_engine'] == 'dnscrypt-proxy2'
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
    assert state == 'profile=clean\nprotocol=mixed\nstrategy=wp2\nserver=cloudflare|https://cloudflare-dns.com/dns-query\n'
    assert 'status=done\n' in (jobs / 'profile/state').read_text()
    for goal in ['options:invalid:p2:clean', 'options:native:invalid:clean']:
        assert json.loads(run('call', 'set_profile', input=json.dumps({'profile': goal})).stdout)['ok'] is False
    assert json.loads(run('call', 'set_profile', input=json.dumps({'profile': 'options:mixed:first:clean'})).stdout)['job'] == 'profile'
    result = run('worker', 'options:mixed:first:clean')
    assert result.returncode == 0 and 'strategy=first\n' in (config / 'dnscrypt-profile.state').read_text()
    result = run('worker', 'clean')
    assert result.returncode == 0 and 'strategy=first\n' in (config / 'dnscrypt-profile.state').read_text()
    (config / 'dnscrypt-profile.state').write_text('profile=clean\n')
    (d / 'dnscrypt.toml').write_text("lb_strategy = 'p2'\n")
    result = run('worker', 'clean')
    assert result.returncode == 0 and 'strategy=p2\n' in (config / 'dnscrypt-profile.state').read_text()
    (d / 'dnscrypt.toml').unlink()
    pool = ('profile=none\nserver=cloudflare|https://cloudflare-dns.com/dns-query\n'
            'server=google|https://dns.google/dns-query\n')
    (config / 'dnscrypt-profile.state').write_text(pool)
    assert json.loads(run('call', 'set_profile', input='{"profile":"server:google"}').stdout)['job'] == 'profile'
    result = run('worker', 'server:google')
    assert result.returncode == 0, result.stderr
    selected = (config / 'dnscrypt-profile.state').read_text()
    assert 'selected=google\n' in selected and 'server=google|https://dns.google/dns-query\n' in selected
    assert 'available=cloudflare|' in selected and 'available=google|' in selected
    result = run('worker', 'server:cloudflare')
    assert result.returncode == 0 and 'selected=cloudflare\n' in (config / 'dnscrypt-profile.state').read_text()
    selected = (config / 'dnscrypt-profile.state').read_text()
    result = run('worker', 'server:missing')
    assert result.returncode != 0 and (config / 'dnscrypt-profile.state').read_text() == selected
    for invalid in ['pool:', 'pool:google,google', 'pool:google,', 'pool:a,b,c,d,e,f,g', 'pool:bad/name']:
        assert json.loads(run('call', 'set_profile', input=json.dumps({'profile': invalid})).stdout)['ok'] is False
    assert json.loads(run('call', 'set_profile', input='{"profile":"pool:google,cloudflare"}').stdout)['job'] == 'profile'
    result = run('worker', 'pool:google,cloudflare')
    assert result.returncode == 0, result.stderr
    assert (config / 'dnscrypt-profile.state').read_text() == ('profile=none\nprotocol=mixed\nstrategy=wp2\nserver=google|https://dns.google/dns-query\nserver=cloudflare|https://cloudflare-dns.com/dns-query\n')
    before = (config / 'dnscrypt-profile.state').read_text()
    result = run('worker', 'pool:google,missing')
    assert result.returncode != 0 and (config / 'dnscrypt-profile.state').read_text() == before
    (config / 'dnscrypt-profile.state').write_text(state)
    result = run('worker', 'clean', extra={'LAB_FAIL': '1'})
    assert result.returncode != 0
    assert (config / 'dnscrypt-profile.state').read_text() == state
    assert 'status=failed\n' in (jobs / 'profile/state').read_text()
    (d / 'enable-fail').touch()
    result = run('worker', 'clean')
    assert result.returncode != 0
    assert not (config / 'dnscrypt-profile.state').exists()
    assert (d / 'restore').read_text() == 'restore 5053\n'
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
    (d / 'hdp-active').touch()
    (d / 'restore').unlink()
    result = run('reset_worker')
    assert result.returncode != 0 and (config / 'dnscrypt-profile.state').exists()
    assert not (d / 'restore').exists()
    (d / 'hdp-active').unlink()
    (d / 'watchdog-fail').touch()
    result = run('reset_worker')
    assert result.returncode != 0 and (config / 'dnscrypt-profile.state').exists()
    assert not (d / 'restore').exists()
    (d / 'watchdog-fail').unlink()
    for flag in ('watchdog-still-active', 'ubus-fail'):
        (d / flag).touch()
        result = run('reset_worker')
        assert result.returncode != 0 and (config / 'dnscrypt-profile.state').exists()
        assert not (d / 'restore').exists()
        (d / flag).unlink()
    (d / 'cron-fail').touch()
    result = run('reset_worker')
    assert result.returncode != 0 and (config / 'dnscrypt-profile.state').exists()
    assert not (d / 'restore').exists()
    (d / 'cron-fail').unlink()
    (d / 'save-fail').touch()
    result = run('reset_worker')
    assert result.returncode != 0 and (config / 'dnscrypt-profile.state').exists()
    assert not (d / 'restore').exists()
    (d / 'save-fail').unlink()
    (d / 'detach-fail').touch()
    result = run('reset_worker')
    assert result.returncode != 0 and (config / 'dnscrypt-profile.state').exists()
    assert not (d / 'restore').exists()
    (d / 'detach-fail').unlink()
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
    assert (d / 'watchdog-disabled').exists()
    assert json.loads((jobs / 'action/output').read_text())['ok'] is True

print('DNSCrypt RPC dispatch and profile job use isolated state and reject unsupported actions')
