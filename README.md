# netbird-bridge for GL.iNet routers

Use [NetBird](https://netbird.io) from the GL.iNet VPN client as if it were an
ordinary WireGuard server.

The package installs NetBird on the router and adds a **NetBird** profile under
**VPN → WireGuard Client** in the GL.iNet admin panel. Connect it there like any
other profile, and everything the GL.iNet VPN client offers applies to it:
per-device and per-domain policies, the VPN dashboard and tunnels, the kill
switch, and so on. Traffic sent into the profile leaves through your NetBird
network, normally through an exit node.

Developed and tested on a **GL.iNet Slate 7 (GL-BE3600), firmware 4.10.1**
(OpenWrt 23.05, fw4). Any GL.iNet router on firmware 4.x with kernel WireGuard
should work.

## Install

SSH into the router (`ssh root@192.168.8.1`) and run:

```sh
wget -qO- https://raw.githubusercontent.com/SerhiyGreench/glinet-netbird-bridge/main/install.sh \
  | sh -s -- --setup-key <YOUR-SETUP-KEY>
```

For a self-hosted NetBird, add the management URL:

```sh
wget -qO- https://raw.githubusercontent.com/SerhiyGreench/glinet-netbird-bridge/main/install.sh \
  | sh -s -- --setup-key <YOUR-SETUP-KEY> --management-url https://netbird.example.com:443
```

A reusable setup key without an expiry is the right kind for a router. The
key is handed to NetBird as a file and is not stored anywhere.

The installer downloads the package from the latest release and the newest
NetBird release for the router's CPU (about 40 MB on flash). It then enrolls
the router as a NetBird peer, picks an exit node and creates the GL.iNet
profile. Running it again is safe.

Then, in the admin panel: **VPN → WireGuard Client → NetBird → Connect**, or
add it to a tunnel in the **VPN Dashboard** with whatever policy you like.

<details>
<summary>Installing without the one-liner</summary>

Download `netbird-bridge.ipk` from the
[latest release](https://github.com/SerhiyGreench/glinet-netbird-bridge/releases/latest),
upload it under **Applications → Plug-ins → Upload** (or `opkg install` it),
then over SSH:

```sh
netbird-bridge setup --setup-key <YOUR-SETUP-KEY> [--management-url <URL>]
```

</details>

## How it works

```
 LAN device ──► GL.iNet VPN policy ──► wgclientN (GL.iNet's WireGuard client)
                                            │  UDP to 127.0.0.1:51830
 ┌──────────────────── namespace nbns ──────┼─────────────────────────────┐
 │                                          ▼                             │
 │   nbwg0 (WireGuard server, 10.211.83.1) ──► wt0 (NetBird) ──► peers,   │
 │                                                              exit node │
 │   NetBird's own traffic ──► nbv1 ═══ veth ═══ nbv0 ──► WAN             │
 └────────────────────────────────────────────────────────────────────────┘
```

- **NetBird runs in its own network namespace.** It changes routing,
  firewall rules and DNS when it connects, especially with an exit node. Inside
  the namespace none of that touches the router, so GL.iNet's VPN policy routing,
  other VPN clients and Tailscale keep working exactly as before.
- **The bridge is a WireGuard interface created in the router's namespace and
  then moved into NetBird's.** Its UDP socket stays in the router's namespace,
  so GL.iNet's client reaches it on `127.0.0.1`. Whatever arrives on it comes
  out inside NetBird's namespace.
- **Traffic from the bridge can only leave through NetBird.** Anything not
  routed into `wt0` is dropped. If no exit node is reachable, devices on the
  profile lose internet access rather than leaking out of the WAN, and GL.iNet's
  kill switch covers the moments when the bridge itself is down.
- **NetBird's own encrypted traffic** leaves through a veth pair into a small
  firewall zone (`nbbridge`) forwarded to `wan`. GL.iNet's VPN policy only marks
  traffic from LAN interfaces, so this never ends up inside a tunnel.
- **NetBird names resolve on the LAN.** The profile's DNS is NetBird's resolver.
  Every dnsmasq instance on the router also forwards the NetBird domain (for
  example `netbird.cloud`) there, so `peer.netbird.cloud` resolves from any
  device, on the VPN or not.
- **A watcher** checks every 30 seconds and puts back whatever went missing:
  the namespace after a network restart, the dnsmasq rules after GL.iNet
  recreates an instance, and an exit-node selection.
- **NetBird's identity lives in `/etc/netbird-bridge`** and survives reboots.
  It survives firmware upgrades too if you keep settings, though the package
  itself has to be reinstalled.

## Commands

```
netbird-bridge status              bridge, GL.iNet handshake, NetBird and exit node
netbird-bridge selftest            traffic and DNS through the bridge from a throwaway client
netbird-bridge exit-node           list exit nodes and show the selected one
netbird-bridge exit-node <ID>      use a particular exit node
netbird-bridge exit-node auto      use whichever exit node NetBird offers first (default)
netbird-bridge exit-node none      no exit node: only NetBird peers and routes are reachable
netbird-bridge netbird <args>      the NetBird CLI, inside the bridge's namespace
netbird-bridge install-netbird     update NetBird to its latest release
netbird-bridge profile             recreate the GL.iNet profile if it was deleted
netbird-bridge up --setup-key KEY  enroll again (e.g. after removing the peer)
netbird-bridge uninstall [--purge] remove the profile, firewall zone and namespace
```

`selftest` does not touch GL.iNet. It connects a temporary WireGuard client to
the bridge, just as GL.iNet's client does, then reports the public IP and DNS
it sees:

```
DNS through the bridge (10.211.83.1):
  ok
Public IP through the bridge:
  203.0.113.10
The router's own public IP, for comparison:
  198.51.100.20
```

## Configuration

`/etc/config/netbird-bridge` (`uci show netbird-bridge`). Apply changes with
`/etc/init.d/netbird-bridge restart`, plus `netbird-bridge profile` if you
changed the port, MTU or addresses.

| Option | Default | |
|---|---|---|
| `profile_name` | `NetBird` | Name of the profile in the GL.iNet UI |
| `exit_node` | `auto` | `auto`, `none`, or a NetBird network ID |
| `lan_dns` | `1` | Resolve NetBird names from every LAN device |
| `listen_port` | `51830` | Bridge port on `127.0.0.1` |
| `mtu` | `1280` | Matches NetBird's interface |
| `tunnel_ip` / `client_ip` | `10.211.83.1/30` / `10.211.83.2` | Addresses inside the bridge; change them if NetBird routes this range |
| `veth_host_ip` / `veth_ns_ip` | `169.254.83.1/30` / `169.254.83.2/30` | The link NetBird uses to reach the internet |
| `upstream_dns` | `1.1.1.1 9.9.9.9` | Resolvers NetBird uses for its own lookups |

## Notes

- **Speed.** Traffic is encrypted twice on the router: once by GL.iNet's client
  and once by NetBird. On the Slate 7 a 100 Mbit/s line gave about 65–75 Mbit/s
  through the profile.
- **IPv4 only.** GL.iNet's VPN client drops IPv6, and so does the bridge.
- **Hardware offload.** On Qualcomm NSS routers the bridge switches off TX
  checksum offload on its own veth pair. Without that, the NSS/ECM fast path
  drops packets on forwarded TCP flows and TLS connections stall.
- **Inbound.** NetBird peers can reach the router's NetBird address. They cannot
  reach your LAN through it; this package does not make the router a NetBird
  routing peer.
- **Removing it** with `opkg remove netbird-bridge` removes the profile,
  firewall zone and namespace. NetBird's binary and identity stay unless you run
  `netbird-bridge uninstall --purge` first. Delete the peer in the NetBird
  dashboard if you are done with it.

## Troubleshooting

```sh
netbird-bridge status
netbird-bridge selftest
netbird-bridge netbird status -d
logread -e netbird
```

- *Profile connects but there is no internet:* `netbird-bridge exit-node`.
  Either no exit node is distributed to this peer's group in the NetBird
  dashboard, or none is selected.
- *The NetBird profile disappeared from the UI:* `netbird-bridge profile`.

## Building

```sh
./scripts/build-ipk.sh 0.1.0      # dist/netbird-bridge_0.1.0_all.ipk
```

Pushing a `v*` tag builds the package and publishes a release with it.

## License

MIT
