import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/utils/ipv6.dart';
import 'package:fav/core/utils/validators.dart';
import 'package:fav/core/wireguard/wg_public_key.dart';
import 'package:fav/features/peers/domain/peer_add_envelope.dart';
import 'package:fav/features/profile/data/client_profile_parser.dart';
import 'package:fav/features/profile/domain/client_profile.dart';
import 'package:fav/features/servers/domain/network_configuration_validator.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';

/// Persisted facts that a v2 peer response must match.
class PeerAddEnvelopeExpectation {
  /// Creates an expectation for one idempotent peer operation.
  const PeerAddEnvelopeExpectation({
    required this.network,
    required this.operationId,
    required this.revision,
  });

  /// Effective installation metadata known before the operation.
  final NetworkConfiguration network;

  /// Operation identity sent to the server.
  final String operationId;

  /// Expected committed manifest revision in the response.
  final int revision;
}

/// Parses legacy peer-add output and the strict, versioned v2 envelope.
class PeerAddEnvelopeParser {
  /// Creates a [PeerAddEnvelopeParser].
  const PeerAddEnvelopeParser();

  static const _beginMarker = '---BEGIN-CONF---';
  static const _endMarker = '---END-CONF---';
  static const _v2Headers = {
    'FAV_ENVELOPE_VERSION',
    'INSTALLATION_ID',
    'OPERATION_ID',
    'REVISION',
    'IPV6_MODE',
    'ADDR4',
    'ADDR6',
    'PUBKEY',
  };

  /// Parses [stdout]. V2 output requires [expected] so identity and revision
  /// are checked rather than merely copied into a model.
  Future<PeerAddEnvelope> parse(
    String stdout, {
    PeerAddEnvelopeExpectation? expected,
  }) async {
    final lines = stdout.replaceAll('\r', '').split('\n');
    final beginIndexes = <int>[];
    final endIndexes = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i] == _beginMarker) beginIndexes.add(i);
      if (lines[i] == _endMarker) endIndexes.add(i);
    }
    if (beginIndexes.length != 1 ||
        endIndexes.length != 1 ||
        endIndexes.single <= beginIndexes.single) {
      _fail('envelope body markers missing, duplicated or unbalanced');
    }
    final begin = beginIndexes.single;
    final end = endIndexes.single;
    final body = '${lines.sublist(begin + 1, end).join('\n')}\n';
    final prefix = lines.sublist(0, begin);
    final versionLines = prefix
        .where((line) => line.startsWith('FAV_ENVELOPE_VERSION'))
        .toList();
    if (versionLines.isEmpty) return _parseLegacy(prefix, body);
    if (versionLines.length != 1) {
      _fail('duplicate FAV_ENVELOPE_VERSION header');
    }
    if (!versionLines.single.startsWith('FAV_ENVELOPE_VERSION=')) {
      _fail('malformed FAV_ENVELOPE_VERSION header');
    }
    final version = int.tryParse(versionLines.single.split('=').last.trim());
    if (version != 2) _fail('unsupported envelope version');
    if (expected == null) {
      _fail('v2 envelope has no expected operation context');
    }

    final start = prefix.indexOf(versionLines.single);
    final headers = <String, String>{};
    for (final line in prefix.skip(start)) {
      if (line.trim().isEmpty) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) _fail('diagnostic output inside v2 envelope headers');
      final key = line.substring(0, eq).trim();
      final value = line.substring(eq + 1).trim();
      if (!_v2Headers.contains(key)) _fail('unknown v2 envelope header');
      if (headers.containsKey(key)) _fail('duplicate $key header');
      if (value.isEmpty) _fail('empty $key header');
      headers[key] = value;
    }
    if (!headers.keys.toSet().containsAll(_v2Headers)) {
      _fail('v2 envelope is missing required headers');
    }

    final revision = int.tryParse(headers['REVISION']!);
    final mode = switch (headers['IPV6_MODE']) {
      'routed' => Ipv6Mode.routed,
      'blocked' => Ipv6Mode.blocked,
      _ => null,
    };
    if (revision == null || revision <= 0 || mode == null) {
      _fail('v2 envelope has an invalid revision or mode');
    }
    if (!_safeIdentity(headers['INSTALLATION_ID']!) ||
        !_safeIdentity(headers['OPERATION_ID']!)) {
      _fail('v2 envelope has an invalid identity');
    }
    try {
      WgPublicKey.parse(headers['PUBKEY']!);
    } on FormatException {
      _fail('v2 envelope has an invalid public key');
    }

    final networkProblem = networkConfigurationV2Problem(expected.network);
    if (networkProblem != null) {
      _fail('incompatible network metadata: $networkProblem');
    }
    if (headers['INSTALLATION_ID'] != expected.network.installationId ||
        headers['OPERATION_ID'] != expected.operationId ||
        revision < expected.revision ||
        mode != expected.network.ipv6Mode) {
      _fail('v2 envelope identity, revision or mode mismatch');
    }

    final profile = await _parseV2Profile(body, mode);
    final address4 = headers['ADDR4']!;
    final address6 = headers['ADDR6']!;
    if (profile.address != address4 ||
        profile.ipv6Address != address6 ||
        profile.clientPublicKey != headers['PUBKEY']) {
      _fail('v2 envelope headers do not match the client profile');
    }
    _validateAllocatedPair(address4, address6, expected.network);
    return PeerAddEnvelope(
      address: address4,
      ipv6Address: address6,
      publicKey: headers['PUBKEY']!,
      rawConf: body,
      version: 2,
      installationId: headers['INSTALLATION_ID'],
      operationId: headers['OPERATION_ID'],
      revision: revision,
      ipv6Mode: mode,
    );
  }

  PeerAddEnvelope _parseLegacy(List<String> prefix, String body) {
    String? address;
    String? publicKey;
    for (final line in prefix) {
      if (line.startsWith('ADDR=')) {
        address = line.substring('ADDR='.length).trim();
      } else if (line.startsWith('PUBKEY=')) {
        publicKey = line.substring('PUBKEY='.length).trim();
      }
    }
    if (address == null || address.isEmpty) _fail('missing ADDR header');
    if (publicKey == null || publicKey.isEmpty) _fail('missing PUBKEY header');
    return PeerAddEnvelope(
      address: address,
      publicKey: publicKey,
      rawConf: body,
    );
  }

  Future<ClientProfile> _parseV2Profile(String body, Ipv6Mode mode) async {
    try {
      return await const ClientProfileParser().parse(
        body,
        requireV2: true,
        ipv6Mode: mode,
      );
    } on AppException {
      _fail('v2 envelope contains an invalid client profile');
    }
  }

  void _validateAllocatedPair(
    String address4,
    String address6,
    NetworkConfiguration network,
  ) {
    if (!address4.endsWith('/32') || !isValidCidrV4(address4)) {
      _fail('v2 envelope has an invalid IPv4 peer address');
    }
    final v4 = address4.split('/').first.split('.').map(int.parse).toList();
    final subnet = network.ipv4Subnet!
        .split('/')
        .first
        .split('.')
        .map(int.parse)
        .toList();
    final slot = v4[3];
    if (slot < 2 ||
        slot > 254 ||
        v4[0] != subnet[0] ||
        v4[1] != subnet[1] ||
        v4[2] != subnet[2] ||
        address6 != '${ipv6AddressForSlot(network.ipv6Subnet!, slot)}/128') {
      _fail('v2 envelope peer addresses do not share the allocated slot');
    }
  }
}

bool _safeIdentity(String value) =>
    RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$').hasMatch(value);

Never _fail(String detail) =>
    throw AppException(ErrorCode.peerParseFailed, detail: detail);
