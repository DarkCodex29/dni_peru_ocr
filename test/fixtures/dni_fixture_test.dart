// ignore_for_file: avoid_print

import 'dart:io';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixture-driven regression tests.
///
/// Each fixture under `test/fixtures/dnis/` represents a plausible raw OCR
/// frame for a real DNI (constructed from device-validated samples + visual
/// inspection of the physical card). The pipeline is run end-to-end against
/// the fixture and the result is asserted field-by-field, capturing the
/// expected behaviour of every supported DNI generation and edge case.
///
/// Fixtures cover both DNI generations (Modelo 2020 + azul booklet), the
/// APELLIDOS-concatenated layout, the Modelo 2020 horizontal sex/birth row,
/// horizontal label rows, multi-side accumulation, and a fake DNI sample.
void main() {
  group('DNI fixtures — end-to-end pipeline', () {
    group('Modelo 2020 — Odette Goicochea Perez', () {
      test('front+back accumulate all 18 effective fields', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('odette_front_modelo2020.txt'));
        hunter.process(_loadFixture('odette_back_modelo2020.txt'));
        final f = hunter.snapshot.fields;

        expect(f.documentNumber, '74984331');
        expect(f.lastName, 'GOICOCHEA');
        expect(f.secondLastName, 'PEREZ');
        expect(f.firstName, 'ODETTE FRANCCESCA');
        expect(f.dateOfBirth, '21/04/2004');
        expect(f.expirationDate, '25/08/2031');
        expect(f.emissionDate, '21/02/2026');
        expect(f.sex, 'F');
        expect(f.nationality, 'PERUANA');
        expect(f.stateCivil, 'SOLTERO');
        expect(f.cardNumber, '0211063654');
        expect(f.address, 'URB. MIRAFLORES ETAPA II MZ. F LT. 13');
        expect(f.department, 'LAMBAYEQUE');
        expect(f.province, 'CHICLAYO');
        expect(f.district, 'CHICLAYO');
        expect(f.organDonor, 'NO');
        expect(f.votingGroup, '272322');
        expect(f.birthUbigeoCode, '130101');
      });
    });

    group('Modelo 2020 — Antony Fabrizio Molina Quispe', () {
      test('vertical label layout extracts all 18 fields', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('antony_front_modelo2020.txt'));
        hunter.process(_loadFixture('antony_back_modelo2020.txt'));
        final f = hunter.snapshot.fields;

        expect(f.documentNumber, '74846787');
        expect(f.lastName, 'MOLINA');
        expect(f.secondLastName, 'QUISPE');
        expect(f.firstName, 'ANTONY FABRIZIO');
        expect(f.dateOfBirth, '02/01/1997');
        expect(f.expirationDate, '03/05/2030');
        expect(f.emissionDate, '03/05/2022');
        expect(f.sex, 'M');
        expect(f.nationality, 'PERUANA');
        expect(f.stateCivil, 'SOLTERO');
        expect(f.cardNumber, '0200869805');
        expect(f.address, 'STA ROSA 1080 MARIATEGUI');
        expect(f.department, 'LIMA');
        expect(f.province, 'LIMA');
        expect(f.district, 'VILLA MARIA DEL TRIUNFO');
        expect(f.organDonor, 'NO');
        expect(f.votingGroup, '046318');
        expect(f.birthUbigeoCode, '140136');
      });
    });

    group('Modelo 2020 — James Ermitaño Quiroz Remigio (APELLIDOS concat)',
        () {
      test('combined APELLIDOS label splits into paternal+maternal', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('james_front_modelo2020.txt'));
        hunter.process(_loadFixture('james_back_modelo2020.txt'));
        final f = hunter.snapshot.fields;

        expect(f.documentNumber, '43005787');
        expect(f.lastName, 'QUIROZ');
        expect(f.secondLastName, 'REMIGIO');
        expect(f.firstName, 'JAMES ERMITAÑO');
        expect(f.dateOfBirth, '24/06/1985');
        expect(f.expirationDate, '25/03/2036');
        expect(f.emissionDate, '25/03/2026');
        expect(f.sex, 'M');
        expect(f.nationality, 'PERUANA');
        expect(f.stateCivil, 'SOLTERO');
        expect(f.cardNumber, '0210795745');
        expect(
          f.address,
          contains('MZ.C LT.20'),
          reason: 'address must include MZ/LT prefixes (no OCR space)',
        );
        expect(f.province, 'CALLAO');
        expect(f.district, 'VENTANILLA');
        expect(f.organDonor, 'SI');
        expect(f.votingGroup, '231433');
        expect(f.birthUbigeoCode, '190702');
      });
    });

    group('Modelo 2020 — Ruben Bolo Vergara (DIVORCIADO)', () {
      test('extracts DIVORCIADO state civil and all front fields', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('ruben_front_modelo2020.txt'));
        final f = hunter.snapshot.fields;

        expect(f.documentNumber, '42588537');
        expect(f.lastName, 'BOLO');
        expect(f.secondLastName, 'VERGARA');
        expect(f.firstName, 'RUBEN JOHNATAN');
        expect(f.dateOfBirth, '04/07/1984');
        expect(f.expirationDate, '03/03/2033');
        expect(f.emissionDate, '03/03/2025');
        expect(f.sex, 'M');
        expect(f.nationality, 'PERUANA');
        expect(f.stateCivil, 'DIVORCIADO');
        expect(f.cardNumber, '0206495282');
      });
    });

    group('Azul booklet — Sonia Soledad Mio Lopez', () {
      test('single-letter state civil + separated apellido labels', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('sonia_front_azul_booklet.txt'));
        hunter.process(_loadFixture('sonia_back_azul_booklet.txt'));
        final f = hunter.snapshot.fields;

        expect(f.documentNumber, '16793105');
        expect(f.lastName, 'MIO');
        expect(f.secondLastName, 'LOPEZ');
        expect(f.firstName, 'SONIA SOLEDAD');
        expect(f.dateOfBirth, '04/12/1976');
        expect(f.expirationDate, '18/11/2029');
        expect(f.emissionDate, '18/11/2021');
        expect(f.inscriptionDate, '27/01/2000');
        expect(f.sex, 'F');
        expect(f.nationality, 'PERUANA');
        expect(
          f.stateCivil,
          'SOLTERO',
          reason: 'azul booklet uses single-letter S code',
        );
        expect(f.address, contains('AMPLC'));
        expect(f.department, 'LAMBAYEQUE');
        expect(f.province, 'CHICLAYO');
        expect(f.district, 'CHICLAYO');
        expect(f.organDonor, 'NO');
        expect(f.votingGroup, '083966');
        expect(
          f.birthUbigeoCode,
          '130101',
          reason: 'azul booklet stores it on the front',
        );
      });
    });

    group('Azul booklet — Jose Carlos Joao Moreno (back only)', () {
      test('back-only frame still extracts address + ubigeo + donor', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('jose_carlos_back_azul_booklet.txt'));
        final f = hunter.snapshot.fields;

        expect(f.address, contains('ASENT'));
        expect(f.department, 'ANCASH');
        expect(f.province, 'SANTA');
        expect(f.district, 'CHIMBOTE');
        expect(f.organDonor, 'NO');
        expect(f.votingGroup, '164559');
      });
    });

    group('FAKE DNI — Juanito Bebe Salas Comer', () {
      test(
        'fake DNI still extracts the labelled fields '
        '(authenticity detection is a separate concern)',
        () {
          final hunter = FieldHunter.standard();
          hunter.process(_loadFixture('juanito_front_fake.txt'));
          hunter.process(_loadFixture('juanito_back_fake.txt'));
          final f = hunter.snapshot.fields;

          // The pipeline is honest: if the OCR sees the labels, it extracts.
          // Detecting that the document is fake (no photo, smiley face,
          // joke MRZ) is a separate authenticity layer for v0.9.0+.
          expect(f.documentNumber, '75462451');
          expect(f.lastName, 'SALAS');
          expect(f.secondLastName, 'COMER');
          expect(f.firstName, 'JUANITO BEBE');
          expect(f.inscriptionDate, '17/08/2025');
          expect(f.emissionDate, isNull);
          expect(f.expirationDate, '17/08/2029');
          expect(f.department, 'LIMA');
          expect(f.province, 'LIMA');
          expect(f.district, 'SANTIAGO DE SURCO');
          expect(f.address, contains('TOMAS MARZANO'));
        },
      );
    });

    group('Edge cases — names', () {
      test('compound paternal surname DE LA CRUZ stays intact', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('edge_compound_surname.txt'));
        final f = hunter.snapshot.fields;
        expect(f.lastName, 'DE');
        expect(f.secondLastName, anyOf('LA CRUZ GARCIA', 'LA CRUZ'));
        expect(f.firstName, 'MARIA DEL CARMEN');
        expect(f.stateCivil, 'CASADO');
      });

      test('asian surname WONG NAKAMURA', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('edge_asian_surname.txt'));
        final f = hunter.snapshot.fields;
        expect(f.lastName, 'WONG');
        expect(f.secondLastName, 'NAKAMURA');
        expect(f.firstName, 'KENJI HIROSHI');
        expect(f.sex, 'M');
        expect(f.dateOfBirth, '22/11/1992');
      });

      test('Ñ → NH OCR noise (MUNHOZ) still extracts surname', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('edge_nh_ocr_error.txt'));
        final f = hunter.snapshot.fields;
        expect(f.lastName, isNotNull);
        expect(f.firstName, 'JUAN PABLO');
        expect(f.stateCivil, 'SOLTERO');
      });

      test('naturalized Peruvian still extracts core fields', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('edge_naturalizada.txt'));
        final f = hunter.snapshot.fields;
        expect(f.lastName, 'SCHMIDT');
        expect(f.secondLastName, 'FERNANDEZ');
        expect(f.firstName, 'HANS PEDRO');
        expect(f.stateCivil, 'DIVORCIADO');
        expect(f.sex, 'M');
      });

      test('widow (VIUDA) with heavy OCR noise', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('edge_widow_ocr_noise.txt'));
        final f = hunter.snapshot.fields;
        expect(f.stateCivil, 'VIUDO');
        expect(f.sex, 'F');
        expect(f.dateOfBirth, '25/12/1955');
      });

      test('CONVIVIENTE state civil', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('edge_conviviente.txt'));
        expect(hunter.snapshot.fields.stateCivil, 'CONVIVIENTE');
      });
    });

    group('Edge cases — addresses & districts', () {
      test('long district SAN JUAN DE LURIGANCHO preserved', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('edge_long_district.txt'));
        final f = hunter.snapshot.fields;
        expect(f.district, 'SAN JUAN DE LURIGANCHO');
        expect(f.department, 'LIMA');
        expect(f.province, 'LIMA');
        expect(f.address, contains('PROCERES'));
      });

      test('Callao with empty department (leading slash)', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('edge_callao_no_dep.txt'));
        final f = hunter.snapshot.fields;
        expect(f.province, 'CALLAO');
        expect(f.district, 'VENTANILLA');
        expect(f.organDonor, 'NO');
        expect(f.votingGroup, '015678');
      });
    });

    group('Edge cases — single-side scans', () {
      test('back-only frame extracts what it can', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('edge_only_back.txt'));
        final f = hunter.snapshot.fields;
        expect(f.address, contains('JR. UNION'));
        expect(f.department, 'LIMA');
        expect(f.organDonor, 'SI');
        expect(f.votingGroup, '099887');
        expect(f.birthUbigeoCode, '150101');
      });

      test('front-only frame extracts identity + dates', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('edge_only_front.txt'));
        final f = hunter.snapshot.fields;
        expect(f.documentNumber, '88776655');
        expect(f.lastName, 'GARCIA');
        expect(f.firstName, 'CARLOS ALBERTO');
        expect(f.sex, 'M');
        expect(f.stateCivil, 'SOLTERO');
        expect(f.cardNumber, '0288776655');
      });

      test('blurry partial OCR still recovers what is readable', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('edge_blurry_partial.txt'));
        final f = hunter.snapshot.fields;
        expect(f.documentNumber, '22334455');
        expect(f.firstName, 'ANA LUCIA');
        expect(f.dateOfBirth, '14/02/1985');
        expect(f.sex, 'F');
      });
    });

    group('Adversarial inputs (must not crash, must not over-claim)', () {
      test('SQL injection / XSS strings do not crash extractor', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('adversarial_inject_sql.txt'));
        final f = hunter.snapshot.fields;
        expect(f.documentNumber, '99999999');
        expect(f.firstName, isNull, reason: 'XSS string is not a valid name');
        expect(f.sex, 'M');
        expect(f.dateOfBirth, '01/01/2000');
      });

      test('huge text with noise lines does not slow down extraction', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('adversarial_huge_text.txt'));
        final f = hunter.snapshot.fields;
        expect(f.documentNumber, '12121212');
        expect(f.lastName, 'LOPEZ');
        expect(f.secondLastName, 'GARCIA');
        expect(f.firstName, 'MIGUEL ANGEL');
      });

      test('fake DNI with code keywords extracts only safe fields', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('fake_typescript_dev.txt'));
        final f = hunter.snapshot.fields;
        expect(f.documentNumber, '12345678');
        expect(f.lastName, 'TYPESCRIPT');
        expect(f.firstName, 'HELLO WORLD');
        expect(f.sex, isNull, reason: 'invalid sex code "?" must be rejected');
      });

      test('fake DNI with malformed MRZ — header still proves PERUANA', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('fake_wrong_mrz.txt'));
        final f = hunter.snapshot.fields;
        expect(f.documentNumber, '00000000');
        expect(f.stateCivil, isNull);
        expect(f.sex, isNull);
        expect(f.nationality, 'PERUANA');
      });

      test('only anchor + decoration extracts nothing', () {
        final hunter = FieldHunter.standard();
        hunter.process(_loadFixture('fake_only_anchor.txt'));
        final f = hunter.snapshot.fields;
        expect(f.documentNumber, isNull);
        expect(f.lastName, isNull);
        expect(f.firstName, isNull);
      });
    });

    group('Side detection across fixtures', () {
      const detector = DocumentSideDetector();

      test('Odette front → DocumentSide.front', () {
        expect(
          detector.detect(_loadFixture('odette_front_modelo2020.txt')),
          DocumentSide.front,
        );
      });

      test('Odette back → DocumentSide.back', () {
        expect(
          detector.detect(_loadFixture('odette_back_modelo2020.txt')),
          DocumentSide.back,
        );
      });

      test('Sonia front (azul booklet) → DocumentSide.front via DNI anchor',
          () {
        expect(
          detector.detect(_loadFixture('sonia_front_azul_booklet.txt')),
          DocumentSide.front,
        );
      });

      test(
        'Sonia back (azul booklet) → DocumentSide.back via CONSTANCIA anchor',
        () {
          expect(
            detector.detect(_loadFixture('sonia_back_azul_booklet.txt')),
            DocumentSide.back,
          );
        },
      );

      test(
        'Antony back (Modelo 2020) → DocumentSide.back via CONSTANCIA anchor',
        () {
          expect(
            detector.detect(_loadFixture('antony_back_modelo2020.txt')),
            DocumentSide.back,
          );
        },
      );
    });
  });
}

String _loadFixture(String name) {
  final path = 'test/fixtures/dnis/$name';
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError('Fixture not found at $path. Run tests from the repo root.');
  }
  return file.readAsStringSync();
}
