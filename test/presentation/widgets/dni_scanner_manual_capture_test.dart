import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

class _MockCameraController extends Mock implements CameraController {}

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
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
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
}
