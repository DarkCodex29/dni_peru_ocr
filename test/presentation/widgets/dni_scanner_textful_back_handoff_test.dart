import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

class _MockCameraController extends Mock implements CameraController {}

class _PassQualityGate extends ImageQualityGate {
  @override
  Future<QualityCheckResult> validate(Uint8List bytes) async =>
      QualityCheckResult.pass;
}

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

Widget _buildTwoSidedScanner({
  required CameraController cam,
  required GlobalKey<DniScannerState> key,
  required void Function(DniScanResult) onScanComplete,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniScanner(
          key: key,
          controller: cam,
          autoCaptureMs: 1500,
          gracePeriodMs: 600,
          minStableFrames: 2,
          motionGate: _StillMotionGate(),
          imageQualityGate: _PassQualityGate(),
          onScanComplete: onScanComplete,
        ),
      ),
    ),
  );
}

/// A realistic Peru DNI FRONT OCR block: the title anchor plus the four minimal
/// fields. `DocumentSideDetector` reads it as front; the hunter fills the
/// minimal set, exactly as on device.
const _frontText = 'DOCUMENTO NACIONAL DE IDENTIDAD\n'
    'DNI 16793105\n'
    'PRIMER APELLIDO\nMUÑOZ\n'
    'SEGUNDO APELLIDO\nPEREZ\n'
    'PRE NOMBRES\nJUAN CARLOS';

/// A realistic textful Peru DNI BACK OCR block: the DNI number near the MRZ,
/// Grupo de Votación and an address — NO front title block, NO clean back
/// anchor. Through the real detector this resolves to `unknown` (#5499).
const _textfulBackText = 'Grupo de Votación 083966\n'
    'Dirección AMPLC. TUPAC AMARU SICUANI 215\n'
    'DNI 71542895\n'
    'I<PER7154289<<<<<<<<<<<<<<<';

void main() {
  setUpAll(() {
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(Offset.zero);
    registerFallbackValue(FocusMode.auto);
    registerFallbackValue(ExposureMode.auto);
  });

  group('DniScanner textful-back across handoff via the routed device path '
      '(#5562)', () {
    testWidgets(
      'after the front captures, a TEXTFUL back fed as REAL OCR text (detect() '
      'reads unknown, no quad) does NOT capture the front as the back — the '
      'device path runs through the coordinator with no pre-set side',
      (tester) async {
        final cam = _idleMockCamera();
        var takePictureCalls = 0;
        final frontFile = File(
          '${Directory.systemTemp.path}/dni_textful_${DateTime.now().microsecondsSinceEpoch}.jpg',
        )..writeAsBytesSync(Uint8List.fromList(List<int>.filled(64, 7)));
        addTearDown(() {
          if (frontFile.existsSync()) frontFile.deleteSync();
        });
        when(() => cam.takePicture()).thenAnswer((_) async {
          takePictureCalls++;
          return XFile(frontFile.path);
        });
        final key = GlobalKey<DniScannerState>();

        await tester.runAsync(() async {
          await tester.pumpWidget(
            _buildTwoSidedScanner(
              cam: cam,
              key: key,
              onScanComplete: (_) {},
            ),
          );
          await tester.pump();
          final state = key.currentState!;

          // PHASE 1 — drive the FRONT through the REAL routed path: real OCR
          // text -> coordinator.onFrame -> detect()==front -> latch + countdown
          // -> fire. Feed the front text on a real cadence until the front
          // shutter fires and the machine advances to the back phase.
          for (var i = 0; i < 60; i++) {
            if (state.debugHuntPhase == HuntPhase.waitingBack ||
                state.debugHuntPhase == HuntPhase.done) {
              break;
            }
            state.debugProcessTextForTest(_frontText);
            await Future<void>.delayed(const Duration(milliseconds: 60));
            await tester.pump();
          }

          expect(
            state.debugHuntPhase,
            HuntPhase.waitingBack,
            reason: 'the front must capture through the routed device path and '
                'advance to the back phase',
          );
          expect(takePictureCalls, 1,
              reason: 'exactly the front photo was taken');

          // PHASE 2 — the user has NOT flipped yet (or the front momentarily
          // reads unknown). The text-dense front in view yields no clean card
          // quad, so framing is invalid. Feed the TEXTFUL back string as REAL
          // OCR with NO quad. detect() returns unknown, the hunter adds no new
          // minimal field, so only cached front fields could latch. The routed
          // device path must NOT capture the front as the back.
          state.debugSetFramingValid(false);
          for (var i = 0; i < 20; i++) {
            if (state.debugHuntPhase == HuntPhase.done) break;
            state.debugProcessTextForTest(_textfulBackText);
            await Future<void>.delayed(const Duration(milliseconds: 60));
            await tester.pump();
          }

          expect(
            state.debugHuntPhase,
            HuntPhase.waitingBack,
            reason: 'a textful back reading unknown with no quad must NOT latch '
                'extractingBack from cached front fields — that is the '
                'front-as-back capture bug (#5562)',
          );
          expect(
            takePictureCalls,
            1,
            reason: 'no second (front-as-back) photo may be taken',
          );
        });
        await tester.pump();

        await _disposeWidget(tester);
      },
    );
  });
}
