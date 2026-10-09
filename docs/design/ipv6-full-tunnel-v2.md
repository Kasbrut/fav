# Full-tunnel IPv4/IPv6 — implementation contract v2

Status: design for implementation, not a description of shipped behaviour.
Phase 0, 2026-09-17. Existing application baseline: `26ecb95`.
Changes to this contract must be reviewed by the coordinating agent before an
implementation agent changes the corresponding behaviour.

## Product invariants

- New profiles have both `0.0.0.0/0` and `::/0`, one server peer, an IPv4 `/32`
  and an IPv6 `/128`. No bypass option and no required network-mode selector.
- Effective server mode is `routed` (native IPv6) or `blocked` (IPv6 captured
  by the client tunnel and rejected by the server). `legacy` is a compatibility
  classification, never a mode for a new installation.
- The server accepts only each peer's assigned IPv4 `/32` and IPv6 `/128` in
  that peer's AllowedIPs. Never put a default route in server peer AllowedIPs.
- An IPv6 UDP endpoint does not establish IPv6 Internet egress or delegated
  tunnel space. IPv4 egress remains required in this release.
- No NAT66, proxy NDP, NAT64/CLAT or general firewall-backend migration in v2.
- FAV validates its output and server state. It cannot verify an imported
  client's routes, enforce an OS kill switch, or guarantee all system/LAN
  traffic follows a default route. Instructions refer to the destination
  client, not necessarily the OS running FAV.
- No automatic removal of `::/0` on failure. No declaration of client safety
  based on an export, handshake, or a user acknowledgement alone.

## Addressing and the T1 API boundary

Keep the canonical IPv4 `/24` and host allocation `.2` through `.254` (253
peers). Host slot 1 belongs to the server. IPv6 tunnel space is a canonical
`/64`; slot N maps to the numeric IPv6 address `prefix + N`. Decimal slot 10
therefore ends in `::a`, not `::10`. Reusing an IPv4 slot reuses its IPv6 slot
only after the old peer has been removed from persistent and runtime state.
Do not derive allocation from a display label or app UUID. Check occupancy of
both addresses before assigning the pair under the interface lock.

Use a new pure Dart helper `lib/core/utils/ipv6.dart` for parsing, canonical
formatting, prefix membership and slot assignment. Prefer bytes or BigInt to
platform-dependent integer widths. Canonical format: lowercase hexadecimal,
longest zero run compressed, first run on ties, no compression of a single
zero group. General address parsing may accept embedded IPv4; tunnel prefix
policy must reject mapped/compatible, unspecified, loopback, link-local,
multicast and other non-tunnel ranges. No brackets or zone IDs in CIDR fields;
existing bracketed endpoint support remains unchanged.

`validators.dart` adds `isValidCidrV6`, `isValidVpnSubnetV6` (canonical /64
syntax/policy), and `isValidFullTunnelMtu` (1280–1500). Keep existing
`isValidMtu` for legacy compatibility; new install wiring changes in T3/T7.
Extend `isValidDnsList` to individual IPv4 or IPv6 literals, no ports, brackets,
zone IDs, empty entries or hostnames. Reject unspecified/multicast DNS targets
for new provisioning during semantic validation, not by changing the general
endpoint parser. IPv6 DNS is not usable in `blocked` mode in v2: require an
IPv4 resolver rather than silently discarding user-entered DNS entries.

ULA: generate `fd` + 40 cryptographically random global-ID bits + a 16-bit
subnet ID of zero, yielding a /64. Generate once when creating a new install
run, persist before upload, reuse on retry/export. T1 supplies generation
using `Random.secure()` with a deterministic byte source injectable for tests;
T2/T3 own persistence. Reject local known overlaps; do not claim to discover
all client LAN conflicts. Test vectors must be shared with server validation.

Routed allocation must be within `2000::/3` and pass an explicit special-use
exclusion policy (including documentation ranges); range membership alone is
not evidence of public routability. T1 implements syntax/address arithmetic;
T3 owns eligibility exclusions and provider/route evidence. Documentation
examples below intentionally use non-deployable documentation addresses.

## Capability discovery and automatic selection

