/// Smoke tests for [OcrConsensusAccumulator] public surface and the
/// controller-side accumulator lifecycle hook.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

void main() {
  group('OcrConsensusAccumulator — public surface', () {
    test('OcrConsensusAccumulator can be instantiated', () {
      final accumulator = OcrConsensusAccumulator();
      expect(accumulator, isNotNull);
    });

    test('OcrConsensusAccumulator.recordVote works same as before', () {
      final accumulator = OcrConsensusAccumulator();
      accumulator.recordVote({'documentNumber': '12345678'});
      final result = accumulator.snapshot();
      expect(result.documentNumber.value, isNotNull);
    });

    test('OcrConsensusAccumulator.checkAllThresholds returns bool', () {
      final accumulator = OcrConsensusAccumulator();
      expect(accumulator.checkAllThresholds(), isFalse);
    });

    test('OcrConsensusAccumulator.dispose() completes without error', () {
      final accumulator = OcrConsensusAccumulator();
      expect(() => accumulator.dispose(), returnsNormally);
    });

    test('OcrConsensusAccumulator.isMrzLocked starts false', () {
      final accumulator = OcrConsensusAccumulator();
      expect(accumulator.isMrzLocked, isFalse);
    });
  });

  group('DniCameraController — accumulator lifecycle via onSideChanged', () {
    test(
      'DniCameraController.onSideChanged() can be called without error',
      () {
        final controller = DniCameraController(
          isBackSide: false,
          onValidCapture: (_, _) {},
        );
        expect(() => controller.onSideChanged(), returnsNormally);
        controller.dispose();
      },
    );
  });
}
