import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:dni_peru_ocr/src/presentation/widgets/quad_overlay_painter.dart';

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
          onSideCaptured: (_) {},
        ),
      ),
    ),
  );
}

Iterable<QuadOverlayPainter> _quadPainters(WidgetTester tester) {
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((cp) => cp.painter)
      .whereType<QuadOverlayPainter>();
}

void main() {
  setUpAll(() {
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(Offset.zero);
    registerFallbackValue(FocusMode.auto);
    registerFallbackValue(ExposureMode.auto);
  });

  group('DniScanner live quad overlay', () {
    testWidgets('renders the quad outline when four corners are present',
        (tester) async {
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(_buildScanner(cam: cam, key: key));
      await tester.pump();

      key.currentState!.debugSetQuad(const [
        QuadCorner(10, 20),
        QuadCorner(200, 20),
        QuadCorner(200, 300),
        QuadCorner(10, 300),
      ]);
      await tester.pump();

      final painters = _quadPainters(tester).toList();
      expect(painters, isNotEmpty);
      expect(painters.first.points, hasLength(4));

      await _disposeWidget(tester);
    });

    testWidgets('draws nothing when no corners are present', (tester) async {
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(_buildScanner(cam: cam, key: key));
      await tester.pump();

      // Default state: no quad detected yet.
      final painters = _quadPainters(tester).toList();
      for (final painter in painters) {
        expect(painter.points, isEmpty);
      }

      await _disposeWidget(tester);
    });

    testWidgets('clears the overlay when the quad becomes invalid',
        (tester) async {
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(_buildScanner(cam: cam, key: key));
      await tester.pump();

      key.currentState!.debugSetQuad(const [
        QuadCorner(10, 20),
        QuadCorner(200, 20),
        QuadCorner(200, 300),
        QuadCorner(10, 300),
      ]);
      await tester.pump();
      expect(_quadPainters(tester).first.points, hasLength(4));

      key.currentState!.debugSetQuad(const []);
      await tester.pump();

      for (final painter in _quadPainters(tester)) {
        expect(painter.points, isEmpty);
      }

      await _disposeWidget(tester);
    });
  });
}
