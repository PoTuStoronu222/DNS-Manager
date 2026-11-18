#!/bin/sh
set -eu
umask 077
helpers=${DNS_MANAGER_DNSCRYPT_HELPERS:-/usr/lib/dns-manager-luci/dnscrypt}
config=${DNS_MANAGER_DNSCRYPT_CONFIG_DIR:-/etc/dns-manager/config}
mkdir -p "$config"
tmp=$(mktemp -d "$config/.native-catalog.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
trap 'exit 1' HUP INT TERM
sh "$helpers/dns-manager-dnscrypt-source.sh" > "$tmp/source.json"
ucode -e '''import { stdin } from "fs";
let servers = json(stdin.read("all"));
map(servers, s => {
 if (s.proto == "DNSCrypt" && !s.ipv6 && match(s.name, /^[A-Za-z0-9_.-]+$/) && match(s.stamp, /^sdns:\/\/[A-Za-z0-9_-]+$/))
  print(s.name, "|", s.stamp, "|", s.nofilter ? "clean" : "unknown", "\n");
});''' < "$tmp/source.json" > "$tmp/records"
[ -s "$tmp/records" ] || { echo "В подписанном списке нет серверов DNSCrypt" >&2; exit 1; }
cat "$helpers/dns-manager-dnscrypt-catalog.conf" > "$tmp/catalog"
while IFS='|' read -r name stamp category; do
    case "$name" in
        adguard-dns-family|cisco-familyshield|cleanbrowsing-adult|cleanbrowsing-family) category=family ;;
        adguard-dns) category=adblock ;;
        cleanbrowsing-security) category=security ;;
    esac
    display=$(printf '%s\n' "$name" | awk '{
        if ($0 ~ /^cs-/) sub(/^cs-/, "CryptoStorm-")
        else if ($0 ~ /^adguard-/) sub(/^adguard-/, "AdGuard-")
        else if ($0 ~ /^cleanbrowsing-/) sub(/^cleanbrowsing-/, "CleanBrowsing-")
        else if ($0 ~ /^cisco/) sub(/^cisco/, "Cisco OpenDNS")
        gsub(/[-_]/, " "); print
    }')
    hash=$(printf %s "$name" | sha256sum)
    id=official_${hash%% *}
    printf '%s|%s|dnscrypt|%s|%s|any|official\n' "$id" "$category" "$display" "$stamp"
done < "$tmp/records" >> "$tmp/catalog"
awk -F'|' '/^#/ {print; next} !seen[$5]++ && !ids[$1]++ {print}' "$tmp/catalog" > "$tmp/final"
[ -s "$tmp/final" ] || exit 1
chmod 600 "$tmp/final"
mv -f "$tmp/final" "$config/dnscrypt-native-catalog.conf"
