import 'package:fav/features/settings/domain/app_language.dart';
import 'package:meta/meta.dart';

/// Locale choice persisted in user preferences. The sentinel [system] defers to
/// the device locale; any other value forces the app into a specific language.
///
/// Flutter-free: the application layer maps it to a `Locale` for
/// `MaterialApp.locale` (see `preference_mappers.dart`).
@immutable
class LocaleChoice {
  const LocaleChoice._(this.code);

  /// Forces the app into the language identified by [code], which must be a
  /// registered [appLanguages] entry. Use [LocaleChoice.parse] for untrusted
  /// input (e.g. persisted values).
  factory LocaleChoice.forCode(String code) {
    assert(
      appLanguages.any((language) => language.code == code),
      'Unknown language code "$code" — not in appLanguages',
    );
    return LocaleChoice._(code);
  }

  /// Parses a persisted [storageId]. `null`/`"system"` map to [system]; a code
  /// listed in [appLanguages] maps to that language; anything else falls back
  /// to [system].
  factory LocaleChoice.parse(String? raw) {
    if (raw == null || raw == 'system') return system;
    for (final language in appLanguages) {
      if (language.code == raw) return LocaleChoice._(raw);
    }
    return system;
  }

  /// Follow the OS locale.
  static const LocaleChoice system = LocaleChoice._(null);

  /// BCP-47 language tag to force, or `null` to follow the OS locale.
  final String? code;

  /// Stable identifier persisted in the preferences box. Mirrors the legacy
  /// enum names (`"system"`, `"en"`, `"it"`, …) so no migration is needed.
  String get storageId => code ?? 'system';

  @override
  bool operator ==(Object other) => other is LocaleChoice && other.code == code;

  @override
  int get hashCode => code.hashCode;
}
