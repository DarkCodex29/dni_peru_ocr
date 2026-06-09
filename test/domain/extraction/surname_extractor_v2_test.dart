import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SurnameExtractor — APELLIDOS concatenated label', () {
    const extractor = SurnameExtractor();

    test('extracts paternal+maternal from APELLIDOS concatenated value', () {
      const text = 'APELLIDOS\nMUÑOZ PEREZ';
      final result = extractor.extract(text);
      expect(result.lastName, 'MUÑOZ');
      expect(result.secondLastName, 'PEREZ');
    });

    test('extracts paternal+maternal from APELLIDOS with 3-word maternal', () {
      const text = 'APELLIDOS\nGARCIA DE LA TORRE';
      final result = extractor.extract(text);
      expect(result.lastName, 'GARCIA');
      expect(result.secondLastName, 'DE LA TORRE');
    });

    test('handles APELLIDOS with single name (only paternal)', () {
      const text = 'APELLIDOS\nMUÑOZ';
      final result = extractor.extract(text);
      expect(result.lastName, 'MUÑOZ');
      expect(result.secondLastName, isNull);
    });

    test('separated labels still win over concatenated APELLIDOS', () {
      const text =
          'APELLIDOS\nWRONG WRONG\n'
          'PRIMER APELLIDO\nMUÑOZ\nSEGUNDO APELLIDO\nPEREZ';
      final result = extractor.extract(text);
      expect(result.lastName, 'MUÑOZ');
      expect(result.secondLastName, 'PEREZ');
    });
  });
}
