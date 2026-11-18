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
  print(s.name, "|", s.stamp, "|", s.nofilter ? "clean" : "unknown", "|", replace(replace(s.description || "", /\n/g, " "), /\|/g, "/"), "\n");
});''' < "$tmp/source.json" > "$tmp/records"
[ -s "$tmp/records" ] || { echo "В подписанном списке нет серверов DNSCrypt" >&2; exit 1; }
cat "$helpers/dns-manager-dnscrypt-catalog.conf" > "$tmp/catalog"
# Location metadata: https://www.dnscry.pt/resolvers.json (snapshot).
cat > "$tmp/locations" <<'EOF_LOCATIONS'
adelaide|Adelaide|AU
allendale|Allendale|US
allentown|Allentown|US
amsterdam|Amsterdam|NL
ashburn|Ashburn|US
atlanta|Atlanta|US
auckland|Auckland|NZ
bengaluru|Bengaluru|IN
berkeleysprings|Berkeley Springs|US
bratislava|Bratislava|SK
bremen|Bremen|DE
brisbane|Brisbane|AU
bucharest|Bucharest|RO
calgary|Calgary|CA
capetown|Cape Town|ZA
chicago|Chicago|US
chisinau|Chișinău|MD
copenhagen|Copenhagen|DK
coventry|Coventry|GB
dallas|Dallas|US
denver|Denver|US
detroit|Detroit|US
dhaka|Dhaka|BD
dublin|Dublin|IE
dusseldorf|Düsseldorf|DE
ebene|Ebène|MU
ebenecity|Ebène|MU
eygelshoven|Eygelshoven|NL
flint|Flint|US
frankfurt|Frankfurt|DE
fremont|Fremont|NG
gdansk|Gdansk|PL
geneva|Geneva|CH
grandrapids|Grand Rapids|US
hafnarfjordur|Hafnarfjordur|IS
halifax|Halifax|CA
hanoi|Hanoi|VN
helsinki|Helsinki|FI
hochiminhcity|Ho-Chi-Minh City|VN
hongkong|Hong Kong|HK
houston|Houston|US
hudiksvall|Hudiksvall|SE
ikeja|Ikeja|NG
indianapolis|Indianapolis|US
islamabad|Islamabad|PK
istanbul|Istanbul|TR
jacksonville|Jacksonville|US
jakarta|Jakarta|ID
johannesburg|Johannesburg|ZA
johor|Johor|MY
kansascity|Kansas City|US
kyiv|Kyiv|UA
lasvegas|Las Vegas|US
libertylake|Liberty Lake|US
lisbon|Lisbon|PT
london|London|GB
losangeles|Los Angeles|US
madrid|Madrid|ES
manchester|Manchester|GB
marseille|Marseille|FR
melbourne|Melbourne|AU
miami|Miami|US
milan|Milan|IT
molln|Mölln|DE
montreal|Montreal|CA
moscow|Moscow|RU
mumbai|Mumbai|IN
munich|Munich|DE
newcastle|Newcastle|GB
newyork|New York|US
nuremberg|Nuremberg|DE
ogden|Ogden|US
oradea|Oradea|RO
ottoville|Ottoville|US
paris|Paris|FR
perth|Perth|AU
phoenix|Phoenix|US
portedwards|Port Edwards|US
portland|Portland|US
prague|Prague|CZ
redditch|Redditch|GB
riga|Riga|LV
saltlakecity|Salt Lake City|US
sandefjord|Sandefjord|NO
sanjose|San Jose|US
santaclara|Santa Clara|US
saopaulo|São Paulo|BR
seattle|Seattle|US
seoul|Seoul|KR
singapore|Singapore|SG
sofia|Sofia|BG
spokane|Spokane|US
stockholm|Stockholm|SE
sydney|Sydney|AU
taipeh|Taipeh|TW
tallinn|Tallinn|EE
tampa|Tampa|US
taos|Taos|US
tbilisi|Tbilisi|GE
thessaloniki|Thessaloniki|GR
timisoara|Timișoara|RO
tirana|Tirana|AL
tokyo|Tokyo|JP
toronto|Toronto|CA
tuusula|Tuusula|FI
valdivia|Valdivia|CL
vancouver|Vancouver|CA
vienna|Vienna|AT
vientiane|Vientiane|LA
vilnius|Vilnius|LT
warsaw|Warsaw|PL
zurich|Zürich|CH
EOF_LOCATIONS
while IFS='|' read -r name stamp category description; do
    case "$name" in
        adguard-dns-family|cisco-familyshield|cleanbrowsing-adult|cleanbrowsing-family|dnsforfamily|dnsforfamily-no-safe-search|sfw.scaleway-fr) category=family ;;
        adguard-dns|doh.tiar.app) category=adblock ;;
        cisco|cleanbrowsing-security|quad9-dnscrypt-ip4-filter-ecs-pri|quad9-dnscrypt-ip4-filter-pri) category=security ;;
    esac
    display=$(printf '%s\n' "$name" | awk '{
        if ($0 ~ /^cs-/) sub(/^cs-/, "CryptoStorm-")
        else if ($0 ~ /^adguard-/) sub(/^adguard-/, "AdGuard-")
        else if ($0 ~ /^cleanbrowsing-/) sub(/^cleanbrowsing-/, "CleanBrowsing-")
        else if ($0 ~ /^cisco/) sub(/^cisco/, "Cisco OpenDNS")
        sub(/-ipv4$/, ""); gsub(/[-_]/, " ");
        for (i=1; i<=NF; i++) { if ($i == "dns") $i="DNS"; else if ($i ~ /^[a-z]/) $i=toupper(substr($i,1,1)) substr($i,2); }
        print
    }')
    # Only use an explicit country in the signed source description.
    region=$(printf '%s\n' "$description" | awk '
        BEGIN {n=split("Austria:AT,Spain:ES,Belgium:BE,Germany:DE,Switzerland:CH,Czech Republic:CZ,Finland:FI,France:FR,Hungary:HU,England:GB,United Kingdom:GB,Italy:IT,Canada:CA,Moldova:MD,Netherlands:NL,Norway:NO,Poland:PL,Portugal:PT,Romania:RO,Serbia:RS,Singapore:SG,Sweden:SE,Australia:AU,Japan:JP,United States:US,USA:US,Mexico:MX,Canadian:CA,Swedish:SE", a, ",")}
        {for(i=1;i<=n;i++){split(a[i], b, ":"); if(index($0,b[1])) {print b[2]; exit}}}
    ')
    case "$name" in
        dnscry.pt-*-ipv4)
            location_key=${name#dnscry.pt-}; location_key=${location_key%-ipv4}
            location_base=$(printf '%s' "$location_key" | sed 's/[0-9]*$//')
            location_number=${location_key#"$location_base"}
            location=$(awk -F'|' -v key="$location_base" '$1==key {print $2 "|" $3; exit}' "$tmp/locations")
            if [ -n "$location" ]; then
                city=${location%|*}; region=${location##*|}
                display="dnscry.pt $city${location_number:+ $location_number}"
            fi
            ;;
        cs-*)
            # The signed list uses US state abbreviations for these locations.
            case "$name" in cs-dc|cs-fl|cs-ga|cs-il|cs-la|cs-nv|cs-nyc|cs-ore|cs-sea|cs-tx) region=US;; esac
            case "$description" in 'CryptoStorm '*resolver.*)
                display=${description%% resolver.*}; display=${display%%,*} ;;
            esac
            ;;
        dct-de) display='DCT Berlin'; region=DE;;
        dct-de2) display='DCT Karlsruhe'; region=DE;;
        dct-fr) display='DCT Paris'; region=FR;;
        deffer-dns.au) display='deffer-dns.au Sydney'; region=AU;;
        dnscrypt.ca-ipv4) display='dnscrypt.ca'; region=CA;;
        nwps.fi) display='NWPS.fi Helsinki'; region=FI;;
        plan9dns-fl) display='Plan9 DNS Miami'; region=US;;
        plan9dns-nj) display='Plan9 DNS New Jersey'; region=US;;
        plan9dns-mx) display='Plan9 DNS Mexico City'; region=MX;;
        saldns01-conoha-ipv4) display='salDNS Tokyo 01'; region=JP;;
        saldns02-conoha-ipv4) display='salDNS Tokyo 02'; region=JP;;
        saldns03-conoha-ipv4) display='salDNS Tokyo 03'; region=JP;;
        scaleway-ams) display='Scaleway Amsterdam'; region=NL;;
        searx-se-ipv4) display='searx.se'; region=SE;;
        sfw.scaleway-fr) display='Scaleway Family'; region=FR;;
    esac
    if [ -n "$region" ]; then
        display=$(printf '%s\n' "$display" | awk -v region="$region" '{if (NF>1 && toupper($NF)==region) NF--; print}')
        display="$display [$region]"
    fi
    hash=$(printf %s "$name" | sha256sum)
    id=official_${hash%% *}
    printf '%s|%s|dnscrypt|%s|%s|%s|official\n' "$id" "$category" "$display" "$stamp" "$(printf '%s' "${region:-any}" | tr 'A-Z' 'a-z')"
done < "$tmp/records" >> "$tmp/catalog"
awk -F'|' '/^#/ {print; next} !seen[$5]++ && !ids[$1]++ {print}' "$tmp/catalog" > "$tmp/final"
[ -s "$tmp/final" ] || exit 1
chmod 600 "$tmp/final"
mv -f "$tmp/final" "$config/dnscrypt-native-catalog.conf"
