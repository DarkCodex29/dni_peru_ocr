// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

class _MockCameraController extends Mock implements CameraController {}

class _FakeXFile extends Fake implements XFile {}

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
  when(() => mock.takePicture()).thenAnswer(
    (_) async => XFile('/tmp/test.jpg'),
  );
  when(() => mock.setFlashMode(any())).thenAnswer((_) async {});
  return mock;
}

Widget _buildApp(CameraController cam, {required bool isBackSide}) =>
    MaterialApp(
      home: KycThemeProvider(
        theme: KycTheme.defaults(),
        child: Scaffold(
          body: DniCameraMask(
            controller: cam,
            onValidCapture: (_, __) {},
            isBackSide: isBackSide,
          ),
        ),
      ),
    );

Future<void> _triggerSideIntro(
    WidgetTester tester, _MockCameraController cam) async {
  await tester.pumpWidget(_buildApp(cam, isBackSide: false));
  await tester.pump();
  await tester.pumpWidget(_buildApp(cam, isBackSide: true));
  await tester.pump();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeXFile());
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(ImageFormatGroup.bgra8888);
  });

  group('FlipDocumentBanner — gradient background', () {
    testWidgets('renders Material Orange 600 → 700 gradient when visible',
        (tester) async {
      final cam = _idleMock();
      await _triggerSideIntro(tester, cam);

      final containers = tester.widgetList<Container>(find.byType(Container));
      LinearGradient? found;
      for (final c in containers) {
        final deco = c.decoration;
        if (deco is BoxDecoration && deco.gradient is LinearGradient) {
          found = deco.gradient as LinearGradient;
          break;
        }
      }
      expect(found, isNotNull,
          reason: 'No LinearGradient found in FlipDocumentBanner');
      expect(found!.colors, contains(const Color(0xFFFB8C00)));
      expect(found.colors, contains(const Color(0xFFF57C00)));

      await _dispose(tester);
    });
  });

  group('FlipDocumentBanner — rotation animation', () {
    testWidgets('RotationTransition is present and animating (repeat)',
        (tester) async {
      final cam = _idleMock();
      await _triggerSideIntro(tester, cam);
      await tester.pump(const Duration(milliseconds: 50));

      final rotations = tester
          .widgetList<RotationTransition>(find.byType(RotationTransition));
      expect(rotations, isNotEmpty,
          reason: 'RotationTransition should be in FlipDocumentBanner');

      final rotation = rotations.first;
      expect(rotation.turns.isAnimating, isTrue,
          reason: '_rotate controller should be repeating');

      await _dispose(tester);
    });
  });

  group('FlipDocumentBanner — text content', () {
    testWidgets('renders new flip instruction text', (tester) async {
      final cam = _idleMock();
      await _triggerSideIntro(tester, cam);

      expect(find.text('Voltee el documento'), findsOneWidget);

      await _dispose(tester);
    });
  });

  group('FlipDocumentBanner — semantics', () {
    testWidgets('semantics label is present and non-empty', (tester) async {
      final cam = _idleMock();
      await _triggerSideIntro(tester, cam);

      final semantics = tester.getSemantics(find.text('Voltee el documento'));
      expect(semantics.label, isNotEmpty,
          reason: 'Expected non-empty semantics on text widget');

      await _dispose(tester);
    });
  });

  group('FlipDocumentBanner — AnimationController disposal', () {
    testWidgets('transientCallbackCount is 0 after full widget removal',
        (tester) async {
      final cam = _idleMock();
      await _triggerSideIntro(tester, cam);
      await tester.pump(const Duration(milliseconds: 50));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);

      expect(
        tester.binding.transientCallbackCount,
        equals(0),
        reason: 'All AnimationControllers should be disposed — no ticker leak',
      );
    });
  });

  group('FlipDocumentBanner — HapticFeedback', () {
    testWidgets('HapticFeedback.mediumImpact fires on banner mount',
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
      await _triggerSideIntro(tester, cam);
      await tester.pump();

      final vibrateCalls = hapticCalls.where(
        (c) => c.method == 'HapticFeedback.vibrate',
      );
      expect(vibrateCalls, isNotEmpty,
          reason:
              'HapticFeedback.mediumImpact should have triggered HapticFeedback.vibrate');

      await _dispose(tester);
    });
  });
}
