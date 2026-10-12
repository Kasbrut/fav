Security and reliability fixes:

- Fixed SSH hardening with cloud-init while rejecting unsafe conditional overrides.
- Installation progress and results now distinguish verified hardening from incomplete or skipped hardening.
- Made SSH key rotation recoverable after interruptions and installed firewall protections before enabling forwarding.
- Tightened encrypted backup validation and resource limits.
- Pinned CI actions to immutable commits and restricted signing-secret exposure.

Validated on a Pixel 8a and Debian 13 VPS, including reboot recovery and VPN connectivity.

Android APKs, the Play Store AAB, Linux packages and checksums are attached when the release workflow completes. Google Play and sideloaded APKs use different signing keys: export a FAV backup before switching channels.
