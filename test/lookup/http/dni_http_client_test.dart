import 'package:flutter_test/flutter_test.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_http_response.dart';
import 'package:dni_peru_ocr/src/lookup/http/dni_http_client.dart';

final class _FakeHttpClient implements DniHttpClient {
  @override
  Future<DniHttpResponse> get(Uri uri, {Map<String, String>? headers}) async {
    return const DniHttpResponse(statusCode: 200, body: '{"success":true}');
  }
}

final class _HeaderCapturingClient implements DniHttpClient {
  Map<String, String>? capturedHeaders;

  @override
  Future<DniHttpResponse> get(Uri uri, {Map<String, String>? headers}) async {
    capturedHeaders = headers;
    return const DniHttpResponse(statusCode: 200, body: '{}');
  }
}

void main() {
  group('DniHttpClient contract', () {
    test('get returns DniHttpResponse with statusCode and body', () async {
      final client = _FakeHttpClient();
      final response = await client.get(Uri.parse('https://example.com'));

      expect(response, isA<DniHttpResponse>());
      expect(response.statusCode, 200);
      expect(response.body, isNotEmpty);
    });

    test('headers are forwarded to get()', () async {
      final client = _HeaderCapturingClient();
      await client.get(
        Uri.parse('https://example.com'),
        headers: {'Authorization': 'Bearer token123'},
      );

      expect(client.capturedHeaders?['Authorization'], 'Bearer token123');
    });

    test('get can be called without headers', () async {
      final client = _FakeHttpClient();
      final response = await client.get(Uri.parse('https://example.com'));

      expect(response.statusCode, 200);
    });

    test('interface can be implemented via implements keyword', () {
      final DniHttpClient client = _FakeHttpClient();
      expect(client, isA<DniHttpClient>());
    });
  });
}
