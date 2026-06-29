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

/// Runs the live front countdown ticker until [_captureFront] finishes and the
/// hunt machine advances out of the front phase. Mirrors the real per-frame
/// cadence so the post-await `advanceToWaitingBack` runs exactly as on device.
Future<void> _runFrontCountdown(
  WidgetTester tester,
  DniScannerState state,
) async {
  state.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
  for (var i = 0; i < 30; i++) {
    if (state.debugHuntPhase == HuntPhase.waitingBack ||
        state.debugHuntPhase == HuntPhase.done) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 110));
    await tester.pump();
  }
}

/// Drives the REAL textless-back chain a live device frame uses — feeds
/// quad-confirmed back frames through [HuntStateMachine.recordFrame] via
/// [debugProcessFrameForTest] so the machine re-emits backCaptureReady every
/// frame (as on device) and advances the ticker between frames. Crucially it
/// NEVER calls debugResetToScanning: the back must start its own countdown from
/// whatever capture state the front handoff left behind.
Future<void> _driveBackChain(
  WidgetTester tester,
  DniScannerState state, {
  int maxFrames = 80,
}) async {
  state.debugSetFramingValid(true);
  for (var frame = 0; frame < maxFrames; frame++) {
    if (state.debugHuntPhase == HuntPhase.done) break;
    state.debugProcessFrameForTest(
      detectedSide: DocumentSide.unknown,
      addedNewField: false,
      filledFields: 11,
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

void main() {
  late File capturedFile;

  setUpAll(() {
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(Offset.zero);
    registerFallbackValue(FocusMode.auto);
    registerFallbackValue(ExposureMode.auto);
  });

  setUp(() {
    capturedFile = File(
      '${Directory.systemTemp.path}/dni_handoff_${DateTime.now().microsecondsSinceEpoch}.jpg',
    )..writeAsBytesSync(Uint8List.fromList(List<int>.filled(64, 7)));
  });

  tearDown(() {
    if (capturedFile.existsSync()) capturedFile.deleteSync();
  });

  group('DniScanner two-sided front -> back handoff (#5535)', () {
    testWidgets(
      'after the front captures, the back countdown starts on its own and the '
      'back photo is taken without any manual capture-state reset',
      (tester) async {
        final cam = _idleMockCamera();
        var takePictureCalls = 0;
        when(() => cam.takePicture()).thenAnswer((_) async {
          takePictureCalls++;
          return XFile(capturedFile.path);
        });
        final key = GlobalKey<DniScannerState>();
        DniScanResult? completed;

        await tester.runAsync(() async {
          await tester.pumpWidget(
            _buildTwoSidedScanner(
              cam: cam,
              key: key,
              onScanComplete: (result) => completed = result,
            ),
          );
          await tester.pump();

          // 1) Real FRONT countdown to InFlight; _captureFront completes and
          // the hunt machine reaches waitingBack (the device handoff point).
          await _runFrontCountdown(tester, key.currentState!);

          expect(
            key.currentState!.debugHuntPhase,
            HuntPhase.waitingBack,
            reason: 'the front must capture and advance to the back phase',
          );
          expect(
            takePictureCalls,
            1,
            reason: 'exactly the front photo has been taken so far',
          );

          // THE BUG DISCRIMINATOR: once the front shutter is done and the
          // machine is in waitingBack, the leftover front DniCaptureInFlight
          // must already be cleared. On the device it stays InFlight here, so
          // every back frame early-returns in the _onCaptureReady guard and the
          // back countdown never starts (#5535).
          expect(
            key.currentState!.debugCaptureState,
            isNot(isA<DniCaptureInFlight>()),
            reason:
                'the front handoff must clear its InFlight state so the back '
                'guard can pass; it stays stuck InFlight on the device bug',
          );

          // 2) WITHOUT debugResetToScanning, feed real back frames. The machine
          // re-emits backCaptureReady every frame just like the device stream;
          // the back must now start its own countdown and capture.
          await _driveBackChain(tester, key.currentState!);
        });
        await tester.pump();

        // The back photo MUST be taken — a SECOND takePicture call.
        expect(
          takePictureCalls,
          greaterThanOrEqualTo(2),
          reason:
              'the back countdown must start after the front handoff and fire '
              'the shutter; the device bug left this at 1 forever',
        );

        // The whole scan finishes — only reachable if the back actually ran.
        expect(
          key.currentState!.debugHuntPhase,
          HuntPhase.done,
          reason: 'two-sided scan must reach done after the back captures',
        );
        expect(
          completed,
          isNotNull,
          reason: 'onScanComplete must fire once both sides are captured',
        );

        await _disposeWidget(tester);
      },
    );

    testWidgets(
      'the in-flight re-entry guard is preserved: a capture-ready frame '
      'arriving while the front shutter is still in flight does NOT fire a '
      'second takePicture',
      (tester) async {
        final cam = _idleMockCamera();
        var takePictureCalls = 0;
        // Hold the front shutter OPEN: takePicture never resolves while we
        // probe re-entry, pinning the scanner inside the live in-flight window.
        final shutter = Completer<XFile>();
        when(() => cam.takePicture()).thenAnswer((_) {
          takePictureCalls++;
          return shutter.future;
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

          // Drive the front countdown until the shutter fires (in-flight); the
          // Completer keeps takePicture pending so we stay mid-capture.
          key.currentState!
              .debugFeedCaptureReady(HuntSignal.frontCaptureReady);
          for (var i = 0; i < 30; i++) {
            if (key.currentState!.debugCaptureState is DniCaptureInFlight) {
              break;
            }
            await Future<void>.delayed(const Duration(milliseconds: 110));
            await tester.pump();
          }

          expect(
            key.currentState!.debugCaptureState,
            isA<DniCaptureInFlight>(),
            reason: 'the front dwell completed and the shutter is in flight',
          );
          expect(
            takePictureCalls,
            1,
            reason: 'the front shutter fired exactly once',
          );

          // A frame arrives DURING the live shutter. The InFlight guard must
          // block it — no second capture may start mid-shutter.
          key.currentState!
              .debugFeedCaptureReady(HuntSignal.frontCaptureReady);
          await tester.pump();
          key.currentState!.debugProcessFrameForTest(
            detectedSide: DocumentSide.unknown,
            addedNewField: false,
            filledFields: 11,
          );
          await tester.pump();

          expect(
            takePictureCalls,
            1,
            reason:
                'no second takePicture may fire while the front shutter is '
                'still in flight — the re-entry guard must hold',
          );

          // Release the shutter so the widget tears down cleanly.
          shutter.complete(XFile('/nonexistent/fake_front.jpg'));
          await tester.pump();
        });
        await tester.pump();

        await _disposeWidget(tester);
      },
    );
  });
}
