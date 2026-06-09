import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SurnameExtractor', () {
    const extractor = SurnameExtractor();

    group('e-DNI labels (PRIMER APELLIDO / SEGUNDO APELLIDO)', () {
      test('extracts paternal surname after PRIMER APELLIDO label', () {
        const text = 'PRIMER APELLIDO\nMUÑOZ\nSEGUNDO APELLIDO\nPEREZ';
        final result = extractor.extract(text);
        expect(result.lastName, 'MUÑOZ');
      });

      test('extracts maternal surname after SEGUNDO APELLIDO label', () {
        const text = 'PRIMER APELLIDO\nMUÑOZ\nSEGUNDO APELLIDO\nPEREZ';
        final result = extractor.extract(text);
        expect(result.secondLastName, 'PEREZ');
      });

      test('handles SEGUNDO.APELLIDO with period (OCR noise)', () {
        const text = 'PRIMER APELLIDO\nGARCIA\nSEGUNDO.APELLIDO\nLOPEZ';
        final result = extractor.extract(text);
        expect(result.lastName, 'GARCIA');
        expect(result.secondLastName, 'LOPEZ');
      });
    });

    group('DNI azul booklet labels (APELLIDO PATERNO / APELLIDO MATERNO)', () {
      test('extracts paternal surname after APELLIDO PATERNO label', () {
        const text = 'APELLIDO PATERNO\nMUÑOZ\nAPELLIDO MATERNO\nPEREZ';
        final result = extractor.extract(text);
        expect(result.lastName, 'MUÑOZ');
      });

      test('extracts maternal surname after APELLIDO MATERNO label', () {
        const text = 'APELLIDO PATERNO\nMUÑOZ\nAPELLIDO MATERNO\nPEREZ';
        final result = extractor.extract(text);
        expect(result.secondLastName, 'PEREZ');
      });
    });

    group('OCR noise tolerance', () {
      test('handles missing accents (PRMER instead of PRIMER)', () {
        const text = 'PRMER APELLIDO\nSALAS\nSEGUNDO APELLIDO\nCOMER';
        final result = extractor.extract(text);
        expect(result.lastName, 'SALAS');
        expect(result.secondLastName, 'COMER');
      });

      test('handles SGUNDO instead of SEGUNDO', () {
        const text = 'PRIMER APELLIDO\nGARCIA\nSGUNDO APELLIDO\nLOPEZ';
        final result = extractor.extract(text);
        expect(result.secondLastName, 'LOPEZ');
      });
    });

    group('edge cases', () {
      test('returns nulls when no surname labels present', () {
        final result = extractor.extract('Hello world');
        expect(result.lastName, isNull);
        expect(result.secondLastName, isNull);
      });

      test('returns nulls when label is alone without value', () {
        final result = extractor.extract('PRIMER APELLIDO\nDNI 12345678');
        expect(result.lastName, isNull);
      });

      test('ignores value with digits (label corruption)', () {
        const text = 'PRIMER APELLIDO\n12345\nSEGUNDO APELLIDO\nPEREZ';
        final result = extractor.extract(text);
        expect(result.lastName, isNull);
        expect(result.secondLastName, 'PEREZ');
      });

      test('extracts only paternal when maternal label missing', () {
        const text = 'PRIMER APELLIDO\nMUÑOZ\nPRENOMBRES\nJUAN';
        final result = extractor.extract(text);
        expect(result.lastName, 'MUÑOZ');
        expect(result.secondLastName, isNull);
      });
    });
  });
}
