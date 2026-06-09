import 'package:flutter_test/flutter_test.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';

void main() {
  group('DniData', () {
    test('minimal construction with required fields only', () {
      const data = DniData(
        dni: '43005787',
        nombres: 'JUAN CARLOS',
        apellidoPaterno: 'GARCIA',
        apellidoMaterno: 'LOPEZ',
        nombreCompleto: 'GARCIA LOPEZ JUAN CARLOS',
      );

      expect(data.dni, '43005787');
      expect(data.nombres, 'JUAN CARLOS');
      expect(data.apellidoPaterno, 'GARCIA');
      expect(data.apellidoMaterno, 'LOPEZ');
      expect(data.nombreCompleto, 'GARCIA LOPEZ JUAN CARLOS');
      expect(data.ubigeo, isNull);
      expect(data.departamento, isNull);
      expect(data.provincia, isNull);
      expect(data.distrito, isNull);
      expect(data.rawSource, isNull);
      expect(data.raw, isNull);
    });

    test('full construction with all fields including raw', () {
      const data = DniData(
        dni: '43005787',
        nombres: 'JUAN CARLOS',
        apellidoPaterno: 'GARCIA',
        apellidoMaterno: 'LOPEZ',
        nombreCompleto: 'GARCIA LOPEZ JUAN CARLOS',
        ubigeo: '150101',
        departamento: 'LIMA',
        provincia: 'LIMA',
        distrito: 'LIMA',
        rawSource: 'apis_peru',
        raw: {'codVerifica': '7', 'extra': 'value'},
      );

      expect(data.ubigeo, '150101');
      expect(data.departamento, 'LIMA');
      expect(data.provincia, 'LIMA');
      expect(data.distrito, 'LIMA');
      expect(data.rawSource, 'apis_peru');
      expect(data.raw, {'codVerifica': '7', 'extra': 'value'});
    });

    test('placeholder "-" values from ReniecSunat are preserved', () {
      const data = DniData(
        dni: '43005787',
        nombres: 'JUAN CARLOS',
        apellidoPaterno: 'GARCIA',
        apellidoMaterno: 'LOPEZ',
        nombreCompleto: 'GARCIA LOPEZ JUAN CARLOS',
        ubigeo: '-',
        departamento: '-',
      );

      expect(data.ubigeo, '-');
      expect(data.departamento, '-');
    });

    test('copyWith produces new instance with updated fields', () {
      const original = DniData(
        dni: '43005787',
        nombres: 'JUAN CARLOS',
        apellidoPaterno: 'GARCIA',
        apellidoMaterno: 'LOPEZ',
        nombreCompleto: 'GARCIA LOPEZ JUAN CARLOS',
      );

      final updated = original.copyWith(nombres: 'CARLOS JUAN');

      expect(updated.nombres, 'CARLOS JUAN');
      expect(updated.dni, '43005787');
      expect(updated.apellidoPaterno, 'GARCIA');
    });

    test('copyWith preserves optional fields when not overridden', () {
      const original = DniData(
        dni: '43005787',
        nombres: 'JUAN CARLOS',
        apellidoPaterno: 'GARCIA',
        apellidoMaterno: 'LOPEZ',
        nombreCompleto: 'GARCIA LOPEZ JUAN CARLOS',
        ubigeo: '150101',
        departamento: 'LIMA',
      );

      final updated = original.copyWith(nombres: 'OTRO');

      expect(updated.ubigeo, '150101');
      expect(updated.departamento, 'LIMA');
    });
  });
}
