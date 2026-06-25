import 'dart:async';
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

class _ScriptedQualityGate extends ImageQualityGate {
  _ScriptedQualityGate(this._verdicts);

  final List<QualityCheckResult> _verdicts;
  int calls = 0;

  @override
  Future<QualityCheckResult> validate(Uint8List bytes) async {
    final index = calls < _verdicts.length ? calls : _verdicts.length - 1;
    calls++;
    return _verdicts[index];
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
  required ImageQualityGate gate,
  void Function(DniSideScanResult)? onSideCaptured,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniScanner(
          key: key,
          controller: cam,
          isBackSide: false,
          autoCaptureMs: 1500,
          gracePeriodMs: 600,
          minStableFrames: 2,
          motionGate: _StillMotionGate(),
          imageQualityGate: gate,
          onSideCaptured: onSideCaptured ?? (_) {},
        ),
      ),
    ),
  );
}

Future<void> _runCountdown(WidgetTester tester) async {
  for (var i = 0; i < 22; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 110));
    await tester.pump();
  }
}

void main() {
  late File capturedFile;

  setUpAll(() {
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(Offset.zero);
    registerFallbackValue(FocusMode.auto);
    registerFallbackValue(ExposureMode.auto);
  });

  setUp(() {
    capturedFile = File(
      '${Directory.systemTemp.path}/dni_blur_${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync(Uint8List.fromList(List<int>.filled(64, 7)));
  });

  tearDown(() {
    if (capturedFile.existsSync()) capturedFile.deleteSync();
  });

  group('DniScanner post-shutter blur gate', () {
    testWidgets('sharp capture emits onSideCaptured', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile(capturedFile.path));
      final gate = _ScriptedQualityGate([QualityCheckResult.pass]);
      final key = GlobalKey<DniScannerState>();
      DniSideScanResult? captured;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          _buildScanner(
            cam: cam,
            key: key,
            gate: gate,
            onSideCaptured: (r) => captured = r,
          ),
        );
        await tester.pump();

        key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
        await _runCountdown(tester);
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pump();

      expect(gate.calls, 1);
      expect(captured, isNotNull);
      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets('blurry capture rejects the shot and returns to scanning',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile(capturedFile.path));
      final gate = _ScriptedQualityGate([QualityCheckResult.blurry]);
      final key = GlobalKey<DniScannerState>();
      DniSideScanResult? captured;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          _buildScanner(
            cam: cam,
            key: key,
            gate: gate,
            onSideCaptured: (r) => captured = r,
          ),
        );
        await tester.pump();

        key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
        await _runCountdown(tester);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(gate.calls, 1);
      expect(captured, isNull);
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureScanning>(),
      );
      await _disposeWidget(tester);
    });

    testWidgets('undecodable capture does not emit', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile(capturedFile.path));
      final gate = _ScriptedQualityGate([QualityCheckResult.error]);
      final key = GlobalKey<DniScannerState>();
      DniSideScanResult? captured;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          _buildScanner(
            cam: cam,
            key: key,
            gate: gate,
            onSideCaptured: (r) => captured = r,
          ),
        );
        await tester.pump();

        key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
        await _runCountdown(tester);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(gate.calls, 1);
      expect(captured, isNull);
      await _disposeWidget(tester);
    });

    testWidgets(
        'bounded retry: sustained blur stops retrying at the cap and accepts',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile(capturedFile.path));
      final gate = _ScriptedQualityGate([QualityCheckResult.blurry]);
      final key = GlobalKey<DniScannerState>();
      DniSideScanResult? captured;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          _buildScanner(
            cam: cam,
            key: key,
            gate: gate,
            onSideCaptured: (r) => captured = r,
          ),
        );
        await tester.pump();

        for (var attempt = 0;
            attempt < DniScannerState.maxBlurRetries + 1;
            attempt++) {
          key.currentState!
              .debugFeedCaptureReady(HuntSignal.frontCaptureReady);
          await _runCountdown(tester);
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await tester.pump();
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pump();

      expect(gate.calls, DniScannerState.maxBlurRetries + 1);
      expect(captured, isNotNull);
      await _disposeWidget(tester);
    });
  });
}
