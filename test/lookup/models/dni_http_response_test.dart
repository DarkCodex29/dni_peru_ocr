import 'package:flutter_test/flutter_test.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_http_response.dart';

void main() {
  group('DniHttpResponse', () {
    test('construction with statusCode and body', () {
      const response = DniHttpResponse(statusCode: 200, body: '{"success":true}');

      expect(response.statusCode, 200);
      expect(response.body, '{"success":true}');
    });

    test('statusCode and body are accessible as int and String', () {
      const response = DniHttpResponse(statusCode: 404, body: 'Not Found');

      expect(response.statusCode, isA<int>());
      expect(response.body, isA<String>());
    });

    test('500 status with plain text body', () {
      const response = DniHttpResponse(statusCode: 500, body: 'Ocurrió un Error');

      expect(response.statusCode, 500);
      expect(response.body, 'Ocurrió un Error');
    });
  });
}
