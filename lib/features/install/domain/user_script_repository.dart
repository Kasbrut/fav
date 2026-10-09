import 'package:fav/features/install/domain/user_script.dart';

/// Stores user-editable script overrides in the encrypted database
/// (spec §6.3, RF-09, RF-10).
///
/// Each override is keyed by the script's relative path (e.g.
/// `modules/60_firewall.sh`); see `kEditableScriptPaths`. An absent entry
/// means the effective content is the bundled original.
abstract interface class UserScriptRepository {
  /// Returns every stored override.
  Future<List<UserScript>> getAll();

  /// Returns the override for the path [id], or `null` when none exists.
  Future<UserScript?> getById(String id);

  /// Inserts or updates [script] (keyed by `script.id`, the relative path).
  Future<void> save(UserScript script);

  /// Removes the override for the path [id] (restoring the original).
  Future<void> delete(String id);
}
