#!/bin/sh
# Save a DoT selection separately from the active DoH configuration.
# The caller chooses the namespaced destination and holds the mutation lock.
set -eu
input="${1:-}"; destination="${2:-}"; dot_catalog="${3:-}"; dns_catalog="${4:-}"
[ "$#" -ge 4 ] || { echo 'DoT storage is unavailable' >&2; exit 1; }
shift 4
validator="${DOT_SELECTION_VALIDATOR:-/usr/libexec/dns-manager-dot-selection}"
[ -n "$destination" ] && [ -x "$validator" ] || { echo 'DoT storage is unavailable' >&2; exit 1; }
"$validator" "$input" "$dot_catalog" "$dns_catalog" "$@" || exit 1
parent="$(dirname "$destination")"
[ -d "$parent" ] || { echo 'DoT configuration directory is unavailable' >&2; exit 1; }
umask 077
tmp="$(mktemp "$destination.tmp.XXXXXX")" || exit 1
trap 'rm -f "$tmp"' EXIT HUP INT TERM
cat "$input" > "$tmp" || exit 1
"$validator" "$tmp" "$dot_catalog" "$dns_catalog" "$@" || exit 1
chmod 0600 "$tmp" || exit 1
mv -f "$tmp" "$destination" || exit 1
trap - EXIT HUP INT TERM

