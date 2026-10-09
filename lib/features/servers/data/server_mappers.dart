import 'package:fav/features/servers/data/network_mappers.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/domain/server_metadata.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';

/// Serializes [server] to a storage map.
///
/// `pinnedHostKey` is intentionally omitted — host key fingerprints live in
/// secure storage (spec §4.2). Login passwords are never part of a [Server].
Map<String, Object?> serverToMap(Server server) {
  return {
    'id': server.id,
    'label': server.label,
    'host': server.host,
    'sshPort': server.sshPort,
    'username': server.username,
    'sshKeyId': server.sshKeyId,
    'metadata': server.metadata == null
        ? null
        : _metadataToMap(server.metadata!),
    'installation': server.installation == null
        ? null
        : _installationToMap(server.installation!),
    'createdAt': server.createdAt.toIso8601String(),
    'lastSeenAt': server.lastSeenAt?.toIso8601String(),
    'userAuthorizedKeys': server.userAuthorizedKeys,
  };
}

/// Reconstructs a [Server] from a storage map.
Server serverFromMap(Map<dynamic, dynamic> map) {
  final metadata = map['metadata'];
  final installation = map['installation'];
  final lastSeenAt = map['lastSeenAt'];
  final userAuthorizedKeys = map['userAuthorizedKeys'];
  return Server(
    id: map['id'] as String,
    label: map['label'] as String,
    host: map['host'] as String,
    sshPort: map['sshPort'] as int,
    username: map['username'] as String,
    sshKeyId: map['sshKeyId'] as String?,
    metadata: metadata == null
        ? null
        : _metadataFromMap(metadata as Map<dynamic, dynamic>),
    installation: installation == null
        ? null
        : _installationFromMap(installation as Map<dynamic, dynamic>),
    createdAt: DateTime.parse(map['createdAt'] as String),
    lastSeenAt: lastSeenAt == null
        ? null
        : DateTime.parse(lastSeenAt as String),
    // Absent for records written before this feature shipped — default to [].
    userAuthorizedKeys: userAuthorizedKeys == null
        ? const []
        : (userAuthorizedKeys as List<dynamic>).cast<String>(),
  );
}

Map<String, Object?> _metadataToMap(ServerMetadata metadata) {
  return {
    'osId': metadata.osId,
    'osVersion': metadata.osVersion,
    'prettyName': metadata.prettyName,
    'kernelVersion': metadata.kernelVersion,
    'architecture': metadata.architecture,
    'hostname': metadata.hostname,
    'totalMemoryMb': metadata.totalMemoryMb,
    'cpuCount': metadata.cpuCount,
    'publicIp': metadata.publicIp,
    'networkInterfaces': metadata.networkInterfaces,
    'probedAt': metadata.probedAt.toIso8601String(),
  };
}

ServerMetadata _metadataFromMap(Map<dynamic, dynamic> map) {
  return ServerMetadata(
    osId: map['osId'] as String,
    osVersion: map['osVersion'] as String,
    prettyName: map['prettyName'] as String,
    kernelVersion: map['kernelVersion'] as String,
    architecture: map['architecture'] as String,
    hostname: map['hostname'] as String,
    totalMemoryMb: map['totalMemoryMb'] as int,
    cpuCount: map['cpuCount'] as int,
    publicIp: map['publicIp'] as String,
    networkInterfaces: (map['networkInterfaces'] as List<dynamic>)
        .cast<String>(),
    probedAt: DateTime.parse(map['probedAt'] as String),
  );
}

Map<String, Object?> _installationToMap(WireguardInstallation installation) {
  return {
    'interfaceName': installation.interfaceName,
    'listenPort': installation.listenPort,
    'vpnSubnet': installation.vpnSubnet,
    'serverPublicKey': installation.serverPublicKey,
    'peers': installation.peers.map(_peerToMap).toList(),
    'hardeningApplied': installation.hardeningApplied,
    'rootSshDisabled': installation.rootSshDisabled,
    'installedAt': installation.installedAt.toIso8601String(),
    'portReachability': installation.portReachability.name,
    'portCheckedAt': installation.portCheckedAt?.toIso8601String(),
    'publicEndpoint': installation.publicEndpoint,
    'network': installation.network == null
        ? null
        : networkConfigurationToMap(installation.network!),
  };
}

WireguardInstallation _installationFromMap(Map<dynamic, dynamic> map) {
  final peers = map['peers'] as List<dynamic>;
  return WireguardInstallation(
    interfaceName: map['interfaceName'] as String,
    listenPort: map['listenPort'] as int,
    vpnSubnet: map['vpnSubnet'] as String,
    serverPublicKey: map['serverPublicKey'] as String,
    peers: peers
        .map((peer) => _peerFromMap(peer as Map<dynamic, dynamic>))
        .toList(),
    hardeningApplied: map['hardeningApplied'] as bool,
    // Legacy records (pre root-SSH tracking) read as "not disabled".
    rootSshDisabled: map['rootSshDisabled'] as bool? ?? false,
    installedAt: DateTime.parse(map['installedAt'] as String),
    portReachability: WireguardPortReachability.values.firstWhere(
      (value) => value.name == map['portReachability'],
      orElse: () => WireguardPortReachability.unknown,
    ),
    portCheckedAt: map['portCheckedAt'] == null
        ? null
        : DateTime.parse(map['portCheckedAt'] as String),
    publicEndpoint: map['publicEndpoint'] as String?,
    network: map['network'] == null
        ? null
        : networkConfigurationFromMap(map['network']),
  );
}

Map<String, Object?> _peerToMap(PeerSummary peer) {
  return {
    'publicKey': peer.publicKey,
    'allowedIp': peer.allowedIp,
    'ipv6Address': peer.ipv6Address,
    'label': peer.label,
  };
}

PeerSummary _peerFromMap(Map<dynamic, dynamic> map) {
  return PeerSummary(
    publicKey: map['publicKey'] as String,
    allowedIp: map['allowedIp'] as String,
    ipv6Address: map['ipv6Address'] as String?,
    label: map['label'] as String?,
  );
}
