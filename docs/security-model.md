# Security model

FAV manages a remote server and therefore cannot remove the risks of changing
SSH, firewall or network configuration. Use a dedicated server and retain an
out-of-band recovery path, such as a cloud-provider console.

## SSH server identity

On the first connection, FAV shows the server's SSH host-key fingerprint and
asks the user to confirm it. The confirmed fingerprint is pinned in secure
storage for that host and port. A later mismatch blocks the connection instead
of silently accepting a potentially different server.

## Credentials and keys

- Server login passwords are held in memory only for the operation that needs
  them; they are not persisted in the app database or preferences.
- App-generated SSH private keys are stored in secure storage. They can be
  exported only through the explicit encrypted-backup flow. WireGuard keys
  originate on the server and remain there in
  restricted files. Client profiles are also stored locally in secure storage.
  QR codes, clipboard, saved files and sharing deliberately expose a client's
  private key and pre-shared key to the recipient; anyone with a profile can
  use that peer. Treat profiles as credentials. Diagnostic exports exclude them.
- Local structured data is stored in encrypted Hive boxes. Their encryption key
  is kept in operating-system secure storage.
- Portable backups use a user-supplied password, Argon2id and authenticated
  AES-256-GCM encryption. Restoring reproduces the backed-up SSH identity;
  optional online recovery can replace it on reachable servers after proving
  the new key works. Optional peer cleanup requires two confirmations and
  revokes every peer currently present on each reachable server.
- Logs, errors and diagnostic exports are scrubbed to avoid passwords, private
  keys, pre-shared keys and server-identifying values.

Provisioning may temporarily upload a mode-`0600` parameter file containing a
new management-user password. The remote installer removes that file as soon
as it has loaded the parameters. A failed launch also triggers an attempt to
remove the run directory.

## Script integrity and overrides

The bundled provisioning, monitoring and teardown scripts are hashed in the
application. Before using the default installer bundle, FAV verifies its
scripts and canonical bundle hash. Peer scripts are checked by their own
loader. A mismatch blocks use of the affected scripts.

The app can retain user-edited script overrides for advanced use. Such overrides
are intentionally not treated as trusted bundled code. Review every override
before running it on a server.

## SSH hardening and teardown

Optional hardening first verifies that the management account and its key-based
login work. The SSH configuration change is validated before it is applied,
backed up, reloaded and checked; failures trigger rollback. Password
authentication is not disabled if the key-only login cannot be proven.

When removing a server, FAV can tear down the services it installed and can
re-open SSH access. It refuses a removal that would delete the app's final SSH
key while no other recorded access path remains. These safeguards reduce risk;
they do not replace an independent recovery channel.

## Reporting a vulnerability

Do not open public issues for security vulnerabilities. Use the repository's
private vulnerability-reporting flow described in [SECURITY.md](../SECURITY.md).

## Boundaries and limitations

- The first host-key confirmation is only as reliable as the independent
  fingerprint comparison. A compromised server, client OS or unlocked app is
  outside the protection offered by local database encryption.
- New v2 profiles carry `0.0.0.0/0` and `::/0`; FAV does not offer an IPv6
  bypass. It selects routed IPv6 only after validating provider-delegated `/64`
  and return-path evidence. Otherwise it captures IPv6 in a persistent ULA
  tunnel and rejects it at the server. The fallback is not IPv6 Internet
  access, and a WAN address or IPv6 endpoint is not delegated-prefix evidence.
- This evidence covers the server configuration only. Profile generation or
  export, a declared import and a WireGuard handshake do not verify destination
  routes, DNS, OS/LAN exceptions or client leak protection. They do not create
  a kill switch or protect traffic when the VPN is stopped. Configure and test
  external client/OS protection separately. Server operators and hosting
  providers can still observe network metadata; running your own VPN does not
  provide anonymity from the host provider.
- Script hashes detect changes relative to the baseline compiled into the app;
  they are not a signature or proof that a third-party app binary is trustworthy.
- Secret storage uses platform backends; Linux requires a Secret Service keyring.
  A factory reset destroys local credentials, not remote keys or running tunnels.
- The server probe contacts `https://api.ipify.org` from the server to discover
  its public IPv4 address, then falls back to local interface addresses. Package
  installation contacts the server's APT repositories. External help links and
  GitHub reports open only when requested by the user. There is no app analytics.
- Log scrubbing is best-effort. Review reports before submitting them, especially
  text produced by custom scripts or pasted into a report manually.
