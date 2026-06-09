import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StateCivilExtractor', () {
    const extractor = StateCivilExtractor();

    test('extracts SOLTERO after ESTADO CIVIL label', () {
      expect(extractor.extract('ESTADO CIVIL\nSOLTERO').stateCivil, 'SOLTERO');
    });

    test('extracts CASADO after ESTADO CIVIL label', () {
      expect(extractor.extract('ESTADO CIVIL\nCASADO').stateCivil, 'CASADO');
    });

    test('extracts DIVORCIADO after ESTADO CIVIL label', () {
      expect(
        extractor.extract('ESTADO CIVIL\nDIVORCIADO').stateCivil,
        'DIVORCIADO',
      );
    });

    test('extracts VIUDO after ESTADO CIVIL label', () {
      expect(extractor.extract('ESTADO CIVIL\nVIUDO').stateCivil, 'VIUDO');
    });

    test('extracts CONVIVIENTE after ESTADO CIVIL label', () {
      expect(
        extractor.extract('ESTADO CIVIL\nCONVIVIENTE').stateCivil,
        'CONVIVIENTE',
      );
    });

    test('normalizes SOLTERA to SOLTERO', () {
      expect(extractor.extract('ESTADO CIVIL\nSOLTERA').stateCivil, 'SOLTERO');
    });

    test('normalizes CASADA to CASADO', () {
      expect(extractor.extract('ESTADO CIVIL\nCASADA').stateCivil, 'CASADO');
    });

    test('normalizes DIVORCIADA to DIVORCIADO', () {
      expect(
        extractor.extract('ESTADO CIVIL\nDIVORCIADA').stateCivil,
        'DIVORCIADO',
      );
    });

    test('normalizes VIUDA to VIUDO', () {
      expect(extractor.extract('ESTADO CIVIL\nVIUDA').stateCivil, 'VIUDO');
    });

    test('handles ESTADO CIVIL with colon and same line', () {
      expect(
        extractor.extract('ESTADO CIVIL: DIVORCIADO').stateCivil,
        'DIVORCIADO',
      );
    });

    test('handles abbreviated EST. CIVIL label', () {
      expect(extractor.extract('EST. CIVIL\nCASADO').stateCivil, 'CASADO');
    });

    test('handles ESTADO label alone followed by valid value', () {
      expect(
        extractor.extract('ESTADO\nSOLTERO\nOTRO TEXTO').stateCivil,
        'SOLTERO',
      );
    });

    test('returns null when no ESTADO CIVIL label present', () {
      expect(extractor.extract('Hello world').stateCivil, isNull);
    });

    test('returns null when value after label is invalid', () {
      expect(extractor.extract('ESTADO CIVIL\nXYZ').stateCivil, isNull);
    });

    test('finds value within 2 lines after label', () {
      expect(
        extractor.extract('ESTADO CIVIL\n\nDIVORCIADO').stateCivil,
        'DIVORCIADO',
      );
    });

    test('handles diacritics on value side (CONVIVIÉNTE)', () {
      expect(
        extractor.extract('ESTADO CIVIL\nCONVIVIÉNTE').stateCivil,
        'CONVIVIENTE',
      );
    });

    group('Modelo 2020 inverted layout (value BEFORE label)', () {
      test('extracts SOLTERA when value sits 1 line above ESTADO CIVIL', () {
        const text = 'SOLTERA\nESTADO CIVIL\nNEXT';
        expect(extractor.extract(text).stateCivil, 'SOLTERO');
      });

      test('extracts CASADO when value sits 2 lines above ESTADO CIVIL', () {
        const text = 'CASADO\n\nESTADO CIVIL\nNEXT';
        expect(extractor.extract(text).stateCivil, 'CASADO');
      });
    });

    group('unique-token fallback (no label visible at all)', () {
      test('claims SOLTERA on its own line without any nearby label', () {
        // Real Modelo 2020 OCR fragment after the label is out of frame.
        const text = '21 04\nSOLTERA\n25 08 2031';
        expect(extractor.extract(text).stateCivil, 'SOLTERO');
      });

      test('does NOT claim a substring inside a longer line', () {
        // "SOLTERA" inside a noisy line should not be claimed (must be the
        // entire line).
        const text = 'NOTA SOLTERA INVALIDA';
        expect(extractor.extract(text).stateCivil, isNull);
      });

      test('does NOT claim arbitrary words', () {
        const text = 'PEPE\nJUAN\nMARIA';
        expect(extractor.extract(text).stateCivil, isNull);
      });
    });

    group('single-letter values (azul booklet)', () {
      test('S after ESTADO CIVIL becomes SOLTERO', () {
        expect(extractor.extract('ESTADO CIVIL\nS').stateCivil, 'SOLTERO');
      });

      test('C after ESTADO CIVIL becomes CASADO', () {
        expect(extractor.extract('ESTADO CIVIL\nC').stateCivil, 'CASADO');
      });

      test('D after ESTADO CIVIL becomes DIVORCIADO', () {
        expect(
          extractor.extract('ESTADO CIVIL\nD').stateCivil,
          'DIVORCIADO',
        );
      });

      test('V after ESTADO CIVIL becomes VIUDO', () {
        expect(extractor.extract('ESTADO CIVIL\nV').stateCivil, 'VIUDO');
      });

      test('CV after ESTADO CIVIL becomes CONVIVIENTE', () {
        expect(
          extractor.extract('ESTADO CIVIL\nCV').stateCivil,
          'CONVIVIENTE',
        );
      });

      test('Estado Civil S inline (azul booklet horizontal layout)', () {
        expect(extractor.extract('ESTADO CIVIL S').stateCivil, 'SOLTERO');
      });

      test('Sexo F Estado Civil S adjacency (real azul booklet OCR)', () {
        expect(
          extractor.extract('SEXO F ESTADO CIVIL S').stateCivil,
          'SOLTERO',
        );
      });

      test('does NOT claim a lone S without ESTADO CIVIL nearby', () {
        // Avoid stealing initials from names ("SONIA S LOPEZ").
        expect(extractor.extract('SONIA S LOPEZ').stateCivil, isNull);
      });
    });
  });
}
