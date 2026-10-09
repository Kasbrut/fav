import 'package:fav/features/peers/domain/peer.dart';

/// Serializes [peer] to a storage map for the encrypted `peers` Hive box.
Map<String, Object?> peerToMap(Peer peer) {
  return {
    'id': peer.id,
    'serverId': peer.serverId,
    'label': peer.label,
    'address': peer.address,
    'ipv6Address': peer.ipv6Address,
    'publicKey': peer.publicKey,
    'createdAt': peer.createdAt.toIso8601String(),
  };
}

/// Reconstructs a [Peer] from a storage map.
Peer peerFromMap(Map<dynamic, dynamic> map) {
  return Peer(
    id: map['id'] as String,
    serverId: map['serverId'] as String,
    label: map['label'] as String,
    address: map['address'] as String,
    ipv6Address: map['ipv6Address'] as String?,
    publicKey: map['publicKey'] as String,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}
