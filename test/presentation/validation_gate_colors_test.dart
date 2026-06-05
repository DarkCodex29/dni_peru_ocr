/// RED tests for ValidationGateColors presentation helper (PR4 — task 4.2b).
///
/// Verifies:
/// 1. ValidationGateColors exists in presentation layer.
/// 2. colorFor(null, theme) returns theme.success (capturable).
/// 3. All 6 ValidationGate values map to a non-null Color from KycTheme.
/// 4. No Color is hardcoded — all reference KycTheme tokens.
/// 5. Switch is exhaustive (compile-time guarantee).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

void main() {
  final theme = KycTheme.defaults();

  group('ValidationGateColors — all gates mapped', () {
    test('null (capturable) → theme.success', () {
      final color = ValidationGateColors.colorFor(null, theme);
      expect(color, equals(theme.success));
    });

    test('minBlocks → non-null Color from KycTheme', () {
      final color = ValidationGateColors.colorFor(ValidationGate.minBlocks, theme);
      expect(color, isNotNull);
    });

    test('centering → non-null Color from KycTheme', () {
      final color = ValidationGateColors.colorFor(ValidationGate.centering, theme);
      expect(color, isNotNull);
    });

    test('fillHigh → non-null Color from KycTheme', () {
      final color = ValidationGateColors.colorFor(ValidationGate.fillHigh, theme);
      expect(color, isNotNull);
    });

    test('fillLow → non-null Color from KycTheme', () {
      final color = ValidationGateColors.colorFor(ValidationGate.fillLow, theme);
      expect(color, isNotNull);
    });

    test('lineCount → non-null Color from KycTheme', () {
      final color = ValidationGateColors.colorFor(ValidationGate.lineCount, theme);
      expect(color, isNotNull);
    });

    test('tilt → non-null Color from KycTheme', () {
      final color = ValidationGateColors.colorFor(ValidationGate.tilt, theme);
      expect(color, isNotNull);
    });

    test('all failure gates map to either accentOrange or white (theme tokens)', () {
      final failureGates = [
        ValidationGate.minBlocks,
        ValidationGate.centering,
        ValidationGate.fillHigh,
        ValidationGate.fillLow,
        ValidationGate.lineCount,
        ValidationGate.tilt,
      ];
      for (final gate in failureGates) {
        final color = ValidationGateColors.colorFor(gate, theme);
        expect(
          color == theme.accentOrange || color == theme.white,
          isTrue,
          reason: 'Gate $gate should map to accentOrange or white, got $color',
        );
      }
    });
  });
}
