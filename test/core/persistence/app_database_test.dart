import 'dart:io';

import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/features/settings/data/preferences_box.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../support/in_memory_secure_store.dart';

/// Tests for the encrypted persistence infrastructure.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('wg_db_test');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  group('resolveDbEncryptionKey', () {
    test('generates a 256-bit key on first run and reuses it', () async {
      final store = InMemorySecureStore();
      final first = await resolveDbEncryptionKey(store);
      final second = await resolveDbEncryptionKey(store);
      expect(first, hasLength(32));
      expect(second, equals(first));
    });

    test('a corrupted stored key never leaks into the error (H2)', () async {
      // FormatException.toString() embeds its source: a garbled-but-present
      // keystore value (e.g. an OS backup restore) would put the key
      // material on the boot-failure screen. The rethrown error must carry
      // none of the stored string.
      const corrupted = 'AAsWISw3Qk1YY255hI+apbC7xtHc5/L9CBMeKTQ/SlU';
      final store = InMemorySecureStore();
      await store.write('db_encryption_key', corrupted);

      Object? thrown;
      try {
        await resolveDbEncryptionKey(store);
      } on Object catch (error) {
        thrown = error;
      }
      expect(thrown, isNotNull);
      expect('$thrown', isNot(contains('AAsWISw3')));
    });
  });

  group('openServersBox', () {
    test('opens the encrypted servers box', () async {
      final box = await openServersBox(InMemorySecureStore());
      expect(box.isOpen, isTrue);
      expect(box.name, 'servers');
    });
  });

  group('openRunsBox', () {
    test('opens the encrypted runs box', () async {
      final box = await openRunsBox(InMemorySecureStore());
      expect(box.isOpen, isTrue);
      expect(box.name, 'runs');
    });
  });

  group('openScriptsBox', () {
    test('opens the encrypted scripts box', () async {
      final box = await openScriptsBox(InMemorySecureStore());
      expect(box.isOpen, isTrue);
      expect(box.name, 'scripts');
    });
  });

  group('openMonitoringEventsBox', () {
    test('opens the encrypted monitoring_events box', () async {
      final box = await openMonitoringEventsBox(InMemorySecureStore());
      expect(box.isOpen, isTrue);
      expect(box.name, 'monitoring_events');
    });
  });

  group('openPeersBox', () {
    test('opens the encrypted peers box', () async {
      final box = await openPeersBox(InMemorySecureStore());
      expect(box.isOpen, isTrue);
      expect(box.name, 'peers');
    });
  });

  group('AppDatabase', () {
    test('exposes the opened boxes', () async {
      final store = InMemorySecureStore();
      final serversBox = await openServersBox(store);
      final runsBox = await openRunsBox(store);
      final scriptsBox = await openScriptsBox(store);
      final monitoringEventsBox = await openMonitoringEventsBox(store);
      final peersBox = await openPeersBox(store);
      final preferencesBox = await openPreferencesBox(store);
      final database = AppDatabase(
        serversBox: serversBox,
        runsBox: runsBox,
        scriptsBox: scriptsBox,
        monitoringEventsBox: monitoringEventsBox,
        peersBox: peersBox,
        preferencesBox: preferencesBox,
      );
      expect(database.serversBox, same(serversBox));
      expect(database.runsBox, same(runsBox));
      expect(database.scriptsBox, same(scriptsBox));
      expect(database.monitoringEventsBox, same(monitoringEventsBox));
      expect(database.peersBox, same(peersBox));
      expect(database.preferencesBox, same(preferencesBox));
    });
  });

  group('appDatabaseProvider', () {
    test('throws until overridden', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // Riverpod 3 wraps an errored provider's exception in a
      // ProviderException when read; the underlying cause is still the
      // UnimplementedError raised by the un-overridden provider.
      expect(
        () => container.read(appDatabaseProvider),
        throwsA(
          isA<ProviderException>().having(
            (e) => e.exception,
            'exception',
            isA<UnimplementedError>(),
          ),
        ),
      );
    });
  });
}
