import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DocumentSideDetector', () {
    const detector = DocumentSideDetector();

    group('front anchors (any one is enough)', () {
      test('CUI alone marks front (Modelo 2020)', () {
        expect(detector.detect('CUI 1234567890'), DocumentSide.front);
      });

      test('DNI + 8 digits marks front (azul booklet)', () {
        expect(detector.detect('DNI 16793105'), DocumentSide.front);
      });

      test('DNI + 8 digits + check digit marks front', () {
        expect(detector.detect('DNI 16793105-2'), DocumentSide.front);
      });

      test('REPUBLICA DEL PERU marks front', () {
        expect(detector.detect('REPÚBLICA DEL PERÚ'), DocumentSide.front);
      });

      test('REPUBLICA DEL PERU without diacritics marks front', () {
        expect(detector.detect('REPUBLICA DEL PERU'), DocumentSide.front);
      });

      test('DOCUMENTO NACIONAL DE IDENTIDAD marks front', () {
        expect(
          detector.detect('DOCUMENTO NACIONAL DE IDENTIDAD'),
          DocumentSide.front,
        );
      });

      test('REGISTRO NACIONAL DE IDENTIFICACION marks front', () {
        expect(
          detector.detect('REGISTRO NACIONAL DE IDENTIFICACIÓN'),
          DocumentSide.front,
        );
      });
    });

    group('back anchors', () {
      test('DONACION DE ORGANOS marks back (universal)', () {
        expect(
          detector.detect('DONACIÓN DE ÓRGANOS'),
          DocumentSide.back,
        );
      });

      test('DONACION without diacritics marks back', () {
        expect(detector.detect('DONACION DE ORGANOS'), DocumentSide.back);
      });

      test('CONSTANCIA DE SUFRAGIO marks back (azul booklet)', () {
        expect(
          detector.detect('CONSTANCIA DE SUFRAGIO'),
          DocumentSide.back,
        );
      });
    });

    group('back wins over front when both anchors present', () {
      test('DONACIÓN beats CUI in the same frame', () {
        const both = 'CUI 1234567 DONACIÓN DE ÓRGANOS';
        expect(detector.detect(both), DocumentSide.back);
      });

      test('CONSTANCIA SUFRAGIO beats DNI in the same frame', () {
        const both = 'DNI 16793105 CONSTANCIA DE SUFRAGIO';
        expect(detector.detect(both), DocumentSide.back);
      });
    });

    group('unknown', () {
      test('returns unknown for empty text', () {
        expect(detector.detect(''), DocumentSide.unknown);
      });

      test('returns unknown for random text', () {
        expect(detector.detect('Hello world'), DocumentSide.unknown);
      });

      test('returns unknown for short numeric strings', () {
        expect(detector.detect('1234'), DocumentSide.unknown);
      });

      test('returns unknown when only MRZ line is present', () {
        // MRZ can appear on front OR back depending on DNI generation.
        expect(
          detector.detect('I<PER1234567890<<<<<<<<<<<<<<<'),
          DocumentSide.unknown,
        );
      });
    });

    group('real OCR fragments', () {
      test('Modelo 2020 front fragment', () {
        const text =
            'CUI\n74984331-0\nREPÚBLICA DEL PERÚ\n'
            'DOCUMENTO NACIONAL DE IDENTIDAD\n'
            'GOICOCHEA PEREZ\nApellidos';
        expect(detector.detect(text), DocumentSide.front);
      });

      test('azul booklet front fragment (SONIA)', () {
        const text =
            'REPUBLICA DEL PERU\n'
            'REGISTRO NACIONAL DE IDENTIFICACIÓN Y ESTADO CIVIL  DNI 16793105-2\n'
            'DOCUMENTO NACIONAL DE IDENTIDAD\n'
            'Primer Apellido  MIO\n'
            'Segundo Apellido  LOPEZ';
        expect(detector.detect(text), DocumentSide.front);
      });

      test('azul booklet back fragment (Constancia de Sufragio)', () {
        const text =
            'CONSTANCIA DE SUFRAGIO\n'
            'CONSTANCIA DE SUFRAGIO\n'
            'Departamento LAMBAYEQUE\n'
            'Dirección AMPLC. TUPAC AMARU SICUANI 215\n'
            'Donación de Órganos NO\n'
            'Grupo de Votación 083966';
        expect(detector.detect(text), DocumentSide.back);
      });
    });
  });
}
