# DNS over TLS transport — experimental work

This branch is incomplete. It does not add a LuCI switch or change the router's
DNS path. Do not install or enable the experimental service yet.

The existing DNS Manager assumes https-dns-proxy for discovery, profile tests,
updates, rollback, the watchdog and status. Substituting an unrelated resolver
without updating those paths would break slot routes or cause the watchdog to
restore the old proxy. A working DoT option must handle all of them together.

The prototype maps only documented endpoint identities and addresses. One
isolated Stubby instance per occupied slot retains the existing local slot port
and requires authenticated TLS, with no plaintext upstream. The service uses
its own config and must never overwrite `/etc/config/stubby`, which may belong
to the operator. The optional development-host test checks two independent
listeners and rejects a mismatched TLS name; it does not prove OpenWrt behavior.

Remaining design and validation requirements:

* Maintain independent saved selections for DoH and DoT, including the previous
  routes and user choices, and never infer DoT support from a DoH URL.
* Stage candidate DoT listeners on genuinely free temporary ports and test DNS
  responses before stopping the current DoH service; handle port collisions.
* Under the shared mutation lock, snapshot the manager state and owned UCI
  changes, switch the slot listeners, verify DNS, and roll back on failure.
  Recover safely if the process or router is interrupted between these steps.
* Adapt profile selection, catalog testing, current-server checks, individual
  slots, watchdog and DNSSEC checks to the chosen transport. A DoH HTTP success
  is never evidence that a DoT endpoint works.
* Preserve regional DNS, per-device DNS, forced-DNS rules and external Steer
  behavior. Confirm that LAN-to-WAN DoT blocking does not block router-origin
  upstream DoT traffic, including IPv6 and TCP.
* Handle service start and stop, boot ordering, existing operator-managed
  Stubby, package ownership, update and uninstall without taking over unrelated
  services. TLS verification must fail closed when time or CA data is wrong.
* Measure resource use and test on real OpenWrt hardware, especially weak
  devices, with one and multiple selected slots and after power loss.

References: [OpenWrt Stubby package](https://github.com/openwrt/packages/blob/master/net/stubby/files/README.md),
[Stubby strict TLS configuration](https://github.com/getdnsapi/stubby#configure-stubby),
and [Cloudflare DoT addresses](https://developers.cloudflare.com/1.1.1.1/infrastructure/network-operators/).
