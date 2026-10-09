# Architecture

FAV is a Flutter application for provisioning and managing a WireGuard server
over SSH. The application targets Android and iOS first, and also carries
desktop platform projects for macOS, Linux and Windows.

## Project layout

The codebase is feature-first and layered. Within a feature, dependencies point
inward:

```
presentation -> application -> domain <- data
```

- `presentation` contains screens and widgets.
- `application` contains Riverpod controllers and orchestration of use cases.
- `domain` contains entities, value objects and repository interfaces; it does
  not depend on Flutter.
- `data` contains SSH, persistence, asset and repository implementations.

Shared concerns live under `lib/core/`: routing, persistence, cryptography,
error mapping, logging, theming and reusable widgets.

## Provisioning flow

The app connects to a Debian or Ubuntu server over SSH, uploads an
integrity-checked bundle of shell scripts, and starts the installer in detached
mode. The installer writes a JSON state file, an exit file and a log on the
server. The app polls those files, so it can show progress and recover a run
after a connection loss or app restart.

The installer is split into small numbered modules. It creates or uses a
management account, configures WireGuard and forwarding, installs optional
monitoring, and can apply optional SSH hardening. Peer creation and revocation,
monitoring and server teardown are separate SSH-driven operations.

## Local data

FAV stores server metadata, runs, peer metadata, monitoring events and editable
script overrides in encrypted Hive boxes. The encryption key is kept in the
operating system's secure storage. SSH private keys and generated client
profiles are also stored through secure-storage-backed repositories rather than
in the normal database.

Server login passwords are requested for the operation that needs them and are
not saved as application data. A new management-user password can temporarily
exist in the remote install parameters while provisioning is in progress; the
installer removes those parameters immediately after reading them.

## Tests and automation

The `test/` tree contains Dart unit and widget tests. The installer and peer
shell scripts are covered by BATS tests in `test/scripts/`. GitHub Actions runs
formatting, static analysis, Dart tests and the BATS suite. See
[testing.md](testing.md) for the local verification workflow.

## Installation stages

| Module | Responsibility |
| --- | --- |
| 00 probe | Reject unsupported distribution IDs or kernels |
| 10 install packages | Install WireGuard tools, iptables and sudo through APT |
| 20 create user | Optional management account, sudo membership and initial password |
| 25 / 26 deploy keys | App public key and optional user public keys |
| 30 generate keys | Server key and first-client keys |
| 40 write configuration | Back up existing config; write interface, first peer and firewall hooks |
| 50 / 60 networking | Enable IPv4 forwarding and runtime NAT/FORWARD rules |
| 70 / 80 services | Start WireGuard; optionally install/configure fail2ban |
| 90 / 99 completion | Check service/port health and generate the first profile |

`ConfigEnvWriter` renders escaped parameters; the contract is documented in
[the provisioner reference](../lib/features/install/data/provisioner/README.md).
Root/password SSH restrictions run afterwards through separate verified
sessions, not inside the detached account-creation module. Monitoring and
teardown also have separate application services.

The orchestrator serializes installer runs with a server lock, writes state
atomically and records its exit status. The app polls state/exit files with a
bounded retry budget. Post-install work can still fail after the detached
installer completes; controllers expose these outcomes separately.

## Persistence and ownership

| Store | Contents |
| --- | --- |
| `servers` | Addresses, usernames, metadata, installed options and key references |
| `runs` | Run IDs, progress, timestamps and recovery information |
| `peers` | Labels, addresses and public-key metadata |
| `monitoring_events` | Peer connection history with seven-day retention |
| `scripts` | User-edited overrides |
| `preferences` | Theme, language, app lock and recent error codes |
| Secure storage | Database encryption key, app SSH key seeds, host-key pins and client profiles |

Controllers own short-lived SSH connections or explicitly transfer them to a
polling/terminal controller. Passwords must not enter persisted entities,
provider state intended for long-term retention, command-line arguments or
logs. Teardown retries ask for a new password.

## Script integrity and portability

The installer/monitor/teardown bundle and peer scripts have separate SHA-256
baselines (`script_integrity.dart` and `peer_script_source.dart`). Refresh the
appropriate baseline after reviewing any script change; tests compare actual
asset bytes. `.gitattributes` forces LF on shell assets so Windows checkouts
produce the same hashes and executable scripts as Linux/macOS.

Keep platform-specific I/O behind injected services (SSH, secure storage,
sharing, device authentication). Tests use fakes; native plugin behaviour needs
platform smoke testing. `local_auth` does not implement Linux authentication,
and unsigned Apple builds cannot verify the configured Keychain entitlements.
