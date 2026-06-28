import 'package:dni_peru_ocr/src/domain/extraction/dni_fields.dart';
import 'package:dni_peru_ocr/src/domain/extraction/hunt_state_machine.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_coordinator.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_decision.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/frame_input.dart';
import 'package:flutter_test/flutter_test.dart';

/// PR4 — countdown/dwell migration into the [CaptureCoordinator].
///
/// These tests pin the MIGRATED ownership: the coordinator now owns the
/// countdown/dwell decision (the `DniCaptureOrchestrator` + the capture state +
/// the wall-clock anchor), driven by the injectable [FrameInput.now] clock. A
/// readiness signal no longer fires immediately — it STARTS a countdown that
/// emits [CaptureCountingDown] each held frame and [CaptureFire] only when the
/// dwell completes. A disturbance past the grace window emits [CaptureReset].
///
/// The clock is supplied per frame (above OCR, like every other frame value),
/// so the dwell is deterministic and needs NO real Timer — exactly what the
/// device-faithful harness requires.
const _frontText = 'DOCUMENTO NACIONAL DE IDENTIDAD\n'
    'DNI 16793105\n'
    'PRIMER APELLIDO\nMUÑOZ\n'
    'SEGUNDO APELLIDO\nPEREZ\n'
    'PRE NOMBRES\nJUAN CARLOS';

const _autoCaptureMs = 3000;
const _gracePeriodMs = 600;

FrameInput _frontFrameAt(DateTime now, {bool quadFramingValid = false}) =>
    FrameInput(
      ocrText: _frontText,
      quadFramingValid: quadFramingValid,
      imuStill: true,
      now: now,
    );

FrameInput _emptyFrameAt(DateTime now, {bool quadFramingValid = false}) =>
    FrameInput(
      ocrText: '',
      quadFramingValid: quadFramingValid,
      imuStill: true,
      now: now,
    );

CaptureCoordinator _twoSided() => CaptureCoordinator(
      fields: DniFields.minimal(),
      idleFramesThreshold: 4,
      autoCaptureMs: _autoCaptureMs,
      gracePeriodMs: _gracePeriodMs,
      minStableFrames: 1,
    );

void main() {
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);

  group('CaptureDecision — widened countdown lifecycle', () {
    test('CaptureCountingDown carries the dwell progress', () {
      const counting = CaptureCountingDown(0.5);
      expect(counting.progress, 0.5);
    });

    test('CaptureReset is a distinct decision the widget can render', () {
      const reset = CaptureReset();
      expect(reset, isA<CaptureDecision>());
    });
  });

  group('CaptureCoordinator — countdown ownership (front)', () {
    test(
      'a front readiness signal STARTS a countdown instead of firing '
      'immediately — the first ready frame emits CaptureCountingDown',
      () {
        final coordinator = _twoSided();

        // Frame 0 latches extractingFront (Scanning); frame 1 reaches the OCR
        // completion floor — under the OLD model this returned Fire(front).
        coordinator.onFrame(_frontFrameAt(t0));
        final readyDecision = coordinator.onFrame(
          _frontFrameAt(t0.add(const Duration(milliseconds: 120))),
        );

        expect(
          readyDecision,
          isA<CaptureCountingDown>(),
          reason: 'the migrated coordinator starts a countdown on readiness — '
              'it no longer fires on the readiness signal frame',
        );
      },
    );

    test(
      'holding the front still for the full dwell completes the countdown and '
      'emits CaptureFire(front) — even with the quad false at the completion '
      'tick (cures "stay still after 3-2-1" / corners=0 at completion)',
      () {
        final coordinator = _twoSided();

        coordinator.onFrame(_frontFrameAt(t0));

        CaptureDecision? lastFire;
        var sawCountingDown = false;
        // Advance the injectable clock past autoCaptureMs across held frames.
        // The quad is FALSE on every frame (corners=0 device truth), so a Fire
        // at completion proves the front fires from OCR alone.
        for (var ms = 120; ms <= _autoCaptureMs + 600; ms += 120) {
          final decision = coordinator.onFrame(
            _frontFrameAt(t0.add(Duration(milliseconds: ms))),
          );
          if (decision is CaptureCountingDown) sawCountingDown = true;
          if (decision is CaptureFire) lastFire = decision;
        }

        expect(sawCountingDown, isTrue,
            reason: 'the dwell must visibly count down before firing');
        expect(lastFire, isNotNull,
            reason: 'a fully-held front dwell must fire at completion');
        expect((lastFire! as CaptureFire).side, CaptureSide.front);
      },
    );

    test(
      'a disturbance sustained past the grace window aborts the countdown and '
      'emits CaptureReset (document removed mid-dwell)',
      () {
        final coordinator = _twoSided();

        coordinator.onFrame(_frontFrameAt(t0));
        // Start the countdown with a held ready frame.
        final counting =
            coordinator.onFrame(_frontFrameAt(t0.add(const Duration(milliseconds: 120))));
        expect(counting, isA<CaptureCountingDown>());

        // The document is removed: empty OCR with no quad means the front is no
        // longer captureable. Hold the disturbance for longer than the grace
        // window; the coordinator must emit a reset (transient, like a fire)
        // and must NOT fire the shutter.
        final decisions = <CaptureDecision>[];
        for (var ms = 240; ms <= 240 + _gracePeriodMs + 600; ms += 120) {
          decisions.add(
            coordinator.onFrame(
              _emptyFrameAt(t0.add(Duration(milliseconds: ms))),
            ),
          );
        }

        expect(
          decisions.whereType<CaptureReset>(),
          isNotEmpty,
          reason: 'a disturbance past the grace window aborts the countdown',
        );
        expect(
          decisions.whereType<CaptureFire>(),
          isEmpty,
          reason: 'a removed document must never fire the shutter',
        );
      },
    );
  });

  group('CaptureCoordinator — countdown ownership (back)', () {
    test(
      'a textless back with a sustained valid quad counts down then fires '
      'CaptureFire(back) once the dwell completes',
      () {
        final coordinator = CaptureCoordinator(
          fields: DniFields.minimal(),
          idleFramesThreshold: 4,
          backQuadDwellFrames: 3,
          autoCaptureMs: _autoCaptureMs,
          gracePeriodMs: _gracePeriodMs,
          minStableFrames: 1,
          initialPhase: HuntPhase.waitingBack,
        );

        CaptureDecision? lastFire;
        var sawCountingDown = false;
        for (var ms = 0; ms <= _autoCaptureMs + 1200; ms += 120) {
          final decision = coordinator.onFrame(
            _emptyFrameAt(t0.add(Duration(milliseconds: ms)),
                quadFramingValid: true),
          );
          if (decision is CaptureCountingDown) sawCountingDown = true;
          if (decision is CaptureFire) lastFire = decision;
        }

        expect(sawCountingDown, isTrue);
        expect(lastFire, isNotNull);
        expect((lastFire! as CaptureFire).side, CaptureSide.back);
      },
    );
  });
}
