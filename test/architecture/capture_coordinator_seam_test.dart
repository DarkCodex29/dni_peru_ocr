import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural guard for the capture-redesign PR3a coordinator seam + harness.
///
/// PR3a introduces the [CaptureCoordinator] skeleton, the [FrameInput] /
/// [CaptureDecision] types, and the device-faithful frame-sequence harness. The
/// whole POINT of the harness is to close the 6x test blind spot (#5545) by
/// driving the REAL DocumentSideDetector + FieldHunter + HuntStateMachine chain
/// from realistic frame inputs — NOT by injecting capture flags below OCR. This
/// test pins three load-bearing invariants so a later change cannot quietly
/// re-open the blind spot, leak the seam into the public API, or pull Flutter /
/// dartcv into the pure-Dart coordinator.
void main() {
  const coordinatorDir = 'lib/src/presentation/coordinators';
  const harnessDir = 'test/harness';

  /// Debug-injection entry points that manufacture a readiness signal WITHOUT
  /// running the real path. A harness using any of these would have landed
  /// below OCR — the documented failure mode.
  const bannedInjectionTokens = <String>[
    'debugFeedCaptureReady',
    'debugSetFramingValid',
    'debugSetFrameCaptureable',
    'debugResetToScanning',
    'debugProcessFrameForTest',
  ];

  group('capture-redesign PR3a — coordinator seam + harness', () {
    test('the coordinator skeleton source files exist', () {
      expect(
        File('$coordinatorDir/capture_coordinator.dart').existsSync(),
        isTrue,
      );
      expect(
        File('$coordinatorDir/frame_input.dart').existsSync(),
        isTrue,
      );
      expect(
        File('$coordinatorDir/capture_decision.dart').existsSync(),
        isTrue,
      );
    });

    test('the harness drives the seam without any debug-flag injection', () {
      final harnessSources = Directory(harnessDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');

      for (final token in bannedInjectionTokens) {
        // Match an actual CALL (`.token(`), not a bare mention in a doc comment
        // describing the contract. The harness documents these as forbidden, so
        // the names appear in prose; only an invocation re-opens the blind spot.
        expect(
          harnessSources.contains('.$token('),
          isFalse,
          reason: 'the harness must run the REAL readiness path; "$token" is a '
              'below-OCR flag injection that re-opens the blind spot (#5545).',
        );
      }
    });

    test('the harness drives the real two-sided isBackSide:null path', () {
      final harnessSources = Directory(harnessDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');

      expect(
        harnessSources.contains('CaptureFrameSequenceHarness'),
        isTrue,
        reason: 'the device-faithful frame-sequence driver must be present.',
      );
      expect(
        harnessSources.contains('FrameInput('),
        isTrue,
        reason: 'the harness must construct FrameInput frames, not flags.',
      );
    });

    test('the coordinator, FrameInput and CaptureDecision stay INTERNAL', () {
      final barrel = File('lib/dni_peru_ocr.dart').readAsStringSync();
      expect(
        barrel.contains('coordinators/capture_coordinator.dart'),
        isFalse,
        reason: 'CaptureCoordinator is internal — not part of the public API.',
      );
      expect(
        barrel.contains('coordinators/frame_input.dart'),
        isFalse,
        reason: 'FrameInput is internal — not part of the public API.',
      );
      expect(
        barrel.contains('coordinators/capture_decision.dart'),
        isFalse,
        reason: 'CaptureDecision is internal — not part of the public API.',
      );
    });

    test('the coordinator stays pure Dart: no Flutter, no dartcv import', () {
      final coordinator =
          File('$coordinatorDir/capture_coordinator.dart').readAsStringSync();
      final frameInput =
          File('$coordinatorDir/frame_input.dart').readAsStringSync();
      final decision =
          File('$coordinatorDir/capture_decision.dart').readAsStringSync();
      final allSources = '$coordinator\n$frameInput\n$decision';

      expect(
        allSources.contains('package:flutter/'),
        isFalse,
        reason: 'the coordinator owns no widget/timer state in PR3a; it must '
            'stay pure Dart so it is trivially testable and layer-clean.',
      );
      expect(
        allSources.contains('package:dartcv'),
        isFalse,
        reason: 'dartcv stays confined to the opencv adapter.',
      );
    });
  });
}
