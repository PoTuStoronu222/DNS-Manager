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
The optional active profile map excludes bindings for which the device service
could not prepare a resolver; its tests cover a skipped unavailable upstream and
reject an active mask absent from the saved bindings.

Steer has its own response cache and optional TTL rules for requests handled by
Steer itself (see https://github.com/splify2/steer/blob/main/docs/spec-v2.md#dns).
The proposed shared budget covers DNS Manager's dnsmasq instances only; it must
not silently modify or claim to limit Steer's independent cache.

`dns-manager-uci-cache.sh` is an experimental isolated rpcd-session writer for
the two dnsmasq UCI options. The OpenWrt 25.12.2 userspace test commits values
to a disposable package while an unrelated change is pending and verifies
that the unrelated change remains uncommitted. It does not restart dnsmasq,
handle rollback, resolve concurrent edits of the same options, or integrate
with the manager. It is not installed or called by DNS Manager yet.
The 25.12.2 test also demonstrates that the standard `uci export` includes
uncommitted changes from the global delta directory. OpenWrt's dnsmasq init
script loads DHCP configuration through this export, so isolated commit alone
does not isolate a subsequent service restart from other pending changes.
Do not hook this helper into a live dnsmasq restart until that is handled.

An experimental read guard uses shared advisory locks in libuci's order
(base file then global delta) and refuses to run if the global delta is not
empty. On OpenWrt 25.12.2 userspace, a concurrent CLI writer waited while a
reader continued and the guard refused an existing pending change. A further
isolated OpenWrt 25.12.2 userspace test starts dnsmasq with procd, verifies a
guarded restart applies the requested options, checks that concurrent CLI
writes and an rpcd session commit wait, and that locks are released after the
restart. This lab disables ujail, which cannot start in that environment. It
does not test Steer, reboot or programs bypassing libuci advisory locks. The
guard alone does not implement transaction rollback or cache application.

`dns-manager-cache-transaction.sh` experiments with applying both UCI options,
restarting under the read guard and restoring the original options if restart
fails. A 25.12.2 procd/dnsmasq lab (without ujail) covers success, an injected
restart failure, restoring an initially absent TTL and refusal with a pending
foreign UCI change. This helper is not connected to DNS Manager, does not
persist the requested total or handle per-device instances, and has not been
verified against a same-option concurrent writer or a reboot.

The optional TTL lab uses a synthetic upstream and an isolated dnsmasq. It
verifies that a short TTL is respected by default and extended when an
explicit minimum is configured. It does not emulate OpenWrt, Steer, or
per-device traffic.

Still required: atomic safe application and restore of existing UCI settings,
reallocation when device bindings change, installer and uninstall handling,
UI, and integration tests for Steer, reboot and constrained devices. No user
DNS settings are changed by these prototypes.
