// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

class _MockCameraController extends Mock implements CameraController {}

class _FakeXFile extends Fake implements XFile {}

class _FakeLookupService implements DniLookupService {
  _FakeLookupService(this._result);
  final DniLookupResult _result;

  @override
  Future<DniLookupResult> lookup(String dni) async => _result;
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
  when(() => mock.takePicture()).thenAnswer(
    (_) async => XFile('/tmp/test_capture.jpg'),
  );
  when(() => mock.setFlashMode(any())).thenAnswer((_) async {});
  return mock;
}

Widget _buildMask({
  required CameraController cameraController,
  DniLookupService? lookupService,
  void Function(DniData)? onDniReady,
  void Function(XFile, OcrConsensusResult?)? onValidCapture,
  bool isBackSide = true,
}) {
  return MaterialApp(
    home: KycThemeProvider(
      theme: KycTheme.defaults(),
      child: Scaffold(
        body: DniCameraMask(
          controller: cameraController,
          onValidCapture: onValidCapture ?? (_, __) {},
          isBackSide: isBackSide,
          lookupService: lookupService,
          onDniReady: onDniReady,
        ),
      ),
    ),
  );
}

Future<void> _disposeWidget(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

OcrExtractedFields _mrzFields({String dni = '71542895'}) {
  final fields = OcrExtractedFields()
    ..documentNumber = dni
    ..firstName = 'JOSE'
    ..lastName = 'MORENO'
    ..secondLastName = 'ALEMAN'
    ..dateOfBirth = '01/09/1994'
    ..expirationDate = '19/02/2028';
  fields.fromMrzForTest = true;
  return fields;
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeXFile());
    registerFallbackValue(FlashMode.off);
    registerFallbackValue(ImageFormatGroup.bgra8888);
  });

  group('DniCameraMask — lookupService + onDniReady forwarding', () {
    testWidgets(
      'controller receives lookupService and fires onDniReady on consensus',
      (tester) async {
        final completer = Completer<DniData>();
        final service = _FakeLookupService(
          const DniLookupSuccess(
            DniData(
              dni: '71542895',
              nombres: 'JOSE',
              apellidoPaterno: 'MORENO',
              apellidoMaterno: 'ALEMAN',
              nombreCompleto: 'JOSE MORENO ALEMAN',
            ),
          ),
        );

        await tester.pumpWidget(
          _buildMask(
            cameraController: _idleMock(),
            lookupService: service,
            onDniReady: completer.complete,
            isBackSide: true,
          ),
        );
        await tester.pump();

        final maskState = tester.state(find.byType(DniCameraMask)) as dynamic;
        final controller = maskState.captureController as DniCameraController;

        controller.recordOcrFrame(_mrzFields());
        controller.recordOcrFrame(_mrzFields());

        final result = await completer.future.timeout(
          const Duration(seconds: 3),
        );
        expect(result.dni, equals('71542895'));

        await _disposeWidget(tester);
      },
    );

    testWidgets(
      'onDniReady never fires when lookupService is null',
      (tester) async {
        var called = false;

        await tester.pumpWidget(
          _buildMask(
            cameraController: _idleMock(),
            onDniReady: (_) => called = true,
            isBackSide: true,
          ),
        );
        await tester.pump();

        final maskState = tester.state(find.byType(DniCameraMask)) as dynamic;
        final controller = maskState.captureController as DniCameraController;

        controller.recordOcrFrame(_mrzFields());
        controller.recordOcrFrame(_mrzFields());

        await tester.pump(const Duration(milliseconds: 100));
        expect(called, isFalse);

        await _disposeWidget(tester);
      },
    );

    testWidgets(
      'onValidCapture still fires independently when lookupService provided',
      (tester) async {
        XFile? capturedFile;
        final service = _FakeLookupService(const DniLookupNetworkError());

        await tester.pumpWidget(
          _buildMask(
            cameraController: _idleMock(),
            lookupService: service,
            onDniReady: (_) {},
            onValidCapture: (file, _) => capturedFile = file,
            isBackSide: true,
          ),
        );
        await tester.pump();

        final maskState = tester.state(find.byType(DniCameraMask)) as dynamic;
        final controller = maskState.captureController as DniCameraController;

        controller.onCaptureDelivered(file: XFile('back.jpg'));

        expect(capturedFile, isNotNull);
        expect(capturedFile!.path, equals('back.jpg'));

        await _disposeWidget(tester);
      },
    );

    testWidgets(
      'no exception when lookupService provided but onDniReady is null',
      (tester) async {
        final service = _FakeLookupService(const DniLookupNotFound());

        await tester.pumpWidget(
          _buildMask(
            cameraController: _idleMock(),
            lookupService: service,
            isBackSide: true,
          ),
        );
        await tester.pump();

        final maskState = tester.state(find.byType(DniCameraMask)) as dynamic;
        final controller = maskState.captureController as DniCameraController;

        controller.recordOcrFrame(_mrzFields());
        controller.recordOcrFrame(_mrzFields());

        await tester.pump(const Duration(milliseconds: 200));

        await _disposeWidget(tester);
      },
    );
  });
}
