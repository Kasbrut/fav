import 'package:fav/features/settings/domain/app_language.dart';
import 'package:fav/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('appLanguages registry', () {
    test('matches the locales generated from the ARB files', () {
      final registryCodes = appLanguages.map((l) => l.code).toSet();
      final supportedCodes = AppLocalizations.supportedLocales
          .map((l) => l.languageCode)
          .toSet();
      // Every registered language must ship an ARB, and every shipped ARB must
      // be registered — otherwise the picker and the actual translations drift.
      expect(registryCodes, supportedCodes);
    });

    test('has no duplicate codes', () {
      final codes = appLanguages.map((l) => l.code).toList();
      expect(codes.toSet(), hasLength(codes.length));
    });

    test('every entry has a non-empty native name', () {
      for (final language in appLanguages) {
        expect(language.nativeName, isNotEmpty);
      }
    });
  });
}
