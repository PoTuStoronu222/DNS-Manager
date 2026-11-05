#!/usr/bin/env python3
"""Isolated Linux networking lab; not production fallback code.

Provide DNS_LAB_PARENT_NETNS and run in a different network namespace with
loopback up, CAP_NET_ADMIN and a path to nft as argv[1].
"""
import concurrent.futures
import os
import socket
import subprocess
import sys
import threading

if len(sys.argv) != 2:
    raise SystemExit('usage: python3 provider-fallback-nft-lab.py /path/to/nft')
nft = sys.argv[1]
parent = os.environ.get('DNS_LAB_PARENT_NETNS', '')
if not parent.isdigit() or os.stat('/proc/self/ns/net').st_ino == int(parent):
    raise SystemExit('run in a new network namespace and provide DNS_LAB_PARENT_NETNS')

def serve(port, answer, kind):
    sock = socket.socket(socket.AF_INET, kind)
    sock.bind(('127.0.0.1', port))
    if kind == socket.SOCK_STREAM:
        sock.listen(16)
    def loop():
        while True:
            try:
                if kind == socket.SOCK_DGRAM:
                    _, peer = sock.recvfrom(64)
                    sock.sendto(answer, peer)
                else:
                    conn, _ = sock.accept()
                    with conn:
                        conn.recv(64)
                        conn.sendall(answer)
            except OSError:
                return
    threading.Thread(target=loop, daemon=True).start()
    return sock

def rule(*args):
    subprocess.run([nft, *args], check=True, stdout=subprocess.DEVNULL)

def socket_for(kind):
    sock = socket.socket(socket.AF_INET, kind)
    sock.settimeout(3)
    return sock

def query(kind, sock=None):
    own = sock is None
    sock = sock or socket_for(kind)
    try:
        if kind == socket.SOCK_DGRAM:
            sock.sendto(b'probe', ('127.0.0.1', 5053))
            return sock.recvfrom(64)[0]
        sock.connect(('127.0.0.1', 5053))
        sock.sendall(b'probe')
        return sock.recv(64)
    finally:
        if own:
            sock.close()

servers = [serve(5053, b'doh', k) for k in (socket.SOCK_DGRAM, socket.SOCK_STREAM)]
servers += [serve(15053, b'provider', k) for k in (socket.SOCK_DGRAM, socket.SOCK_STREAM)]
created = False
try:
    assert all(query(k) == b'doh' for k in (socket.SOCK_DGRAM, socket.SOCK_STREAM))
    rule('add', 'table', 'ip', 'provider_fallback_lab')
    created = True
    rule('add', 'chain', 'ip', 'provider_fallback_lab', 'output', '{', 'type', 'nat', 'hook', 'output', 'priority', 'dstnat', ';', '}')
    for proto in ('udp', 'tcp'):
        rule('add', 'rule', 'ip', 'provider_fallback_lab', 'output', 'ip', 'daddr', '127.0.0.1', proto, 'dport', '5053', 'redirect', 'to', ':15053')
    assert all(query(k) == b'provider' for k in (socket.SOCK_DGRAM, socket.SOCK_STREAM))

    # Keep an occupied port open while another socket requests an available one.
    occupied = socket_for(socket.SOCK_DGRAM)
    occupied.bind(('127.0.0.1', 0))
    probe = socket_for(socket.SOCK_DGRAM)
    probe.bind(('127.0.0.1', 0))
    assert occupied.getsockname()[1] != probe.getsockname()[1]
    occupied.close()
    probe.close()

    # A probe keeps its socket bound while registering an exception for its
    # kernel-assigned port. In production this would require an actual socket
    # owner and lifecycle/cleanup mechanism, not a shell reservation.
    gate = threading.Barrier(4)
    registered = []
    def probe_direct(kind):
        proto = 'udp' if kind == socket.SOCK_DGRAM else 'tcp'
        with socket_for(kind) as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
            registered.append((kind, port))
            rule('insert', 'rule', 'ip', 'provider_fallback_lab', 'output', 'ip', 'daddr', '127.0.0.1', proto, 'sport', str(port), proto, 'dport', '5053', 'return')
            gate.wait(timeout=5)
            return query(kind, sock)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        jobs = [pool.submit(probe_direct, k) for k in (socket.SOCK_DGRAM, socket.SOCK_DGRAM, socket.SOCK_STREAM, socket.SOCK_STREAM)]
        assert [x.result() for x in jobs] == [b'doh'] * 4
    assert all(query(k) == b'provider' for k in (socket.SOCK_DGRAM, socket.SOCK_STREAM))
    # A stale exception also exempts a new socket after its original owner closes.
    old_port = next(port for kind, port in registered if kind == socket.SOCK_DGRAM)
    with socket_for(socket.SOCK_DGRAM) as reused:
        reused.bind(('127.0.0.1', old_port))
        assert query(socket.SOCK_DGRAM, reused) == b'doh'
    print('WARNING: stale probe exception also exempts a reused source port')
    rule('delete', 'table', 'ip', 'provider_fallback_lab')
    assert all(query(k) == b'doh' for k in (socket.SOCK_DGRAM, socket.SOCK_STREAM))
    print('OK: UDP/TCP redirect, held ports, concurrent isolated probes, and removal in a network namespace')
finally:
    if created:
        subprocess.run([nft, 'delete', 'table', 'ip', 'provider_fallback_lab'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for server in servers:
        server.close()
