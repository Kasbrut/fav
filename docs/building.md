# Building and signing

Use the Flutter SDK pinned in `.fvmrc` through FVM. Commit `pubspec.lock` and
use `fvm flutter pub get --enforce-lockfile` for reproducible dependency
resolution. Run `fvm flutter gen-l10n` after editing ARB files; generated Dart
localizations are intentionally ignored by Git. Internet access is required
for the first SDK, dependency and native build-tool downloads.

## Platform matrix

| Target | Build host | Prerequisites | Verification artifact |
| --- | --- | --- | --- |
| Android API 24+ | macOS, Linux, Windows | JDK 17, Android SDK platform 37, platform-tools, SDK licenses, Flutter-selected NDK | `build/app/outputs/flutter-apk/` |
| iOS 17+ | macOS | Xcode, command-line tools, iOS SDK, CocoaPods | `build/ios/iphoneos/Runner.app` (unsigned) |
| macOS 12+ | macOS | Xcode, command-line tools, CocoaPods, signing team for running | `build/macos/Build/Products/Release/FAV.app` |
| Linux | Linux | Clang, CMake, Ninja, pkg-config, GTK 3 and libsecret development packages | `build/linux/<arch>/release/bundle/` |
| Windows | Windows | Visual Studio with Desktop development with C++, Windows SDK | `build/windows/<arch>/runner/Release/` |

The pinned Flutter SDK's [deployment support matrix](https://docs.flutter.dev/reference/supported-platforms)
starts at macOS 12, and the CocoaPods and Xcode deployment targets are aligned
to that minimum.

Android and iOS are the primary targets. macOS has also been exercised
end-to-end on native hardware. Linux has received a native Ubuntu 24.04 smoke
test, and Windows has received a native Windows 11 Pro smoke test. Broader
desktop coverage remains. Linux requires a running Secret
Service keyring (for example GNOME Keyring or KWallet with Secret Service);
app lock is unavailable because `local_auth` has no Linux implementation.
Distribute the entire Linux bundle or Windows Release directory, not just the
executable. Web and cross-compilation are unsupported.

For Ubuntu build hosts:

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev libsecret-1-dev
```

After building the Linux release bundle, create an AppImage, a Debian package
and their checksums with:

```bash
./scripts/package-linux.sh
```

The script downloads checksum-pinned AppImage packaging tools. Both packages
were install/start smoke-tested on Ubuntu 24.04 x64.

After building the Windows release bundle, install Inno Setup 6 and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\package-windows.ps1
```

This creates a per-user installer, a portable ZIP and a checksum manifest. The
installer's install, Start menu launch and uninstall paths were smoke-tested
on Windows 11 Pro x64. Public installers still require code signing.

Run `fvm flutter doctor -v` and resolve toolchain errors before building.
The Bash helpers require Git Bash on Windows; PowerShell users can run
`fvm flutter build windows --release` or the corresponding Android command.

## Android

The project uses Java 17, Gradle/AGP versions pinned in `android/`, and the
external Kotlin plugin with `android.builtInKotlin=false` and
`android.newDsl=false` for compatibility with the current dependency set.
Keep these settings together when migrating AGP or Kotlin.

### Signing

Follow the [Flutter Android signing guide](https://docs.flutter.dev/deployment/android#sign-the-app)
to create and securely back up a release keystore. Create the ignored
`android/key.properties` file:

```properties
storeFile=/absolute/path/to/fav-release.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=YOUR_KEY_ALIAS
keyPassword=YOUR_KEY_PASSWORD
```

Use an absolute path; escape Windows backslashes as `\\` in properties files.
Do not commit this file or the keystore. Keep the same key for future sideload
updates. Changing the key normally requires uninstalling the old app, which
can destroy access to its local credentials. Google Play has a separate app
signing/upload-key workflow; plan it before distributing your first build.

Equivalent environment variables are `FAV_KEYSTORE_PATH`, `FAV_STORE_PASSWORD`,
`FAV_KEY_ALIAS` and `FAV_KEY_PASSWORD` (they override the properties file).
Release tasks fail when signing is absent. For personal testing only:

```bash
FAV_ALLOW_DEBUG_SIGNING=true ./scripts/build-android.sh
```

Never distribute debug-signed builds. Debug runs (`fvm flutter run`) need no
release key. Build commands:

```bash
./scripts/build-android.sh           # three per-ABI APKs plus universal APK
./scripts/build-android.sh --bundle  # build/app/outputs/bundle/release/app-release.aab
./scripts/build-android.sh --install # install universal APK on first connected device
```

`--bundle` and `--install` cannot be combined. The APK ABIs are armeabi-v7a,
arm64-v8a and x86_64. The universal APK supports all three.

### Release workflow secrets

Set these repository Actions secrets before running **Release artifacts**:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 encoding of the release keystore file |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Alias in that keystore |
| `ANDROID_KEY_PASSWORD` | Password for that alias |

A manual run builds and uploads signed Android APKs, the Play Store AAB and
Linux x64 packages without publishing. A `v*` tag publishes them with separate checksum
manifests; the tag must match the version before `+` in `pubspec.yaml` (for
example `v1.0.0`). Only the publish job has write access to repository
contents. Never expose signing secrets to pull-request workflows. Windows and
Apple artifacts stay excluded until their signing pipelines are configured.

### Emulator

Use Android Studio's Device Manager to create an emulator named `fav_dev`.
Choose an ARM64 image on Apple Silicon or an x86_64 image on Intel/AMD hosts.
Set `ANDROID_HOME` to your SDK directory, or put `adb` on PATH. The app minimum
is API 24; test both that minimum and a recent Android version before release.

## iOS

```bash
fvm flutter build ios --release --no-codesign
```

This verifies compilation, not installation or App Store eligibility. Open
`ios/Runner.xcworkspace` in Xcode, choose your team for Runner, and configure
signing/provisioning for a physical device or archive. For an App Store build,
use your distribution provisioning setup and `fvm flutter build ipa`.
Test Face ID/device unlock, profile sharing on both iPhone and iPad, and file
export on a real device. Personal signing-team IDs do not belong in commits.

## macOS

Open `macos/Runner.xcworkspace`, select Runner → Signing & Capabilities, enable
automatic signing and select your Apple Developer Team. Use an Apple Development
certificate for local runs, not “Sign to Run Locally”. The configured
`keychain-access-groups` entitlement requires team signing; an ad-hoc/unsigned
build cannot validate production Keychain access. A startup storage failure
shows the recovery screen.

```bash
fvm flutter build macos --release
```

Keep local team IDs out of `project.pbxproj` commits. CI compiles with signing
disabled and therefore does not verify launch, Keychain or distribution.
Public distribution also requires the appropriate Apple signing and
notarization/archive process; the helper does not perform those steps.
