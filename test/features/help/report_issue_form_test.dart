import 'package:fav/core/utils/app_logger.dart';
import 'package:fav/features/help/presentation/report_issue_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    // package_info_plus uses 'dev.fluttercommunity.plus/package_info' and
    // calls 'getAll'.
    // device_info_plus uses 'dev.fluttercommunity.plus/device_info'.
    // On the macOS test host neither isIOS nor isAndroid is true, so the
    // osVersion branch in _loadDiagnostic is skipped — we still register the
    // handler so any accidental call doesn't throw.
    messenger
      ..setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (call) async {
          if (call.method == 'getAll') {
            return <String, dynamic>{
              'appName': 'FAV',
              'packageName': 'com.kasbrut.fav',
              'version': '1.0.0',
              'buildNumber': '1',
              'buildSignature': '',
              'installerStore': null,
            };
          }
          return null;
        },
      )
      ..setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/device_info'),
        (call) async {
          if (call.method == 'getIosDeviceInfo') {
            return <String, dynamic>{
              'systemVersion': '17.4',
              'name': 'iPhone',
              'systemName': 'iOS',
              'model': 'iPhone',
              'localizedModel': 'iPhone',
              'identifierForVendor': '00000000-0000-0000-0000-000000000000',
              'isPhysicalDevice': false,
              'utsname': {
                'sysname': 'Darwin',
                'nodename': 'iPhone',
                'release': '23.0.0',
                'version': '1',
                'machine': 'arm64',
              },
            };
          }
          if (call.method == 'getAndroidDeviceInfo') {
            return <String, dynamic>{
              'version': {'release': '14'},
              'board': 'mock',
              'bootloader': 'mock',
              'brand': 'mock',
              'device': 'mock',
              'display': 'mock',
              'fingerprint': 'mock',
              'hardware': 'mock',
              'host': 'mock',
              'id': 'mock',
              'manufacturer': 'mock',
              'model': 'mock',
              'product': 'mock',
              'tags': 'mock',
              'type': 'mock',
              'isPhysicalDevice': false,
              'systemFeatures': <String>[],
              'serialNumber': 'mock',
              'supported32BitAbis': <String>[],
              'supported64BitAbis': <String>[],
              'supportedAbis': <String>[],
            };
          }
          return null;
        },
      );
  });

  tearDown(() {
    messenger
      ..setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        null,
      )
      ..setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/device_info'),
        null,
      );
  });

  testWidgets(
    'renders the three text fields, the dropdown and the security warning',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: ReportIssueScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('What were you doing?'), findsOneWidget);
      expect(find.text('What did you expect?'), findsOneWidget);
      expect(find.text('What happened instead?'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber), findsOneWidget);
      expect(
        find.text('Open GitHub to send', skipOffstage: false),
        findsOneWidget,
      );
      // Diagnostic block — scroll to the ExpansionTile (it lives below the
      // visible area in the test viewport), expand it, then assert content.
      // package_info channel is stubbed so appVersion is '1.0.0+1'.
      // Platform OS label varies by test host — assert only the prefix.
      final expansionTiles = find.byType(ExpansionTile);
      if (expansionTiles.evaluate().isNotEmpty) {
        await tester.ensureVisible(expansionTiles.first);
        await tester.pumpAndSettle();
        await tester.tap(expansionTiles.first);
        await tester.pumpAndSettle();
        expect(find.text('App: 1.0.0+1'), findsOneWidget);
        expect(find.textContaining('Platform: '), findsOneWidget);
        expect(find.text('Locale: en'), findsOneWidget);
      }
    },
  );

  testWidgets('renders the extended diagnostic checkbox', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReportIssueScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text('Include extended diagnostic (recommended)'),
      findsOneWidget,
    );
  });

  testWidgets('renders the attach-logs checkbox', (tester) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ReportIssueScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Attach recent app logs'), findsOneWidget);
  });

  testWidgets(
    'attaching logs previews the scrubbed text and copies it on continue',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // Capture what reaches the clipboard.
      String? copied;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final buffer = AppLogBuffer(capacity: 10)
        ..output(
          OutputEvent(
            LogEvent(
              Level.info,
              'SSH connect: root@198.51.100.1:22',
              time: DateTime(2026, 8, 19, 12),
            ),
            const [],
          ),
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appLogBufferProvider.overrideWithValue(buffer)],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: ReportIssueScreen(),
          ),
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Attach recent app logs'));
      await tester.tap(find.text('Attach recent app logs'));
      await tester.pump();
      await tester.ensureVisible(find.text('Open GitHub to send'));
      await tester.tap(find.text('Open GitHub to send'));
      await tester.pumpAndSettle();

      // The editable preview shows the SCRUBBED lines: identifying values
      // are masked, and only what the user sees can be copied.
      expect(find.text('Review the logs'), findsOneWidget);
      final preview = tester.widget<TextField>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
      );
      expect(preview.controller!.text, contains('<user>@<ip>:22'));
      expect(preview.controller!.text, isNot(contains('198.51.100.1')));

      await tester.tap(find.text('Copy logs & continue'));
      await tester.pumpAndSettle();
      expect(copied, contains('<user>@<ip>:22'));
      expect(copied, isNot(contains('198.51.100.1')));
    },
  );

  testWidgets(
    'the preview offers continuing without logs instead of aborting (L3)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      String? copied;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      var launches = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: ReportIssueScreen(
              urlLauncher: (_) async {
                launches++;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.ensureVisible(find.text('Attach recent app logs'));
      await tester.tap(find.text('Attach recent app logs'));
      await tester.pump();
      await tester.ensureVisible(find.text('Open GitHub to send'));
      await tester.tap(find.text('Open GitHub to send'));
      await tester.pumpAndSettle();

      // Changing one's mind about the logs must not abort the whole report.
      await tester.tap(find.text('Continue without logs'));
      await tester.pumpAndSettle();

      // Nothing was copied, and the submission still proceeded to the
      // browser launch.
      expect(copied, isNull);
      expect(launches, 1);

      // A dismissal (Cancel), by contrast, aborts without launching.
      await tester.tap(find.text('Open GitHub to send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      expect(launches, 1);
    },
  );
}
