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
CameraValue _initializedCameraValue() => CameraValue(
  isInitialized: true,
  previewSize: const Size(640, 480),
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
  description: const CameraDescription(
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

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeXFile());
  });

  group('DniCameraMask widget — controller wire-up', () {
    testWidgets(
      'renders without throwing when camera is initialized',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        expect(find.byType(DniCameraMask), findsOneWidget);
      },
    );

    testWidgets(
      'exposes captureController — the internal DniCameraController',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        // The state must expose `captureController` as a DniCameraController
        // so integration tests can drive state transitions without bypassing
        // the public widget API.
        final maskState =
            tester.state(find.byType(DniCameraMask)) as dynamic;
        final controller = maskState.captureController as DniCameraController;
        expect(controller, isNotNull);
      },
    );

    testWidgets(
      'captureState transitions to InFlight on captureManually()',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        final maskState =
            tester.state(find.byType(DniCameraMask)) as dynamic;
        final controller = maskState.captureController as DniCameraController;

        controller.captureManually();
        await tester.pump();

        expect(controller.captureState.value, isA<DniCaptureInFlight>());
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

        // Either the spinner or the check-mark icon appear for loading state.
        expect(
          find.byWidgetPredicate(
            (w) => w is CircularProgressIndicator || w is Icon,
          ),
          findsWidgets,
        );
      },
    );

    testWidgets(
      'widget state does NOT have _perfectSince (removed — owned by orchestrator)',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        final maskState =
            tester.state(find.byType(DniCameraMask)) as dynamic;

        // Regression guard: perfectSince must be gone from the widget state.
        expect(
          () => maskState.perfectSince,
          throwsA(isA<NoSuchMethodError>()),
        );
      },
    );

    testWidgets(
      'widget state does NOT have _manualModeActive (removed — owned by orchestrator)',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        final maskState =
            tester.state(find.byType(DniCameraMask)) as dynamic;

        expect(
          () => maskState.manualModeActive,
          throwsA(isA<NoSuchMethodError>()),
        );
      },
    );

    testWidgets(
      'widget state does NOT have _capturing (removed — owned by controller)',
      (tester) async {
        final cam = _idleMockCamera();

        await tester.pumpWidget(_buildMask(cameraController: cam));
        await tester.pump();

        final maskState =
            tester.state(find.byType(DniCameraMask)) as dynamic;

        expect(
          () => maskState.capturing,
          throwsA(isA<NoSuchMethodError>()),
        );
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

        final maskState =
            tester.state(find.byType(DniCameraMask)) as dynamic;
        final controller = maskState.captureController as DniCameraController;

        expect(controller.telemetry.value, isA<DniTelemetry>());
        expect(controller.telemetry.value.stableFrames, 0);
      },
    );
  });
}
