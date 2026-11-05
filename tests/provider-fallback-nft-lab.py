#!/usr/bin/env python3
"""Run only in a disposable network namespace: python3 SCRIPT /path/to/nft.

Demonstrates that a simple NAT rule also intercepts local DoH health checks.
Requires loopback up and CAP_NET_ADMIN in the current network namespace.
"""
import os
import socket
import subprocess
import sys
import threading

if len(sys.argv) != 2:
    raise SystemExit('usage: python3 provider-fallback-nft-lab.py /path/to/nft')
nft = sys.argv[1]
parent_netns = os.environ.get('DNS_LAB_PARENT_NETNS', '')
if not parent_netns.isdigit() or os.stat('/proc/self/ns/net').st_ino == int(parent_netns):
    raise SystemExit('run in a new network namespace and provide DNS_LAB_PARENT_NETNS')

def serve(port, answer):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(('127.0.0.1', port))
    def loop():
        while True:
            try:
                _, peer = s.recvfrom(64)
                s.sendto(answer, peer)
            except OSError:
                return
    threading.Thread(target=loop, daemon=True).start()
    return s

def query(source_port=None):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.settimeout(3)
        if source_port is not None:
            s.bind(('127.0.0.1', source_port))
        s.sendto(b'probe', ('127.0.0.1', 5053))
        return s.recvfrom(64)[0]

def rule(*args):
    subprocess.run([nft, *args], check=True, stdout=subprocess.DEVNULL)

original, backup = serve(5053, b'doh'), serve(15053, b'provider')
created = False
try:
    assert query() == b'doh'
    rule('add', 'table', 'ip', 'provider_fallback_lab')
    created = True
    rule('add', 'chain', 'ip', 'provider_fallback_lab', 'output', '{', 'type', 'nat', 'hook', 'output', 'priority', 'dstnat', ';', '}')
    rule('add', 'rule', 'ip', 'provider_fallback_lab', 'output', 'ip', 'daddr', '127.0.0.1', 'udp', 'dport', '5053', 'redirect', 'to', ':15053')
    client = query()
    watchdog = query()
    assert client == b'provider' and watchdog == b'provider'
    rule('insert', 'rule', 'ip', 'provider_fallback_lab', 'output', 'ip', 'daddr', '127.0.0.1', 'udp', 'sport', '15453', 'udp', 'dport', '5053', 'return')
    assert query(15453) == b'doh', 'explicitly bound probe did not reach DoH'
    assert query() == b'provider', 'client did not reach provider'
    print('OK: dedicated source port bypasses the rule in this isolated experiment')
    rule('delete', 'table', 'ip', 'provider_fallback_lab')
    assert query() == b'doh'
    print('OK: redirect and removal work; unrestricted local watchdog probe is also redirected')
finally:
    if created:
        subprocess.run([nft, 'delete', 'table', 'ip', 'provider_fallback_lab'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    original.close()
    backup.close()
