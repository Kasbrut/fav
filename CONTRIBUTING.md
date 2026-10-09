# Contributing to FAV

Thanks for your interest in contributing! This document covers how to set up the
project, the quality bar for changes, and the conventions the codebase follows.

By contributing, you agree that your contributions are licensed under the
project's [GPL-3.0](LICENSE) license, together with the
[App Store exception](LICENSE-EXCEPTION.md) (an additional permission under
GPLv3 §7).

## Prerequisites & setup

See the [README](README.md) for the full environment setup (FVM, Android
Studio/Xcode, emulators). In short:

```bash
fvm install            # install the pinned Flutter version (.fvmrc)
fvm flutter pub get --enforce-lockfile
fvm flutter gen-l10n
fvm flutter doctor     # verify the toolchain
```

Always run Flutter/Dart through **FVM** (`fvm flutter ...`, `fvm dart ...`); the
bare `flutter` is not assumed to be on `PATH`.

Platform prerequisites and signing are documented in [docs/building.md](docs/building.md).
When deliberately updating dependencies, use `fvm flutter pub get` and commit
the reviewed `pubspec.lock` changes. Do not upgrade dependencies opportunistically.

## Development loop

Use the helper scripts, each in its own terminal:

```bash
./scripts/dev-ios.sh       # iOS Simulator
./scripts/dev-android.sh   # Android emulator
```

## Quality gate (run before opening a PR)

```bash
fvm dart format .                  # formatting
fvm flutter analyze                # static analysis (must be clean)
fvm flutter test                   # unit + widget tests
./scripts/test-shell.sh             # Bash 4+, BATS; see docs/testing.md
```

All of the above must pass. New behaviour needs tests (happy path + error
path). Aim to keep domain and provisioner code well covered.

## Conventions

- **Architecture**: layered, feature-first. Dependencies point inward only
  (`presentation → application → domain ← data`); the domain layer never imports
  Flutter. State management is Riverpod; routing is centralized with go_router.
- **Localization**: every user-facing string goes through the i18n layer (ARB
  files in `lib/l10n/`), never inlined. The base/template ARB is English
  (`app_en.arb`); the app ships **10 locales** — en, it, de, es, fr, pt, ru, tr,
  uk, zh. Add every new key to **all 10** ARB files. The non-English locales are
  machine-translated, so native-speaker corrections are especially welcome.
- **English in code**: all identifiers, comments, log messages, commit messages,
  branch names and PR descriptions are in English.
- **Input validation & errors**: validate inputs (regexes/ranges); map failures
  to the project's error catalogue with a human message plus expandable
  technical detail.
- **Scope**: keep changes focused. Avoid adding dependencies or abstractions
  beyond the task; prefer editing existing files over creating new ones.

## Security-sensitive changes

If your change touches SSH, credential handling, host keys, secret storage, the
bundled installer scripts, or the anti-lockout/hardening flow, please call this
out in the PR description and describe the security implications. Such changes
get extra scrutiny against the threat model in [SECURITY.md](SECURITY.md). Note
that the bundled scripts are integrity-checked: if you change one, refresh the
hashes (the `script_integrity` test prints the per-file and canonical bundle hashes).

## Opening a pull request

1. Fork and create a feature branch.
2. Make your change with tests; run the full quality gate.
3. Write a clear PR description (what, why, and any security implications).
4. Be ready to iterate on review feedback.

Found a security vulnerability? Do **not** open a public issue — see
[SECURITY.md](SECURITY.md) for private reporting.
