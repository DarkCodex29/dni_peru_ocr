import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FieldHunter', () {
    const frontAnchor = 'CUI 1234567890\n';

    group('fields parameter — extractor filtering', () {
      test('standard() with no fields instantiates all 14 extractors', () {
        final hunter = FieldHunter.standard();
        expect(hunter.extractors.length, 14);
      });

      test('standard(fields: minimal()) excludes AddressExtractor', () {
        final hunter = FieldHunter.standard(fields: DniFields.minimal());
        final types = hunter.extractors.map((e) => e.runtimeType.toString());
        expect(types.contains('AddressExtractor'), isFalse);
      });

      test('standard(fields: minimal()) includes DniNumberExtractor', () {
        final hunter = FieldHunter.standard(fields: DniFields.minimal());
        final types = hunter.extractors.map((e) => e.runtimeType.toString());
        expect(types.contains('DniNumberExtractor'), isTrue);
      });

      test(
          'standard(fields: required({documentNumber})) includes MrzExtractor',
          () {
        final hunter = FieldHunter.standard(
          fields: DniFields.required({DniField.documentNumber}),
        );
        final types = hunter.extractors.map((e) => e.runtimeType.toString());
        expect(types.contains('MrzExtractor'), isTrue);
      });

      test(
          'standard(fields: required({documentNumber, firstName})) '
          'excludes UbigeoExtractor', () {
        final hunter = FieldHunter.standard(
          fields: DniFields.required(
            {DniField.documentNumber, DniField.firstName},
          ),
        );
        final types = hunter.extractors.map((e) => e.runtimeType.toString());
        expect(types.contains('UbigeoExtractor'), isFalse);
      });

      test('standard(fields: full()) returns all 14 extractors', () {
        final hunter = FieldHunter.standard(fields: DniFields.full());
        expect(hunter.extractors.length, 14);
      });
    });

    test('accumulates fields across multiple frames', () {
      final hunter = FieldHunter.standard();

      hunter.process('${frontAnchor}DNI 16793105');
      hunter.process(
        '${frontAnchor}PRIMER APELLIDO\nMUÑOZ\nSEGUNDO APELLIDO\nPEREZ',
      );
      hunter.process('${frontAnchor}PRE NOMBRES\nJUAN CARLOS');

      final fields = hunter.snapshot.fields;
      expect(fields.documentNumber, '16793105');
      expect(fields.lastName, 'MUÑOZ');
      expect(fields.secondLastName, 'PEREZ');
      expect(fields.firstName, 'JUAN CARLOS');
    });

    test('keeps first non-null value (does not overwrite)', () {
      final hunter = FieldHunter.standard();

      hunter.process('${frontAnchor}DNI 16793105');
      hunter.process('${frontAnchor}DNI 87654321');

      expect(hunter.snapshot.fields.documentNumber, '16793105');
    });

    test('tracks front detected when CUI present', () {
      final hunter = FieldHunter.standard();
      hunter.process('CUI 1234567890');
      expect(hunter.snapshot.frontDetected, isTrue);
      expect(hunter.snapshot.backDetected, isFalse);
    });

    test('tracks back detected when DONACIÓN DE ÓRGANOS present', () {
      final hunter = FieldHunter.standard();
      hunter.process('DONACIÓN DE ÓRGANOS');
      expect(hunter.snapshot.backDetected, isTrue);
      expect(hunter.snapshot.frontDetected, isFalse);
    });

    test('both flags true after seeing front then back', () {
      final hunter = FieldHunter.standard();
      hunter.process('CUI 1234567890');
      hunter.process('DONACIÓN DE ÓRGANOS');
      expect(hunter.snapshot.frontDetected, isTrue);
      expect(hunter.snapshot.backDetected, isTrue);
    });

    test('isComplete returns false when required fields missing', () {
      final hunter = FieldHunter.standard();
      hunter.process('DNI 16793105');
      expect(hunter.snapshot.isComplete, isFalse);
    });

    test('isComplete returns true when all required fields present', () {
      final hunter = FieldHunter.standard();
      hunter.process('${frontAnchor}DNI 16793105');
      hunter.process(
        '${frontAnchor}PRIMER APELLIDO\nMUÑOZ\nSEGUNDO APELLIDO\nPEREZ',
      );
      hunter.process('${frontAnchor}PRE NOMBRES\nJUAN CARLOS');
      hunter.process('${frontAnchor}FECHA DE NACIMIENTO\n04 12 1976');
      hunter.process('${frontAnchor}FECHA DE CADUCIDAD\n18 11 2029');
      expect(hunter.snapshot.isComplete, isTrue);
    });

    test('reset clears all accumulated state', () {
      final hunter = FieldHunter.standard();
      hunter.process('DNI 16793105 CUI 1234567890');
      hunter.reset();
      expect(hunter.snapshot.fields.documentNumber, isNull);
      expect(hunter.snapshot.frontDetected, isFalse);
    });

    group('voting accumulator scope', () {
      const validMrzLine1 = 'I<SWE59000002<8198703142391<<<';
      const validMrzLine2 = '8703145M1701027SWE<<<<<<<<<<<8';
      const validMrzLine3 = 'SPECIMEN<<SVEN<<<<<<<<<<<<<<<<';

      test(
          'standard(fields: required({documentNumber})) — MRZ-produced '
          'firstName vote is not in snapshot', () {
        final hunter = FieldHunter.standard(
          fields: DniFields.required({DniField.documentNumber}),
        );
        hunter.process(
          '$validMrzLine1\n$validMrzLine2\n$validMrzLine3',
        );
        final snapshot = hunter.snapshot;
        expect(snapshot.fields.documentNumber, isNotNull);
        expect(snapshot.fields.firstName, isNull);
        expect(snapshot.fields.lastName, isNull);
        expect(snapshot.fields.dateOfBirth, isNull);
        expect(snapshot.fields.sex, isNull);
      });

      test(
          'standard(fields: required({documentNumber, firstName})) — '
          'MRZ firstName survives, non-selected fields discarded', () {
        final hunter = FieldHunter.standard(
          fields: DniFields.required(
            {DniField.documentNumber, DniField.firstName},
          ),
        );
        hunter.process(
          '$validMrzLine1\n$validMrzLine2\n$validMrzLine3',
        );
        final snapshot = hunter.snapshot;
        expect(snapshot.fields.documentNumber, isNotNull);
        expect(snapshot.fields.firstName, isNotNull);
        expect(snapshot.fields.dateOfBirth, isNull);
      });

      test(
          'standard() with null fields — no votes discarded (full extraction)',
          () {
        final hunter = FieldHunter.standard();
        hunter.process(
          '$validMrzLine1\n$validMrzLine2\n$validMrzLine3',
        );
        final snapshot = hunter.snapshot;
        expect(snapshot.fields.documentNumber, isNotNull);
        expect(snapshot.fields.firstName, isNotNull);
        expect(snapshot.fields.dateOfBirth, isNotNull);
      });
    });

    group('surname reconciliation', () {
      test('splits "MUÑOZ PEREZ" stuck in lastName into paternal+maternal', () {
        // APELLIDOS concatenated label: SurnameExtractor stores the whole
        // 'MUÑOZ PEREZ' string in lastName. _reconcileSurnames must split
        // it into paternal/maternal on snapshot.
        final hunter = FieldHunter.standard();
        hunter.process('${frontAnchor}APELLIDOS\nMUÑOZ PEREZ');

        final fields = hunter.snapshot.fields;
        expect(fields.lastName, 'MUÑOZ');
        expect(fields.secondLastName, 'PEREZ');
      });

      test('reconcile handles 3-token maternal (compound) surname', () {
        final hunter = FieldHunter.standard();
        hunter.process('${frontAnchor}APELLIDOS\nGARCIA DE LA CRUZ');

        final fields = hunter.snapshot.fields;
        expect(fields.lastName, 'GARCIA');
        expect(fields.secondLastName, 'DE LA CRUZ');
      });

      test('reconcile does NOT overwrite explicit maternal surname', () {
        // If a separated label feed already populated secondLastName, the
        // concatenated reconciliation must not clobber it.
        final hunter = FieldHunter.standard();
        hunter.process(
          '${frontAnchor}PRIMER APELLIDO\nMUÑOZ\nSEGUNDO APELLIDO\nPEREZ',
        );

        final fields = hunter.snapshot.fields;
        expect(fields.lastName, 'MUÑOZ');
        expect(fields.secondLastName, 'PEREZ');
      });

      test('reconcile is a no-op when lastName has a single token', () {
        final hunter = FieldHunter.standard();
        hunter.process('${frontAnchor}PRIMER APELLIDO\nMUÑOZ');

        final fields = hunter.snapshot.fields;
        expect(fields.lastName, 'MUÑOZ');
        expect(fields.secondLastName, isNull);
      });

      test('processes anchorless frames once a side is already detected', () {
        // Real Modelo 2020 bug: when the camera focuses on the BOTTOM of
        // the front (state civil + dates), no CUI / REPÚBLICA DEL PERÚ
        // anchor appears in the frame, so the side detector returns
        // unknown. But we already saw the front before — we must keep
        // extracting from these continuation frames.
        final hunter = FieldHunter.standard();
        // First frame: clear front anchor.
        hunter.process('CUI 1234567890\nDNI 74984331');
        // Continuation frame: bottom of the front, no anchor.
        hunter.process(
          'ESTADO CIVIL\n'
          'SOLTERA\n'
          'FECHA DE CADUCIDAD\n'
          '25 08 2031\n'
          'FECHA DE EMISIÓN\n'
          '21 02 2024',
        );

        final fields = hunter.snapshot.fields;
        expect(fields.stateCivil, 'SOLTERO');
        expect(fields.expirationDate, '25/08/2031');
        expect(fields.emissionDate, '21/02/2024');
      });

      test('extractors always run even when side is unknown (layout-agnostic)',
          () {
        // The side detector is for state-machine signalling, NOT a gate.
        // Frames with no front/back anchor must still feed the extractors.
        final hunter = FieldHunter.standard();
        hunter.process(
          'DNI 16793105\n'
          'Primer Apellido\nMIO\n'
          'Segundo Apellido\nLOPEZ\n'
          'Pre Nombres\nSONIA SOLEDAD',
        );

        final fields = hunter.snapshot.fields;
        expect(fields.documentNumber, '16793105');
        expect(fields.lastName, 'MIO');
        expect(fields.secondLastName, 'LOPEZ');
        expect(fields.firstName, 'SONIA SOLEDAD');
      });

      test('Modelo 2020 layout: value BEFORE label (real OCR order)', () {
        // ML Kit reads top-to-bottom; in Modelo 2020 the surname value comes
        // BEFORE the "Apellidos" label. Same for prenombres. SurnameExtractor
        // must not confuse ODETTE FRANCCESCA (prenombres) with the surname.
        final hunter = FieldHunter.standard();
        hunter.process(
          '$frontAnchor'
          'GOICOCHEA PEREZ\n'
          'APELLIDOS\n'
          'ODETTE FRANCCESCA\n'
          'PRENOMBRES',
        );

        final fields = hunter.snapshot.fields;
        expect(fields.lastName, 'GOICOCHEA');
        expect(fields.secondLastName, 'PEREZ');
        expect(fields.firstName, 'ODETTE FRANCCESCA');
      });
    });
  });
}
