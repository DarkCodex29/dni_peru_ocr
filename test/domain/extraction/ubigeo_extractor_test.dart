import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UbigeoExtractor', () {
    const extractor = UbigeoExtractor();

    test('extracts department/province/district from slash format', () {
      const text = 'LIMA / LIMA / SAN ISIDRO';
      final result = extractor.extract(text);
      expect(result.department, 'LIMA');
      expect(result.province, 'LIMA');
      expect(result.district, 'SAN ISIDRO');
    });

    test('extracts after labels DEPARTAMENTO / PROVINCIA / DISTRITO', () {
      const text =
          'DEPARTAMENTO\nANCASH\nPROVINCIA\nSANTA\nDISTRITO\nCHIMBOTE';
      final result = extractor.extract(text);
      expect(result.department, 'ANCASH');
      expect(result.province, 'SANTA');
      expect(result.district, 'CHIMBOTE');
    });

    test('handles leading slash (Callao)', () {
      const text = '/ CALLAO / VENTANILLA';
      final result = extractor.extract(text);
      expect(result.department, isNull);
      expect(result.province, 'CALLAO');
      expect(result.district, 'VENTANILLA');
    });

    test('returns nulls when no ubigeo pattern present', () {
      final result = extractor.extract('Random text');
      expect(result.department, isNull);
      expect(result.province, isNull);
      expect(result.district, isNull);
    });

    group('label-as-value rejection (real OCR bug)', () {
      test('rejects label triple "Departamento / Provincia / Distrito"', () {
        // ML Kit reads the horizontal label row as a slash-triple too.
        const text = 'DEPARTAMENTO / PROVINCIA / DISTRITO';
        final result = extractor.extract(text);
        expect(result.department, isNull);
        expect(result.province, isNull);
        expect(result.district, isNull);
      });

      test('rejects OCR-corrupted label "DEPARTAMENTE / PREVINCIA / DISTRITO"',
          () {
        const text = 'DEPARTAMENTE / PREVINCIA / DISTRITO';
        final result = extractor.extract(text);
        expect(result.department, isNull);
        expect(result.province, isNull);
        expect(result.district, isNull);
      });

      test('picks real value when label and value coexist in text', () {
        // The real Modelo 2020 OCR produces: label line + value line.
        // We must skip the label line and pick the value line.
        const text =
            'DEPARTAMENTO / PROVINCIA / DISTRITO\n'
            'LAMBAYEQUE/CHICLAYO/CHICLAYO';
        final result = extractor.extract(text);
        expect(result.department, 'LAMBAYEQUE');
        expect(result.province, 'CHICLAYO');
        expect(result.district, 'CHICLAYO');
      });

      test('rejects OCR-corrupted label even when uppercase has typos', () {
        const text =
            'DEPARTAMENTE /PREVINCIA /DISTRITO\n'
            'LAMBAYEQUE/CHICLAYO/CHICLAYO';
        final result = extractor.extract(text);
        expect(result.department, 'LAMBAYEQUE');
        expect(result.province, 'CHICLAYO');
        expect(result.district, 'CHICLAYO');
      });
    });
  });
}
