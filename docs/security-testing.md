# Security Testing

FAV has been tested beyond basic installation and happy-path checks. The
following security-relevant tests have been completed.

## Real server testing

- Full provisioning, peer creation, peer revocation, VPN traffic, reboot and
  teardown on Debian 12, Debian 13, Ubuntu 24.04 and Ubuntu 26.04.
- Installation from both root and sudo accounts, including passwordless sudo.
- All combinations of SSH hardening and monitoring enabled or disabled.
- Verification that SSH access remains available after hardening and reboot.
- Custom SSH and WireGuard ports, and a custom VPN subnet.
- Complete teardown verification, including firewall and service cleanup.
- Native macOS end-to-end verification of provisioning, profile export,
  restart persistence, peer revocation and reuse, reboot recovery and teardown.
- Native macOS profile exports verified with owner-only (`0600`) permissions;
  automated coverage prevents regressions on POSIX desktop systems. The native
  share sheet and export paths containing spaces and non-ASCII characters were
  also verified.
- Native iPadOS end-to-end verification of provisioning, SSH hardening,
  profile handling, peer lifecycle, app-lock behavior and teardown.
- Native iPadOS layout verification in light/dark themes, multiple languages,
  both orientations, windowed mode and practical accessibility text sizes.
- Native iPadOS recovery after forced app termination while the detached
  installer completed successfully on the server.
- A second physical Android device was used to verify root provisioning,
  profile import, live VPN use, peer revocation, biometric app lock and
  teardown without relying on data from the original device.

## Failure and recovery testing

- Network interruption during provisioning, including automatic SSH
  reconnection and successful completion.
- Recovery after the app is interrupted while the server finishes the
  installation independently.
- Offline hosts, incorrect addresses and invalid credentials handled before
  provisioning without reporting false success.
- A changed SSH host key was rejected before provisioning with an explicit
  possible man-in-the-middle warning.
- Intentional SSH host-key rotation was verified end to end: mismatch warning,
  old/new fingerprint comparison, authenticated replacement and pin update.
- Unreachable package repositories reported as an explicit package-installation
  failure, without false success or a partially active VPN.
- A forced late-stage installer failure was reported at the correct step and
  automatically rolled back the active interface and server configuration,
  while retaining the diagnostic log until the user left the failure screen.
- Duplicate actions blocked while sensitive operations are running.
- Partial-run cleanup and removal of temporary server-side files containing
  client secrets.

## Peer and configuration safety

- Peer add, revoke and address reuse after revocation.
- Automated coverage for concurrent peer operations, exhausted address pools,
  rollback, idempotency and revocation.
- Rejection of invalid WireGuard ports and malformed subnets.
- Separation between local-only removal and verified remote teardown, with an
  additional confirmation for local-only removal.

## Tunnel behavior

- A physical Android client was tested through a public Debian 13 VPS: its
  visible IPv4 address matched the VPS, IPv6 connectivity was unavailable,
  and standard and extended DNS leak tests reported only Cloudflare resolvers.
- The tunnel retained the VPS address while roaming from Wi-Fi to mobile data
  and back. When the VPS WireGuard port was deliberately blocked, new traffic
  stopped instead of falling back outside the active tunnel, then recovered
  after the port was restored.
- Concurrent VPS captures recorded 28,078 decrypted packets on the WireGuard
  interface and 32,476 WireGuard UDP packets on the public interface. The
  pre-existing Docker service remained available throughout provisioning and
  tunnel tests.
- Android full-tunnel routing was verified for IPv4 and IPv6, including VPN
  DNS selection and live server-side handshake and traffic counters.
- With the WireGuard endpoint deliberately blocked, the active tunnel did not
  fall back to the underlying connection; connectivity resumed immediately
  when the endpoint was restored.
- Android always-on VPN and its connection-blocking mode were verified: both
  an unreachable endpoint and a disabled tunnel blocked network access, while
  access recovered after the tunnel was restored.
- With Android's connection-blocking mode disabled, normal connectivity
  resumed after explicitly disabling the VPN.
- Controlled-gateway packet captures detected no clear IPv4 traffic outside
  the tunnel while it was active or while its endpoint was unreachable. A VPN-
  off positive control captured 7,701 packets through the same gateway.

## Automated security checks

- Shell tests cover locking, rollback, firewall behavior, teardown,
  provisioning options and peer lifecycle edge cases.
- Application tests cover SSH error classification, recovery, credential
  handling, duplicate submissions and secure cleanup.
- Installer bundle integrity is checked before execution.

These tests materially reduce risk, but they are not a formal security audit.
Independent packet-capture verification of IPv6 leak behavior is not claimed
as complete.
