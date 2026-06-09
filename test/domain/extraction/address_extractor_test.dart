import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AddressExtractor', () {
    const extractor = AddressExtractor();

    test('extracts address after DIRECCIÓN label', () {
      const text = 'DIRECCIÓN\nAV. LIMA 123 SAN ISIDRO';
      expect(extractor.extract(text).address, 'AV. LIMA 123 SAN ISIDRO');
    });

    test('extracts address after DOMICILIO label (azul booklet)', () {
      const text = 'DOMICILIO\nJR. CALLAO 456';
      expect(extractor.extract(text).address, 'JR. CALLAO 456');
    });

    test('handles DIRECCION without accent', () {
      const text = 'DIRECCION\nCALLE 7 102 SAN BORJA';
      expect(extractor.extract(text).address, 'CALLE 7 102 SAN BORJA');
    });

    test('returns null when no address label present', () {
      expect(extractor.extract('Random text').address, isNull);
    });

    test('returns null when label has no value below', () {
      expect(extractor.extract('DIRECCIÓN\nSEXO\nM').address, isNull);
    });

    group('anchor-based fallback (when label is corrupted by OCR)', () {
      test('detects URB. address without DIRECCIÓN label', () {
        // Real Modelo 2020 OCR sometimes mangles "Dirección" to "Direcelbn"
        // or drops it entirely. We must still detect addresses by anchor.
        // Note: AddressNoiseFilter drops "FLT" (not a known street code).
        const text =
            'URB. MIRAFLORES ETAPA II MZ. FLT 13\n'
            'DEPARTAMENTO / PROVINCIA / DISTRITO\n'
            'LAMBAYEQUE/CHICLAYO/CHICLAYO';
        expect(
          extractor.extract(text).address,
          'URB. MIRAFLORES ETAPA II MZ. 13',
        );
      });

      test('detects AV. address without label', () {
        const text = 'AV. JAVIER PRADO 1234 SAN BORJA';
        expect(
          extractor.extract(text).address,
          'AV. JAVIER PRADO 1234 SAN BORJA',
        );
      });

      test('detects JR. address without label', () {
        const text = 'JR. CALLAO 456 LIMA';
        expect(extractor.extract(text).address, 'JR. CALLAO 456 LIMA');
      });

      test('detects CALLE address without label', () {
        // AddressNoiseFilter strips "NUMERO" (a known label token).
        const text = 'CALLE 7 NUMERO 102 SAN BORJA';
        expect(
          extractor.extract(text).address,
          'CALLE 7 102 SAN BORJA',
        );
      });

      test('detects MZ. + LT. address without label', () {
        const text = 'MZ. C LT. 20 ANTONIA MORENO';
        expect(
          extractor.extract(text).address,
          'MZ. C LT. 20 ANTONIA MORENO',
        );
      });

      test('does not flag a non-address line as address', () {
        const text = 'GOICOCHEA PEREZ\nODETTE FRANCCESCA';
        expect(extractor.extract(text).address, isNull);
      });

      test('explicit DIRECCIÓN label still wins over anchor scan', () {
        const text =
            'DIRECCIÓN\nAV. LIMA 123\n\nURB. OTRO LUGAR 456';
        expect(extractor.extract(text).address, 'AV. LIMA 123');
      });
    });
  });
}
