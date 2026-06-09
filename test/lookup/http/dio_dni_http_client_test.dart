import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/src/lookup/http/dio_dni_http_client.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_http_response.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockDio mockDio;
  late DioDniHttpClient client;

  setUp(() {
    mockDio = _MockDio();
    client = DioDniHttpClient(mockDio);
  });

  group('DioDniHttpClient', () {
    test('returns DniHttpResponse with status and body on success', () async {
      final uri = Uri.parse('https://example.com/api/v1/dni/43005787');
      when(
        () => mockDio.getUri<String>(
          uri,
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<String>(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
          data: '{"success":true}',
        ),
      );

      final response = await client.get(uri);

      // response is statically typed DniHttpResponse — assert real fields.
      expect(response.statusCode, equals(200));
      expect(response.body, equals('{"success":true}'));
    });

    test('returns DniHttpResponse instead of re-throwing DioException', () async {
      final uri = Uri.parse('https://example.com/api/v1/dni/43005787');
      when(
        () => mockDio.getUri<String>(
          uri,
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: uri.toString()),
          type: DioExceptionType.connectionError,
          message: 'Connection refused',
        ),
      );

      final response = await client.get(uri);

      // response is statically typed DniHttpResponse — assert sentinel statusCode 0
      // (encodes "transport failure, no HTTP status") and that the error message
      // is preserved in the body so callers can surface it.
      expect(response.statusCode, equals(0));
      expect(response.body, equals('Connection refused'));
    });

    test('forwards custom headers to Dio request', () async {
      final uri = Uri.parse('https://example.com/api/v1/dni/43005787');
      const headers = {'X-Api-Key': 'secret'};
      when(
        () => mockDio.getUri<String>(
          uri,
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<String>(
          requestOptions: RequestOptions(path: uri.toString()),
          statusCode: 200,
          data: '{"success":true}',
        ),
      );

      await client.get(uri, headers: headers);

      final captured = verify(
        () => mockDio.getUri<String>(
          uri,
          options: captureAny(named: 'options'),
        ),
      ).captured;
      final opts = captured.first as Options;
      expect(opts.headers, containsPair('X-Api-Key', 'secret'));
    });
  });
}
