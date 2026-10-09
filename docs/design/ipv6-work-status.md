# IPv6 implementation checkpoint

Updated: 2026-09-18. Contract: [full-tunnel v2](ipv6-full-tunnel-v2.md).

## Current checkpoint

- Phase 0 design deliverable complete: contracts for address allocation,
  persistence, probe evidence, script protocol, firewall lifecycle and errors.
- T1 IPv6 helpers/validators completed, reviewed and verified.
  Provisioning and generated tunnel profiles remain IPv4-only until later tasks.
- Baseline commit: `26ecb95`; working tree clean before this task.
- One GPT-5.6 Luna agent performed a focused read-only interface/bundle audit.
  Coordinator wrote and reviewed the contract. No recursive delegation.
- T2b completed: multi-address profiles, strict peer envelope v2, semantic
  network validation and mutation/export gates. T2a and T2b are separate
  commits. Next task: T3 only.
- Phase 0 device/server prototype validation is **pending**, not passed. It is
  a prerequisite for certifying behaviour, not for implementing pure helpers.

## Verification performed

Command:

```sh
fvm flutter test test/core/utils/validators_test.dart test/features/profile/data/client_profile_parser_test.dart test/features/peers/data/peer_add_envelope_parser_test.dart test/features/install/data/provisioner/config_env_writer_test.dart test/features/install/data/scripts/script_integrity_test.dart
```

Result: **61 tests passed**, standard Flutter runner, exit 0. Dependency
resolution did not change tracked files. This is a targeted baseline, not the
full project suite or an IPv6 implementation test.

`./scripts/test-shell.sh`: exit 1 at its prerequisite check (system Bash 3.2;
Bash 4+ required). BATS exists, but the shell tests did not execute. Set up a
Bash 4+/GNU-utils environment before shell implementation validation; do not
weaken the wrapper or label this a test assertion failure.

No live server, client leak, native build or complete CI test was run here.
No push or release. Last quota reading supplied by user: 6% five-hour (latest user update),
69% weekly (previous reading); the coordinator has no live quota counter. No current remaining
percentage can be inferred from this checkpoint.

## T1 handoff

Model: GPT-5.6 Luna, medium reasoning, fresh focused context. Read the contract's
product invariants and addressing/T1 section plus existing validators/tests.
Allowed edits:

- `lib/core/utils/ipv6.dart` (new pure helper);
- `lib/core/utils/validators.dart`;
- `test/core/utils/ipv6_test.dart` (new);
- `test/core/utils/validators_test.dart`.

No UI, model migration, script, hash or profile-generation edits. No new Dart
package. Use byte/BigInt arithmetic, deterministic random injection for tests,
canonical /64 validation and the exact slot mapping from the contract. Preserve
legacy MTU validation and endpoint behaviour. Add new full-tunnel MTU validator;
extend DNS syntax to raw IPv6 literals without ports/brackets/zones. Persistent
ULA lifecycle and routed-provider eligibility evidence belong to T2/T3, not T1.

Run targeted tests and formatter on changed files. Coordinator reviews the diff,
edge cases and test results, then commits a coherent T1 change. Do not add tests
that merely duplicate the implementation algorithm; use independent literal
vectors and invalid/edge inputs. Report ambiguities before expanding scope.

## Subsequent tasks

T2 models/persistence; T3 probe/SSH; T4 config/profiles; T5 firewall/teardown;
T6 peer lifecycle; T7 minimal UI; T8 docs/locales; T9 integration and release
validation. The former legacy-migration task was removed because the product is
unreleased and v2-only. Follow one task at a time; do not automatically publish.

## T1 completion

Implemented by Luna, reviewed and corrected by coordinator. New byte-based IPv6
parser/formatter, membership and slot arithmetic, secure-default ULA generator;
CIDR /64, full-tunnel MTU and mixed DNS syntax validators. Existing endpoint
brackets and legacy MTU remain supported. Embedded IPv4 octets with ambiguous
leading zeros are now rejected. Provider eligibility and persistence remain T2/T3.

