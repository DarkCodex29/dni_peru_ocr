import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OcrTextSanitizer', () {
    const sanitizer = OcrTextSanitizer();

    test('removes pure external-noise lines (drinks/devices)', () {
      const input =
          'CUI 123\n'
          'SABORIZANTES NATURALES\n'
          'PRIMER APELLIDO\n'
          'MUÑOZ';
      final out = sanitizer.sanitize(input);
      expect(out.contains('SABORIZANTES'), isFalse);
      expect(out.contains('CUI 123'), isTrue);
      expect(out.contains('MUÑOZ'), isTrue);
    });

    test('keeps lines that mix noise with real content', () {
      const input = 'NATURAL EXTRACT DOCUMENTO MUÑOZ';
      final out = sanitizer.sanitize(input);
      expect(out.contains('MUÑOZ'), isTrue);
    });

    test('keeps DNI label lines like NACIONALIDAD PER', () {
      const input = 'NACIONALIDAD PER\nSEXO M';
      final out = sanitizer.sanitize(input);
      expect(out.contains('NACIONALIDAD'), isTrue);
      expect(out.contains('SEXO'), isTrue);
    });

    test('keeps DNI labels untouched', () {
      const input = 'REPUBLICA DEL PERU\nDNI 12345678\nCUI 123';
      final out = sanitizer.sanitize(input);
      expect(out, contains('DNI 12345678'));
      expect(out, contains('CUI 123'));
    });

    test('returns empty when all lines are external noise', () {
      const input = 'SABORIZANTES NATURALES\nREFRESCANTES JUGO';
      expect(sanitizer.sanitize(input).trim(), isEmpty);
    });
  });
}