Three capability results: `supported`, `unavailable`, `unknown`, each with a
machine reason and UTC check time. `supported` means verified IPv6 egress
for the supplied routed prefix, not client leak protection.

1. Basic preflight validates OS, input and installed-state ownership.
2. Install required tools. Add explicit Debian/Ubuntu dependency `python3`:
   use its standard-library `ipaddress` and `json` for server address/schema
   processing rather than fragile Bash IPv6 arithmetic or `eval`. No pip
   dependencies. This is a deliberate phase-0 dependency decision.
3. Probe IPv4/IPv6 routes, WAN devices, IPv6 kernel availability and matching
   iptables/ip6tables backend. Do not guess `eth0` if discovery fails.
4. Require explicit routed-prefix evidence: an existing validated FAV manifest
   or an optional provider-delegated /64 input with operator attestation.
   A WAN address, on-link /64, RA prefix, or default route is insufficient.
   The optional input is shown only in contextual setup/help; not a mode menu.
5. Require return-path evidence before choosing `routed`. Use a temporary
   isolated namespace/veth test source inside the candidate /64, distinct
   from server and peer slots, forwarding through the host. Verify a reply
   from a configured external IPv6 test destination to this source. An echo
   exchange must have matching identifiers; a timeout is `unknown`, not
   proof that IPv6 is absent. Remove only owned temporary resources on every
   exit. Never add the candidate /64 as on-link to the WAN or enable proxy NDP.
6. The test destination is opt-in/configured; v2 introduces no mandatory
   FAV telemetry service or silent requests to arbitrary third parties.
   Use controlled targets in tests. Without a target/evidence, select
   `blocked` with an explanatory reason. Provider-specific automation can
   be added later without changing the profile policy.
7. If local IPv6 addresses/routes/firewall cannot support even the ULA capture
   configuration, stop provisioning; do not emit an IPv4-only success profile.
   Missing Internet IPv6 is compatible with `blocked`; a disabled local IPv6
   stack is a different problem. Do not globally re-enable it without a
   deliberate, reversible remediation.

Probe rules must be scoped to the temporary source/interface and recorded for
cleanup. A valid probe needs routing and provider attestation together; it
cannot prove reachability of every Internet destination. Repeat health checks
after installation and report later degradation without rewriting profiles.
An existing installation retains its prefix on transient probe failure; an
upgrade/change to ULA is an explicit migration, never an automatic readdress.

## Data model and persistent authority

Use explicit `ipv4Address` and nullable `ipv6Address` fields on `Peer`,
`PeerSummary`, `ClientProfile` and `PeerAddEnvelope`. Values include host CIDR.
Keep old `address`/`allowedIp` read compatibility or deprecated getters during
migration; never store a comma-separated list as one address. ClientProfile
parsing accepts both comma-separated and repeated Address entries. Reject
conflicting duplicates for a v2 profile. Raw .conf remains the secret-bearing
authority in secure storage; do not place key material in ordinary Hive maps.

Persist a versioned network configuration on `WireguardInstallation` and
install-run state with: `schemaVersion=2`, installation ID, revision,
`ipv6Mode`, IPv4 subnet, effective IPv6 /64, fallback ULA /64,
server IPv6 /64 address, capability result and its reason/time. Preserve
endpoint/DNS/MTU in the server manifest so peer generation does not reconstruct
them from defaults. The planned optional prefix input belongs in
`AdvancedOptions`; an effective mode is resolved data, not a user preference.

Missing version means v1/legacy. Unknown future versions or partial v2 data
remain readable for diagnostics but reject mutation/export as v2. A malformed
v2 record must not be reinterpreted as legacy. App local data is a cache for
server-managed allocation; an SSH refresh reconciles mismatches before writes.

Server manifest: `/etc/wireguard/fav/<interface>/manifest.json`, root-owned
0600 with 0700 directory. It is JSON data, never sourced as shell. Example
(shape, not a usable installation):

