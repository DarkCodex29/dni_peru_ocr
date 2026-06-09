import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DateFieldExtractor', () {
    const extractor = DateFieldExtractor();

    test('extracts birth date with NACIMIENTO label', () {
      const text = 'FECHA DE NACIMIENTO\n04 12 1976';
      final result = extractor.extract(text);
      expect(result.dateOfBirth, '04/12/1976');
    });

    test('extracts expiration date with CADUCIDAD label', () {
      const text = 'FECHA DE CADUCIDAD\n18 11 2029';
      final result = extractor.extract(text);
      expect(result.expirationDate, '18/11/2029');
    });

    test('extracts emission date with EMISION label (separate field)', () {
      const text = 'FECHA DE EMISION\n18 11 2021';
      final result = extractor.extract(text);
      expect(result.emissionDate, '18/11/2021');
      expect(result.dateOfBirth, isNull);
      expect(result.expirationDate, isNull);
    });

    test('extracts inscription date with INSCRIPCION label (separate)', () {
      const text = 'FECHA DE INSCRIPCION\n27 01 2000';
      final result = extractor.extract(text);
      expect(result.inscriptionDate, '27/01/2000');
      expect(result.dateOfBirth, isNull);
    });

    test('extracts all 4 dates from full DNI text', () {
      const text =
          'FECHA INSCRIPCION\n27 01 2000\n'
          'FECHA EMISION\n18 11 2021\n'
          'FECHA NACIMIENTO\n04 12 1976\n'
          'FECHA CADUCIDAD\n18 11 2029';
      final result = extractor.extract(text);
      expect(result.inscriptionDate, '27/01/2000');
      expect(result.emissionDate, '18/11/2021');
      expect(result.dateOfBirth, '04/12/1976');
      expect(result.expirationDate, '18/11/2029');
    });

    test('returns nulls when no dates present', () {
      final result = extractor.extract('Hello world');
      expect(result.dateOfBirth, isNull);
      expect(result.expirationDate, isNull);
      expect(result.emissionDate, isNull);
      expect(result.inscriptionDate, isNull);
    });

    test('rejects invalid date with day > 31', () {
      const text = 'FECHA DE NACIMIENTO\n45 12 1990';
      expect(extractor.extract(text).dateOfBirth, isNull);
    });

    group('Modelo 2020 horizontal layout', () {
      test('extracts emission date with trailing 10-digit card number', () {
        // "Fecha emisión 03 05 2022 0200869805" — date + card on same line
        const text = 'FECHA EMISIÓN 03 05 2022 0200869805';
        final result = extractor.extract(text);
        expect(result.emissionDate, '03/05/2022');
      });

      test('extracts emission date with trailing 6-digit voting group', () {
        const text = 'FECHA EMISIÓN 03 05 2022 255123';
        final result = extractor.extract(text);
        expect(result.emissionDate, '03/05/2022');
      });

      test('extracts birth date from "M PER 24 06 1985" inline', () {
        // Horizontal DNI 2020: no NACIMIENTO label, but date follows "M PER".
        const text = 'M PER 24 06 1985';
        final result = extractor.extract(text);
        expect(result.dateOfBirth, '24/06/1985');
      });

      test('does not mis-assign birth as emission on horizontal line', () {
        const text = 'M PER 24 06 1985';
        final result = extractor.extract(text);
        expect(result.emissionDate, isNull);
        expect(result.expirationDate, isNull);
        expect(result.inscriptionDate, isNull);
      });

      test('reads birth when value comes BEFORE label (real Modelo 2020)', () {
        // Real OCR order: value first, label after — opposite of azul booklet.
        const text =
            '21 04 2004\n'
            'NACIONALIDAD FECHA DE NACIMIENTO';
        expect(extractor.extract(text).dateOfBirth, '21/04/2004');
      });

      test('reads emission when value comes BEFORE label', () {
        const text =
            '03 05 2022\n'
            'FECHA DE EMISIÓN';
        expect(extractor.extract(text).emissionDate, '03/05/2022');
      });

      test('reads inscription when value comes BEFORE label', () {
        const text =
            '27 01 2000\n'
            'FECHA DE INSCRIPCIÓN';
        expect(extractor.extract(text).inscriptionDate, '27/01/2000');
      });
    });
  });
}
