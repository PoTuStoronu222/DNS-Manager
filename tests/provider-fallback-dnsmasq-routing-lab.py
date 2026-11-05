#!/usr/bin/env python3
"""Isolated experiment, not a fallback implementation. Usage: python3 script DNSMASQ."""
import socket, struct, subprocess, sys, tempfile, threading, time
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit('usage: python3 provider-fallback-dnsmasq-routing-lab.py /path/to/dnsmasq')

def upstream(rcode, delay):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(('127.0.0.1', 0))
    def serve():
        while True:
            try:
                data, addr = sock.recvfrom(4096)
                time.sleep(delay)
                flags = 0x8180 | rcode
                answer = (b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 30, 4) + bytes([203, 0, 113, 5])) if not rcode else b''
                response = data[:2] + struct.pack('!HHHHH', flags, 1, int(not rcode), 0, 0) + data[12:] + answer
                sock.sendto(response, addr)
            except OSError:
                return
    threading.Thread(target=serve, daemon=True).start()
    return sock

def query(port, name):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(3)
    labels = b''.join(bytes([len(x)]) + x.encode('ascii') for x in name.split('.')) + b'\0'
    sock.sendto(struct.pack('!HHHHHH', 1234, 0x0100, 1, 0, 0, 0) + labels + struct.pack('!HH', 1, 1), ('127.0.0.1', port))
    data, _ = sock.recvfrom(4096)
    return struct.unpack('!H', data[2:4])[0] & 15

bad, good = upstream(2, 0), upstream(0, 0.15)
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
    probe.bind(('127.0.0.1', 0))
    port = probe.getsockname()[1]
with tempfile.TemporaryDirectory() as temp:
    conf = Path(temp) / 'dnsmasq.conf'
    conf.write_text(f'port={port}\nlisten-address=127.0.0.1\nbind-interfaces\nno-resolv\nno-hosts\nno-poll\nall-servers\ncache-size=0\nserver=127.0.0.1#{bad.getsockname()[1]}\nserver=127.0.0.1#{good.getsockname()[1]}\nserver=/specific.example/127.0.0.1#{bad.getsockname()[1]}\nserver=/specific.example/127.0.0.1#{good.getsockname()[1]}\nserver=/good.example/127.0.0.1#{good.getsockname()[1]}\n')
    proc = subprocess.Popen([sys.argv[1], '--keep-in-foreground', '--conf-file=' + str(conf)], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        time.sleep(0.3)
        if proc.poll() is not None:
            raise RuntimeError(proc.stderr.read().decode())
        control = query(port, 'a.good.example')
        if control != 0:
            raise RuntimeError(f'control upstream failed: rcode={control}')
        general = query(port, 'general.example')
        specific = query(port, 'a.specific.example')
        print(f'fast SERVFAIL, slower NOERROR: general rcode={general}; domain route rcode={specific}')
        if general != 0 or specific != 0:
            raise SystemExit('FAIL: mixed upstreams did not yield a successful result')
    finally:
        proc.terminate()
        proc.wait(timeout=5)
bad.close()
good.close()
