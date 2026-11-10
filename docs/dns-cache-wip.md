# DNS cache settings — test branch

The LuCI network page controls the main dnsmasq cache size in entries and its
minimum TTL in seconds. Zero TTL keeps the upstream TTL. Device-specific
dnsmasq instances use `cache-size=0`; their DNS bindings still select the same
upstreams and are not restarted when cache settings change. Steer's own cache
is separate and is not modified.

The save operation uses an isolated rpcd UCI session, checks for unrelated
pending DHCP changes, restarts the main dnsmasq under a read guard and checks
its procd state. If the restart fails, the previous cache settings are
restored where they have not been changed externally. On uninstall, stock
cache settings are restored only when the current values still match the
manager's last saved values.

The test environment uses OpenWrt 25.12.2 x86-64 userspace and the actual
fw4, nftables and Steer 2.0.5 binaries in isolated Linux network namespaces.
It checks UDP and TCP DNS traffic with and without Steer, the unchanged nft
rules and device-service PID after saving, pending UCI changes, simulated
restart with persistent configuration, and injected restart failures. The
environment runs without OpenWrt's ujail and is not a physical router reboot.

In this Steer configuration its DNS redirect handles the test client's
requests before the existing fw4 device binding, so the client uses the
router's common resolver both before and after cache changes. This existing
interaction is separate from cache settings and needs independent attention.
