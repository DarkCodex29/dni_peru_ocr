import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/lookup/http/dni_http_client.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_http_response.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/services/reniec_sunat_lookup_service.dart';

String _fixture(String name) {
  return File('test/lookup/fixtures/$name').readAsStringSync();
}

final class _FakeHttpClient implements DniHttpClient {
  _FakeHttpClient(this._response);

  final DniHttpResponse _response;
  Map<String, String>? capturedHeaders;

  @override
  Future<DniHttpResponse> get(Uri uri, {Map<String, String>? headers}) async {
    capturedHeaders = headers;
    return _response;
  }
}

final class _ThrowingHttpClient implements DniHttpClient {
  @override
  Future<DniHttpResponse> get(Uri uri, {Map<String, String>? headers}) async =>
      throw const SocketException('Connection refused');
}

void main() {
  group('ReniecSunatLookupService', () {
    test('response with placeholder ubigeo "-" is preserved in DniData', () async {
      final fakeClient = _FakeHttpClient(
        DniHttpResponse(
          statusCode: 200,
          body: _fixture('reniec_sunat_dashes_placeholder.json'),
        ),
      );
      final service = ReniecSunatLookupService(
        baseUrl: 'https://api.example.com',
        client: fakeClient,
      );

      final result = await service.lookup('43005787');

      expect(
        result,
        isA<DniLookupSuccess>()
            .having((s) => s.data.ubigeo, 'data.ubigeo', equals('-'))
            .having((s) => s.data.departamento, 'data.departamento', equals('-')),
      );
    });

    test('extraHeaders are forwarded to HTTP client', () async {
      final fakeClient = _FakeHttpClient(
        DniHttpResponse(
          statusCode: 200,
          body: _fixture('reniec_sunat_success.json'),
        ),
      );
      final service = ReniecSunatLookupService(
        baseUrl: 'https://api.example.com',
        client: fakeClient,
        extraHeaders: {'X-Custom': 'value'},
      );

      await service.lookup('43005787');

      expect(fakeClient.capturedHeaders, containsPair('X-Custom', 'value'));
    });

    test('no headers sent when extraHeaders is null', () async {
      final fakeClient = _FakeHttpClient(
        DniHttpResponse(
          statusCode: 200,
          body: _fixture('reniec_sunat_success.json'),
        ),
      );
      final service = ReniecSunatLookupService(
        baseUrl: 'https://api.example.com',
        client: fakeClient,
      );

      await service.lookup('43005787');

      expect(fakeClient.capturedHeaders, isNull);
    });

    test('transport exception returns DniLookupNetworkError', () async {
      final service = ReniecSunatLookupService(
        baseUrl: 'https://api.example.com',
        client: _ThrowingHttpClient(),
      );

      final result = await service.lookup('43005787');

      expect(
        result,
        isA<DniLookupNetworkError>()
            .having((e) => e.cause, 'cause', isNotNull),
      );
    });

    test('HTTP 404 returns DniLookupNotFound', () async {
      final service = ReniecSunatLookupService(
        baseUrl: 'https://api.example.com',
        client: _FakeHttpClient(
          DniHttpResponse(
            statusCode: 404,
            body: _fixture('reniec_sunat_not_found.json'),
          ),
        ),
      );

      final result = await service.lookup('00000000');

      expect(result, isA<DniLookupNotFound>());
    });

    test('HTTP 200 success returns populated DniData', () async {
      final service = ReniecSunatLookupService(
        baseUrl: 'https://api.example.com',
        client: _FakeHttpClient(
          DniHttpResponse(
            statusCode: 200,
            body: _fixture('reniec_sunat_success.json'),
          ),
        ),
      );

      final result = await service.lookup('43005787');

      expect(
        result,
        isA<DniLookupSuccess>()
            .having((s) => s.data.dni, 'data.dni', equals('43005787'))
            .having((s) => s.data.nombres, 'data.nombres', equals('JUAN CARLOS'))
            .having((s) => s.data.ubigeo, 'data.ubigeo', equals('150101'))
            .having(
              (s) => s.data.departamento,
              'data.departamento',
              equals('LIMA'),
            ),
      );
    });

    test('HTTP 429 returns DniLookupRateLimited', () async {
      final service = ReniecSunatLookupService(
        baseUrl: 'https://api.example.com',
        client: _FakeHttpClient(
          const DniHttpResponse(statusCode: 429, body: ''),
        ),
      );

      final result = await service.lookup('43005787');

      expect(result, isA<DniLookupRateLimited>());
    });
  });
}
