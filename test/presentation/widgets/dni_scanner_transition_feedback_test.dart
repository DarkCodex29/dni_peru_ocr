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

Widget _buildScanner(
  CameraController cam, {
  required HuntPhase phase,
  String? flipDocumentText,
}) =>
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
            flipDocumentText: flipDocumentText ?? 'Voltea tu DNI',
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

  const successKey = Key('dni_scanner_transition_success_check');

  group('DniScanner front-to-back transition feedback', () {
    testWidgets(
        'shows the default Spanish flip guidance WITHOUT any success check '
        'while waiting for the back side', (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(
        _buildScanner(cam, phase: HuntPhase.waitingBack),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.text('Voltea tu DNI'),
        findsWidgets,
        reason: 'the default flip guidance must be the neutral Spanish copy',
      );
      expect(
        find.byKey(successKey),
        findsNothing,
        reason: 'the green success check was removed; the flip guidance must '
            'stand alone so the front-to-back transition feels continuous',
      );

      await _dispose(tester);
    });

    testWidgets(
        'renders a CONSUMER-PROVIDED flip guidance string instead of the '
        'default when flipDocumentText is set', (tester) async {
      const custom = 'Flip your ID card now';
      final cam = _idleMock();
      await tester.pumpWidget(
        _buildScanner(
          cam,
          phase: HuntPhase.waitingBack,
          flipDocumentText: custom,
        ),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.text(custom),
        findsWidgets,
        reason: 'the configurable parameter must override the default copy '
            'for a published library',
      );
      expect(
        find.text('Voltea tu DNI'),
        findsNothing,
        reason: 'the default copy must not leak when a custom string is given',
      );

      await _dispose(tester);
    });

    testWidgets(
        'the removed success check never reappears before any capture '
        '(front waiting phase)', (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(
        _buildScanner(cam, phase: HuntPhase.waitingFront),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.byKey(successKey),
        findsNothing,
        reason: 'the success check was removed and must not reappear on the '
            'front waiting phase',
      );

      await _dispose(tester);
    });

    testWidgets(
        'the removed success check never reappears once the back is actively '
        'scanning (extractingBack phase)', (tester) async {
      final cam = _idleMock();
      await tester.pumpWidget(
        _buildScanner(cam, phase: HuntPhase.extractingBack),
      );
      await tester.pump(const Duration(milliseconds: 350));

      expect(
        find.byKey(successKey),
        findsNothing,
        reason: 'the success check was removed and must not reappear when back '
            'scanning is active',
      );

      await _dispose(tester);
    });
  });
}
