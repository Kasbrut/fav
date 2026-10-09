import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// Application-layer read seam returning the peers registered for a server,
/// oldest first.
///
/// Lets infrastructure that is not part of the peers feature — notably the
/// router's legacy `/servers/:id/profile` redirect — query peers without
/// importing the peers data layer directly.
final FutureProviderFamily<List<Peer>, String> peersByServerProvider =
    FutureProvider.autoDispose.family<List<Peer>, String>(
      (ref, serverId) =>
          ref.watch(peerRepositoryProvider).getByServerId(serverId),
    );
