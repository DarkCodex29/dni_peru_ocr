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

Widget _buildBackScanner({
  required CameraController cam,
  required GlobalKey<DniScannerState> key,
  required MotionStillnessGate motionGate,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniScanner(
          key: key,
          controller: cam,
          isBackSide: true,
          autoCaptureMs: 3000,
          gracePeriodMs: 600,
          minStableFrames: 2,
          motionGate: motionGate,
          onSideCaptured: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(Offset.zero);
    registerFallbackValue(FocusMode.auto);
    registerFallbackValue(ExposureMode.auto);
  });

  group('DniScanner centered 3-2-1 counter on the BACK side (#5471)', () {
    testWidgets(
        'shows the centered countdown digit while the BACK dwell is running '
        '(backCaptureReady drives the same counter as the front)',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildBackScanner(cam: cam, key: key, motionGate: gate),
      );
      await tester.pump();

      // Drive the live BACK countdown a few frames in (~early dwell → digit 3).
      key.currentState!.debugFeedCaptureReady(HuntSignal.backCaptureReady);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final state = key.currentState!.debugCaptureState;
      expect(state, isA<DniCaptureCountingDown>());
      final progress = (state as DniCaptureCountingDown).progress;
      final expectedDigit = countdownDigitFromProgress(progress, state.totalMs);

      // The centered number must be rendered as visible text on the back side
      // just like the front, so the user sees the 3-2-1 auto-capture countdown.
      expect(
        find.text('$expectedDigit'),
        findsOneWidget,
        reason: 'the centered 3-2-1 counter must display during the BACK dwell '
            '(progress $progress → digit $expectedDigit)',
      );
      expect(expectedDigit, 3);

      await _disposeWidget(tester);
    });
  });
}
