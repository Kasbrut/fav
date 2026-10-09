# Testing

FAV changes remote SSH and network configuration. Run automated tests before a
change and perform end-to-end checks only on a dedicated disposable server with
an out-of-band recovery console available.

## Local quality gate

Install the Flutter version pinned in `.fvmrc`, then run:

```bash
fvm flutter pub get --enforce-lockfile
fvm flutter gen-l10n
fvm dart format --output=none --set-exit-if-changed .
fvm flutter analyze
fvm flutter test
./scripts/test-shell.sh
```

The shell suite requires **Bash 4+**, BATS and GNU-compatible utilities
(including `date`, `stat`, `base64` and `truncate`). On Debian/Ubuntu:

```bash
sudo apt-get install bash bats coreutils
```

macOS ships Bash 3.2, which cannot run the installer’s associative arrays. Use:

```bash
brew install bash bats coreutils
export PATH="$(brew --prefix)/bin:$(brew --prefix coreutils)/libexec/gnubin:$PATH"
./scripts/test-shell.sh
```

The tests replace privileged system commands with mocks and use temporary
folders; they do not provision the test host. Full platform behaviour still
requires disposable Linux servers. The wrapper fails early on an old Bash.

The Dart tests cover domain,
data and widget behaviour; the BATS suite covers the server-side installer,
peer and teardown scripts.

## End-to-end checks

Use a fresh supported Debian or Ubuntu server dedicated to this test. Before
starting, confirm that you can recover access through the provider console.

At minimum, verify the following manually:

1. Add the server and compare the displayed SSH host-key fingerprint through
   an independent trusted channel.
2. Provision WireGuard, add a peer, import or scan the generated profile, and
   confirm tunnel connectivity.
3. Reboot the server and confirm that WireGuard, forwarding and monitoring
   recover as expected.
4. If testing SSH hardening, verify a new key-only session before and after the
   change, while keeping console access available.
5. Exercise teardown on a throwaway server and confirm that the selected
   services and configuration are removed without losing the intended SSH
   access path.
6. Test both automatic IPv6 outcomes. For routed mode, use a provider-delegated
   `/64` and controlled external IPv6 target, then record return-path evidence.
   For blocked mode, verify the client receives `/32`, `/128` and both default
   routes, IPv4 works, and IPv6 Internet traffic is rejected through the
   tunnel. Do not treat a failed `curl -6` alone as a no-leak result: use packet
   capture and controlled endpoints.
7. On every distributed client platform, separately test the imported profile's
   routes/DNS, roaming and a stopped VPN. Record client/OS versions and any
   external kill-switch measure. A generated profile, declared import or
   handshake is not proof of client protection.

Never use production credentials, customer data or a server that hosts unrelated
services for these checks.

## Server regression matrix

Exercise maintained Debian and Ubuntu images with root and non-root sudo
logins. Include passwordless sudo where available, default/custom SSH ports,
default/custom WireGuard ports, the default and an alternate /24 pool,
IPv4/DNS/IPv6 public endpoints, hardening on/off and monitoring on/off.

Check interruption during upload, detached launch, polling and post-install
hardening. Verify recovery after app restart and a network switch. Force an
invalid password, host-key mismatch, unavailable package repository and failed
remote step; failures must not hang indefinitely or report success.

Test peer revocation, a reused address after revocation, two concurrent peer
requests, a full /24, and routed/blocked profiles imported into real WireGuard
clients. Include IPv4-only, IPv6-only and dual-stack client networks; test
server forwarding/firewall, DNS, PMTU, peer isolation and no direct client IPv6
fallback with controlled captures. Confirm reboot persistence and cleanup of
runtime firewall rules, and retain an independent SSH session/console throughout
hardening and teardown tests.

## Automation and limits

CI reads `.fvmrc`, checks locked dependencies, formatting, static analysis,
Dart/widget tests and Linux BATS, then compiles Android, iOS, macOS, Linux and
Windows. The release workflow repeats the quality gate before signing APKs.
Unsigned Apple CI builds prove compilation only. See [building.md](building.md)
for signing and runtime prerequisites.

Native builds require the appropriate SDKs and access to dependency registries.
Run the full CI and native smoke tests before tagging a release.
