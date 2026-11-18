#!/usr/bin/env python3
"""Run catalog-page worker checks in /tmp on an OpenWrt router, without changing DNS."""
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
luci = (root / 'dns-manager-luci.sh').read_text(encoding='utf-8')
backend = (root / 'libexec/backend-dnscrypt.sh').read_text(encoding='utf-8')
page = luci[luci.index('job_execute_test_page() {'):luci.index('\njob_execute_test_one() {')]
snapshot = backend[backend.index('dnscrypt_catalog_snapshot() ('):backend.index('\ndiagnostic() {')]
native = (root / 'libexec/dns-manager-dnscrypt-catalog.conf').read_text(encoding='utf-8')
script = r'''set -e
work=$(mktemp -d /tmp/dm-page-lab.XXXXXX)
trap 'rm -rf "$work"' EXIT
before=$(uci export dhcp | sha256sum)
before_config=$(sha256sum /etc/dnscrypt-proxy2/dnscrypt-proxy.toml 2>/dev/null || :)
mkdir -p "$work/jobs/test_page" "$work/jobs/health" "$work/tmp" "$work/runtime"
JOB_DIR="$work/jobs"; TMP_ROOT="$work"; TMP_DIR="$work/tmp"; RUNTIME_DIR="$work/runtime"
HELPERS=/usr/lib/dns-manager-luci/dnscrypt
TEST_RESULTS="$work/results"; TEST_BATCH=2; BOOTSTRAP_DNS=1.1.1.1
DNS_CATALOG="$work/catalog"; CUSTOM_DNS_CATALOG="$work/no-custom"; NATIVE_CATALOG="$work/native"
export JOB_DIR TMP_ROOT TMP_DIR RUNTIME_DIR HELPERS TEST_RESULTS TEST_BATCH BOOTSTRAP_DNS DNS_CATALOG CUSTOM_DNS_CATALOG NATIVE_CATALOG
load_manager() { :; }; load_manager_functions() { :; }; load_config() { :; }
acquire_test_lock() { :; }; release_test_lock() { :; }; set_check_stamp() { :; }
new_job_id() { printf '%s' "$1"; }
json_quote() { printf '"%s"' "$1"; }
job_write() { _id="$1"; _key="$2"; _value="$3"; printf '%s=%s\n' "$_key" "$_value" >> "$JOB_DIR/$_id/state"; }
job_record_pid() { jobpid="$2"; }
test_one_dns() {
  sleep 1
  printf '%s|clean|%s|12|OK\n' "$1" "$1" > "$TMP_DIR/t.$1"
  if [ "${STOP_TEST:-0}" = 1 ] && [ "$1" = a ]; then : > "$STOP_FILE"; fi
}
cat > "$DNS_CATALOG" <<'CATALOG'
a|clean|doh|A|https://a.example/dns-query
b|clean|doh|B|https://b.example/dns-query
c|clean|doh|C|https://c.example/dns-query
d|clean|doh|D|https://d.example/dns-query
e|clean|doh|E|https://e.example/dns-query
f|clean|doh|F|https://f.example/dns-query
CATALOG
cat > "$NATIVE_CATALOG" <<'NATIVE'
''' + native + r'''NATIVE
''' + page + '\n' + snapshot + r'''
# HTTPS worker: cancellation finishes the current group and retains older results.
printf 'c|clean|C|77|OK\n' > "$TEST_RESULTS"
STOP_TEST=1; STOP_FILE="$JOB_DIR/test_page/cancel"; export STOP_TEST STOP_FILE
job_execute_test_page a,b,c,d >/dev/null; wait "$jobpid"
grep -q '^cancelled=1$' "$JOB_DIR/test_page/state"
grep -q '^a|clean|a|12|OK$' "$TEST_RESULTS"
grep -q '^b|clean|b|12|OK$' "$TEST_RESULTS"
grep -q '^c|clean|C|77|OK$' "$TEST_RESULTS"
! grep -q '^d|' "$TEST_RESULTS"
rm -f "$STOP_FILE"; STOP_TEST=0; export STOP_TEST
job_execute_test_page c,d >/dev/null; wait "$jobpid"
grep -q '^c|clean|c|12|OK$' "$TEST_RESULTS"
grep -q '^d|clean|d|12|OK$' "$TEST_RESULTS"
grep -q '^a|clean|a|12|OK$' "$TEST_RESULTS"
echo 'HTTPS: page selection, cancellation, cache merge OK'
# DNSCrypt mode: DoH page checks and cache merging run through real jshn.
printf 'a\nb\n' > "$JOB_DIR/health/ids"
dnscrypt_catalog_snapshot
jsonfilter -i "$RUNTIME_DIR/dnscrypt-catalog-latencies.json" -e '@.a' | grep -qx 12
jsonfilter -i "$RUNTIME_DIR/dnscrypt-catalog-latencies.json" -e '@.b' | grep -qx 12
printf 'c\nd\n' > "$JOB_DIR/health/ids"
dnscrypt_catalog_snapshot
jsonfilter -i "$RUNTIME_DIR/dnscrypt-catalog-latencies.json" -e '@.a' | grep -qx 12
jsonfilter -i "$RUNTIME_DIR/dnscrypt-catalog-latencies.json" -e '@.c' | grep -qx 12
printf 'a\nb\nc\nd\ne\nf\n' > "$JOB_DIR/health/ids"
STOP_TEST=1; STOP_FILE="$JOB_DIR/health/cancel"; export STOP_TEST STOP_FILE
dnscrypt_catalog_snapshot
! jsonfilter -i "$RUNTIME_DIR/dnscrypt-catalog-latencies.json" -e '@.e' | grep -q .
echo 'DNSCrypt: page selection, cancellation, cache merge OK'
rm -f "$JOB_DIR/health/cancel"; STOP_TEST=0; export STOP_TEST
printf 'native_adguard_unfiltered\n' > "$JOB_DIR/health/ids"
dnscrypt_catalog_snapshot
value=$(jsonfilter -i "$RUNTIME_DIR/dnscrypt-catalog-latencies.json" -e '@.native_adguard_unfiltered')
case "$value" in ''|*[!0-9-]*) echo 'No native DNSCrypt result' >&2; exit 1;; esac
echo "DNSCrypt: real proxy native-server result $value"
printf 'native_adguard_unfiltered\nnative_adguard_default\nnative_cryptostorm_fr\n' > "$JOB_DIR/health/ids"
dnscrypt_catalog_snapshot & probe_job=$!
sleep 1; : > "$JOB_DIR/health/cancel"; wait "$probe_job"
echo 'DNSCrypt: native proxy check stopped without changing the active service'
[ "$before" = "$(uci export dhcp | sha256sum)" ]
[ "$before_config" = "$(sha256sum /etc/dnscrypt-proxy2/dnscrypt-proxy.toml 2>/dev/null || :)" ]
nslookup openwrt.org 127.0.0.1 >/dev/null
echo 'Router DNS configuration unchanged; dnsmasq resolves'
'''
target = sys.argv[1] if len(sys.argv) > 1 else 'root@192.168.1.1'
subprocess.run(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=5', target, 'sh -s'],
               input=script, text=True, check=True)
