# DNS over TLS transport — experimental work

This branch is incomplete. It does not add a LuCI switch or change the router's
DNS path. Do not install or enable the experimental service yet.

The existing DNS Manager assumes https-dns-proxy for discovery, profile tests,
updates, rollback, the watchdog and status. Substituting an unrelated resolver
without updating those paths would break slot routes or cause the watchdog to
restore the old proxy. A working DoT option must handle all of them together.

The prototype maps only documented endpoint identities and addresses, including
Yandex's published regional DoT endpoints (https://dns.yandex.ru/). The basic
Yandex regional endpoint responded over DoT during a VM preflight. One
isolated Stubby instance per occupied slot retains the existing local slot port
and requires authenticated TLS, with no plaintext upstream. The service uses
its own config and must never overwrite `/etc/config/stubby`, which may belong
to the operator. The optional development-host test checks two independent
listeners and rejects a mismatched TLS name; it does not prove OpenWrt behavior.
The experimental service now reads each port from the manager's saved numeric
`PORT_*` field, rejecting missing, duplicate or invalid fields instead of
assuming ports 5053–5059. Two non-default ports were exercised in a disposable
OpenWrt VM. This preserves the port mapping needed by device resolvers, but does
not by itself update slot identities or prove end-to-end device bindings.
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

The experimental `dns-manager-dot-firewall.sh` takes one existing proxy-owned
firewall metadata array and registers an identical temporary procd guard. It
refuses multiple metadata owners, duplicate guard state and changed guard data;
no proxy rules is handled without installing a guard. In the disposable VM,
the actual proxy rules survived stopping the proxy and reloading fw4, and the
guard was removed after restarting the proxy. The VM test also checks duplicate
startup and changed guard state. This is not installed or called by the manager:
it has no reboot recovery and is not atomic against unrelated service changes.
It does not establish compatibility with Steer or a full transport switch.

An additional isolated OpenWrt 25.12.2 VM test used actual Steer 2.0.4 from
the upstream distribution and an empty v2 policy. Steer redirected LAN DNS to
its local resolver, and UDP and TCP queries to that resolver succeeded after
reboot. With proxy forced DNS disabled, guard preparation made no proxy guard
and did not change the Steer DNS chain. In that setup stopping https-dns-proxy
changed `/etc/config/dhcp` while the Steer redirect remained: proxy stop must
therefore not be treated as a harmless way to release ports. The optional
`tests/dot-openwrt-steer-vm-test.sh` checks this baseline, not a DoT switch,
device traffic or recovery of an interrupted switch. It must not be run on a
production router.

On that VM, a separate experiment captured the actual https-dns-proxy procd
instances, removed each using `ubus service delete` (without invoking the init
script stop handler), then restored them with `ubus service add`. The DHCP and
proxy config files were unchanged, the instances restarted, and Steer DNS
responded again. `tests/dot-openwrt-procd-stop-vm-test.sh` reproduces only this
limited case on a disposable VM. This technique is not yet used by DNS Manager:
it needs conflict detection, firewall ownership handoff when force DNS is on,
process/port verification, interruption recovery, startup ordering and tests
of the manager watchdog, profiles and live device traffic before integration.

A disposable OpenWrt VM experiment now temporarily replaces two DoH proxy
instances with two DoT instances on the same ports and verifies queries through
dnsmasq. It passed with real Steer active and, separately, without Steer while
the procd firewall guard preserved the proxy's forced-DNS rules through an fw4
reload. An injected failure restored the previous DoH instances and DNS
responses in each setup. This is `tests/dot-openwrt-switchover-vm-test.sh`, not
a usable controller: it always returns to DoH, does not handle power failure,
profiles, watchdog or per-device traffic, and is not connected to LuCI.

The intended interface is a DoH/DoT choice followed by Apply, with independent
saved selections; selecting a tab alone must not change the active DNS. The
older saved selection for each protocol is retained. When no DoT selection
exists, only explicitly verified matching endpoints may be proposed.
The experimental draft helper implements this suggestion for slot-list input:
it keeps an existing DoT selection, or matches the current slots against exact
documented DoT identifiers, and checks device bindings before returning a
complete draft. It does not modify or save the running configuration and is
not yet connected to LuCI or the switching logic.

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

