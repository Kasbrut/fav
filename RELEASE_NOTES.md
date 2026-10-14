Backup restore reliability fix:

- Interrupted restores now roll back partial local data before startup migrations.
- Restore retry preserves requested SSH-key rotation and peer-revocation options.
- Recovery remains compatible with existing pending online restores.

Focused interruption and recovery tests cover the restored state.

Android APKs, the Play Store AAB, Linux packages and checksums are attached when the release workflow completes. Google Play and sideloaded APKs use different signing keys: export a FAV backup before switching channels.
