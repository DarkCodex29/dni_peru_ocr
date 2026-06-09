// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

// ── Mocks ────────────────────────────────────────────────────────────────────

class _MockCameraController extends Mock implements CameraController {}

class _FakeXFile extends Fake implements XFile {}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Returns a [CameraValue] with [isInitialized]=true and no active stream.
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
  when(() => mock.takePicture()).thenAnswer(
    (_) async => XFile('/tmp/test_capture.jpg'),
  );
  when(() => mock.setFlashMode(any())).thenAnswer((_) async {});
  return mock;
}

/// Builds a [DniCameraMask] under test wrapped in a minimal app scaffold
/// and a [KycThemeProvider] with defaults.
Widget _buildMask({
  required CameraController cameraController,
  void Function(XFile, OcrConsensusResult?)? onValidCapture,
  bool isBackSide = false,
  bool isLoading = false,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniCameraMask(
          controller: cameraController,
          onValidCapture: onValidCapture ?? (_, __) {},
          isBackSide: isBackSide,
          isLoading: isLoading,
        ),
      ),
    ),
  );
}

/// Disposes the widget under test by replacing it with a [SizedBox] and
/// draining the event loop so [DetectorLifecycle.safeDispose]'s
/// [Future.delayed(Duration.zero)] timer completes before the test ends.
Future<void> _disposeWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  // Let the Duration.zero future in DetectorLifecycle.safeDispose fire.
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeXFile());
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(ImageFormatGroup.bgra8888);
  });

  group('DniCameraMask widget — controller wire-up', () {
    testWidgets(
      'renders without throwing when camera is initialized',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        expect(find.byType(DniCameraMask), findsOneWidget);

        await _disposeWidget(tester);
      },
    );

    testWidgets(
      'exposes captureController — the internal DniCameraController',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        final maskState = tester.state(find.byType(DniCameraMask)) as dynamic;
        final controller = maskState.captureController as DniCameraController;
        expect(controller, isNotNull);

        await _disposeWidget(tester);
      },
    );

    testWidgets(
      'captureState transitions to InFlight on captureManually()',
      (tester) async {
        final cam = _idleMockCamera();

        // Build the widget to establish layout (so _screenSize is set).
        await tester.pumpWidget(_buildMask(cameraController: cam));
        // Allow the layout to build once so LayoutBuilder fires.
        await tester.pump();

        final maskState = tester.state(find.byType(DniCameraMask)) as dynamic;
        final controller = maskState.captureController as DniCameraController;

        // Verify initial scanning state.
        expect(controller.captureState.value, isA<DniCaptureScanning>());

        // Trigger manual capture — state should transition to InFlight.
        controller.captureManually();

        // Drain the sync state update.
        expect(controller.captureState.value, isA<DniCaptureInFlight>());

        // Drain all async work: flash timer + takePicture + onCaptureDelivered.
        await tester.pump(
          const Duration(
            milliseconds: CameraOverlayTuning.captureFlashMs + 50,
          ),
        );
        await tester.pump(Duration.zero);

        await _disposeWidget(tester);
      },
    );

    testWidgets(
      'loading overlay shown when isLoading=true',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(
          _buildMask(cameraController: cam, isLoading: true),
        );
        await tester.pump();

        expect(
          find.byWidgetPredicate(
            (w) => w is CircularProgressIndicator || w is Icon,
          ),
          findsWidgets,
        );

        await _disposeWidget(tester);
      },
    );

    testWidgets(
      'widget state does NOT have _perfectSince (removed — owned by orchestrator)',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        final maskState = tester.state(find.byType(DniCameraMask)) as dynamic;

        // Regression guard: perfectSince must be gone from the widget state.
        expect(
          () => maskState.perfectSince,
          throwsA(isA<NoSuchMethodError>()),
        );

        await _disposeWidget(tester);
      },
    );

    testWidgets(
      'widget state does NOT have _manualModeActive (removed — owned by orchestrator)',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        final maskState = tester.state(find.byType(DniCameraMask)) as dynamic;

        expect(
          () => maskState.manualModeActive,
          throwsA(isA<NoSuchMethodError>()),
        );

        await _disposeWidget(tester);
      },
    );

    testWidgets(
      'widget state does NOT have _capturing (removed — owned by controller)',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        final maskState = tester.state(find.byType(DniCameraMask)) as dynamic;

        expect(
          () => maskState.capturing,
          throwsA(isA<NoSuchMethodError>()),
        );

        await _disposeWidget(tester);
      },
    );
  });

  group('DniCameraMask widget — telemetry', () {
    testWidgets(
      'telemetry observable available via controller with initial values',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        final maskState = tester.state(find.byType(DniCameraMask)) as dynamic;
        final controller = maskState.captureController as DniCameraController;

        // Telemetry is statically typed as DniTelemetry; assert real initial fields.
        expect(controller.telemetry.value.stableFrames, 0);
        expect(controller.telemetry.value.failingGate, isNull);

        await _disposeWidget(tester);
      },
    );
  });

  // ── E2E state lifecycle — front → back rebuild keeps controller in sync
  //
  // Flutter reuses the [State] instance when the host rebuilds the same
  // widget type at the same position in the tree with a different value
  // for one of its parameters. The `DniCameraMask` controller MUST follow
  // that rebuild: if the host swaps `isBackSide: false` → `isBackSide: true`,
  // the underlying [DniCameraController] flag must update so subsequent
  // captures emit the back-side consensus instead of being scrubbed by a
  // stale front-side flag.
  group('Widget E2E — front→back rebuild keeps controller in sync', () {
    testWidgets(
      'controller.isBackSide tracks widget.isBackSide across rebuilds',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        final state = tester.state(find.byType(DniCameraMask)) as dynamic;
        final controller = state.captureController as DniCameraController;
        expect(
          controller.isBackSide,
          isFalse,
          reason: 'fresh-mounted front-side widget',
        );

        // Re-pump the same widget tree shape with `isBackSide: true`.
        // Flutter reuses the State; `didUpdateWidget` must propagate the
        // flag to the controller via `onSideChanged`.
        await tester.pumpWidget(
          _buildMask(cameraController: cam, isBackSide: true),
        );
        await tester.pump();
        expect(
          controller.isBackSide,
          isTrue,
          reason: 'controller flag must follow widget.isBackSide rebuild',
        );

        await _disposeWidget(tester);
      },
    );
  });
}
