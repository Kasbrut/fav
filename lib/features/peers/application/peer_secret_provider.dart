import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/peers/data/hive_peer_repository.dart';
import 'package:fav/features/peers/data/secure_peer_secret_repository.dart';
import 'package:fav/features/peers/domain/peer.dart';
import 'package:fav/features/profile/data/client_profile_parser.dart';
import 'package:fav/features/profile/domain/client_profile.dart';
import 'package:fav/features/profile/domain/profile_contract_validator.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

/// A loaded peer with its parsed `.conf` and the raw text for QR/share.
typedef PeerProfileBundle = ({
  Peer peer,
  String rawConf,
  ClientProfile profile,
});

/// Loads the bundle for the peer identified by `peerId`:
/// the [Peer] row from the encrypted Hive box, the raw `.conf` from secure
/// storage and the parsed [ClientProfile]. Returns `null` if either the
/// peer row or the secret is missing.
final FutureProviderFamily<PeerProfileBundle?, String> peerProfileProvider =
    FutureProvider.autoDispose.family<PeerProfileBundle?, String>((
      ref,
      peerId,
    ) async {
      final peerRepository = ref.watch(peerRepositoryProvider);
      final peer = await peerRepository.getById(peerId);
      if (peer == null) {
        return null;
      }
      final raw = await ref.watch(peerSecretRepositoryProvider).read(peerId);
      if (raw == null) {
        return null;
      }
      final server = await ref
          .watch(serverRepositoryProvider)
          .getById(peer.serverId);
      final installation = server?.installation;
      final network = installation?.network;
      if (network != null && network.status != NetworkMetadataStatus.legacy) {
        if (!network.isStructurallyValidV2) {
          throw AppException(
            ErrorCode.scriptInvalid,
            detail:
                'profile export blocked by ${network.status.name} '
                'network metadata',
          );
        }
        final profile = await const ClientProfileParser().parse(
          raw,
          requireV2: true,
          ipv6Mode: network.ipv6Mode,
        );
        final problem = profileV2Problem(
          profile: profile,
          network: network,
          expectedIpv4Address: peer.ipv4Address,
          expectedIpv6Address: peer.ipv6Address,
          expectedClientPublicKey: peer.publicKey,
          expectedServerPublicKey: installation?.serverPublicKey,
        );
        if (problem != null) {
          throw AppException(ErrorCode.scriptInvalid, detail: problem);
        }
        // Early v2 builds persisted the first peer without copying the IPv6
        // address already present in its secure profile. Repair only after the
        // complete profile has passed the v2 network/slot/key validation.
        final effectivePeer = peer.ipv6Address == null
            ? peer.copyWith(ipv6Address: profile.ipv6Address)
            : peer;
        if (effectivePeer != peer) {
          await peerRepository.save(effectivePeer);
        }
        return (peer: effectivePeer, rawConf: raw, profile: profile);
      }
      final profile = await const ClientProfileParser().parse(raw);
      return (peer: peer, rawConf: raw, profile: profile);
    });
