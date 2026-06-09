import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SexExtractor', () {
    const extractor = SexExtractor();

    test('extracts M after SEXO label', () {
      expect(extractor.extract('SEXO\nM').sex, 'M');
    });

    test('extracts F after SEXO label', () {
      expect(extractor.extract('SEXO\nF').sex, 'F');
    });

    test('extracts MASCULINO and normalizes to M', () {
      expect(extractor.extract('SEXO\nMASCULINO').sex, 'M');
    });

    test('extracts FEMENINO and normalizes to F', () {
      expect(extractor.extract('SEXO\nFEMENINO').sex, 'F');
    });

    test('handles SEXO with colon and same line', () {
      expect(extractor.extract('SEXO: M').sex, 'M');
    });

    test('handles SEX label (English / OCR truncation)', () {
      expect(extractor.extract('SEX\nM').sex, 'M');
    });

    test('returns null when no SEXO label present', () {
      expect(extractor.extract('Hello').sex, isNull);
    });

    test('returns null when value after label is invalid', () {
      expect(extractor.extract('SEXO\nXYZ').sex, isNull);
    });

    group('Modelo 2020 horizontal layout', () {
      test('extracts M from "M PER" on a single line (DNI 2020 layout)', () {
        expect(extractor.extract('M PER 24 06 1985').sex, 'M');
      });

      test('extracts F from "F PER" on a single line (DNI 2020 layout)', () {
        expect(extractor.extract('F PER 12 03 1990').sex, 'F');
      });

      test('extracts M when SEXO and value are on the same line', () {
        expect(extractor.extract('SEXO M PER 24 06 1985').sex, 'M');
      });

      test('does not match "M" alone without PER (avoid false positives)', () {
        // M alone in a noisy line is NOT enough; we only accept "M PER" or label.
        expect(extractor.extract('MARIA M LOPEZ').sex, isNull);
      });
    });

    group('OCR-tolerant fallback (lone M/F after fuzzy sex label)', () {
      test('extracts F when "Sexo" line is misread as "Seve" and F is below',
          () {
        // Real Modelo 2020 OCR fragment.
        const text = '2104 20\nNACINAAD FECHA D A\nSEVE\nF';
        expect(extractor.extract(text).sex, 'F');
      });

      test('extracts M when label is misread as "SXO" and M is below', () {
        const text = 'SXO\nM';
        expect(extractor.extract(text).sex, 'M');
      });

      test('does NOT match a lone F without any sex-like label above', () {
        const text = 'GOICOCHEA PEREZ\nF\nODETTE';
        expect(extractor.extract(text).sex, isNull);
      });
    });
  });
}
