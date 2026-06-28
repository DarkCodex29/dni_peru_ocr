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
import 'package:dni_peru_ocr/src/presentation/orchestrators/dni_capture_orchestrator.dart';
import 'package:dni_peru_ocr/src/presentation/orchestrators/dni_capture_state.dart';

// ─── Test helpers ─────────────────────────────────────────────────────────────

DniCaptureOrchestrator _orchestrator({
  int autoCaptureMs = 1500,
  int gracePeriodMs = 600,
  int manualFallbackMs = 15000,
  int minStableFrames = 2,
}) =>
    DniCaptureOrchestrator(
      autoCaptureMs: autoCaptureMs,
      gracePeriodMs: gracePeriodMs,
      manualFallbackMs: manualFallbackMs,
      minStableFrames: minStableFrames,
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── Group 1: Initialization and initial state ─────────────────────────────

  group('DniCameraController — initialization and initial state', () {
    test('initial state is DniCaptureScanning', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );
      addTearDown(controller.dispose);

      expect(controller.captureState.value, isA<DniCaptureScanning>());
    });

    test('initial scanning state has manualModeActive=false', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );
      addTearDown(controller.dispose);

      final state = controller.captureState.value;
      expect(
        state,
        isA<DniCaptureScanning>()
            .having((s) => s.manualModeActive, 'manualModeActive', isFalse),
      );
    });

    test('exposes captureState as ValueListenable', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );
      addTearDown(controller.dispose);

      // ValueListenable contract: can add/remove listeners without crashing
      var notified = false;
      void listener() => notified = true;
      controller.captureState.addListener(listener);
      controller.captureState.removeListener(listener);
      expect(notified, isFalse);
    });
  });

  // ── Group 2: State transitions ────────────────────────────────────────────

  group('DniCameraController — state transitions', () {
    test('state notifies listeners when changed', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(minStableFrames: 1),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );
      addTearDown(controller.dispose);

      var notifyCount = 0;
      controller.captureState.addListener(() => notifyCount++);

      // A manual capture moves Scanning → InFlight (a real change)
      controller.captureManually();

      expect(notifyCount, greaterThan(0));
      expect(controller.captureState.value, isA<DniCaptureInFlight>());
    });

    test(
        'onSideChanged resets to DniCaptureScanning with manualModeActive=false',
        () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );
      addTearDown(controller.dispose);

      controller.onSideChanged();
      expect(
        controller.captureState.value,
        isA<DniCaptureScanning>()
            .having((s) => s.manualModeActive, 'manualModeActive', isFalse),
      );
    });

    test('onSideChanged can be called multiple times safely', () {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );
      addTearDown(controller.dispose);

      controller.onSideChanged();
      controller.onSideChanged();
      controller.onSideChanged();

      expect(controller.captureState.value, isA<DniCaptureScanning>());
    });
  });

  // ── Group 3: Manual fallback timer ────────────────────────────────────────

  group('DniCameraController — manual fallback timer', () {
    test('state becomes manualModeActive=true after manualFallbackMs',
        () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(manualFallbackMs: 50), // fast for tests
        isBackSide: false,
        onValidCapture: (_, _) {},
      );
      addTearDown(controller.dispose);

      // start() arms the timer
      await controller.start();

      // Wait for the timer to fire
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        controller.captureState.value,
        isA<DniCaptureScanning>()
            .having((s) => s.manualModeActive, 'manualModeActive', isTrue),
      );
    });

    test('onSideChanged resets manualModeActive even after timer fires',
        () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(manualFallbackMs: 50),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );
      addTearDown(controller.dispose);

      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        (controller.captureState.value as DniCaptureScanning).manualModeActive,
        isTrue,
      );

      controller.onSideChanged();
      expect(
        (controller.captureState.value as DniCaptureScanning).manualModeActive,
        isFalse,
      );
    });

    test(
        'restartManualFallbackTimer restarts the window so the manual fallback '
        'measures from the current side, not from scanner open (#5536)',
        () async {
      // Device truth (#5536): the live front->back handoff does NOT call
      // onSideChanged, so the fallback timer kept measuring from scanner open
      // and surfaced the back manual button too soon. A per-side restart at the
      // handoff makes the back manual window start when the back starts trying.
      final controller = DniCameraController(
        orchestrator: _orchestrator(manualFallbackMs: 100),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );
      addTearDown(controller.dispose);

      await controller.start();

      // Partway through the first window, restart it (as the front->back
      // handoff would for the new side).
      await Future<void>.delayed(const Duration(milliseconds: 60));
      controller.restartManualFallbackTimer();

      // The ORIGINAL window (100ms from start) would have elapsed by now, but
      // the restart pushed it out, so manual mode must NOT be active yet.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        (controller.captureState.value as DniCaptureScanning).manualModeActive,
        isFalse,
        reason: 'restart must reset the window so the fallback measures from '
            'the current side, not the original scanner-open instant',
      );

      // A full fresh window from the restart elapses -> manual mode activates.
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(
        (controller.captureState.value as DniCaptureScanning).manualModeActive,
        isTrue,
        reason: 'the fallback must still fire after a full per-side window',
      );
    });
  });

  // ── Group 4: Dispose lifecycle ────────────────────────────────────────────

  group('DniCameraController — dispose lifecycle', () {
    test('dispose transitions state to Done', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );

      await controller.dispose();

      expect(controller.captureState.value, isA<DniCaptureDone>());
    });

    test('dispose is idempotent — second call does not throw', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );

      await controller.dispose();
      await expectLater(controller.dispose(), completes);
    });

    test('calling onSideChanged after dispose is a no-op (does not throw)',
        () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );

      await controller.dispose();

      expect(() => controller.onSideChanged(), returnsNormally);
    });
  });

  // ── Group 5: Mid-capture dispose race condition ───────────────────────────

  group('DniCameraController — mid-capture dispose safety', () {
    test('dispose while InFlight does not throw', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );

      controller.captureManually();
      expect(controller.captureState.value, isA<DniCaptureInFlight>());

      await expectLater(controller.dispose(), completes);
    });

    test('captureManually while already InFlight is a no-op', () async {
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, _) {},
      );
      addTearDown(controller.dispose);

      controller.captureManually();
      expect(controller.captureState.value, isA<DniCaptureInFlight>());

      // A second captureManually on InFlight should be a no-op
      expect(() => controller.captureManually(), returnsNormally);
      expect(controller.captureState.value, isA<DniCaptureInFlight>());
    });
  });

  // ── Group 6: onCaptureDelivered ───────────────────────────────────────────

  group('DniCameraController — onCaptureDelivered', () {
    test('onCaptureDelivered fires onValidCapture and transitions to Done', () {
      XFile? capturedFile;
      OcrConsensusResult? capturedConsensus;
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
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
      expect(controller.captureState.value, isA<DniCaptureDone>());
    });

    test('onCaptureDelivered on back side passes consensus through', () {
      OcrConsensusResult? capturedConsensus;
      final controller = DniCameraController(
        orchestrator: _orchestrator(),
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
        orchestrator: _orchestrator(),
        isBackSide: false,
        onValidCapture: (_, _) => called = true,
      );

      await controller.dispose();
      controller.onCaptureDelivered(file: XFile('photo.jpg'));

      expect(called, isFalse);
    });
  });

  // ── Group 7: Pipeline wiring — lookupService + onDniReady ─────────────────

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
          orchestrator: _orchestrator(),
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
          orchestrator: _orchestrator(),
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
          orchestrator: _orchestrator(),
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
          orchestrator: _orchestrator(),
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
          orchestrator: _orchestrator(),
          isBackSide: false, // ← starts front-side
          onValidCapture: (file, consensus) {
            deliveredFile = file.path;
            deliveredConsensus = consensus;
          },
        );

        // The widget then transitions to back-side (Flutter reuses State,
        // so the controller instance is the same).
        controller.onSideChanged(isBackSide: true);

        // Simulate a back-side capture: feed an MRZ frame through the
        // accumulator so snapshotConsensus() returns NOT-NULL data.
        // We use lockFromMrzFields twice so the accumulator locks.
        // That path mirrors what _triggerShutter does in DniCameraMask.
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
        // Inverse of the above: a controller initially back-side that flips
        // to front must NOT leak a back-side consensus through a stale flag.
        OcrConsensusResult? deliveredConsensus;

        final controller = DniCameraController(
          orchestrator: _orchestrator(),
          isBackSide: true,
          onValidCapture: (file, consensus) {
            deliveredConsensus = consensus;
          },
        );
        controller.onSideChanged(isBackSide: false);

        // Even if the host accidentally passed a non-null consensus, the
        // controller must scrub it because the active side is now front.
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
