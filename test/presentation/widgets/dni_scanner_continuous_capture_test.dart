import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

class _MockCameraController extends Mock implements CameraController {}

class _FakeMotionGate implements MotionStillnessGate {
  _FakeMotionGate(this._isStill);

  final bool _isStill;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  bool get isStill => _isStill;

  @override
  Stream<bool> watchStillness() => _controller.stream;

  @override
  void dispose() {
    unawaited(_controller.close());
  }
}

class _StillMotionGate implements MotionStillnessGate {
  @override
  bool get isStill => true;

  @override
  Stream<bool> watchStillness() => const Stream<bool>.empty();

  @override
  void dispose() {}
}

class _PassQualityGate extends ImageQualityGate {
  @override
  Future<QualityCheckResult> validate(Uint8List bytes) async =>
      QualityCheckResult.pass;
}

CameraValue _initializedCameraValue() => const CameraValue(
      isInitialized: true,
      previewSize: Size(640, 480),
      isStreamingImages: false,
      isRecordingVideo: false,
      isTakingPicture: false,
      isRecordingPaused: false,
      flashMode: FlashMode.off,
      exposureMode: ExposureMode.auto,
      focusMode: FocusMode.auto,
      exposurePointSupported: false,
      focusPointSupported: false,
      deviceOrientation: DeviceOrientation.portraitUp,
      description: CameraDescription(
        name: 'test-cam',
        lensDirection: CameraLensDirection.back,
        sensorOrientation: 0,
      ),
    );

_MockCameraController _idleMockCamera() {
  final mock = _MockCameraController();
  when(() => mock.value).thenReturn(_initializedCameraValue());
  when(() => mock.description).thenReturn(
    const CameraDescription(
      name: 'test-cam',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 0,
    ),
  );
  when(() => mock.imageFormatGroup).thenReturn(null);
  when(() => mock.startImageStream(any())).thenAnswer((_) async {});
  when(() => mock.stopImageStream()).thenAnswer((_) async {});
  when(() => mock.buildPreview()).thenReturn(const SizedBox.expand());
  when(() => mock.setFlashMode(any())).thenAnswer((_) async {});
  when(() => mock.setFocusPoint(any())).thenAnswer((_) async {});
  when(() => mock.setExposurePoint(any())).thenAnswer((_) async {});
  when(() => mock.setFocusMode(any())).thenAnswer((_) async {});
  when(() => mock.setExposureMode(any())).thenAnswer((_) async {});
  return mock;
}

Future<void> _disposeWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

Widget _buildLiveScanner({
  required CameraController cam,
  required GlobalKey<DniScannerState> key,
  required MotionStillnessGate motionGate,
  int autoCaptureMs = 3000,
  int gracePeriodMs = 600,
  int minStableFrames = 2,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniScanner(
          key: key,
          controller: cam,
          isBackSide: false,
          autoCaptureMs: autoCaptureMs,
          gracePeriodMs: gracePeriodMs,
          minStableFrames: minStableFrames,
          motionGate: motionGate,
          onSideCaptured: (_) {},
        ),
      ),
    ),
  );
}

Widget _buildPhaseScanner(
  CameraController cam, {
  required HuntPhase phase,
}) =>
    MaterialApp(
      home: KycThemeProvider(
        theme: KycTheme.defaults(),
        child: Scaffold(
          body: DniScanner(
            controller: cam,
            onScanComplete: (_) {},
            stateMachine: HuntStateMachine(initialPhase: phase),
            motionGate: _StillMotionGate(),
            imageQualityGate: _PassQualityGate(),
          ),
        ),
      ),
    );

