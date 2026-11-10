#!/usr/bin/env python3
"""Optional local experiment using dnsmasq and a synthetic UDP DNS upstream."""
import os
import pwd
import socket
import struct
import subprocess
import threading
import time

DNSMASQ = os.environ.get("DNSMASQ_BIN", "dnsmasq")
QUESTION = b"\x07example\x04test\x00\x00\x01\x00\x01"
QUERY = b"\x12\x34\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00" + QUESTION


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def run_case(minimum, expected):
    upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    upstream.bind(("127.0.0.1", 0))
    upstream.settimeout(0.2)
    upstream_port = upstream.getsockname()[1]
    count = [0]
    stopping = threading.Event()

    def serve():
        while not stopping.is_set():
            try:
                data, peer = upstream.recvfrom(512)
            except socket.timeout:
                continue
            count[0] += 1
            # The forwarded query can contain an EDNS OPT record. Only copy
            # the question; placing that OPT before the answer is malformed.
            end = 12
            while end < len(data) and data[end]:
                end += 1 + data[end]
            end += 5
            response = data[:2] + b"\x81\x80\x00\x01\x00\x01\x00\x00\x00\x00" + data[12:end]
            response += b"\xc0\x0c\x00\x01\x00\x01" + struct.pack("!I", 1) + b"\x00\x04\xc0\x00\x02\x2a"
            upstream.sendto(response, peer)

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    port = free_port()
    args = [DNSMASQ, "--no-daemon", "--no-resolv", "--no-hosts", "--no-poll",
            "--listen-address=127.0.0.1", "--port=" + str(port),
            "--server=127.0.0.1#" + str(upstream_port), "--cache-size=10",
            "--min-cache-ttl=" + str(minimum), "--user=" + pwd.getpwuid(os.getuid()).pw_name]
    process = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        def query():
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
                sock.settimeout(1)
                sock.sendto(QUERY, ("127.0.0.1", port))
                data, _ = sock.recvfrom(512)
                if data[:2] != QUERY[:2] or len(data) < 12 or data[3] & 15:
                    raise AssertionError("invalid DNS response")
        deadline = time.monotonic() + 5
        while True:
            try:
                query()
                break
            except (TimeoutError, ConnectionRefusedError):
                if process.poll() is not None or time.monotonic() >= deadline:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=5)
                    raise RuntimeError("dnsmasq did not start: " + process.stderr.read().decode(errors="replace"))
        time.sleep(2.1)
        query()
        if count[0] != expected:
            raise AssertionError("min TTL %d: expected %d upstream queries, got %d" % (minimum, expected, count[0]))
    finally:
        process.terminate()
        process.wait(timeout=5)
        stopping.set()
        thread.join(timeout=2)
        upstream.close()


run_case(0, 2)
run_case(5, 1)
print("OK: configured minimum TTL keeps short-lived DNS answers in memory longer")
