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
  int manualFallbackMs = CameraOverlayTuning.manualFallbackMs,
  bool? isBackSide,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniScanner(
          key: key,
          controller: cam,
          isBackSide: isBackSide,
          manualFallbackMs: manualFallbackMs,
          motionGate: _StillMotionGate(),
          onScanComplete: isBackSide == null ? (_) {} : null,
          onSideCaptured: isBackSide != null ? (_) {} : null,
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

  group('DniScanner manual fallback', () {
    testWidgets(
        'default (~15s named constant) fallback activates manual mode and '
        'shows the button when no auto-capture is in progress (#5536)',
        (tester) async {
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();

      // Uses the library default (CameraOverlayTuning.manualFallbackMs ~15s),
      // raised from the prior 30s and made the named, host-tunable knob (#5536).
      await tester.pumpWidget(_buildScanner(cam: cam, key: key));
      await tester.pump();

      expect(key.currentState!.debugManualModeActive, isFalse);
      expect(
        find.byKey(const Key('dni_scanner_manual_capture')),
        findsNothing,
      );

      await tester.pump(
        const Duration(milliseconds: CameraOverlayTuning.manualFallbackMs),
      );
      await tester.pump();

      expect(key.currentState!.debugManualModeActive, isTrue);
      expect(
        find.byKey(const Key('dni_scanner_manual_capture')),
        findsOneWidget,
      );

      await _disposeWidget(tester);
    });

    testWidgets('manual mode persists across a scanning reset',
        (tester) async {
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(_buildScanner(cam: cam, key: key));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: CameraOverlayTuning.manualFallbackMs));
      await tester.pump();
      expect(key.currentState!.debugManualModeActive, isTrue);

      key.currentState!.debugResetToScanning();
      await tester.pump();

      expect(key.currentState!.debugManualModeActive, isTrue);

      await _disposeWidget(tester);
    });

    testWidgets('manual mode clears on side toggle', (tester) async {
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(_buildScanner(cam: cam, key: key));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: CameraOverlayTuning.manualFallbackMs));
      await tester.pump();
      expect(key.currentState!.debugManualModeActive, isTrue);

      key.currentState!.debugTriggerSideToggle();
      await tester.pump();

      expect(key.currentState!.debugManualModeActive, isFalse);

      await _disposeWidget(tester);
    });

    testWidgets(
        'manual button is HIDDEN while an auto-capture countdown is active '
        'even after manual mode is flagged (#5536)', (tester) async {
      // Device truth (#5536): the manual-fallback flag flips true in parallel
      // while the working auto-capture is still counting down, surfacing the
      // button too soon. The button must be withheld while the 3-2-1 runs.
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(_buildScanner(cam: cam, key: key));
      await tester.pump();

      // The fallback flag is set (as the early recoverManual escape / timer
      // would), AND a real auto-capture countdown is running concurrently.
      await tester.pump(const Duration(milliseconds: CameraOverlayTuning.manualFallbackMs));
      await tester.pump();
      expect(key.currentState!.debugManualModeActive, isTrue);

      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      expect(
        key.currentState!.debugCaptureState,
        isA<DniCaptureCountingDown>(),
        reason: 'precondition: an auto-capture countdown must be live',
      );

      expect(
        find.byKey(const Key('dni_scanner_manual_capture')),
        findsNothing,
        reason: 'the manual button must not compete with a live 3-2-1 '
            'auto-capture countdown',
      );

      await _disposeWidget(tester);
    });

    testWidgets(
        'manual button reappears as a genuine fallback once the countdown '
        'ends with manual mode still flagged (#5536)', (tester) async {
      // The gate must not destroy the fallback: once the auto-capture is no
      // longer in progress, the flagged manual affordance returns.
      final cam = _idleMockCamera();
      final key = GlobalKey<DniScannerState>();

      await tester.pumpWidget(_buildScanner(cam: cam, key: key));
      await tester.pump();

      await tester.pump(const Duration(milliseconds: CameraOverlayTuning.manualFallbackMs));
      await tester.pump();
      key.currentState!.debugFeedCaptureReady(HuntSignal.frontCaptureReady);
      await tester.pump();
      expect(
        find.byKey(const Key('dni_scanner_manual_capture')),
        findsNothing,
      );

      // Countdown collapses back to scanning (auto-capture stopped making
      // progress); manual mode is still flagged, so the fallback returns.
      key.currentState!.debugResetToScanning();
      await tester.pump();
      expect(key.currentState!.debugManualModeActive, isTrue);
      expect(key.currentState!.debugCaptureState, isA<DniCaptureScanning>());

      expect(
        find.byKey(const Key('dni_scanner_manual_capture')),
        findsOneWidget,
        reason: 'the manual fallback must still appear when auto-capture is '
            'not in progress',
      );

      await _disposeWidget(tester);
    });
  });
}
