# Your first server

A step-by-step walkthrough — no prior experience required.

## 1. Get a virtual machine

A virtual machine (often called a VPS) is a small computer that runs in a data centre and is always on. You rent it by the month from a cloud provider such as Linode, DigitalOcean, Hetzner, or Vultr. The cheapest plan (typically 1 shared CPU core and 1 GB of RAM) is more than enough to run a personal [VPN](glossary://vpn).

When you order the server, choose the latest stable version of Debian or Ubuntu as the operating system. Write down three things before you close the provider's dashboard: the server's public IP address, the login username (usually `root`), and the password the provider gives you.

## 2. Open the WireGuard port

A [firewall](glossary://firewall) is a filter that decides which network connections are allowed in and out of your server. Most cloud providers apply a firewall by default, and it blocks all ports that you have not explicitly opened. WireGuard communicates over a [UDP port](glossary://udp-port) — the default is 51820 — so you need to add an inbound rule that permits UDP traffic on that port.

For step-by-step instructions specific to each major provider, see the "Firewall and port opening" entry in this Help section. Each provider's control panel looks a little different, but the steps are the same: find the firewall rules, add an inbound UDP rule for port 51820, and save.

## 3. Add the server to this app

Open Servers and choose Add a server. Fill in the public IP address, the SSH port (22 by default), the username, and the password you noted in step 1. Review Advanced only if you need to change the WireGuard port, subnet, DNS, hardening, monitoring, or backup options; then choose Connect and install.

The app connects to your server over [SSH](glossary://ssh) — an encrypted channel — and immediately shows you the server's [fingerprint](glossary://fingerprint). The fingerprint is a short code that uniquely identifies the server. Read it and confirm only if it matches what you see in your provider's dashboard or console output. Once confirmed, the app remembers it and will alert you if it ever changes — a change you did not expect can be a sign of a security problem.

## 4. Wait for the installation

After you confirm the fingerprint, FAV checks the server and starts installation. It continues on the server if the app closes. Reopen FAV to recover progress; sudo may require the password again.

## 5. Add your first peer

Installation creates a first client profile. To create another, use Add peer in the server details. On the same device, save or share the .conf file and open it with WireGuard. To import on another device, open WireGuard there, choose its QR-code import action, and scan the code shown by FAV.

Review the imported tunnel, save it, and turn it on. The exact labels vary by WireGuard platform and version; the peer detail screen includes platform-specific instructions.

Your traffic now uses the profile's IPv4 and IPv6 default routes through your own server.

## IPv6 and profile safety

FAV chooses IPv6 automatically. With a provider-delegated `/64` and verified return path it uses routed IPv6. Otherwise it uses a persistent ULA: the profile still captures IPv6, but the server rejects it instead of allowing a direct fallback. There is no IPv6 bypass option.

This verifies the server configuration and the profile FAV generated, not the device that imports it. Exporting, declaring an import or seeing a handshake does not prove client routes, a kill switch, or protection while the VPN is stopped. On Android, enable WireGuard's Always-on VPN and Block connections without VPN only if available, then validate them on that device. For other platforms, configure and test any client/OS protection separately. QR codes and .conf files contain private keys: share them only with the intended device.
