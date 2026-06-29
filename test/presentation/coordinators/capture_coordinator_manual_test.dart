import 'package:dni_peru_ocr/src/domain/extraction/dni_fields.dart';
import 'package:dni_peru_ocr/src/domain/extraction/hunt_state_machine.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_coordinator.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/frame_input.dart';
import 'package:flutter_test/flutter_test.dart';

/// PR5 — manual-fallback single source migrated into the [CaptureCoordinator].
///
/// Before PR5 the manual button read the [DniCameraController]'s parallel
/// `captureState.manualModeActive`, driven by its own ~15s timer that ran
/// IN PARALLEL and did not know an auto-capture was in progress (#5536/#5494).
/// PR5 makes the coordinator the SINGLE source: it owns the per-side fallback
/// window (measured against the injectable clock) and exposes
/// [CaptureCoordinator.manualAvailable]. The flag is SUPPRESSED while an
/// auto-capture is in progress (a countdown is running) so the manual stays a
/// REAL fallback that never competes with the live 3-2-1, and only becomes true
/// once the per-side window elapses without the side stabilizing.
const _frontText = 'DOCUMENTO NACIONAL DE IDENTIDAD\n'
    'DNI 16793105\n'
    'PRIMER APELLIDO\nMUÑOZ\n'
    'SEGUNDO APELLIDO\nPEREZ\n'
    'PRE NOMBRES\nJUAN CARLOS';

const _autoCaptureMs = 3000;
const _manualFallbackMs = 15000;

FrameInput _frontFrameAt(DateTime now) => FrameInput(
      ocrText: _frontText,
      quadFramingValid: false,
      imuStill: true,
      now: now,
    );

FrameInput _blankFrameAt(DateTime now) => FrameInput(
      ocrText: 'PERU 2024',
      quadFramingValid: false,
      imuStill: true,
      now: now,
    );

CaptureCoordinator _coordinator({int idleFramesThreshold = 100}) =>
    CaptureCoordinator(
      fields: DniFields.minimal(),
      // High idle threshold so recoverManual never fires from idle — this test
      // isolates the TIMER-based fallback window, not the stuck-side escape.
      idleFramesThreshold: idleFramesThreshold,
      autoCaptureMs: _autoCaptureMs,
      gracePeriodMs: 600,
      manualFallbackMs: _manualFallbackMs,
      minStableFrames: 1,
    );

void main() {
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);

  group('CaptureCoordinator.manualAvailable — single fallback source', () {
    test('starts unavailable when scanning opens', () {
      final coordinator = _coordinator();
      expect(coordinator.manualAvailable, isFalse);
    });

    test(
      'becomes available after the per-side fallback window elapses without '
      'the side stabilizing',
      () {
        final coordinator = _coordinator();

        // A blank/anchorless view that never stabilizes. Feed frames past the
        // fallback window against the injectable clock.
        for (var ms = 0; ms <= _manualFallbackMs + 1000; ms += 500) {
          coordinator.onFrame(_blankFrameAt(t0.add(Duration(milliseconds: ms))));
        }

        expect(
          coordinator.manualAvailable,
          isTrue,
          reason: 'after the per-side window the manual fallback must surface',
        );
      },
    );

    test(
      'stays SUPPRESSED while an auto-capture countdown is in progress even '
      'past the fallback window — manual never competes with the live 3-2-1',
      () {
        final coordinator = _coordinator();

        // Hold a ready front so a countdown runs the whole time, advancing the
        // clock well past the fallback window. The countdown completing/firing
        // is fine; what matters is that while it is COUNTING the manual is off.
        var sawCountingManualSuppressed = false;
        for (var ms = 0; ms <= _manualFallbackMs + 4000; ms += 200) {
          final decision =
              coordinator.onFrame(_frontFrameAt(t0.add(Duration(milliseconds: ms))));
          final counting = decision.runtimeType.toString() == 'CaptureCountingDown';
          if (counting) {
            sawCountingManualSuppressed = true;
            expect(
              coordinator.manualAvailable,
              isFalse,
              reason: 'manual must be suppressed while a countdown is running',
            );
          }
        }

        expect(sawCountingManualSuppressed, isTrue,
            reason: 'the held front must run a countdown to exercise suppression');
      },
    );

    test(
      'the per-side window restarts at the front->back handoff so the back '
      'gets its own full window instead of inheriting the front elapsed time '
      '(#5536)',
      () {
        final coordinator = _coordinator();

        // Spend most of a window on the front, then hand off to the back.
        for (var ms = 0; ms <= _manualFallbackMs - 2000; ms += 1000) {
          coordinator.onFrame(_frontFrameAt(t0.add(Duration(milliseconds: ms))));
        }
        coordinator.advanceAfterCapture();
        expect(coordinator.phase, HuntPhase.waitingBack);

        // Just past where the ORIGINAL window would have elapsed: the back must
        // NOT yet offer manual because its window restarted at the handoff.
        final justPastOriginal = t0.add(const Duration(milliseconds: _manualFallbackMs + 500));
        coordinator.onFrame(
          FrameInput(ocrText: '', quadFramingValid: false, imuStill: true, now: justPastOriginal),
        );
        expect(
          coordinator.manualAvailable,
          isFalse,
          reason: 'the back manual window must measure from the handoff, not '
              'from scanner open',
        );
      },
    );
  });
}
