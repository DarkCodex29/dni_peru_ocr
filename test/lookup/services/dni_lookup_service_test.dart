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
      final result = await service.lookup('43005787');
      expect(result, isA<DniLookupResult>());
    });

    test('successful lookup returns DniLookupSuccess with populated DniData', () async {
      final service = _FakeLookupService();
      final result = await service.lookup('43005787');

      expect(result, isA<DniLookupSuccess>());
      final success = result as DniLookupSuccess;
      expect(success.data.dni, '43005787');
    });

    test('implementation can return DniLookupNotFound', () async {
      final service = _NotFoundService();
      final result = await service.lookup('00000000');
      expect(result, isA<DniLookupNotFound>());
    });

    test('network failure does not throw — returns DniLookupNetworkError', () async {
      final service = _NetworkErrorService();
      final result = await service.lookup('43005787');

      expect(result, isA<DniLookupNetworkError>());
      final error = result as DniLookupNetworkError;
      expect(error.cause, isNotNull);
    });

    test('interface can be implemented via implements keyword', () {
      final DniLookupService service = _FakeLookupService();
      expect(service, isA<DniLookupService>());
    });
  });
}
