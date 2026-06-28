import 'package:dni_peru_ocr/src/domain/extraction/dni_fields.dart';
import 'package:dni_peru_ocr/src/domain/extraction/hunt_state_machine.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_coordinator.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_decision.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/frame_input.dart';
import 'package:flutter_test/flutter_test.dart';

/// A realistic front-side OCR text block: the title anchor plus the four
/// minimal fields (document number + three name fields). Driving this through
/// the coordinator runs the REAL DocumentSideDetector + FieldHunter chain — the
/// side is detected from the title, the fields are parsed by the extractors,
/// and the filled-field count is computed exactly as the live widget does.
const _frontText = 'DOCUMENTO NACIONAL DE IDENTIDAD\n'
    'DNI 16793105\n'
    'PRIMER APELLIDO\nMUÑOZ\n'
    'SEGUNDO APELLIDO\nPEREZ\n'
    'PRE NOMBRES\nJUAN CARLOS';

FrameInput _frontFrame({bool quadFramingValid = false}) => FrameInput(
      ocrText: _frontText,
      quadFramingValid: quadFramingValid,
      imuStill: true,
      isBlurry: false,
      frameWidth: 640,
      frameHeight: 480,
    );

FrameInput _emptyFrame({bool quadFramingValid = false}) => FrameInput(
      ocrText: '',
      quadFramingValid: quadFramingValid,
      imuStill: true,
      isBlurry: false,
      frameWidth: 640,
      frameHeight: 480,
    );

void main() {
  group('CaptureCoordinator — real readiness path (no flag injection)', () {
    test('a front sequence drives the real path and fires once', () {
      // Two-sided mode: the side is DETECTED from OCR text, never injected.
      final coordinator = CaptureCoordinator(
        fields: DniFields.minimal(),
        idleFramesThreshold: 4,
      );

      // First front frame: the title anchor latches extractingFront.
      final first = coordinator.onFrame(_frontFrame());
      expect(
        first,
        isA<CaptureScanning>(),
        reason: 'the first front frame detects the side and starts extracting, '
            'not yet capture-ready',
      );
      expect(coordinator.phase, HuntPhase.extractingFront);

      // Hold still on the same plateau: the distinct field count stops rising,
      // so after the idle dwell the REAL HuntStateMachine emits
      // frontCaptureReady — derived from OCR stability, NOT an injected flag.
      CaptureDecision? lastFire;
      for (var i = 0; i < 6; i++) {
        final decision = coordinator.onFrame(_frontFrame());
        if (decision is CaptureFire) lastFire = decision;
      }

      expect(
        lastFire,
        isNotNull,
        reason: 'the front must fire from OCR stability through the real path',
      );
      expect((lastFire! as CaptureFire).side, CaptureSide.front);
    });

    test('a textless back fires through the real quad-dwell back path', () {
      // Single-side back run: start the machine in the back phase exactly as
      // the live widget does for isBackSide:true. The back is TEXTLESS, so OCR
      // is empty and the only readiness proof is a sustained valid quad driven
      // through the REAL machine — never an injected backCaptureReady.
      final coordinator = CaptureCoordinator(
        fields: DniFields.minimal(),
        idleFramesThreshold: 4,
        backQuadDwellFrames: 3,
        initialPhase: HuntPhase.waitingBack,
      );

      CaptureDecision? lastFire;
      for (var i = 0; i < 8; i++) {
        final decision = coordinator.onFrame(_emptyFrame(quadFramingValid: true));
        if (decision is CaptureFire) lastFire = decision;
      }

      expect(
        lastFire,
        isNotNull,
        reason: 'a sustained valid quad must drive the textless back to fire '
            'through the real machine, with no injected flag',
      );
      expect((lastFire! as CaptureFire).side, CaptureSide.back);
    });

    test('a genuine removal (empty OCR, no quad) resets to scanning', () {
      final coordinator = CaptureCoordinator(
        fields: DniFields.minimal(),
        idleFramesThreshold: 4,
        initialPhase: HuntPhase.waitingBack,
      );

      final decision = coordinator.onFrame(_emptyFrame());

      expect(
        decision,
        isA<CaptureScanning>(),
        reason: 'a blank frame with no quad in the back phase is skipped — '
            'no fire, no false presence',
      );
    });

    test('a stuck waiting phase offers manual through the real machine', () {
      // A non-front, sub-floor stream in waitingBack (a frame that carries text
      // but never confirms the back anchor and never reaches the field floor)
      // exhausts the idle threshold. The REAL machine emits recoverManual; the
      // coordinator must surface ManualAvailable — not an injected flag.
      final coordinator = CaptureCoordinator(
        fields: DniFields.minimal(),
        idleFramesThreshold: 3,
        initialPhase: HuntPhase.waitingBack,
      );

      // A textful but anchorless / sub-floor frame: it has OCR text (so it is
      // not the empty-OCR branch) but detects as `unknown` and fills no minimal
      // field, so the back never latches and idle accrues to the threshold.
      // recoverManual is a transient signal emitted each time the idle dwell is
      // exhausted, so collect the stream and assert it surfaced manual.
      const stuckText = 'PERU 2024';
      final decisions = <CaptureDecision>[];
      for (var i = 0; i < 5; i++) {
        decisions.add(
          coordinator.onFrame(
            const FrameInput(
              ocrText: stuckText,
              imuStill: true,
              isBlurry: false,
              frameWidth: 640,
              frameHeight: 480,
            ),
          ),
        );
      }

      expect(
        decisions.whereType<CaptureManualAvailable>(),
        isNotEmpty,
        reason: 'a stuck waiting phase must hand off to manual via the real '
            'recoverManual signal',
      );
    });
  });
}
