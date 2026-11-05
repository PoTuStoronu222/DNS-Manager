# DNSSEC profile investigation — work in progress

The DNSSEC profile is not implemented or enabled. Do not install this branch expecting a working profile.

On 2026-11-05 a development host made HTTPS wire-format DNS requests to the 113 catalog entries with no configured HTTP proxy. A positive sample required a NOERROR response with AD for cloudflare.com, SERVFAIL for dnssec-failed.org without CD, and NOERROR for the same name with CD. The test checks observed resolver behavior, not cryptographic validation by the router. An unavailable, blocked, or otherwise unconfirmed entry is not proof of absence of DNSSEC support. Availability and results depend on network and time.

27 catalog entries showed the sampled behavior. Entries include variants of the same operator and filtering policies; they are not 27 independent providers or a production eligibility list:

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

The experimental dnssec_probe_local helper and its mock tests are not used by profile selection or auto replacement. They are not validated against a real OpenWrt dig, proxy, Steer, per-device dnsmasq, regional routing, reboot or weak hardware. Do not claim the profile is secure or complete until those cases are implemented and verified.

References:
- https://developers.google.com/speed/public-dns/faq
- https://developers.cloudflare.com/1.1.1.1/faq/

On 2026-11-05 the probe passed local synthetic DNS wire-response tests using
actual BIND dig 9.18.39 in a Linux development environment. This validates
parsing for that dig version only; OpenWrt package variants and live DoH
paths remain untested.
