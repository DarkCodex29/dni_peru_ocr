import 'dart:async';
import 'dart:io';

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

class _PassingQualityGate extends ImageQualityGate {
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

Widget _buildSingleSideScanner({
  required CameraController cam,
  required GlobalKey<DniScannerState> key,
  required void Function(DniSideScanResult) onSideCaptured,
  void Function(Object error, StackTrace stack)? onError,
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
          imageQualityGate: _PassingQualityGate(),
          onSideCaptured: onSideCaptured,
          onError: onError,
        ),
      ),
    ),
  );
}

Widget _buildTwoSidedScanner({
  required CameraController cam,
  required GlobalKey<DniScannerState> key,
  required void Function(DniScanResult) onScanComplete,
  void Function(Object error, StackTrace stack)? onError,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniScanner(
          key: key,
          controller: cam,
          autoCaptureMs: 1500,
          gracePeriodMs: 600,
          minStableFrames: 2,
          motionGate: _StillMotionGate(),
          imageQualityGate: _PassingQualityGate(),
          onScanComplete: onScanComplete,
          onError: onError,
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
      '${Directory.systemTemp.path}/dni_cbr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync(Uint8List.fromList(List<int>.filled(64, 7)));
  });

  tearDown(() {
    if (capturedFile.existsSync()) capturedFile.deleteSync();
  });

  group('DniScanner host-callback resilience', () {
    testWidgets(
        'a throwing onSideCaptured does not crash the scanner and is '
        'forwarded to onError', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile(capturedFile.path));
      final key = GlobalKey<DniScannerState>();
      Object? forwardedError;
      StackTrace? forwardedStack;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          _buildSingleSideScanner(
            cam: cam,
            key: key,
            onSideCaptured: (_) => throw StateError('host blew up'),
            onError: (error, stack) {
              forwardedError = error;
              forwardedStack = stack;
            },
          ),
        );
        await tester.pump();

        key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
        await _runCountdown(tester);
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pump();

      expect(forwardedError, isA<StateError>());
      expect((forwardedError! as StateError).message, 'host blew up');
      expect(forwardedStack, isNotNull);
      expect(tester.takeException(), isNull);
      expect(find.byType(DniScanner), findsOneWidget);
      await _disposeWidget(tester);
    });

    testWidgets(
        'a throwing onSideCaptured with no onError is swallowed and does '
        'not crash the scanner', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile(capturedFile.path));
      final key = GlobalKey<DniScannerState>();

      await tester.runAsync(() async {
        await tester.pumpWidget(
          _buildSingleSideScanner(
            cam: cam,
            key: key,
            onSideCaptured: (_) => throw StateError('host blew up'),
          ),
        );
        await tester.pump();

        key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
        await _runCountdown(tester);
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(DniScanner), findsOneWidget);
      await _disposeWidget(tester);
    });

    testWidgets(
        'a throwing onScanComplete in two-sided mode does not crash the '
        'scanner and is forwarded to onError', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile(capturedFile.path));
      final key = GlobalKey<DniScannerState>();
      Object? forwardedError;

      await tester.runAsync(() async {
        await tester.pumpWidget(
          _buildTwoSidedScanner(
            cam: cam,
            key: key,
            onScanComplete: (_) => throw StateError('complete blew up'),
            onError: (error, _) => forwardedError = error,
          ),
        );
        await tester.pump();

        key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
        await _runCountdown(tester);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();

        // No manual debugResetToScanning here: the production front->back
        // handoff now clears the front InFlight on its own (#5535), so the back
        // countdown starts from a clean state exactly as on the device.
        key.currentState!.debugFeedCaptureReady(HuntSignal.backCaptureReady);
        await _runCountdown(tester);
        await Future<void>.delayed(const Duration(milliseconds: 700));
      });
      await tester.pump();

      expect(forwardedError, isA<StateError>());
      expect((forwardedError! as StateError).message, 'complete blew up');
      expect(tester.takeException(), isNull);
      expect(find.byType(DniScanner), findsOneWidget);
      await _disposeWidget(tester);
    });
  });
}
