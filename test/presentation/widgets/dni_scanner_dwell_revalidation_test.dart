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

  group('DniScanner dwell re-validation of framing', () {
    testWidgets('document framed for the full dwell still fires the shutter',
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

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      await tester.pump(const Duration(milliseconds: 1600));

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets(
        'document lost beyond grace mid-dwell resets and does NOT fire',
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
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      key.currentState!.debugSetFrameCaptureable(false);
      await tester.pump(const Duration(milliseconds: 3000));

      verifyNever(() => cam.takePicture());
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureScanning>(),
      );
      await _disposeWidget(tester);
    });

    testWidgets('one-frame loss within grace keeps the anchor and still fires',
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
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      await tester.pump(const Duration(milliseconds: 200));
      key.currentState!.debugSetFrameCaptureable(false);
      await tester.pump(const Duration(milliseconds: 100));
      key.currentState!.debugSetFrameCaptureable(true);
      await tester.pump(const Duration(milliseconds: 1600));

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });
  });
}
