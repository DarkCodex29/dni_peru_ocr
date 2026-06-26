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
  int autoCaptureMs = 1500,
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

  group('DniScanner countdown re-entrancy (live per-frame path)', () {
    testWidgets(
      'repeated frontCaptureReady frames accumulate progress monotonically '
      'toward 1.0 (no mid-countdown reset)',
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

        final state = key.currentState!;

        // Simulate the LIVE camera loop: the hunt machine keeps returning
        // frontCaptureReady on EVERY frame once the dwell gate is satisfied,
        // so _onCaptureReady is re-entered frame after frame while the
        // countdown is still running. Frames arrive ~150ms apart.
        final progressSamples = <double>[];
        for (var frame = 0; frame < 8; frame++) {
          state.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
          await tester.pump(const Duration(milliseconds: 150));
          final current = state.debugCaptureState;
          if (current is DniCaptureInFlight || current is DniCaptureDone) {
            // Countdown already completed and fired — record full progress.
            progressSamples.add(1.0);
            break;
          }
          progressSamples.add(state.debugCountdownProgress);
        }

        // The ring must visibly grow: progress must climb toward 1.0 and never
        // collapse back to ~0 mid-countdown because of a repeated frame.
        final maxProgress =
            progressSamples.reduce((a, b) => a > b ? a : b);
        expect(
          maxProgress,
          greaterThan(0.5),
          reason: 'countdown progress should accumulate toward 1.0 across '
              'repeated frames, but it stalled near zero (ring invisible). '
              'Samples: $progressSamples',
        );

        // No mid-countdown collapse: once progress has grown, a later frame
        // must not reset it back to ~0 (the device "ring never fills" bug).
        for (var i = 1; i < progressSamples.length; i++) {
          final prev = progressSamples[i - 1];
          final curr = progressSamples[i];
          if (prev > 0.2) {
            expect(
              curr,
              greaterThan(prev - 0.05),
              reason: 'progress dropped from $prev to $curr at frame $i — a '
                  'repeated frame reset the countdown. Samples: '
                  '$progressSamples',
            );
          }
        }

        await _disposeWidget(tester);
      },
    );
  });
}
