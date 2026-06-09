import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr_example/lookup/in_memory_dni_cache.dart';

void main() {
  group('InMemoryDniCache', () {
    late InMemoryDniCache cache;
    late DniData sampleData;

    setUp(() {
      cache = InMemoryDniCache();
      sampleData = const DniData(
        dni: '43005787',
        nombres: 'JUAN CARLOS',
        apellidoPaterno: 'MUÑOZ',
        apellidoMaterno: 'PEREZ',
        nombreCompleto: 'MUÑOZ PEREZ JUAN CARLOS',
      );
    });

    test('get returns null when entry does not exist', () async {
      final result = await cache.get('43005787');
      expect(result, isNull);
    });

    test('set then get returns stored data', () async {
      await cache.set('43005787', sampleData);
      final result = await cache.get('43005787');
      expect(result, equals(sampleData));
      expect(result!.nombreCompleto, equals('MUÑOZ PEREZ JUAN CARLOS'));
    });

    test('evict removes entry so subsequent get returns null', () async {
      await cache.set('43005787', sampleData);
      await cache.evict('43005787');
      final result = await cache.get('43005787');
      expect(result, isNull);
    });
  });
}
