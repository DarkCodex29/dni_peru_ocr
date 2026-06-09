import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:dni_peru_ocr/src/lookup/reliable/dni_data_merger.dart';
import 'package:flutter_test/flutter_test.dart';

DniData _ocr({
  String dni = '12345678',
  String nombres = 'OCR_NOMBRES',
  String apellidoPaterno = 'OCR_PATERNO',
  String apellidoMaterno = 'OCR_MATERNO',
  String nombreCompleto = 'OCR_COMPLETO',
  String? ubigeo,
  String? departamento,
  String? provincia,
  String? distrito,
  String? rawSource,
  Map<String, dynamic>? raw,
}) =>
    DniData(
      dni: dni,
      nombres: nombres,
      apellidoPaterno: apellidoPaterno,
      apellidoMaterno: apellidoMaterno,
      nombreCompleto: nombreCompleto,
      ubigeo: ubigeo,
      departamento: departamento,
      provincia: provincia,
      distrito: distrito,
      rawSource: rawSource,
      raw: raw,
    );

DniData _reniec({
  String dni = '12345678',
  String nombres = 'RENIEC_NOMBRES',
  String apellidoPaterno = 'RENIEC_PATERNO',
  String apellidoMaterno = 'RENIEC_MATERNO',
  String nombreCompleto = 'RENIEC_COMPLETO',
  String? ubigeo,
  String? departamento,
  String? provincia,
  String? distrito,
  String? rawSource,
  Map<String, dynamic>? raw,
}) =>
    DniData(
      dni: dni,
      nombres: nombres,
      apellidoPaterno: apellidoPaterno,
      apellidoMaterno: apellidoMaterno,
      nombreCompleto: nombreCompleto,
      ubigeo: ubigeo,
      departamento: departamento,
      provincia: provincia,
      distrito: distrito,
      rawSource: rawSource,
      raw: raw,
    );

