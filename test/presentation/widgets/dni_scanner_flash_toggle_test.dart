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

class _PassQualityGate extends ImageQualityGate {
  @override
  Future<QualityCheckResult> validate(Uint8List bytes) async =>
      QualityCheckResult.pass;
}

CameraValue _initializedValue() => const CameraValue(
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

_MockCameraController _idleMock() {
  final mock = _MockCameraController();
  when(() => mock.value).thenReturn(_initializedValue());
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

Widget _buildScanner(CameraController cam) => MaterialApp(
      home: KycThemeProvider(
        theme: KycTheme.defaults(),
        child: Scaffold(
          body: DniScanner(
            controller: cam,
            onScanComplete: (_) {},
            motionGate: _StillMotionGate(),
            imageQualityGate: _PassQualityGate(),
          ),
        ),
      ),
    );

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(Offset.zero);
    registerFallbackValue(FocusMode.auto);
    registerFallbackValue(ExposureMode.auto);
  });

  group('DniScanner flash toggle', () {
    testWidgets('renders a flash-off icon in the idle state', (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(_buildScanner(cam));
      await tester.pump();

      expect(find.byIcon(Icons.flash_off_rounded), findsOneWidget);

      await _dispose(tester);
    });

    testWidgets('toggle is enclosed in a circular container', (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(_buildScanner(cam));
      await tester.pump();

      final containers = tester.widgetList<Container>(find.byType(Container));
      final hasCircle = containers.any((c) {
        final deco = c.decoration;
        return deco is BoxDecoration &&
            deco.shape == BoxShape.circle &&
            deco.color != null;
      });
      expect(hasCircle, isTrue,
          reason: 'Flash toggle should be a circular container');

      await _dispose(tester);
    });

    testWidgets('tapping the flash toggle calls setFlashMode', (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(_buildScanner(cam));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.flash_off_rounded));
      await tester.pump();

      verify(() => cam.setFlashMode(FlashMode.torch)).called(1);

      await _dispose(tester);
    });

    testWidgets('tapping the flash toggle switches to the flash-on icon',
        (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(_buildScanner(cam));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.flash_off_rounded));
      await tester.pump();

      expect(find.byIcon(Icons.flash_on_rounded), findsOneWidget);
      expect(find.byIcon(Icons.flash_off_rounded), findsNothing);

      await _dispose(tester);
    });

    testWidgets('tapping the flash toggle triggers haptic feedback',
        (tester) async {
      final hapticCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          hapticCalls.add(call);
          return null;
        },
      );

      final cam = _idleMock();
      await tester.pumpWidget(_buildScanner(cam));
      await tester.pump();
      hapticCalls.clear();

      await tester.tap(find.byIcon(Icons.flash_off_rounded));
      await tester.pump();

      final vibrate = hapticCalls.where(
        (c) => c.method == 'HapticFeedback.vibrate',
      );
      expect(vibrate, isNotEmpty,
          reason: 'HapticFeedback should fire on flash toggle tap');

      await _dispose(tester);
    });

    testWidgets('flash toggle exposes an accessible touch target (>=44x44)',
        (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(_buildScanner(cam));
      await tester.pump();

      final iconEl = tester.element(find.byIcon(Icons.flash_off_rounded));
      final box = iconEl.renderObject as RenderBox?;
      expect(box, isNotNull);
      expect(box!.size.width, greaterThanOrEqualTo(20.0));
      expect(box.size.height, greaterThanOrEqualTo(20.0));

      await _dispose(tester);
    });
  });
}