Final verification: **65 tests passed** across IPv6, validators, advanced form,
profile parser and config-env writer; targeted Dart analysis **no issues**;
formatter clean. No shell scripts changed. No live tunnel protection added yet.

Commands:

```sh
fvm flutter test --no-pub test/core/utils/ipv6_test.dart test/core/utils/validators_test.dart test/features/install/presentation/advanced_form_screen_test.dart test/features/profile/data/client_profile_parser_test.dart test/features/install/data/provisioner/config_env_writer_test.dart
fvm dart analyze lib/core/utils/ipv6.dart lib/core/utils/validators.dart test/core/utils/ipv6_test.dart test/core/utils/validators_test.dart
```

Quota caution: the last reported five-hour balance fell from 30% to 6% during
this task. Do not infer future cost from model price alone; coordinator context
and review also consume allowance. No next task started. Resume with this file
and the contract rather than replaying the conversation.

## T2 start

User requested continuation with last reported five-hour quota 6%. T2 is split:
T2a adds backward-compatible models/mappers and persistence tests; T2b handles
profile/envelope parsing and validation. One Luna agent executes T2a only.
No provisioning/UI changes; no next task started. Agent recovery notes:
/tmp/fav-t2-progress.md (temporary, final evidence must be copied here).

## T2a checkpoint

Completed backward-compatible IPv6 fields and IPv4 alias getters on peer/profile
models; optional delegated prefix on AdvancedOptions; network metadata on install
runs and installations, with dedicated shared mapper and explicit legacy,
structurally valid, invalid and unsupported states. This is structural storage
support, NOT server/client protection certification. No script or UI changes.

Luna implemented the models; coordinator corrected mapper handling for malformed
containers, legacy roundtrips and required structural fields, and added regression
tests. 39 tests passed across network/run/server mappers, peer repository and
legacy profile/envelope parsers. Targeted analysis clean after import-order fix.

T2 remains incomplete: T2b must implement profile/envelope versions and parsing,
semantic network validation (subnet/address consistency, UTC evidence and mode
requirements), refusal of mutation/export for unusable metadata, and explicit
clearing semantics for optional fields where migration needs them. ULA generation
before upload belongs to T3; T2a only provides persistent storage for it. Do not
mistake isStructurallyValidV2 for a security or reachability guarantee. Unknown
schema data is diagnostic only; never overwrite it through normal v2 operations.

New test: test/features/servers/data/network_mappers_test.dart. No live server,
leak or BATS tests run for this Dart-only increment. Last quota reading remains
6% (user then explicitly authorized continuation); no next task started.

## T2b checkpoint

Completed profile parsing for repeated and comma-separated `Address` entries,
with explicit IPv4/IPv6 fields and strict v2 validation for canonical host
CIDRs, WireGuard keys, DNS/MTU and both default routes. Legacy profiles and v1
peer envelopes remain readable.

Implemented peer envelope v2 with required unique headers, explicit version,
installation/operation identity, revision and mode. V2 parsing requires an
expected operation context and cross-checks the derived client public key,
profile/header addresses, allocation slot, persisted subnets and full-tunnel
routes. Partial, corrupt and future envelopes fail closed and are not retried
as legacy.

Added semantic validation above `isStructurallyValidV2`: canonical IPv4 /24,
eligible effective/fallback IPv6 /64 values, ULA fallback, server slot 1,
UTC capability evidence and mode/capability consistency. Invalid and future
metadata retain their original map across ordinary persistence. Nullable
network/IPv6 model fields now have explicit clearing semantics.

The profile providers validate v2 metadata and profile parity before exposing
raw configuration to QR/copy/share/save consumers. Peer add/revoke rejects
invalid or unsupported metadata before SSH. Semantically valid v2 peer
mutations are also blocked from the current legacy scripts: enabling those
operations requires the manifest-aware T6 protocol and would be unsafe in
T2b. Legacy operations remain supported.

Verification:

