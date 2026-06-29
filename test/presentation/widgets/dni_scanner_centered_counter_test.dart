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

/// Records every path stroked onto the canvas so a test can prove how many
/// paint operations the live `_HolePainter` performs (corners only vs. ring).
class _RecordingCanvas implements Canvas {
  int drawPathCalls = 0;

  @override
  void drawPath(Path path, Paint paint) {
    drawPathCalls++;
  }

  @override
  void noSuchMethod(Invocation invocation) {}
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

void main() {
  setUpAll(() {
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(Offset.zero);
    registerFallbackValue(FocusMode.auto);
    registerFallbackValue(ExposureMode.auto);
  });

  group('DniScanner centered 3-2-1 counter (replaces the border ring)', () {
    testWidgets(
        'shows the centered countdown digit while CountingDownWithAnchor is '
        'active (live per-frame path)', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, motionGate: gate),
      );
      await tester.pump();

      // Drive the live countdown a few frames in (~early dwell → digit 3).
      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final state = key.currentState!.debugCaptureState;
      expect(state, isA<DniCaptureCountingDown>());
      final progress = (state as DniCaptureCountingDown).progress;
      final expectedDigit = countdownDigitFromProgress(progress, state.totalMs);

      // The centered number must be rendered as visible text.
      expect(
        find.text('$expectedDigit'),
        findsOneWidget,
        reason: 'the centered 3-2-1 counter should display the digit matching '
            'the remaining dwell time (progress $progress → $expectedDigit)',
      );
      // Early in a 3s dwell the digit is 3.
      expect(expectedDigit, 3);

      await _disposeWidget(tester);
    });

    testWidgets('the live painter no longer strokes the border ring',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, motionGate: gate),
      );
      await tester.pump();

      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Confirm a countdown is genuinely running (the painter path that used
      // to draw the ring is exercised), so the assertion is not trivially
      // green from an idle scanner.
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );
      expect(key.currentState!.debugCountdownProgress, greaterThan(0));

      final painter = key.currentState!.debugBuildHolePainter();
      final recording = _RecordingCanvas();
      painter.paint(recording, const Size(400, 800));

      // The painter strokes the overlay cut-out path (1) plus the four corner
      // brackets (4) = 5 paths. The old border ring (a 6th drawPath during an
      // active countdown) is gone entirely — the live painter does not draw it
      // even while a countdown is running.
      expect(
        recording.drawPathCalls,
        5,
        reason: 'the countdown border ring must no longer be drawn; only the '
            'overlay cut-out and the four corner brackets should be stroked',
      );

      await _disposeWidget(tester);
    });
  });
}
