import 'dart:math' as math;

import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Builds a [TextBlock] containing exactly the lines passed in.
/// The block text is `\n`-joined so the extractor's text-block fallback sees
/// each line independently. Bounding box is irrelevant for these tests.
TextBlock _makeTextBlock(List<String> lines) {
  const box = Rect.fromLTWH(0, 0, 100, 100);
  return TextBlock(
    text: lines.join('\n'),
    lines: const [],
    boundingBox: box,
    recognizedLanguages: const ['es'],
    cornerPoints: [
      math.Point(box.left.toInt(), box.top.toInt()),
      math.Point(box.right.toInt(), box.top.toInt()),
      math.Point(box.right.toInt(), box.bottom.toInt()),
      math.Point(box.left.toInt(), box.bottom.toInt()),
    ],
  );
}

RecognizedText _recognizedFromLines(List<String> lines) =>
    RecognizedText(text: lines.join('\n'), blocks: [_makeTextBlock(lines)]);

// ── Test logger ───────────────────────────────────────────────────────────

/// Captures breadcrumbs emitted via [OcrLogger].
class _CapturingOcrLogger implements OcrLogger {
  final List<_LoggedEvent> events = [];

  @override
  void breadcrumb(
    String category,
    String message, {
    Map<String, Object?>? data,
  }) {
    events.add(_LoggedEvent(category, message, data));
  }
}

