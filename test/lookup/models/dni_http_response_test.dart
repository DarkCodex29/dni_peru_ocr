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

      // Fields are statically typed as int/String — assert real values
      // and that the int participates in arithmetic / the String in concatenation.
      expect(response.statusCode, equals(404));
      expect(response.statusCode + 1, equals(405));
      expect(response.body, equals('Not Found'));
      expect('${response.body}!', equals('Not Found!'));
    });

    test('500 status with plain text body', () {
      const response = DniHttpResponse(statusCode: 500, body: 'Ocurrió un Error');

      expect(response.statusCode, 500);
      expect(response.body, 'Ocurrió un Error');
    });
  });
}