```sh
fvm flutter test --no-pub test/core/utils/ipv6_test.dart test/core/utils/validators_test.dart test/features/profile/data/client_profile_parser_test.dart test/features/profile/application/client_profile_provider_test.dart test/features/peers/data/peer_add_envelope_parser_test.dart test/features/peers/data/ssh/peer_add_runner_test.dart test/features/peers/data/legacy_peer_migrator_test.dart test/features/peers/data/hive_peer_repository_test.dart test/features/peers/application/peers_controller_test.dart test/features/servers/data/network_mappers_test.dart test/features/servers/data/server_mappers_test.dart test/features/install/data/run_mappers_test.dart
fvm flutter analyze
```

Result: **113 tests passed**. Full analysis exited 0 with no errors or warnings;
it reported 22 existing `prefer_initializing_formals` info diagnostics, including
two in the otherwise unchanged constructor of `peer_add_runner.dart`. No lint
was suppressed. `git diff --check` passed.

No shell/BATS, live server/client, leak, native build or full test suite was run
for this Dart-only task. Provisioning and generated profiles remain IPv4-only;
T3 must add probe/result transport and T4/T5/T6 must implement actual profile,
firewall and peer lifecycle behavior. One GPT-5.6 Terra agent performed a
read-only T2b surface audit; the coordinator reviewed the diff and test output.
No recursive delegation, push or release. No live quota balance was available.

## T3 checkpoint

T3 completed the versioned provisioning request and result contract. New runs
generate one ULA before upload, persist it with stable installation/operation
identities, and reuse those values through confirmation retry and recovery.
The shell-quoted transport carries all six v2 fields; legacy records remain a
separate unversioned path.

The server now installs `python3`, `iproute2` and `iputils-ping`, validates v2
inputs again with Python standard-library `ipaddress`/`json`, discovers IPv4
and IPv6 default-route devices independently, verifies matching
iptables/ip6tables backends and exercises local ULA configuration in an owned
temporary namespace/veth. Routed mode requires an explicitly supplied eligible
/64, an explicitly configured external target, existing IPv6 forwarding and a
correlated ping reply from a source near the end of the supplied prefix.
Missing target or timeout is `unknown`; missing attested prefix is
`unavailable`; both select blocked ULA metadata. No WAN/default route is used
as prefix evidence, no `eth0` fallback exists, and no global IPv6 sysctl is
enabled. Owned namespace, veth, host route and narrow temporary probe rules are
cleaned on success and failure.

`network-result.json` is written atomically with version, identities, revision,
effective network, distinct WANs and capability evidence. The app fetches it
before run cleanup, verifies request identity plus structural and semantic v2
rules, persists only the server result, and rejects missing, partial, corrupt,
future or inconsistent results. A malformed v2 result is never treated as
legacy. Bundle manifests and compiled hashes include the new helper/module;
the existing `pubspec.yaml` directory asset declarations already cover both.

Verification performed:

```sh
python3 -m unittest -v test/scripts/network_probe_test.py
python3 -m py_compile lib/assets/scripts/lib/network_probe.py
bash -n lib/assets/scripts/install_wireguard.sh lib/assets/scripts/modules/10_install_pkgs.sh lib/assets/scripts/modules/15_network_probe.sh
fvm flutter test --no-pub test/features/install/application/install_controller_test.dart test/features/install/data/provisioner/config_env_writer_test.dart test/features/install/data/provisioner/network_result_parser_test.dart test/features/install/data/provisioner/debian_provisioner_test.dart test/features/install/data/run_mappers_test.dart test/features/install/data/scripts/script_integrity_test.dart test/features/servers/data/network_mappers_test.dart test/features/servers/data/server_mappers_test.dart
fvm flutter analyze
```

Results: 5 Python probe tests and 78 Dart tests passed; Python compilation and
Bash syntax checks passed. Full Flutter analysis exited 0 with no errors or
warnings and the same 22 pre-existing `prefer_initializing_formals` info
diagnostics. `./scripts/test-shell.sh` stopped at its prerequisite check because
the active Bash is 3.2 and Bash 4+ is required; BATS tests did not start. No
live namespace/netfilter server test, client/leak test, native build or full
suite was run. T3 does not render IPv6 profiles or install permanent IPv6
firewall/lifecycle rules: those remain T4 and T5. Peer v2 mutation stays gated
until T6. Next task is T4 only.