```json
{
  "schemaVersion": 2,
  "installationId": "stable-uuid",
  "revision": 1,
  "state": "ready",
  "interfaceName": "wg0",
  "network": {
    "ipv4Subnet": "10.13.13.0/24",
    "ipv6Mode": "blocked",
    "ipv6Subnet": "fd12:3456:789a::/64",
    "fallbackIpv6Subnet": "fd12:3456:789a::/64",
    "serverIpv6Address": "fd12:3456:789a::1/64",
    "wan4": "eth0",
    "wan6": null,
    "endpointHost": "vpn.example.org",
    "listenPort": 51820,
    "dns": ["1.1.1.1", "1.0.0.1"],
    "mtu": 1420
  },
  "capability": {
    "status": "unknown",
    "reason": "no_delegated_prefix",
    "checkedAt": "2026-09-17T00:00:00Z"
  },
  "peers": [],
  "resources": {"rules": [], "routes": [], "sysctls": []},
  "pendingOperation": null
}
```

Each peer record contains operation ID, public key, slot, v4/v6 CIDR and
profile version (no private key/PSK). Resources record exact owned rule argv,
route attributes and sysctl original/applied values. Never execute arbitrary
resource argv read from a manifest: validate against known operation schemas.
Revision increments only on committed changes. Reject symlink/unowned manifest
paths and validate installation/interface identity before operating.

Write atomic replacements in the same filesystem under lock. A write-ahead
`pendingOperation` plus protected backup permits reconciliation of crashes
between config, runtime and manifest changes. `ready` is committed only after
all three agree. Keep existing app secrets until the replacement is securely
stored. A lost SSH response triggers reconciliation by operation ID, not a
second peer allocation. Key/PSK recovery stays over authenticated SSH and
uses protected server files; failures never expose secrets in diagnostic logs.

## Versioned transport

Keep existing `VPN_SUBNET`, DNS, endpoint, port and MTU variables. Add request
fields (shell-quoted using the existing writer; validate again on the server):

```sh
FAV_CONFIG_VERSION="2"
FAV_INSTALLATION_ID="stable-uuid"
FAV_OPERATION_ID="operation-uuid"
VPN_IPV6_ULA_SUBNET="fd12:3456:789a::/64"
VPN_IPV6_ROUTED_SUBNET=""
IPV6_PROBE_TARGET=""
```

These are inputs, not proof that a mode is active. The server selects the mode
and emits a validated `network-result.json` using the manifest's version,
identity, revision, network and capability fields. Missing/invalid result
prevents the app recording success. Existing installer run-state/exit protocol
is retained. Peer operations use installation ID plus operation ID and read
effective settings from the manifest; conflicting app inputs fail explicitly.

Peer envelope v2 (illustrative placeholders):

```text
FAV_ENVELOPE_VERSION=2
INSTALLATION_ID=stable-uuid
OPERATION_ID=operation-uuid
REVISION=2
IPV6_MODE=blocked
ADDR4=10.13.13.2/32
ADDR6=fd12:3456:789a::2/128
PUBKEY=<client-public-key>
---BEGIN-CONF---
[Interface]
PrivateKey = <client-private-key>
Address = 10.13.13.2/32, fd12:3456:789a::2/128
DNS = 1.1.1.1, 1.0.0.1
MTU = 1420

[Peer]
PublicKey = <server-public-key>
PresharedKey = <preshared-key>
Endpoint = vpn.example.org:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
---END-CONF---
```

A routed example differs in addresses, e.g. `2001:db8:1234:5678::2/128`,
and `IPV6_MODE=routed`; routing is a server fact, not a portable WireGuard
profile field. `2001:db8::/32` is only an illustration and fails deployment
eligibility. Validate envelope identity, keys, addresses, routes and manifest
revision against the profile. Duplicate required headers, missing end marker,
unknown version or mismatch fail closed. Accept banners before the envelope;
no diagnostic output inside it. Read v1 envelopes only as legacy.

Shared renderer and network/manifest helper must be shipped with install,
peer and teardown bundles as needed, integrity-checked, and reachable after
RUN_DIR cleanup (persistent root-owned helper directory for wg-quick hooks).
Update asset manifests, hash maps, pubspec assets and isolated test bundles
in the same task that introduces a helper. Never assume the installer upload
is available to a later peer operation.

## Firewall, lifecycle and concurrency

- Scope filter chains to installation/interface with validated short names;
  include explicit ownership comments. Track actual WAN4/WAN6 separately.
