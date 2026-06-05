/// RED tests for OcrConsensusAccumulator rename (PR4 — task 4.3).
///
/// Verifies:
/// 1. OcrConsensusAccumulator class exists with same behavior as OcrConsensusBuilder.
/// 2. OcrConsensusBuilder remains as a @Deprecated typedef alias.
/// 3. DniCameraController exposes onSideChanged() to seed the accumulator.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

void main() {
  group('OcrConsensusAccumulator — rename from OcrConsensusBuilder', () {
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

    // ── OcrConsensusBuilder must remain accessible (deprecated alias) ──────

    test('OcrConsensusBuilder still compiles (deprecated typedef alias)', () {
      // ignore: deprecated_member_use
      final builder = OcrConsensusBuilder();
      expect(builder, isNotNull);
    });

    test('OcrConsensusBuilder is a subtype of OcrConsensusAccumulator', () {
      // ignore: deprecated_member_use
      final builder = OcrConsensusBuilder();
      expect(builder, isA<OcrConsensusAccumulator>());
    });
  });

  group('DniCameraController — accumulator lifecycle via onSideChanged', () {
    test(
      'DniCameraController.onSideChanged() can be called without error',
      () {
        final orchestrator = DniCaptureOrchestrator(
          autoCaptureMs: 5000,
          gracePeriodMs: 1000,
          manualFallbackMs: 30000,
          minStableFrames: 10,
        );
        final controller = DniCameraController(
          orchestrator: orchestrator,
          isBackSide: false,
          onValidCapture: (_, __) {},
        );
        expect(() => controller.onSideChanged(), returnsNormally);
        controller.dispose();
      },
    );
  });
}
