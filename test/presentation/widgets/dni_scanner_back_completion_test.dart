import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

class _MockCameraController extends Mock implements CameraController {}

class _PassQualityGate extends ImageQualityGate {
  @override
  Future<QualityCheckResult> validate(Uint8List bytes) async =>
      QualityCheckResult.pass;
}

/// Motion gate that flaps [isStill] on a fixed cadence, mirroring a handheld
/// phone whose accelerometer never reads perfectly still. The device-confirmed
/// back hang (#5532) only reproduces under this jitter — a permanently-still
/// gate masks the reset-loop bug.
class _JitterMotionGate implements MotionStillnessGate {
  _JitterMotionGate({required this.stillEvery});

  /// Reads NOT still on every [stillEvery]-th query (1 in N frames jitters).
  final int stillEvery;
  int _calls = 0;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  bool get isStill {
    _calls++;
    return _calls % stillEvery != 0;
  }

  @override
  Stream<bool> watchStillness() => _controller.stream;

  @override
  void dispose() => unawaited(_controller.close());
}

class _StillMotionGate implements MotionStillnessGate {
  @override
  bool get isStill => true;
  @override
  Stream<bool> watchStillness() => const Stream<bool>.empty();
  @override
  void dispose() {}
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
  ImageQualityGate? imageQualityGate,
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
          imageQualityGate: imageQualityGate,
          onSideCaptured: (_) {},
        ),
      ),
    ),
  );
}

/// Drives the REAL back capture chain a live device frame uses — feeds textless
/// quad-confirmed back frames through [HuntStateMachine.recordFrame] via
/// [debugProcessFrameForTest] so the machine actually re-emits backCaptureReady
/// every frame (as on device), and advances the ticker between frames. Returns
/// once the capture leaves CountingDownWithAnchor or [maxFrames] elapses.
Future<void> _driveBackChain(
  WidgetTester tester,
  DniScannerState state, {
  int maxFrames = 80,
}) async {
  state.debugSetFramingValid(true);
  for (var frame = 0; frame < maxFrames; frame++) {
    state.debugProcessFrameForTest(
      detectedSide: DocumentSide.unknown,
      addedNewField: false,
      filledFields: 11,
    );
    await tester.pump(const Duration(milliseconds: 100));
    final cs = state.debugCaptureState;
    if (cs is DniCaptureInFlight || cs is DniCaptureDone) break;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(Offset.zero);
    registerFallbackValue(FocusMode.auto);
    registerFallbackValue(ExposureMode.auto);
  });

  group('DniScanner BACK capture completes on countdown elapse (#5532)', () {
    testWidgets(
      'the textless back FIRES takePicture and leaves the countdown even '
      'when the hand jitters throughout the dwell (device-confirmed hang)',
      (tester) async {
        final cam = _idleMockCamera();
        var takePictureCalls = 0;
        when(() => cam.takePicture()).thenAnswer((_) async {
          takePictureCalls++;
          return XFile('/nonexistent/fake_back.jpg');
        });
        final key = GlobalKey<DniScannerState>();
        // Handheld jitter: not-still on every 4th frame (1 in 4), exactly the
        // cadence that hung the back on the S22.
        final gate = _JitterMotionGate(stillEvery: 4);

        await tester.pumpWidget(
          _buildBackScanner(cam: cam, key: key, motionGate: gate),
        );
        await tester.pump();

        await _driveBackChain(tester, key.currentState!);

        // The actual photo MUST have been taken — the device bug left this at 0
        // for 125+ frames because the countdown reset-looped forever.
        expect(
          takePictureCalls,
          greaterThanOrEqualTo(1),
          reason:
              'the back countdown must elapse and fire the shutter even with '
              'handheld jitter; it hung forever before the fix',
        );

        // The countdown must NOT still be running — it reached a terminal capture.
        expect(
          key.currentState!.debugCaptureState,
          isNot(isA<DniCaptureCountingDown>()),
          reason:
              'the back must reach a terminal capture state, not keep the '
              'countdown running indefinitely',
        );

        await _disposeWidget(tester);
      },
    );

    testWidgets(
      'a held back with jitter advances the hunt machine to done after the '
      'shutter fires (the scan finishes instead of hanging)',
      (tester) async {
        final file = File(
          '${Directory.systemTemp.path}/dni_back_${DateTime.now().microsecondsSinceEpoch}.jpg',
        )..writeAsBytesSync(Uint8List.fromList(List<int>.filled(64, 7)));
        addTearDown(() {
          if (file.existsSync()) file.deleteSync();
        });
        final cam = _idleMockCamera();
        when(() => cam.takePicture()).thenAnswer((_) async => XFile(file.path));
        final key = GlobalKey<DniScannerState>();
        final gate = _JitterMotionGate(stillEvery: 4);

        await tester.pumpWidget(
          _buildBackScanner(
            cam: cam,
            key: key,
            motionGate: gate,
            imageQualityGate: _PassQualityGate(),
          ),
        );
        await tester.pump();

        // Drive the full chain under runAsync so the real Timer.periodic ticker
        // AND the capture body's real I/O (file read → blur gate → crop isolate →
        // advanceToDone) all progress. Frames are fed on a real ~100ms cadence,
        // jittering the hand, exactly like the device image stream.
        final state = key.currentState!;
        state.debugSetFramingValid(true);
        await tester.runAsync(() async {
          for (var frame = 0; frame < 80; frame++) {
            if (state.debugHuntPhase == HuntPhase.done) break;
            state.debugProcessFrameForTest(
              detectedSide: DocumentSide.unknown,
              addedNewField: false,
              filledFields: 11,
            );
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        });
        await tester.pump();

        expect(
          state.debugHuntPhase,
          HuntPhase.done,
          reason:
              'after the back shutter fires the hunt machine must advance to '
              'done so the flow closes instead of hanging on the back',
        );

        await _disposeWidget(tester);
      },
    );
  });

  group('DniScanner FRONT capture path unchanged (#5532 regression)', () {
    testWidgets(
      'a steady front still reaches inFlight at autoCaptureMs and advances '
      'toward the back phase',
      (tester) async {
        final cam = _idleMockCamera();
        var takePictureCalls = 0;
        when(() => cam.takePicture()).thenAnswer((_) async {
          takePictureCalls++;
          return XFile('/nonexistent/fake_front.jpg');
        });
        final key = GlobalKey<DniScannerState>();
        final gate = _StillMotionGate();

        await tester.pumpWidget(
          MaterialApp(
            home: KycThemeProvider(
              theme: KycTheme.defaults(),
              child: Scaffold(
                body: DniScanner(
                  key: key,
                  controller: cam,
                  isBackSide: false,
                  autoCaptureMs: 3000,
                  gracePeriodMs: 600,
                  minStableFrames: 2,
                  motionGate: gate,
                  onSideCaptured: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        // Start the live front countdown and advance the ticker past 3s.
        key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
        await tester.pump();
        for (var i = 0; i < 38; i++) {
          if (key.currentState!.debugCaptureState is! DniCaptureCountingDown) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 100));
        }

        expect(
          takePictureCalls,
          greaterThanOrEqualTo(1),
          reason: 'the steady front must still auto-capture exactly as before',
        );

        await _disposeWidget(tester);
      },
    );
  });
}
