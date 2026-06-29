import 'package:dni_peru_ocr/src/domain/extraction/dni_fields.dart';
import 'package:dni_peru_ocr/src/domain/extraction/hunt_state_machine.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_coordinator.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_decision.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/frame_input.dart';
import 'package:flutter_test/flutter_test.dart';

import 'capture_frame_sequence_harness.dart';

/// #5562 — the REAL-LAYER reproduction of the device side-confusion regression.
///
/// The SACRED both-sides golden drives an EMPTY-OCR back (the quad-only path).
/// But the real Peru DNI back carries RENIEC tokens (DNI + 8 digits, Grupo de
/// Votación, address) with NO front title block and NO clean back anchor, so on
/// device the back goes down the REAL `detect()` branch and reads `unknown`
/// (#5499). No test drove a TEXTFUL back through the real detect() across the
/// `advanceAfterCapture` handoff — the blind spot.
///
/// These tests feed realistic textful OCR through the REAL
/// `DocumentSideDetector.detect` -> `FieldHunter.process` ->
/// `HuntStateMachine.recordFrame` chain across the two-sided handoff, with NO
/// pre-set side and NO injected signal. They prove:
///  - while the front is still shown (or its cached fields linger) a textful
///    frame reading `unknown` with no quad does NOT capture the front as the
///    back, and
///  - a genuine back (a sustained quad) DOES capture correctly.
void main() {
  /// A realistic Peru DNI FRONT OCR block: title anchor + the four minimal
  /// fields. `detect()` reads it as front; the hunter fills the minimal set.
  const frontText = 'DOCUMENTO NACIONAL DE IDENTIDAD\n'
      'DNI 16793105\n'
      'PRIMER APELLIDO\nMUÑOZ\n'
      'SEGUNDO APELLIDO\nPEREZ\n'
      'PRE NOMBRES\nJUAN CARLOS';

  const frontFrame = FrameInput(
    ocrText: frontText,
    quadFramingValid: false,
    imuStill: true,
    frameWidth: 640,
    frameHeight: 480,
  );

  /// A realistic textful Peru DNI BACK OCR block: the DNI number near the MRZ,
  /// Grupo de Votación and an address — NO front title block, NO clean back
  /// anchor. Through the real detector this resolves to `unknown` (#5499), so
  /// the ONLY guard against a front-as-back capture is the cached-field
  /// isolation (#5562): it carries text but adds no NEW minimal-field data.
  const textfulBackText = 'Grupo de Votación 083966\n'
      'Dirección AMPLC. TUPAC AMARU SICUANI 215\n'
      'DNI 71542895\n'
      'I<PER7154289<<<<<<<<<<<<<<<';

  /// The textful back held with NO quad: the hazard frame. Empty quad means the
  /// only thing that could latch is the cached front field count.
  const textfulBackNoQuad = FrameInput(
    ocrText: textfulBackText,
    quadFramingValid: false,
    imuStill: true,
    frameWidth: 640,
    frameHeight: 480,
  );

  /// A genuine textless back held still with a sustained valid quad.
  const genuineBackFrame = FrameInput(
    ocrText: '',
    quadFramingValid: true,
    imuStill: true,
    frameWidth: 640,
    frameHeight: 480,
  );

  const idleThreshold = 4;
  const backQuadDwell = 3;

  CaptureCoordinator twoSided() => CaptureCoordinator(
        fields: DniFields.minimal(),
        idleFramesThreshold: idleThreshold,
        backQuadDwellFrames: backQuadDwell,
      );

  test(
    'a textful back reading unknown across the handoff (no quad) does NOT '
    'capture the front as the back — cached front fields must not latch (#5562)',
    () {
      final coordinator = twoSided();
      final harness = CaptureFrameSequenceHarness(coordinator);

      // PHASE 1 — the front scans through the REAL detector and fires once.
      final frontFire = harness.feedUntilFire(frontFrame);
      expect(frontFire, isNotNull);
      expect(frontFire!.side, CaptureSide.front);

      // HANDOFF — the device captures the front and advances to the back phase.
      coordinator.advanceAfterCapture();
      expect(coordinator.phase, HuntPhase.waitingBack);

      // PHASE 2 — a TEXTFUL back (or a front momentarily reading unknown) is
      // held with NO quad. detect() returns unknown and the hunter adds no new
      // minimal field, so the only thing that could latch is the cached front
      // field count. It must NOT latch extractingBack, or the front is one
      // quad-blip away from being captured as the back.
      for (var i = 0; i < 10; i++) {
        harness.feed(textfulBackNoQuad);
      }

      expect(
        coordinator.phase,
        HuntPhase.waitingBack,
        reason: 'cached front fields must not latch extractingBack while only a '
            'textful unknown frame with no quad is in view — latching here is '
            'one quad-blip away from capturing the front as the back (#5562)',
      );
      expect(
        harness.fireCount(CaptureSide.back),
        0,
        reason: 'a textful back with no quad must never auto-capture from '
            'cached front fields — that is the front-as-back bug (#5562)',
      );
    },
  );

  test(
    'a genuine back (sustained quad) across the handoff DOES capture correctly '
    'through the real path',
    () {
      final coordinator = twoSided();
      final harness = CaptureFrameSequenceHarness(coordinator);

      final frontFire = harness.feedUntilFire(frontFrame);
      expect(frontFire, isNotNull);
      expect(frontFire!.side, CaptureSide.front);

      coordinator.advanceAfterCapture();
      expect(coordinator.phase, HuntPhase.waitingBack);

      // A genuine back: textless but a sustained valid quad. The quad is the
      // real back trigger and must fire the back exactly once.
      final backFire = harness.feedUntilFire(genuineBackFrame);
      expect(backFire, isNotNull);
      expect(backFire!.side, CaptureSide.back);
      expect(harness.fireCount(CaptureSide.back), 1);
      expect(harness.fireCount(CaptureSide.front), 1);
    },
  );

  test(
    'the wrong-side guard still holds: the FRONT shown again during the back '
    'phase (real detect == front) never captures (#5499/#5484)',
    () {
      final coordinator = twoSided();
      final harness = CaptureFrameSequenceHarness(coordinator);

      final frontFire = harness.feedUntilFire(frontFrame);
      expect(frontFire!.side, CaptureSide.front);
      coordinator.advanceAfterCapture();

      // The user keeps showing the FRONT during the back phase. detect() reads
      // front every frame, so the back must never latch or fire.
      for (var i = 0; i < 10; i++) {
        harness.feed(frontFrame);
      }

      expect(harness.fireCount(CaptureSide.back), 0);
      expect(coordinator.phase, isNot(HuntPhase.extractingBack));
    },
  );
}
