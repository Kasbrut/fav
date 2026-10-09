<!-- Thanks for contributing to FAV! Please fill in the sections below. -->

## What & why

<!-- What does this change do, and why? Link any related issue. -->

## Quality gate

- [ ] `fvm dart format .` — formatted
- [ ] `fvm flutter analyze` — clean
- [ ] `fvm flutter test` — green
- [ ] `bats test/scripts/*.bats` — green (if shell scripts changed)
- [ ] Tests added/updated for the change (happy path + error path)

## Conventions

- [ ] User-facing strings go through the ARB files (no inlined literals)
- [ ] Code, comments and commit messages are in English
- [ ] No secrets in code, logs, tests, or fixtures

## Security

- [ ] This change does **not** touch SSH, credentials, host keys, secret
      storage, the bundled installer scripts, or the anti-lockout/hardening flow
- [ ] …or it does, and the security implications are described below

<!-- If security-sensitive: describe the implications and how you verified them.
     If you changed a bundled script, confirm the script-integrity hashes were
     refreshed. -->
