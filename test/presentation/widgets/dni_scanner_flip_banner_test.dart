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

Widget _buildScanner(CameraController cam, {required HuntPhase phase}) =>
    MaterialApp(
      home: KycThemeProvider(
        theme: KycTheme.defaults(),
        child: Scaffold(
          body: DniScanner(
            controller: cam,
            onScanComplete: (_) {},
            stateMachine: HuntStateMachine(initialPhase: phase),
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

  group('DniScanner flip-document banner', () {
    testWidgets('shows the flip instruction text when waiting for the back side',
        (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(
        _buildScanner(cam, phase: HuntPhase.waitingBack),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Voltea tu DNI'), findsWidgets);

      await _dispose(tester);
    });

    testWidgets('renders the Material Orange gradient when waiting for the back',
        (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(
        _buildScanner(cam, phase: HuntPhase.waitingBack),
      );
      await tester.pump(const Duration(milliseconds: 350));

      final containers = tester.widgetList<Container>(find.byType(Container));
      LinearGradient? gradient;
      for (final c in containers) {
        final deco = c.decoration;
        if (deco is BoxDecoration && deco.gradient is LinearGradient) {
          gradient = deco.gradient as LinearGradient;
          break;
        }
      }
      expect(gradient, isNotNull,
          reason: 'Flip banner should paint a LinearGradient');
      expect(gradient!.colors, contains(const Color(0xFFFB8C00)));
      expect(gradient.colors, contains(const Color(0xFFF57C00)));

      await _dispose(tester);
    });

    testWidgets('animates the flip icon with a repeating RotationTransition',
        (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(
        _buildScanner(cam, phase: HuntPhase.waitingBack),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final rotations = tester
          .widgetList<RotationTransition>(find.byType(RotationTransition));
      expect(rotations, isNotEmpty,
          reason: 'Flip banner should contain a RotationTransition');
      expect(rotations.first.turns.isAnimating, isTrue,
          reason: 'The rotation controller should repeat');

      await _dispose(tester);
    });

    testWidgets('collapses the banner opacity while waiting for the front side',
        (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(
        _buildScanner(cam, phase: HuntPhase.waitingFront),
      );
      await tester.pump(const Duration(milliseconds: 350));

      final opacities = tester
          .widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .toList();
      expect(opacities, isNotEmpty,
          reason: 'Flip banner uses an AnimatedOpacity to show/hide');
      expect(opacities.any((o) => o.opacity == 0.0), isTrue,
          reason: 'On the front side the flip banner opacity must be 0');

      await _dispose(tester);
    });

    testWidgets('disposes its AnimationController without leaking a ticker',
        (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(
        _buildScanner(cam, phase: HuntPhase.waitingBack),
      );
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      expect(tester.binding.transientCallbackCount, equals(0),
          reason: 'All AnimationControllers should be disposed');
    });
  });
}
