import 'package:dni_peru_ocr/dni_peru_ocr.dart';

class InMemoryDniCache implements DniCache {
  final Map<String, DniData> _store = {};

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
