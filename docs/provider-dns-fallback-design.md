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