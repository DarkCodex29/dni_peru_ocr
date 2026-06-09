import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GivenNamesExtractor', () {
    const extractor = GivenNamesExtractor();

    group('e-DNI label (PRE NOMBRES with space)', () {
      test('extracts names after PRE NOMBRES label', () {
        const text = 'PRE NOMBRES\nJUAN CARLOS';
        final result = extractor.extract(text);
        expect(result.firstName, 'JUAN CARLOS');
      });

      test('extracts single name', () {
        const text = 'PRE NOMBRES\nMARIA';
        final result = extractor.extract(text);
        expect(result.firstName, 'MARIA');
      });
    });

    group('DNI azul label (PRENOMBRES one word)', () {
      test('extracts names after PRENOMBRES label', () {
        const text = 'PRENOMBRES\nJUAN CARLOS';
        final result = extractor.extract(text);
        expect(result.firstName, 'JUAN CARLOS');
      });
    });

    group('OCR noise tolerance', () {
      test('handles PRMER NOMBRES (missing accent)', () {
        const text = 'PRMER NOMBRES\nANA';
        final result = extractor.extract(text);
        expect(result.firstName, 'ANA');
      });

      test('handles just NOMBRES label', () {
        const text = 'NOMBRES\nROBERTO';
        final result = extractor.extract(text);
        expect(result.firstName, 'ROBERTO');
      });
    });

    group('edge cases', () {
      test('returns null when no label present', () {
        final result = extractor.extract('Hello world');
        expect(result.firstName, isNull);
      });

      test('ignores value containing digits', () {
        const text = 'PRENOMBRES\nJUAN 123\nSEXO\nM';
        final result = extractor.extract(text);
        expect(result.firstName, isNull);
      });

      test('does not consume next label as name', () {
        const text = 'PRENOMBRES\nSEXO\nM';
        final result = extractor.extract(text);
        expect(result.firstName, isNull);
      });

      test('extracts from real OCR with multi-line context', () {
        const text =
            'SEGUNDO APELLIDO\nMORENO\nPRE NOMBRES\nJOSE CARLOS\nFECHA DE NACIMIENTO';
        final result = extractor.extract(text);
        expect(result.firstName, 'JOSE CARLOS');
      });
    });
  });
}
