import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UbigeoNacimientoExtractor', () {
    const extractor = UbigeoNacimientoExtractor();

    test('extracts 6-digit code after UBIGEO DE NACIMIENTO label', () {
      expect(
        extractor.extract('UBIGEO DE NACIMIENTO\n150101').birthUbigeoCode,
        '150101',
      );
    });

    test('handles UBIGEO NACIMIENTO without DE', () {
      expect(
        extractor.extract('UBIGEO NACIMIENTO\n130101').birthUbigeoCode,
        '130101',
      );
    });

    test('handles abbreviated UB NACIMIENTO', () {
      expect(
        extractor.extract('UB. NACIMIENTO\n040501').birthUbigeoCode,
        '040501',
      );
    });

    test('keeps leading zeros', () {
      expect(
        extractor.extract('UBIGEO DE NACIMIENTO\n010203').birthUbigeoCode,
        '010203',
      );
    });

    test('handles colon on same line', () {
      expect(
        extractor.extract('UBIGEO DE NACIMIENTO: 150101').birthUbigeoCode,
        '150101',
      );
    });

    test('returns null when no birth ubigeo label present', () {
      // Lone UBIGEO label (domicile) must NOT match; that is the other extractor.
      expect(
        extractor.extract('UBIGEO\n150101').birthUbigeoCode,
        isNull,
      );
    });

    test('returns null when value not exactly 6 digits', () {
      expect(
        extractor.extract('UBIGEO DE NACIMIENTO\n12345').birthUbigeoCode,
        isNull,
      );
      expect(
        extractor.extract('UBIGEO DE NACIMIENTO\n1234567').birthUbigeoCode,
        isNull,
      );
    });

    test('finds value within 2 lines after label', () {
      expect(
        extractor.extract('UBIGEO DE NACIMIENTO\n\n150101').birthUbigeoCode,
        '150101',
      );
    });

    test('returns null when label missing entirely', () {
      expect(extractor.extract('hola 150101 mundo').birthUbigeoCode, isNull);
    });
  });
}
