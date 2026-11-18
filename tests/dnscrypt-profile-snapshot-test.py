#!/usr/bin/env python3
"""Exercise native profile selection through the real catalog snapshot logic."""
import os
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
backend = (root / 'libexec/backend-dnscrypt.sh').read_text()
snapshot = backend[backend.index('dnscrypt_catalog_snapshot() ('):backend.index('\ndiagnostic() {')]
with tempfile.TemporaryDirectory(prefix='dnscrypt-snapshot-') as directory:
    d = pathlib.Path(directory)
    (d / 'catalog').write_text('# no DoH required\n')
    (d / 'dnscrypt-proxy').write_text(r"""#!/bin/sh
config=$2
log=$(sed -n "s/^log_file = '\(.*\)'$/\1/p" "$config")
printf '%s\n' '[NOTICE] [manager-1] OK (DNSCrypt) - rtt: 18ms' '[NOTICE] Server with the lowest initial latency: manager-1 (rtt: 18ms), live servers: 1' > "$log"
while :; do sleep 1; done
""")
    (d / 'dnscrypt-proxy').chmod(0o755)
    script = """set -e
HELPERS="$TEST_ROOT/libexec"
RUNTIME_DIR="$TEST_TMP"
TMP_DIR="$TEST_TMP"
DNS_CATALOG="$TEST_TMP/catalog"
CUSTOM_DNS_CATALOG="$TEST_TMP/no-custom"
NATIVE_CATALOG="$HELPERS/dns-manager-dnscrypt-catalog.conf"
BOOTSTRAP_DNS=1.1.1.1
DNS_MANAGER_PROTOCOL=native
DNS_MANAGER_LB_STRATEGY=p6
export DNS_MANAGER_PROTOCOL DNS_MANAGER_LB_STRATEGY
load_manager_functions() { :; }
load_config() { :; }
""" + snapshot + """
. "$HELPERS/dns-manager-dnscrypt-profile.sh"
dnscrypt_select_profile clean
printf '%s\n' --privacy--
dnscrypt_select_profile privacy
printf '%s\n' --selected--
printf '%s\n' 'server=native_adguard_unfiltered|sdns://selected' > "$TEST_TMP/selected"
dnscrypt_catalog_snapshot native "$TEST_TMP/selected"
"""
    env = {**os.environ, 'TEST_ROOT': str(root), 'TEST_TMP': directory,
           'PATH': directory + os.pathsep + os.environ['PATH']}
    result = subprocess.run(['sh'], input=script, env=env, text=True,
                            capture_output=True, timeout=20)
    assert result.returncode == 0, result.stderr
    profiles, selected = result.stdout.split('--selected--\n')
    clean, privacy = profiles.split('--privacy--\n')
    assert selected.strip() == 'native_adguard_unfiltered|18', selected
    assert 'native_adguard_unfiltered|sdns://' in clean, clean
    assert 'native_cryptostorm_fr|sdns://' in privacy, privacy
    assert 'https://' not in result.stdout
print('Native profiles consume actual snapshot results without including DoH')
