import 'dart:io';

import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/core/persistence/secure_store.dart';
import 'package:fav/features/settings/presentation/backup_restore_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../support/in_memory_secure_store.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late InMemorySecureStore secureStore;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('backup_screen_test_');
    Hive.init(tempDir.path);
    Future<Box<Map<dynamic, dynamic>>> box(String name) =>
        Hive.openBox<Map<dynamic, dynamic>>(name);
    database = AppDatabase(
      serversBox: await box('servers'),
      runsBox: await box('runs'),
      scriptsBox: await box('scripts'),
      monitoringEventsBox: await box('monitoring'),
      peersBox: await box('peers'),
      preferencesBox: await box('preferences'),
    );
    secureStore = InMemorySecureStore();
  });

  tearDown(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          secureStoreProvider.overrideWithValue(secureStore),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: BackupRestoreScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lays out backup and restore actions on a phone', (tester) async {
    await pump(tester, const Size(390, 844));

    expect(find.text('Backup and restore'), findsOneWidget);
    expect(find.text('Create encrypted backup'), findsOneWidget);
    expect(find.text('Restore backup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remains constrained without overflow on a tablet', (
    tester,
  ) async {
    await pump(tester, const Size(1024, 768));

    expect(find.text('Create encrypted backup'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
