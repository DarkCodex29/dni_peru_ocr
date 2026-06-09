import 'package:flutter_test/flutter_test.dart';
import 'package:dni_peru_ocr/src/domain/extraction/dni_field.dart';

void main() {
  group('DniField', () {
    test('has exactly 19 values', () {
      expect(DniField.values.length, 19);
    });

    test('all 19 values are distinct', () {
      final set = DniField.values.toSet();
      expect(set.length, 19);
    });

    test('declaration order matches ExtractedFields — front-side-first', () {
      final expected = [
        DniField.documentNumber,
        DniField.firstName,
        DniField.lastName,
        DniField.secondLastName,
        DniField.dateOfBirth,
        DniField.expirationDate,
        DniField.emissionDate,
        DniField.inscriptionDate,
        DniField.sex,
        DniField.nationality,
        DniField.address,
        DniField.department,
        DniField.province,
        DniField.district,
        DniField.stateCivil,
        DniField.cardNumber,
        DniField.organDonor,
        DniField.votingGroup,
        DniField.birthUbigeoCode,
      ];
      expect(DniField.values, expected);
    });

    test('each value is accessible by name', () {
      expect(DniField.documentNumber, isNotNull);
      expect(DniField.firstName, isNotNull);
      expect(DniField.lastName, isNotNull);
      expect(DniField.secondLastName, isNotNull);
      expect(DniField.dateOfBirth, isNotNull);
      expect(DniField.expirationDate, isNotNull);
      expect(DniField.emissionDate, isNotNull);
      expect(DniField.inscriptionDate, isNotNull);
      expect(DniField.sex, isNotNull);
      expect(DniField.nationality, isNotNull);
      expect(DniField.address, isNotNull);
      expect(DniField.department, isNotNull);
      expect(DniField.province, isNotNull);
      expect(DniField.district, isNotNull);
      expect(DniField.stateCivil, isNotNull);
      expect(DniField.cardNumber, isNotNull);
      expect(DniField.organDonor, isNotNull);
      expect(DniField.votingGroup, isNotNull);
      expect(DniField.birthUbigeoCode, isNotNull);
    });
  });
}