class _LoggedEvent {
  const _LoggedEvent(this.category, this.message, this.data);
  final String category;
  final String message;
  final Map<String, Object?>? data;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Builds an [OcrExtractedFields] with text-OCR sourced values.
OcrExtractedFields textFields({String? documentNumber}) =>
    OcrExtractedFields()..documentNumber = documentNumber;
// _fromMrz stays false by default — text-OCR sourced.

/// Builds an [OcrExtractedFields] with MRZ-sourced values.
OcrExtractedFields mrzFields({String? documentNumber}) {
  final f = OcrExtractedFields()
    ..fromMrzForTest = true
    ..documentNumber = documentNumber;
  return f;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Group 1 — MRZ wins over text OCR on merge.
  // ─────────────────────────────────────────────────────────────────────────
  group('merge — MRZ wins over text-OCR', () {
    test(
      'merge MRZ frame into text-OCR accumulator → MRZ value overwrites',
      () {
        final accumulator = textFields(documentNumber: '71542835'); // wrong OCR
        final incoming = mrzFields(documentNumber: '71542895'); // correct MRZ

        accumulator.merge(incoming);

        expect(accumulator.documentNumber, '71542895');
      },
    );

    test(
      'merge text-OCR frame into MRZ accumulator → MRZ value is kept',
      () {
        final accumulator = mrzFields(
          documentNumber: '71542895',
        ); // correct MRZ
        final incoming = textFields(documentNumber: '71542835'); // bad text OCR

        accumulator.merge(incoming);

        expect(accumulator.documentNumber, '71542895');
      },
    );

    test(
      'merge MRZ frame when accumulator is empty → MRZ value is stored',
      () {
        final accumulator = OcrExtractedFields();
        final incoming = mrzFields(documentNumber: '71542895');

        accumulator.merge(incoming);

        expect(accumulator.documentNumber, '71542895');
        expect(accumulator.hasMrzData, isTrue);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 2 — Logger breadcrumb on OCR/MRZ mismatch.
  // ─────────────────────────────────────────────────────────────────────────
  group('merge — logger breadcrumb on OCR/MRZ mismatch', () {
    late _CapturingOcrLogger capturingLogger;

    setUp(() {
      capturingLogger = _CapturingOcrLogger();
    });

    test(
      'OCR and MRZ differ → breadcrumb added with both values',
      () {
        final accumulator = textFields(documentNumber: '71542835');
        final incoming = mrzFields(documentNumber: '71542895');

        accumulator.merge(incoming, logger: capturingLogger);

        expect(capturingLogger.events, hasLength(1));
        final ev = capturingLogger.events.first;
        expect(ev.category, 'kyc-ocr-mrz-mismatch');
        expect(ev.message, contains('71542835'));
        expect(ev.message, contains('71542895'));
        expect(ev.data, isNotNull);
        expect(ev.data!['field'], 'documentNumber');
        expect(ev.data!['ocr'], '71542835');
        expect(ev.data!['mrz'], '71542895');
      },
    );

    test(
      'OCR and MRZ are identical → no breadcrumb added',
      () {
        final accumulator = textFields(documentNumber: '71542895');
        final incoming = mrzFields(documentNumber: '71542895');

        accumulator.merge(incoming, logger: capturingLogger);

        expect(capturingLogger.events, isEmpty);
      },
    );

    test(
      'no existing OCR value → no breadcrumb (nothing to compare)',
      () {
        final accumulator = OcrExtractedFields(); // no documentNumber
        final incoming = mrzFields(documentNumber: '71542895');

        accumulator.merge(incoming, logger: capturingLogger);

        expect(capturingLogger.events, isEmpty);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 3 — Name fields routed through normalizeForDisplay.
  // ─────────────────────────────────────────────────────────────────────────
  group('extract — names denoised + uppercased via normalizeForDisplay', () {
    test(
      'noisy MUNXXOZ on lastName label → stored as MUÑOZ',
      () {
        final rt = _recognizedFromLines(const [
          'PRIMER APELLIDO',
          'MUNXXOZ',
          'SEGUNDO APELLIDO',
          'GARCIA',
          'PRENOMBRES',
          'JUAN CARLOS',
          'DNI 12345678',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.lastName, 'MUÑOZ');
        expect(result.secondLastName, 'GARCIA');
        expect(result.firstName, 'JUAN CARLOS');
      },
    );

    test(
      'noisy on all three name fields → all denoised to Ñ form',
      () {
        final rt = _recognizedFromLines(const [
          'PRIMER APELLIDO',
          'MUNXXOZ',
          'SEGUNDO APELLIDO',
          'ERMITANXXO',
          'PRENOMBRES',
          'JUAN',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.lastName, 'MUÑOZ');
        expect(result.secondLastName, 'ERMITAÑO');
        expect(result.firstName, 'JUAN');
      },
    );

    test(
      'clean Ñ on a label-extracted name → preserved unchanged',
      () {
        final rt = _recognizedFromLines(const [
          'PRIMER APELLIDO',
          'MUÑOZ',
          'PRENOMBRES',
          'PEDRO',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.lastName, 'MUÑOZ');
        expect(result.firstName, 'PEDRO');
      },
    );

    test(
      'document number and DNI label are untouched by name normalizer',
      () {
        final rt = _recognizedFromLines(const [
          'DNI 12345678',
          'PRIMER APELLIDO',
          'MUNXXOZ',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.documentNumber, '12345678');
        expect(result.lastName, 'MUÑOZ');
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 4 — Real Peruvian DNI labels with Ñ/tildes.
  //
  // Uses the real DNI label strings the extractor recognizes
  // (`PRIMER APELLIDO`, `SEGUNDO APELLIDO`, `PRENOMBRES`). The Peruvian DNI
  // does NOT use plain `APELLIDOS` / `NOMBRES` — those are filtered as
  // forbidden tokens by `_isPersonName`. Address recovery uses `DOMICILIO`
  // or the Peruvian address-prefix strategy (`AV.`, `JR.`, `CALLE`, etc.),
  // not a `DIRECCIÓN` label (the DNI does not print that label).
  //
  // Known limitations explicitly encoded as test expectations:
  //   • Only Ñ is recovered from `NXX` noise. Other tildes (Á, É, Í, Ó, Ú)
  //     are NOT recoverable when OCR drops them at the source.
  //   • Address content is uppercased+trimmed only — there is no NXX
  //     denoise step on the address pipeline.
  // ─────────────────────────────────────────────────────────────────────────
  group('Real Peruvian DNI labels with Ñ/tildes', () {
    test(
      'noisy paterno+materno: IBANXXEZ + MARINXXO → IBAÑEZ + MARIÑO',
      () {
        final rt = _recognizedFromLines(const [
          'PRIMER APELLIDO',
          'IBANXXEZ',
          'SEGUNDO APELLIDO',
          'MARINXXO',
          'PRENOMBRES',
          'JUAN',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.lastName, 'IBAÑEZ');
        expect(result.secondLastName, 'MARIÑO');
        expect(result.firstName, 'JUAN');
      },
    );

    test(
      'clean MUÑOZ + PEÑA preserved as-is',
      () {
        final rt = _recognizedFromLines(const [
          'PRIMER APELLIDO',
          'MUÑOZ',
          'SEGUNDO APELLIDO',
          'PEÑA',
          'PRENOMBRES',
          'JUAN CARLOS',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.lastName, 'MUÑOZ');
        expect(result.secondLastName, 'PEÑA');
        expect(result.firstName, 'JUAN CARLOS');
      },
    );

    test(
      'compound first name MARÍA JESÚS with tildes preserved',
      () {
        final rt = _recognizedFromLines(const [
          'PRIMER APELLIDO',
          'GARCIA',
          'PRENOMBRES',
          'MARÍA JESÚS',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.firstName, 'MARÍA JESÚS');
      },
    );

    test(
      'first name JUAN ÁNGEL with tilde preserved',
      () {
        final rt = _recognizedFromLines(const [
          'PRIMER APELLIDO',
          'PEREZ',
          'PRENOMBRES',
          'JUAN ÁNGEL',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.firstName, 'JUAN ÁNGEL');
      },
    );

    test(
      'all four name slots with diacritics preserved end-to-end',
      () {
        final rt = _recognizedFromLines(const [
          'PRIMER APELLIDO',
          'CASTAÑEDA',
          'SEGUNDO APELLIDO',
          'NÚÑEZ',
          'PRENOMBRES',
          'JOSÉ ANDRÉS',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.lastName, 'CASTAÑEDA');
        expect(result.secondLastName, 'NÚÑEZ');
        expect(result.firstName, 'JOSÉ ANDRÉS');
      },
    );

    test(
      'worst case: noisy surnames + tilde-less first names — '
      'Ñ recovered, other tildes lost (known limitation)',
      () {
        final rt = _recognizedFromLines(const [
          'PRIMER APELLIDO',
          'CASTANXXEDA',
          'SEGUNDO APELLIDO',
          'NUNXXEZ',
          'PRENOMBRES',
          'JOSE ANDRES',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        // Ñ recovered from both surnames.
        expect(result.lastName, 'CASTAÑEDA');
        // Note: Ú in NÚÑEZ is NOT recoverable from `NUNXXEZ` — only Ñ is.
        expect(result.secondLastName, 'NUÑEZ');
        // First names with no diacritics in OCR stay ASCII (Á, É lost).
        expect(result.firstName, 'JOSE ANDRES');
      },
    );

    test(
      'DOMICILIO label with Peruvian address (JR. CAÑETE 123 BREÑA)',
      () {
        final rt = _recognizedFromLines(const [
          'PRIMER APELLIDO',
          'GARCIA',
          'DOMICILIO',
          'JR. CAÑETE 123 BREÑA',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        // Address is uppercased + trimmed; Ñ chars preserved as-is.
        expect(result.address, 'JR. CAÑETE 123 BREÑA');
      },
    );

    test(
      'Peruvian address prefix (AV.) — picked up without DOMICILIO label',
      () {
        final rt = _recognizedFromLines(const [
          'PRIMER APELLIDO',
          'GARCIA',
          'AV. ESPAÑA 890 LIMA',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.address, 'AV. ESPAÑA 890 LIMA');
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 5 — Address noise filtering: QR/barcode artifacts.
  //
  // Real production case on Peruvian DNI electrónico back:
  //   OCR returned "WHAPP AGE 0-- AT 220S MG MZ.CL20 3ER SECTOR
  //                 URB.ANTONIA MORENO DE CACERES DIRECCIS"
  //   Real printed address: "MZ.C LT.20 3ER SECTOR URB.ANTONIA MORENO
  //                          DE CACERES"
  //
  // Root cause: Strategy 3 (ubigeo anchor) walked up 4 lines and appended
  // ALL lines passing the very permissive `_isValidAddress`, including QR
  // module text read as Latin ("WHAPP AGE 0-- AT 220S MG") and the
  // corrupted "Dirección" label ("DIRECCIS").
  //
  // Fix: hybrid filter — per-line noise ratio (>40% non-address tokens
  // drops the whole line), plus label-tail strip at head and tail of the
  // joined address.
  // ─────────────────────────────────────────────────────────────────────────
  group('Address noise filtering — QR/barcode artifacts', () {
    test(
      'real prod case: QR noise above, label corruption below, '
      'ubigeo anchor — real address recovered, noise dropped',
      () {
        final rt = _recognizedFromLines(const [
          'WHAPP AGE 0-- AT 220S MG',
          'MZ.C LT.20 3ER SECTOR URB.ANTONIA MORENO DE CACERES',
          'DIRECCIS',
          '/CALLAO/VENTANILLA',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(
          result.address,
          'MZ.C LT.20 3ER SECTOR URB.ANTONIA MORENO DE CACERES',
        );
      },
    );

    test(
      'clean control: same address without surrounding noise',
      () {
        final rt = _recognizedFromLines(const [
          'MZ.C LT.20 3ER SECTOR URB.ANTONIA MORENO DE CACERES',
          '/CALLAO/VENTANILLA',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(
          result.address,
          'MZ.C LT.20 3ER SECTOR URB.ANTONIA MORENO DE CACERES',
        );
      },
    );

    test('AV. SANTA ROSA 1080 MARIATEGUI above LIMA ubigeo', () {
      final rt = _recognizedFromLines(const [
        'AV. SANTA ROSA 1080 MARIATEGUI',
        '/LIMA/LIMA/VILLA MARIA DEL TRIUNFO',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'AV. SANTA ROSA 1080 MARIATEGUI');
    });

    test('JR. CAÑETE 123 BREÑA preserved with Ñ', () {
      final rt = _recognizedFromLines(const [
        'JR. CAÑETE 123 BREÑA',
        '/LIMA/LIMA/BREÑA',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'JR. CAÑETE 123 BREÑA');
    });

    test('AV. JOSÉ GÁLVEZ with tildes preserved', () {
      final rt = _recognizedFromLines(const [
        'AV. JOSÉ GÁLVEZ 789 MAGDALENA DEL MAR',
        '/LIMA/LIMA/MAGDALENA DEL MAR',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'AV. JOSÉ GÁLVEZ 789 MAGDALENA DEL MAR');
    });

    test('PP.JJ. HUAYCÁN ZONA C — community settlement prefix', () {
      final rt = _recognizedFromLines(const [
        'PP.JJ. HUAYCÁN ZONA C',
        '/LIMA/ATE/ATE',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'PP.JJ. HUAYCÁN ZONA C');
    });

    test('AAHH SAN MARTIN MZ.B LT.5 — informal settlement', () {
      final rt = _recognizedFromLines(const [
        'AAHH SAN MARTIN MZ.B LT.5',
        '/LIMA/LIMA/SAN JUAN DE LURIGANCHO',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'AAHH SAN MARTIN MZ.B LT.5');
    });

    test('URB. LOS PINOS ETAPA II MZ.A LT.15 — roman numeral preserved', () {
      final rt = _recognizedFromLines(const [
        'URB. LOS PINOS ETAPA II MZ.A LT.15',
        '/LIMA/LIMA/SAN BORJA',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'URB. LOS PINOS ETAPA II MZ.A LT.15');
    });

    test('all-noise lines above ubigeo → address is null', () {
      final rt = _recognizedFromLines(const [
        'M2 0-- < >> 22S',
        'WHAPP AGE 0-- AT 220S MG',
        '/CALLAO/VENTANILLA',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, isNull);
    });

    test('QR-like prefix on its own line, valid address mid-block', () {
      final rt = _recognizedFromLines(const [
        '0-- M2 22S',
        'AV. ARGENTINA 4490',
        '/CALLAO/CALLAO',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'AV. ARGENTINA 4490');
    });

    test('DIRECCION label glued to head of address → stripped from head', () {
      final rt = _recognizedFromLines(const [
        'DIRECCION MZ.C LT.20 SECTOR ANTONIA MORENO',
        '/CALLAO/VENTANILLA',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'MZ.C LT.20 SECTOR ANTONIA MORENO');
    });

    test('DIRECCI label variant glued to tail → stripped from tail', () {
      final rt = _recognizedFromLines(const [
        'MZ.A LT.5 URB. SAN JOSE DIRECCI',
        '/LIMA/LIMA/LIMA',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'MZ.A LT.5 URB. SAN JOSE');
    });

    test('DOMICILIO label (Strategy 1) → label stripped from value', () {
      // DOMICILIO triggers Strategy 1, which replaces the label prefix.
      // The result should not contain "DOMICILIO" at the head.
      final rt = _recognizedFromLines(const [
        'DOMICILIO AV. PERU 100',
        '/LIMA/LIMA/LIMA',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, isNotNull);
      expect(result.address!.startsWith('DOMICILIO'), isFalse);
      expect(result.address, contains('AV. PERU 100'));
    });

    test('address with Y connector preserved (multiple street names)', () {
      final rt = _recognizedFromLines(const [
        'AV. JOSÉ GÁLVEZ Y MARÍA REICHE 100',
        '/LIMA/SURCO/SURCO',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'AV. JOSÉ GÁLVEZ Y MARÍA REICHE 100');
    });

    test('JR. LOS OLIVOS 234 with ñ in BREÑA ubigeo', () {
      final rt = _recognizedFromLines(const [
        'JR. LOS OLIVOS 234',
        '/LIMA/LIMA/BREÑA',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'JR. LOS OLIVOS 234');
    });

    test('URB. SANTA PATRICIA III ETAPA MZ.D LT.3 — roman III preserved', () {
      final rt = _recognizedFromLines(const [
        'URB. SANTA PATRICIA III ETAPA MZ.D LT.3',
        '/LIMA/LA MOLINA/LA MOLINA',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'URB. SANTA PATRICIA III ETAPA MZ.D LT.3');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 6 — Unit tests on the address noise filter helpers.
  //
  // These hit `OcrFieldExtractor.cleanAddressLine` and
  // `OcrFieldExtractor.stripAddressLabelTail` directly, so we can pin the
  // exact verdict on edge cases without going through ML Kit's block model.
  // ─────────────────────────────────────────────────────────────────────────
  group('cleanAddressLine — per-line noise filter', () {
    test('valid address with prefix+code+words → kept as-is', () {
      expect(
        OcrFieldExtractor.cleanAddressLine(
          'MZ. C LT. 20 3ER SECTOR URB. ANTONIA MORENO DE CACERES',
        ),
        'MZ. C LT. 20 3ER SECTOR URB. ANTONIA MORENO DE CACERES',
      );
    });

    test('QR module text "WHAPP AGE 0-- AT 220S MG" → null (noise > 40%)', () {
      expect(
        OcrFieldExtractor.cleanAddressLine('WHAPP AGE 0-- AT 220S MG'),
        isNull,
      );
    });

    test('pure barcode-like "M2 0-- < >> 22S" → null', () {
      expect(
        OcrFieldExtractor.cleanAddressLine('M2 0-- < >> 22S'),
        isNull,
      );
    });

    test('alphanumeric MZ.CL20 token preserved (no spaces variant)', () {
      expect(
        OcrFieldExtractor.cleanAddressLine(
          'MZ.CL20 3ER SECTOR URB.ANTONIA MORENO DE CACERES',
        ),
        'MZ.CL20 3ER SECTOR URB.ANTONIA MORENO DE CACERES',
      );
    });

    test('single lonely connector "DE" → null (1 token, no context)', () {
      expect(OcrFieldExtractor.cleanAddressLine('DE'), isNull);
    });

    test('clean AV address kept as-is', () {
      expect(
        OcrFieldExtractor.cleanAddressLine('AV. ARGENTINA 4490 CALLAO'),
        'AV. ARGENTINA 4490 CALLAO',
      );
    });

    test('empty input → null', () {
      expect(OcrFieldExtractor.cleanAddressLine(''), isNull);
    });

    test('URB. LOS PINOS ETAPA II MZ.A LT.15 kept (roman II)', () {
      expect(
        OcrFieldExtractor.cleanAddressLine(
          'URB. LOS PINOS ETAPA II MZ.A LT.15',
        ),
        'URB. LOS PINOS ETAPA II MZ.A LT.15',
      );
    });

    test('JR. CAÑETE 123 BREÑA kept with Ñ', () {
      expect(
        OcrFieldExtractor.cleanAddressLine('JR. CAÑETE 123 BREÑA'),
        'JR. CAÑETE 123 BREÑA',
      );
    });

    test(
      'mixed "MZ.A LT.5 WHAPP 0-- 22S" — 2/5 tokens noise (0.4) → kept (not strictly > 40%)',
      () {
        // 5 tokens: MZ.A, LT.5, WHAPP, 0--, 22S
        //   MZ.A → prefix.code combo
        //   LT.5 → prefix.code combo
        //   WHAPP → has vowel A. consonants WHPP=3 vs vowel A=1 → 3 > 1*3 = 3, fails (>)
        //   0-- → noise (has "--")
        //   22S → digit+letter combo, length 3, isAlphanumericCode? 22S matches \d+[A-Z]+ → kept
        // noise count: WHAPP + 0-- = 2. ratio 2/5 = 0.4 — NOT > 0.4, so kept.
        expect(
          OcrFieldExtractor.cleanAddressLine('MZ.A LT.5 WHAPP 0-- 22S'),
          isNotNull,
        );
      },
    );
  });

  group(
    'stripAddressLabelTail — strip corrupted Dirección/Domicilio labels',
    () {
      test('DIRECCIS at tail → stripped', () {
        expect(
          OcrFieldExtractor.stripAddressLabelTail(
            'MZ.C LT.20 SECTOR ANTONIA MORENO DIRECCIS',
          ),
          'MZ.C LT.20 SECTOR ANTONIA MORENO',
        );
      });

      test('DIRECCION at tail → stripped', () {
        expect(
          OcrFieldExtractor.stripAddressLabelTail('MZ.C LT.20 DIRECCION'),
          'MZ.C LT.20',
        );
      });

      test('DIRECCION at head → stripped', () {
        expect(
          OcrFieldExtractor.stripAddressLabelTail('DIRECCION MZ.C LT.20'),
          'MZ.C LT.20',
        );
      });

      test('DOMICILIO at tail → stripped', () {
        expect(
          OcrFieldExtractor.stripAddressLabelTail('MZ.C LT.20 DOMICILIO'),
          'MZ.C LT.20',
        );
      });

      test('DOMICILI at head (corrupted) → stripped', () {
        expect(
          OcrFieldExtractor.stripAddressLabelTail('DOMICILI MZ.C LT.20'),
          'MZ.C LT.20',
        );
      });

      test('no label → no-op', () {
        expect(
          OcrFieldExtractor.stripAddressLabelTail('MZ.C LT.20'),
          'MZ.C LT.20',
        );
      });

      test('only label → empty string', () {
        expect(OcrFieldExtractor.stripAddressLabelTail('DIRECCION'), '');
      });
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Group 7 — CONSTANCIA DE SUFRAGIO.
  //
  // The back of the Peruvian DNI prints up to 4 "CONSTANCIA DE SUFRAGIO"
  // voting boxes near the address. ML Kit reads them as Latin text and
  // they pollute Strategy 3 (ubigeo anchor) because every token passes
  // the "likely Spanish word" heuristic.
  //
  // Strategy 3 must recover ONLY the real address line and drop every
  // CONSTANCIA / SUFRAGIO / GRUPO DE VOTACION fragment.
  // ─────────────────────────────────────────────────────────────────────────
  group('Address noise — CONSTANCIA DE SUFRAGIO', () {
    // Real-world end-to-end cases via ML Kit text blocks.

    test('case 1: 4 CONSTANCIA boxes above the real address', () {
      final rt = _recognizedFromLines(const [
        'CONSTANCIA DE SUFRAGIO',
        'CONSTANCIA DE SUFRAGIO',
        'CONSTANCIA DE SUFRAGIO',
        'CONSTANCIA DE SUFRAGIO',
        'STA ROSA 1080 MARIATEGUI',
        '/LIMA/LIMA/VILLA MARIA DEL TRIUNFO',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'STA ROSA 1080 MARIATEGUI');
    });

    test('case 2: ML Kit fragments the 4 boxes', () {
      final rt = _recognizedFromLines(const [
        'CONSTANCIA',
        'DE SUFRAGIO',
        'CONSTANCIA DE SUFRAGIO',
        'STA ROSA 1080 MARIATEGUI',
        '/LIMA/LIMA/VILLA MARIA DEL TRIUNFO',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'STA ROSA 1080 MARIATEGUI');
    });

    test('case 3: only a "DE SUFRAGIO" fragment near the address', () {
      final rt = _recognizedFromLines(const [
        'DE SUFRAGIO',
        'STA ROSA 1080 MARIATEGUI',
        '/LIMA/LIMA/VILLA MARIA DEL TRIUNFO',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'STA ROSA 1080 MARIATEGUI');
    });

    test(
      'case 4: noise joined into one line — must NOT contain "DE SUFRAGIO"',
      () {
        final rt = _recognizedFromLines(const [
          'DE SUFRAGIO DE SUFRAGIO STA ROSA 1080 MARIATEGUI',
          '/LIMA/LIMA/VILLA MARIA DEL TRIUNFO',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.address, isNotNull);
        expect(result.address, isNot(contains('SUFRAGIO')));
      },
    );

    test('case 5: CONSTANCIA + "Grupo de Votación 046318" above address', () {
      final rt = _recognizedFromLines(const [
        'CONSTANCIA DE SUFRAGIO',
        'Grupo de Votación 046318',
        'STA ROSA 1080 MARIATEGUI',
        '/LIMA/LIMA/VILLA MARIA DEL TRIUNFO',
      ]);

      final result = OcrFieldExtractor.extract(rt);

      expect(result.address, 'STA ROSA 1080 MARIATEGUI');
    });

    test(
      'case 6: QR noise + CONSTANCIA + DIRECCIS label + ubigeo combo',
      () {
        final rt = _recognizedFromLines(const [
          'WHAPP AGE 0--',
          'CONSTANCIA DE SUFRAGIO',
          'STA ROSA 1080 MARIATEGUI',
          'DIRECCIS',
          '/LIMA/LIMA/VILLA MARIA DEL TRIUNFO',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.address, 'STA ROSA 1080 MARIATEGUI');
      },
    );

    test(
      'case 7: CONSTANCIA appears INSIDE an otherwise-valid line — '
      'whole line should be rejected by the noise filter',
      () {
        final rt = _recognizedFromLines(const [
          'CONSTANCIA STA ROSA 1080',
          '/LIMA/LIMA/VILLA MARIA DEL TRIUNFO',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        // Either null (line rejected) or non-null without CONSTANCIA.
        if (result.address != null) {
          expect(result.address, isNot(contains('CONSTANCIA')));
        }
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 8 — Direct unit tests on cleanAddressLine for CONSTANCIA/SUFRAGIO.
  //
  // CONSTANCIA, SUFRAGIO, VOTACION are phonotactically valid Spanish
  // words, so the underlying classifier would otherwise pass them — the
  // denylist drops them at the token level.
  // ─────────────────────────────────────────────────────────────────────────
  group('cleanAddressLine — CONSTANCIA/SUFRAGIO tokens', () {
    test('"CONSTANCIA DE SUFRAGIO" alone → null (no address signal)', () {
      expect(
        OcrFieldExtractor.cleanAddressLine('CONSTANCIA DE SUFRAGIO'),
        isNull,
      );
    });

    test('"DE SUFRAGIO" alone → null', () {
      expect(OcrFieldExtractor.cleanAddressLine('DE SUFRAGIO'), isNull);
    });

    test('"SUFRAGIO" alone → null', () {
      expect(OcrFieldExtractor.cleanAddressLine('SUFRAGIO'), isNull);
    });

    test(
      '"Grupo de Votación 046318" → null (voting metadata, not address)',
      () {
        expect(
          OcrFieldExtractor.cleanAddressLine('Grupo de Votación 046318'),
          isNull,
        );
      },
    );

    test('"STA ROSA 1080 MARIATEGUI" → kept as-is (real address)', () {
      expect(
        OcrFieldExtractor.cleanAddressLine('STA ROSA 1080 MARIATEGUI'),
        'STA ROSA 1080 MARIATEGUI',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 9 — Direct unit tests on stripAddressLabelTail for SUFRAGIO/etc.
  //
  // The strip step is the second line of defense: even if a CONSTANCIA /
  // DE SUFRAGIO fragment gets joined into the address, it should be
  // removed at head/tail before the final assignment.
  // ─────────────────────────────────────────────────────────────────────────
  group('stripAddressLabelTail — CONSTANCIA/SUFRAGIO/VOTACION', () {
    test('"DE SUFRAGIO DE SUFRAGIO" at head → stripped', () {
      expect(
        OcrFieldExtractor.stripAddressLabelTail(
          'DE SUFRAGIO DE SUFRAGIO STA ROSA 1080 MARIATEGUI',
        ),
        'STA ROSA 1080 MARIATEGUI',
      );
    });

    test('"CONSTANCIA" at head → stripped', () {
      expect(
        OcrFieldExtractor.stripAddressLabelTail('CONSTANCIA STA ROSA 1080'),
        'STA ROSA 1080',
      );
    });

    test('"CONSTANCIA DE SUFRAGIO" at tail → stripped', () {
      expect(
        OcrFieldExtractor.stripAddressLabelTail(
          'STA ROSA 1080 CONSTANCIA DE SUFRAGIO',
        ),
        'STA ROSA 1080',
      );
    });

    test('"GRUPO DE VOTACION" at tail → stripped', () {
      expect(
        OcrFieldExtractor.stripAddressLabelTail(
          'STA ROSA 1080 GRUPO DE VOTACION',
        ),
        'STA ROSA 1080',
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 10 — Address noise: DNI FRONT-side labels (defense in depth).
  //
  // The denylist already covers BACK-side labels of the Peruvian DNI
  // (DOMICILIO, UBIGEO, CONSTANCIA, SUFRAGIO, …). This group extends it
  // with FRONT-side labels that ML Kit could leak into the address
  // extractor if the extractor sees both sides in one frame.
  //
  // Tokens added (safe — no realistic collision with address content):
  //   DOCUMENTO, IDENTIDAD, CUI, APELLIDO, APELLIDOS, PRENOMBRES,
  //   EMISION (→ EMISIÓN normalized), CADUCIDAD, TARJETA,
  //   NUMERO (→ NÚMERO normalized),
  //   SOLTERO/A, CASADO/A, DIVORCIADO/A, VIUDO/A, CONVIVIENTE.
  //
  // Tokens deliberately NOT added (would collide with real addresses):
  //   PRIMER, SEGUNDO — appear in real street names ("PRIMERA DE OCTUBRE")
  //   NOMBRE/NOMBRES   — too generic
  // ─────────────────────────────────────────────────────────────────────────
  group('Address noise — DNI front labels (defense in depth)', () {
    // ── cleanAddressLine — direct unit tests ──────────────────────────────

    group('cleanAddressLine — front-label rejection', () {
      test('"DOCUMENTO NACIONAL DE IDENTIDAD" → null (3/4 noise tokens)', () {
        expect(
          OcrFieldExtractor.cleanAddressLine('DOCUMENTO NACIONAL DE IDENTIDAD'),
          isNull,
        );
      });

      test('"ESTADO CIVIL SOLTERO" → null (3/3 denylist)', () {
        expect(
          OcrFieldExtractor.cleanAddressLine('ESTADO CIVIL SOLTERO'),
          isNull,
        );
      });

      test('"ESTADO CIVIL CASADO" → null (3/3 denylist)', () {
        expect(
          OcrFieldExtractor.cleanAddressLine('ESTADO CIVIL CASADO'),
          isNull,
        );
      });

      test('"ESTADO CIVIL DIVORCIADA" → null (3/3 denylist)', () {
        expect(
          OcrFieldExtractor.cleanAddressLine('ESTADO CIVIL DIVORCIADA'),
          isNull,
        );
      });

      test('"ESTADO CIVIL CONVIVIENTE" → null (3/3 denylist)', () {
        expect(
          OcrFieldExtractor.cleanAddressLine('ESTADO CIVIL CONVIVIENTE'),
          isNull,
        );
      });

      test('"Nº DE TARJETA 0210795745" → null (TARJETA + Nº as noise)', () {
        // Nº has no vowels → fails _isLikelySpanishWord → noise.
        // TARJETA → denylist (noise). DE → connector. Number → code.
        // 2 noise / 4 tokens = 50% > 40% → rejected.
        expect(
          OcrFieldExtractor.cleanAddressLine('Nº DE TARJETA 0210795745'),
          isNull,
        );
      });

      test('"APELLIDOS LOPEZ QUISPE" → null (structural anchor)', () {
        // APELLIDOS stripped by denylist; surviving LOPEZ QUISPE has no
        // address prefix and no numeric code, so `_hasAddressAnchor`
        // rejects the whole line. The person-name leak is closed.
        expect(
          OcrFieldExtractor.cleanAddressLine('APELLIDOS LOPEZ QUISPE'),
          isNull,
        );
      });

      test('"PRENOMBRES JUAN CARLOS" → null (structural anchor)', () {
        // Same shape as APELLIDOS LOPEZ QUISPE: only proper nouns survive
        // the denylist strip, no prefix, no number → anchor rejects.
        expect(
          OcrFieldExtractor.cleanAddressLine('PRENOMBRES JUAN CARLOS'),
          isNull,
        );
      });

      test('"CUI 74846787" → null (CUI noise + lone code, no content)', () {
        // CUI → denylist. 74846787 → code (counts as content).
        // 1 noise / 2 = 50% > 40% → rejected.
        expect(OcrFieldExtractor.cleanAddressLine('CUI 74846787'), isNull);
      });

      test(
        '"EMISIÓN 25 03 2026" → null (structural anchor)',
        () {
          // EMISIÓN → diacritic-stripped to EMISION → denylist.
          //   25, 03, 2026 → codes. 1 noise / 4 = 25% < 40% → kept as
          //   "25 03 2026" (date fragment leak).
          // Structural anchor: surviving tokens are all numeric — no
          //   proper-noun word. The anchor requires
          //   (prefix) OR (numeric AND proper-noun), so the line is
          //   rejected. The date fragment leak is closed.
          expect(
            OcrFieldExtractor.cleanAddressLine('EMISIÓN 25 03 2026'),
            isNull,
          );
        },
      );

      test('"AV. JOSÉ GÁLVEZ 789" → unchanged (clean control)', () {
        // Sanity check: a real Peruvian street must NOT be affected by the
        // expanded denylist.
        expect(
          OcrFieldExtractor.cleanAddressLine('AV. JOSÉ GÁLVEZ 789'),
          'AV. JOSÉ GÁLVEZ 789',
        );
      });

      test(
        '"AV. PRIMERA DE OCTUBRE 123" → unchanged (PRIMER intentionally NOT in denylist)',
        () {
          // Guard: confirms we did NOT add PRIMER/SEGUNDO to the denylist.
          // Real Peruvian streets contain those words.
          expect(
            OcrFieldExtractor.cleanAddressLine('AV. PRIMERA DE OCTUBRE 123'),
            'AV. PRIMERA DE OCTUBRE 123',
          );
        },
      );
    });

    // ── stripAddressLabelTail — direct unit tests ─────────────────────────

    group('stripAddressLabelTail — front-label strip', () {
      test('"DOCUMENTO" at head → stripped', () {
        expect(
          OcrFieldExtractor.stripAddressLabelTail('DOCUMENTO STA ROSA 1080'),
          'STA ROSA 1080',
        );
      });

      test('"DOCUMENTO NACIONAL" at tail → stripped', () {
        expect(
          OcrFieldExtractor.stripAddressLabelTail(
            'STA ROSA 1080 DOCUMENTO NACIONAL',
          ),
          'STA ROSA 1080',
        );
      });

      test('"APELLIDOS" at head → stripped', () {
        expect(
          OcrFieldExtractor.stripAddressLabelTail('APELLIDOS STA ROSA 1080'),
          'STA ROSA 1080',
        );
      });

      test('"SOLTERO" at tail → stripped', () {
        expect(
          OcrFieldExtractor.stripAddressLabelTail('STA ROSA 1080 SOLTERO'),
          'STA ROSA 1080',
        );
      });

      test('"CASADA" at tail → stripped', () {
        expect(
          OcrFieldExtractor.stripAddressLabelTail('STA ROSA 1080 CASADA'),
          'STA ROSA 1080',
        );
      });

      test('"CUI" + alphanumeric code at head → stripped', () {
        // CUI is the denylist token; 74846787-0 looks like a regular token
        // (digits + hyphen) — the strip step only removes denylist tokens
        // and stranded connectors. The alphanumeric code remains.
        // Documenting current behaviour: the cleaner upstream is the layer
        // that drops the bare code from Strategy 3 segments.
        expect(
          OcrFieldExtractor.stripAddressLabelTail(
            'CUI 74846787-0 STA ROSA 1080',
          ),
          '74846787-0 STA ROSA 1080',
        );
      });

      test('"IDENTIDAD" at tail → stripped', () {
        expect(
          OcrFieldExtractor.stripAddressLabelTail(
            'STA ROSA 1080 DOCUMENTO NACIONAL DE IDENTIDAD',
          ),
          'STA ROSA 1080',
        );
      });
    });

    // ── End-to-end via extract() ──────────────────────────────────────────

    group('extract — front-side bleed-through scenarios', () {
      test(
        'DOCUMENTO label above real address — ignored, address recovered',
        () {
          final rt = _recognizedFromLines(const [
            'DOCUMENTO NACIONAL DE IDENTIDAD',
            'STA ROSA 1080 MARIATEGUI',
            '/LIMA/LIMA/VILLA MARIA DEL TRIUNFO',
          ]);

          final result = OcrFieldExtractor.extract(rt);

          expect(result.address, 'STA ROSA 1080 MARIATEGUI');
        },
      );

      test(
        'CUI + APELLIDOS bleed-through — only real address survives',
        () {
          // The denylist removes APELLIDOS at the token level. The
          // surviving person-name tokens (LOPEZ QUISPE) would leak into
          // Strategy 3 because proper nouns count as content.
          // The structural anchor (`_hasAddressAnchor`) requires
          // surviving tokens to include a prefix OR (numeric + proper
          // noun). "LOPEZ QUISPE" has only proper nouns — rejected.
          // The address is exactly the legitimate line.
          final rt = _recognizedFromLines(const [
            'CUI 74846787',
            'APELLIDOS LOPEZ QUISPE',
            'STA ROSA 1080 MARIATEGUI',
            '/LIMA/LIMA/VILLA MARIA DEL TRIUNFO',
          ]);

          final result = OcrFieldExtractor.extract(rt);

          expect(result.address, 'STA ROSA 1080 MARIATEGUI');
        },
      );

      test('ESTADO CIVIL SOLTERO bleed-through — address still recovered', () {
        final rt = _recognizedFromLines(const [
          'ESTADO CIVIL SOLTERO',
          'STA ROSA 1080 MARIATEGUI',
          '/LIMA/LIMA/VILLA MARIA DEL TRIUNFO',
        ]);

        final result = OcrFieldExtractor.extract(rt);

        expect(result.address, 'STA ROSA 1080 MARIATEGUI');
      });

      test(
        'FECHA DE CADUCIDAD bleed-through — only real address survives',
        () {
          // FECHA and CADUCIDAD are removed by the denylist, but
          //   "DE 25 03 2036" (connector + date codes) would leak into the
          //   joined address.
          // Structural anchor sees only connector + numeric codes on the
          //   remnant line — no proper-noun word, no prefix → the whole
          //   fragment is rejected. Only the real address survives.
          final rt = _recognizedFromLines(const [
            'FECHA DE CADUCIDAD 25 03 2036',
            'STA ROSA 1080 MARIATEGUI',
            '/LIMA/LIMA/VILLA MARIA DEL TRIUNFO',
          ]);

          final result = OcrFieldExtractor.extract(rt);

          expect(result.address, 'STA ROSA 1080 MARIATEGUI');
        },
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 11 — Address prefixes — Peru official vocabulary.
  //
  // Common urban prefixes (AV, JR, CALLE, MZ, LT, URB, PP.JJ., A.H., …) are
  // covered by the basic denylist. This group covers the official Peruvian
  // address vocabulary published by RENIEC SRGDD and INEI — rural,
  // residential complexes, and indigenous community prefixes that real
  // citizens carry on their DNI:
  //
  //   CP / CPM   — Centro Poblado / Centro Poblado Menor
  //   CC / CCNN  — Comunidad Campesina / Comunidad Nativa
  //   CAS / CASERIO
  //   ANEXO / ANX
  //   RES / RESIDENCIAL
  //   COND / CONDOMINIO
  //   EDIF / EDIFICIO
  //   BLOCK / BLK / TORRE / TR / PISO / PSO
  //   BARRIO / BARR / COOP / COOPERATIVA / VILLA
  //   FUNDO / PARC / PARCELA / PARQUE / PQ
  //
  // Each test feeds a real-shape Peruvian address through Strategy 3
  // (ubigeo anchor) and asserts the address is recovered verbatim.
  // ─────────────────────────────────────────────────────────────────────────
  group(
    'Address prefixes — Peru official vocabulary (RENIEC SRGDD + INEI)',
    () {
      test('CP. SANTA ROSA MZ.B LT.5 — Centro Poblado', () {
        final rt = _recognizedFromLines(const [
          'CP. SANTA ROSA MZ.B LT.5',
          '/HUANUCO/HUANUCO/HUANUCO',
        ]);
        final result = OcrFieldExtractor.extract(rt);
        expect(result.address, 'CP. SANTA ROSA MZ.B LT.5');
      });

      test('CC. SAN JOSE DE QUERO MZ.A LT.10 — Comunidad Campesina', () {
        final rt = _recognizedFromLines(const [
          'CC. SAN JOSE DE QUERO MZ.A LT.10',
          '/JUNIN/CONCEPCION/SAN JOSE DE QUERO',
        ]);
        final result = OcrFieldExtractor.extract(rt);
        expect(result.address, 'CC. SAN JOSE DE QUERO MZ.A LT.10');
      });

      test('CCNN AGUARUNA RIO MARANON — Comunidad Nativa', () {
        final rt = _recognizedFromLines(const [
          'CCNN AGUARUNA RIO MARANON',
          '/AMAZONAS/CONDORCANQUI/NIEVA',
        ]);
        final result = OcrFieldExtractor.extract(rt);
        expect(result.address, 'CCNN AGUARUNA RIO MARANON');
      });

      test('CASERIO BUENOS AIRES SECTOR 2', () {
        final rt = _recognizedFromLines(const [
          'CASERIO BUENOS AIRES SECTOR 2',
          '/CAJAMARCA/CAJAMARCA/JESUS',
        ]);
        final result = OcrFieldExtractor.extract(rt);
        expect(result.address, 'CASERIO BUENOS AIRES SECTOR 2');
      });

      test('ANEXO LOS LIRIOS MZ.C LT.15', () {
        final rt = _recognizedFromLines(const [
          'ANEXO LOS LIRIOS MZ.C LT.15',
          '/AREQUIPA/AREQUIPA/JOSE LUIS BUSTAMANTE Y RIVERO',
        ]);
        final result = OcrFieldExtractor.extract(rt);
        expect(result.address, 'ANEXO LOS LIRIOS MZ.C LT.15');
      });

      test('RES. SAN BORJA TORRE B PISO 7 — Residencial', () {
        final rt = _recognizedFromLines(const [
          'RES. SAN BORJA TORRE B PISO 7',
          '/LIMA/LIMA/SAN BORJA',
        ]);
        final result = OcrFieldExtractor.extract(rt);
        expect(result.address, 'RES. SAN BORJA TORRE B PISO 7');
      });

      test('COND. LOS PARQUES BLOCK A LT.5 — Condominio', () {
        final rt = _recognizedFromLines(const [
          'COND. LOS PARQUES BLOCK A LT.5',
          '/LIMA/LIMA/SAN MIGUEL',
        ]);
        final result = OcrFieldExtractor.extract(rt);
        expect(result.address, 'COND. LOS PARQUES BLOCK A LT.5');
      });

      test('EDIF. SAN JUAN PISO 4 DPTO 401 — Edificio', () {
        final rt = _recognizedFromLines(const [
          'EDIF. SAN JUAN PISO 4 DPTO 401',
          '/LIMA/LIMA/MIRAFLORES',
        ]);
        final result = OcrFieldExtractor.extract(rt);
        expect(result.address, 'EDIF. SAN JUAN PISO 4 DPTO 401');
      });

      test('BARRIO ALTO MZ.A LT.20', () {
        final rt = _recognizedFromLines(const [
          'BARRIO ALTO MZ.A LT.20',
          '/CUSCO/CUSCO/CUSCO',
        ]);
        final result = OcrFieldExtractor.extract(rt);
        expect(result.address, 'BARRIO ALTO MZ.A LT.20');
      });

      test('COOP. SANTA ELIZABETH MZ.D LT.3 — Cooperativa', () {
        final rt = _recognizedFromLines(const [
          'COOP. SANTA ELIZABETH MZ.D LT.3',
          '/LIMA/LIMA/SAN JUAN DE LURIGANCHO',
        ]);
        final result = OcrFieldExtractor.extract(rt);
        expect(result.address, 'COOP. SANTA ELIZABETH MZ.D LT.3');
      });
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Group 12 — Address noise: migration documents + DNIe security tokens.
  //
  // Two classes of tokens in the denylist:
  //
  //   1. Migration / CE document labels — when ML Kit misclassifies a
  //      foreign-citizen card (Carnet de Extranjería, PTP, CPP), the label
  //      text bleeds into the address pass and must be killed at the token
  //      level. Tokens: CARNET, EXTRANJERIA (→ EXTRANJERÍA via diacritic
  //      strip), MIGRACIONES, PTP, CPP, PERMISO, TEMPORAL, PERMANENCIA,
  //      RESOLUCION.
  //
  //   2. DNIe security / spec labels — the Peruvian electronic DNI
  //      back-side printed area contains RENIEC-mandated security tokens
  //      that aren't part of the address: DNI, DNIE, OACI, IOFE, OVI,
  //      JAVACARD, MRZ, FIRMA. FIRMA is on the "risky" side (it's a real
  //      Spanish word), but the realistic collision with Peruvian streets
  //      is essentially zero, so it's accepted.
  //
  // The strip-tail test cases also confirm both head and tail removal so
  // that joined Strategy-3 outputs are scrubbed even if a denylist token
  // straddles the join.
  // ─────────────────────────────────────────────────────────────────────────
  group(
    'Address noise — migration documents + DNIe security tokens',
    () {
      group('cleanAddressLine — migration + DNIe rejection', () {
        test('"CARNET DE EXTRANJERIA NRO 0123456" → null', () {
          // CARNET → denylist. DE → connector. EXTRANJERIA → denylist.
          // NRO → prefix. 0123456 → code.
          // 2 noise / 5 = 40% — NOT > 40%, so the line survives the ratio
          // gate, but the structural anchor requires surviving content to
          // anchor on a real address shape. Even with NRO+0123456 the line
          // has no proper-noun content, so the anchor still rejects it.
          // Either way: null.
          expect(
            OcrFieldExtractor.cleanAddressLine(
              'CARNET DE EXTRANJERIA NRO 0123456',
            ),
            isNull,
          );
        });

        test('"MIGRACIONES PERMISO TEMPORAL PERMANENCIA" → null', () {
          // All 4 tokens denylist → 100% noise.
          expect(
            OcrFieldExtractor.cleanAddressLine(
              'MIGRACIONES PERMISO TEMPORAL PERMANENCIA',
            ),
            isNull,
          );
        });

        test('"PTP NRO 12345" → null', () {
          // PTP → denylist (1/3 = 33% < 40%). NRO+12345 has no proper noun
          // → structural anchor rejects regardless.
          expect(
            OcrFieldExtractor.cleanAddressLine('PTP NRO 12345'),
            isNull,
          );
        });

        test('"CPP RESOLUCION 6789" → null', () {
          // CPP + RESOLUCION → 2/3 = 67% noise → ratio gate rejects.
          expect(
            OcrFieldExtractor.cleanAddressLine('CPP RESOLUCION 6789'),
            isNull,
          );
        });

        test('"OACI IOFE OVI JAVACARD" → null (4/4 DNIe security tokens)', () {
          expect(
            OcrFieldExtractor.cleanAddressLine('OACI IOFE OVI JAVACARD'),
            isNull,
          );
        });

        test('"DNIE NRO 12345678" → null', () {
          // DNIE → denylist (1/3 = 33%). NRO+12345678 no proper noun
          // → structural anchor rejects.
          expect(
            OcrFieldExtractor.cleanAddressLine('DNIE NRO 12345678'),
            isNull,
          );
        });

        test(
          '"FIRMA REGISTRADA" → null (FIRMA denylist + REGISTRADA noise)',
          () {
            // FIRMA → denylist. REGISTRADA → Spanish word but no number, no
            // prefix → structural anchor rejects (and the denylist still
            // marks FIRMA as noise = 1/2 = 50%, which alone trips the
            // ratio).
            expect(
              OcrFieldExtractor.cleanAddressLine('FIRMA REGISTRADA'),
              isNull,
            );
          },
        );

        test(
          '"AV. CARNET 100" (hypothetical) — AV anchors, CARNET stripped',
          () {
            // 3 tokens: AV. (prefix), CARNET (denylist noise), 100 (code).
            // 1 noise / 3 = 33% < 40% → kept. AV anchor passes.
            // Final output drops CARNET → "AV. 100".
            // Documents the actual behavior: a denylist token surrounded
            // by legitimate address signal does not poison the whole line.
            expect(
              OcrFieldExtractor.cleanAddressLine('AV. CARNET 100'),
              'AV. 100',
            );
          },
        );
      });

      group('stripAddressLabelTail — migration + DNIe strip', () {
        test('"CARNET DE EXTRANJERIA STA ROSA 1080" → "STA ROSA 1080"', () {
          expect(
            OcrFieldExtractor.stripAddressLabelTail(
              'CARNET DE EXTRANJERIA STA ROSA 1080',
            ),
            'STA ROSA 1080',
          );
        });

        test('"STA ROSA 1080 MIGRACIONES" → "STA ROSA 1080"', () {
          expect(
            OcrFieldExtractor.stripAddressLabelTail(
              'STA ROSA 1080 MIGRACIONES',
            ),
            'STA ROSA 1080',
          );
        });

        test('"OACI IOFE STA ROSA 1080 OVI" → "STA ROSA 1080"', () {
          expect(
            OcrFieldExtractor.stripAddressLabelTail(
              'OACI IOFE STA ROSA 1080 OVI',
            ),
            'STA ROSA 1080',
          );
        });
      });
    },
  );

  // ─────────────────────────────────────────────────────────────────────────
  // Group 13 — Address line structural guard — requires anchor.
  //
  // The LABEL leak (APELLIDOS, FECHA, CADUCIDAD, …) is closed by the
  // denylist. Two structural gaps remain after the denylist runs:
  //
  //   • Person-name leak: `APELLIDOS LOPEZ QUISPE` → after denylist
  //     strip → `LOPEZ QUISPE`. Two proper-noun tokens, 0% noise →
  //     ratio gate passes → Strategy 3 would join it with the real
  //     address.
  //
  //   • Date-fragment leak: `FECHA DE CADUCIDAD 25 03 2036` → after
  //     strip → `DE 25 03 2036`. Connector + numeric codes, 0% noise →
  //     same problem.
  //
  // The STRUCTURAL anchor closes both: a surviving line must contain at
  // least one address prefix (AV, JR, MZ, …) OR have both a numeric code
  // AND a proper-noun-shaped word. Person names alone fail because they
  // have no number; date fragments alone fail because they have no proper
  // noun.
  //
  // Critical regression case: `SANTA ROSA 1080 MARIATEGUI` is a real
  // Peruvian address — it has NO prefix word but it IS a real address.
  // The anchor is "prefix OR (numeric AND proper-noun)" specifically so
  // that prefix-less but otherwise structured addresses still pass.
  // ─────────────────────────────────────────────────────────────────────────
  group('Address line structural guard — requires anchor', () {
    // ── Tokens that must be rejected (lacked anchor) ────────────────────────

    test('"APELLIDOS LOPEZ QUISPE" → null (no prefix, no number)', () {
      // After denylist strip → "LOPEZ QUISPE" (2 proper nouns).
      // Anchor: no prefix, no numeric → reject.
      expect(
        OcrFieldExtractor.cleanAddressLine('APELLIDOS LOPEZ QUISPE'),
        isNull,
      );
    });

    test('"LOPEZ QUISPE" (no label, raw names) → null', () {
      // Two proper-noun tokens, no number, no prefix → anchor rejects.
      expect(
        OcrFieldExtractor.cleanAddressLine('LOPEZ QUISPE'),
        isNull,
      );
    });

    test('"FECHA DE CADUCIDAD 25 03 2036" → null (only dates after strip)', () {
      // After denylist strip → "DE 25 03 2036": connector + 3 date codes.
      // Anchor: no prefix, no proper noun → reject.
      expect(
        OcrFieldExtractor.cleanAddressLine('FECHA DE CADUCIDAD 25 03 2036'),
        isNull,
      );
    });

    test('"DE 25 03 2036" (already stripped) → null', () {
      // Same shape as the post-strip remnant above.
      expect(
        OcrFieldExtractor.cleanAddressLine('DE 25 03 2036'),
        isNull,
      );
    });

    // ── Lines that must KEEP passing (regression guard) ─────────────────────

    test('"AV. SANTA ROSA 100" → kept (AV prefix anchors)', () {
      expect(
        OcrFieldExtractor.cleanAddressLine('AV. SANTA ROSA 100'),
        'AV. SANTA ROSA 100',
      );
    });

    test('"MZ. C LT. 20" → kept (MZ + LT prefixes anchor)', () {
      expect(
        OcrFieldExtractor.cleanAddressLine('MZ. C LT. 20'),
        'MZ. C LT. 20',
      );
    });

    test(
      '"SANTA ROSA 1080 MARIATEGUI" → kept (numeric 1080 + proper-noun anchor)',
      () {
        // The prefix-less prod case. No prefix word, but 1080 (numeric
        // code) + SANTA / ROSA / MARIATEGUI (proper nouns) satisfy the
        // (numeric AND proper-noun) branch of the anchor.
        expect(
          OcrFieldExtractor.cleanAddressLine('SANTA ROSA 1080 MARIATEGUI'),
          'SANTA ROSA 1080 MARIATEGUI',
        );
      },
    );

    test('"WHAPP AGE 0--" → null (no anchor — also fails noise ratio)', () {
      // Double protection: noise-ratio already rejects this in the basic
      // filter; the anchor is a second line of defense.
      expect(
        OcrFieldExtractor.cleanAddressLine('WHAPP AGE 0--'),
        isNull,
      );
    });
  });
}
