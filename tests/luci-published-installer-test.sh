#!/bin/sh
set -eu
file="${1:-dns-manager-luci.sh}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cr="$(printf '\r')"
if LC_ALL=C grep -q "$cr" "$file"; then
    echo 'FAIL: LuCI installer contains Windows CRLF line endings' >&2
    exit 1
fi
awk '/^validate_candidate\(\) \{/,/^}/' "$file" > "$tmp/validate"
[ -s "$tmp/validate" ] || exit 1
. "$tmp/validate"
validate_candidate "$file" || { echo 'FAIL: LuCI updater rejected the installer' >&2; exit 1; }
echo 'OK: LuCI installer passes updater validation without line-ending conversion'
