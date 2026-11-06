#!/usr/bin/env python3
"""Optional integration test. Runs under dot-probe-live-test.sh."""
import os
import socket
import subprocess

tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
try:
    for port in range(30000, 31000):
        try:
            tcp.bind(('127.0.0.1', port))
            udp.bind(('127.0.0.1', port))
            break
        except OSError:
            tcp.close()
            udp.close()
            tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    else:
        raise RuntimeError('No suitable temporary test port')
    tcp.listen(1)
    env = os.environ.copy()
    env['DOT_PROBE_START_PORT'] = str(port)
    subprocess.run(['sh', 'libexec/dns-manager-dot-probe.sh', env['DOT_TEST_SELECTION'], 'catalogs/dot-endpoints.conf', 'catalogs/dns-8.7-RU-NOSOCIAL.conf'], check=True, env=env)
    if tcp.getsockname()[1] != port or udp.getsockname()[1] != port:
        raise RuntimeError('An unrelated listener was disturbed')
    print('OK: occupied port was skipped without affecting the existing listener')
finally:
    udp.close()
    tcp.close()
