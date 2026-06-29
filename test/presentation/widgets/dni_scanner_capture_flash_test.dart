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

Widget _buildScanner({
  required CameraController cam,
  required GlobalKey<DniScannerState> key,
  required MotionStillnessGate motionGate,
  required bool isBackSide,
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
          isBackSide: isBackSide,
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

/// Drives the live per-frame countdown to completion so the orchestrator
/// transitions the capture state into [DniCaptureInFlight] — the exact moment
/// the shutter fires. Repeated capture-ready frames keep the anchor alive
/// (idempotent countdown, see #5463) while wall-clock advances past the dwell.
Future<void> _driveCountdownToCapture(
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
    key.currentState!.debugFeedCaptureReady(signal);
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

  const flashKey = Key('dni_scanner_capture_flash');

  group('DniScanner white capture flash on photo taken', () {
    testWidgets(
        'FRONT: a white flash overlay appears the moment the capture fires '
        'and then disappears after the short animation', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          motionGate: gate,
          isBackSide: false,
        ),
      );
      await tester.pump();

      // No flash before any capture fires.
      expect(find.byKey(flashKey), findsNothing);

      await _driveCountdownToCapture(
        tester,
        key,
        HuntSignal.frontCaptureReady,
      );

      // The capture fired (state advanced past CountingDown), and the flash
      // overlay is visible at the capture moment.
      expect(
        find.byKey(flashKey),
        findsOneWidget,
        reason: 'a white flash overlay must appear when the front photo is '
            'taken so the user sees the capture happened',
      );

      // The flash is snappy: after ~250ms the animation completes and the
      // overlay is gone (it is not persistent UI).
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byKey(flashKey),
        findsNothing,
        reason: 'the capture flash must auto-dismiss quickly; it is a brief '
            'flash, not persistent UI',
      );

      await _disposeWidget(tester);
    });

    testWidgets(
        'BACK: a white flash overlay also fires when the back photo is taken',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          motionGate: gate,
          isBackSide: true,
        ),
      );
      await tester.pump();

      expect(find.byKey(flashKey), findsNothing);

      await _driveCountdownToCapture(
        tester,
        key,
        HuntSignal.backCaptureReady,
      );

      expect(
        find.byKey(flashKey),
        findsOneWidget,
        reason: 'the white capture flash must fire on the BACK side too, not '
            'only the front',
      );

      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(flashKey), findsNothing);

      await _disposeWidget(tester);
    });
  });
}
