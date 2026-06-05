/// Coordinator-level tests for the refactored [OcrFieldExtractor].
///
/// These tests verify the strategy pipeline ordering, null-propagation
/// between strategies, and merge precedence. The 1621-line regression
/// test (`ocr_field_extractor_test.dart`) remains the primary gate for
/// full output parity — these tests focus on coordinator logic only.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

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

// Valid TD1 MRZ lines (checksum-valid — from ICAO sample used in mrz_parser tests).
const _kMrzLine1 = 'I<SWE59000002<8198703142391<<<';
const _kMrzLine2 = '8703145M1701027SWE<<<<<<<<<<<8';
const _kMrzLine3 = 'SPECIMEN<<SVEN<<<<<<<<<<<<<<<<';

void main() {
  // ── Strategy pipeline: MRZ found → text extraction skipped, address runs ──

  group('OcrFieldExtractor coordinator — strategy pipeline', () {
    test(
      'MRZ found → text name extraction skipped, address still runs',
      () {
        // Block 1: MRZ zone.
        // Block 2: regular text with an address (address extraction should still run).
        final block1 = _makeTextBlock([_kMrzLine1, _kMrzLine2, _kMrzLine3]);
        final block2 = _makeTextBlock([
          'AV. ARGENTINA 4490',
          '/CALLAO/CALLAO',
        ]);
        final recognized = RecognizedText(
          text: '${block1.text}\n${block2.text}',
          blocks: [block1, block2],
        );

        final result = OcrFieldExtractor.extract(recognized);

        // MRZ parse should have set hasMrzData.
        expect(result.hasMrzData, isTrue);
        // Address should be populated (address strategy always runs).
        expect(result.address, isNotNull);
      },
    );

    test(
      'MRZ null → text strategy runs and extracts names',
      () {
        final recognized = _recognizedFromLines([
          'PRIMER APELLIDO',
          'GARCIA',
          'SEGUNDO APELLIDO',
          'RODRIGUEZ',
          'PRENOMBRES',
          'CARLOS',
        ]);

        final result = OcrFieldExtractor.extract(recognized);

        // No MRZ found.
        expect(result.hasMrzData, isFalse);
        // Text strategy should have extracted names.
        expect(result.lastName, isNotNull);
      },
    );

    test(
      'empty RecognizedText → returns empty OcrExtractedFields',
      () {
        final recognized = RecognizedText(text: '', blocks: const []);
        final result = OcrFieldExtractor.extract(recognized);
        expect(result.foundCount, 0);
      },
    );

    test(
      'address extracted even when MRZ is present',
      () {
        // One block with MRZ + address on non-MRZ lines.
        final recognized = _recognizedFromLines([
          _kMrzLine1,
          _kMrzLine2,
          _kMrzLine3,
          'AV. PERU 500',
          '/LIMA/LIMA/LIMA',
        ]);

        final result = OcrFieldExtractor.extract(recognized);

        expect(result.address, isNotNull);
      },
    );

    test(
      'merge precedence: MRZ documentNumber wins over text-OCR on accumulate',
      () {
        // Build two fields simulating MRZ frame and text-OCR frame.
        final mrzFrame = OcrExtractedFields()
          ..fromMrzForTest = true
          ..documentNumber = '71542895';

        final textFrame = OcrExtractedFields()..documentNumber = '71542835';

        mrzFrame.merge(textFrame); // merge text into MRZ accumulator → MRZ wins
        expect(mrzFrame.documentNumber, '71542895');
      },
    );
  });
}
