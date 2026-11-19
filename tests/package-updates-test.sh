#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
awk '/^package_candidate_version\(\)/ {f=1} /^package_update_index\(\)/ {if(f)exit} f' dns-manager-luci.sh > "$tmp/functions"
mkdir "$tmp/apk" "$tmp/opkg"
cat > "$tmp/apk/apk" <<'EOF'
#!/bin/sh
case "$1" in
 list) [ "${FAIL_LIST:-0}" = 0 ] || exit 1; printf '%s\n' 'dnscrypt-proxy2-2.2.0-r1 aarch64 {repo} [upgradable from: 2.1.15-r1]' 'https-dns-proxy-2027.01-r1 aarch64 {repo} [upgradable from: 2026.01-r1]' ;;
 version) echo '>' ;;
esac
EOF
cat > "$tmp/opkg/opkg" <<'EOF'
#!/bin/sh
case "$1" in
 list-upgradable) [ "${FAIL_LIST:-0}" = 0 ] || exit 1; printf '%s\n' 'dnscrypt-proxy2 - 2.1.15-1 - 2.2.0-1' 'https-dns-proxy - 2026.01-1 - 2027.01-1' ;;
 compare-versions) [ "$3" = '>>' ] ;;
esac
EOF
chmod +x "$tmp/apk/apk" "$tmp/opkg/opkg"
for manager in apk opkg; do
  PATH="$tmp/$manager:/usr/bin:/bin"; export PATH
  TMP_ROOT="$tmp"; export TMP_ROOT
  . "$tmp/functions"
  case "$manager" in apk) dc=2.2.0-r1; doh=2027.01-r1 ;; *) dc=2.2.0-1; doh=2027.01-1 ;; esac
  [ "$(package_candidate_version dnscrypt-proxy2)" = "$dc" ]
  [ "$(package_candidate_version https-dns-proxy)" = "$doh" ]
  [ -z "$(package_candidate_version nonexistent)" ]
  package_version_cmp "$dc" 2.1.15-1
  if FAIL_LIST=1 package_candidate_version dnscrypt-proxy2 >/dev/null; then echo "$manager hid an index error" >&2; exit 1; fi
done
echo 'OK: apk and opkg package candidates, missing packages and errors'
