# User guide

FAV provisions a server over SSH. It does not run a VPN tunnel on your device;
use a WireGuard client to import and activate the profiles it generates.

## Before installation

Use a dedicated Debian/Ubuntu machine with kernel 5.6+, systemd, Bash and APT.
FAV checks the distribution ID and kernel, not a certified list of OS releases.
Use an actively maintained distribution and validate it on a disposable server
before relying on it. Containers without kernel WireGuard/network privileges
and non-systemd systems are outside the supported setup.

Have the server address, SSH port, username, password and provider console
available. A non-root user needs sudo access. Initial onboarding uses a
password; importing an existing SSH private key is not supported. User key
uploads are **public keys**. Keep their private counterparts outside FAV so
you can administer the server independently.

Allow the SSH TCP port and WireGuard UDP port through provider and host
firewalls. FAV adds iptables NAT/forwarding rules but does not replace UFW,
nftables policies or provider firewall rules. Avoid hosts running Docker,
other VPNs or unrelated services: installation and teardown affect shared
network configuration.

## Install and connect

1. Add the server, then compare the SSH host-key fingerprint against a trusted
   source such as the provider console before accepting it. A later mismatch
   is blocked; investigate it rather than accepting a new key blindly.
2. Start installation from the server screen. Review management-user creation
   and the advanced settings. Defaults are UDP 51820, `wg0`, `10.13.13.0/24`,
   MTU 1420, DNS `1.1.1.1, 1.0.0.1`, monitoring on and SSH hardening off.
3. Optionally provide your own SSH public keys. If enabling hardening, verify
   independent console/key access first. FAV verifies the management key before
   disabling root/password SSH login and configures fail2ban for the SSH port.
4. Wait for the detached installer to finish. If the app closes or connectivity
   changes, reopen it and use run recovery. A password may be needed again for
   sudo. Remote completion alone does not prove post-install hardening finished;
   inspect the app's reported outcome.
5. Import the first generated profile into a WireGuard client, or add more peers
   from the server detail screen. Use QR from another screen, or save/import the
   `.conf` file on the same device. Use a distinct peer for each device.
6. Activate the tunnel and verify connectivity, DNS and the public IPv4 address.
   Perform the IPv6/client checks below on the device that imports the profile.
   Reboot the server and verify that the tunnel still works before relying on it.

The IPv4 subnet must be a canonical `/24` ending in `.0/24`; `.1` belongs to
the server and `.2`–`.254` to peers. Avoid overlap with the server or client
LAN. IPv6 literals are accepted as public endpoints.

## IPv6 policy and client limits

New v2 profiles always include the IPv4 and IPv6 default routes
(`0.0.0.0/0`, `::/0`) and one IPv4 `/32` plus one IPv6 `/128` for the client.
There is no FAV bypass option and no mode selector. FAV automatically selects:

- **Routed:** native IPv6 only after FAV verifies a provider-delegated eligible
  `/64` and a return path to a configured external IPv6 target. A WAN IPv6
  address, router advertisement, on-link prefix or IPv6 endpoint is not enough.
- **Blocked:** when that evidence is absent, unavailable or inconclusive, FAV
  retains a per-installation ULA prefix, captures IPv6 in the tunnel and the
  server rejects forwarded tunnel IPv6. This is intentional failure of IPv6
  Internet traffic, not a direct-IPv6 fallback. If local IPv6 cannot support
  even this capture configuration, provisioning fails rather than producing an
  IPv4-only success profile.

The app can verify the v2 server configuration and the profile it generates.
It cannot verify routes after another app imports the file, infer protection
from a handshake, or guarantee that all OS, LAN or system traffic follows the
default routes. The app's “imported” indication is a user declaration, not a
technical client check. A profile and handshake also do not provide a permanent
kill switch or protection after the VPN/client is stopped.

Choose instructions for the **destination client**, which may differ from the
device running FAV. On Android, WireGuard's Android VPN settings can offer
Always-on VPN and “Block connections without VPN”; enable them only if present
and validate the result on the target Android version. For iOS/iPadOS, macOS,
Windows and Linux, FAV has not verified a portable kill-switch configuration:
follow the client/OS documentation and test it yourself. Before treating a
setup as protected, test routed and blocked profiles with controlled endpoints
and packet capture across the target networks, roaming and a stopped tunnel.

## Profiles, peers and monitoring

A profile contains private key material. QR, clipboard, file export and sharing
all disclose it to their recipient. Do not attach profiles or QR screenshots
to GitHub issues. Revoke a peer if its profile is exposed or its device is lost.
Renaming a peer changes its label; revocation removes its server access.

Monitoring infers online status from WireGuard handshakes and traffic counters;
it is not proof that a user is present. The agent runs periodically, and history
is retained for seven days. Monitoring data includes peer/network metadata.

The SSH terminal uses the same host-key verification and credentials as other
operations. Commands run with the privileges of the connected account; changes
made manually are not automatically tracked or reversed by FAV.

## Removal, reset and recovery

Removing a server can also remove its services and reopen SSH. Remote cleanup
stops the WireGuard unit and removes its configuration/keys, monitor, firewall
rules, forwarding drop-in and FAV fail2ban jail. Packages and the management
account remain installed. Reloading sysctl does not necessarily reset a runtime
forwarding value if no remaining configuration specifies it. SSH reopening is
optional and changes the server's authentication policy.

FAV removes its deployed SSH public key last. The anti-lockout check uses the
access paths recorded in the app; it cannot prove that an external private key
or password is still available. Test your independent access yourself.

If remote cleanup fails, retry (entering the password again), or remove locally.
Local-only removal does not stop the remote VPN. Local deletion is best-effort
for related credentials; use a full factory reset to erase all app data.

A factory reset deletes all local servers, profiles, keys, preferences and run
history. It does not revoke peers, restore remote SSH configuration or stop the
server.

Settings → Backup and restore creates a password-encrypted `.favbackup` file
containing server records, pinned fingerprints, FAV SSH keys, peer profiles,
custom scripts and transferable settings. Passwords, app lock, diagnostics and
monitoring history are excluded. Restore requires an empty FAV installation
and verifies each server online. If the old device was lost or compromised,
restore can rotate FAV's SSH keys and, after two confirmations, revoke every
existing peer on reachable servers. Offline servers remain pending. Avoid
using restored data concurrently on multiple devices, keep the backup private,
and retain your own SSH key and provider console.

Installation can leave protected run files after a connection failure. These
live under `/opt/wg-installer/`, `/var/lib/wg-installer/` and
`/var/log/wg-installer/`. Inspect run state before manually cleaning them up;
do not delete an active run. Server configuration and keys are under
`/etc/wireguard/`. Never paste their contents into public reports.

## Troubleshooting

Use Help → Error codes for the specific error, and review diagnostics before
using Report a problem. For a connectivity failure check the server address,
SSH/UDP ports, host and provider firewall rules, and the client's IPv4/IPv6
routing. A blocked IPv6 profile is expected not to reach the IPv6 Internet
through the server. For a startup storage failure use the recovery screen only after
considering the consequences of erasing local credentials. Security reports
belong in the private channel described in [SECURITY.md](../SECURITY.md).
