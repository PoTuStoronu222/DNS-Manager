# DNS cache controls — work in progress

This work is not connected to LuCI or installed by DNS Manager yet.
`dns-manager-cache-budget.sh` calculates a common record budget for the
system dnsmasq and the per-device profile instances; the allocations sum to
the user's limit. If system dnsmasq performs DNSSEC validation, the main cache
keeps at least 150 entries, as required by dnsmasq. The caller still needs to
assign the planned device values to the actual unique profiles.

The optional TTL lab uses a synthetic upstream and an isolated dnsmasq. It
verifies that a short TTL is respected by default and extended when an
explicit minimum is configured. It does not emulate OpenWrt, Steer, or
per-device traffic.

Still required: atomic safe application and restore of existing UCI settings,
reallocation when device bindings change, installer and uninstall handling,
UI, and integration tests for Steer, reboot and constrained devices. No user
DNS settings are changed by these prototypes.

