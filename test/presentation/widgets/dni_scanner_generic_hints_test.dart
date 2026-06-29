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
  DniScanHints? scanHints,
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
            scanHints: scanHints ?? const DniScanHints(),
          ),
        ),
      ),
    );

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

/// Specific DNI field names (and their printed-label fragments) that must
/// NEVER appear in a bottom guidance hint. The side a field belongs to is not
/// knowable across DNI versions, so naming any field in a hint is an invalid
/// assumption (#5486).
const _forbiddenFieldTerms = <String>[
  'grupo de votación',
  'votación',
  'sufragio',
  'donación',
  'cuadrícula',
  'nombres',
  'apellidos',
  'fechas',
];

bool _containsForbiddenTerm(String hint) {
  final lower = hint.toLowerCase();
  return _forbiddenFieldTerms.any(lower.contains);
}

void main() {
  setUpAll(() {
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(Offset.zero);
    registerFallbackValue(FocusMode.auto);
    registerFallbackValue(ExposureMode.auto);
  });

  group('DniScanner bottom guidance never names a specific field (#5486)', () {
    for (final phase in const [
      HuntPhase.waitingFront,
      HuntPhase.extractingFront,
      HuntPhase.waitingBack,
      HuntPhase.extractingBack,
    ]) {
      testWidgets('phase ${phase.name} renders only generic guidance',
          (tester) async {
        final cam = _idleMock();
        await tester.pumpWidget(_buildScanner(cam, phase: phase));
        await tester.pump(const Duration(milliseconds: 50));

        final hintWidget =
            tester.widget<Text>(find.byKey(const Key('dni_scanner_hint')));
        final hint = hintWidget.data ?? '';

        expect(
          hint,
          isNotEmpty,
          reason: 'every scanning phase must surface a guidance hint',
        );
        expect(
          _containsForbiddenTerm(hint),
          isFalse,
          reason: 'phase ${phase.name} hint "$hint" names a specific field; '
              'bottom guidance must only guide the action, never a field',
        );

        await _dispose(tester);
      });
    }
  });

  group('DniScanHints default copy is generic and field-free (#5486)', () {
    test('no default hint in any phase names a specific field', () {
      const hints = DniScanHints();
      final all = [
        ...hints.waitingFront,
        ...hints.extractingFront,
        ...hints.waitingBack,
        ...hints.extractingBack,
      ];
      expect(all, isNotEmpty);
      for (final hint in all) {
        expect(
          _containsForbiddenTerm(hint),
          isFalse,
          reason: 'default hint "$hint" names a specific field',
        );
      }
    });
  });

  group('DniScanHints is configurable for a published library (#5486)', () {
    testWidgets('renders a consumer-provided front waiting hint', (tester) async {
      const custom = 'Place the front of your ID inside the frame';
      final cam = _idleMock();
      await tester.pumpWidget(
        _buildScanner(
          cam,
          phase: HuntPhase.waitingFront,
          scanHints: const DniScanHints(waitingFront: [custom]),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final hintWidget =
          tester.widget<Text>(find.byKey(const Key('dni_scanner_hint')));
      expect(hintWidget.data, custom);

      await _dispose(tester);
    });
  });
}
