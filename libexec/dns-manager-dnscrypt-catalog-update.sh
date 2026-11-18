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
  print(s.name, "|", s.stamp, "|", s.nofilter ? "clean" : "unknown", "|", replace(split(s.description || "", "\n")[0], /\|/g, "/"), "\n");
});''' < "$tmp/source.json" > "$tmp/records"
[ -s "$tmp/records" ] || { echo "В подписанном списке нет серверов DNSCrypt" >&2; exit 1; }
cat "$helpers/dns-manager-dnscrypt-catalog.conf" > "$tmp/catalog"
while IFS='|' read -r name stamp category description; do
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
        gsub(/[-_]/, " ");
        for (i=1; i<=NF; i++) { if ($i == "dns") $i="DNS"; else if ($i ~ /^[a-z]/) $i=toupper(substr($i,1,1)) substr($i,2); }
        print
    }')
    # Only use an explicit country in the signed source description.
    region=$(printf '%s\n' "$description" | awk '
        BEGIN {n=split("Austria:AT,Spain:ES,Belgium:BE,Germany:DE,Switzerland:CH,Czech Republic:CZ,Finland:FI,France:FR,Hungary:HU,England:GB,United Kingdom:GB,Italy:IT,Canada:CA,Moldova:MD,Netherlands:NL,Norway:NO,Poland:PL,Portugal:PT,Romania:RO,Serbia:RS,Singapore:SG,Sweden:SE,Australia:AU,Japan:JP,United States:US", a, ",")}
        {for(i=1;i<=n;i++){split(a[i], b, ":"); if(index($0,b[1])) {print b[2]; exit}}}
    ')
    if [ -n "$region" ]; then
        display=$(printf '%s\n' "$display" | awk -v region="$region" '{if (NF>1 && toupper($NF)==region) NF--; print}')
        display="$display [$region]"
    fi
    hash=$(printf %s "$name" | sha256sum)
    id=official_${hash%% *}
    printf '%s|%s|dnscrypt|%s|%s|any|official\n' "$id" "$category" "$display" "$stamp"
done < "$tmp/records" >> "$tmp/catalog"
awk -F'|' '/^#/ {print; next} !seen[$5]++ && !ids[$1]++ {print}' "$tmp/catalog" > "$tmp/final"
[ -s "$tmp/final" ] || exit 1
chmod 600 "$tmp/final"
mv -f "$tmp/final" "$config/dnscrypt-native-catalog.conf"
