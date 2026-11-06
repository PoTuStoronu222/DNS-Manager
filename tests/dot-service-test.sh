#!/bin/sh
set -eu
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT HUP INT TERM
cp libexec/dns-manager-dot-config.sh "$t/generator"; chmod +x "$t/generator"
sed -e "s|^DOT_CONFIG=.*|DOT_CONFIG=$t/slots|" -e "s|^DOT_CATALOG=.*|DOT_CATALOG=$PWD/catalogs/dot-endpoints.conf|" -e "s|^DOT_GENERATOR=.*|DOT_GENERATOR=$t/generator|" -e "s|^DOT_RUN=.*|DOT_RUN=$t/run|" -e "s|^DOT_PORTS=.*|DOT_PORTS=$t/manager.conf|" files/dns-manager-dot.init > "$t/service"
. "$t/service"
stubby() { [ "$1" = -i ] && [ "$2" = -C ] && [ -s "$3" ]; }
procd_open_instance() { printf '%s\n' "$1" >> "$t/instances"; }
procd_set_param() { :; }; procd_close_instance() { :; }
printf '%s\n' '1|cloudflare_clean' '2|google_clean' > "$t/slots"
printf '%s\n' "PORT_1='15553'" "PORT_2='15554'" > "$t/manager.conf"
start_service || exit 1
[ "$(cat "$t/instances")" = "$(printf 'slot_1\nslot_2')" ] || exit 1
grep -qx '  - 127.0.0.1@15553' "$t/run/1.yml" && grep -qx '  - 127.0.0.1@15554' "$t/run/2.yml" || exit 1
: > "$t/instances"; printf '%s\n' '1|cloudflare_clean' '1|google_clean' > "$t/slots"
if start_service; then echo 'FAIL: duplicate slot accepted' >&2; exit 1; fi
[ ! -s "$t/instances" ] || exit 1
printf '%s\n' '1|cloudflare_clean' '2|google_clean' > "$t/slots"
printf '%s\n' "PORT_1='15553'" "PORT_2='15553'" > "$t/manager.conf"
if start_service; then echo 'FAIL: duplicate manager ports accepted' >&2; exit 1; fi
printf '%s\n' "PORT_1='15553'" > "$t/manager.conf"
if start_service; then echo 'FAIL: missing manager port accepted' >&2; exit 1; fi
printf '%s\n' "PORT_1='15553'" "PORT_2='15554'" "PORT_2='15555'" > "$t/manager.conf"
if start_service; then echo 'FAIL: duplicate manager port field accepted' >&2; exit 1; fi
printf '%s\n' '1|unknown' > "$t/slots"
if start_service 2>/dev/null; then echo 'FAIL: unknown endpoint accepted' >&2; exit 1; fi
[ ! -s "$t/instances" ] || exit 1
echo 'OK: isolated DoT service validates every slot before starting instances'

