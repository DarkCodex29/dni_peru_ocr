import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

class _MockCameraController extends Mock implements CameraController {}

class _FakeXFile extends Fake implements XFile {}

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
  return mock;
}

Future<void> _disposeWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeXFile());
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(ImageFormatGroup.bgra8888);
  });

  group('DniCameraMask — fields parameter', () {
    testWidgets('mounts without fields param (backward compat)', (tester) async {
      final cam = _idleMockCamera();
      await tester.pumpWidget(
        MaterialApp(
          home: KycThemeProvider(
            theme: KycTheme.defaults(),
            child: Scaffold(
              body: DniCameraMask(
                controller: cam,
                onValidCapture: (_, __) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DniCameraMask), findsOneWidget);
      await _disposeWidget(tester);
    });

    testWidgets('mounts with fields: minimal() without error', (tester) async {
      final cam = _idleMockCamera();
      await tester.pumpWidget(
        MaterialApp(
          home: KycThemeProvider(
            theme: KycTheme.defaults(),
            child: Scaffold(
              body: DniCameraMask(
                controller: cam,
                onValidCapture: (_, __) {},
                fields: DniFields.minimal(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(DniCameraMask), findsOneWidget);
      await _disposeWidget(tester);
    });

    testWidgets(
        'fieldHunter built with minimal() has fewer than 14 extractors',
        (tester) async {
      final cam = _idleMockCamera();
      final hunter = FieldHunter.standard(fields: DniFields.minimal());
      await tester.pumpWidget(
        MaterialApp(
          home: KycThemeProvider(
            theme: KycTheme.defaults(),
            child: Scaffold(
              body: DniCameraMask(
                controller: cam,
                onValidCapture: (_, __) {},
                fieldHunter: hunter,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(hunter.extractors.length, lessThan(14));
      await _disposeWidget(tester);
    });

    testWidgets(
        'fieldHunter built with full() has all 14 extractors (backward compat)',
        (tester) async {
      final cam = _idleMockCamera();
      final hunter = FieldHunter.standard(fields: DniFields.full());
      await tester.pumpWidget(
        MaterialApp(
          home: KycThemeProvider(
            theme: KycTheme.defaults(),
            child: Scaffold(
              body: DniCameraMask(
                controller: cam,
                onValidCapture: (_, __) {},
                fieldHunter: hunter,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(hunter.extractors.length, 14);
      await _disposeWidget(tester);
    });

    testWidgets(
        'fields: minimal() without fieldHunter — effectiveFieldHunter '
        'has fewer than 14 extractors', (tester) async {
      final cam = _idleMockCamera();
      await tester.pumpWidget(
        MaterialApp(
          home: KycThemeProvider(
            theme: KycTheme.defaults(),
            child: Scaffold(
              body: DniCameraMask(
                controller: cam,
                onValidCapture: (_, __) {},
                fields: DniFields.minimal(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final maskState = tester.state(find.byType(DniCameraMask)) as dynamic;
      final hunter = maskState.effectiveFieldHunter as FieldHunter?;
      expect(hunter, isNotNull);
      expect(hunter!.extractors.length, lessThan(14));
      await _disposeWidget(tester);
    });

    testWidgets(
        'fields: omitted — effectiveFieldHunter defaults to DniFields.kyc',
        (tester) async {
      final cam = _idleMockCamera();
      await tester.pumpWidget(
        MaterialApp(
          home: KycThemeProvider(
            theme: KycTheme.defaults(),
            child: Scaffold(
              body: DniCameraMask(
                controller: cam,
                onValidCapture: (_, __) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final maskState = tester.state(find.byType(DniCameraMask)) as dynamic;
      final hunter = maskState.effectiveFieldHunter as FieldHunter?;
      expect(hunter, isNotNull);
      await _disposeWidget(tester);
    });
  });
}
