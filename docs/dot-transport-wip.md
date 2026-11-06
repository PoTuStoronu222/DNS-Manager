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
An experimental preflight now launches one temporary instance at a time,
checks exclusive ownership of both loopback sockets, probes UDP and TCP, and
stops only the process it started. It does not install or activate DoT.
An isolated single-file journal prototype also tests interruption recovery and
refuses to overwrite a file changed externally. A separate experimental boot
helper can recover the owned DoT selection, but is not installed by default.
The journal is not connected to UCI, switching or the web interface. Its comparison and rename
are not an atomic lock against other programs; it must not be used as evidence
that concurrent Steer/UCI writes are safe.

An isolated OpenWrt 25.12.2 x86-64 virtual machine was used for an additional
prototype check. The preflight succeeded using OpenWrt's Stubby and dig. Two
procd-managed instances answered DNS queries over UDP and TCP, left the
operator's `/etc/config/stubby` untouched, and came back after reboot. A
simulated interrupted change to the owned slot file was restored on reboot,
before both slot instances started. This exercises only the experimental
single-file recovery, not DNS Manager's UCI changes or a transport switch.
The VM is not representative of a weak MIPS router or an actual Steer setup.

With DNS Manager 4.15 and LuCI 2.25 installed in that VM, the running
https-dns-proxy service exposed its forced DNS redirect and port-853 rejection
as procd firewall metadata. Stopping the service removed its procd instances
and their metadata. In this default setup the DHCP file did not change on
stop; other configurations can invoke its DHCP backup restoration. A safe
switch must account for both effects instead of assuming that stopping the
service only releases local DNS ports.
With that VM's LAN port-853 reject rules present, a router-originated DoT
preflight also completed successfully. This is not a packet-level test from
a LAN client, nor a test of Steer or a complete transport switch.

`tests/dot-openwrt-firewall-vm-test.sh` exercises a possible building block
on a disposable OpenWrt VM only: a temporary procd instance supplies fixed
LAN DNS redirect and TCP/UDP port-853 reject metadata. The test checks rules
attributed to that instance after stopping https-dns-proxy and reloading fw4,
then removes it and restarts the proxy. It passed on OpenWrt 25.12.2 x86-64.
The fixture does not derive user options, transfer rule ownership, test
traffic, Steer or boot recovery, and is not connected to switching. Do not
run this destructive test on an actual router.

The selection, save and preflight helpers discover both Manager device-binding
files by default and fail if a discovered file cannot be read. Explicit paths
are supported for tests and override discovery; callers using that override
must provide every relevant binding file. The eventual switch must hold the
shared mutation lock across validation and application. This check does not
yet cover a full transport switch or live device traffic.

The optional UCI experiment uses the actual UCI executable and libraries from
the SHA-256-verified OpenWrt 25.12.2 x86-64 root filesystem, with temporary
config and delta directories. An explicitly added foreign delta path was
included in a commit while its pending delta file remained. An unrelated
concurrent committed option survived, but a same-option concurrent commit was
overwritten by the later staged commit. Separate delta directories alone do not
provide conflict detection. This does not emulate the Steer service or reboot.

OpenWrt's `https-dns-proxy` init script attaches forced-DNS firewall data to
its procd instance and its stop path can restore a DHCP backup and commit
`dhcp`. Merely stopping that service to free ports is therefore not a safe
transport switch: it can change forced interception or interact with a
concurrent UCI delta. A replacement interception mechanism and a guarded UCI
strategy must be verified first, for both Steer-present and Steer-absent cases.

Remaining design and validation requirements:

* Maintain independent saved selections for DoH and DoT, including the previous
  routes and user choices, and never infer DoT support from a DoH URL.
* Connect the temporary DoT preflight to the future switch and test it on
  OpenWrt, including address-family and port ownership edge cases.
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
The package behavior above is visible in the
[OpenWrt https-dns-proxy init script](https://github.com/openwrt/packages/blob/master/net/https-dns-proxy/files/etc/init.d/https-dns-proxy).

