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
  DniCaptureMode captureMode = DniCaptureMode.auto,
  void Function(DniSideScanResult)? onSideCaptured,
  bool? isBackSide,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniScanner(
          controller: cam,
          captureMode: captureMode,
          isBackSide: isBackSide,
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

  group('DniCaptureMode.manual', () {
    testWidgets('renders the manual capture button', (tester) async {
      final cam = _idleMockCamera();
      await tester.pumpWidget(
        _buildScanner(cam: cam, captureMode: DniCaptureMode.manual),
      );
      await tester.pump();

      expect(find.byKey(const Key('dni_scanner_manual_capture')), findsOneWidget);
      await _disposeWidget(tester);
    });

    testWidgets('auto mode (default) does NOT render the capture button',
        (tester) async {
      final cam = _idleMockCamera();
      await tester.pumpWidget(_buildScanner(cam: cam));
      await tester.pump();

      expect(find.byKey(const Key('dni_scanner_manual_capture')), findsNothing);
      await _disposeWidget(tester);
    });

    testWidgets('tapping the capture button takes a picture', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));

      await tester.pumpWidget(
        _buildScanner(cam: cam, captureMode: DniCaptureMode.manual),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('dni_scanner_manual_capture')));
      await tester.pump();

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets(
        'single-side back mode: tap captures the back and emits onSideCaptured',
        (tester) async {
      final file = File(
        '${Directory.systemTemp.path}/dni_manual_${DateTime.now().microsecondsSinceEpoch}.jpg',
      )..writeAsBytesSync(Uint8List.fromList(List<int>.filled(64, 7)));
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile(file.path));
      DniSideScanResult? captured;

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          captureMode: DniCaptureMode.manual,
          isBackSide: true,
          onSideCaptured: (r) => captured = r,
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('dni_scanner_manual_capture')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(captured, isNotNull);
      expect(captured!.isBackSide, isTrue);
      await _disposeWidget(tester);
    });
  });

  group('DniCaptureMode.hybrid', () {
    testWidgets('renders the manual capture button as override', (tester) async {
      final cam = _idleMockCamera();
      await tester.pumpWidget(
        _buildScanner(cam: cam, captureMode: DniCaptureMode.hybrid),
      );
      await tester.pump();

      expect(find.byKey(const Key('dni_scanner_manual_capture')), findsOneWidget);
      await _disposeWidget(tester);
    });

    testWidgets('tapping the button captures without waiting for auto',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));

      await tester.pumpWidget(
        _buildScanner(cam: cam, captureMode: DniCaptureMode.hybrid),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('dni_scanner_manual_capture')));
      await tester.pump();

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });
  });

  group('pre-shutter focus/exposure lock', () {
    testWidgets(
        'locks focus and exposure before takePicture and restores auto after',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.setFocusMode(any())).thenAnswer((_) async {});
      when(() => cam.setExposureMode(any())).thenAnswer((_) async {});
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));

      await tester.pumpWidget(
        _buildScanner(cam: cam, captureMode: DniCaptureMode.manual),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('dni_scanner_manual_capture')));
      await tester.pump();

      verifyInOrder([
        () => cam.setFocusMode(FocusMode.locked),
        () => cam.setExposureMode(ExposureMode.locked),
        () => cam.takePicture(),
        () => cam.setFocusMode(FocusMode.auto),
        () => cam.setExposureMode(ExposureMode.auto),
      ]);
      await _disposeWidget(tester);
    });

    testWidgets(
        'still captures when the platform surfaces a raw PlatformException',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.setFocusMode(any())).thenThrow(
        PlatformException(code: 'setFocusModeFailed', message: 'unsupported'),
      );
      when(() => cam.setExposureMode(any())).thenThrow(
        PlatformException(
          code: 'setExposureModeFailed',
          message: 'unsupported',
        ),
      );
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));

      await tester.pumpWidget(
        _buildScanner(cam: cam, captureMode: DniCaptureMode.manual),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('dni_scanner_manual_capture')));
      await tester.pump();

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets('still captures when the device does not support locking',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.setFocusMode(any()))
          .thenThrow(CameraException('unsupported', 'no focus lock'));
      when(() => cam.setExposureMode(any()))
          .thenThrow(CameraException('unsupported', 'no exposure lock'));
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));

      await tester.pumpWidget(
        _buildScanner(cam: cam, captureMode: DniCaptureMode.manual),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('dni_scanner_manual_capture')));
      await tester.pump();

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });
  });

  group('DniFields side counts', () {
    test('kyc() selection: 6 front fields, 1 back field', () {
      final fields = DniFields.kyc();
      expect(fields.frontCount, 6);
      expect(fields.backCount, 1);
    });

    test('full() selection matches legacy totals', () {
      final fields = DniFields.full();
      expect(fields.frontCount, 12);
      expect(fields.backCount, 7);
    });

    test('minimal() selection is front-only', () {
      final fields = DniFields.minimal();
      expect(fields.frontCount, 4);
      expect(fields.backCount, 0);
    });
  });
}
