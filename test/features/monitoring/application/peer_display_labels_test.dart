import 'package:fav/features/monitoring/application/peer_display_labels_provider.dart';
import 'package:fav/features/peers/application/peers_controller.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/peers/domain/peer_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/static_peer_repository.dart';

class _FailingPeerRepository implements PeerRepository {
  @override
  Future<List<Peer>> getAll() async => throw StateError('boom');

  @override
  Future<Peer?> getById(String id) async => throw StateError('boom');

  @override
  Future<List<Peer>> getByServerId(String serverId) async =>
      throw StateError('boom');

  @override
  Future<void> save(Peer peer) async {}

  @override
  Future<void> delete(String id) async {}
}

/// Pumps the underlying `peersControllerProvider` AsyncNotifier so that
/// reading `peerDisplayLabelsProvider` returns its post-build value.
Future<void> _settlePeersController(
  ProviderContainer container,
  String serverId,
) async {
  try {
    await container.read(peersControllerProvider(serverId).future);
  } on Object {
    // Errored state — that's fine; the derived provider returns empty.
  }
}

Peer _peer({
  required String id,
  required String label,
  required String publicKey,
  String serverId = 'srv',
}) => Peer(
  id: id,
  serverId: serverId,
  label: label,
  address: '10.13.13.2/32',
  publicKey: publicKey,
  createdAt: DateTime.utc(2026),
);

void main() {
  group('peerDisplayLabel', () {
    test('returns the label when present and non-empty', () {
      expect(
        peerDisplayLabel('PUBKEY44CHARS', const {'PUBKEY44CHARS': 'Laptop'}),
        'Laptop',
      );
    });

    test('falls back to short pubkey when key is absent', () {
      expect(peerDisplayLabel('abcdefghijklmno', const {}), 'abcdefgh…');
    });

    test('falls back to short pubkey when label is empty', () {
      expect(
        peerDisplayLabel('abcdefghijklmno', const {'abcdefghijklmno': ''}),
        'abcdefgh…',
      );
    });

    test('returns the full key when length <= 12', () {
      expect(peerDisplayLabel('short', const {}), 'short');
      expect(peerDisplayLabel('twelve_chars', const {}), 'twelve_chars');
    });
  });

  group('isPubkeyFallback', () {
    test('true when label is missing', () {
      expect(isPubkeyFallback('k1', const {}), isTrue);
    });

    test('true when label is empty string', () {
      expect(isPubkeyFallback('k1', const {'k1': ''}), isTrue);
    });

    test('false when label is present and non-empty', () {
      expect(isPubkeyFallback('k1', const {'k1': 'Phone'}), isFalse);
    });
  });

  group('sortPeersByDisplay', () {
    test('labelled peers come before unlabelled', () {
      final result = sortPeersByDisplay(
        const ['unlabelledA', 'unlabelledB', 'k1', 'k2'],
        const {'k1': 'Beta', 'k2': 'Alpha'},
      );
      expect(result.take(2), ['k2', 'k1']); // Alpha, Beta
      expect(result.skip(2), ['unlabelledA', 'unlabelledB']);
    });

    test('labelled bucket is case-insensitive alphabetical', () {
      final result = sortPeersByDisplay(
        const ['a', 'b', 'c'],
        const {'a': 'banana', 'b': 'Apple', 'c': 'cherry'},
      );
      expect(result, ['b', 'a', 'c']);
    });

    test('uses raw pubkey as stable tie-breaker among unlabelled peers', () {
      final result = sortPeersByDisplay(
        const ['kZ', 'kA', 'kM'],
        const {},
      );
      expect(result, ['kA', 'kM', 'kZ']);
    });
  });

  group('peerDisplayLabelsProvider', () {
    test('returns the {pubkey: label} map when peers are loaded', () async {
      final repo = StaticPeerRepository([
        _peer(id: 'p1', label: 'Phone', publicKey: 'KEY_PHONE'),
        _peer(id: 'p2', label: 'Laptop', publicKey: 'KEY_LAPTOP'),
        _peer(
          id: 'p3',
          label: 'Other',
          publicKey: 'KEY_OTHER',
          serverId: 'other',
        ),
      ]);
      final container = ProviderContainer(
        overrides: [peerRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      // Keep both providers alive across the awaited tick.
      container.listen(peerDisplayLabelsProvider('srv'), (_, _) {});

      await _settlePeersController(container, 'srv');

      final map = container.read(peerDisplayLabelsProvider('srv'));
      expect(map, {'KEY_PHONE': 'Phone', 'KEY_LAPTOP': 'Laptop'});
    });

    test('returns an empty map in loading', () {
      final repo = StaticPeerRepository(const []);
      final container = ProviderContainer(
        overrides: [peerRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      // First read happens synchronously while the AsyncNotifier is still
      // in its loading state.
      expect(container.read(peerDisplayLabelsProvider('srv')), isEmpty);
    });

    test('returns an empty map when peers controller errors', () async {
      final failing = _FailingPeerRepository();
      final container = ProviderContainer(
        overrides: [peerRepositoryProvider.overrideWithValue(failing)],
      );
      addTearDown(container.dispose);
      container.listen(peerDisplayLabelsProvider('srv'), (_, _) {});

      await _settlePeersController(container, 'srv');

      expect(container.read(peerDisplayLabelsProvider('srv')), isEmpty);
    });
  });
}
