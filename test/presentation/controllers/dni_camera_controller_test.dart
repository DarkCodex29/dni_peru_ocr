// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/presentation/controllers/dni_camera_controller.dart';
import 'package:dni_peru_ocr/src/presentation/document_validator.dart';
import 'package:dni_peru_ocr/src/presentation/orchestrators/dni_capture_orchestrator.dart';
import 'package:dni_peru_ocr/src/presentation/orchestrators/dni_capture_state.dart';

// ─── Test helpers ─────────────────────────────────────────────────────────────

DniCaptureOrchestrator _orchestrator({
  int autoCaptureMs = 1500,
  int gracePeriodMs = 600,
  int manualFallbackMs = 15000,
  int minStableFrames = 2,
}) => DniCaptureOrchestrator(
    autoCaptureMs: autoCaptureMs,
    gracePeriodMs: gracePeriodMs,
    manualFallbackMs: manualFallbackMs,
    minStableFrames: minStableFrames,
  );

/// Builds a [DocumentValidationResult] for tests without ML Kit.
DocumentValidationResult _fakeValidation({required bool isCaptureable}) =>
    DocumentValidationResult.forTest(isCaptureable: isCaptureable);

/// Calls [DniCameraController.processFrame] with a synthetic frame result.
///
/// Convenience helper so individual tests don't repeat the full parameter list.
void _injectFrame(
  DniCameraController controller, {
  required bool isCaptureable,
  required int stableFrames,
  bool? userDataMatch,
  String? failingGate,
}) {
  controller.processFrame(
    validation: _fakeValidation(isCaptureable: isCaptureable),
    stableFrames: stableFrames,
    userDataMatch: userDataMatch,
    failingGate: failingGate,
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── Group 1: Initialization and initial state ─────────────────────────────

  group('DniCameraController — initialization and initial state', () {
    test('initial state is DniCaptureScanning', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      expect(controller.captureState.value, isA<DniCaptureScanning>());
    });

    test('initial scanning state has manualModeActive=false', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      final state = controller.captureState.value as DniCaptureScanning;
      expect(state.manualModeActive, isFalse);
    });

    test('exposes captureState as ValueListenable', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      // ValueListenable contract: can add/remove listeners without crashing
      var notified = false;
      void listener() => notified = true;
      controller.captureState.addListener(listener);
      controller.captureState.removeListener(listener);
      expect(notified, isFalse);
    });

    test('exposes telemetry as ValueListenable', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      expect(controller.telemetry.value, isA<DniTelemetry>());
    });
  });

  // ── Group 2: State transitions ────────────────────────────────────────────

  group('DniCameraController — state transitions', () {
    test('state notifies listeners when changed', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      var notifyCount = 0;
      controller.captureState.addListener(() => notifyCount++);

      // A captureable frame moves Scanning → CountingDown (a real change)
      _injectFrame(
        controller,
        isCaptureable: true,
        stableFrames: 1,
      );

      expect(notifyCount, greaterThan(0));
      expect(controller.captureState.value, isA<DniCaptureCountingDown>());
    });

    test('onSideChanged resets to DniCaptureScanning with manualModeActive=false', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      controller.onSideChanged();
      final state = controller.captureState.value;
      expect(state, isA<DniCaptureScanning>());
      expect((state as DniCaptureScanning).manualModeActive, isFalse);
    });

    test('onSideChanged can be called multiple times safely', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      controller.onSideChanged();
      controller.onSideChanged();
      controller.onSideChanged();

      expect(controller.captureState.value, isA<DniCaptureScanning>());
    });
  });

  // ── Group 3: Manual fallback timer ────────────────────────────────────────

  group('DniCameraController — manual fallback timer', () {
    test('state becomes manualModeActive=true after manualFallbackMs', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(manualFallbackMs: 50), // fast for tests
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      // start() arms the timer
      await controller.start();

      // Wait for the timer to fire
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final state = controller.captureState.value;
      expect(state, isA<DniCaptureScanning>());
      expect((state as DniCaptureScanning).manualModeActive, isTrue);
    });

    test('onSideChanged resets manualModeActive even after timer fires', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(manualFallbackMs: 50),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        (controller.captureState.value as DniCaptureScanning).manualModeActive,
        isTrue,
      );

      controller.onSideChanged();
      expect(
        (controller.captureState.value as DniCaptureScanning).manualModeActive,
        isFalse,
      );
    });
  });

  // ── Group 4: Dispose lifecycle ────────────────────────────────────────────

  group('DniCameraController — dispose lifecycle', () {
    test('dispose transitions state to Done', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );

      await controller.dispose();

      expect(controller.captureState.value, isA<DniCaptureDone>());
    });

    test('dispose is idempotent — second call does not throw', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );

      await controller.dispose();
      await expectLater(controller.dispose(), completes);
    });

    test('calling onSideChanged after dispose is a no-op (does not throw)', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );

      await controller.dispose();

      expect(() => controller.onSideChanged(), returnsNormally);
    });
  });

  // ── Group 5: Frame processing via orchestrator ────────────────────────────

  group('DniCameraController — frame processing delegates to orchestrator', () {
    test('captureable frame with enough stableFrames → CountingDown', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      _injectFrame(controller, isCaptureable: true, stableFrames: 1);

      expect(controller.captureState.value, isA<DniCaptureCountingDown>());
    });

    test('non-captureable frame keeps Scanning state', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(minStableFrames: 2),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      _injectFrame(controller, isCaptureable: false, stableFrames: 0);

      expect(controller.captureState.value, isA<DniCaptureScanning>());
    });

    test('countdown completion (elapsed >= autoCaptureMs) → InFlight', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(autoCaptureMs: 1, minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      // Start countdown
      _injectFrame(controller, isCaptureable: true, stableFrames: 1);
      expect(controller.captureState.value, isA<DniCaptureCountingDown>());

      // Let autoCaptureMs=1ms elapse
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Next captureable frame: elapsed ≥ 1ms → InFlight
      _injectFrame(controller, isCaptureable: true, stableFrames: 1);

      expect(controller.captureState.value, isA<DniCaptureInFlight>());
    });

    test('processFrame after dispose is a no-op (state stays Done)', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );

      await controller.dispose();
      final stateAfterDispose = controller.captureState.value;

      _injectFrame(controller, isCaptureable: true, stableFrames: 5);

      // State must not change — controller is disposed
      expect(controller.captureState.value, equals(stateAfterDispose));
    });

    test('quality regression within grace period keeps CountingDown', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(
          autoCaptureMs: 1500,
          gracePeriodMs: 600,
          minStableFrames: 1,
        ),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      // Start countdown
      _injectFrame(controller, isCaptureable: true, stableFrames: 1);
      expect(controller.captureState.value, isA<DniCaptureCountingDown>());

      // Brief quality regression while still within grace period (< 600ms)
      _injectFrame(controller, isCaptureable: false, stableFrames: 0);

      // Should still be counting down (grace period protects against reset)
      expect(controller.captureState.value, isA<DniCaptureCountingDown>());
    });
  });

  // ── Group 6: Telemetry exposure ───────────────────────────────────────────

  group('DniCameraController — telemetry', () {
    test('initial telemetry has zero/neutral values', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      final t = controller.telemetry.value;
      expect(t.stableFrames, equals(0));
      expect(t.failingGate, isNull);
    });

    test('telemetry updates after a processed frame', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      _injectFrame(
        controller,
        isCaptureable: false,
        stableFrames: 3,
        failingGate: 'tilt',
      );

      final t = controller.telemetry.value;
      expect(t.stableFrames, equals(3));
      expect(t.failingGate, equals('tilt'));
    });

    test('telemetry with no failingGate when captureable', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      _injectFrame(
        controller,
        isCaptureable: true,
        stableFrames: 2,
        failingGate: null,
      );

      expect(controller.telemetry.value.failingGate, isNull);
      expect(controller.telemetry.value.stableFrames, equals(2));
    });
  });

  // ── Group 7: Mid-capture dispose race condition ───────────────────────────

  group('DniCameraController — mid-capture dispose safety', () {
    test('dispose while InFlight does not throw', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(autoCaptureMs: 1, minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );

      _injectFrame(controller, isCaptureable: true, stableFrames: 1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      _injectFrame(controller, isCaptureable: true, stableFrames: 1);
      expect(controller.captureState.value, isA<DniCaptureInFlight>());

      await expectLater(controller.dispose(), completes);
    });

    test('captureManually while already InFlight is a no-op', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(autoCaptureMs: 1, minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      _injectFrame(controller, isCaptureable: true, stableFrames: 1);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      _injectFrame(controller, isCaptureable: true, stableFrames: 1);
      expect(controller.captureState.value, isA<DniCaptureInFlight>());

      // captureManually on InFlight should be a no-op
      expect(() => controller.captureManually(), returnsNormally);
      expect(controller.captureState.value, isA<DniCaptureInFlight>());
    });

    test('captureManually while Expired is a no-op', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
        onDocumentExpired: (_) {},
      );
      addTearDown(controller.dispose);

      // Inject expiration via processFrame
      controller.processFrame(
        validation: _fakeValidation(isCaptureable: false),
        stableFrames: 0,
        userDataMatch: null,
        expirationDate: DateTime(2020, 1, 1),
      );
      expect(controller.captureState.value, isA<DniCaptureExpired>());

      // captureManually on Expired must be no-op
      controller.captureManually();
      expect(controller.captureState.value, isA<DniCaptureExpired>());
    });
  });

  // ── Group 8: Document expiration ─────────────────────────────────────────

  group('DniCameraController — document expiration', () {
    test('expired document fires onDocumentExpired and sets Expired state', () {
      DateTime? firedDate;
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
        onDocumentExpired: (d) => firedDate = d,
      );
      addTearDown(controller.dispose);

      final pastDate = DateTime(2020, 1, 1);
      controller.processFrame(
        validation: _fakeValidation(isCaptureable: false),
        stableFrames: 0,
        userDataMatch: null,
        expirationDate: pastDate,
      );

      expect(firedDate, equals(pastDate));
      expect(controller.captureState.value, isA<DniCaptureExpired>());
    });

    test('expired document only fires once even if processFrame called again', () {
      var fireCount = 0;
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
        onDocumentExpired: (_) => fireCount++,
      );
      addTearDown(controller.dispose);

      final pastDate = DateTime(2020, 1, 1);
      controller.processFrame(
        validation: _fakeValidation(isCaptureable: false),
        stableFrames: 0,
        userDataMatch: null,
        expirationDate: pastDate,
      );
      controller.processFrame(
        validation: _fakeValidation(isCaptureable: false),
        stableFrames: 0,
        userDataMatch: null,
        expirationDate: pastDate,
      );

      expect(fireCount, equals(1));
    });

    test('future expiration date is NOT treated as expired', () {
      var fired = false;
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
        onDocumentExpired: (_) => fired = true,
      );
      addTearDown(controller.dispose);

      final futureDate = DateTime.now().add(const Duration(days: 365));
      controller.processFrame(
        validation: _fakeValidation(isCaptureable: false),
        stableFrames: 0,
        userDataMatch: null,
        expirationDate: futureDate,
      );

      expect(fired, isFalse);
      expect(controller.captureState.value, isA<DniCaptureScanning>());
    });
  });

  // ── Group 9: onCaptureDelivered ───────────────────────────────────────────

  group('DniCameraController — onCaptureDelivered', () {
    test('onCaptureDelivered fires onValidCapture and transitions to Done', () {
      dynamic capturedFile;
      dynamic capturedConsensus;
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (file, consensus) {
          capturedFile = file;
          capturedConsensus = consensus;
        },
      );
      addTearDown(controller.dispose);

      controller.onCaptureDelivered(file: 'photo.jpg', consensus: 'some_consensus');

      expect(capturedFile, equals('photo.jpg'));
      // isBackSide=false: consensus is always null on front side
      expect(capturedConsensus, isNull);
      expect(controller.captureState.value, isA<DniCaptureDone>());
    });

    test('onCaptureDelivered on back side passes consensus through', () {
      dynamic capturedConsensus;
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: true,
        onValidCapture: (_, consensus) => capturedConsensus = consensus,
      );
      addTearDown(controller.dispose);

      controller.onCaptureDelivered(file: 'photo.jpg', consensus: 'back_consensus');

      expect(capturedConsensus, equals('back_consensus'));
    });

    test('onCaptureDelivered after dispose is a no-op', () async {
      var called = false;
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) => called = true,
      );

      await controller.dispose();
      controller.onCaptureDelivered(file: 'photo.jpg');

      expect(called, isFalse);
    });
  });

  group('DniTelemetry — value equality', () {
    test('two telemetries with identical fields are equal', () {
      const a = DniTelemetry(stableFrames: 3, failingGate: 'tilt');
      const b = DniTelemetry(stableFrames: 3, failingGate: 'tilt');

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing stableFrames breaks equality', () {
      const a = DniTelemetry(stableFrames: 3, failingGate: null);
      const b = DniTelemetry(stableFrames: 4, failingGate: null);

      expect(a, isNot(equals(b)));
    });

    test('differing failingGate breaks equality', () {
      const a = DniTelemetry(stableFrames: 3, failingGate: null);
      const b = DniTelemetry(stableFrames: 3, failingGate: 'tilt');

      expect(a, isNot(equals(b)));
    });

    test('differing tiltDegrees breaks equality', () {
      const a = DniTelemetry(stableFrames: 3, failingGate: null);
      const b = DniTelemetry(
        stableFrames: 3,
        failingGate: null,
        tiltDegrees: 0.5,
      );

      expect(a, isNot(equals(b)));
    });
  });
}
