# FAQ

## What is a VPN, in one sentence?

A VPN is a tunnel between your device and a server: your device's traffic appears to come from the server, and the connection between your device and the server is encrypted.

## Why do I need my own server?

You control the VPN server and its configuration. You still need to trust the hosting provider and server administrators, who can observe network metadata. A self-hosted VPN does not make you anonymous.

## How much does it cost to run?

FAV is free. Hosting and bandwidth charges depend on your provider and plan; check their current prices and traffic limits.

## Is the password I type into the app stored on my device?

Login and sudo passwords are requested when needed and are not saved as app data. The app generates its SSH key during provisioning, even when hardening is off, and keeps it in secure storage.

## Can I move my server to another device?

Yes. Open Settings → Backup and restore to create a password-encrypted `.favbackup` file. Restore it only into an empty FAV installation. Avoid managing the same servers from both devices: locally stored records can diverge. If the old device was lost or compromised, restore can rotate FAV's SSH keys and, after two confirmations, revoke every existing peer on reachable servers.

## Can the app route my device through the VPN automatically?

Not yet. Today the app sets up the server — your device connects via the official WireGuard app. Building the client into this app is on the long-term roadmap.

## What does "Enable hardening" do?

Hardening (in Advanced options, off by default) locks down the whole server after the install: it turns off SSH password sign-in so only key login works, disables root SSH login, and adds brute-force protection. It applies to whichever user the app manages the server as — the user it creates for a root login, or your existing user for a non-root sudoer login. The app first checks that your key-based login works and rolls back automatically if anything looks wrong, but always keep your provider's console handy as a way back in.

## How do I remove a server?

In Servers, swipe a server, use its menu, or choose Remove server in its details. Select **Remove VPN & services** for a remote teardown before FAV forgets it; when applicable, you can also undo SSH hardening. Leave that option off and choose **Disconnect FAV and remove** to remove only FAV's SSH key remotely while leaving the VPN running. **Forget without contacting server** removes only local data and leaves every remote change, including FAV's SSH key; use it only when the server cannot be reached or you will clean it yourself. Failed remote steps can be retried before choosing local-only removal.

## I'm having trouble — what should I do?

Check the **Error codes** section in this Help tab if you saw a red error. If you still can't find a solution, use **Report a problem** to open a prefilled GitHub issue.

## IPv6 and profile safety

New v2 profiles include IPv4 and IPv6 default routes; FAV has no IPv6 bypass setting. It uses routed IPv6 only after verifying provider-delegated `/64` return-path evidence. Otherwise, blocked mode captures IPv6 in a ULA tunnel and rejects it on the server, rather than using direct IPv6. A public IPv6 endpoint is not that evidence.

FAV verifies the server result and generated profile only. Export, a declared import and a WireGuard handshake do not verify the destination client's routes or a kill switch, and do not protect traffic after the VPN stops. Configure and validate client/OS protection separately. On Android, check the target device's Always-on VPN and Block connections without VPN settings; their availability and behaviour are not verified by FAV. Use a dedicated server and keep console access. QR codes and .conf files contain private keys: share them only with the intended device.
