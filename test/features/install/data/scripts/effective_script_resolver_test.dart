import 'dart:convert';

import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/features/install/data/scripts/editable_script_catalog.dart';
import 'package:fav/features/install/domain/user_script.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fake_effective_scripts.dart';
import '../../../../support/in_memory_user_script_repository.dart';

void main() {
  UserScript override(String id, String content) => UserScript.fromContent(
    id: id,
    content: content,
    createdAt: DateTime(2026),
  );

  test('bytesFor returns the override when one exists', () async {
    final repo = InMemoryUserScriptRepository([
      override('modules/60_firewall.sh', '# custom firewall\n'),
    ]);
    final resolver = fakeResolver(repo);
    expect(
      utf8.decode(await resolver.bytesFor('modules/60_firewall.sh')),
      '# custom firewall\n',
    );
  });

  test('bytesFor falls back to the bundled original', () async {
    final resolver = fakeResolver(InMemoryUserScriptRepository());
    expect(
      utf8.decode(await resolver.bytesFor('modules/60_firewall.sh')),
      '# modules/60_firewall.sh\n',
    );
  });

  test('bytesFor resolves peer scripts via the peer source', () async {
    final resolver = fakeResolver(InMemoryUserScriptRepository());
    expect(
      utf8.decode(await resolver.bytesFor(kPeerAddScript)),
      '# peers/peer_add.sh\n',
    );
  });

  test('bytesFor honours a peer-script override', () async {
    final repo = InMemoryUserScriptRepository([
      override(kPeerRevokeScript, '# custom revoke\n'),
    ]);
    expect(
      utf8.decode(await fakeResolver(repo).bytesFor(kPeerRevokeScript)),
      '# custom revoke\n',
    );
  });

  test('bytesFor throws for an unknown path', () async {
    final resolver = fakeResolver(InMemoryUserScriptRepository());
    await expectLater(
      resolver.bytesFor('modules/does_not_exist.sh'),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          ErrorCode.scriptInvalid,
        ),
      ),
    );
  });

  test(
    'effectiveBundle hash equals the pristine hash with no overrides',
    () async {
      final resolver = fakeResolver(InMemoryUserScriptRepository());
      final effective = await resolver.effectiveBundle();
      expect(effective.bundleHash, resolver.pristineBundle.bundleHash);
    },
  );

  test(
    'effectiveBundle substitutes override bytes and changes the hash',
    () async {
      final repo = InMemoryUserScriptRepository([
        override('modules/60_firewall.sh', '# custom firewall\n'),
      ]);
      final resolver = fakeResolver(repo);
      final effective = await resolver.effectiveBundle();
      expect(effective.bundleHash, isNot(resolver.pristineBundle.bundleHash));
      final asset = effective.assets.firstWhere(
        (a) => a.relativePath == 'modules/60_firewall.sh',
      );
      expect(utf8.decode(asset.bytes), '# custom firewall\n');
    },
  );

  test('hasAnyOverride is false with no overrides', () async {
    final resolver = fakeResolver(InMemoryUserScriptRepository());
    expect(await resolver.hasAnyOverride(), isFalse);
  });

  test('hasAnyOverride ignores stale non-catalog (UUID) keys', () async {
    final repo = InMemoryUserScriptRepository([
      override('a-random-uuid-from-an-old-build', '# orphan\n'),
    ]);
    expect(await fakeResolver(repo).hasAnyOverride(), isFalse);
  });

  test('hasAnyOverride is true for a real catalog override', () async {
    final repo = InMemoryUserScriptRepository([
      override('install_wireguard.sh', '# custom\n'),
    ]);
    expect(await fakeResolver(repo).hasAnyOverride(), isTrue);
  });

  test('pruneUnknownOverrides deletes only non-catalog rows', () async {
    final repo = InMemoryUserScriptRepository([
      override('install_wireguard.sh', '# kept\n'),
      override('a-random-uuid', '# removed\n'),
    ]);
    await fakeResolver(repo).pruneUnknownOverrides();
    expect(await repo.getById('install_wireguard.sh'), isNotNull);
    expect(await repo.getById('a-random-uuid'), isNull);
  });
}
