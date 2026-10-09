import 'package:fav/features/servers/domain/host_key_fingerprint.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory host-key mismatches detected during this app session.
///
/// Pins remain in secure storage and are never changed here. This registry
/// only lets every SSH entry point surface the same unresolved warning in the
/// server detail UI.
class HostKeyChangeRegistry extends Notifier<Map<String, HostKeyFingerprint>> {
  @override
  Map<String, HostKeyFingerprint> build() => const {};

  /// Records an untrusted replacement received from an SSH handshake.
  void record(HostKeyFingerprint fingerprint) {
    state = {...state, _key(fingerprint.host, fingerprint.port): fingerprint};
  }

  /// Clears a resolved mismatch after the replacement was authenticated.
  void clear(String host, int port) {
    final updated = Map<String, HostKeyFingerprint>.of(state)
      ..remove(_key(host, port));
    state = updated;
  }

  /// Returns the registry key shared by an SSH endpoint and its detail view.
  static String keyFor(String host, int port) => _key(host, port);

  static String _key(String host, int port) => '$host:$port';
}

/// Shared session registry for detected host-key changes.
final hostKeyChangeRegistryProvider =
    NotifierProvider<HostKeyChangeRegistry, Map<String, HostKeyFingerprint>>(
      HostKeyChangeRegistry.new,
    );
