#!/usr/bin/env python3
"""Do not report a stopped watchdog while it remains enabled or running."""
import os
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parent.parent
source = (root / 'dns-manager.sh').read_text(encoding='utf-8')
start = source.index('watchdog_service_stop_disable() {')
end = source.index('\n}\n', start) + 3
function = source[start:end]
with tempfile.TemporaryDirectory() as tmp:
    directory = pathlib.Path(tmp)
    service = directory / 'service'
    service.write_text('''#!/bin/sh
case "$1" in
  stop) [ -e "$TEST_DIR/stop-fails" ] || rm -f "$TEST_DIR/running" ;;
  disable) [ ! -e "$TEST_DIR/disable-fails" ] || exit 1
           [ -e "$TEST_DIR/disable-lies" ] || rm -f "$TEST_DIR/enabled" ;;
esac
''')
    service.chmod(0o755)
    script = function + '''
WATCHDOG_SERVICE_PATH=$1
watchdog_service_running() { [ -e "$TEST_DIR/running" ]; }
watchdog_service_enabled() { [ -e "$TEST_DIR/enabled" ]; }
err_msg() { printf '%s\\n' "$*" >&2; }
sleep() { :; }
watchdog_service_stop_disable
'''
    env = {**os.environ, 'TEST_DIR': str(directory)}

    def run():
        return subprocess.run(['sh', '-c', script, 'sh', str(service)], env=env, capture_output=True, text=True)

    assert run().returncode == 0
    (directory / 'running').touch()
    (directory / 'enabled').touch()
    assert run().returncode == 0
    assert not (directory / 'running').exists() and not (directory / 'enabled').exists()
    (directory / 'disable-fails').touch()
    assert run().returncode != 0
    (directory / 'disable-fails').unlink()
    (directory / 'enabled').touch()
    (directory / 'disable-lies').touch()
    assert run().returncode != 0
    (directory / 'disable-lies').unlink()
    (directory / 'running').touch()
    (directory / 'stop-fails').touch()
    assert run().returncode != 0
print('PASS: watchdog stop verifies both service and autostart')
