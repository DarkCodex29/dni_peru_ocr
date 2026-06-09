import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DonacionExtractor', () {
    const extractor = DonacionExtractor();

    test('extracts SI after DONACION DE ORGANOS label', () {
      expect(
        extractor.extract('DONACIÓN DE ÓRGANOS\nSI').organDonor,
        'SI',
      );
    });

    test('extracts NO after DONACION DE ORGANOS label', () {
      expect(
        extractor.extract('DONACIÓN DE ÓRGANOS\nNO').organDonor,
        'NO',
      );
    });

    test('works without diacritics (OCR-friendly)', () {
      expect(
        extractor.extract('DONACION DE ORGANOS\nSI').organDonor,
        'SI',
      );
    });

    test('handles colon on same line', () {
      expect(
        extractor.extract('DONACIÓN DE ÓRGANOS: NO').organDonor,
        'NO',
      );
    });

    test('handles short DONACION label alone', () {
      expect(extractor.extract('DONACIÓN\nSI').organDonor, 'SI');
    });

    test('normalizes SÍ with accent to SI', () {
      expect(
        extractor.extract('DONACIÓN DE ÓRGANOS\nSÍ').organDonor,
        'SI',
      );
    });

    test('returns null when label missing', () {
      expect(extractor.extract('hola mundo SI').organDonor, isNull);
    });

    test('returns null when value invalid', () {
      expect(
        extractor.extract('DONACIÓN DE ÓRGANOS\nMAYBE').organDonor,
        isNull,
      );
    });

    test('finds value within 2 lines after label', () {
      expect(
        extractor.extract('DONACIÓN DE ÓRGANOS\n\nSI').organDonor,
        'SI',
      );
    });
  });
}
