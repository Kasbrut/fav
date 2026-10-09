import 'package:fav/features/settings/domain/app_language.dart';
import 'package:fav/features/settings/domain/locale_choice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocaleChoice', () {
    test('system has a null code and the "system" storage id', () {
      expect(LocaleChoice.system.code, isNull);
      expect(LocaleChoice.system.storageId, 'system');
    });

    test('forCode keeps the code as its storage id', () {
      final choice = LocaleChoice.forCode('de');
      expect(choice.code, 'de');
      expect(choice.storageId, 'de');
    });

    test('value equality is based on the code', () {
      expect(LocaleChoice.forCode('en'), LocaleChoice.forCode('en'));
      expect(LocaleChoice.forCode('en'), isNot(LocaleChoice.forCode('it')));
      expect(LocaleChoice.forCode('en'), isNot(LocaleChoice.system));
    });

    group('parse', () {
      test('null and "system" map to system', () {
        expect(LocaleChoice.parse(null), LocaleChoice.system);
        expect(LocaleChoice.parse('system'), LocaleChoice.system);
      });

      test('legacy and new codes round-trip', () {
        for (final language in appLanguages) {
          final parsed = LocaleChoice.parse(language.code);
          expect(parsed, LocaleChoice.forCode(language.code));
          expect(parsed.storageId, language.code);
        }
      });

      test('unknown codes fall back to system', () {
        expect(LocaleChoice.parse('klingon'), LocaleChoice.system);
      });
    });
  });
}
