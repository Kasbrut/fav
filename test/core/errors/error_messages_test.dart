import 'package:fav/core/errors/app_exception.dart';
import 'package:fav/core/errors/error_messages.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppLocalizations> _l10n(WidgetTester tester, Locale locale) async {
  late AppLocalizations result;
  await tester.pumpWidget(
    Localizations(
      locale: locale,
      delegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: Builder(
        builder: (context) {
          result = AppLocalizations.of(context)!;
          return const SizedBox();
        },
      ),
    ),
  );
  return result;
}

void main() {
  test('every error code maps to a non-empty English message', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    for (final code in ErrorCode.values) {
      expect(localizedErrorMessage(l10n, code), isNotEmpty, reason: code.id);
    }
  });

  test('runStepFailed embeds the step name', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final message = localizedErrorMessage(
      l10n,
      ErrorCode.runStepFailed,
      stepName: 'install_pkgs',
    );
    expect(message, contains('install_pkgs'));
  });

  test('the Italian locale resolves a message', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('it'));
    expect(
      localizedErrorMessage(l10n, ErrorCode.connSshPortClosed),
      isNotEmpty,
    );
  });

  testWidgets('every ErrorCode resolves a non-empty cause and fix in EN', (
    tester,
  ) async {
    final l10n = await _l10n(tester, const Locale('en'));
    for (final code in ErrorCode.values) {
      expect(
        localizedErrorCause(l10n, code),
        isNotEmpty,
        reason: 'cause empty for ${code.id}',
      );
      expect(
        localizedErrorFix(l10n, code),
        isNotEmpty,
        reason: 'fix empty for ${code.id}',
      );
    }
  });

  testWidgets('every ErrorCode resolves a non-empty cause and fix in IT', (
    tester,
  ) async {
    final l10n = await _l10n(tester, const Locale('it'));
    for (final code in ErrorCode.values) {
      expect(
        localizedErrorCause(l10n, code),
        isNotEmpty,
        reason: 'cause empty for ${code.id}',
      );
      expect(
        localizedErrorFix(l10n, code),
        isNotEmpty,
        reason: 'fix empty for ${code.id}',
      );
    }
  });

  test('teardownFailed maps to message/cause/fix in English', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(localizedErrorMessage(l10n, ErrorCode.teardownFailed), isNotEmpty);
    expect(localizedErrorCause(l10n, ErrorCode.teardownFailed), isNotEmpty);
    expect(localizedErrorFix(l10n, ErrorCode.teardownFailed), isNotEmpty);
  });

  test('teardownFailed has the ERR-TRD-01 id', () {
    expect(ErrorCode.teardownFailed.id, 'ERR-TRD-01');
  });

  test('teardown UI strings resolve in English', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(l10n.teardownTitle, isNotEmpty);
    expect(l10n.teardownServicesOption, isNotEmpty);
    expect(l10n.teardownReopenWarning, isNotEmpty);
    expect(l10n.teardownLockoutWarning, isNotEmpty);
    expect(l10n.teardownMessage('vps'), contains('vps'));
    expect(l10n.teardownDoneSnackbar('vps'), contains('vps'));
  });
}
