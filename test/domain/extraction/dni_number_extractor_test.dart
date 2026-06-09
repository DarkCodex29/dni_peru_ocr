import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DniNumberExtractor', () {
    const extractor = DniNumberExtractor();

    test('extracts 8-digit number after DNI label', () {
      final result = extractor.extract('DNI 12345678');
      expect(result.documentNumber, '12345678');
    });

    test('extracts when DNI label has trailing colon', () {
      final result = extractor.extract('DNI: 12345678');
      expect(result.documentNumber, '12345678');
    });

    test('extracts when DNI sticks to number without space', () {
      final result = extractor.extract('DNI12345678');
      expect(result.documentNumber, '12345678');
    });

    test('extracts isolated 8-digit number when no DNI label', () {
      final result = extractor.extract('Some text 87654321 more text');
      expect(result.documentNumber, '87654321');
    });

    test('extracts from real OCR sample', () {
      const real =
          'DOCUMENTO NACIONAL DE IDENTIDAD DNI 16793105-2 Fecha Inscripción';
      final result = extractor.extract(real);
      expect(result.documentNumber, '16793105');
    });

    test('ignores numbers longer than 8 digits', () {
      final result = extractor.extract('Code 123456789012');
      expect(result.documentNumber, isNull);
    });

    test('ignores numbers shorter than 8 digits', () {
      final result = extractor.extract('Year 2024');
      expect(result.documentNumber, isNull);
    });

    test('returns null when no number present', () {
      final result = extractor.extract('Hello world');
      expect(result.documentNumber, isNull);
    });

    test('returns empty result with all null fields', () {
      final result = extractor.extract('');
      expect(result.documentNumber, isNull);
      expect(result.firstName, isNull);
      expect(result.lastName, isNull);
    });

    test('prefers DNI-labeled number over isolated 8-digit number', () {
      const text = 'Random 87654321 something DNI 12345678 more';
      final result = extractor.extract(text);
      expect(result.documentNumber, '12345678');
    });
  });
}
