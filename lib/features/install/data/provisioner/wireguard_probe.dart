import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Detects whether a server already carries a WireGuard installation.
class WireguardProbe {
  /// Creates a [WireguardProbe].
  const WireguardProbe();

  /// Returns `true` when the connected server already has WireGuard set up.
  ///
  /// Detects any interface configuration under `/etc/wireguard`, not just the
  /// default one, so an install under a custom interface name is still found
  /// before a second installation overwrites it (spec §15, criterion 16).
  Future<bool> isWireguardInstalled(SshClient client) async {
    final result = await client.run(
      'ls /etc/wireguard/*.conf >/dev/null 2>&1 && echo WG-PRESENT',
    );
    return result.stdout.contains('WG-PRESENT');
  }
}

/// Provides the [WireguardProbe].
final Provider<WireguardProbe> wireguardProbeProvider =
    Provider<WireguardProbe>((ref) => const WireguardProbe());
