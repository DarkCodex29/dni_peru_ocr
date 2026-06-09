import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TarjetaExtractor', () {
    const extractor = TarjetaExtractor();

    test('extracts 10-digit card number after NRO TARJETA label', () {
      expect(
        extractor.extract('NRO TARJETA\n0200869805').cardNumber,
        '0200869805',
      );
    });

    test('extracts card number after NUMERO DE TARJETA label', () {
      expect(
        extractor.extract('NUMERO DE TARJETA\n1234567890').cardNumber,
        '1234567890',
      );
    });

    test('extracts card number after N TARJETA label', () {
      expect(
        extractor.extract('N. TARJETA\n9876543210').cardNumber,
        '9876543210',
      );
    });

    test('handles NRO TARJETA with colon and same line', () {
      expect(
        extractor.extract('NRO TARJETA: 0200869805').cardNumber,
        '0200869805',
      );
    });

    test('extracts trailing 10-digit token from emission line', () {
      // Modelo 2020 horizontal: "Fecha emisión 03 05 2022 0200869805"
      expect(
        extractor
            .extract('FECHA EMISIÓN 03 05 2022 0200869805')
            .cardNumber,
        '0200869805',
      );
    });

    test('does not confuse 8-digit DNI with 10-digit card number', () {
      expect(extractor.extract('DNI 73452810').cardNumber, isNull);
    });

    test('returns null when no card number present', () {
      expect(extractor.extract('hola mundo').cardNumber, isNull);
    });

    test('returns null when value is too short', () {
      expect(extractor.extract('NRO TARJETA\n123').cardNumber, isNull);
    });

    test('does not match 11+ consecutive digits', () {
      expect(
        extractor.extract('NRO TARJETA\n12345678901').cardNumber,
        isNull,
      );
    });
  });
}
