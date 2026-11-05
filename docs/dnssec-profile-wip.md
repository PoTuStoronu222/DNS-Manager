# DNSSEC profile investigation — work in progress

The DNSSEC profile is implemented experimentally in this test branch. It has not been verified end-to-end on OpenWrt hardware and must not be merged as a proven production feature.

On 2026-11-05 a development host made HTTPS wire-format DNS requests to the 113 catalog entries with no configured HTTP proxy. A positive sample required a NOERROR response with AD for cloudflare.com, SERVFAIL for dnssec-failed.org without CD, and NOERROR for the same name with CD. The test checks observed resolver behavior, not cryptographic validation by the router. An unavailable, blocked, or otherwise unconfirmed entry is not proof of absence of DNSSEC support. Availability and results depend on network and time.

27 catalog entries showed the sampled behavior. Entries include variants of the same operator and filtering policies; they are not 27 independent providers. This observed set seeds the experimental candidate pool; every selected general slot is checked again locally:

- `adguard_default` — AdGuard DNS
- `aquilenet` — Aquilenet DNS
- `cloudflare_clean` — Cloudflare
- `cloudflare_family` — Cloudflare Family
- `cloudflare_security` — Cloudflare Security
- `cynthia` — CynthiaLabs DNS
- `dagami` — Dagami DNS
- `digitalsize` — DigitalSize DNS
- `dnsbunker` — DNSBUNKER Pro+TIF
- `dnsforge` — dnsforge
- `dnsforge_strict` — dnsforge Strict
- `dnsforge_youth` — dnsforge Youth Protection
- `doh_lacontrevoie` — LaContreVoie DNS
- `ffmuc` — FFMUC
- `geodema` — Geodema DNS
- `google_clean` — Google Public DNS
- `hostux` — Hostux DNS
- `iijjp` — IIJ Public DNS (не семейный)
- `malw_cloudflare` — Malw.link Cloudflare
- `nextdns_anycast` — NextDNS Anycast
- `nwps_kids` — NWPS.fi Kids
- `nwps_standard` — NWPS.fi Standard
- `opendns_family` — OpenDNS FamilyShield
- `opendns_standard` — OpenDNS Standard
- `paesa` — Paesa DNS
- `shecan` — Zapret DNS
- `wikimedia` — Wikimedia DNS

The profile tests the full catalog for availability, takes up to six candidates
from the observed pool by response time, then checks their DNSSEC behavior
through the local proxy before accepting the configuration. Unconfirmed slots
are removed; if no general slot is confirmed the apply transaction fails.
Auto replacement continues to pick within the existing slot category and
checks DNSSEC before saving a replacement. The independent regional setting is
not changed, and is not a DNSSEC-validation guarantee. Server filtering
policies can differ. Steer may answer some queries independently.

The profile does not continuously recertify DNSSEC when a previously validated
server remains responsive. It is not validated end-to-end against OpenWrt dig
variants, real https-dns-proxy, Steer, per-device dnsmasq, reboot or weak
hardware. Mock tests do not establish these properties.
References:
- https://developers.google.com/speed/public-dns/faq
- https://developers.cloudflare.com/1.1.1.1/faq/

On 2026-11-05 the probe passed local synthetic DNS wire-response tests using
actual BIND dig 9.18.39 in a Linux development environment. This validates
parsing for that dig version only; OpenWrt package variants and live DoH
paths remain untested.


A development-only UDP-to-DoH bridge using actual BIND dig and Cloudflare
passed the probe in addition to local synthetic wire fixtures. This is not a
test of OpenWrt https-dns-proxy or of the installed router.

An additional Linux development test built https-dns-proxy from upstream
source and passed the actual BIND dig probe through that proxy to Cloudflare.
This is not an OpenWrt build or a real router/Steer/LAN-device test.

Current limitation: the profile selects at most the six fastest available
entries from the observed candidate pool before DNSSEC probing. If all six
fail DNSSEC validation, it aborts rather than trying slower candidates. A
passing test here is only an observation of the selected resolver; signed
answers on regional or Steer-owned paths are not covered. The 113-resolver
availability scan is resource-limited by the existing runner but has not
been benchmarked on weak routers.
