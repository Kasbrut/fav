import 'dart:convert';

import 'package:fav/features/install/data/provisioner/network_result_parser.dart';
import 'package:fav/features/servers/domain/wireguard_installation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = NetworkResultParser();

  Map<String, Object?> valid() => {
    'schemaVersion': 2,
    'installationId': 'installation-1',
    'operationId': 'operation-1',
    'revision': 1,
    'network': {
      'ipv4Subnet': '10.13.13.0/24',
      'ipv6Mode': 'blocked',
      'ipv6Subnet': 'fd12:3456:789a::/64',
      'fallbackIpv6Subnet': 'fd12:3456:789a::/64',
      'serverIpv6Address': 'fd12:3456:789a::1/64',
      'wan4': 'ens3',
      'wan6': null,
    },
    'capability': {
      'status': 'unknown',
      'reason': 'probe_target_missing',
      'checkedAt': '2026-09-17T10:00:00Z',
    },
  };

  dynamic parse(Map<String, Object?> value) => parser.parse(
    jsonEncode(value),
    expectedInstallationId: 'installation-1',
    expectedOperationId: 'operation-1',
    expectedIpv4Subnet: '10.13.13.0/24',
    expectedFallbackIpv6Subnet: 'fd12:3456:789a::/64',
  );

  test('accepts a complete semantically valid result', () {
    final result = parse(valid()) as NetworkConfiguration;
    expect(result.ipv6Mode, Ipv6Mode.blocked);
    expect(result.capabilityStatus, CapabilityStatus.unknown);
  });

  test('rejects corrupt, partial and future results', () {
    expect(
      () => parser.parse(
        '{bad',
        expectedInstallationId: 'installation-1',
        expectedOperationId: 'operation-1',
        expectedIpv4Subnet: '10.13.13.0/24',
        expectedFallbackIpv6Subnet: 'fd12:3456:789a::/64',
      ),
      throwsFormatException,
    );
    final partial = valid()..remove('capability');
    expect(() => parse(partial), throwsFormatException);
    final future = valid()..['schemaVersion'] = 3;
    expect(() => parse(future), throwsFormatException);
  });

  test('rejects identity, revision and request mismatches', () {
    final identity = valid()..['installationId'] = 'other';
    expect(() => parse(identity), throwsFormatException);
    final revision = valid()..['revision'] = 2;
    expect(() => parse(revision), throwsFormatException);
    final network = Map<String, Object?>.from(valid()['network']! as Map)
      ..['ipv4Subnet'] = '10.14.14.0/24';
    final mismatch = valid()..['network'] = network;
    expect(() => parse(mismatch), throwsFormatException);
  });

  test(
    'rejects structurally complete but semantically inconsistent result',
    () {
      final capability = Map<String, Object?>.from(
        valid()['capability']! as Map,
      )..['status'] = 'supported';
      final mismatch = valid()..['capability'] = capability;
      expect(() => parse(mismatch), throwsFormatException);
    },
  );
}
