#!/usr/bin/env python3
"""Optional real-network test; DNSCRYPT_BIN points to dnscrypt-proxy 2.1.x."""
import os
import pathlib
import socket
import struct
import subprocess
import tempfile
import time
import tomllib

root = pathlib.Path(__file__).resolve().parent.parent
binary = os.environ['DNSCRYPT_BIN']
bootstrap = os.environ.get('DNSCRYPT_BOOTSTRAP', '1.1.1.1')

with socket.socket() as listener:
    listener.bind(('127.0.0.1', 0))
    port = listener.getsockname()[1]

generated = subprocess.run(['sh', str(root / 'libexec/dns-manager-dnscrypt-pool.sh'),
                            str(port), bootstrap],
                           input='https://cloudflare-dns.com/dns-query\nhttps://dns.google/dns-query\n',
                           text=True, capture_output=True, check=True).stdout
assert tomllib.loads(generated)['server_names'] == ['manager-1', 'manager-2']

packet = struct.pack('!HHHHHH', 0x2917, 0x100, 1, 0, 0, 0)
packet += b'\x07example\x03com\x00' + struct.pack('!HH', 1, 1)


def query(tcp):
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
                        raise OSError('short TCP response')
                    data += part
                return data

            response = read(struct.unpack('!H', read(2))[0])
        else:
            sock.send(packet)
            response = sock.recv(4096)
    if len(response) < 12:
        return False
    ident, flags, questions, answers, _, _ = struct.unpack('!HHHHHH', response[:12])
    return ident == 0x2917 and bool(flags & 0x8000) and flags & 15 == 0 and questions == 1 and answers > 0


with tempfile.TemporaryDirectory(prefix='dnscrypt-pool-live-') as tmp:
    path = pathlib.Path(tmp)
    config = path / 'dnscrypt.toml'
    config.write_text(generated, encoding='utf-8')
    with (path / 'proxy.log').open('w+') as log:
        process = subprocess.Popen([binary, '-config', str(config)], stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 40
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError(f'proxy exited with {process.returncode}')
                try:
                    if query(False) and query(True):
                        break
                except (OSError, struct.error):
                    pass
                time.sleep(1)
            else:
                raise RuntimeError('No valid UDP and TCP DNS responses')
            print('One dnscrypt-proxy process returned real DNS answers over UDP and TCP')
        except Exception:
            log.flush()
            log.seek(0)
            print(log.read())
            raise
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
