#!/bin/sh
# Experimental: guard a read/reload using UCI's shared file-lock convention.
# Usage: package command [args...]. No cache configuration is modified here.
set -eu
[ "$#" -ge 2 ] || exit 2
package=$1
shift
case "$package" in ''|*[!A-Za-z0-9_]*) exit 2 ;; esac
file="/etc/config/$package"
delta="/tmp/.uci/$package"
[ -f "$file" ] && [ ! -L "$file" ] || exit 1
mkdir -p /tmp/.uci
exec 8<"$file"
exec 9>>"$delta"
# The base file is always locked first, matching libuci commit order. Nonblocking
# locks fail instead of stalling the UI if another UCI operation is in progress.
flock -s -n 8 || exit 1
flock -s -n 9 || exit 1
[ ! -s "$delta" ] || { echo 'Pending UCI changes; refusing to reload' >&2; exit 1; }
"$@"
