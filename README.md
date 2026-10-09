# FAV

**Free and verifiable VPN provisioner** — turn a Debian/Ubuntu server into your
own WireGuard VPN endpoint, from your phone.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Status: beta](https://img.shields.io/badge/status-beta-orange.svg)

> ⚠️ **Early-release software — use a dedicated server.** FAV changes remote
> **SSH, firewall and network** configuration, and can disable root or password
> login. Use it only on a server dedicated to FAV and WireGuard; do not install
> it on a host running other production services or workloads you cannot afford
> to disrupt. Keep an out-of-band recovery path (e.g. your provider's console)
> available at all times.

FAV is a cross-platform Flutter app that provisions a fresh Debian/Ubuntu
server into a working WireGuard VPN over SSH. You give it an address, a username
and a password; it runs a modular installer on the server, tracks progress, and
then helps you manage clients and watch the VPN's live state — all from a phone.

> **Note**: WireGuard is a registered trademark of Jason A. Donenfeld. FAV is
> an independent project and is not affiliated with or endorsed by the WireGuard
> project. "WireGuard" is used here only to describe the protocol FAV sets up.

## What it does

- **Provision over SSH** — connects to a Debian/Ubuntu server and runs a modular
  installer in **detached mode**, polling a JSON state file so progress survives
  connection loss, app kills and network switches.
- **Manage peers** — add and revoke VPN clients; share a client config via QR
  code or file.
- **Live monitoring** — see peer connection state and a connection-history
  timeline.
- **Remove cleanly** — when you delete a server you can optionally tear down what
  FAV configured (WireGuard services/configs, the monitor agent, firewall
  rules, the forwarding drop-in and its fail2ban jail) and re-open SSH access (undo hardening). An anti-lockout guard refuses
  to strip your last way in, and a failed remote step lets you retry or remove the
  server locally anyway.
- **SSH terminal** — open an interactive shell to a managed server straight from
  its detail screen, reusing the same host-key pinning and on-demand password
  prompt as every other operation.
- **Security-first** — host-key Trust-On-First-Use pinning, secrets kept in the
  OS keychain, an encrypted local database, an optional app lock behind the
  device's own unlock (biometrics or PIN), and an anti-lockout flow when
  hardening SSH. See [SECURITY.md](SECURITY.md).
- **Harden the whole server** — optional SSH hardening disables root login and
  password authentication (key login only) and adds brute-force protection
  (fail2ban). It applies to the management user for **any** login — the user FAV
  creates for a root login, or your existing user for a non-root sudoer login —
  not only when FAV creates a new account. It is **off by default**.
- **Keep your own access** — optionally upload your SSH public keys so hardening
  doesn't lock you out; you can also add a key later from the server's detail
  screen or use the built-in SSH terminal.
- **Learn as you go** — a built-in FAQ, glossary, firewall guide and per-error
  troubleshooting, plus Settings for theme, language, a sanitized diagnostic
  export and a full factory reset.
- **Recover on another device** — create a password-protected encrypted backup
  of managed servers, pinned identities, FAV SSH keys, peer profiles, custom
  scripts and transferable settings. Restore verifies each server online and
  can optionally rotate FAV's SSH keys or revoke every existing peer.

The UI ships in **10 languages** — English, Italian, German, Spanish, French,
Portuguese, Russian, Turkish, Ukrainian and Chinese (the non-English locales are
machine-translated and welcome native-speaker review; see
[CONTRIBUTING.md](CONTRIBUTING.md)).

## How it works

1. **Add a server** — enter its address, SSH username and password (the password
   is requested per operation and never stored).
2. **Verify the host key** — FAV shows the SSH fingerprint on first connect and
   pins it; any later mismatch is blocked.
3. **Provision** — FAV uploads and runs the installer in detached mode and polls
   progress, so it survives app kills and network changes.
4. **Add peers** — generate client configs and share them by QR code or file.
5. **Monitor** — watch peer connection state and a connection-history timeline.
6. **Remove (optional)** — when you're done, delete the server; you can optionally
   tear down the WireGuard, monitor, firewall and forwarding changes and re-open
   SSH, with an anti-lockout guard and a retry / remove-locally fallback.

## ⚠️ Disclaimer

FAV changes remote server configuration over SSH, including **SSH access** and
**firewall rules**, and can disable root login and password authentication.
It includes anti-lockout safeguards (verify-then-apply, `sshd -t` dry-run,
config backup, rollback), but you run it against your own servers **at your own
risk**. Always keep an out-of-band recovery path (e.g. your provider's console)
available, especially when hardening a server.

## Platforms

Primary targets are **Android (API 24+)** and **iOS (17+)**. The repository also includes
build targets for **macOS, Linux and Windows**. macOS has been exercised
end-to-end on native hardware, and the Linux desktop build has received a native
Ubuntu 24.04 smoke test. The Windows build has received a native Windows 11 Pro
smoke test. Web is intentionally unsupported: the app relies on an SSH client,
OS-keystore-backed secure storage and an encrypted local database that have no
meaningful browser equivalent.

> **macOS:** the build must be signed with your own Apple Developer Team (a free
> Personal Team is enough) for production Keychain access — see
> [macOS signing](docs/building.md#macos).

## Server requirements

Use a **dedicated Debian or Ubuntu server** with Linux kernel **5.6 or newer**,
`systemd`, Bash and APT, an Internet connection to its package repositories,
and an accessible SSH account with a password. A non-root account must be able
to use `sudo`. Keep your provider's recovery console available.

Allow your SSH TCP port and the WireGuard UDP port (default **51820**) in both
the provider firewall and any host firewall. FAV supports one managed
WireGuard installation per dedicated server.

New v2 profiles carry IPv4 and IPv6: each client receives `/32` and `/128`
addresses and both default routes (`0.0.0.0/0` and `::/0`). FAV selects this
automatically, without an IPv6 bypass option or a routed/blocked selector. It
uses **routed** IPv6 only when the provider has supplied an eligible delegated
`/64` and FAV has verified its return path with a configured external target.
Otherwise it uses a persistent ULA **blocked** fallback: IPv6 is still captured
by the tunnel and explicitly rejected by the server rather than silently sent
outside it. An IPv6 server endpoint or WAN address alone is not proof of
delegated IPv6 space. IPv4 Internet egress remains required.

This verifies the generated server configuration, not the destination device.
Exporting a profile, importing it, a user declaration, or a WireGuard handshake
does not prove the client installed the routes or remains protected when its
VPN stops. Configure and validate any client/OS kill switch separately; see the
[user guide](docs/user-guide.md#ipv6-policy-and-client-limits). FAV is a
provisioner, not a VPN client; import its profiles into a WireGuard client.

Read the [user guide](docs/user-guide.md) for setup, recovery, removal and
known limitations.

## Development setup

Install [FVM](https://fvm.app/) and the native toolchain for the target you want
to build. Flutter is pinned in `.fvmrc`; CI reads that same file.

```bash
git clone https://github.com/Kasbrut/fav.git
cd fav
fvm install
fvm flutter pub get --enforce-lockfile
fvm flutter gen-l10n
fvm flutter doctor
```

Use `fvm flutter run -d <device-id>` (`fvm flutter devices` lists devices), or
run the Bash helpers in a terminal:

```bash
./scripts/dev-ios.sh       # macOS + bootable iOS Simulator
./scripts/dev-android.sh   # Android emulator named fav_dev
./scripts/dev-desktop.sh   # native desktop target
```

Hotkeys: `r` reloads, `R` restarts and `q` quits. The Android helper uses
`ANDROID_HOME` / `ANDROID_SDK_ROOT`, then the usual macOS SDK path or `adb`
on PATH. Windows users can use Git Bash for the helpers or invoke FVM directly.

## Building release artifacts

```bash
./scripts/build.sh android       # a single target
./scripts/build.sh macos ios     # multiple targets on macOS
./scripts/build.sh               # all targets buildable on this host
```

See [Building and signing](docs/building.md) for platform prerequisites,
Android signing, Apple signing, emulator setup and artifact paths. Android
release builds require a signing key; debug signing is an explicit opt-in for
local testing. iOS helper builds are unsigned and cannot be installed as-is.
macOS needs team signing to use the production Keychain configuration.
Linux maintainers can package the release bundle as AppImage and DEB with
`./scripts/package-linux.sh`. Windows maintainers can create an installer and
portable ZIP with `scripts/package-windows.ps1`; see the signing caveat in the
building guide.

Maintainers: follow [Release and publication checklist](docs/releasing.md)
before publishing the source or creating a release tag.

## Quality checks

```bash
fvm dart format --output=none --set-exit-if-changed .
fvm flutter analyze        # static analysis
fvm flutter test           # unit and widget tests
./scripts/test-shell.sh    # requires Bash 4+ and BATS; see docs/testing.md
```

## Architecture

Layered, feature-first. Each feature owns four layers and dependencies point
inward only (`presentation → application → domain ← data`); the domain layer
never imports Flutter. State management is Riverpod; routing is centralized with
go_router; SSH uses the pure-Dart `dartssh2`.

For an overview of the codebase and its security properties, see
[docs/architecture.md](docs/architecture.md) and
[docs/security-model.md](docs/security-model.md).

## Buy me a coffee ☕

FAV is free and open source, with no ads, tracking, or paid features. If it has
been useful to you and you feel like buying me a coffee, see
[DONATE.md](DONATE.md). It is entirely optional and changes nothing in the app.

A ⭐ on this repository also helps.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for setup, the
quality gate, and conventions. Please also read the
[Code of Conduct](CODE_OF_CONDUCT.md). For security issues, **do not** open a
public issue; follow [SECURITY.md](SECURITY.md).

## License

Copyright © 2026 Kasbrut. Licensed under the
[GNU General Public License v3.0](LICENSE), with an
[App Store exception](LICENSE-EXCEPTION.md) — an additional permission under
GPLv3 §7 that allows distribution through app stores such as Apple's App Store
and Google Play.
