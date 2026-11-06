#!/bin/sh
# Probe DoT on temporary loopback ports without changing DNS or UCI.
set -eu
selection="${1:-}"; dot_catalog="${2:-}"; dns_catalog="${3:-}"
[ "$#" -ge 3 ] || { echo 'Selection or catalog is unavailable' >&2; exit 1; }
shift 3
validator="${DOT_SELECTION_VALIDATOR:-/usr/libexec/dns-manager-dot-selection}"
generator="${DOT_CONFIG_GENERATOR:-/usr/libexec/dns-manager-dot-config}"
stubby="${DOT_STUBBY:-stubby}"
dig="${DOT_DIG:-dig}"
start_port="${DOT_PROBE_START_PORT:-$((20000 + ($$ % 20000)))}"
case "$start_port" in ''|*[!0-9]*) echo 'Invalid temporary DNS port' >&2; exit 1;; esac
[ "$start_port" -ge 1024 ] 2>/dev/null && [ "$start_port" -le 60000 ] 2>/dev/null || { echo 'Invalid temporary DNS port' >&2; exit 1; }
[ -x "$validator" ] && [ -x "$generator" ] || { echo 'DoT helpers unavailable' >&2; exit 1; }
command -v "$stubby" >/dev/null 2>&1 && command -v "$dig" >/dev/null 2>&1 || { echo 'Stubby or dig unavailable' >&2; exit 1; }
"$validator" "$selection" "$dot_catalog" "$dns_catalog" "$@" || exit 1
for table in /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6; do
    [ -r "$table" ] || { echo 'Cannot inspect local DNS ports' >&2; exit 1; }
done
t="$(mktemp -d "${TMPDIR:-/tmp}/dns-manager-dot-probe.XXXXXX")" || exit 1
pid=''; pid_start=''
same_child() {
    [ -n "$pid" ] && [ -n "$pid_start" ] && [ "$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)" = "$pid_start" ]
}
stop_child() {
    [ -n "$pid" ] || return 0
    if same_child; then kill "$pid" 2>/dev/null || true; fi
    for _stop_try in 1 2 3; do
        same_child || break
        sleep 1
    done
    if same_child; then kill -9 "$pid" 2>/dev/null || true; fi
    wait "$pid" 2>/dev/null || true
    pid=''; pid_start=''
}
cleanup() {
    stop_child
    rm -rf "$t"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
port_busy() {
    h="$(printf '%04X' "$1")"
    awk -v p="$h" 'FNR>1 {split($2,a,":"); if(toupper(a[2])==p) found=1} END {exit !found}' /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6
}
port_owned() {
    # Stubby must own both TCP and UDP sockets; another listener cannot satisfy a probe.
    p="$1"; h="$(printf '%04X' "$p")"
    : > "$t/inodes"
    for fd in /proc/"$pid"/fd/*; do
        readlink "$fd" 2>/dev/null | sed -n 's/^socket:\[\([0-9][0-9]*\)\]$/\1/p' >> "$t/inodes" || true
    done
    for table in /proc/net/tcp /proc/net/udp; do
        awk -v p="$h" 'NR>1 {split($2,a,":"); if(toupper(a[2])==p) print $10}' "$table" > "$t/ports"
        grep -Fxf "$t/inodes" "$t/ports" >/dev/null 2>&1 || return 1
        if grep -Fvxf "$t/inodes" "$t/ports" >/dev/null 2>&1; then return 1; fi
    done
    if awk -v p="$h" 'FNR>1 {split($2,a,":"); if(toupper(a[2])==p) found=1} END{exit !found}' /proc/net/tcp6 /proc/net/udp6; then return 1; fi
}
answer_ok() {
    "$dig" @127.0.0.1 -p "$1" example.com A +time=2 +tries=1 +short "$2" 2>/dev/null |
        awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $0!="0.0.0.0" && $0 !~ /^127\./ {ok=1} END{exit !ok}'
}
while IFS='|' read -r slot id extra; do
    [ -n "$slot" ] || continue
    port="$start_port"; attempts=0
    while port_busy "$port"; do
        port=$((port+1)); attempts=$((attempts+1))
        [ "$port" -le 60000 ] && [ "$attempts" -lt 100 ] || { echo 'No free temporary DNS port' >&2; exit 1; }
    done
    "$generator" "$id" "$port" "$dot_catalog" > "$t/stage.yml" || exit 1
    "$stubby" -i -C "$t/stage.yml" >/dev/null 2>&1 || { echo "Invalid DoT configuration for slot $slot" >&2; exit 1; }
    "$stubby" -C "$t/stage.yml" > "$t/stubby.log" 2>&1 &
    pid=$!
    pid_start="$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null || true)"
    [ -n "$pid_start" ] || { kill "$pid" 2>/dev/null || true; pid=''; echo "Temporary DoT process did not start for slot $slot" >&2; exit 1; }
    ready=0
    for tries in 1 2 3 4 5; do
        same_child || break
        if port_owned "$port" && same_child; then ready=1; break; fi
        sleep 1
    done
    [ "$ready" = 1 ] || { echo "Temporary DoT listener did not start for slot $slot" >&2; exit 1; }
    { answer_ok "$port" +notcp || answer_ok "$port" +notcp; } && { answer_ok "$port" +tcp || answer_ok "$port" +tcp; } && same_child && port_owned "$port" || { echo "DoT probe failed for slot $slot" >&2; exit 1; }
    stop_child
    printf 'DoT slot %s: OK\n' "$slot"
done < "$selection"

