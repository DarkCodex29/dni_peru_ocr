import 'dart:async';

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

Widget _buildScanner({
  required CameraController cam,
  required GlobalKey<DniScannerState> key,
  required bool isBackSide,
  int idleFramesBeforeCapture = 18,
  int backQuadDwellFrames = 6,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniScanner(
          key: key,
          controller: cam,
          isBackSide: isBackSide,
          idleFramesBeforeCapture: idleFramesBeforeCapture,
          backQuadDwellFrames: backQuadDwellFrames,
          autoCaptureMs: 1500,
          gracePeriodMs: 600,
          minStableFrames: 2,
          motionGate: _StillMotionGate(),
          onSideCaptured: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(Offset.zero);
    registerFallbackValue(FocusMode.auto);
    registerFallbackValue(ExposureMode.auto);
  });

  group('DniScanner quad framing gate wiring', () {
    testWidgets('valid quad framing allows front countdown to reach capture',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      key.currentState!.debugSetFramingValid(true);
      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      await tester.pump(const Duration(milliseconds: 1600));

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets('invalid quad framing does NOT block front countdown entry '
        '(front readiness is OCR-sourced, not quad-gated) (#5543)',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      // The text-dense front rarely yields a clean quad. Because the front
      // countdown is driven by OCR readiness (which already implies a framed
      // document), the degrade-closed quad must NOT veto it: the countdown
      // starts and the shutter fires on completion.
      key.currentState!.debugSetFramingValid(false);
      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      await tester.pump(const Duration(milliseconds: 1600));

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets('valid quad framing auto-captures the BACK side via edges',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: true),
      );
      await tester.pump();

      key.currentState!.debugSetFramingValid(true);
      key.currentState!.debugFeedCaptureReady(HuntSignal.backCaptureReady);
      await tester.pump();

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      await tester.pump(const Duration(milliseconds: 1600));

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets('quad loss beyond grace during the BACK countdown resets to '
        'scanning (the back keeps the strict quad gate)', (tester) async {
      // The strict quad gate lives on the BACK path: the quad is the back's
      // only readiness proof, so a sustained quad loss beyond the grace window
      // must reset its countdown. The FRONT countdown is OCR-driven and is
      // proven NOT to reset on quad loss by the #5543 group below.
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          isBackSide: true,
          backQuadDwellFrames: 3,
        ),
      );
      await tester.pump();

      key.currentState!.debugSetFramingValid(true);
      DniCaptureState? state;
      for (var i = 0; i < 6; i++) {
        state = key.currentState!.debugProcessFrameForTest(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 0,
        );
        await tester.pump();
      }
      expect(state, isA<DniCaptureCountingDown>());

      key.currentState!.debugSetFramingValid(false);
      await tester.pump(const Duration(milliseconds: 800));

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureScanning>(),
      );
      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });

    testWidgets('framing defaults to valid before any quad result (fallback '
        'degrades to OCR-block, capture still works)', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      // No debugSetFramingValid call: the default must be valid so a fallback
      // detector (no quad signal) never blocks capture.
      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );
      await _disposeWidget(tester);
    });

    testWidgets('valid quad framing cannot override a wrong-side OCR block '
        '(no wrong-side capture)', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      // Quad reports a perfectly framed document, but the side gate (OCR-block
      // derived) says this frame is not captureable for the expected side.
      key.currentState!.debugSetFramingValid(true);
      key.currentState!.debugSetFrameCaptureable(false);
      key.currentState!.debugResetToScanning();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1600));

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureScanning>(),
      );
      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });
  });

  // The FRONT readiness is OCR-sourced (frontCaptureReady comes from field
  // stability, independent of the quad), so once the front countdown is running
  // the document is already OCR-confirmed framed. The text-dense Peru DNI front
  // held still makes the native quad find text edges, not a clean 4-corner card
  // boundary, so framingValid frequently reads FALSE at the completion tick.
  // The front shutter must NOT be vetoed by that degrade-closed quad — it fired
  // on completion before commit 08a32e4 wired the live quad into the front
  // gate. The BACK has no OCR readiness signal, so the quad stays its only
  // proof and keeps a strict gate. These tests cover the at-completion device
  // case the entry-only tests above never exercised (#5543).
  group('front fires on countdown completion without a clean quad (#5543)', () {
    testWidgets('FRONT held still: quad invalid AT completion still fires the '
        'shutter (OCR readiness already implies a framed document)',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      // The front countdown starts on OCR readiness with a momentarily clean
      // quad, then the text-dense card held still degrades the quad to invalid
      // right as the dwell completes.
      key.currentState!.debugSetFramingValid(true);
      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      key.currentState!.debugSetFramingValid(false);
      await tester.pump(const Duration(milliseconds: 1600));

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets('FRONT entry with no clean quad still starts and completes the '
        'countdown (front never requires a quad)', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      // The text-dense front never yields a clean quad: framing stays invalid
      // from entry through completion. The OCR-confirmed front must still fire.
      key.currentState!.debugSetFramingValid(false);
      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      await tester.pump(const Duration(milliseconds: 1600));

      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets('SAFETY: the BACK keeps a strict quad gate — quad invalid AT '
        'completion does NOT fire (the quad is the back\'s only readiness)',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          isBackSide: true,
          backQuadDwellFrames: 3,
        ),
      );
      await tester.pump();

      // A sustained valid quad latches the back into extractingBack and starts
      // the back countdown through the REAL dispatch chain.
      key.currentState!.debugSetFramingValid(true);
      DniCaptureState? state;
      for (var i = 0; i < 6; i++) {
        state = key.currentState!.debugProcessFrameForTest(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 0,
        );
        await tester.pump();
      }
      expect(state, isA<DniCaptureCountingDown>());

      // The quad is lost right as the dwell completes. The back has no OCR
      // readiness to fall back on, so the strict quad gate must veto the
      // shutter — unlike the front, the back stays blocked.
      key.currentState!.debugSetFramingValid(false);
      await tester.pump(const Duration(milliseconds: 1600));

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureScanning>(),
      );
      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });

    testWidgets('SAFETY (#5540): sustained document removal beyond grace still '
        'aborts the FRONT countdown (no capture of empty air)', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, isBackSide: false),
      );
      await tester.pump();

      key.currentState!.debugSetFramingValid(true);
      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      // The DNI leaves the frame: OCR goes empty so the frame is no longer
      // captureable. Degrade-open framing must NOT mask a removed document —
      // the capture-eligibility (OCR) gate still aborts past the grace window.
      key.currentState!.debugSetFrameCaptureable(false);
      await tester.pump(const Duration(milliseconds: 1600));

      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureScanning>(),
      );
      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });
  });

  // These tests drive the REAL record-and-dispatch chain the live frame
  // processing uses (DocumentSideDetector-derived side + field count + the
  // quad framing flag fed into HuntStateMachine.recordFrame and the signal
  // dispatch into _onCaptureReady). They deliberately do NOT inject
  // backCaptureReady via debugFeedCaptureReady — that injects the very signal
  // the device never produces on a textless back and hid this bug repeatedly
  // (#5461/#5491/#5498/#5517). Here the state machine must EMIT the signal
  // from realistic textless-back inputs.
  group('quad-driven back trigger through the real dispatch chain (#5517)', () {
    testWidgets('a textless back (filled < floor, side-safe) with a sustained '
        'valid quad starts the back countdown and auto-captures by edges',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          isBackSide: true,
          backQuadDwellFrames: 3,
        ),
      );
      await tester.pump();

      // The quad detector reports a well-framed document quad on the back.
      key.currentState!.debugSetFramingValid(true);

      // Feed realistic textless-back frames through the REAL dispatch: the
      // side detector resolves the sparse back to `unknown` (not front) and no
      // OCR fields accrue (filled = 0, below the floor of 4). With no quad
      // this would never start a countdown — today the back stalls.
      DniCaptureState? state;
      for (var i = 0; i < 6; i++) {
        state = key.currentState!.debugProcessFrameForTest(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 0,
        );
        await tester.pump();
      }
      expect(state, isA<DniCaptureCountingDown>());

      await tester.pump(const Duration(milliseconds: 1600));
      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets('SAFETY: a well-framed FRONT held during the back phase '
        '(detectedSide == front + valid quad) never starts the back countdown',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          isBackSide: true,
          idleFramesBeforeCapture: 3,
        ),
      );
      await tester.pump();

      // A perfectly framed FRONT is shown while the back is expected: the side
      // detector reports `front`. A confident quad must NOT override the side
      // guard — no wrong-side capture.
      key.currentState!.debugSetFramingValid(true);

      DniCaptureState? state;
      for (var i = 0; i < 8; i++) {
        state = key.currentState!.debugProcessFrameForTest(
          detectedSide: DocumentSide.front,
          addedNewField: false,
          filledFields: 0,
        );
        await tester.pump();
      }
      expect(state, isA<DniCaptureScanning>());

      await tester.pump(const Duration(milliseconds: 1600));
      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });

    testWidgets('DWELL: a single valid-quad back frame then quad loss does NOT '
        'auto-capture (the quad must be sustained, not a blip)',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          isBackSide: true,
          idleFramesBeforeCapture: 3,
        ),
      );
      await tester.pump();

      // One valid-quad frame latches the back...
      key.currentState!.debugSetFramingValid(true);
      key.currentState!.debugProcessFrameForTest(
        detectedSide: DocumentSide.unknown,
        addedNewField: false,
        filledFields: 0,
      );
      await tester.pump();

      // ...but the quad is then lost. Without a sustained quad and with no OCR
      // fields, the stability dwell must not reach a capture.
      key.currentState!.debugSetFramingValid(false);
      DniCaptureState? state;
      for (var i = 0; i < 6; i++) {
        state = key.currentState!.debugProcessFrameForTest(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 0,
        );
        await tester.pump();
      }
      expect(state, isA<DniCaptureScanning>());

      await tester.pump(const Duration(milliseconds: 1600));
      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });
  });

  // These tests drive the REAL empty-OCR branch of _processImage through a seam
  // that runs the same routing decision a textless device frame triggers. They
  // do NOT pre-resolve the side/field count and hand them to _recordAndDispatch
  // (the prior real-chain tests did, so they never proved that an EMPTY OCR
  // frame routes to the trigger at all). Here the seam reproduces the live
  // empty-OCR branch: text.isEmpty -> resolveEmptyOcrRoute -> dispatch or skip.
  // This is the layer the device log (#5523) fingered: many "frame skipped —
  // empty OCR" and zero back trigger.
  group('empty-OCR back frame drives the real trigger routing (#5523)', () {
    testWidgets('a textless back (empty OCR) with a sustained valid quad drives '
        'the back countdown without any OCR fields', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          isBackSide: true,
          backQuadDwellFrames: 3,
        ),
      );
      await tester.pump();

      key.currentState!.debugSetFramingValid(true);

      DniCaptureState? state;
      for (var i = 0; i < 6; i++) {
        state = key.currentState!.debugProcessEmptyOcrForTest();
        await tester.pump();
      }
      expect(state, isA<DniCaptureCountingDown>());

      await tester.pump(const Duration(milliseconds: 1600));
      verify(() => cam.takePicture()).called(1);
      await _disposeWidget(tester);
    });

    testWidgets('SAFETY: an empty-OCR frame with NO valid quad skips and never '
        'starts a countdown (a blank frame is not a document)', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          isBackSide: true,
          idleFramesBeforeCapture: 3,
        ),
      );
      await tester.pump();

      key.currentState!.debugSetFramingValid(false);

      DniCaptureState? state;
      for (var i = 0; i < 8; i++) {
        state = key.currentState!.debugProcessEmptyOcrForTest();
        await tester.pump();
      }
      expect(state, isA<DniCaptureScanning>());

      await tester.pump(const Duration(milliseconds: 1600));
      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });

    testWidgets('SAFETY: an empty-OCR frame on the FRONT phase with a valid '
        'quad skips (front stays OCR-triggered, no wrong-side trigger)',
        (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          isBackSide: false,
          idleFramesBeforeCapture: 3,
        ),
      );
      await tester.pump();

      key.currentState!.debugSetFramingValid(true);

      DniCaptureState? state;
      for (var i = 0; i < 8; i++) {
        state = key.currentState!.debugProcessEmptyOcrForTest();
        await tester.pump();
      }
      expect(state, isA<DniCaptureScanning>());

      await tester.pump(const Duration(milliseconds: 1600));
      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });

    testWidgets('DWELL: a single empty-OCR valid-quad frame then quad loss does '
        'NOT auto-capture (the quad must be sustained)', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          isBackSide: true,
          idleFramesBeforeCapture: 3,
        ),
      );
      await tester.pump();

      key.currentState!.debugSetFramingValid(true);
      key.currentState!.debugProcessEmptyOcrForTest();
      await tester.pump();

      key.currentState!.debugSetFramingValid(false);
      DniCaptureState? state;
      for (var i = 0; i < 6; i++) {
        state = key.currentState!.debugProcessEmptyOcrForTest();
        await tester.pump();
      }
      expect(state, isA<DniCaptureScanning>());

      await tester.pump(const Duration(milliseconds: 1600));
      verifyNever(() => cam.takePicture());
      await _disposeWidget(tester);
    });
  });
}
