import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MrzExtractor', () {
    const extractor = MrzExtractor();

    test('returns empty when no MRZ block present', () {
      expect(extractor.extract('NORMAL TEXT').documentNumber, isNull);
    });

    test('returns empty when MRZ lines have invalid checksums', () {
      const mrz =
          'IDPER167931050<<<<<<<<<<<<<<<\n'
          '7612046F2911180PER<<<<<<<<<<<6\n'
          'MUNOZ<MORALES<<JOSE<CARLOS<<<<';
      expect(extractor.extract(mrz).documentNumber, isNull);
    });
  });
}
