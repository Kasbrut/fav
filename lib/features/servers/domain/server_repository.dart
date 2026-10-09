import 'package:fav/features/servers/domain/server.dart';

/// Persistence contract for the registered servers.
abstract interface class ServerRepository {
  /// Returns every registered server.
  Future<List<Server>> getAll();

  /// Returns the server identified by [id], or `null` if none exists.
  Future<Server?> getById(String id);

  /// Inserts [server], or updates it if one with the same id already exists.
  Future<void> save(Server server);

  /// Removes the server identified by [id]; a no-op if it does not exist.
  Future<void> delete(String id);
}
