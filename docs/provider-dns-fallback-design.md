# Provider DNS fallback: work in progress

This branch does not activate fallback or change the router's DNS settings.
The current implementation only selects potential upstream addresses,
provides an isolated upstream probe, classifies completed watchdog results,
constructs a proposed server list and prepares a recovery journal. It also
includes an isolated UCI transaction and rollback helper with mocked tests.
These helpers are not connected to Watchdog.

Before enabling the feature, the implementation must satisfy these conditions:

1. The fallback is opt-in, clearly says that queries to the upstream DNS are
   not protected by DoH and that the provider can apply different filtering.
2. Trigger only after a complete, repeated failure of the selected general
   DoH slots. Unknown or incomplete probes must not count as failures. The
   cycle classifier is tested; repeated-cycle integration is unfinished.
3. Before switching, query the candidate upstream directly and require a
   valid reply. Reject local interface addresses and prevent forwarding loops.
   Handle missing, changing, IPv4-only and IPv6-only upstreams. The isolated
   probe exists, but its integration and forwarding-loop behavior remain to be
   verified.
4. Preserve unrelated dnsmasq rules, canary domains and regional routes.
   The planner requires an exact list of Manager-owned rules and refuses a
   missing rule. The UCI helper uses a private save directory and attempts
   rollback on verification failure. Current OpenWrt UCI still reads shared
   pending deltas with a custom save directory; concurrent edits between the
   last check and commit remain unresolved. This was reproduced using a
   locally built official UCI in an isolated directory. The transaction helpers
   now fail closed without touching UCI. The standalone development test
   `tests/provider-fallback-real-uci-race.sh /path/to/uci-source` must pass
   before removing those guards. Integration with real OpenWrt remains untested.
5. Preserve and restore per-device DNS bindings and support Steer without
   altering its own rules. A successful fallback must be verified through the
   path actually used by clients, not just by querying the upstream directly.
6. Continue checking the original DoH slots while fallback is active. Return
   only after confirmed recovery, with cooldown and no repeated restart loop.
7. Revalidate concurrent profile, slot, device and network changes before
   restoring anything. The journal classifies exact old, new and externally
   changed lists; the helper refuses restoration if the DNS list or Manager
   configuration changed. Integration with all settings paths is unfinished.
8. Handle reboot, watchdog restart, disabling the feature, uninstall and
   partial writes without leaving stale provider DNS or a broken resolver.
9. Display the active state, failure reason and transition in LuCI and the log.

These conditions are not yet implemented or verified on an OpenWrt router.

## Runtime servers-file investigation

OpenWrt exposes dnsmasq `serversfile`, and dnsmasq can reread this file on
SIGHUP. This does not by itself replace existing UCI server entries or routes
through per-device dnsmasq instances. It therefore is not a complete fallback.
Also, dnsmasq 2.91 built from the upstream release rejects a second
`servers-file` option: adding one without checking an existing option may
prevent dnsmasq from starting. Reproduce with
`sh tests/provider-fallback-dnsmasq-compat-test.sh /path/to/dnsmasq`. The test
only runs configuration validation in a temporary directory; it does not alter
a running resolver. A real OpenWrt build and the Steer packet path have not
been verified.

Sources: https://openwrt.org/docs/guide-user/base-system/dhcp and
https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html
## Zapret Manager comparison

Reviewed `ZapretManager_LuCI.sh` (`doh_watch`) from Zapret Manager main.
Its opt-in direct fallback stops https-dns-proxy and restarts dnsmasq; it
checks DoH endpoints while in direct mode and starts the proxy again when a
candidate responds. It explicitly skips its watcher when DNS Manager is
present (`_dnsm_present && return 0`).

That mechanism cannot be transplanted directly: DNS Manager configures
`dnsmasq_config_update=-` in its normal owned configuration and its dnsmasq
server entries and per-device resolver instances continue pointing to the
local proxy ports. Stopping the proxy alone can leave them without an upstream.
Where https-dns-proxy integration is enabled, its own backup/restore also
writes UCI; it does not solve the concurrent-pending-delta issue.

Source: https://github.com/StressOzz/Zapret-Manager/blob/main/ZapretManager_LuCI.sh
and https://github.com/openwrt/packages/blob/master/net/https-dns-proxy/files/etc/init.d/https-dns-proxy
## Mixed-upstream and device-service experiment

