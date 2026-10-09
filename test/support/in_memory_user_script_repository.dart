import 'package:fav/features/install/domain/user_script.dart';
import 'package:fav/features/install/domain/user_script_repository.dart';

/// In-memory [UserScriptRepository] for tests.
class InMemoryUserScriptRepository implements UserScriptRepository {
  /// Creates the repository, optionally pre-populated with [seed] scripts.
  InMemoryUserScriptRepository([Iterable<UserScript> seed = const []]) {
    for (final script in seed) {
      _store[script.id] = script;
    }
  }

  final Map<String, UserScript> _store = {};

  @override
  Future<List<UserScript>> getAll() async {
    return _store.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<UserScript?> getById(String id) async => _store[id];

  @override
  Future<void> save(UserScript script) async {
    _store[script.id] = script;
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }
}
