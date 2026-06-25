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
  int manualFallbackMs = 30000,
  bool? isBackSide,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniScanner(
          key: key,
          controller: cam,
          isBackSide: isBackSide,
          manualFallbackMs: manualFallbackMs,
          motionGate: _StillMotionGate(),
          onScanComplete: isBackSide == null ? (_) {} : null,
          onSideCaptured: isBackSide != null ? (_) {} : null,
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

  group('DniScanner manual fallback', () {
    testWidgets(
        'default 30000ms fallback activates manual mode and shows the button',
        (tester) async {
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(_buildScanner(cam: cam, key: key));
      await tester.pump();

      expect(key.currentState!.debugManualModeActive, isFalse);
      expect(
        find.byKey(const Key('dni_scanner_manual_capture')),
        findsNothing,
      );

      await tester.pump(const Duration(milliseconds: 30000));
      await tester.pump();

      expect(key.currentState!.debugManualModeActive, isTrue);
      expect(
        find.byKey(const Key('dni_scanner_manual_capture')),
        findsOneWidget,
      );

      await _disposeWidget(tester);
    });

    testWidgets('manual mode persists across a scanning reset',
        (tester) async {
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(_buildScanner(cam: cam, key: key));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 30000));
      await tester.pump();
      expect(key.currentState!.debugManualModeActive, isTrue);

      key.currentState!.debugResetToScanning();
      await tester.pump();

      expect(key.currentState!.debugManualModeActive, isTrue);

      await _disposeWidget(tester);
    });

    testWidgets('manual mode clears on side toggle', (tester) async {
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(_buildScanner(cam: cam, key: key));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 30000));
      await tester.pump();
      expect(key.currentState!.debugManualModeActive, isTrue);

      key.currentState!.debugTriggerSideToggle();
      await tester.pump();

      expect(key.currentState!.debugManualModeActive, isFalse);

      await _disposeWidget(tester);
    });
  });
}
