/// Registry of the languages the app ships translations for.
///
/// Single source of truth for the language picker: adding a new language is a
/// one-line entry here plus the matching `app_<code>.arb` file. [code] is the
/// BCP-47 tag and must equal the ARB suffix (and therefore the locale exposed
/// by `AppLocalizations.supportedLocales`).
///
/// [nativeName] is the language's own endonym (e.g. "Deutsch", "中文（简体）").
/// A language is always shown in its own language, so this is deliberately not
/// localized and does not live in the ARB files.
///
/// Flutter-free: this is plain data consumed by the presentation layer.
class AppLanguage {
  /// Creates a registry entry.
  const AppLanguage({required this.code, required this.nativeName});

  /// BCP-47 language tag (matches the `app_<code>.arb` suffix).
  final String code;

  /// The language's endonym, shown verbatim in the picker.
  final String nativeName;
}

/// Languages shipped by the app, in display order.
///
/// Keep this in sync with the `lib/l10n/app_<code>.arb` files; the drift-guard
/// test asserts the codes match `AppLocalizations.supportedLocales`.
const List<AppLanguage> appLanguages = [
  AppLanguage(code: 'en', nativeName: 'English'),
  AppLanguage(code: 'it', nativeName: 'Italiano'),
  AppLanguage(code: 'es', nativeName: 'Español'),
  AppLanguage(code: 'fr', nativeName: 'Français'),
  AppLanguage(code: 'de', nativeName: 'Deutsch'),
  AppLanguage(code: 'pt', nativeName: 'Português (Brasil)'),
  AppLanguage(code: 'ru', nativeName: 'Русский'),
  AppLanguage(code: 'zh', nativeName: '中文（简体）'),
  AppLanguage(code: 'tr', nativeName: 'Türkçe'),
  AppLanguage(code: 'uk', nativeName: 'Українська'),
];
