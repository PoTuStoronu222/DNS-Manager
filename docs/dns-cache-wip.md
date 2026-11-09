# DNS cache controls — work in progress

This work is not connected to LuCI or installed by DNS Manager yet.
`dns-manager-cache-budget.sh` calculates a common record budget for the
system dnsmasq and the per-device profile instances; the allocations sum to
the user's limit. If system dnsmasq performs DNSSEC validation, the main cache
keeps at least 150 entries, as required by dnsmasq. The caller still needs to
assign the planned device values to the actual unique profiles.

`dns-manager-cache-plan.sh` derives the profile masks from saved device
bindings, counts each distinct slot combination once and maps a share to each
mask. Its test covers devices joining an existing group, adding and removing a
group, and malformed bindings. This is a read-only plan, not runtime
reallocation; it has not been tested on the router.

`dns-manager-cache-profiles.sh` applies a verified plan and minimum TTL to a
private staging directory of generated per-device dnsmasq profiles. It checks
that all staged profiles have exactly one allocation before writing. Tests
cover missing and duplicate masks, unallocated profiles, invalid TTL, and TTL
zero; one generated profile also passed `dnsmasq --test` in a Linux lab. The
script is not installed or called by DNS Manager yet.

`dns-manager-cache-stage.sh` combines planning and profile rendering in one
operation on a private staging directory. Its tests exercise multiple devices
sharing one profile, adding a group, and disabling a custom minimum TTL. The
result is a staged configuration only; no live UCI or dnsmasq is modified.

The optional TTL lab uses a synthetic upstream and an isolated dnsmasq. It
verifies that a short TTL is respected by default and extended when an
explicit minimum is configured. It does not emulate OpenWrt, Steer, or
per-device traffic.

Still required: atomic safe application and restore of existing UCI settings,
reallocation when device bindings change, installer and uninstall handling,
UI, and integration tests for Steer, reboot and constrained devices. No user
DNS settings are changed by these prototypes.

