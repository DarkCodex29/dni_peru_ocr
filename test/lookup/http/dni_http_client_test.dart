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

      // Response is statically typed DniHttpResponse — assert real fields.
      expect(response.statusCode, equals(200));
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

    test('interface can be implemented via implements keyword', () async {
      // Static typing already proves _FakeHttpClient implements DniHttpClient
      // (this assignment would not compile otherwise). Exercise the interface
      // to assert the contract behaves end-to-end.
      final DniHttpClient client = _FakeHttpClient();
      final response = await client.get(Uri.parse('https://example.com'));
      expect(response.statusCode, equals(200));
      expect(response.body, equals('{"success":true}'));
    });
  });
}
