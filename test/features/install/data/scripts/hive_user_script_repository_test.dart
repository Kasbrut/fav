import 'dart:io';

import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/features/install/data/scripts/hive_user_script_repository.dart';
import 'package:fav/features/install/domain/user_script.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../../../support/in_memory_secure_store.dart';

void main() {
  late Directory tempDir;
  late InMemorySecureStore secureStore;
  late HiveUserScriptRepository repository;

  UserScript buildScript(String id, {DateTime? createdAt, String? content}) {
    return UserScript.fromContent(
      id: id,
      content: content ?? '#!/bin/bash\n# version $id\n',
      createdAt: createdAt ?? DateTime(2026, 5, 18),
    );
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('wg_user_script_test');
    Hive.init(tempDir.path);
    secureStore = InMemorySecureStore();
    repository = HiveUserScriptRepository(await openScriptsBox(secureStore));
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('saves and reads a script by id, including its hash', () async {
    final script = buildScript('s1');
    await repository.save(script);
    final loaded = await repository.getById('s1');
    expect(loaded, isNotNull);
    expect(loaded!.id, 's1');
    expect(loaded.content, script.content);
    expect(loaded.contentHash, script.contentHash);
  });

  test('getById returns null for an unknown id', () async {
    expect(await repository.getById('missing'), isNull);
  });

  test('round-trips an override keyed by a script path', () async {
    // Overrides are keyed by the script's relative path (id == path).
    const path = 'modules/26_deploy_user_keys.sh';
    await repository.save(buildScript(path, content: '# custom deploy keys\n'));
    final loaded = await repository.getById(path);
    expect(loaded?.id, path);
    expect(loaded?.content, '# custom deploy keys\n');
    await repository.delete(path);
    expect(await repository.getById(path), isNull);
  });

  test('getAll returns scripts newest first', () async {
    await repository.save(buildScript('old', createdAt: DateTime(2026)));
    await repository.save(buildScript('mid', createdAt: DateTime(2026, 3)));
    await repository.save(buildScript('new', createdAt: DateTime(2026, 6)));
    final all = await repository.getAll();
    expect(all.map((script) => script.id), ['new', 'mid', 'old']);
  });

  test('save replaces an existing script at the same id', () async {
    await repository.save(buildScript('s1', content: 'echo first'));
    await repository.save(buildScript('s1', content: 'echo second'));
    final loaded = await repository.getById('s1');
    expect(loaded?.content, 'echo second');
  });

  test('delete removes a script', () async {
    await repository.save(buildScript('s1'));
    await repository.delete('s1');
    expect(await repository.getById('s1'), isNull);
  });

  test('scripts survive a re-open of the box', () async {
    await repository.save(buildScript('s1'));
    await Hive.close();
    Hive.init(tempDir.path);
    final reopened = HiveUserScriptRepository(
      await openScriptsBox(secureStore),
    );
    expect((await reopened.getById('s1'))?.id, 's1');
  });
}
