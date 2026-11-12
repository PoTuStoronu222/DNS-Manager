#!/usr/bin/env python3
"""Optional network test; DNSCRYPT_BIN must point to dnscrypt-proxy 2.1.x."""
import os
import pathlib
import socket
import struct
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parent.parent
binary = os.environ['DNSCRYPT_BIN']
bootstrap = os.environ.get('DNSCRYPT_BOOTSTRAP', '1.1.1.1:53')
if any(c not in '0123456789abcdefABCDEF.:[]' for c in bootstrap):
    raise SystemExit('DNSCRYPT_BOOTSTRAP must be a literal DNS address with port')


def free_port(used):
    # This is a laboratory test, not a reservation for a production service.
    while True:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        if port not in used:
            used.add(port)
            return port


def query(port, tcp):
    packet = struct.pack('!HHHHHH', 0x2917, 0x100, 1, 0, 0, 0)
    packet += b'\x07example\x03com\x00' + struct.pack('!HH', 1, 1)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM if tcp else socket.SOCK_DGRAM) as sock:
        sock.settimeout(2)
        sock.connect(('127.0.0.1', port))
        if tcp:
            sock.sendall(struct.pack('!H', len(packet)) + packet)
            def read(n):
                data = b''
                while len(data) < n:
                    part = sock.recv(n - len(data))
                    if not part:
                        raise OSError('short TCP DNS response')
                    data += part
                return data
            size = struct.unpack('!H', read(2))[0]
            response = read(size)
        else:
            sock.send(packet)
            response = sock.recv(4096)
    if len(response) < 12:
        return False
    ident, flags, questions, answers, _, _ = struct.unpack('!HHHHHH', response[:12])
    return ident == 0x2917 and bool(flags & 0x8000) and flags & 15 == 0 and questions == 1 and answers > 0


with tempfile.TemporaryDirectory(prefix='dnscrypt-live-') as tmp:
    processes = []
    used_ports = set()
    try:
        for number, url in enumerate(('https://cloudflare-dns.com/dns-query',
                                      'https://dns.google/dns-query'), 1):
            port = free_port(used_ports)
            stamp = subprocess.check_output(['sh', str(root / 'libexec/dns-manager-doh-stamp.sh'), url], text=True).strip()
            config = pathlib.Path(tmp) / f'slot-{number}.toml'
            config.write_text(f"""server_names = ['test']
listen_addresses = ['127.0.0.1:{port}']
cache = false
bootstrap_resolvers = ['{bootstrap}']
ignore_system_dns = true
netprobe_timeout = 0
[static.test]
stamp = '{stamp}'
""")
            log = open(pathlib.Path(tmp) / f'slot-{number}.log', 'w+')
            proc = subprocess.Popen([binary, '-config', str(config)], stdout=log, stderr=log)
            processes.append((proc, log, port, url))

        for proc, log, port, url in processes:
            deadline = time.monotonic() + 40
            while True:
                if proc.poll() is not None:
                    raise RuntimeError(f'{url}: proxy exited with {proc.returncode}')
                try:
                    if query(port, False) and query(port, True):
                        print(f'{url}: UDP and TCP DNS responses OK')
                        break
                except (OSError, struct.error):
                    pass
                if time.monotonic() >= deadline:
                    raise RuntimeError(f'{url}: DNS response not received')
                time.sleep(1)
    except Exception:
        for proc, log, _, url in processes:
            log.flush()
            log.seek(0)
            print(f'--- {url} ---\n{log.read()}')
        raise
    finally:
        for proc, log, _, _ in processes:
            proc.terminate()
        for proc, log, _, _ in processes:
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()
            log.close()
