import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

/// #5562 — cached-front-fields handoff hazard.
///
/// At the front->back handoff the shared FieldHunter is NEVER reset, so the
/// front's ~11 filled fields stay cached into the back phase. The back latch
/// floor `filledFields >= minFieldsForStableCapture` was therefore ALWAYS
/// satisfied by the cached front fields, leaving `detectedSide != front` as the
/// only wrong-side guard. A back frame that momentarily reads `unknown` (the
/// front title block briefly unread, e.g. glare/motion) WHILE the user is still
/// showing the front then latches `extractingBack` on the cached front fields
/// and captures the FRONT as the BACK.
///
/// The fix snapshot-isolates the back-phase field count at the handoff: the
/// back floor measures fields gained SINCE the handoff, so cached front fields
/// can no longer satisfy it. The textless-back QUAD trigger (#5517/#5525) and
/// the wrong-side guard (`detectedSide != front`, #5499) are unchanged.
void main() {
  group('HuntStateMachine front->back handoff field isolation (#5562)', () {
    HuntStateMachine handedOffMachine() {
      final machine = HuntStateMachine(
        idleFramesThreshold: 4,
        fastAdvanceThreshold: 3,
        minFieldsForFastAdvance: 4,
        minFieldsForStableCapture: 4,
        backCompleteFieldsCount: 19,
      );
      // Front phase reaches an 11-field plateau, exactly as the device leaves
      // the hunter at the handoff.
      machine.recordFrame(
        detectedSide: DocumentSide.front,
        addedNewField: false,
        filledFields: 11,
      );
      machine.recordFrame(
        detectedSide: DocumentSide.unknown,
        addedNewField: false,
        filledFields: 11,
      );
      machine.advanceToWaitingBack();
      return machine;
    }

    test(
      'a back frame reading unknown with ONLY cached front fields (no new back '
      'data, no quad) does NOT latch extractingBack — the cached-field hazard',
      () {
        final machine = handedOffMachine();

        // The front is still in view but this single frame failed to read the
        // title block, so detect() momentarily returns unknown. The cached
        // front fields (11) are still in the hunter. No quad confirms framing.
        machine.recordFrame(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 11,
        );

        expect(
          machine.phase,
          HuntPhase.waitingBack,
          reason: 'cached front fields must NOT satisfy the back floor; '
              'latching here captures the front as the back (#5562)',
        );
      },
    );

    test(
      'cached-only front fields never reach backCaptureReady (no front-as-back '
      'auto-capture)',
      () {
        final machine = handedOffMachine();

        final signals = <HuntSignal>[
          for (var i = 0; i < 8; i++)
            machine.recordFrame(
              detectedSide: DocumentSide.unknown,
              addedNewField: false,
              filledFields: 11,
            ),
        ];

        expect(
          signals,
          isNot(contains(HuntSignal.backCaptureReady)),
          reason: 'a back never auto-captures from cached front fields alone',
        );
        expect(machine.phase, isNot(HuntPhase.extractingBack));
      },
    );

    test(
      'PRESERVED (#5517): a side-safe valid QUAD still latches the textless '
      'back even though the cached-field floor is now neutralized',
      () {
        final machine = handedOffMachine();

        machine.recordFrame(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 11,
          quadFramingValid: true,
        );

        expect(
          machine.phase,
          HuntPhase.extractingBack,
          reason: 'the quad is the textless back trigger and must still latch',
        );
      },
    );

    test(
      'PRESERVED: a genuine back that gains NEW fields ABOVE the handoff '
      'baseline latches via the field path (OCR-rich back)',
      () {
        final machine = handedOffMachine();

        // A genuinely OCR-rich back keeps revealing back-specific fields, so the
        // filled count rises above the 11-field handoff baseline by the floor.
        machine.recordFrame(
          detectedSide: DocumentSide.unknown,
          addedNewField: true,
          filledFields: 15,
        );

        expect(
          machine.phase,
          HuntPhase.extractingBack,
          reason: 'fields gained after the handoff (15 - 11 = 4 >= floor) are '
              'real back data and must latch',
        );
      },
    );

    test(
      'PRESERVED (#5499): a confirmed back anchor (detectedSide == back) still '
      'latches regardless of cached fields',
      () {
        final machine = handedOffMachine();

        machine.recordFrame(
          detectedSide: DocumentSide.back,
          addedNewField: false,
          filledFields: 11,
        );

        expect(machine.phase, HuntPhase.extractingBack);
      },
    );
  });
}