## T4 checkpoint

New v2 installations now render the server and first client exclusively from
the authoritative `network-result.json`. Server slot 1 and peer slot 2 receive
matching IPv4/IPv6 addresses; the client has `/32`, `/128` and both default
routes, while the server peer has only its `/32` and `/128`. Routed uses the
verified effective prefix and blocked uses the persistent ULA. Endpoint
(IPv4, DNS or bracketed IPv6), mixed DNS and MTU are validated and persisted
in the root-only server manifest; blocked mode requires at least one IPv4 DNS
resolver. No NAT66, proxy NDP, NAT64 or permanent IPv6 firewall work was added.

The shared fail-closed Python renderer is integrity-checked in both install and
peer asset bundles, installed under `/etc/wireguard/fav/lib` before use, and is
therefore independent of the temporary run directory for T6. Partial, corrupt,
future, identity/revision/network mismatched data is rejected. Existing v2
configuration is not rewritten: upgrade remains T8. The unversioned legacy
branches are unchanged, and peer v2 add/revoke remains blocked until T6.

Verification: 10 Python tests passed across probe/renderer; targeted Dart
integrity, peer-source/runner/controller and script-editor regression tests
passed; Python compilation, Bash syntax, formatting, full Flutter analysis and
`git diff --check` passed. Analysis retained only the 22 pre-existing
`prefer_initializing_formals` info diagnostics. `./scripts/test-shell.sh`
stopped at its prerequisite check: active Bash 3.2, Bash 4+ required; BATS did
not start. No live server/client, leak, native build or full Flutter suite was
run. Next task: T5 only.

## T5 checkpoint

New v2 installations install a deny-first, manifest-backed firewall guard
before forwarding changes. Per-interface IPv4/IPv6 chains enforce source
validation, peer isolation, stateful return traffic and denial of new
WAN-to-peer flows. IPv4 retains subnet/WAN-scoped masquerading. Routed IPv6
uses persisted WAN6 without NAT66, permits ICMPv6 errors including Packet Too
Big, enables forwarding and preserves WAN RA reception. Blocked mode explicitly
rejects forwarded tunnel IPv6 even if host forwarding was already enabled;
tunnel ICMPv6 remains usable while other host services are denied by default.

The persistent helper records exact owned rules and original/applied sysctls in
the root-only v2 manifest. It validates schema, state, identity, interface/path,
permissions, ownership and resource shapes; manifest argv are compared with
regenerated known operations and never executed directly. Reconciliation is
idempotent, rolls back partial changes, and wg-quick hooks restore rules after
reboot without duplicates. Teardown uses persisted WANs/resources, restores
unchanged sysctls with cross-installation reference checks, and removes only
FAV-owned resources. Install and teardown take global then interface locks.
Legacy behavior remains separate. Peer v2 stays gated until T6; migration stays
deferred to T8.

Verification: 17 Python tests and 28 Dart tests passed; Python compilation,
Bash syntax, formatter and bundle/peer asset integrity passed. Full Flutter
analysis completed with the same 22 pre-existing `prefer_initializing_formals`
info diagnostics and exit 1, with no errors or warnings. `./scripts/test-shell.sh`
stopped at its prerequisite check because active Bash is 3.2 and Bash 4+ is
required; BATS did not start and the wrapper was unchanged. No live
netfilter/WireGuard server, reboot, UFW/Docker interaction, client leak, native
build or complete Flutter suite was run. The commit SHA is recorded in the
external handoff files after commit creation. Next task: T6 only.

## T6 checkpoint

Peer add/revoke v2 now use a separate manifest-authoritative protocol under the
existing per-interface lock. The app sends only installation/operation identity,
interface and label or public key; subnet, mode, WAN, endpoint, DNS and MTU come
only from the validated root-owned server manifest. The legacy script branches
and custom-script path remain separate and unchanged.

