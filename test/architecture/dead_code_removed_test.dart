import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural guard for the capture-redesign PR1 dead-code removal.
///
/// PR1 deletes the orphan [CaptureDecider]/[CaptureSignal] capture engine and
/// the never-called `DniCameraController.processFrame` parallel orchestration
/// (plus its telemetry sibling). These symbols had zero live callers in `lib/`
/// and `example/`, so their removal is a behavior-neutral cleanup. This test
/// keeps them from creeping back in.
void main() {
  group('capture-redesign PR1 — dead code is removed', () {
    test('orphan CaptureDecider/CaptureSignal source files are deleted', () {
      expect(
        File('lib/src/domain/capture/capture_decider.dart').existsSync(),
        isFalse,
        reason: 'capture_decider.dart was an orphan with zero live callers.',
      );
      expect(
        File('lib/src/domain/capture/capture_signal.dart').existsSync(),
        isFalse,
        reason: 'capture_signal.dart only fed the orphan CaptureDecider.',
      );
    });

    test('public barrel no longer exports the removed capture symbols', () {
      final barrel = File('lib/dni_peru_ocr.dart').readAsStringSync();
      expect(
        barrel.contains('capture/capture_decider.dart'),
        isFalse,
        reason: 'CaptureDecider export is a public removal (see CHANGELOG).',
      );
      expect(
        barrel.contains('capture/capture_signal.dart'),
        isFalse,
        reason: 'CaptureSignal export is a public removal (see CHANGELOG).',
      );
    });

    test('controller no longer carries the dead processFrame engine', () {
      final controller = File(
        'lib/src/presentation/controllers/dni_camera_controller.dart',
      ).readAsStringSync();
      expect(
        controller.contains('void processFrame('),
        isFalse,
        reason: 'processFrame had zero callers in lib/ and example/.',
      );
      expect(
        controller.contains('class DniTelemetry'),
        isFalse,
        reason: 'DniTelemetry was only produced by the dead processFrame.',
      );
    });
  });

  group('capture-redesign PR5 — controller parallel capture-state removed', () {
    // PR5 (final migration) moved the single capture-readiness ownership —
    // countdown, presence, AND manual fallback — into CaptureCoordinator. The
    // DniCameraController's parallel capture-STATE subsystem (the second,
    // unreconciled source of truth #5494) had zero remaining readers and is
    // removed: the captureState notifier, the manual-fallback timer, and the
    // start / captureManually / activateManualFallback / restartManualFallbackTimer
    // methods. This guard keeps that parallel state from creeping back in.
    const controllerPath =
        'lib/src/presentation/controllers/dni_camera_controller.dart';

    test('controller no longer exposes the parallel captureState notifier', () {
      final controller = File(controllerPath).readAsStringSync();
      expect(
        controller.contains('get captureState'),
        isFalse,
        reason: 'the parallel captureState notifier was the second source of '
            'truth (#5494); CaptureCoordinator owns capture state now.',
      );
      expect(
        controller.contains('ValueNotifier<DniCaptureState>'),
        isFalse,
        reason: 'no parallel DniCaptureState notifier remains in the controller.',
      );
    });

    test('controller no longer carries the parallel manual-fallback subsystem',
        () {
      final controller = File(controllerPath).readAsStringSync();
      for (final removed in const <String>[
        'void activateManualFallback(',
        'void captureManually(',
        'void restartManualFallbackTimer(',
        '_manualFallbackTimer',
      ]) {
        expect(
          controller.contains(removed),
          isFalse,
          reason: 'the manual fallback is coordinator-owned now (#5536); '
              '"$removed" was the parallel controller source.',
        );
      }
    });
  });
}
