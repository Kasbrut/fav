# IPv6 implementation history

The full-tunnel IPv4/IPv6 design described in
[full-tunnel-v2.md](ipv6-full-tunnel-v2.md) was implemented before FAV 1.0.0.
This document records the resulting architecture at a high level; the current
code, tests and user-facing documentation remain authoritative.

## Implemented capabilities

- Canonical IPv6 parsing, formatting, `/64` validation and deterministic peer
  slot allocation.
- Versioned network metadata with strict validation and fail-closed handling of
  malformed or unsupported records.
- Automatic selection between routed IPv6 and blocked IPv6. Routed mode
  requires an eligible delegated prefix and return-path evidence; otherwise FAV
  uses a persistent ULA and rejects forwarded tunnel IPv6.
- Manifest-authoritative profile rendering with IPv4 and IPv6 client addresses,
  both default routes, validated DNS and MTU settings.
- Deny-first, installation-owned firewall rules with rollback, reconciliation,
  reboot restoration and ownership-aware teardown.
- Idempotent peer creation and revocation under per-interface locking, including
  recovery after interrupted operations.
- User-interface guidance that separates server verification, profile export,
  declared import and externally verified client behavior.

## Security boundaries

FAV validates its server configuration and generated profile, but it cannot
prove how another application imports that profile or whether every operating
system route follows the tunnel. A WireGuard handshake is not proof of DNS or
traffic leak protection, and a profile is not a kill switch after the VPN is
stopped. See [the security model](../security-model.md) and
[security testing record](../security-testing.md).

## Verification

The implementation is covered by Dart/widget tests, Python helper tests and
BATS tests for server-side scripts. Release validation also includes native
builds and disposable-server/client checks. See [testing.md](../testing.md) for
the current quality gate and test matrix.
