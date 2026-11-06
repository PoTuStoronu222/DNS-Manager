#!/bin/sh
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
cat > "$t/validator" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$t/generator" <<'EOF'
#!/bin/sh
echo unexpected > "$SENTINEL"
EOF
cat > "$t/stubby" <<'EOF'
#!/bin/sh
echo unexpected > "$SENTINEL"
EOF
cp "$t/stubby" "$t/dig"
chmod +x "$t/validator" "$t/generator" "$t/stubby" "$t/dig"
DOT_SELECTION_VALIDATOR="$t/validator"; DOT_CONFIG_GENERATOR="$t/generator"; DOT_STUBBY="$t/stubby"; DOT_DIG="$t/dig"; SENTINEL="$t/called"
export DOT_SELECTION_VALIDATOR DOT_CONFIG_GENERATOR DOT_STUBBY DOT_DIG SENTINEL
if sh libexec/dns-manager-dot-probe.sh missing missing missing >/dev/null 2>&1; then echo 'FAIL: invalid selection accepted' >&2; exit 1; fi
[ ! -e "$SENTINEL" ] || { echo 'FAIL: service launched before selection validation' >&2; exit 1; }
DOT_PROBE_START_PORT='53;bad'; export DOT_PROBE_START_PORT
if sh libexec/dns-manager-dot-probe.sh missing missing missing >/dev/null 2>&1; then exit 1; fi
[ ! -e "$SENTINEL" ] || exit 1
echo 'OK: DoT preflight rejects invalid inputs before starting a process'
