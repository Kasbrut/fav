# Provisioner — `config.env` reference

This directory holds the SSH provisioning logic. The key artifact it produces is
**`config.env`**: a small key/value file the app generates per run and uploads
next to `install_wireguard.sh`. The orchestrator sources it once, then deletes
it immediately.

`config.env` is generated in code by [`config_env_writer.dart`](config_env_writer.dart)
— this document describes its format and contract; it is **not** read from a
file at runtime.

## Security contract

`NEW_PASSWORD` is a **transient secret**: the app never persists it and the
installer never logs it. The generator must:

- Create the run directory mode `0700` and upload `config.env` mode `0600`, so
  the cleartext password is never group/world-readable on the server.
- Shell-escape every value: the orchestrator sources the file as bash, so each
  line is emitted as strict `KEY="value"` and every `"`, `\`, `$` and
  backtick inside a value is escaped; control characters are rejected (see `config_env_writer.dart`).

Booleans are the literal strings `"true"` / `"false"`. Values containing a space
or comma are double-quoted.

## Parameters

### Non-root user (`modules/20_create_user.sh`)

| Key | Meaning |
| --- | --- |
| `CREATE_USER` | Whether to create a non-root sudo user. When `false`, module 20 is skipped. |
| `NEW_USERNAME` | Username of the non-root user (required when `CREATE_USER=true`). |
| `NEW_PASSWORD` | Password for the new user (required when `CREATE_USER=true`). Transient secret. |

Root SSH is never disabled by a module: it happens **post-install**,
app-driven, by `AntiLockoutService` from a verified second session
(`sshd -T` effective-config check), and only when hardening is enabled.
Module 20 carries no inline disable path.

### SSH hardening (`modules/80_hardening.sh`)

| Key | Meaning |
| --- | --- |
| `ENABLE_HARDENING` | Whether to apply optional SSH hardening. Module 80 installs fail2ban (brute-force protection) only. Disabling root SSH **and** password authentication is done post-install, app-driven, against the management user — the created user for a root login, or the login user for a non-root sudoer — so hardening secures the whole server for any login. When `false`, module 80 is skipped. |

### WireGuard parameters

| Key | Meaning |
| --- | --- |
| `INTERFACE_NAME` | WireGuard interface name (e.g. `wg0`). |
| `SSH_PORT` | SSH TCP port to protect with fail2ban (default `22`). |
| `WG_PORT` | UDP port WireGuard listens on (e.g. `51820`). |
| `VPN_SUBNET` | Canonical IPv4 /24 network ending in `.0/24`; the server takes `.1`, the first client `.2` (e.g. `10.13.13.0/24`). |
| `MTU` | Interface MTU (e.g. `1420`). |
| `DNS` | DNS servers advertised to the client, comma-separated (e.g. `1.1.1.1, 1.0.0.1`). |
| `PUBLIC_ENDPOINT` | Public IP or hostname clients use to reach the server. The app defaults to the SSH host unless overridden. IPv6 literals are bracketed when writing profiles. |
| `VPN_IPV6_ULA_SUBNET` | Persistent canonical ULA `/64` created by the app for the v2 blocked fallback. |
| `VPN_IPV6_ROUTED_SUBNET` | Optional provider-delegated canonical `/64`, considered only with the required provider attestation and return-path probe. |
| `IPV6_PROBE_TARGET` | Optional controlled external IPv6 target used to verify the routed-prefix return path. It is not telemetry and an absent/inconclusive probe selects blocked mode. |

## IPv6 v2 selection and evidence

The v2 installer selects mode automatically; `config.env` never represents a
client-facing routed/blocked selector or IPv6 bypass. It accepts routed IPv6
only when the supplied delegated `/64`, provider attestation and correlated
probe reply establish the required evidence. A public IPv6 endpoint, WAN
address, default route, RA or on-link prefix is insufficient. With no usable
evidence it uses `VPN_IPV6_ULA_SUBNET`: client profiles still include `/128` and
`::/0`, while the server explicitly rejects forwarded tunnel IPv6. If local
IPv6 cannot support this fallback, installation must fail instead of emitting an
IPv4-only success profile.

`network-result.json` is the server-authoritative result used for profile and
firewall rendering. Its verification says nothing about routes after an import,
the client OS's kill switch, or traffic while the VPN is stopped. Export, a
declared import and a WireGuard handshake are separate, weaker facts and must
not be promoted to client-protection evidence.

### SSH keys

`SSH_PUBKEY` is the app-generated public key. `USER_AUTHORIZED_KEYS_B64` is a
base64-encoded newline-separated list of optional user public keys. Modules 25
and 26 deploy these to `NEW_USERNAME`, or root when it is empty. The parameter
file contains public keys, never the app SSH private key.

## Example

```sh
CREATE_USER="false"
NEW_USERNAME="deploy"
NEW_PASSWORD=""
ENABLE_HARDENING="false"
INTERFACE_NAME="wg0"
WG_PORT="51820"
VPN_SUBNET="10.13.13.0/24"
MTU="1420"
DNS="1.1.1.1, 1.0.0.1"
PUBLIC_ENDPOINT="vpn.example.com"
```
