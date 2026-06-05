import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:dni_peru_ocr/src/data/strategies/text_ocr_field_strategy.dart';

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
  group('TextOcrFieldStrategy', () {
    late TextOcrFieldStrategy strategy;

    setUp(() {
      strategy = const TextOcrFieldStrategy();
    });

    // ── Scenario: Returns null for empty input ────────────────────────────
    test('returns null when blocks are empty', () {
      final recognized = RecognizedText(text: '', blocks: const []);
      final result = strategy.extract(recognized);
      expect(result, isNull);
    });

    // ── Scenario: Label-anchored name extraction ──────────────────────────
    test('extracts lastName via PRIMER APELLIDO label', () {
      final recognized = _recognizedFromLines([
        'PRIMER APELLIDO',
        'GARCIA',
        'SEGUNDO APELLIDO',
        'RODRIGUEZ',
        'PRENOMBRES',
        'CARLOS LUIS',
      ]);
      final result = strategy.extract(recognized);
      expect(result, isNotNull);
      expect(result!.lastName, 'GARCIA');
      expect(result.secondLastName, 'RODRIGUEZ');
      expect(result.firstName, 'CARLOS LUIS');
    });

    // ── Scenario: DNI number extraction via label ─────────────────────────
    test('extracts documentNumber from DNI/number pattern', () {
      final recognized = _recognizedFromLines([
        'DNI 71542895',
        'PRIMER APELLIDO',
        'GARCIA',
      ]);
      final result = strategy.extract(recognized);
      expect(result, isNotNull);
      expect(result!.documentNumber, '71542895');
    });

    // ── Scenario: address field is always null ────────────────────────────
    test('never populates address field', () {
      final recognized = _recognizedFromLines([
        'PRIMER APELLIDO',
        'GARCIA',
        'AV. PERU 100',
      ]);
      final result = strategy.extract(recognized);
      // TextOcrFieldStrategy handles name/date/sex — not address.
      // Address is handled by AddressFieldStrategy.
      expect(result?.address, isNull);
    });

    // ── Scenario: MRZ input returns no names (lines filtered) ────────────
    test('returns result with no name fields when input is MRZ-only', () {
      // MRZ lines look like MRZ and get filtered out by _looksLikeMrzLine
      final recognized = _recognizedFromLines([
        'I<SWE59000002<8198703142391<<<',
        '8703145M1701027SWE<<<<<<<<<<<8',
        'SPECIMEN<<SVEN<<<<<<<<<<<<<<<<',
      ]);
      final result = strategy.extract(recognized);
      // All lines are filtered as MRZ-like, so nothing extracted
      // Result could be null or have all-null name fields
      if (result != null) {
        expect(result.lastName, isNull);
        expect(result.firstName, isNull);
      }
    });

    // ── Scenario: hasMrzData is always false ──────────────────────────────
    test('hasMrzData is always false', () {
      final recognized = _recognizedFromLines([
        'PRIMER APELLIDO',
        'GARCIA',
        'PRENOMBRES',
        'CARLOS',
      ]);
      final result = strategy.extract(recognized);
      if (result != null) {
        expect(result.hasMrzData, isFalse);
      }
    });

    // ── Scenario: Ordinal name matching for two-column DNI layout ─────────
    test('extracts names by ordinal when labels and values are in separate passes', () {
      final recognized = _recognizedFromLines([
        'PRIMER APELLIDO',
        'SEGUNDO APELLIDO',
        'PRENOMBRES',
        'GARCIA',
        'RODRIGUEZ',
        'CARLOS',
      ]);
      final result = strategy.extract(recognized);
      expect(result, isNotNull);
      // Ordinal matching assigns 1st name value to 1st label, etc.
      expect(result!.lastName, isNotNull);
    });

    // ── Scenario: Date extraction ─────────────────────────────────────────
    test('extracts dateOfBirth from NACIMIENTO context', () {
      final recognized = _recognizedFromLines([
        'PRIMER APELLIDO',
        'GARCIA',
        'NACIMIENTO 01 01 1990',
      ]);
      final result = strategy.extract(recognized);
      expect(result, isNotNull);
      expect(result!.dateOfBirth, '01/01/1990');
    });

    // ── BUG regression — DNI moderno unified "Apellidos" field ────────────
    //
    // Modern Peruvian DNI cards print a SINGLE "Apellidos" label with both
    // paternal and maternal surnames joined (e.g. "QUIROZ REMIGIO"). The
    // MRZ on the back only carries the paternal half — we need the text-OCR
    // to split the joined "Apellidos" value into lastName + secondLastName
    // so the back-side consensus accumulator has both via vote map fallback.
    //
    // Real case from JC's v0.6.5 verification: JAMES ERMITAÑO QUIROZ REMIGIO,
    // CUI 43005787. MRZ trae "QUIROZ<<JAMES<ERMITANXX0", only "QUIROZ".
    // The frente has "Apellidos: QUIROZ REMIGIO".
    group('BUG regression — DNI moderno unified Apellidos label', () {
      test(
        'splits "Apellidos QUIROZ REMIGIO" into lastName + secondLastName',
        () {
          final recognized = _recognizedFromLines([
            'REPUBLICA DEL PERU',
            'Apellidos',
            'QUIROZ REMIGIO',
            'Prenombres',
            'JAMES ERMITAÑO',
            'Sexo M Nacionalidad PER',
          ]);
          final result = strategy.extract(recognized);
          expect(result, isNotNull);
          expect(result!.lastName, 'QUIROZ');
          expect(result.secondLastName, 'REMIGIO');
          expect(result.firstName, contains('JAMES'));
        },
      );

      test(
        'single-token Apellidos leaves secondLastName null (no fabrication)',
        () {
          final recognized = _recognizedFromLines([
            'Apellidos',
            'QUIROZ',
            'Prenombres',
            'JAMES',
          ]);
          final result = strategy.extract(recognized);
          expect(result, isNotNull);
          expect(result!.lastName, 'QUIROZ');
          expect(result.secondLastName, isNull);
        },
      );

      test(
        '3+ token Apellidos uses first as paternal, rest joined as maternal',
        () {
          // Edge case: some registries store compound maternal surnames
          // (e.g. "DE LA CRUZ"). Keep paternal as first token, join the rest.
          final recognized = _recognizedFromLines([
            'Apellidos',
            'PEREZ DE LA CRUZ',
            'Prenombres',
            'JUAN',
          ]);
          final result = strategy.extract(recognized);
          expect(result, isNotNull);
          expect(result!.lastName, 'PEREZ');
          expect(result.secondLastName, 'DE LA CRUZ');
        },
      );
    });
  });
}