The v2 manager validates manifest/config/runtime parity and secure paths, then
allocates the first free shared IPv4/IPv6 slot (server slot 1 reserved). Atomic
config/manifest replacements, a protected backup and `pendingOperation` provide
rollback and restart reconciliation. Add and revoke are idempotent by operation
ID; the app persists an outstanding ID in secure storage so a lost SSH response
or app restart cannot create a second allocation. Server peers receive only
`/32` and `/128`; returned client profiles contain both host addresses and both
default routes. Revocation stages owned secrets in the protected backup before
commit, deletes that backup only after commit and does not release the slot
early. Resource argv from JSON are shape-validated and never executed. T5
firewall policy is unchanged; migration remains T8.

Verification: 21 Python peer/renderer/firewall tests and 93 Dart peer/profile/
network/integrity tests passed in the final broad targeted run, including secure
operation-ID restart coverage.
Python compilation, Bash syntax, formatter, asset hashes and `git diff --check`
passed. Full Flutter analysis had no errors or warnings and only the 22 existing
`prefer_initializing_formals` info diagnostics. `./scripts/test-shell.sh`
stopped exactly at its prerequisite check: active Bash 3.2, Bash 4+ required;
BATS did not start and the wrapper was not changed. No live WireGuard server,
concurrent process/netfilter integration, client leak, native build or complete
Flutter suite was run. Next task: T7 only.

## Current product-scope correction

FAV is not released and has no legacy installation population. Compatibility,
migration and upgrade of old installations are therefore out of scope and must
not be counted as a remaining task. The former T8 migration task is removed.
Remaining work is T7 UI, T8 documentation/locales and T9 integration/release.
Historical checkpoint notes above describe implementation chronology only and
do not reinstate legacy support requirements.

## T7 checkpoint

T7 completed the minimal v2 UI without adding an IPv6 mode selector, bypass,
legacy migration or extra wizard. Server details identify the effective routed
or blocked mode. Profile and peer details keep the client-limit warning visible
and separately report server verification, export completed in the current UI
session and a user-declared import; neither a declaration nor the existing live
handshake banner is presented as technical client verification.

Client instructions now select Android, iOS/iPadOS, macOS, Windows or Linux as
the destination independently of the platform running FAV. Android includes
the external always-on VPN and block-without-VPN steps with an explicit
validation caveat. Other platforms state that no portable kill switch has been
verified and direct the user to validate client/OS protection separately. The
English and Italian base copy is complete; the other eight ARBs retain key
parity with English fallback copy pending the planned T8 language pass.

Verification: 54 profile, peer, server and ARB-parity widget/tests passed;
`fvm flutter gen-l10n` and the full formatter passed. Full Flutter analysis had
no errors or warnings and only the 22 existing `prefer_initializing_formals`
info diagnostics. `git diff --check` passed. No shell files changed, so BATS
was not retried in the known Bash 3.2 environment (the unchanged wrapper
requires Bash 4+). No live client/server, leak, accessibility-device, native
build or complete Flutter suite was run. Next task: T8 documentation and full
language review only.

## T8 checkpoint

T8 aligned the README, user/security/testing/releasing guides, provisioner
reference and all localized getting-started/FAQ help with the v2 automatic
routed/blocked policy. They distinguish server verification, profile generation
or export, declared import and actually verified client behaviour. They state
that no bypass exists, routed mode requires provider-delegated `/64` and
return-path evidence, and blocked mode captures then rejects tunnel IPv6. A
profile, handshake or declared import is not a permanent kill switch and does
not protect traffic after the VPN stops. Android's external always-on/blocking
settings are documented as requiring target-device validation; other platforms
have no FAV-verified portable kill-switch claim.

The T7 strings were translated in all ten shipped locales. ARB parity and help
asset tests passed, l10n was regenerated, and full analysis had only the
existing 22 `prefer_initializing_formals` info diagnostics. No BATS, live
server/client, leak, native build or external client-protection test was run.
T8 is complete; T9 integration and release validation is next.
