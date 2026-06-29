import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

void main() {
  group('countdownDigitFromProgress (3s dwell → 3-2-1)', () {
    const totalMs = 3000;

    test('shows 3 while ~2.4s remain (early in the dwell)', () {
      // elapsed 600ms of 3000ms → progress 0.2 → remaining 2400ms → ceil = 3.
      expect(countdownDigitFromProgress(0.2, totalMs), 3);
    });

    test('shows 2 while ~1.2s remain (mid dwell)', () {
      // elapsed 1800ms of 3000ms → progress 0.6 → remaining 1200ms → ceil = 2.
      expect(countdownDigitFromProgress(0.6, totalMs), 2);
    });

    test('shows 1 while ~0.4s remain (near the end)', () {
      // elapsed 2600ms of 3000ms → progress ~0.867 → remaining 400ms → ceil = 1.
      expect(countdownDigitFromProgress(2600 / 3000, totalMs), 1);
    });

    test('shows 3 at the very start (progress 0)', () {
      expect(countdownDigitFromProgress(0, totalMs), 3);
    });

    test('clamps to 1 at full progress (never 0)', () {
      // remaining 0 → still floor the display at 1 so the user always sees a
      // digit through the final tick before the shutter fires.
      expect(countdownDigitFromProgress(1.0, totalMs), 1);
    });

    test('clamps to 1 when progress overshoots past 1.0', () {
      expect(countdownDigitFromProgress(1.5, totalMs), 1);
    });

    test('boundary: exactly 2.0s remaining still shows 2', () {
      // remaining exactly 2000ms → ceil(2000/1000) = 2 (not 3).
      expect(countdownDigitFromProgress(1000 / 3000, totalMs), 2);
    });

    test('boundary: exactly 1.0s remaining still shows 1', () {
      // remaining exactly 1000ms → ceil(1000/1000) = 1 (not 2).
      expect(countdownDigitFromProgress(2000 / 3000, totalMs), 1);
    });
  });
}
