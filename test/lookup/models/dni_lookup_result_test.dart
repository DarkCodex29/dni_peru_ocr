import 'package:flutter_test/flutter_test.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';

void main() {
  group('DniLookupResult', () {
    group('exhaustive switch compiles without default', () {
      test('switch expression covers all 6 variants without default', () {
        const results = <DniLookupResult>[
          DniLookupSuccess(DniData(
            dni: '43005787',
            nombres: 'JUAN',
            apellidoPaterno: 'GARCIA',
            apellidoMaterno: 'LOPEZ',
            nombreCompleto: 'GARCIA LOPEZ JUAN',
          )),
          DniLookupNotFound(),
          DniLookupRateLimited(),
          DniLookupNetworkError(),
          DniLookupInvalidToken(),
          DniLookupServerError(statusCode: 500),
        ];

        for (final result in results) {
          final label = switch (result) {
            DniLookupSuccess() => 'success',
            DniLookupNotFound() => 'not_found',
            DniLookupRateLimited() => 'rate_limited',
            DniLookupNetworkError() => 'network_error',
            DniLookupInvalidToken() => 'invalid_token',
            DniLookupServerError() => 'server_error',
          };
          expect(label, isNotEmpty);
        }
      });
    });

    group('RateLimited', () {
      test('carries retryAfterSeconds when present', () {
        const result = DniLookupRateLimited(retryAfterSeconds: 30);
        expect(result.retryAfterSeconds, 30);
      });

      test('retryAfterSeconds is null when not present', () {
        const result = DniLookupRateLimited();
        expect(result.retryAfterSeconds, isNull);
      });
    });

    group('NetworkError', () {
      test('carries cause when present', () {
        const result = DniLookupNetworkError(cause: 'Connection refused');
        expect(result.cause, 'Connection refused');
      });

      test('cause is null when not provided', () {
        const result = DniLookupNetworkError();
        expect(result.cause, isNull);
      });
    });

    group('ServerError', () {
      test('carries required statusCode and optional body', () {
        const result = DniLookupServerError(statusCode: 500, body: 'Internal');
        expect(result.statusCode, 500);
        expect(result.body, 'Internal');
      });

      test('body is null when not provided', () {
        const result = DniLookupServerError(statusCode: 503);
        expect(result.statusCode, 503);
        expect(result.body, isNull);
      });
    });

    group('Success', () {
      test('carries DniData', () {
        const data = DniData(
          dni: '43005787',
          nombres: 'JUAN',
          apellidoPaterno: 'GARCIA',
          apellidoMaterno: 'LOPEZ',
          nombreCompleto: 'GARCIA LOPEZ JUAN',
        );
        const result = DniLookupSuccess(data);
        expect(result.data.dni, '43005787');
      });
    });
  });
}
