import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HuntStateMachine', () {
    const noOpAnchor = DocumentSide.unknown;
    const frontAnchor = DocumentSide.front;
    const backAnchor = DocumentSide.back;

    group('minFieldsForFastAdvance override', () {
      test('override=null uses default value of 12', () {
        final machine = HuntStateMachine();
        expect(machine.minFieldsForFastAdvance, 12);
      });

      test('override=3 uses 3 (scaled for n=4 minimal)', () {
        final machine = HuntStateMachine(minFieldsForFastAdvance: 3);
        expect(machine.minFieldsForFastAdvance, 3);
      });

      test('override=5 uses 5 (scaled for n=7 kyc)', () {
        final machine = HuntStateMachine(minFieldsForFastAdvance: 5);
        expect(machine.minFieldsForFastAdvance, 5);
      });

      test('override=14 uses 14 (same as full/default)', () {
        final machine = HuntStateMachine(minFieldsForFastAdvance: 14);
        expect(machine.minFieldsForFastAdvance, 14);
      });

      test('fast-advance triggers earlier when override is lower', () {
        final machine = HuntStateMachine(
          idleFramesThreshold: 10,
          fastAdvanceThreshold: 2,
          minFieldsForFastAdvance: 3,
        );
        machine.recordFrame(detectedSide: frontAnchor, addedNewField: false);
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 4,
        );
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 4,
        );
        final signal = machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 4,
        );
        expect(signal, HuntSignal.frontCaptureReady);
      });
    });

    test('starts in waitingFront phase', () {
      final machine = HuntStateMachine();
      expect(machine.phase, HuntPhase.waitingFront);
    });

    test('stays in waitingFront when no front anchor seen', () {
      final machine = HuntStateMachine();
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: true);
      expect(machine.phase, HuntPhase.waitingFront);
    });

    test('advances to extractingFront when front anchor detected', () {
      final machine = HuntStateMachine();
      machine.recordFrame(detectedSide: frontAnchor, addedNewField: false);
      expect(machine.phase, HuntPhase.extractingFront);
    });

    test('stays in extractingFront while frames keep adding new fields', () {
      final machine = HuntStateMachine(idleFramesThreshold: 5);
      machine.recordFrame(detectedSide: frontAnchor, addedNewField: false);
      for (var i = 0; i < 10; i++) {
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: true);
      }
      expect(machine.phase, HuntPhase.extractingFront);
    });

    test('signals frontCaptureReady after N idle frames', () {
      final machine = HuntStateMachine(idleFramesThreshold: 3);
      machine.recordFrame(detectedSide: frontAnchor, addedNewField: false);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: true);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      final signal =
          machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      expect(signal, HuntSignal.frontCaptureReady);
    });

    test('resets idle counter when a frame adds new field', () {
      final machine = HuntStateMachine(idleFramesThreshold: 3);
      machine.recordFrame(detectedSide: frontAnchor, addedNewField: false);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: true);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      expect(machine.phase, HuntPhase.extractingFront);
    });

    test('advanceToWaitingBack moves out of extractingFront', () {
      final machine = HuntStateMachine(idleFramesThreshold: 1);
      machine.recordFrame(detectedSide: frontAnchor, addedNewField: false);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      machine.advanceToWaitingBack();
      expect(machine.phase, HuntPhase.waitingBack);
    });

    test('stays in waitingBack until back anchor detected', () {
      final machine = HuntStateMachine();
      _seedFrontPhaseComplete(machine);
      machine.advanceToWaitingBack();
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      machine.recordFrame(detectedSide: frontAnchor, addedNewField: false);
      expect(machine.phase, HuntPhase.waitingBack);
    });

    test('advances to extractingBack when back anchor detected', () {
      final machine = HuntStateMachine();
      _seedFrontPhaseComplete(machine);
      machine.advanceToWaitingBack();
      machine.recordFrame(detectedSide: backAnchor, addedNewField: false);
      expect(machine.phase, HuntPhase.extractingBack);
    });

    test('signals backCaptureReady after N idle frames in extractingBack', () {
      final machine = HuntStateMachine(idleFramesThreshold: 2);
      _seedFrontPhaseComplete(machine);
      machine.advanceToWaitingBack();
      machine.recordFrame(detectedSide: backAnchor, addedNewField: false);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: true);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      final signal =
          machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      expect(signal, HuntSignal.backCaptureReady);
    });

    group('waiting-phase stuck escape (#5457 latch fix)', () {
      test('escapes a stuck waitingBack via idle with a recovery signal, '
          'NOT a blind back-capture', () {
        final machine = HuntStateMachine(idleFramesThreshold: 3);
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        // Side detector never confirms the back anchor (unknown forever).
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        final signal =
            machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        expect(signal, HuntSignal.recoverManual);
      });

      test('SAFETY: escaping waitingBack with an unconfirmed side does NOT '
          'emit backCaptureReady', () {
        final machine = HuntStateMachine(idleFramesThreshold: 3);
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        final signals = <HuntSignal>[
          for (var i = 0; i < 6; i++)
            machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false),
        ];
        expect(signals, isNot(contains(HuntSignal.backCaptureReady)));
      });

      test('escapes a stuck waitingFront via idle with a recovery signal', () {
        final machine = HuntStateMachine(idleFramesThreshold: 3);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        final signal =
            machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        expect(signal, HuntSignal.recoverManual);
      });

      test('REGRESSION: confirmed back anchor still advances to extractingBack '
          'and reaches backCaptureReady (happy path intact)', () {
        final machine = HuntStateMachine(idleFramesThreshold: 2);
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        machine.recordFrame(detectedSide: backAnchor, addedNewField: false);
        expect(machine.phase, HuntPhase.extractingBack);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: true);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        final signal =
            machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        expect(signal, HuntSignal.backCaptureReady);
      });

      test('REGRESSION: an added field resets the waiting idle counter so a '
          'productive wait is not cut short', () {
        final machine = HuntStateMachine(idleFramesThreshold: 3);
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: true);
        final signal =
            machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        expect(signal, HuntSignal.none);
      });
    });

    test('advanceToDone moves to done phase', () {
      final machine = HuntStateMachine();
      _seedFrontPhaseComplete(machine);
      machine.advanceToWaitingBack();
      _seedBackPhaseComplete(machine);
      machine.advanceToDone();
      expect(machine.phase, HuntPhase.done);
    });

    test('reset returns machine to waitingFront', () {
      final machine = HuntStateMachine();
      _seedFrontPhaseComplete(machine);
      machine.advanceToWaitingBack();
      machine.reset();
      expect(machine.phase, HuntPhase.waitingFront);
    });

    group('completeness fast-path (per side)', () {
      test('fires frontCaptureReady when all FRONT-side selected fields are '
          'filled, even though the full selection is larger', () {
        final machine = HuntStateMachine(
          frontCompleteFieldsCount: 6,
          backCompleteFieldsCount: 7,
        );
        _seedFrontPhaseComplete(machine);
        final signal = machine.recordFrame(
          detectedSide: DocumentSide.front,
          addedNewField: true,
          filledFields: 6,
        );
        expect(signal, HuntSignal.frontCaptureReady);
      });

      test('fires backCaptureReady when the back-phase threshold is met', () {
        final machine = HuntStateMachine(
          frontCompleteFieldsCount: 6,
          backCompleteFieldsCount: 7,
        );
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        _seedBackPhaseComplete(machine);
        final signal = machine.recordFrame(
          detectedSide: DocumentSide.back,
          addedNewField: true,
          filledFields: 7,
        );
        expect(signal, HuntSignal.backCaptureReady);
      });

      test('still waits for idle frames while the front side is incomplete',
          () {
        final machine = HuntStateMachine(
          frontCompleteFieldsCount: 6,
          backCompleteFieldsCount: 7,
        );
        _seedFrontPhaseComplete(machine);
        final signal = machine.recordFrame(
          detectedSide: DocumentSide.front,
          addedNewField: true,
          filledFields: 5,
        );
        expect(signal, HuntSignal.none);
      });

      test('without per-side counts the fast-path is disabled', () {
        final machine = HuntStateMachine();
        _seedFrontPhaseComplete(machine);
        final signal = machine.recordFrame(
          detectedSide: DocumentSide.front,
          addedNewField: true,
          filledFields: 19,
        );
        expect(signal, HuntSignal.none);
      });
    });
  });
}

void _seedFrontPhaseComplete(HuntStateMachine machine) {
  machine.recordFrame(
    detectedSide: DocumentSide.front,
    addedNewField: false,
  );
}

void _seedBackPhaseComplete(HuntStateMachine machine) {
  machine.recordFrame(
    detectedSide: DocumentSide.back,
    addedNewField: false,
  );
}