void main() {
  const merger = DniDataMerger();

  group('DniDataMerger — RENIEC prevails for required string fields', () {
    test('nombres: RENIEC wins when non-empty', () {
      final result = merger.merge(ocr: _ocr(), reniec: _reniec());
      expect(result.nombres, equals('RENIEC_NOMBRES'));
    });

    test('apellidoPaterno: RENIEC wins when non-empty', () {
      final result = merger.merge(ocr: _ocr(), reniec: _reniec());
      expect(result.apellidoPaterno, equals('RENIEC_PATERNO'));
    });

    test('apellidoMaterno: RENIEC wins when non-empty', () {
      final result = merger.merge(ocr: _ocr(), reniec: _reniec());
      expect(result.apellidoMaterno, equals('RENIEC_MATERNO'));
    });

    test('nombreCompleto: RENIEC wins when non-empty', () {
      final result = merger.merge(ocr: _ocr(), reniec: _reniec());
      expect(result.nombreCompleto, equals('RENIEC_COMPLETO'));
    });
  });

  group('DniDataMerger — OCR wins when RENIEC field is empty or whitespace', () {
    test('nombres: OCR wins when RENIEC is empty string', () {
      final result = merger.merge(
        ocr: _ocr(nombres: 'OCR_N'),
        reniec: _reniec(nombres: ''),
      );
      expect(result.nombres, equals('OCR_N'));
    });

    test('nombres: OCR wins when RENIEC is whitespace-only', () {
      final result = merger.merge(
        ocr: _ocr(nombres: 'OCR_N'),
        reniec: _reniec(nombres: '   '),
      );
      expect(result.nombres, equals('OCR_N'));
    });

    test('apellidoPaterno: OCR wins when RENIEC is whitespace', () {
      final result = merger.merge(
        ocr: _ocr(apellidoPaterno: 'OCR_P'),
        reniec: _reniec(apellidoPaterno: '\t'),
      );
      expect(result.apellidoPaterno, equals('OCR_P'));
    });

    test('apellidoMaterno: OCR wins when RENIEC is empty', () {
      final result = merger.merge(
        ocr: _ocr(apellidoMaterno: 'OCR_M'),
        reniec: _reniec(apellidoMaterno: ''),
      );
      expect(result.apellidoMaterno, equals('OCR_M'));
    });

    test('nombreCompleto: OCR wins when RENIEC is whitespace', () {
      final result = merger.merge(
        ocr: _ocr(nombreCompleto: 'OCR_C'),
        reniec: _reniec(nombreCompleto: '  '),
      );
      expect(result.nombreCompleto, equals('OCR_C'));
    });
  });

  group('DniDataMerger — optional fields fall back correctly', () {
    test('ubigeo: RENIEC wins when non-null and non-empty', () {
      final result = merger.merge(
        ocr: _ocr(ubigeo: 'OCR_UBI'),
        reniec: _reniec(ubigeo: '150101'),
      );
      expect(result.ubigeo, equals('150101'));
    });

    test('ubigeo: OCR wins when RENIEC ubigeo is null', () {
      final result = merger.merge(
        ocr: _ocr(ubigeo: 'OCR_UBI'),
        reniec: _reniec(ubigeo: null),
      );
      expect(result.ubigeo, equals('OCR_UBI'));
    });

    test('departamento: RENIEC wins when present', () {
      final result = merger.merge(
        ocr: _ocr(departamento: 'OCR_DEP'),
        reniec: _reniec(departamento: 'LIMA'),
      );
      expect(result.departamento, equals('LIMA'));
    });

    test('departamento: OCR wins when RENIEC is null', () {
      final result = merger.merge(
        ocr: _ocr(departamento: 'OCR_DEP'),
        reniec: _reniec(departamento: null),
      );
      expect(result.departamento, equals('OCR_DEP'));
    });

    test('provincia: OCR wins when RENIEC is null', () {
      final result = merger.merge(
        ocr: _ocr(provincia: 'OCR_PRV'),
        reniec: _reniec(provincia: null),
      );
      expect(result.provincia, equals('OCR_PRV'));
    });

    test('distrito: OCR wins when RENIEC is null', () {
      final result = merger.merge(
        ocr: _ocr(distrito: 'OCR_DIS'),
        reniec: _reniec(distrito: null),
      );
      expect(result.distrito, equals('OCR_DIS'));
    });
  });

  group('DniDataMerger — DNI invariant', () {
    test('merged.dni always equals ocr.dni', () {
      final ocr = _ocr(dni: '12345678');
      final reniec = _reniec(dni: '12345678');
      final result = merger.merge(ocr: ocr, reniec: reniec);
      expect(result.dni, equals('12345678'));
    });

    test('merged.dni equals ocr.dni even when reniec.dni differs', () {
      final ocr = _ocr(dni: '11111111');
      final reniec = _reniec(dni: '99999999');
      final result = merger.merge(ocr: ocr, reniec: reniec);
      expect(result.dni, equals('11111111'));
    });
  });

  group('DniDataMerger — rawSource is always null (no source leak)', () {
    test('rawSource is null when both inputs have no rawSource', () {
      final result = merger.merge(ocr: _ocr(), reniec: _reniec());
      expect(result.rawSource, isNull);
    });

    test('rawSource is null even when ocr has a rawSource', () {
      final result = merger.merge(
        ocr: _ocr(rawSource: 'ocr-engine'),
        reniec: _reniec(rawSource: null),
      );
      expect(result.rawSource, isNull);
    });

    test('rawSource is null even when both inputs have rawSource values', () {
      final result = merger.merge(
        ocr: _ocr(rawSource: 'ocr-engine'),
        reniec: _reniec(rawSource: 'reniec-api'),
      );
      expect(result.rawSource, isNull);
    });
  });

  group('DniDataMerger — raw map: RENIEC wins when present', () {
    test('raw: RENIEC raw map wins when non-null', () {
      final result = merger.merge(
        ocr: _ocr(raw: {'from': 'ocr'}),
        reniec: _reniec(raw: {'from': 'reniec'}),
      );
      expect(result.raw, equals({'from': 'reniec'}));
    });

    test('raw: OCR raw map used when RENIEC raw is null', () {
      final result = merger.merge(
        ocr: _ocr(raw: {'from': 'ocr'}),
        reniec: _reniec(raw: null),
      );
      expect(result.raw, equals({'from': 'ocr'}));
    });
  });

  group('DniDataMerger — mixed fields scenario', () {
    test('some fields from RENIEC, others fall through to OCR', () {
      final ocr = _ocr(
        nombres: 'OCR_N',
        apellidoPaterno: 'OCR_P',
        apellidoMaterno: 'OCR_M',
        nombreCompleto: 'OCR_C',
        ubigeo: 'OCR_UBI',
      );
      final reniec = _reniec(
        nombres: 'RENIEC_N',
        apellidoPaterno: '',
        apellidoMaterno: '  ',
        nombreCompleto: 'RENIEC_C',
        ubigeo: null,
      );
      final result = merger.merge(ocr: ocr, reniec: reniec);

      expect(result.nombres, equals('RENIEC_N'));
      expect(result.apellidoPaterno, equals('OCR_P'));
      expect(result.apellidoMaterno, equals('OCR_M'));
      expect(result.nombreCompleto, equals('RENIEC_C'));
      expect(result.ubigeo, equals('OCR_UBI'));
    });
  });

  group('DniDataMerger — fields filter', () {
    test('fields: null → output identical to v0.10.0 (backward compat)', () {
      final result = merger.merge(
        ocr: _ocr(departamento: 'OCR_DEP', provincia: 'OCR_PRV'),
        reniec: _reniec(departamento: 'LIMA', provincia: 'LIMA'),
      );
      expect(result.nombres, equals('RENIEC_NOMBRES'));
      expect(result.departamento, equals('LIMA'));
      expect(result.provincia, equals('LIMA'));
    });

    test('fields: full() → output identical to v0.10.0', () {
      final result = merger.merge(
        ocr: _ocr(departamento: 'OCR_DEP'),
        reniec: _reniec(departamento: 'LIMA'),
        fields: DniFields.full(),
      );
      expect(result.nombres, equals('RENIEC_NOMBRES'));
      expect(result.departamento, equals('LIMA'));
    });

    test(
        'fields: minimal() → departamento, provincia, distrito are null '
        'even when RENIEC has values', () {
      final result = merger.merge(
        ocr: _ocr(
          departamento: 'OCR_DEP',
          provincia: 'OCR_PRV',
          distrito: 'OCR_DIS',
        ),
        reniec: _reniec(
          departamento: 'LIMA',
          provincia: 'LIMA',
          distrito: 'MIRAFLORES',
        ),
        fields: DniFields.minimal(),
      );
      expect(result.departamento, isNull);
      expect(result.provincia, isNull);
      expect(result.distrito, isNull);
    });

    test(
        'fields: minimal() → nombres, apellidoPaterno, apellidoMaterno '
        'retain merged values', () {
      final result = merger.merge(
        ocr: _ocr(),
        reniec: _reniec(),
        fields: DniFields.minimal(),
      );
      expect(result.nombres, equals('RENIEC_NOMBRES'));
      expect(result.apellidoPaterno, equals('RENIEC_PATERNO'));
      expect(result.apellidoMaterno, equals('RENIEC_MATERNO'));
    });

    test(
        'fields: required({documentNumber, address}) → '
        'nombreCompleto cleared (no name fields selected)', () {
      final result = merger.merge(
        ocr: _ocr(nombreCompleto: 'OCR_C'),
        reniec: _reniec(nombreCompleto: 'RENIEC_C'),
        fields: DniFields.required(
          {DniField.documentNumber, DniField.address},
        ),
      );
      expect(result.nombreCompleto, isNull);
    });

    test(
        'fields: required({firstName, documentNumber}) → '
        'nombreCompleto preserved (at least one name field selected)', () {
      final result = merger.merge(
        ocr: _ocr(nombreCompleto: 'OCR_C'),
        reniec: _reniec(nombreCompleto: 'RENIEC_C'),
        fields: DniFields.required(
          {DniField.documentNumber, DniField.firstName},
        ),
      );
      expect(result.nombreCompleto, equals('RENIEC_C'));
    });

    test(
        'fields: required({lastName, documentNumber}) → '
        'nombreCompleto preserved (lastName is a name field)', () {
      final result = merger.merge(
        ocr: _ocr(nombreCompleto: 'OCR_C'),
        reniec: _reniec(nombreCompleto: 'RENIEC_C'),
        fields: DniFields.required(
          {DniField.documentNumber, DniField.lastName},
        ),
      );
      expect(result.nombreCompleto, equals('RENIEC_C'));
    });

    test(
        'fields: required({documentNumber, address}) → '
        'nombreCompleto cleared (ALL three name fields absent)', () {
      final result = merger.merge(
        ocr: _ocr(nombreCompleto: 'OCR_C'),
        reniec: _reniec(nombreCompleto: 'RENIEC_C'),
        fields: DniFields.required(
          {DniField.documentNumber, DniField.address},
        ),
      );
      expect(result.nombreCompleto, isNull);
    });

    test('fields: kyc() → nombre, apellidos, address populated; '
        'departamento, provincia, distrito null', () {
      final result = merger.merge(
        ocr: _ocr(
          departamento: 'OCR_DEP',
          provincia: 'OCR_PRV',
          distrito: 'OCR_DIS',
        ),
        reniec: _reniec(
          departamento: 'LIMA',
          provincia: 'LIMA',
          distrito: 'MIRAFLORES',
        ),
        fields: DniFields.kyc(),
      );
      expect(result.nombres, equals('RENIEC_NOMBRES'));
      expect(result.apellidoPaterno, equals('RENIEC_PATERNO'));
      expect(result.apellidoMaterno, equals('RENIEC_MATERNO'));
      expect(result.departamento, isNull);
      expect(result.provincia, isNull);
      expect(result.distrito, isNull);
    });

    test('DNI invariant preserved: merged.dni == ocr.dni with fields filter',
        () {
      final result = merger.merge(
        ocr: _ocr(dni: '87654321'),
        reniec: _reniec(dni: '87654321'),
        fields: DniFields.minimal(),
      );
      expect(result.dni, equals('87654321'));
    });
  });
}