- Server INPUT: preserve existing WAN/SSH policy; accept required tunnel
  control traffic, deny new tunnel-origin access to other host services by
  default. External DNS is used in v2; no implicit DNS server on the host.
- FORWARD: reject peer-to-peer; validate tunnel source prefixes; allow IPv4
  Internet egress and established/related return; block new WAN-to-peer flows.
  IPv4 NAT remains scoped to the VPN subnet and actual WAN4.
- Routed IPv6: same stateful filtering without NAT, permit required ICMPv6
  errors/PMTU. Preserve WAN NDP and necessary RA independently of tunnel rules.
- Blocked IPv6: explicit terminal rejection of forwarded IPv6 arriving from
  the tunnel, even when another service already enabled IPv6 forwarding.
  No generic accept rule may bypass this decision. INPUT policy remains
  explicit; dropping forwarding alone does not protect server services.
- Existing UFW/Docker/backend arrangements must be tested. Unsupported or
  conflicting enforcement fails provisioning with an actionable error; never
  flush host chains or declare success after checking only rule presence.
- Apply deny guards before enabling forwarding/starting the interface; then
  open only selected egress. The current numerical 50/60 module order cannot
  be taken as sufficient: factor a guard step before module 50 in T5.
- Install/upgrade/teardown take global FAV lifecycle lock, then interface lock;
  peer add/revoke take interface lock. Never take locks in reverse order.
  Use the same interface lock path as existing peers where possible.
- Protect shared forwarding/RA sysctls with global ownership/reference tracking.
  On teardown restore original runtime state only when the value is still
  FAV's applied value and no remaining FAV installation requires it; preserve
  foreign configuration. Remove only FAV drop-ins and owned rules/routes.
- wg-quick hooks use the same idempotent enforcement helper and persisted
  resource identity; retain guards until the interface is down. WAN changes
  require reconciliation; stale egress should fail closed, not select an
  arbitrary new interface. Reboot restores protections before traffic flows.

Error tokens for new scripts: `ERR-NET-CONFIG-INVALID`,
`ERR-NET-VERSION-UNSUPPORTED`, `ERR-NET-IPV4-UNAVAILABLE`,
`ERR-NET-IPV6-LOCAL-UNAVAILABLE`, `ERR-NET-FIREWALL-UNSUPPORTED`,
`ERR-NET-STATE-CONFLICT`, `ERR-NET-APPLY-FAILED`. New network failures exit 42;
existing peer exit 40/41 contracts remain. Missing delegated prefix or an
inconclusive external probe is a capability reason, not installation failure
when the validated blocked fallback works. Map new tokens in app error handling
and localization; messages never include keys or credentials.

## Supported state and acceptance gates

FAV is still in development and supports only installations created with the
current v2 contract. There is no released legacy installation population to
migrate, upgrade or preserve. Development-only v1/legacy compatibility code is
not a product requirement and must not add UI, migration flows, release gates or
implementation work to the remaining IPv6 plan. New scripts still reject
missing, malformed, partial or unsupported metadata before mutation, and the
app refuses to export an invalid/custom-script result as a protected v2 profile.

Required gates before release:

1. Unit/BATS vectors for address arithmetic, schema/version handling, profile
   parity, allocation collision, partial writes and ownership-aware teardown.
2. Linux integration: real WireGuard/netfilter, guard ordering, rollback,
   forwarding already enabled, reboot, DNS, PMTU, spoofing, incoming WAN,
   peer isolation, UFW/Docker and loss of the return route.
3. Android/iOS/macOS/Linux/Windows: record client/OS/backend versions; test
   routed and blocked profiles, IPv4/IPv6/dual-stack access networks, roaming,
   existing connections, suspension and disabled VPN. Use packet capture and
   controlled endpoints; a failed IPv6 request alone is not a no-leak proof.
4. Validate per-platform external protections and instructions separately from
   basic profile routing. No runtime cross-platform kill-switch promise.

Real server/client tests are pending. No server credentials or disposable-device
matrix were supplied for phase 0; do not contact existing servers or fabricate
certification. These gates do not prevent implementing pure T1/T2 components.
