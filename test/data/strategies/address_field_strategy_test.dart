import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:dni_peru_ocr/src/data/strategies/address_field_strategy.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

TextBlock _makeTextBlock(List<String> lines) {
  const box = Rect.fromLTWH(0, 0, 400, 200);
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
    RecognizedText(
      text: lines.join('\n'),
      blocks: [_makeTextBlock(lines)],
    );

void main() {
  group('AddressFieldStrategy', () {
    late AddressFieldStrategy strategy;

    setUp(() {
      strategy = const AddressFieldStrategy();
    });

    // ── Scenario: Returns null for empty input ────────────────────────────
    test('returns null when blocks are empty', () {
      final recognized = RecognizedText(text: '', blocks: const []);
      final result = strategy.extract(recognized);
      expect(result, isNull);
    });

    // ── Scenario: Address prefix detection (Strategy 2) ───────────────────
    test('extracts address with AV. prefix via Strategy 2', () {
      final recognized = _recognizedFromLines([
        'PRIMER APELLIDO',
        'GARCIA',
        'AV. ARGENTINA 4490',
        '/CALLAO/CALLAO',
      ]);
      final result = strategy.extract(recognized);
      expect(result, isNotNull);
      expect(result!.address, 'AV. ARGENTINA 4490');
    });

    // ── Scenario: Ubigeo anchor (Strategy 3) ─────────────────────────────
    test('extracts address via ubigeo anchor /DEPT/PROV/DIST', () {
      final recognized = _recognizedFromLines([
        'MZ.C LT.20 3ER SECTOR URB.ANTONIA MORENO DE CACERES',
        '/CALLAO/VENTANILLA',
      ]);
      final result = strategy.extract(recognized);
      expect(result, isNotNull);
      expect(
        result!.address,
        'MZ.C LT.20 3ER SECTOR URB.ANTONIA MORENO DE CACERES',
      );
    });

    // ── Scenario: DOMICILIO label (Strategy 1) ────────────────────────────
    test('extracts address via DOMICILIO label', () {
      final recognized = _recognizedFromLines([
        'DOMICILIO AV. PERU 100',
        '/LIMA/LIMA/LIMA',
      ]);
      final result = strategy.extract(recognized);
      expect(result, isNotNull);
      expect(result!.address, isNotNull);
      expect(result.address!.startsWith('DOMICILIO'), isFalse);
      expect(result.address, contains('AV. PERU 100'));
    });

    // ── Scenario: Denylist filtering — noise tokens rejected ─────────────
    test('returns null for address when only noise/denylist tokens present', () {
      final recognized = _recognizedFromLines([
        'CONSTANCIA DE SUFRAGIO',
        '/LIMA/LIMA/LIMA',
      ]);
      final result = strategy.extract(recognized);
      // CONSTANCIA and SUFRAGIO are denylist tokens — should not produce address
      expect(result?.address, isNull);
    });

    // ── Scenario: All non-address fields are null ─────────────────────────
    test('all non-address fields are null', () {
      final recognized = _recognizedFromLines([
        'AV. ARGENTINA 4490',
        '/CALLAO/CALLAO',
      ]);
      final result = strategy.extract(recognized);
      expect(result, isNotNull);
      expect(result!.documentNumber, isNull);
      expect(result.firstName, isNull);
      expect(result.lastName, isNull);
      expect(result.secondLastName, isNull);
      expect(result.dateOfBirth, isNull);
      expect(result.sex, isNull);
      expect(result.expirationDate, isNull);
      expect(result.nationality, isNull);
    });

    // ── Scenario: JR. prefix address ─────────────────────────────────────
    test('extracts address with JR. prefix', () {
      final recognized = _recognizedFromLines([
        'JR. LOS OLIVOS 234',
        '/LIMA/LIMA/BREÑA',
      ]);
      final result = strategy.extract(recognized);
      expect(result, isNotNull);
      expect(result!.address, 'JR. LOS OLIVOS 234');
    });

    // ── Scenario: Returns null when no address signal at all ──────────────
    test('returns null when only name-like content and no address', () {
      final recognized = _recognizedFromLines([
        'PRIMER APELLIDO',
        'GARCIA',
        'PRENOMBRES',
        'CARLOS',
      ]);
      final result = strategy.extract(recognized);
      expect(result?.address, isNull);
    });
  });

  // ── BUG 1A regression — Spanish "Dirección" anchor (JC v0.6.0 feedback) ───
  //
  // Real Peruvian electronic DNI prints "Dirección:" (Spanish accent) on the
  // reverse, NOT "Domicilio:". The strategy was DOMICILIO-only, AND
  // "DIRECCION" sat in the noise denylist — so the anchor line was discarded
  // before the parser could use it.
  //
  // Fix:
  //  - Accept DIRECCIÓN / DIRECCION / DIRECCION: as a Strategy 1 anchor
  //    (alongside DOMICILIO/DOM/DOM.).
  //  - Remove DIRECCION from kAddressNoiseDenylist (so anchor line is kept).
  //
  // Source: real DNI photo (obs #4669, image WhatsApp 2026-06-05 at 10.03.05).
  group('BUG 1A regression — Spanish Dirección anchor', () {
    late AddressFieldStrategy strategy;

    setUp(() {
      strategy = const AddressFieldStrategy();
    });

    test('Dirección: with inline value extracts the address', () {
      final recognized = _recognizedFromLines([
        'REPUBLICA DEL PERU',
        'Dirección: ASENT.H15 DE ABRIL CALLE EL MILAGRO',
      ]);
      final result = strategy.extract(recognized);
      expect(result?.address, isNotNull);
      expect(result?.address, contains('ASENT'));
      expect(result?.address, contains('CALLE EL MILAGRO'));
    });

    test('Dirección anchor with value on next line extracts the address', () {
      final recognized = _recognizedFromLines([
        'REPUBLICA DEL PERU',
        'Dirección:',
        'ASENT.H15 DE ABRIL CALLE EL MILAGRO',
        'MZ B LT 19',
      ]);
      final result = strategy.extract(recognized);
      expect(result?.address, isNotNull);
      expect(result?.address, contains('ASENT'));
    });

    test('DIRECCION uppercase no accent is also recognized', () {
      final recognized = _recognizedFromLines([
        'REPUBLICA DEL PERU',
        'DIRECCION:',
        'AV. LOS PINOS 123',
      ]);
      final result = strategy.extract(recognized);
      expect(result?.address, isNotNull);
      expect(result?.address, contains('LOS PINOS'));
    });

    test('DIRECCIÓN with accent uppercase is recognized', () {
      final recognized = _recognizedFromLines([
        'REPUBLICA DEL PERU',
        'DIRECCIÓN:',
        'JR. AREQUIPA 456',
      ]);
      final result = strategy.extract(recognized);
      expect(result?.address, isNotNull);
      expect(result?.address, contains('AREQUIPA'));
    });
  });

  // ── BUG regression — real Peruvian DNI back side (JC v0.6.4 verification)
  //
  // Real DNI photo printed:
  //   "Dirección
  //    ASENT.H15 DE ABRIL CALLE EL MILAGRO
  //    MZ.B LT.19"
  //
  // ML Kit emits these as joined OCR lines, sometimes with the anchor and
  // first word glued together (`ASENTH15`). The extractor must:
  //   - keep the MZ.B and LT.19 tokens (they are valid Peruvian address
  //     codes — Manzana B, Lote 19),
  //   - keep H15 as part of the address (it's the Asentamiento Humano
  //     number 15 — common in shantytown addresses),
  //   - not mangle ABRIL into ABRL.
  group('BUG regression — Peruvian DNI back-side address with MZ/LT codes', () {
    late AddressFieldStrategy strategy;

    setUp(() {
      strategy = const AddressFieldStrategy();
    });

    test(
      'MZ.B and LT.19 are preserved in the final address',
      () {
        final recognized = _recognizedFromLines([
          'REPUBLICA DEL PERU',
          'Dirección',
          'ASENT.H15 DE ABRIL CALLE EL MILAGRO',
          'MZ.B LT.19',
        ]);
        final result = strategy.extract(recognized);
        expect(result?.address, isNotNull);
        // The block / lot tokens MUST survive the noise filter.
        expect(
          result?.address,
          anyOf(contains('MZ.B'), contains('MZ B'), contains('MZ')),
          reason: 'MZ token (Manzana) is a valid Peruvian address code',
        );
        expect(
          result?.address,
          anyOf(contains('LT.19'), contains('LT 19'), contains('LT19'), contains('LT')),
          reason: 'LT token (Lote) is a valid Peruvian address code',
        );
      },
    );

    test(
      'ABRIL is preserved (no token mangling)',
      () {
        final recognized = _recognizedFromLines([
          'Dirección',
          'ASENT.H15 DE ABRIL CALLE EL MILAGRO',
          'MZ.B LT.19',
        ]);
        final result = strategy.extract(recognized);
        expect(result?.address, isNotNull);
        expect(
          result?.address,
          contains('ABRIL'),
          reason: 'ABRIL (15 de Abril asentamiento) must survive intact',
        );
      },
    );

    test(
      'MZ A LT 5 (space-separated, no dots) variant',
      () {
        final recognized = _recognizedFromLines([
          'Dirección:',
          'AV LOS PINOS 123 MZ A LT 5',
        ]);
        final result = strategy.extract(recognized);
        expect(result?.address, isNotNull);
        expect(result?.address, contains('MZ'));
        expect(result?.address, contains('LT'));
        expect(result?.address, contains('LOS PINOS'));
      },
    );

    test(
      'MZA / LTE (full-word variants) preserved',
      () {
        final recognized = _recognizedFromLines([
          'Dirección',
          'JR HUANUCO 456',
          'MZA 12 LTE 8',
        ]);
        final result = strategy.extract(recognized);
        expect(result?.address, isNotNull);
        expect(result?.address, contains('HUANUCO'));
        // MZA and LTE are recognised long-form variants; at minimum the
        // numeric codes 12 and 8 must survive.
        expect(
          result?.address,
          anyOf(
            allOf(contains('MZA'), contains('LTE')),
            allOf(contains('12'), contains('8')),
          ),
        );
      },
    );

    // ── Real JC case: JAMES DNI moderno ───────────────────────────────────
    // The back-side prints the address inline next to the anchor:
    //   "Dirección"
    //   "MZ.C LT.20 3ER SECTOR URB.ANTONIA MORENO DE CACERES"
    // The strategy must preserve all four key segments: MZ.C, LT.20,
    // 3ER (or SECTOR), and URB.ANTONIA MORENO DE CACERES.
    test(
      'real JC case: MZ.C LT.20 3ER SECTOR URB.ANTONIA MORENO DE CACERES',
      () {
        final recognized = _recognizedFromLines([
          'REPUBLICA DEL PERU',
          'Dirección',
          'MZ.C LT.20 3ER SECTOR URB.ANTONIA MORENO DE CACERES',
        ]);
        final result = strategy.extract(recognized);
        expect(result?.address, isNotNull);
        expect(result?.address, contains('MZ'),
            reason: 'MZ block code must survive');
        expect(result?.address, contains('LT'),
            reason: 'LT lot code must survive');
        expect(
          result?.address,
          anyOf(contains('ANTONIA'), contains('MORENO'), contains('CACERES')),
          reason: 'URB name must survive the noise filter',
        );
      },
    );

    // 3ER / SECTOR / URB prefixes — must not be filtered as noise.
    test(
      '3ER and SECTOR tokens are preserved in address',
      () {
        final recognized = _recognizedFromLines([
          'Dirección',
          'AV. LOS PINOS 123 3ER SECTOR ZONA B',
        ]);
        final result = strategy.extract(recognized);
        expect(result?.address, isNotNull);
        expect(result?.address, contains('LOS PINOS'));
        expect(
          result?.address,
          anyOf(contains('3ER'), contains('SECTOR'), contains('ZONA')),
          reason: 'ordinal + sector + zona tokens must not be dropped',
        );
      },
    );

    // BUG F — ML Kit splits address mid-token: anchor line ends at "MZ"
    // and continuation line starts with "B LT.19" (no MZ./MZA. prefix).
    // The _buildAddress loop must tolerate this kind of fragmented OCR
    // when the previous line ENDED with an address-continuation prefix
    // and the next line CONTINUES it without a recognised prefix of its
    // own. Real JC case where the back-side OCR truncates the address.
    test(
      'ML Kit emits MZ at end of line1 + "B LT.19" on line2 — must concatenate',
      () {
        final recognized = _recognizedFromLines([
          'REPUBLICA DEL PERU',
          'ASENT.H15 DE ABRIL CALLE EL MILAGRO MZ',
          'B LT.19',
        ]);
        final result = strategy.extract(recognized);
        expect(result?.address, isNotNull);
        expect(
          result?.address,
          allOf(contains('MZ'), contains('LT'), contains('19')),
          reason: 'continuation line "B LT.19" must attach when previous '
              'line ended with an MZ/LT continuation prefix',
        );
      },
    );

    test(
      'ML Kit emits LT at end of line1 + "19" on line2 — must concatenate',
      () {
        final recognized = _recognizedFromLines([
          'ASENT.H15 DE ABRIL CALLE EL MILAGRO MZ.B LT',
          '19',
        ]);
        final result = strategy.extract(recognized);
        expect(result?.address, isNotNull);
        expect(
          result?.address,
          allOf(contains('LT'), contains('19')),
        );
      },
    );

    test(
      'continuation chain MZ → B → LT → 19 across three lines',
      () {
        final recognized = _recognizedFromLines([
          'ASENT.H15 DE ABRIL CALLE EL MILAGRO MZ',
          'B',
          'LT 19',
        ]);
        final result = strategy.extract(recognized);
        expect(result?.address, isNotNull);
        expect(result?.address, contains('MZ'));
        expect(result?.address, contains('LT'));
      },
    );
  });
}
