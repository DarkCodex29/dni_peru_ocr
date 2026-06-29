import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

class _MockCameraController extends Mock implements CameraController {}

class _FakeXFile extends Fake implements XFile {}

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
  return mock;
}

Future<void> _disposeWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

Widget _buildScanner({
  required CameraController cam,
  DniFields? fields,
  FieldHunter? hunter,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniScanner(
          controller: cam,
          onScanComplete: (_) {},
          hunter: hunter,
          fields: fields,
          motionGate: _StillMotionGate(),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeXFile());
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(ImageFormatGroup.bgra8888);
  });

  group('DniScanner — fields parameter', () {
    testWidgets('mounts without fields param (backward compat)', (tester) async {
      final cam = _idleMockCamera();
      await tester.pumpWidget(
        MaterialApp(
          home: KycThemeProvider(
            theme: KycTheme.defaults(),
            child: Scaffold(
              body: DniScanner(
                controller: cam,
                onScanComplete: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DniScanner), findsOneWidget);
      await _disposeWidget(tester);
    });

    testWidgets('mounts with fields: kyc() without error', (tester) async {
      final cam = _idleMockCamera();
      await tester.pumpWidget(
        _buildScanner(cam: cam, fields: DniFields.kyc()),
      );
      await tester.pump();
      expect(find.byType(DniScanner), findsOneWidget);
      await _disposeWidget(tester);
    });

    testWidgets('mounts with fields: minimal() without error', (tester) async {
      final cam = _idleMockCamera();
      await tester.pumpWidget(
        _buildScanner(cam: cam, fields: DniFields.minimal()),
      );
      await tester.pump();
      expect(find.byType(DniScanner), findsOneWidget);
      await _disposeWidget(tester);
    });

    testWidgets(
        'injected hunter with kyc() has fewer than 14 extractors', (tester) async {
      final cam = _idleMockCamera();
      final hunter = FieldHunter.standard(fields: DniFields.kyc());
      await tester.pumpWidget(
        _buildScanner(cam: cam, hunter: hunter),
      );
      await tester.pump();
      expect(hunter.extractors.length, lessThan(14));
      await _disposeWidget(tester);
    });

    testWidgets(
        'injected hunter with no fields has all 14 extractors', (tester) async {
      final cam = _idleMockCamera();
      final hunter = FieldHunter.standard();
      await tester.pumpWidget(
        _buildScanner(cam: cam, hunter: hunter),
      );
      await tester.pump();
      expect(hunter.extractors.length, 14);
      await _disposeWidget(tester);
    });
  });
}
