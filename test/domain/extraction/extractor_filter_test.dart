import 'package:flutter_test/flutter_test.dart';
import 'package:dni_peru_ocr/src/domain/extraction/dni_field.dart';
import 'package:dni_peru_ocr/src/domain/extraction/dni_fields.dart';
import 'package:dni_peru_ocr/src/domain/extraction/_extractor_filter.dart';
import 'package:dni_peru_ocr/src/domain/extraction/field_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/address_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/date_field_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/dni_number_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/donacion_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/given_names_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/grupo_votacion_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/mrz_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/nationality_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/sex_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/state_civil_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/surname_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/tarjeta_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/ubigeo_extractor.dart';
import 'package:dni_peru_ocr/src/extraction/ubigeo_nacimiento_extractor.dart';

const _allExtractors = <FieldExtractor>[
  MrzExtractor(),
  DniNumberExtractor(),
  SurnameExtractor(),
  GivenNamesExtractor(),
  DateFieldExtractor(),
  SexExtractor(),
  NationalityExtractor(),
  AddressExtractor(),
  UbigeoExtractor(),
  StateCivilExtractor(),
  TarjetaExtractor(),
  DonacionExtractor(),
  GrupoVotacionExtractor(),
  UbigeoNacimientoExtractor(),
];

void main() {
  group('filteredExtractors', () {
    test('null fields returns all 14 extractors unchanged', () {
      final result = filteredExtractors(null, _allExtractors);
      expect(result.length, 14);
      expect(result, equals(_allExtractors));
    });

    test('full() fields returns all 14 extractors', () {
      final result = filteredExtractors(DniFields.full(), _allExtractors);
      expect(result.length, 14);
    });

    test('required({documentNumber}) includes DniNumberExtractor and MrzExtractor', () {
      final fields = DniFields.required({DniField.documentNumber});
      final result = filteredExtractors(fields, _allExtractors);
      final types = result.map((e) => e.runtimeType).toSet();
      expect(types, contains(DniNumberExtractor));
      expect(types, contains(MrzExtractor));
    });

    test('required({documentNumber}) excludes AddressExtractor', () {
      final fields = DniFields.required({DniField.documentNumber});
      final result = filteredExtractors(fields, _allExtractors);
      final types = result.map((e) => e.runtimeType).toSet();
      expect(types, isNot(contains(AddressExtractor)));
    });

    test('required({documentNumber}) excludes DonacionExtractor', () {
      final fields = DniFields.required({DniField.documentNumber});
      final result = filteredExtractors(fields, _allExtractors);
      final types = result.map((e) => e.runtimeType).toSet();
      expect(types, isNot(contains(DonacionExtractor)));
    });

    test('required({documentNumber}) excludes UbigeoExtractor', () {
      final fields = DniFields.required({DniField.documentNumber});
      final result = filteredExtractors(fields, _allExtractors);
      final types = result.map((e) => e.runtimeType).toSet();
      expect(types, isNot(contains(UbigeoExtractor)));
    });

    test('required({documentNumber, firstName}) includes GivenNamesExtractor', () {
      final fields = DniFields.required({DniField.documentNumber, DniField.firstName});
      final result = filteredExtractors(fields, _allExtractors);
      final types = result.map((e) => e.runtimeType).toSet();
      expect(types, contains(GivenNamesExtractor));
    });

    test('required({documentNumber, firstName}) excludes UbigeoExtractor', () {
      final fields = DniFields.required({DniField.documentNumber, DniField.firstName});
      final result = filteredExtractors(fields, _allExtractors);
      final types = result.map((e) => e.runtimeType).toSet();
      expect(types, isNot(contains(UbigeoExtractor)));
    });

    test('kyc() includes DateFieldExtractor (produces dateOfBirth and expirationDate)', () {
      final result = filteredExtractors(DniFields.kyc(), _allExtractors);
      final types = result.map((e) => e.runtimeType).toSet();
      expect(types, contains(DateFieldExtractor));
    });

    test('kyc() excludes UbigeoExtractor', () {
      final result = filteredExtractors(DniFields.kyc(), _allExtractors);
      final types = result.map((e) => e.runtimeType).toSet();
      expect(types, isNot(contains(UbigeoExtractor)));
    });

    test('required({lastName}) includes SurnameExtractor (intersection non-empty)', () {
      final fields = DniFields.required({DniField.lastName});
      final result = filteredExtractors(fields, _allExtractors);
      final types = result.map((e) => e.runtimeType).toSet();
      expect(types, contains(SurnameExtractor));
    });
  });

  group('shouldRunExtractor', () {
    test('null selectedFields always returns true', () {
      expect(shouldRunExtractor('DniNumberExtractor', null), isTrue);
    });

    test('DniNumberExtractor with minimal() returns true (documentNumber in minimal)', () {
      expect(shouldRunExtractor('DniNumberExtractor', DniFields.minimal()), isTrue);
    });

    test('AddressExtractor with minimal() returns false (address not in minimal)', () {
      expect(shouldRunExtractor('AddressExtractor', DniFields.minimal()), isFalse);
    });

    test('SurnameExtractor with required({lastName}) returns true (lastName in set)', () {
      final fields = DniFields.required({DniField.lastName});
      expect(shouldRunExtractor('SurnameExtractor', fields), isTrue);
    });

    test('unknown extractor name with full() returns true (defensive default)', () {
      expect(shouldRunExtractor('UnknownExtractor', DniFields.full()), isTrue);
    });

    test('unknown extractor name with minimal() returns true (defensive default)', () {
      expect(shouldRunExtractor('UnknownExtractor', DniFields.minimal()), isTrue);
    });

    test('MrzExtractor with required({documentNumber}) returns true', () {
      final fields = DniFields.required({DniField.documentNumber});
      expect(shouldRunExtractor('MrzExtractor', fields), isTrue);
    });

    test('UbigeoExtractor with kyc() returns false', () {
      expect(shouldRunExtractor('UbigeoExtractor', DniFields.kyc()), isFalse);
    });
  });

  group('scaledThreshold', () {
    test('n=4 → 3', () {
      expect(scaledThreshold(4), 3);
    });

    test('n=7 → 5', () {
      expect(scaledThreshold(7), 5);
    });

    test('n=19 → 14', () {
      expect(scaledThreshold(19), 14);
    });

    test('n=1 → 3 (clamped to minimum)', () {
      expect(scaledThreshold(1), 3);
    });

    test('n=100 → 14 (clamped to maximum)', () {
      expect(scaledThreshold(100), 14);
    });
  });
}
