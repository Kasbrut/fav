# Security Policy

FAV provisions a Debian/Ubuntu server into a WireGuard VPN endpoint over SSH.
It handles SSH credentials, generates and stores private keys, pins host keys,
and can modify the server's `sshd_config` and firewall. Security is a core
correctness concern, so vulnerability reports are very welcome.

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Report privately through GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability):
go to [Report a vulnerability](https://github.com/Kasbrut/fav/security/advisories/new). This opens
a private advisory visible only to you and the maintainers.

If private reporting is not yet available, contact
[fav-security.transform916@slmail.me](mailto:fav-security.transform916@slmail.me) instead. Do not publish
exploit details in a public issue.

When reporting, please include:

- A description of the issue and its impact.
- Steps to reproduce (a proof of concept if possible).
- Affected version / commit.

You can expect an initial acknowledgement within a few days. We will work with
you on a fix and coordinate disclosure once a patch is available.

## Scope

The areas most relevant to security:

- SSH transport and authentication (`dartssh2` usage).
- Host-key Trust-On-First-Use: fingerprint pinning and mismatch handling.
- Secret handling: SSH/WireGuard private keys, pre-shared keys, and server
  login passwords.
- Secret storage (`flutter_secure_storage`) and the encrypted local database.
- The anti-lockout / SSH-hardening flow (disabling root login and password
  authentication), for any login user — the account FAV creates for a root login
  or the existing login user for a non-root sudoer.
- The server-removal teardown flow: re-opening SSH (reversing hardening) and
  removing FAV's deployed key, with its anti-lockout guard.
- The bundled installer scripts and their integrity verification.
- Encrypted backup creation and restore, including optional SSH-key rotation
  and bulk peer revocation.

## Security model (summary)

- Server login passwords are **never persisted** — they are requested on demand
  and held only in memory for the duration of a single operation.
- App-generated SSH private keys are kept in OS-backed secure storage. They
  leave it only inside an explicitly created, password-encrypted FAV backup.
  WireGuard keys are generated on the server;
  client profiles are stored locally in secure storage and intentionally
  displayed/exported through QR, copy, share and save actions. Those profiles
  contain private keys and pre-shared keys. Server-side keys and backups remain
  on the server until revoked or removed; protect both endpoints.
- The local database is encrypted with a key held in the OS keychain/keystore.
- Portable backups use Argon2id password derivation and authenticated
  AES-256-GCM encryption. A restored backup intentionally reproduces the same
  management identity until the user selects SSH-key rotation. FAV cannot
  recover a forgotten backup password.
- Host keys are pinned on first connect (the fingerprint is shown to the user);
  any later mismatch blocks the connection with an explicit error.
- Disabling root SSH / password authentication follows a verify-then-apply
  sequence with an `sshd -t` dry-run, a config backup, an effective-config
  re-check, and rollback on any anomaly. Password authentication is disabled only
  after a key-only login is proven for the management user, so a broken key
  deployment fails safe (password login is left enabled).
- Removing a server can optionally tear down the FAV-installed services and
  re-open SSH (reverse hardening) using the same verify/backup/reload/rollback
  harness; FAV's deployed key is removed last. An anti-lockout guard refuses a
  removal that would strip the only remaining way in, and a failed remote step
  leaves the local record intact so it can be retried.
- Secrets are sanitized out of logs, error messages, and diagnostic exports.
- An optional app lock reuses the device's own unlock (biometrics with a
  PIN/passcode fallback) at launch and on every return from the background.
  The feature is unavailable on Linux. It protects the UI only — database
  encryption does not depend on
  it — and it deliberately fails open if the device unlock is removed, so it
  can never lock you out of your own data.

## Disclaimer

FAV changes remote server configuration, including SSH access and firewall
rules. While it includes anti-lockout safeguards, you run it against your own
servers at your own risk. Always keep an out-of-band recovery path (e.g. a
provider console) available when hardening a server.
