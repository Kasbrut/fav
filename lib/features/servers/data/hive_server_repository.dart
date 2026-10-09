import 'package:fav/core/persistence/app_database.dart';
import 'package:fav/features/servers/data/server_mappers.dart';
import 'package:fav/features/servers/domain/server.dart';
import 'package:fav/features/servers/domain/server_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

/// [ServerRepository] backed by the encrypted Hive database.
class HiveServerRepository implements ServerRepository {
  /// Creates a [HiveServerRepository] over the given encrypted box.
  HiveServerRepository(this._box);

  final Box<Map<dynamic, dynamic>> _box;

  @override
  Future<List<Server>> getAll() async {
    return _box.values.map(serverFromMap).toList();
  }

  @override
  Future<Server?> getById(String id) async {
    final raw = _box.get(id);
    return raw == null ? null : serverFromMap(raw);
  }

  @override
  Future<void> save(Server server) {
    return _box.put(server.id, serverToMap(server));
  }

  @override
  Future<void> delete(String id) => _box.delete(id);
}

/// Provides the [ServerRepository] backed by the encrypted database.
final Provider<ServerRepository> serverRepositoryProvider =
    Provider<ServerRepository>(
      (ref) => HiveServerRepository(ref.watch(appDatabaseProvider).serversBox),
    );
