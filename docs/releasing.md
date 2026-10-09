# Release and publication checklist

## Audit scope

Review these areas before the first public import and before releases touching
them. Passing unit tests is not a substitute for native or disposable-server
testing.

- Code: validation, shell escaping, SSH host-key verification, key-only checks,
  password lifetime, retries/timeouts, failure cleanup, peer add/revoke and
  hardening/teardown ordering.
- Secrets: tracked files, signing configuration, fixtures, logs, exported
  profiles, local database encryption, reset and recovery behaviour.
- Server scripts: fresh installation, rerun, custom SSH/WireGuard ports,
  IPv4 `/24` and IPv6 `/64` addressing, automatic routed/blocked selection,
  reboot persistence, fail2ban and teardown.
- Assets: bundled-script hashes, locale/placeholder parity, help topics,
  icons and native permissions/entitlements.
- Builds: the `.fvmrc` pin, locked dependencies, Java/Gradle/Kotlin compatibility,
  five native targets, signing and artifact names.
- Documentation: English contributor material, accurate user-facing translations,
  valid local links, current repository URLs, setup from a fresh clone,
  security boundaries, supported behaviour and known limitations.
- Repository: license and exception, contribution/security policies, issue
  templates, minimal CI permissions, ignored local files and line endings.

## Prepare the source release

Review the exact source snapshot intended for publication. Check `git status
--short`, `git diff --check` and `git ls-files`: all intended files must be
tracked, and credentials, developer signing IDs, local configuration and build
output must be excluded. Scan the snapshot for secrets, then verify the quality
gate from a fresh checkout. Do not publish a source snapshot with uncommitted
fixes or unverified release artifacts.

## Repository settings

- Enable Issues and **private vulnerability reporting**. Confirm that the
  Security policy link works; the published security email is the fallback.
- Enable Actions with read-only default token permissions. Workflows request
  write access only for publishing release artifacts.
- Require CI and native build checks for main, and configure branch protection
  or a ruleset. Do not require a status until it has run in the repository.
- Review Dependabot/security alerts and repository metadata. Check links in
  the app's report and donation screens before each release.
- Configure the four Android signing secrets from [building.md](building.md).
  Keep the keystore backup outside Git. Test with a manual release workflow
  run before pushing the first release tag.

## Binary release

1. Run formatting, analysis, Dart/widget tests, BATS, and all native build jobs.
2. Follow the disposable-server matrix in [testing.md](testing.md), including
   custom ports, routed and blocked IPv6, client route/DNS checks, external
   client protection, hardening, recovery and teardown. Do not claim a kill
   switch or stopped-VPN protection from a profile, handshake or import alone.
3. Smoke-test on actual Android and Apple devices; test iPad sharing and macOS
   Keychain/file access with a properly signed app. Test Linux keyring access
   and Windows file/share behaviour if distributing desktop builds.
4. Update `pubspec.yaml` version/build number. A prerelease should use a suffix
   such as `1.0.0-beta.1+1`; the matching tag is `v1.0.0-beta.1` and is marked
   as a prerelease automatically.
5. Tag the exact reviewed commit. The release workflow verifies the version,
   reruns the quality gate, signs Android APKs and the Play Store AAB, builds
   Linux x64 AppImage/DEB packages, hashes them and publishes them with the tag.
6. Verify a fresh install from the exact reviewed commit. Publish release notes
   describing the automatic IPv6 policy, client limits and known limitations.

App Store/Play publication, Apple certificates/notarization and store metadata
are separate release operations; the source repository does not configure
those accounts or publish to them automatically.

## Distribution order

1. Publish the reviewed source and signed non-iOS artifacts on GitHub.
2. Submit the Android App Bundle to Google Play and resolve review feedback.
3. Validate with TestFlight, then submit the iOS build to App Review.
4. Prepare F-Droid metadata and an isolated reproducible build, then propose
   inclusion in `fdroiddata`.

Publish the documentation and privacy-policy site through GitHub Pages before
store submissions so their metadata can reference a stable public URL.
