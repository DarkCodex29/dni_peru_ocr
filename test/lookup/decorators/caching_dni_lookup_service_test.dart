import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/lookup/cache/dni_cache.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/services/dni_lookup_service.dart';
import 'package:dni_peru_ocr/src/lookup/decorators/caching_dni_lookup_service.dart';

final class _FakeService implements DniLookupService {
  _FakeService(this._result);

  final DniLookupResult _result;
  int callCount = 0;

  @override
  Future<DniLookupResult> lookup(String dni) async {
    callCount++;
    return _result;
  }
}

final class _FakeCache implements DniCache {
  DniData? stored;
  int getCalls = 0;
  int setCalls = 0;
  int evictCalls = 0;

  @override
  Future<DniData?> get(String dni) async {
    getCalls++;
    return stored;
  }

  @override
  Future<void> set(String dni, DniData data) async {
    setCalls++;
    stored = data;
  }

  @override
  Future<void> evict(String dni) async {
    evictCalls++;
    stored = null;
  }
}

DniData _sampleData(String dni) => DniData(
      dni: dni,
      nombres: 'JUAN CARLOS',
      apellidoPaterno: 'PEREZ',
      apellidoMaterno: 'GARCIA',
      nombreCompleto: 'PEREZ GARCIA JUAN CARLOS',
    );

void main() {
  group('CachingDniLookupService', () {
    test('cache hit returns cached value without calling delegate', () async {
      final data = _sampleData('43005787');
      final cache = _FakeCache()..stored = data;
      final delegate = _FakeService(const DniLookupNotFound());
      final service = CachingDniLookupService(
        delegate: delegate,
        cache: cache,
      );

      final result = await service.lookup('43005787');

      expect(
        result,
        isA<DniLookupSuccess>()
            .having((s) => s.data.dni, 'data.dni', equals('43005787')),
      );
      expect(delegate.callCount, equals(0));
    });

    test('cache miss calls delegate and stores Success in cache', () async {
      final data = _sampleData('43005787');
      final cache = _FakeCache();
      final delegate = _FakeService(DniLookupSuccess(data));
      final service = CachingDniLookupService(
        delegate: delegate,
        cache: cache,
      );

      final result = await service.lookup('43005787');

      expect(
        result,
        isA<DniLookupSuccess>()
            .having((s) => s.data.dni, 'data.dni', equals('43005787')),
      );
      expect(delegate.callCount, equals(1));
      expect(cache.setCalls, equals(1));
      expect(cache.stored, equals(data));
    });

    test('non-Success result is not cached', () async {
      final cache = _FakeCache();
      final delegate = _FakeService(const DniLookupNotFound());
      final service = CachingDniLookupService(
        delegate: delegate,
        cache: cache,
      );

      final result = await service.lookup('43005787');

      expect(result, isA<DniLookupNotFound>());
      expect(cache.setCalls, equals(0));
      expect(cache.stored, isNull);
    });

    test('TTL expiry evicts and re-fetches from delegate', () async {
      final data = _sampleData('43005787');
      final cache = _FakeCache()..stored = data;
      final delegate = _FakeService(DniLookupSuccess(data));
      final service = CachingDniLookupService(
        delegate: delegate,
        cache: cache,
        ttl: const Duration(milliseconds: 1),
      );

      await service.lookup('43005787');

      await Future<void>.delayed(const Duration(milliseconds: 10));

      delegate.callCount = 0;
      cache.setCalls = 0;
      cache.evictCalls = 0;
      cache.stored = data;

      final result = await service.lookup('43005787');

      expect(result, isA<DniLookupSuccess>());
      expect(delegate.callCount, equals(1));
      expect(cache.evictCalls, equals(1));
      expect(cache.setCalls, equals(1));
    });

    test('null TTL means cached value never expires', () async {
      final data = _sampleData('43005787');
      final cache = _FakeCache()..stored = data;
      final delegate = _FakeService(const DniLookupNetworkError());
      final service = CachingDniLookupService(
        delegate: delegate,
        cache: cache,
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      final result = await service.lookup('43005787');

      expect(result, isA<DniLookupSuccess>());
      expect(delegate.callCount, equals(0));
    });
  });
}
