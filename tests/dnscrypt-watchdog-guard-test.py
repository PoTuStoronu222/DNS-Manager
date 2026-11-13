#!/usr/bin/env python3
"""The legacy watchdog must not run against the DNSCrypt engine."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
source = (root / 'dns-manager.sh').read_text(encoding='utf-8')
start = source.index('watchdog_legacy_engine_allowed() {')
end = source.index('\n}\n', source.index('watchdog_embedded_loop() {', start)) + 3
functions = source[start:end]
with tempfile.TemporaryDirectory() as tmp:
    directory = pathlib.Path(tmp)
    marker = directory / 'dnscrypt-engine'
    sentinel = directory / 'loaded'
    script = functions + '''
CFG_DIR=$1
STATE_DIR=$1
SENTINEL=$2
load_config() { : > "$SENTINEL"; WATCHDOG_ENABLED=0; FORCE_DOH=0; }
watchdog_embedded_loop
'''

    def run(value):
        marker.unlink(missing_ok=True)
        sentinel.unlink(missing_ok=True)
        if value == 'broken':
            marker.symlink_to(directory / 'missing')
        elif value is not None:
            marker.write_text(value)
        result = subprocess.run(['sh', '-c', script, 'sh', str(directory), str(sentinel)], capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        return sentinel.exists()

    assert run(None) and run('https-dns-proxy\n')
    assert not run('dnscrypt-proxy2\n')
    assert not run('unexpected\n') and not run('') and not run('broken')
print('PASS: legacy watchdog ignores DNSCrypt and invalid engine selections')
