// ignore_for_file: prefer_const_constructors
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/data/ocr_consensus.dart';
import 'package:dni_peru_ocr/src/data/ocr_field_extractor.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_data.dart';
import 'package:dni_peru_ocr/src/lookup/models/dni_lookup_result.dart';
import 'package:dni_peru_ocr/src/lookup/services/dni_lookup_service.dart';
import 'package:dni_peru_ocr/src/presentation/controllers/dni_camera_controller.dart';

// ─── Tests ──────────────────────────────────────────────────────────────────
//
// PR5 (capture-redesign final migration) removed this controller's parallel
// capture-STATE subsystem — the `captureState` notifier, the manual-fallback
// timer, and the `start` / `stop` / `captureManually` / `activateManualFallback`
// / `restartManualFallbackTimer` methods. The single capture-readiness owner is
// now CaptureCoordinator. These tests cover the controller's REMAINING job: the
// back-side OCR consensus accumulator, the reliable lookup pipeline, capture
// delivery, the side-flag, and the dispose lifecycle.

void main() {
  // ── Group 1: Dispose lifecycle ────────────────────────────────────────────

  group('DniCameraController — dispose lifecycle', () {
    test('dispose is idempotent — second call does not throw', () async {
      final controller = DniCameraController(
        isBackSide: false,
        onValidCapture: (_, _) {},
      );

      await controller.dispose();
      await expectLater(controller.dispose(), completes);
    });

    test('calling onSideChanged after dispose is a no-op (does not throw)',
        () async {
      final controller = DniCameraController(
        isBackSide: false,
        onValidCapture: (_, _) {},
      );

      await controller.dispose();

      expect(() => controller.onSideChanged(), returnsNormally);
    });
  });

  // ── Group 2: onCaptureDelivered ───────────────────────────────────────────

  group('DniCameraController — onCaptureDelivered', () {
    test('onCaptureDelivered fires onValidCapture', () {
      XFile? capturedFile;
      OcrConsensusResult? capturedConsensus;
      final controller = DniCameraController(
        isBackSide: false,
        onValidCapture: (file, consensus) {
          capturedFile = file;
          capturedConsensus = consensus;
        },
      );
      addTearDown(controller.dispose);

      controller.onCaptureDelivered(file: XFile('photo.jpg'));

      expect(capturedFile?.path, equals('photo.jpg'));
      // isBackSide=false: consensus is always null on front side
      expect(capturedConsensus, isNull);
    });

    test('onCaptureDelivered on back side passes consensus through', () {
      OcrConsensusResult? capturedConsensus;
      final controller = DniCameraController(
        isBackSide: true,
        onValidCapture: (_, consensus) => capturedConsensus = consensus,
      );
      addTearDown(controller.dispose);

      final backConsensus = OcrConsensusResult(
        success: true,
        source: OcrConsensusSource.mrzChecksum,
        documentNumber:
            const OcrFieldResult(value: '12345678', confidence: 1.0, locked: true),
        firstName:
            const OcrFieldResult(value: 'JOSE', confidence: 1.0, locked: true),
        lastName:
            const OcrFieldResult(value: 'MORENO', confidence: 1.0, locked: true),
        secondLastName:
            const OcrFieldResult(value: null, confidence: 0, locked: false),
        dateOfBirth:
            const OcrFieldResult(value: null, confidence: 0, locked: false),
        expirationDate:
            const OcrFieldResult(value: null, confidence: 0, locked: false),
        address:
            const OcrFieldResult(value: null, confidence: 0, locked: false),
      );
      controller.onCaptureDelivered(
          file: XFile('photo.jpg'), consensus: backConsensus);

      expect(capturedConsensus, isNotNull);
      expect(capturedConsensus!.firstName.value, equals('JOSE'));
    });

    test('onCaptureDelivered after dispose is a no-op', () async {
      var called = false;
      final controller = DniCameraController(
        isBackSide: false,
        onValidCapture: (_, _) => called = true,
      );

      await controller.dispose();
      controller.onCaptureDelivered(file: XFile('photo.jpg'));

      expect(called, isFalse);
    });
  });

  // ── Group 3: Pipeline wiring — lookupService + onDniReady ─────────────────

  group('DniCameraController — lookupService + onDniReady wiring', () {
    OcrExtractedFields buildMrzFields({String dni = '71542895'}) {
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

    test(
      'onDniReady fires once with DniData after consensus when lookupService provided',
      () async {
        final completer = Completer<DniData>();
        final service = _FakeLookupService(
          DniLookupSuccess(
            DniData(
              dni: '71542895',
              nombres: 'JOSE',
              apellidoPaterno: 'MORENO',
              apellidoMaterno: 'ALEMAN',
              nombreCompleto: 'JOSE MORENO ALEMAN',
            ),
          ),
        );
        final controller = DniCameraController(
          isBackSide: true,
          onValidCapture: (_, _) {},
          lookupService: service,
          onDniReady: completer.complete,
        );
        addTearDown(controller.dispose);

        controller.onSideChanged(isBackSide: true);
        controller.recordOcrFrame(buildMrzFields());
        final consensusReached = controller.recordOcrFrame(buildMrzFields());
        expect(consensusReached, isTrue);

        final result = await completer.future.timeout(
          const Duration(seconds: 3),
        );
        expect(result.dni, equals('71542895'));
        expect(result.nombres, equals('JOSE'));
      },
    );

    test(
      'onDniReady never called when lookupService is null',
      () async {
        var called = false;
        final controller = DniCameraController(
          isBackSide: true,
          onValidCapture: (_, _) {},
          onDniReady: (_) => called = true,
        );
        addTearDown(controller.dispose);

        controller.onSideChanged(isBackSide: true);
        controller.recordOcrFrame(buildMrzFields());
        controller.recordOcrFrame(buildMrzFields());

        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(called, isFalse);
      },
    );

    test(
      'no crash when lookupService provided but onDniReady is null',
      () async {
        final service = _FakeLookupService(
          DniLookupSuccess(
            DniData(
              dni: '71542895',
              nombres: 'JOSE',
              apellidoPaterno: 'MORENO',
              apellidoMaterno: 'ALEMAN',
              nombreCompleto: 'JOSE MORENO ALEMAN',
            ),
          ),
        );
        final controller = DniCameraController(
          isBackSide: true,
          onValidCapture: (_, _) {},
          lookupService: service,
        );
        addTearDown(controller.dispose);

        controller.onSideChanged(isBackSide: true);
        controller.recordOcrFrame(buildMrzFields());
        final consensusReached = controller.recordOcrFrame(buildMrzFields());
        expect(consensusReached, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 200));
      },
    );

    test(
      'onDniReady fires only once even if consensus fires multiple times',
      () async {
        var callCount = 0;
        final service = _FakeLookupService(
          DniLookupSuccess(
            DniData(
              dni: '71542895',
              nombres: 'JOSE',
              apellidoPaterno: 'MORENO',
              apellidoMaterno: 'ALEMAN',
              nombreCompleto: 'JOSE MORENO ALEMAN',
            ),
          ),
        );
        final controller = DniCameraController(
          isBackSide: true,
          onValidCapture: (_, _) {},
          lookupService: service,
          onDniReady: (_) => callCount++,
        );
        addTearDown(controller.dispose);

        controller.onSideChanged(isBackSide: true);
        controller.recordOcrFrame(buildMrzFields());
        controller.recordOcrFrame(buildMrzFields());
        controller.recordOcrFrame(buildMrzFields());
        controller.recordOcrFrame(buildMrzFields());

        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(callCount, equals(1));
      },
    );
  });

  // ── BUG regression — controller side-flag must update on onSideChanged ────
  //
  // Symptom (JC v0.6.3 report): `DniCameraMask` shutter prints
  //   🔴 isBackSide=true consensus=NOT-NULL firstName=JOSE
  // but InClub host callback prints
  //   🟠 ENTRY isFront=false consensus=NULL
  //
  // Root cause: the controller's _isBackSide flag was `final` and only set
  // in the constructor. When Flutter REUSES the widget state across the
  // front→back step transition, initState does not re-run, so the controller
  // stays with _isBackSide=false. onCaptureDelivered then passes
  // `_isBackSide ? consensus : null` = `false ? ... : null` = null, dropping
  // the snapshot on the floor before it reaches the host.
  //
  // Fix: _isBackSide is now mutable and synced inside onSideChanged.
  group('BUG regression — controller side-flag follows onSideChanged', () {
    test(
      'controller created front-side then flipped to back delivers consensus',
      () {
        OcrConsensusResult? deliveredConsensus;
        var deliveredFile = '';

        final controller = DniCameraController(
          isBackSide: false, // ← starts front-side
          onValidCapture: (file, consensus) {
            deliveredFile = file.path;
            deliveredConsensus = consensus;
          },
        );

        // The widget then transitions to back-side (Flutter reuses State,
        // so the controller instance is the same).
        controller.onSideChanged(isBackSide: true);

        final consensus = OcrConsensusResult(
          success: true,
          source: OcrConsensusSource.mrzChecksum,
          documentNumber: const OcrFieldResult(
            value: '71542895',
            confidence: 1.0,
            locked: true,
          ),
          firstName: const OcrFieldResult(
            value: 'JOSE',
            confidence: 1.0,
            locked: true,
          ),
          lastName: const OcrFieldResult(
            value: 'MORENO',
            confidence: 1.0,
            locked: true,
          ),
          secondLastName: const OcrFieldResult(
            value: 'ALEMAN',
            confidence: 1.0,
            locked: true,
          ),
          dateOfBirth: const OcrFieldResult(
            value: '01/09/1994',
            confidence: 1.0,
            locked: true,
          ),
          expirationDate: const OcrFieldResult(
            value: '19/02/2028',
            confidence: 1.0,
            locked: true,
          ),
          address:
              const OcrFieldResult(value: null, confidence: 0, locked: false),
        );

        controller.onCaptureDelivered(file: XFile('back.jpg'), consensus: consensus);

        expect(deliveredFile, 'back.jpg');
        expect(
          deliveredConsensus,
          isNotNull,
          reason:
              'BUG: controller was constructed front-side and then flipped to '
              'back via onSideChanged — the consensus from onCaptureDelivered '
              'must reach the host, NOT be dropped by a stale _isBackSide flag.',
        );
        expect(deliveredConsensus!.firstName.value, 'JOSE');
        expect(deliveredConsensus!.lastName.value, 'MORENO');
        expect(deliveredConsensus!.documentNumber.value, '71542895');
      },
    );

    test(
      'controller created back-side then flipped to front delivers null consensus',
      () {
        OcrConsensusResult? deliveredConsensus;

        final controller = DniCameraController(
          isBackSide: true,
          onValidCapture: (file, consensus) {
            deliveredConsensus = consensus;
          },
        );
        controller.onSideChanged(isBackSide: false);

        final consensus = OcrConsensusResult(
          success: true,
          source: OcrConsensusSource.mrzChecksum,
          documentNumber: const OcrFieldResult(
            value: '71542895',
            confidence: 1.0,
            locked: true,
          ),
          firstName: const OcrFieldResult(
            value: 'JOSE',
            confidence: 1.0,
            locked: true,
          ),
          lastName: const OcrFieldResult(
            value: 'MORENO',
            confidence: 1.0,
            locked: true,
          ),
          secondLastName:
              const OcrFieldResult(value: null, confidence: 0, locked: false),
          dateOfBirth:
              const OcrFieldResult(value: null, confidence: 0, locked: false),
          expirationDate:
              const OcrFieldResult(value: null, confidence: 0, locked: false),
          address:
              const OcrFieldResult(value: null, confidence: 0, locked: false),
        );

        controller.onCaptureDelivered(file: XFile('front.jpg'), consensus: consensus);

        expect(
          deliveredConsensus,
          isNull,
          reason: 'Controller transitioned to front-side: consensus must be '
              'scrubbed regardless of what the host passed.',
        );
      },
    );
  });
}

class _FakeLookupService implements DniLookupService {
  _FakeLookupService(this._result);
  final DniLookupResult _result;

  @override
  Future<DniLookupResult> lookup(String dni) async => _result;
}
