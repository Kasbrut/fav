import 'package:fav/app.dart';
import 'package:fav/features/settings/application/app_reset_service.dart';
import 'package:fav/features/settings/presentation/post_wipe_screen.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [AppResetService] fake: records whether `wipe()` ran, without touching
/// Hive or secure storage.
class _FakeResetService extends AppResetService {
  _FakeResetService() : super(deleteAllSecureEntries: _noop);
  bool wiped = false;
  @override
  Future<void> wipe() async => wiped = true;
}

Future<void> _noop() async {}

void main() {
  Future<AppLocalizations> loadEn() =>
      AppLocalizations.delegate.load(const Locale('en'));

  testWidgets(
    'explains the boot failure and shows the technical detail (M10)',
    (tester) async {
      final l10n = await loadEn();
      await tester.pumpWidget(
        BootFailureApp(
          error: StateError('cannot decrypt box'),
          resetService: _FakeResetService(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n.bootFailureTitle), findsOneWidget);
      expect(find.text(l10n.bootFailureBody), findsOneWidget);
      expect(find.textContaining('cannot decrypt box'), findsOneWidget);
      expect(find.text(l10n.settingsWipeButton), findsOneWidget);
    },
  );

  testWidgets(
    'erasing from the boot-failure app runs the confirmed wipe (M10)',
    (tester) async {
      final l10n = await loadEn();
      final service = _FakeResetService();
      await tester.pumpWidget(
        BootFailureApp(
          error: StateError('cannot decrypt box'),
          resetService: service,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.settingsWipeButton));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, l10n.settingsWipeDialog1Continue),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        l10n.settingsWipeConfirmWord,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, l10n.settingsWipeDialog2Action),
      );
      await tester.pumpAndSettle();

      // The shared terminal screen owns the wipe and shows its outcome.
      expect(find.byType(PostWipeScreen), findsOneWidget);
      expect(service.wiped, isTrue);
      expect(find.text(l10n.settingsPostWipeTitle), findsOneWidget);
    },
  );
}
