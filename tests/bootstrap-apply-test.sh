#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
awk '/^bootstrap_normalize_addresses\(\) \{/,/^}/' "$ROOT/dns-manager.sh" > "$tmp/functions"
awk '/^bootstrap_apply_selection\(\) \{/,/^}/' "$ROOT/dns-manager.sh" >> "$tmp/functions"
. "$tmp/functions"
TMP_DIR="$tmp" BOOTSTRAP_DNS_ALL='1.1.1.1,8.8.8.8' BOOTSTRAP_DNS_SELECTED='' BOOTSTRAP_DNS='1.1.1.1,8.8.8.8'
SLOT_1=dns1 PORT_1=5053 SLOT_2='' SLOT_3='' SLOT_4='' SLOT_5='' SLOT_6='' SLOT_RU=''
printf '*' > "$tmp/integration"; printf '8.8.8.8' > "$tmp/boot0"; printf 'unrelated' > "$tmp/boot1"
dns_url() { printf 'https://dns.example/query'; }
normalize_url() { printf '%s' "$1"; }
listener_port_exists() { return 0; }
local_dns_query_ok() { if [ -e "$tmp/trigger-move" ]; then : > "$tmp/moved"; return 1; fi; [ ! -e "$tmp/fail-query" ]; }
detect_steer_dns_path() { STEER_DNS_ACTIVE="${TEST_STEER:-0}"; }
save_config() { [ ! -e "$tmp/fail-save" ] || return 1; printf '%s' "$BOOTSTRAP_DNS_SELECTED" > "$tmp/saved"; }
uci() {
    [ "$1" != -q ] || shift
    case "$1:$2" in
        changes:*) [ ! -e "$tmp/pending" ] || printf 'pending-change'; return 0 ;;
        get:https-dns-proxy.config.dnsmasq_config_update) cat "$tmp/integration" ;;
        get:https-dns-proxy.config.force_dns) if [ -e "$tmp/force-enabled" ]; then printf 1; else printf 0; fi ;;
        get:https-dns-proxy.@https-dns-proxy\[0\]) printf 'https-dns-proxy' ;;
        get:https-dns-proxy.@https-dns-proxy\[1\]) printf 'https-dns-proxy' ;;
        get:https-dns-proxy.@https-dns-proxy\[0\].listen_port) if [ -e "$tmp/moved" ]; then printf 5070; else printf 5053; fi ;;
        get:https-dns-proxy.@https-dns-proxy\[1\].listen_port) printf 5060 ;;
        get:https-dns-proxy.@https-dns-proxy\[0\].resolver_url) printf 'https://dns.example/query' ;;
        get:https-dns-proxy.@https-dns-proxy\[1\].resolver_url) printf 'https://other.example/query' ;;
        get:https-dns-proxy.@https-dns-proxy\[0\].bootstrap_dns) cat "$tmp/boot0" ;;
        set:https-dns-proxy.config.dnsmasq_config_update=*) printf '%s' "${2#*=}" > "$tmp/integration" ;;
        delete:https-dns-proxy.config.dnsmasq_config_update) rm -f "$tmp/integration" ;;
        set:https-dns-proxy.@https-dns-proxy\[0\].bootstrap_dns=*) printf '%s' "${2#*=}" > "$tmp/boot0" ;;
        delete:https-dns-proxy.@https-dns-proxy\[0\].bootstrap_dns) rm -f "$tmp/boot0" ;;
        commit:https-dns-proxy) return 0 ;;
        *) return 1 ;;
    esac
}
cat > "$tmp/init" <<'EOF'
#!/bin/sh
[ "$1" = running ] && exit 0
[ "$1" = restart ] || exit 1
printf 'restart\n' >> "$BOOTSTRAP_TEST_DIR/restarts"
[ ! -e "$BOOTSTRAP_TEST_DIR/fail-once" ] || { rm -f "$BOOTSTRAP_TEST_DIR/fail-once"; exit 1; }
[ "$(cat "$BOOTSTRAP_TEST_DIR/integration")" = '-' ]
EOF
chmod +x "$tmp/init"
HTTPS_DNS_PROXY_INIT="$tmp/init" BOOTSTRAP_TEST_DIR="$tmp"; export BOOTSTRAP_TEST_DIR
TEST_STEER=1
bootstrap_apply_selection '9.9.9.9' || exit 1
[ "$(cat "$tmp/boot0")" = '9.9.9.9' ] && [ "$(cat "$tmp/boot1")" = unrelated ] && [ "$(cat "$tmp/integration")" = '*' ] || exit 2
[ "$(cat "$tmp/saved")" = '9.9.9.9' ] || exit 3
: > "$tmp/fail-query"
if bootstrap_apply_selection '1.0.0.1'; then exit 4; fi
[ "$(cat "$tmp/boot0")" = '9.9.9.9' ] && [ "$(cat "$tmp/integration")" = '*' ] && [ "$(cat "$tmp/saved")" = '9.9.9.9' ] || exit 5
[ "$(wc -l < "$tmp/restarts" | tr -d ' ')" = 3 ] || exit 6
rm -f "$tmp/fail-query"; : > "$tmp/pending"
if bootstrap_apply_selection '8.8.4.4'; then exit 7; fi
[ "$(cat "$tmp/boot0")" = '9.9.9.9' ] && [ "$(cat "$tmp/integration")" = '*' ] || exit 8
rm -f "$tmp/pending"; TEST_STEER=0
bootstrap_apply_selection '1.0.0.1' || exit 9
[ "$(cat "$tmp/boot0")" = '1.0.0.1' ] && [ "$(cat "$tmp/integration")" = '*' ] || exit 10
: > "$tmp/fail-save"
if bootstrap_apply_selection '8.8.4.4'; then exit 11; fi
[ "$(cat "$tmp/boot0")" = '1.0.0.1' ] && [ "$(cat "$tmp/saved")" = '1.0.0.1' ] && [ "$(cat "$tmp/integration")" = '*' ] || exit 12
rm -f "$tmp/fail-save"
if bootstrap_apply_selection 'invalid'; then exit 13; fi
[ "$(cat "$tmp/boot0")" = '1.0.0.1' ] || exit 14
SLOT_1=''; bootstrap_apply_selection '' || exit 15
[ ! -s "$tmp/saved" ] && [ "$(cat "$tmp/boot1")" = unrelated ] || exit 16
SLOT_1=dns1; rm -f "$tmp/integration"
bootstrap_apply_selection '9.9.9.9' || exit 17
[ ! -e "$tmp/integration" ] && [ "$(cat "$tmp/boot0")" = '9.9.9.9' ] || exit 18
: > "$tmp/fail-once"
if bootstrap_apply_selection '8.8.8.8'; then exit 19; fi
[ ! -e "$tmp/integration" ] && [ "$(cat "$tmp/boot0")" = '9.9.9.9' ] && [ "$(cat "$tmp/saved")" = '9.9.9.9' ] || exit 20
: > "$tmp/trigger-move"
if bootstrap_apply_selection '8.8.4.4'; then exit 21; fi
[ "$(cat "$tmp/boot0")" = '8.8.4.4' ] && [ "$(cat "$tmp/boot1")" = unrelated ] || exit 22
case "$BOOTSTRAP_ERROR" in *'откат не завершён'*) ;; *) exit 23;; esac
rm -f "$tmp/trigger-move" "$tmp/moved" "$tmp/boot0"; : > "$tmp/fail-query"
if bootstrap_apply_selection '8.8.4.4'; then exit 24; fi
[ ! -e "$tmp/boot0" ] && [ ! -e "$tmp/integration" ] || exit 25
rm -f "$tmp/fail-query"; TEST_STEER=1; : > "$tmp/force-enabled"
if bootstrap_apply_selection '8.8.8.8'; then exit 26; fi
[ ! -e "$tmp/boot0" ] && [ ! -e "$tmp/integration" ] || exit 27
case "$BOOTSTRAP_ERROR" in *Steer*) ;; *) exit 28;; esac
echo 'OK: bootstrap applies to selected DNS and rolls back after failed probe'
