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
}
