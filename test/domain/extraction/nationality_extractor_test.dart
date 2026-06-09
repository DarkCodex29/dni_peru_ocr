import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NationalityExtractor', () {
    const extractor = NationalityExtractor();

    test('extracts PERUANA after NACIONALIDAD', () {
      expect(extractor.extract('NACIONALIDAD\nPERUANA').nationality, 'PERUANA');
    });

    test('extracts PER (MRZ short form) after NACIONALIDAD', () {
      expect(extractor.extract('NACIONALIDAD\nPER').nationality, 'PERUANA');
    });

    test('extracts inline NACIONALIDAD: PERUANA', () {
      expect(
        extractor.extract('NACIONALIDAD: PERUANA').nationality,
        'PERUANA',
      );
    });

    test('returns null when no NACIONALIDAD label', () {
      expect(extractor.extract('Random text').nationality, isNull);
    });

    group('Modelo 2020 horizontal layout', () {
      test('extracts PERUANA from "M PER" inline (no NACIONALIDAD label)', () {
        expect(
          extractor.extract('M PER 24 06 1985').nationality,
          'PERUANA',
        );
      });

      test('extracts PERUANA from "F PER" inline', () {
        expect(
          extractor.extract('F PER 12 03 1990').nationality,
          'PERUANA',
        );
      });

      test('extracts PERUANA from "SEXO M PER ..." inline', () {
        expect(
          extractor.extract('SEXO M PER 24 06 1985').nationality,
          'PERUANA',
        );
      });

      test('does not match PER inside a longer word (PEREZ)', () {
        expect(extractor.extract('PEREZ MARIA').nationality, isNull);
      });
    });
  });
}
