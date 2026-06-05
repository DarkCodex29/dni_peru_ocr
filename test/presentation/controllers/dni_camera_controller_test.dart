// ignore_for_file: prefer_const_constructors
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/presentation/controllers/dni_camera_controller.dart';
import 'package:dni_peru_ocr/src/presentation/orchestrators/dni_capture_orchestrator.dart';
import 'package:dni_peru_ocr/src/presentation/orchestrators/dni_capture_state.dart';

// ─── Fake CameraController contract ──────────────────────────────────────────
//
// The real camera plugin requires a platform channel (device). We define a
// minimal contract that DniCameraController needs from a camera and provide
// a fake that works purely in Dart with no platform channels.

/// Minimal contract DniCameraController needs from the camera plugin.
abstract class FakeCameraInterface {
  bool get isStreamingImages;
  bool get isInitialized;
  Future<void> startImageStream(void Function(dynamic image) onImage);
  Future<void> stopImageStream();
  Future<void> setFlashMode(dynamic mode);
}

/// Fake CameraController that works in unit tests (no platform channel).
class FakeCameraController implements FakeCameraInterface {
  bool _isStreamingImages = false;
  bool _isInitialized = true;

  void Function(dynamic image)? _imageStreamHandler;

  final List<String> calls = [];

  @override
  bool get isStreamingImages => _isStreamingImages;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> startImageStream(void Function(dynamic image) onImage) async {
    calls.add('startImageStream');
    _isStreamingImages = true;
    _imageStreamHandler = onImage;
  }

  @override
  Future<void> stopImageStream() async {
    calls.add('stopImageStream');
    _isStreamingImages = false;
    _imageStreamHandler = null;
  }

  @override
  Future<void> setFlashMode(dynamic mode) async {
    calls.add('setFlashMode:$mode');
  }

  /// Manually push a fake camera image to the stream.
  void pushImage(dynamic image) {
    _imageStreamHandler?.call(image);
  }
}

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

      // ValueListenable contract: can add/remove listeners
      var notified = false;
      void listener() => notified = true;
      controller.captureState.addListener(listener);
      controller.captureState.removeListener(listener);
      expect(notified, isFalse); // just structural: addListener doesn't crash
    });

    test('exposes telemetry as ValueListenable', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      // Should be accessible without crashing
      expect(controller.telemetry.value, isA<DniTelemetry>());
    });
  });

  // ── Group 2: State transitions via _updateState ───────────────────────────

  group('DniCameraController — state transitions', () {
    test('state notifies listeners when changed', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      var notifyCount = 0;
      controller.captureState.addListener(() => notifyCount++);

      // Trigger a transition via onSideChanged — resets to fresh scanning state
      controller.onSideChanged();

      expect(notifyCount, greaterThan(0));
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

      // Start stream to arm the timer
      await controller.start();

      // Wait for the timer to fire
      await Future<void>.delayed(const Duration(milliseconds: 150));

      final state = controller.captureState.value;
      expect(state, isA<DniCaptureScanning>());
      expect((state as DniCaptureScanning).manualModeActive, isTrue);
    });

    test('onSideChanged cancels manual fallback timer and resets manualModeActive', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(manualFallbackMs: 50), // fast for tests
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      await controller.start();
      // Wait for timer to fire
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        (controller.captureState.value as DniCaptureScanning).manualModeActive,
        isTrue,
      );

      // Side change should reset
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
      // Should not throw
      await expectLater(controller.dispose(), completes);
    });

    test('state notifications stop after dispose', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );

      await controller.dispose();

      // After dispose, calling onSideChanged should be a no-op (not crash)
      expect(() => controller.onSideChanged(), returnsNormally);
    });
  });

  // ── Group 5: Frame processing via orchestrator ────────────────────────────

  group('DniCameraController — frame processing delegates to orchestrator', () {
    test('processFrame with captureable=true transitions from Scanning to CountingDown', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      // Simulate a "perfect" frame: captureable=true, enough stable frames
      controller.injectTestFrame(
        isCaptureable: true,
        stableFrames: 1,
        userDataMatch: null,
      );

      expect(controller.captureState.value, isA<DniCaptureCountingDown>());
    });

    test('processFrame with captureable=false keeps Scanning state', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(minStableFrames: 2),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      controller.injectTestFrame(
        isCaptureable: false,
        stableFrames: 0,
        userDataMatch: null,
      );

      expect(controller.captureState.value, isA<DniCaptureScanning>());
    });

    test('processFrame after countdown completion triggers InFlight', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(autoCaptureMs: 1, minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      // First frame: start countdown
      controller.injectTestFrame(
        isCaptureable: true,
        stableFrames: 1,
        userDataMatch: null,
      );
      expect(controller.captureState.value, isA<DniCaptureCountingDown>());

      // Small delay to let autoCaptureMs=1ms elapse
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Second frame after elapsed time: triggers InFlight
      controller.injectTestFrame(
        isCaptureable: true,
        stableFrames: 1,
        userDataMatch: null,
      );

      expect(controller.captureState.value, isA<DniCaptureInFlight>());
    });

    test('processFrame after dispose is a no-op (does not change state)', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );

      await controller.dispose();
      final stateAfterDispose = controller.captureState.value;

      // Inject a frame after dispose: should be ignored
      controller.injectTestFrame(
        isCaptureable: true,
        stableFrames: 5,
        userDataMatch: null,
      );

      expect(controller.captureState.value, equals(stateAfterDispose));
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

    test('telemetry updates after a processed frame', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      controller.injectTestFrame(
        isCaptureable: false,
        stableFrames: 3,
        userDataMatch: null,
        failingGate: 'tilt',
      );

      final t = controller.telemetry.value;
      expect(t.stableFrames, equals(3));
      expect(t.failingGate, equals('tilt'));
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

      // Advance to CountingDown
      controller.injectTestFrame(
        isCaptureable: true,
        stableFrames: 1,
        userDataMatch: null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Advance to InFlight
      controller.injectTestFrame(
        isCaptureable: true,
        stableFrames: 1,
        userDataMatch: null,
      );
      expect(controller.captureState.value, isA<DniCaptureInFlight>());

      // Dispose during InFlight — must not throw
      await expectLater(controller.dispose(), completes);
    });

    test('captureManually while already InFlight is a no-op', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(autoCaptureMs: 1, minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, __) {},
      );
      addTearDown(controller.dispose);

      // Advance to InFlight
      controller.injectTestFrame(
        isCaptureable: true,
        stableFrames: 1,
        userDataMatch: null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      controller.injectTestFrame(
        isCaptureable: true,
        stableFrames: 1,
        userDataMatch: null,
      );
      expect(controller.captureState.value, isA<DniCaptureInFlight>());

      // Second captureManually should be a no-op, not crash
      expect(() => controller.captureManually(), returnsNormally);
      // State remains InFlight (no double-capture)
      expect(controller.captureState.value, isA<DniCaptureInFlight>());
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
      controller.injectExpiredDocument(expirationDate: pastDate);

      expect(firedDate, equals(pastDate));
      expect(controller.captureState.value, isA<DniCaptureExpired>());
    });

    test('expired document only fires once even if injected twice', () {
      var fireCount = 0;
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, __) {},
        onDocumentExpired: (_) => fireCount++,
      );
      addTearDown(controller.dispose);

      final pastDate = DateTime(2020, 1, 1);
      controller.injectExpiredDocument(expirationDate: pastDate);
      controller.injectExpiredDocument(expirationDate: pastDate);

      expect(fireCount, equals(1));
    });
  });
}
