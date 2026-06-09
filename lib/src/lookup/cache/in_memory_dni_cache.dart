import '../models/dni_data.dart';
import 'dni_cache.dart';

/// Convenience [DniCache] implementation that keeps entries in a process-local
/// [Map]. Useful for tests, demos, and apps that do not need persistence across
/// process restarts. For production caching across sessions, implement
/// [DniCache] backed by `shared_preferences`, Hive, sqflite, or similar.
class InMemoryDniCache implements DniCache {
  final Map<String, DniData> _store = <String, DniData>{};

  @override
  Future<DniData?> get(String dni) async => _store[dni];

  @override
  Future<void> set(String dni, DniData data) async {
    _store[dni] = data;
  }

  @override
  Future<void> evict(String dni) async {
    _store.remove(dni);
  }
}
