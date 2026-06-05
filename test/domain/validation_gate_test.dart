/// RED tests for ValidationGate enum introduction (PR4 — task 4.2).
///
/// Verifies:
/// 1. ValidationGate enum exists with all 6 cases.
/// 2. DocumentValidationResult.failingGate is typed ValidationGate? (not String?).
/// 3. Each failing gate returns the correct enum value.
/// 4. Capturable result has null failingGate.
/// 5. ValidationGate has stable Sentry codes via sentryCode getter.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

TextBlock _makeBlock({
  Rect boundingBox = const Rect.fromLTWH(100, 100, 200, 100),
  String text = 'dummy text',
}) {
  return TextBlock(
    text: text,
    lines: [],
    boundingBox: boundingBox,
    recognizedLanguages: ['es'],
    cornerPoints: [
      math.Point(boundingBox.left.toInt(), boundingBox.top.toInt()),
      math.Point(boundingBox.right.toInt(), boundingBox.top.toInt()),
      math.Point(boundingBox.right.toInt(), boundingBox.bottom.toInt()),
      math.Point(boundingBox.left.toInt(), boundingBox.bottom.toInt()),
    ],
  );
}

RecognizedText _makeRecognizedText({
  required int count,
  Rect boundingBox = const Rect.fromLTRB(250, 250, 1650, 800),
}) {
  final blocks = List.generate(count, (_) => _makeBlock(boundingBox: boundingBox));
  return RecognizedText(text: 'dummy', blocks: blocks);
}

const _kImageSize = Size(1920, 1080);

void main() {
  final theme = KycTheme.defaults();

  group('ValidationGate enum — enum values', () {
    // ── All 6 cases must exist ──────────────────────────────────────────────

    test('ValidationGate has minBlocks case', () {
      expect(ValidationGate.minBlocks, isNotNull);
    });

    test('ValidationGate has centering case', () {
      expect(ValidationGate.centering, isNotNull);
    });

    test('ValidationGate has fillHigh case', () {
      expect(ValidationGate.fillHigh, isNotNull);
    });

    test('ValidationGate has fillLow case', () {
      expect(ValidationGate.fillLow, isNotNull);
    });

    test('ValidationGate has lineCount case', () {
      expect(ValidationGate.lineCount, isNotNull);
    });

    test('ValidationGate has tilt case', () {
      expect(ValidationGate.tilt, isNotNull);
    });

    // ── Exactly 6 cases (exhaustiveness guarantee) ─────────────────────────

    test('ValidationGate has exactly 6 values', () {
      expect(ValidationGate.values.length, 6);
    });

    // ── Sentry-stable codes (no translation) ───────────────────────────────

    test('minBlocks has stable Sentry code "min_blocks"', () {
      expect(ValidationGate.minBlocks.sentryCode, 'min_blocks');
    });

    test('centering has stable Sentry code "centering"', () {
      expect(ValidationGate.centering.sentryCode, 'centering');
    });

    test('fillHigh has stable Sentry code "fill_high"', () {
      expect(ValidationGate.fillHigh.sentryCode, 'fill_high');
    });

    test('fillLow has stable Sentry code "fill_low"', () {
      expect(ValidationGate.fillLow.sentryCode, 'fill_low');
    });

    test('lineCount has stable Sentry code "line_count"', () {
      expect(ValidationGate.lineCount.sentryCode, 'line_count');
    });

    test('tilt has stable Sentry code "tilt"', () {
      expect(ValidationGate.tilt.sentryCode, 'tilt');
    });
  });

  group('DocumentValidationResult — typed failingGate', () {
    // ── failingGate typed as ValidationGate? (not String?) ─────────────────

    test('capturable result has failingGate == null', () {
      final result = DocumentValidationResult.evaluate(
        recognizedText: _makeRecognizedText(count: 5),
        imageSize: _kImageSize,
        theme: theme,
      );
      expect(result.isCaptureable, isTrue);
      expect(result.failingGate, isNull);
    });

    test('0 blocks → failingGate == ValidationGate.minBlocks', () {
      final result = DocumentValidationResult.evaluate(
        recognizedText: _makeRecognizedText(count: 0),
        imageSize: _kImageSize,
        theme: theme,
      );
      expect(result.failingGate, ValidationGate.minBlocks);
    });

    test('< 5 blocks (line-count) → failingGate == ValidationGate.lineCount', () {
      final result = DocumentValidationResult.evaluate(
        recognizedText: _makeRecognizedText(count: 2),
        imageSize: _kImageSize,
        theme: theme,
      );
      expect(result.failingGate, ValidationGate.lineCount);
    });

    test('high fill → failingGate == ValidationGate.fillHigh', () {
      // Very large bounding box that exceeds maxFillRatio (0.85)
      // holeArea = 1632 * 702 = 1145664
      // Need fillRatio > 0.85 → area > 973814 → e.g. 1600×700 = 1120000 / 1145664 ≈ 0.978
      const bigBox = Rect.fromLTRB(50, 100, 1650, 800);
      final result = DocumentValidationResult.evaluate(
        recognizedText: _makeRecognizedText(count: 5, boundingBox: bigBox),
        imageSize: _kImageSize,
        theme: theme,
      );
      expect(result.failingGate, ValidationGate.fillHigh);
    });

    test('low fill → failingGate == ValidationGate.fillLow', () {
      // Very small bounding box below minFillRatio (0.20)
      // Need fillRatio < 0.20 → area < 229133 → e.g. 200×100 = 20000 / 1145664 ≈ 0.017
      const smallBox = Rect.fromLTRB(800, 400, 1000, 500);
      final result = DocumentValidationResult.evaluate(
        recognizedText: _makeRecognizedText(count: 5, boundingBox: smallBox),
        imageSize: _kImageSize,
        theme: theme,
      );
      expect(result.failingGate, ValidationGate.fillLow);
    });

    test('tilt → failingGate == ValidationGate.tilt', () {
      // Inject a 45-degree tilt via the test seam to trigger the tilt gate.
      DocumentValidationResult.tiltCalculator = (_) => 45.0;
      addTearDown(() => DocumentValidationResult.tiltCalculator = null);

      final result = DocumentValidationResult.evaluate(
        recognizedText: _makeRecognizedText(count: 5),
        imageSize: _kImageSize,
        theme: theme,
      );
      expect(result.failingGate, ValidationGate.tilt);
    });

    // ── failingGate is typed ValidationGate? ── compile-time check ─────────

    test('failingGate is of type ValidationGate? (not String?)', () {
      final result = DocumentValidationResult.evaluate(
        recognizedText: _makeRecognizedText(count: 0),
        imageSize: _kImageSize,
        theme: theme,
      );
      // This line will fail to compile if failingGate is String? — the
      // switch expression requires exhaustive matching on ValidationGate.
      final code = switch (result.failingGate) {
        ValidationGate.minBlocks => 'min_blocks',
        ValidationGate.centering => 'centering',
        ValidationGate.fillHigh => 'fill_high',
        ValidationGate.fillLow => 'fill_low',
        ValidationGate.lineCount => 'line_count',
        ValidationGate.tilt => 'tilt',
        null => 'ok',
      };
      expect(code, isNotNull);
    });
  });
}
