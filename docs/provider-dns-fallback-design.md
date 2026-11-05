# Provider DNS fallback: work in progress

This branch does not activate fallback or change the router's DNS settings.
The current implementation only selects potential upstream addresses,
provides an isolated upstream probe and constructs a proposed server list.
These helpers are covered by offline tests and are not connected to Watchdog.

Before enabling the feature, the implementation must satisfy these conditions:

1. The fallback is opt-in, clearly says that queries to the upstream DNS are
   not protected by DoH and that the provider can apply different filtering.
2. Trigger only after a complete, repeated failure of the selected general
   DoH slots. Unknown or incomplete probes must not count as failures.
3. Before switching, query the candidate upstream directly and require a
   valid reply. Reject local interface addresses and prevent forwarding loops.
   Handle missing, changing, IPv4-only and IPv6-only upstreams. The isolated
   probe exists, but its integration and forwarding-loop behavior remain to be
   verified.
4. Preserve unrelated dnsmasq rules, canary domains and regional routes.
   Publish the full change atomically and restore the previous state on error.
5. Preserve and restore per-device DNS bindings and support Steer without
   altering its own rules. A successful fallback must be verified through the
   path actually used by clients, not just by querying the upstream directly.
6. Continue checking the original DoH slots while fallback is active. Return
   only after confirmed recovery, with cooldown and no repeated restart loop.
7. Revalidate concurrent profile, slot, device and network changes before
   restoring anything. Never overwrite later user or third-party changes.
8. Handle reboot, watchdog restart, disabling the feature, uninstall and
   partial writes without leaving stale provider DNS or a broken resolver.
9. Display the active state, failure reason and transition in LuCI and the log.

These conditions are not yet implemented or verified on an OpenWrt router.
