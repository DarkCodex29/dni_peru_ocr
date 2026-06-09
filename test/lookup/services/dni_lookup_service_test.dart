import 'package:flutter_test/flutter_test.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/services/dni_lookup_service.dart';

final class _FakeLookupService implements DniLookupService {
  @override
  Future<DniLookupResult> lookup(String dni) async {
    return DniLookupSuccess(DniData(
      dni: dni,
      nombres: 'JUAN',
      apellidoPaterno: 'GARCIA',
      apellidoMaterno: 'LOPEZ',
      nombreCompleto: 'GARCIA LOPEZ JUAN',
    ));
  }
}

final class _NotFoundService implements DniLookupService {
  @override
  Future<DniLookupResult> lookup(String dni) async {
    return const DniLookupNotFound();
  }
}

final class _NetworkErrorService implements DniLookupService {
  @override
  Future<DniLookupResult> lookup(String dni) async {
    return const DniLookupNetworkError(cause: 'Connection refused');
  }
}

void main() {
  group('DniLookupService contract', () {
    test('lookup signature returns Future<DniLookupResult>', () async {
      final service = _FakeLookupService();
      // Statically typed Future<DniLookupResult>: awaiting yields a non-null
      // sealed variant. Verify the call actually completes with a value.
      final result = await service.lookup('43005787');
      expect(result, isNotNull);
    });

    test('successful lookup returns DniLookupSuccess with populated DniData', () async {
      final service = _FakeLookupService();
      final result = await service.lookup('43005787');

      expect(
        result,
        isA<DniLookupSuccess>()
            .having((s) => s.data.dni, 'data.dni', '43005787'),
      );
    });

    test('implementation can return DniLookupNotFound', () async {
      final service = _NotFoundService();
      final result = await service.lookup('00000000');
      expect(result, isA<DniLookupNotFound>());
    });

    test('network failure does not throw — returns DniLookupNetworkError', () async {
      final service = _NetworkErrorService();
      final result = await service.lookup('43005787');

      expect(
        result,
        isA<DniLookupNetworkError>()
            .having((e) => e.cause, 'cause', isNotNull),
      );
    });

    test('interface can be implemented via implements keyword', () async {
      // Static typing already proves _FakeLookupService implements
      // DniLookupService — this assignment wouldn't compile otherwise.
      // Strengthen by actually invoking the interface and asserting behavior.
      final DniLookupService service = _FakeLookupService();
      final result = await service.lookup('43005787');
      expect(
        result,
        isA<DniLookupSuccess>()
            .having((s) => s.data.dni, 'data.dni', equals('43005787')),
      );
    });
  });
}
