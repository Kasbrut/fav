import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/features/install/data/scripts/user_script_mappers.dart';
import 'package:fav/features/install/domain/user_script.dart';
import 'package:fav/features/install/domain/user_script_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

/// [UserScriptRepository] backed by the encrypted Hive database.
class HiveUserScriptRepository implements UserScriptRepository {
  /// Creates a [HiveUserScriptRepository] over the given encrypted box.
  HiveUserScriptRepository(this._box);

  final Box<Map<dynamic, dynamic>> _box;

  @override
  Future<List<UserScript>> getAll() async {
    return _box.values.map(userScriptFromMap).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<UserScript?> getById(String id) async {
    final raw = _box.get(id);
    return raw == null ? null : userScriptFromMap(raw);
  }

  @override
  Future<void> save(UserScript script) {
    return _box.put(script.id, userScriptToMap(script));
  }

  @override
  Future<void> delete(String id) => _box.delete(id);
}

/// Provides the [UserScriptRepository] backed by the encrypted database.
final Provider<UserScriptRepository> userScriptRepositoryProvider =
    Provider<UserScriptRepository>(
      (ref) =>
          HiveUserScriptRepository(ref.watch(appDatabaseProvider).scriptsBox),
    );
