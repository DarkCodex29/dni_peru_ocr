import 'package:flutter_test/flutter_test.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';
import 'package:dni_peru_ocr/src/lookup/cache/dni_cache.dart';

final class _InMemoryDniCache implements DniCache {
  final Map<String, DniData> _store = {};

  @override
  Future<DniData?> get(String dni) async => _store[dni];

  @override
  Future<void> set(String dni, DniData data) async => _store[dni] = data;

  @override
  Future<void> evict(String dni) async => _store.remove(dni);
}

void main() {
  group('DniCache contract', () {
    late _InMemoryDniCache cache;

    setUp(() {
      cache = _InMemoryDniCache();
    });

    const testData = DniData(
      dni: '43005787',
      nombres: 'JUAN',
      apellidoPaterno: 'GARCIA',
      apellidoMaterno: 'LOPEZ',
      nombreCompleto: 'GARCIA LOPEZ JUAN',
    );

    test('get returns null on cache miss', () async {
      final result = await cache.get('43005787');
      expect(result, isNull);
    });

    test('set stores DniData and get retrieves it', () async {
      await cache.set('43005787', testData);
      final result = await cache.get('43005787');

      expect(result, isNotNull);
      expect(result!.dni, '43005787');
    });

    test('evict removes entry from cache', () async {
      await cache.set('43005787', testData);
      await cache.evict('43005787');
      final result = await cache.get('43005787');

      expect(result, isNull);
    });

    test('interface can be implemented via implements keyword', () {
      final DniCache dniCache = _InMemoryDniCache();
      expect(dniCache, isA<DniCache>());
    });

    test('cache miss for unknown DNI returns null', () async {
      await cache.set('99999999', testData);
      final result = await cache.get('43005787');
      expect(result, isNull);
    });
  });
}
