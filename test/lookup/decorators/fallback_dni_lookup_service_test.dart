import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/services/dni_lookup_service.dart';
import 'package:dni_peru_ocr/src/lookup/decorators/fallback_dni_lookup_service.dart';

final class _FakeService implements DniLookupService {
  _FakeService(this._results);

  final List<DniLookupResult> _results;
  int callCount = 0;

  @override
  Future<DniLookupResult> lookup(String dni) async {
    final index = callCount;
    callCount++;
    return _results[index < _results.length ? index : _results.length - 1];
  }
}

DniData _sampleData() => const DniData(
      dni: '43005787',
      nombres: 'JUAN',
      apellidoPaterno: 'PEREZ',
      apellidoMaterno: 'GARCIA',
      nombreCompleto: 'PEREZ GARCIA JUAN',
    );

void main() {
  group('FallbackDniLookupService', () {
    test('first service Success returns immediately without calling second', () async {
      final data = _sampleData();
      final first = _FakeService([DniLookupSuccess(data)]);
      final second = _FakeService([const DniLookupNotFound()]);
      final service = FallbackDniLookupService(services: [first, second]);

      final result = await service.lookup('43005787');

      expect(result, isA<DniLookupSuccess>());
      expect((result as DniLookupSuccess).data.dni, equals('43005787'));
      expect(first.callCount, equals(1));
      expect(second.callCount, equals(0));
    });

    test('NetworkError in first triggers fallback to second service', () async {
      final data = _sampleData();
      final first = _FakeService([const DniLookupNetworkError(cause: 'timeout')]);
      final second = _FakeService([DniLookupSuccess(data)]);
      final service = FallbackDniLookupService(services: [first, second]);

      final result = await service.lookup('43005787');

      expect(result, isA<DniLookupSuccess>());
      expect((result as DniLookupSuccess).data.dni, equals('43005787'));
      expect(first.callCount, equals(1));
      expect(second.callCount, equals(1));
    });

    test('InvalidToken in first stops chain — second is never called', () async {
      final first = _FakeService([const DniLookupInvalidToken()]);
      final second = _FakeService([const DniLookupNotFound()]);
      final service = FallbackDniLookupService(services: [first, second]);

      final result = await service.lookup('43005787');

      expect(result, isA<DniLookupInvalidToken>());
      expect(first.callCount, equals(1));
      expect(second.callCount, equals(0));
    });

    test('all services fail — returns last error', () async {
      final first = _FakeService([const DniLookupNetworkError(cause: 'first-fail')]);
      final second = _FakeService([const DniLookupServerError(statusCode: 503)]);
      final service = FallbackDniLookupService(services: [first, second]);

      final result = await service.lookup('43005787');

      expect(result, isA<DniLookupServerError>());
      expect((result as DniLookupServerError).statusCode, equals(503));
      expect(first.callCount, equals(1));
      expect(second.callCount, equals(1));
    });

    test('defaultRetryOn returns true for NetworkError', () {
      expect(FallbackDniLookupService.defaultRetryOn(const DniLookupNetworkError()), isTrue);
    });

    test('defaultRetryOn returns true for ServerError', () {
      expect(FallbackDniLookupService.defaultRetryOn(const DniLookupServerError(statusCode: 500)), isTrue);
    });

    test('defaultRetryOn returns false for InvalidToken', () {
      expect(FallbackDniLookupService.defaultRetryOn(const DniLookupInvalidToken()), isFalse);
    });

    test('defaultRetryOn returns false for NotFound', () {
      expect(FallbackDniLookupService.defaultRetryOn(const DniLookupNotFound()), isFalse);
    });

    test('defaultRetryOn returns false for RateLimited', () {
      expect(FallbackDniLookupService.defaultRetryOn(const DniLookupRateLimited()), isFalse);
    });

    test('empty services list throws AssertionError', () {
      expect(
        () => FallbackDniLookupService(services: const []),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
