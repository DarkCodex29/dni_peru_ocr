import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

class _MockCameraController extends Mock implements CameraController {}

class _FakeMotionGate implements MotionStillnessGate {
  _FakeMotionGate(this._isStill);

  final bool _isStill;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  bool get isStill => _isStill;

  @override
  Stream<bool> watchStillness() => _controller.stream;

  @override
  void dispose() {
    unawaited(_controller.close());
  }
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
  required MotionStillnessGate motionGate,
  bool? isBackSide = false,
  DniScanHints scanHints = const DniScanHints(),
  int autoCaptureMs = 1500,
  int gracePeriodMs = 600,
  int minStableFrames = 2,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniScanner(
          key: key,
          controller: cam,
          isBackSide: isBackSide,
          autoCaptureMs: autoCaptureMs,
          gracePeriodMs: gracePeriodMs,
          minStableFrames: minStableFrames,
          motionGate: motionGate,
          scanHints: scanHints,
          onSideCaptured: isBackSide != null ? (_) {} : null,
          onScanComplete: isBackSide == null ? (_) {} : null,
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

  const absentBannerKey = Key('dni_scanner_document_absent_banner');

  group('DniScanner cancels the countdown when the document is removed (#5540)',
      () {
    testWidgets(
        'document removed (OCR goes empty) for the full dwell resets the front '
        'countdown and does NOT fire the shutter', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, motionGate: gate),
      );
      await tester.pump();

      // A real countdown is running (the document was framed + capture-ready).
      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      // The user REMOVES the DNI. The front shutter is NOT quad-gated (#5543):
      // its framing degrades open because the text-dense card never yields a
      // clean quad. The real removal detector on the front is OCR going empty,
      // which drops capture eligibility — that gate must abort the count past
      // the grace window so the front never captures empty air (#5540). The
      // quad-only removal of the textless BACK is covered by its own test.
      key.currentState!.debugSetFrameCaptureable(false);
      await tester.pump(const Duration(milliseconds: 1600));

      verifyNever(() => cam.takePicture());
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureScanning>(),
        reason: 'removing the document mid-count must reset to scanning, not '
            'capture empty air',
      );

      await _disposeWidget(tester);
    });

    testWidgets(
        'a one-frame framing blip within the grace window does NOT reset the '
        'countdown (preserves #5504/#5532 hysteresis)', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_front.jpg'));
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, motionGate: gate),
      );
      await tester.pump();

      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      // A brief flicker: framing drops for a single sub-grace window then
      // recovers. The countdown must survive and still fire.
      await tester.pump(const Duration(milliseconds: 200));
      key.currentState!.debugSetFramingValid(false);
      await tester.pump(const Duration(milliseconds: 100));
      key.currentState!.debugSetFramingValid(true);
      await tester.pump(const Duration(milliseconds: 1600));

      verify(() => cam.takePicture()).called(1);

      await _disposeWidget(tester);
    });

    testWidgets(
        'the back countdown also cancels when the document is removed '
        '(front + back symmetry)', (tester) async {
      final cam = _idleMockCamera();
      when(() => cam.takePicture())
          .thenAnswer((_) async => XFile('/nonexistent/fake_back.jpg'));
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          motionGate: gate,
          isBackSide: true,
        ),
      );
      await tester.pump();

      key.currentState!.debugFeedCaptureReady(HuntSignal.backCaptureReady);
      await tester.pump();
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
      );

      key.currentState!.debugSetFramingValid(false);
      await tester.pump(const Duration(milliseconds: 1600));

      verifyNever(() => cam.takePicture());
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureScanning>(),
      );

      await _disposeWidget(tester);
    });
  });

  group('DniScanner top banner warns when no document is detected (#5540)', () {
    testWidgets(
        'shows the default neutral-Spanish warning once the document is absent',
        (tester) async {
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, motionGate: gate),
      );
      await tester.pump();

      // No document in view: presence is coordinator-owned now (PR5), so drive
      // the single presence source to absent.
      key.currentState!.debugSetDocumentPresent(false);
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        find.byKey(absentBannerKey),
        findsOneWidget,
        reason: 'the top banner must surface a no-document warning',
      );
      expect(find.text('No se detecta el documento'), findsWidgets);

      await _disposeWidget(tester);
    });

    testWidgets('renders a configurable override warning string',
        (tester) async {
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildScanner(
          cam: cam,
          key: key,
          motionGate: gate,
          scanHints: const DniScanHints(documentAbsent: 'Coloca tu DNI'),
        ),
      );
      await tester.pump();

      key.currentState!.debugSetDocumentPresent(false);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Coloca tu DNI'), findsWidgets);
      expect(
        find.text('No se detecta el documento'),
        findsNothing,
        reason: 'the configurable override must replace the default copy',
      );

      await _disposeWidget(tester);
    });

    testWidgets(
        'the warning banner is hidden (opacity 0) while the document is present',
        (tester) async {
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();
      final gate = _FakeMotionGate(true);

      await tester.pumpWidget(
        _buildScanner(cam: cam, key: key, motionGate: gate),
      );
      await tester.pump();

      // Document present (coordinator-owned presence, PR5). The banner must be
      // collapsed so the warning never shows when there is nothing wrong.
      key.currentState!.debugSetDocumentPresent(true);
      await tester.pump(const Duration(milliseconds: 350));

      final bannerFinder = find.ancestor(
        of: find.byKey(const Key('dni_scanner_document_absent_banner')),
        matching: find.byType(AnimatedOpacity),
      );
      final opacity = tester.widget<AnimatedOpacity>(bannerFinder);
      expect(
        opacity.opacity,
        0.0,
        reason: 'the no-document banner must be collapsed when a document is '
            'present',
      );

      await _disposeWidget(tester);
    });
  });
}
