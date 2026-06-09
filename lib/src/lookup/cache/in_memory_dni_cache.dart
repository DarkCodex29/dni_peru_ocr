import '../models/dni_data.dart';
import 'dni_cache.dart';

/// In-memory [DniCache] implementation backed by a [Map]. No persistence.
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