A local dnsmasq 2.91 experiment used two UDP DNS stubs: one immediately
returned SERVFAIL, the other returned a valid NOERROR answer after 150 ms. The
working stub passed a control query. With `all-servers`, dnsmasq returned
SERVFAIL for both a general query and an explicitly routed domain when both
upstreams were configured for each. Thus simply adding provider servers
alongside failing DoH listeners is insufficient. Reproduce with
`python3 tests/provider-fallback-dnsmasq-routing-lab.py /path/to/dnsmasq`;
this intentionally fails on the observed behavior. It is an isolated upstream
experiment and is not an OpenWrt device or Steer end-to-end test.

The per-device service's stop/start also modifies and commits the UCI firewall
package and reloads fw4. Restarting it during fallback has its own pending-UCI
conflict and needs a safe design; it is not an independent runtime-only step.
## Transition decision (not integrated)

A pure, side-effect-free helper now models two consecutive complete failures
before proposing fallback, only with a verified provider available, and two
consecutive fully recovered cycles before proposing restoration. Partial or
unknown results reset the corresponding streak. It makes no UCI changes, does
not track state across calls, and is not called by the watchdog. Crash/reboot
persistence, transition rollback, concurrent changes, and actual routing remain
unimplemented and require independent validation before integration.
## Local NAT experiment

In an isolated Linux network namespace with nftables 1.0.9, a temporary
output-chain redirect of UDP loopback traffic from a DoH port to a mock
provider listener could be installed and removed without touching UCI. The
same rule also intercepted the local watchdog query to the original DoH
listener: it saw the mock provider response. It therefore cannot be used as
written to decide recovery. TCP, process-specific scoping, real dnsmasq,
firewall reload, Steer ordering, local IPv6, provider changes, user changes,
crash and reboot are not covered. This is an experiment, not a design approved
for integration. Run `tests/provider-fallback-nft-lab.py` only inside a new
network namespace with loopback enabled, a working nft binary, and the original namespace inode passed as DNS_LAB_PARENT_NETNS.
A follow-up isolated UDP test added an exception for a dedicated source port:
a probe explicitly bound to that port reached the original local listener,
while an ordinary query reached the redirected listener. This is a possible
building block, not a safe implementation: source-port collisions, concurrent
probes, dig variants, timeout behavior, TCP, conntrack, firewall interference,
Steer, provider listeners and reboot still require implementation and tests.
The namespace lab now exercises UDP and TCP, kernel-assigned source ports held
open by the querying sockets, four simultaneous probes, and deletion of the
NAT table. It also demonstrates that a stale source-port exception applies to
a different socket if that port is reused. The script intentionally leaves
exceptions in place to expose this risk. It does not implement safe atomic
rule cleanup, watchdog integration, provider DNS forwarding, Steer, device
bindings, firewall reload handling or reboot recovery. Those remain required.
The namespace lab also reproduced a conntrack issue: after deleting the source
port exception, a new UDP socket using the same tuple still reached the DoH
listener because the old NAT decision persisted. With an explicitly supplied
conntrack binary, a targeted deletion of that one tuple while the source port
was held allowed the same socket to reach the provider listener. This only
establishes behavior in the Linux lab; conntrack availability on OpenWrt,
UDP/TCP teardown, crash safety, lifecycle ownership, unrelated conntrack
entries, and integration with Steer and procd are not verified. No cleanup or
failover code has been connected to production.
## Steer and return-path limits

Steer v2 documents its own per-rule DNS resolver and separate upstreams, so
redirecting only local dnsmasq-to-proxy traffic cannot guarantee fallback for
requests handled by Steer itself. No Steer DNS rule is modified by the lab.
See https://splify2.github.io/docs/steer/ .

The namespace lab additionally records what happens to a held UDP tuple when
the redirect table is deleted, then performs targeted conntrack deletion and
confirms the original listener answers. On the tested kernel that tuple
reached the original listener immediately after table deletion; no conclusion
is drawn for OpenWrt kernels, active TCP streams, or unrelated firewall rules.
This remains isolated experimental code and does not implement failover.