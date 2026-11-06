#!/usr/bin/env python3
"""Optional development-host test. Requires real Stubby and outbound TCP/853."""
import os
import pathlib
import socket
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
STUBBY = os.environ.get('STUBBY_BIN', 'stubby')
QUERY = bytes.fromhex('123401000001000000000000076578616d706c6503636f6d0000010001')

def ask(port):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.settimeout(12)
        s.sendto(QUERY, ('127.0.0.1', port))
        return s.recv(2048)

with tempfile.TemporaryDirectory(prefix='dns-manager-dot-test-') as td:
    processes = []
    try:
        for name, port, wrong_name in [('cloudflare_clean', 15453, False), ('cloudflare_clean', 15454, False), ('cloudflare_clean', 15455, True)]:
            config = subprocess.check_output(['sh', str(ROOT / 'libexec/dns-manager-dot-config.sh'), name, str(port), str(ROOT / 'catalogs/dot-endpoints.conf')], text=True)
            if wrong_name:
                config = config.replace('one.one.one.one', 'dns.google')
            path = pathlib.Path(td) / (str(port) + '.yml')
            path.write_text(config, encoding='utf-8')
            subprocess.run([STUBBY, '-i', '-C', str(path)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            processes.append(subprocess.Popen([STUBBY, '-C', str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        time.sleep(1)
        if any(p.poll() is not None for p in processes):
            raise RuntimeError('Stubby instance did not start; a test port may be busy')
        for port in (15453, 15454):
            for attempt in range(3):
                try:
                    response = ask(port)
                except socket.timeout:
                    response = b''
                if len(response) >= 12 and response[:2] == QUERY[:2] and response[3] & 15 == 0 and int.from_bytes(response[6:8], 'big'):
                    break
                time.sleep(1)
            if len(response) < 12 or response[:2] != QUERY[:2] or response[3] & 15 or int.from_bytes(response[6:8], 'big') < 1:
                raise RuntimeError('No valid DNS response through DoT on port %d: %s' % (port, response[:12].hex()))
        try:
            response = ask(15455)
        except socket.timeout:
            response = b''
        if len(response) >= 12 and response[3] & 15 == 0 and int.from_bytes(response[6:8], 'big'):
            raise RuntimeError('DoT query succeeded despite wrong TLS authentication name')
        print('OK: independent Stubby listeners answered via DoT and rejected an incorrect TLS name')
    finally:
        for process in processes:
            process.terminate()
        for process in processes:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
