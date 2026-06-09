import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryDniCache', () {
    late InMemoryDniCache cache;

    setUp(() {
      cache = InMemoryDniCache();
    });

    test('get returns null when dni is not cached', () async {
      final result = await cache.get('12345678');
      expect(result, isNull);
    });

    test('set stores entry that get can retrieve', () async {
      const data = DniData(
        dni: '12345678',
        nombres: 'JUAN',
        apellidoPaterno: 'PEREZ',
        apellidoMaterno: 'LOPEZ',
        nombreCompleto: 'JUAN PEREZ LOPEZ',
      );
      await cache.set('12345678', data);
      final retrieved = await cache.get('12345678');
      expect(retrieved, same(data));
    });

    test('evict removes a previously cached entry', () async {
      const data = DniData(
        dni: '12345678',
        nombres: 'JUAN',
        apellidoPaterno: 'PEREZ',
        apellidoMaterno: 'LOPEZ',
        nombreCompleto: 'JUAN PEREZ LOPEZ',
      );
      await cache.set('12345678', data);
      await cache.evict('12345678');
      expect(await cache.get('12345678'), isNull);
    });

    test('evict on missing key is a no-op', () async {
      await cache.evict('00000000');
      expect(await cache.get('00000000'), isNull);
    });

    test('different dnis do not collide', () async {
      const a = DniData(
        dni: '11111111',
        nombres: 'A',
        apellidoPaterno: 'A',
        apellidoMaterno: 'A',
        nombreCompleto: 'A A A',
      );
      const b = DniData(
        dni: '22222222',
        nombres: 'B',
        apellidoPaterno: 'B',
        apellidoMaterno: 'B',
        nombreCompleto: 'B B B',
      );
      await cache.set('11111111', a);
      await cache.set('22222222', b);
      expect(await cache.get('11111111'), same(a));
      expect(await cache.get('22222222'), same(b));
    });

    test('set with same dni overwrites previous entry', () async {
      const first = DniData(
        dni: '12345678',
        nombres: 'A',
        apellidoPaterno: 'A',
        apellidoMaterno: 'A',
        nombreCompleto: 'A A A',
      );
      const second = DniData(
        dni: '12345678',
        nombres: 'B',
        apellidoPaterno: 'B',
        apellidoMaterno: 'B',
        nombreCompleto: 'B B B',
      );
      await cache.set('12345678', first);
      await cache.set('12345678', second);
      expect(await cache.get('12345678'), same(second));
    });
  });
}