/// Drives the live per-frame countdown until the orchestrator transitions the
/// capture state into [DniCaptureInFlight] — the exact instant the shutter
/// fires and the white flash plays. Stops on the first non-CountingDown state
/// so the assertion lands at the capture moment, mid-processing, before the
/// state machine advances to the back phase.
///
/// Feeds exactly ONE capture-ready frame to start the countdown, then advances
/// only the internal ticker (no further feeds). This mirrors a real device:
/// once the shutter fires, [DniScannerState._onCaptureReady] early-returns for
/// every subsequent image-stream frame (in-flight / capturing), so NO extra
/// setState is queued around the in-flight transition. The only rebuild that
/// could clear the counter is the one the fix adds on the transition itself.
Future<void> _driveToCaptureInstant(
  WidgetTester tester,
  GlobalKey<DniScannerState> key,
  HuntSignal signal, {
  int autoCaptureMs = 3000,
}) async {
  key.currentState!.debugFeedCaptureReady(signal);
  await tester.pump();
  final ticks = (autoCaptureMs ~/ 100) + 8;
  for (var i = 0; i < ticks; i++) {
    if (key.currentState!.debugCaptureState is! DniCaptureCountingDown) {
      break;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(Offset.zero);
    registerFallbackValue(FocusMode.auto);
    registerFallbackValue(ExposureMode.auto);
  });

  const counterKey = Key('dni_scanner_countdown_counter');
  const successKey = Key('dni_scanner_transition_success_check');

  group('DniScanner continuous capture flow (no frozen counter, no check)', () {
    testWidgets(
        'the 3-2-1 counter is rendered WHILE counting down (sanity, so the '
        'clear-on-capture assertion is not trivially green)', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildLiveScanner(cam: cam, key: key, motionGate: gate),
      );
      await tester.pump();

      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
        reason: 'a countdown must be genuinely running for this sanity check',
      );
      expect(
        find.byKey(counterKey),
        findsOneWidget,
        reason: 'the centered 3-2-1 counter renders during the dwell',
      );

      await _disposeWidget(tester);
    });

    testWidgets(
        'the countdown counter CLEARS the instant the capture fires — no '
        'frozen "1" lingers during the post-capture processing window',
        (tester) async {
      final cam = _idleMockCamera();
      // Hold takePicture OPEN with a Completer that never resolves during the
      // assertion. This pins the scanner inside the real-device processing
      // window: the shutter fired (in-flight) but the camera is still busy and
      // the state machine has NOT yet advanced to the back phase. If the only
      // rebuild that clears the counter were the post-capture state-machine
      // advance, the counter would stay frozen here — exactly the device bug.
      final shutter = Completer<XFile>();
      when(() => cam.takePicture()).thenAnswer((_) => shutter.future);
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildLiveScanner(cam: cam, key: key, motionGate: gate),
      );
      await tester.pump();

      await _driveToCaptureInstant(
        tester,
        key,
        HuntSignal.frontCaptureReady,
      );

      // The capture fired: the orchestrator advanced the state past the
      // countdown into the in-flight (shutter) state, but takePicture is still
      // pending (Completer not completed) — we are mid-processing.
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureInFlight>(),
        reason: 'the dwell completed and the capture transitioned in-flight '
            'while takePicture is still pending',
      );

      // At that instant the countdown counter must already be GONE, BEFORE the
      // camera finishes. If it lingers, the user sees a frozen "1" during the
      // camera processing pause — the "stuck on step 1" freeze we are fixing.
      expect(
        find.byKey(counterKey),
        findsNothing,
        reason: 'the countdown counter must clear the instant capture fires, '
            'so no frozen digit lingers during the processing window',
      );

      // Release the shutter so the widget tears down cleanly.
      shutter.complete(XFile('/nonexistent/fake_front.jpg'));
      await tester.pump();
      await _disposeWidget(tester);
    });

    testWidgets(
        'the green transition success check is REMOVED — it never renders '
        'during the front-to-back transition', (tester) async {
      final cam = _idleMockCamera();
      await tester.pumpWidget(
        _buildPhaseScanner(cam, phase: HuntPhase.waitingBack),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.byKey(successKey),
        findsNothing,
        reason: 'the green success check was removed; only the flip guidance '
            'remains during the front-to-back transition',
      );

      await _disposeWidget(tester);
    });

    testWidgets(
        'the flip guidance text STILL renders during the front-to-back '
        'transition (preserved behavior minus the check)', (tester) async {
      final cam = _idleMockCamera();
      await tester.pumpWidget(
        _buildPhaseScanner(cam, phase: HuntPhase.waitingBack),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        find.text('Voltea tu DNI'),
        findsWidgets,
        reason: 'the flip-the-document guidance must still guide the user '
            'through the front-to-back transition',
      );

      await _disposeWidget(tester);
    });
  });
}
