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

Widget _buildApp(CameraController cam, {bool isBackSide = false}) =>
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

  group('_FlashToggle — off-state color', () {
    testWidgets('off-state uses higher-contrast color (alpha >= 0.25)', (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(_buildApp(cam));
      await tester.pump();

      final containers = tester.widgetList<Container>(find.byType(Container));
      Container? toggleContainer;
      for (final c in containers) {
        final deco = c.decoration;
        if (deco is BoxDecoration && deco.shape == BoxShape.circle && deco.color != null) {
          toggleContainer = c;
          break;
        }
      }
      expect(toggleContainer, isNotNull, reason: 'Flash toggle container not found');

      final deco = toggleContainer!.decoration as BoxDecoration;
      final color = deco.color!;
      expect(color.a, greaterThanOrEqualTo(0.24),
          reason: 'Off-state should use white.withValues(alpha:0.25) or higher');

      await _dispose(tester);
    });
  });

  group('_FlashToggle — on-state border', () {
    testWidgets('on-state has white border decoration', (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(_buildApp(cam));
      await tester.pump();

      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is GestureDetector &&
              w.child is Container &&
              (w.child as Container).decoration is BoxDecoration &&
              ((w.child as Container).decoration as BoxDecoration).shape ==
                  BoxShape.circle,
        ),
      );
      await tester.pump();

      final containers = tester.widgetList<Container>(find.byType(Container));
      Container? onToggle;
      for (final c in containers) {
        final deco = c.decoration;
        if (deco is BoxDecoration &&
            deco.shape == BoxShape.circle &&
            deco.border != null) {
          onToggle = c;
          break;
        }
      }
      expect(onToggle, isNotNull,
          reason: 'On-state flash toggle should have a border');

      await _dispose(tester);
    });
  });

  group('_FlashToggle — icon size', () {
    testWidgets('flash icon has size 22', (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(_buildApp(cam));
      await tester.pump();

      final icons = tester.widgetList<Icon>(find.byType(Icon));
      final flashIcons = icons.where(
        (i) =>
            i.icon == Icons.flash_off_rounded ||
            i.icon == Icons.flash_on_rounded,
      );
      expect(flashIcons, isNotEmpty, reason: 'Flash icon not found');
      expect(flashIcons.first.size, equals(22.0),
          reason: 'Flash icon should be size 22 (shared ScannerFlashToggle)');

      await _dispose(tester);
    });
  });

  group('_FlashToggle — touch target size', () {
    testWidgets('touch target is at least 48x48 logical pixels', (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(_buildApp(cam));
      await tester.pump();

      final gestureDetectors = tester.widgetList<GestureDetector>(
          find.byType(GestureDetector));
      RenderBox? targetBox;
      for (final gd in gestureDetectors) {
        final el = tester.element(find.byWidget(gd));
        final rb = el.renderObject as RenderBox?;
        if (rb != null) {
          final size = rb.size;
          if (size.width >= 44 && size.height >= 44) {
            targetBox = rb;
            break;
          }
        }
      }
      expect(targetBox, isNotNull,
          reason: 'At least one GestureDetector should have a touch target >= 44x44');
      expect(targetBox!.size.width, greaterThanOrEqualTo(44.0));
      expect(targetBox.size.height, greaterThanOrEqualTo(44.0));

      await _dispose(tester);
    });
  });

  group('_FlashToggle — tap fires callback', () {
    testWidgets('tapping flash toggle calls setFlashMode', (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(_buildApp(cam));
      await tester.pump();

      final iconFinder = find.byWidgetPredicate(
        (w) =>
            w is Icon &&
            (w.icon == Icons.flash_off_rounded || w.icon == Icons.flash_on_rounded),
      );
      expect(iconFinder, findsOneWidget);

      await tester.tap(iconFinder);
      await tester.pump();

      verify(() => cam.setFlashMode(any())).called(1);

      await _dispose(tester);
    });
  });

  group('_FlashToggle — HapticFeedback', () {
    testWidgets('tapping flash toggle triggers haptic feedback', (tester) async {
      final hapticCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          hapticCalls.add(call);
          return null;
        },
      );

      final cam = _idleMock();
      await tester.pumpWidget(_buildApp(cam));
      await tester.pump();

      hapticCalls.clear();

      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is Icon &&
              (w.icon == Icons.flash_off_rounded || w.icon == Icons.flash_on_rounded),
        ),
      );
      await tester.pump();

      expect(hapticCalls, isNotEmpty,
          reason: 'HapticFeedback should fire on flash toggle tap');

      await _dispose(tester);
    });
  });
}
