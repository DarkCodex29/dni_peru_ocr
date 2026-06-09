import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/lookup/http/dni_http_client.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_http_response.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/services/apis_peru_lookup_service.dart';

final class _FakeHttpClient implements DniHttpClient {
  _FakeHttpClient(this._response);

  final DniHttpResponse _response;

  @override
  Future<DniHttpResponse> get(Uri uri, {Map<String, String>? headers}) async =>
      _response;
}

final class _ThrowingHttpClient implements DniHttpClient {
  @override
  Future<DniHttpResponse> get(Uri uri, {Map<String, String>? headers}) async =>
      throw const SocketException('Connection refused');
}

String _fixture(String name) {
  return File('test/lookup/fixtures/$name').readAsStringSync();
}

void main() {
  group('ApisPeruLookupService', () {
    test('HTTP 200 success:true returns DniLookupSuccess with DniData', () async {
      final body = _fixture('apis_peru_success.json');
      final service = ApisPeruLookupService(
        token: 'valid-token',
        client: _FakeHttpClient(DniHttpResponse(statusCode: 200, body: body)),
      );

      final result = await service.lookup('43005787');

      expect(
        result,
        isA<DniLookupSuccess>()
            .having((s) => s.data.dni, 'data.dni', equals('43005787'))
            .having((s) => s.data.nombres, 'data.nombres', equals('JUAN CARLOS'))
            .having(
              (s) => s.data.apellidoPaterno,
              'data.apellidoPaterno',
              equals('GARCIA'),
            )
            .having(
              (s) => s.data.apellidoMaterno,
              'data.apellidoMaterno',
              equals('LOPEZ'),
            ),
      );
    });

    test('HTTP 200 success:false returns DniLookupNotFound', () async {
      final body = _fixture('apis_peru_not_found.json');
      final service = ApisPeruLookupService(
        token: 'valid-token',
        client: _FakeHttpClient(DniHttpResponse(statusCode: 200, body: body)),
      );

      final result = await service.lookup('99999999');

      expect(result, isA<DniLookupNotFound>());
    });

    test('HTTP 500 non-JSON body returns DniLookupInvalidToken without throwing', () async {
      final body = _fixture('apis_peru_invalid_token_500.txt');
      final service = ApisPeruLookupService(
        token: 'invalid-token',
        client: _FakeHttpClient(DniHttpResponse(statusCode: 500, body: body)),
      );

      final result = await service.lookup('43005787');

      expect(result, isA<DniLookupInvalidToken>());
    });

    test('transport exception returns DniLookupNetworkError with non-null cause', () async {
      final service = ApisPeruLookupService(
        token: 'valid-token',
        client: _ThrowingHttpClient(),
      );

      final result = await service.lookup('43005787');

      expect(
        result,
        isA<DniLookupNetworkError>()
            .having((e) => e.cause, 'cause', isNotNull),
      );
    });

    test('includeRaw:true populates DniData.raw with original response fields', () async {
      final body = _fixture('apis_peru_success.json');
      final service = ApisPeruLookupService(
        token: 'valid-token',
        client: _FakeHttpClient(DniHttpResponse(statusCode: 200, body: body)),
        includeRaw: true,
      );

      final result = await service.lookup('43005787');

      expect(
        result,
        isA<DniLookupSuccess>()
            .having((s) => s.data.raw, 'data.raw', isNotNull)
            .having(
              (s) => s.data.raw,
              'data.raw',
              containsPair('success', true),
            ),
      );
    });

    test('HTTP 429 returns DniLookupRateLimited', () async {
      final service = ApisPeruLookupService(
        token: 'valid-token',
        client: _FakeHttpClient(
          const DniHttpResponse(statusCode: 429, body: ''),
        ),
      );

      final result = await service.lookup('43005787');

      expect(result, isA<DniLookupRateLimited>());
    });
  });
}
