import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/theme/app_theme.dart';
import 'package:fav/features/install/application/install_controller.dart';
import 'package:fav/features/install/domain/install_run.dart';
import 'package:fav/features/install/presentation/install_progress_screen.dart';
import 'package:fav/features/servers/data/hive_server_repository.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/server_fakes.dart';

/// [InstallController] pinned to a fixed state, bypassing the real deps.
class _FixedInstallController extends InstallController {
  _FixedInstallController(this._initial, {this.runLog = ''});

  final InstallFlowState _initial;

  /// Canned log returned by [fetchRunLog].
  final String runLog;

  @override
  InstallFlowState build() => _initial;

  @override
  Future<String> fetchRunLog() async => runLog;
}

void main() {
  Future<AppLocalizations> loadEn() {
    return AppLocalizations.delegate.load(const Locale('en'));
  }

  Future<void> pumpFailure(
    WidgetTester tester,
    InstallFailure failure, {
    String runLog = '',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          installControllerProvider.overrideWith(
            () => _FixedInstallController(failure, runLog: runLog),
          ),
          serverRepositoryProvider.overrideWithValue(FakeServerRepository()),
        ],
        child: MaterialApp(
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const InstallProgressScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpSuccess(
    WidgetTester tester,
    InstallSuccess success,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          installControllerProvider.overrideWith(
            () => _FixedInstallController(success),
          ),
          serverRepositoryProvider.overrideWithValue(FakeServerRepository()),
        ],
        child: MaterialApp(
          theme: lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const InstallProgressScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> expandTechnicalDetails(
    WidgetTester tester,
    AppLocalizations l10n,
  ) async {
    await tester.scrollUntilVisible(
      find.text(l10n.errorTechnicalDetails),
      100,
    );
    await tester.tap(find.text(l10n.errorTechnicalDetails));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'groups hardening warnings under an explicit incomplete outcome',
    (tester) async {
      final l10n = await loadEn();
      final run = InstallRun(
        runId: 'hardening-warning',
        serverId: 'server-1',
        status: RunStatus.success,
        steps: const [],
        scriptWasModified: false,
        startedAt: DateTime(2026, 10, 6),
      );
      await pumpSuccess(
        tester,
        InstallSuccess(
          run: run,
          rootSshDisabled: false,
          hardeningApplied: false,
          monitoringInstalled: false,
          lockoutWarning: const AppException(ErrorCode.lockoutAborted),
          hardeningWarning: const AppException(ErrorCode.lockoutAborted),
        ),
      );

      expect(find.text(l10n.hardeningIncompleteTitle), findsOneWidget);
      expect(
        find.text('${l10n.antiLockoutWarning}\n\n${l10n.hardeningWarning}'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a pre-launch failure hides View full log but keeps the cleanup (F11)',
    (tester) async {
      final l10n = await loadEn();
      // run == null: the failure happened before any run was launched, so
      // there is no remote log to fetch — the sheet would only show "–".
      await pumpFailure(
        tester,
        const InstallFailure(
          error: AppException(ErrorCode.authInvalidCredentials),
        ),
      );

      expect(find.text(l10n.installFailedTitle), findsOneWidget);
      await expandTechnicalDetails(tester, l10n);

      expect(find.text(l10n.runViewLog), findsNothing);
      expect(find.text(l10n.actionCleanup), findsOneWidget);
    },
  );

  testWidgets(
    'a failure of a launched run still offers View full log',
    (tester) async {
      final l10n = await loadEn();
      await pumpFailure(
        tester,
        InstallFailure(
          error: const AppException(ErrorCode.runStepFailed),
          run: InstallRun(
            runId: 'aabbcc-run',
            serverId: 'server-1',
            status: RunStatus.failed,
            steps: const [],
            scriptWasModified: false,
            startedAt: DateTime(2026, 8, 19),
          ),
        ),
      );

      await expandTechnicalDetails(tester, l10n);

      expect(find.text(l10n.runViewLog), findsOneWidget);
    },
  );

  testWidgets(
    'copying the run log scrubs identities; the on-screen view stays raw',
    (tester) async {
      // What leaves the device (clipboard, share sheet) must hold the same
      // bar as the bug-report scrubber; the visible sheet is an on-device
      // diagnostic and stays verbatim (audit L6).
      final clipboardCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardCalls.add(call);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final l10n = await loadEn();
      await pumpFailure(
        tester,
        InstallFailure(
          error: const AppException(ErrorCode.runStepFailed),
          run: InstallRun(
            runId: 'aabbcc-run',
            serverId: 'server-1',
            status: RunStatus.failed,
            steps: const [],
            scriptWasModified: false,
            startedAt: DateTime(2026, 8, 19),
          ),
        ),
        runLog: 'SSH exec: chown favops@203.0.113.5 done',
      );

      await expandTechnicalDetails(tester, l10n);
      await tester.tap(find.text(l10n.runViewLog));
      await tester.pumpAndSettle();

      // The sheet shows the raw log.
      expect(
        find.textContaining('favops@203.0.113.5'),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(Icons.copy_outlined));
      await tester.pumpAndSettle();

      final copied =
          (clipboardCalls.single.arguments as Map<Object?, Object?>)['text']!
              as String;
      expect(copied, contains('<user>@<ip>'));
      expect(copied, isNot(contains('favops')));
      expect(copied, isNot(contains('203.0.113.5')));
    },
  );
}
