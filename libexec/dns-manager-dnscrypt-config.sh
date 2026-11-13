#!/bin/sh
# Experimental config generator. It only prints TOML; it never starts a service.
set -eu
LC_ALL=C
export LC_ALL

fail() { printf '%s\n' "$1" >&2; exit 1; }
[ "$#" -eq 3 ] || fail 'Expected local port, DoH URL and bootstrap IP list'
port=$1
case "$port" in ''|*[!0-9]*) fail 'Invalid local port' ;; esac
[ "${#port}" -le 5 ] && [ "$port" -gt 0 ] && [ "$port" -le 65535 ] || fail 'Invalid local port'
helper="$(dirname "$0")/dns-manager-doh-stamp.sh"
stamp=$(sh "$helper" "$2") || fail 'Unable to encode DoH address'

# Same public literal-address rules as bootstrap_normalize_addresses in the
# manager. Formatting is performed only after validating the complete list.
resolvers=$(printf '%s\n' "$3" | awk '
function ipv4(s,a,n,i) {
 n=split(s,a,"."); if(n!=4) return 0
 for(i=1;i<=4;i++) if(a[i] !~ /^[0-9]+$/ || length(a[i])>3 || a[i]+0>255 || (length(a[i])>1 && substr(a[i],1,1)=="0")) return 0
 return a[1]+0>0 && a[1]+0!=127 && a[1]+0<224
}
function ipv6(s,a,n,i,parts,compressed,nonzero) {
 if(s !~ /^[0-9a-fA-F:]+$/ || index(s,":")==0 || s=="::" || s=="::1") return 0
 if(s ~ /^:[^:]/ || s ~ /[^:]:$/ || s ~ /:::/) return 0
 compressed=(index(s,"::")>0)
 if(compressed) { if(index(substr(s,index(s,"::")+2),"::")>0) return 0; sub(/::/,":Z:",s); sub(/^:/,"",s); sub(/:$/,"",s) }
 if(s ~ /^:/ || s ~ /:$/ || s ~ /::/) return 0
 n=split(s,a,":"); parts=0; nonzero=0
 for(i=1;i<=n;i++) { if(a[i]=="Z") continue; if(a[i] !~ /^[0-9a-fA-F]+$/ || length(a[i])>4) return 0; parts++; if(a[i] !~ /^0+$/) nonzero++ }
 if(nonzero==0 || (nonzero==1 && a[n] ~ /^0*1$/)) return 0
 return compressed ? parts<8 : parts==8
}
NR>1 { bad=1; exit }
{
 gsub(/[,[:space:]]+/," "); sub(/^ /,""); sub(/ $/,"")
 n=split($0,a," "); if(n<1 || n>48 || a[1]=="") { bad=1; exit }
 for(i=1;i<=n;i++) {
  ip=tolower(a[i]); if((!ipv4(ip) && !ipv6(ip)) || seen[ip]++) { bad=1; exit }
  addr=index(ip,":") ? "[" ip "]:53" : ip ":53"
  result=result (i==1 ? "" : ", ") "\047" addr "\047"
 }
}
END { if(bad || NR!=1) exit 1; print result }
') || fail 'Invalid bootstrap addresses'
[ -n "$resolvers" ] || fail 'Empty bootstrap list'

printf "server_names = ['manager-slot']\n"
printf "listen_addresses = ['127.0.0.1:%s']\n" "$port"
# dnsmasq's cache is disabled in DNSCrypt mode; keep one cache in the proxy.
printf "cache = true\n"
printf "bootstrap_resolvers = [%s]\n" "$resolvers"
printf "ignore_system_dns = true\n"
printf "[static.manager-slot]\n"
printf "stamp = '%s'\n" "$stamp"
