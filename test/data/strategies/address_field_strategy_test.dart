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
}
