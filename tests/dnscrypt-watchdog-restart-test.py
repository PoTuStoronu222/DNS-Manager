#!/usr/bin/env python3
"""Exercise DNSCrypt watchdog recovery without touching a running resolver."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parent.parent / "dns-manager.sh").read_text()
start = source.index("watchdog_dnscrypt_check() {")
end = source.index("\nrun_watchdog() {", start)
function = source[start:end]
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    (root / "dnscrypt-engine").write_text("dnscrypt-proxy2\n")
    init = root / "init"
    init.write_text("#!/bin/sh\n[ \"$1\" != restart ] || echo restart >> \"$STATE_DIR/restarts\"\n")
    init.chmod(0o755)
    runner = r"""
STATE_DIR=$1 CFG_DIR=$1 DNS_MANAGER_DNSCRYPT_INIT=$1/init
export STATE_DIR
WATCHDOG_ENABLED=1 WATCHDOG_FAIL_THRESHOLD=2
load_config() { :; }
load_watchdog_state() { [ ! -f "$STATE_DIR/state" ] || . "$STATE_DIR/state"; }
save_watchdog_state() { printf 'WD_FAIL_1=%s\nWD_RECOVERY_BLOCKED_1=%s\n' "$WD_FAIL_1" "$WD_RECOVERY_BLOCKED_1" > "$STATE_DIR/state"; }
watchdog_check_due() { :; }
local_dns_query_ok() { [ "$DNS_OK" = 1 ]; }
ping() { [ "$WAN_OK" = 1 ]; }
watchdog_loop_repair_cooldown_ok() { [ "$WD_RECOVERY_BLOCKED_1" != 1 ]; }
watchdog_loop_mark_repair() { :; }
acquire_mutation_lock() { :; }
release_mutation_lock() { :; }
logger() { :; }
watchdog_append_check_record() { printf '%s' "$5" > "$STATE_DIR/result"; }
watchdog_save_check_results() { rm -f "$1"; }
watchdog_dnscrypt_check
"""
    import os
    def run(wan, dns):
        env = dict(os.environ, WAN_OK=str(wan), DNS_OK=str(dns))
        subprocess.run(["sh", "-c", function + runner, "sh", tmp], env=env, check=True)
    def restarts():
        path = root / "restarts"
        return path.read_text().count("restart") if path.exists() else 0
    run(0, 0); run(0, 0); run(0, 0)
    assert restarts() == 0
    run(1, 0); assert restarts() == 0
    run(1, 0); assert restarts() == 1
    run(1, 0); assert restarts() == 1
    run(1, 1); assert (root / "result").read_text() == "OK"
    run(1, 0); run(1, 0); assert restarts() == 2
    (root / "dnscrypt-engine").write_text("https-dns-proxy\n")
    run(1, 1); run(1, 0); run(1, 0); assert restarts() == 2
print("PASS: DNSCrypt recovery, WAN outage, retry limit and engine switch")
