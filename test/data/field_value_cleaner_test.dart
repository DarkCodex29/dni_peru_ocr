import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FieldValueCleaner', () {
    const cleaner = FieldValueCleaner();

    test('removes label tokens that leaked into surname value', () {
      expect(cleaner.clean('MUÑOZ DIRECCION'), 'MUÑOZ');
      expect(cleaner.clean('PEREZ APELLIDO'), 'PEREZ');
      expect(cleaner.clean('FECHA MUÑOZ'), 'MUÑOZ');
    });

    test('keeps clean values untouched', () {
      expect(cleaner.clean('MUÑOZ'), 'MUÑOZ');
      expect(cleaner.clean('JOSE CARLOS'), 'JOSE CARLOS');
    });

    test('returns null when all tokens are denylisted', () {
      expect(cleaner.clean('DIRECCION FECHA'), isNull);
      expect(cleaner.clean('APELLIDO PRENOMBRES SEXO'), isNull);
    });

    test('returns null for empty or whitespace input', () {
      expect(cleaner.clean(null), isNull);
      expect(cleaner.clean(''), isNull);
      expect(cleaner.clean('   '), isNull);
    });

    test('handles diacritic-stripped denylist matches', () {
      expect(cleaner.clean('MUNOZ DIRECCIÓN'), 'MUNOZ');
      expect(cleaner.clean('GARCIA DONACIÓN'), 'GARCIA');
    });
  });
}
