import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:dni_peru_ocr/src/domain/capture/motion_stillness_gate.dart';

class _MockCameraController extends Mock implements CameraController {}

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

Widget _buildScanner({
  required CameraController cam,
  required GlobalKey<DniScannerState> key,
  void Function(DniSideScanResult)? onSideCaptured,
  bool? isBackSide,
  int autoCaptureMs = 1500,
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
          minStableFrames: minStableFrames,
          motionGate: _StillMotionGate(),
          imageQualityGate: _PassQualityGate(),
          onScanComplete: isBackSide == null ? (_) {} : null,
          onSideCaptured: isBackSide != null ? (onSideCaptured ?? (_) {}) : null,
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

  group('DniScanner capture via DniCaptureOrchestrator', () {
    testWidgets(
        'front capture-ready signal drives countingDown then inFlight capture',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );
      verifyNever(() => cam.takePicture());

      await tester.pump(const Duration(milliseconds: 1600));

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets('insufficient dwell does not fire capture early',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });

    testWidgets('back capture-ready signal drives capture in back mode',
        (tester) async {
      final file = File(
        '${Directory.systemTemp.path}/dni_orch_${DateTime.now().microsecondsSinceEpoch}.jpg',
      )..writeAsBytesSync(Uint8List.fromList(List<int>.filled(64, 7)));
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile(file.path));
      final key = GlobalKey<DniScannerState>();
      DniSideScanResult? captured;

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          isBackSide: true,
          onSideCaptured: (r) => captured = r,
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        key.currentState!.debugFeedCaptureReady(HuntSignal.backCaptureReady);
        await Future<void>.delayed(const Duration(milliseconds: 1800));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pump();

      verify(() => cam.takePicture()).called(1);
      expect(captured, isNotNull);
      expect(captured!.isBackSide, isTrue);
      await _disposeWidget(tester);
    });
  });
}
