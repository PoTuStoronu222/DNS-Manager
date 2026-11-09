# DNS cache controls — experimental, not ready for router testing

The test branch connects the LuCI form to a saved total cache-entry budget and
minimum TTL. The device DNS service distributes the budget between the main
dnsmasq and its actual device-specific profiles. Zero minimum TTL leaves DNS
answers' original TTL unchanged. Steer's own cache remains independent.

The disposable OpenWrt 25.12.2 userspace lab verifies procd/dnsmasq execution,
RPC worker application, adding and removing device groups, TTL changes,
service restart, failed dnsmasq restart, and pre-existing pending DHCP/firewall
UCI changes. The lab disables ujail and uses firewall/nft stubs. It is not a
full router, reboot, firewall or Steer integration test.

Do not install this experiment yet. In particular, a concurrent firewall UCI
change occurring after preflight but while device DNS is restarting could
prevent removal of an old firewall redirect after its listener stops. Review
and test this failure path using real fw4 and Steer before enabling use. Also
verify recovery after router reboot, uninstall handling, and concurrent writes
to the same cache options.
