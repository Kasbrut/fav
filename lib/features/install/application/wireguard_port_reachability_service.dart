import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:fav/core/utils/shell_quote.dart';
import 'package:fav/features/install/domain/ssh_client.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';

/// Checks whether a WireGuard UDP port is reachable from this device.
///
/// A random marker is sent over UDP while a temporary nftables rule on the
/// server counts only that marker. This tests the entire path, including a
/// cloud-provider firewall, without relying on an external service.
class WireguardPortReachabilityService {
  /// Creates the service.
  const WireguardPortReachabilityService({
    this.settleDelay = const Duration(milliseconds: 500),
  });

  /// Brief interval allowed for the datagram to reach the remote firewall.
  final Duration settleDelay;

  /// Returns [WireguardPortReachability.unknown] when the check itself cannot
  /// be performed; infrastructure failures must not be reported as a closed
  /// port.
  Future<WireguardPortReachability> check({
    required SshClient client,
    required String endpoint,
    required int port,
    bool useSudo = false,
    String? sudoPassword,
  }) async {
    final random = Random.secure();
    final marker = List<int>.generate(16, (_) => random.nextInt(256));
    final markerHex = marker
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final suffix = List<int>.generate(
      4,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final table = 'fav_port_probe_$suffix';

    try {
      final setup = await _run(
        client,
        'set -eu; '
        'nft add table inet $table; '
        "nft 'add chain inet $table input { type filter hook input "
        "priority -250; policy accept; }'; "
        'nft add rule inet $table input udp dport $port '
        '@th,64,128 0x$markerHex counter; '
        "printf 'FAV_PORT_PROBE_READY'",
        sudoPassword,
        useSudo: useSudo,
      );
      if (setup.exitCode != 0 ||
          !setup.stdout.contains('FAV_PORT_PROBE_READY')) {
        return WireguardPortReachability.unknown;
      }

      final addresses = await InternetAddress.lookup(
        _hostOnly(endpoint),
      ).timeout(const Duration(seconds: 4));
      if (addresses.isEmpty) return WireguardPortReachability.unknown;
      final address = addresses.firstWhere(
        (candidate) => candidate.type == InternetAddressType.IPv4,
        orElse: () => addresses.first,
      );
      final socket = await RawDatagramSocket.bind(
        address.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4,
        0,
      );
      try {
        socket.send(marker, address, port);
      } finally {
        socket.close();
      }
      await Future<void>.delayed(settleDelay);

      final result = await _run(
        client,
        'nft list table inet $table',
        sudoPassword,
        useSudo: useSudo,
      );
      if (result.exitCode != 0) return WireguardPortReachability.unknown;
      final packets = RegExp(
        'counter packets ([0-9]+)',
      ).firstMatch(result.stdout);
      if (packets == null) return WireguardPortReachability.unknown;
      return int.parse(packets.group(1)!) > 0
          ? WireguardPortReachability.reachable
          : WireguardPortReachability.blocked;
    } on Object {
      return WireguardPortReachability.unknown;
    } finally {
      try {
        await _run(
          client,
          'nft delete table inet $table 2>/dev/null || true',
          sudoPassword,
          useSudo: useSudo,
        );
      } on Object {
        // Best-effort cleanup of a uniquely named, non-blocking counter rule.
      }
    }
  }

  Future<SshCommandResult> _run(
    SshClient client,
    String command,
    String? sudoPassword, {
    bool useSudo = false,
  }) {
    if (!useSudo) return client.run(command);
    if (sudoPassword == null) {
      return client.run('sudo -n -- sh -c ${shellSingleQuote(command)}');
    }
    return client.run(
      "sudo -S -p '' -- sh -c ${shellSingleQuote(command)}",
      stdin: '$sudoPassword\n',
    );
  }

  String _hostOnly(String endpoint) {
    final trimmed = endpoint.trim();
    if (trimmed.startsWith('[')) {
      final close = trimmed.indexOf(']');
      if (close > 1) return trimmed.substring(1, close);
    }
    return trimmed;
  }
}
