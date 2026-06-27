import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

class _MockCameraController extends Mock implements CameraController {}

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

Widget _buildScanner({
  required CameraController cam,
  required GlobalKey<DniScannerState> key,
  required bool isBackSide,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniScanner(
          key: key,
          controller: cam,
          isBackSide: isBackSide,
          autoCaptureMs: 1500,
          gracePeriodMs: 600,
          minStableFrames: 2,
          motionGate: _StillMotionGate(),
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

  group('DniScanner quad framing gate wiring', () {
    testWidgets('valid quad framing allows front countdown to reach capture',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      key.currentState!.debugSetFramingValid(true);
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

    testWidgets('invalid quad framing blocks front countdown entry',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      key.currentState!.debugSetFramingValid(false);
      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureScanning>(),
      );
      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });

    testWidgets('valid quad framing auto-captures the BACK side via edges',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: true),
      );
      await tester.pump();

      key.currentState!.debugSetFramingValid(true);
      key.currentState!.debugFeedCaptureReady(HuntSignal.backCaptureReady);
      await tester.pump();

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      await tester.pump(const Duration(milliseconds: 1600));

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets('quad loss beyond grace during countdown resets to scanning',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      key.currentState!.debugSetFramingValid(true);
      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      key.currentState!.debugSetFramingValid(false);
      await tester.pump(const Duration(milliseconds: 800));

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureScanning>(),
      );
      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });

    testWidgets('framing defaults to valid before any quad result (fallback '
        'degrades to OCR-block, capture still works)', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      // No debugSetFramingValid call: the default must be valid so a fallback
      // detector (no quad signal) never blocks capture.
      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );
      await _disposeWidget(tester);
    });

    testWidgets('valid quad framing cannot override a wrong-side OCR block '
        '(no wrong-side capture)', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      // Quad reports a perfectly framed document, but the side gate (OCR-block
      // derived) says this frame is not captureable for the expected side.
      key.currentState!.debugSetFramingValid(true);
      key.currentState!.debugSetFrameCaptureable(false);
      key.currentState!.debugResetToScanning();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureScanning>(),
      );
      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });
  });
}
