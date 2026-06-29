import 'package:dni_peru_ocr/src/domain/extraction/dni_fields.dart';
import 'package:dni_peru_ocr/src/domain/extraction/hunt_state_machine.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_coordinator.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_decision.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/frame_input.dart';
import 'package:flutter_test/flutter_test.dart';

import 'capture_frame_sequence_harness.dart';

/// GOLDEN CAPTURE ORACLE — capture-redesign PR3b, UPDATED in PR4.
///
/// This file FREEZES capture behavior as a set of golden characterization
/// tests, driven entirely through the device-faithful harness (the REAL
/// DocumentSideDetector → FieldHunter → HuntStateMachine chain plus, since PR4,
/// the coordinator-owned countdown), with NO debug-flag injection. It is the
/// regression gate around the god-object → [CaptureCoordinator] migration: any
/// deviation from the decisions pinned here trips a golden immediately.
///
/// PR4 UPDATE (deliberate approval-test changes, NOT silent):
/// PR4 moved the countdown/dwell OWNERSHIP into the coordinator. A readiness
/// signal no longer maps straight to `Fire` — it STARTS the owned countdown,
/// which emits `CountingDown` each held frame and fires `Fire(side)` only when
/// the dwell completes against the harness clock. So the pre-migration
/// `['Scanning','Fire(front)']` shape is now
/// `['Scanning', CountingDown…, 'Fire(front)']`. The SACRED INVARIANT is
/// unchanged and still proven here: the two-sided scan fires the front exactly
/// once and the back exactly once, end-to-end, through the real path with no
/// injected flag. The literal label list grew because the decision vocabulary
/// widened — the migration's whole point — not because capture behavior
/// regressed. These goldens pin the migrated STRUCTURE: latch → countdown →
/// single fire. The exact CountingDown repeat count is a function of the
/// harness frame cadence vs. the dwell duration (an implementation detail), so
/// the goldens assert "one or more CountingDown frames then exactly one Fire"
/// rather than a brittle literal repeat count.
///
/// Two classes of golden live here:
///  - PINNED-FOREVER goldens (the sacred both-sides oracle, front/back happy
///    paths, the motion-blip rejection) describe behavior that MUST be
///    preserved across the migration.
///  - CURED-IN-PR5 goldens were the known device bugs (false-absent presence,
///    front stuck-after-removal). PR5 migrated presence into the coordinator
///    (OCR-based front presence + the coordinator-owned absent banner) and
///    FLIPPED these goldens, as deliberate approval-test updates, to the new
///    correct behavior: a removed document now surfaces CaptureAbsentBanner
///    instead of staying silently stuck. They carry a "CURED in PR5" marker so
///    a regression that reverts the fix is caught.
///
/// Asserts the migrated countdown structure: the leading [latchFrames] latch
/// frames are Scanning, every frame after that until the last is CountingDown,
/// and the final frame is exactly one Fire for [side]. Pins "latch → owned
/// countdown → single shutter" without a brittle literal CountingDown count.
void _expectLatchThenCountdownThenFire(
  List<String> labels, {
  required int latchFrames,
  required CaptureSide side,
}) {
  expect(labels.length, greaterThan(latchFrames + 1),
      reason: 'expected latch frames, at least one CountingDown, then a Fire');
  for (var i = 0; i < latchFrames; i++) {
    expect(labels[i], 'Scanning', reason: 'frame $i is a latch/scan frame');
  }
  expect(labels.last, 'Fire(${side.name})',
      reason: 'the dwell completes with exactly one fire at the end');
  for (var i = latchFrames; i < labels.length - 1; i++) {
    expect(labels[i], 'CountingDown',
        reason: 'frame $i is part of the owned countdown dwell');
  }
  expect(labels.where((l) => l.startsWith('Fire')).length, 1,
      reason: 'the countdown fires the shutter exactly once');
}
///
/// A realistic Peru DNI FRONT OCR block: the title anchor plus the four minimal
/// fields. `DocumentSideDetector` reads the title as `front`; the extractors
/// parse the document number and three name fields. The harness supplies this as
/// the OCR OUTPUT, above the seam.
const _frontText = 'DOCUMENTO NACIONAL DE IDENTIDAD\n'
    'DNI 16793105\n'
    'PRIMER APELLIDO\nMUÑOZ\n'
    'SEGUNDO APELLIDO\nPEREZ\n'
    'PRE NOMBRES\nJUAN CARLOS';

/// A held FRONT frame: OCR present, IMU still, sharp. The text-dense card makes
/// the native quad find text edges, not a clean card boundary, so the quad
/// degrades to false — the corners=0 device truth (#5532). The front must still
/// fire from OCR stability alone.
const _frontFrame = FrameInput(
  ocrText: _frontText,
  quadFramingValid: false,
  imuStill: true,
  isBlurry: false,
  frameWidth: 640,
  frameHeight: 480,
);

/// A held textless BACK frame: empty OCR, sustained valid quad. The only
/// readiness proof is the quad dwell routed through the empty-OCR back trigger.
const _backHeldFrame = FrameInput(
  ocrText: '',
  quadFramingValid: true,
  imuStill: true,
  isBlurry: false,
  frameWidth: 640,
  frameHeight: 480,
);

/// A back frame during a motion blip: device moving, quad flickers invalid.
const _backBlipFrame = FrameInput(
  ocrText: '',
  quadFramingValid: false,
  imuStill: false,
  isBlurry: false,
  frameWidth: 640,
  frameHeight: 480,
);

/// A document-removed frame: nothing in view, empty OCR, no quad.
const _removedFrame = FrameInput(
  ocrText: '',
  quadFramingValid: false,
  imuStill: true,
  isBlurry: false,
  frameWidth: 640,
  frameHeight: 480,
);

/// A textful-but-anchorless back frame: it carries OCR text (so it is NOT the
/// empty-OCR branch) but detects as `unknown` and fills no minimal field, so the
/// back never latches and the idle dwell accrues toward the manual escape.
const _stuckBackFrame = FrameInput(
  ocrText: 'PERU 2024',
  quadFramingValid: false,
  imuStill: true,
  isBlurry: false,
  frameWidth: 640,
  frameHeight: 480,
);

/// The bounded thresholds the golden sequences run under. They scale the dwell
/// down so the plateaus are reachable in a short, deterministic frame sequence;
/// the LOGIC under test (the readiness path) is unchanged. These exact values
/// are part of the golden contract: the pinned decision sequences below are the
/// machine's output AT these thresholds.
const _idleThreshold = 4;
const _backQuadDwell = 3;

CaptureCoordinator _twoSidedCoordinator() => CaptureCoordinator(
      fields: DniFields.minimal(),
      idleFramesThreshold: _idleThreshold,
      backQuadDwellFrames: _backQuadDwell,
    );

void main() {
  group('GOLDEN — sacred both-sides auto-capture oracle (isBackSide:null)', () {
    test(
      'the two-sided front->back device sequence emits the exact frozen '
      'decision sequence: front scans then fires once, handoff, back scans '
      'then fires once, done — through the real path with NO injected flag',
      () {
        // Two-sided mode: isBackSide is null, so the side is DETECTED from OCR
        // text on every frame — the real device mode PR3a first exercised. This
        // golden PINS that proven sequence as the frozen pre-migration gate.
        final coordinator = _twoSidedCoordinator();
        final harness = CaptureFrameSequenceHarness(coordinator);

        // PHASE 1 — FRONT. Hold the front DNI. Frame 0 detects the side and
        // latches extractingFront (Scanning); frame 1 reaches the front
        // completion floor and STARTS the owned countdown; the dwell then
        // counts down (CountingDown) and fires once it completes. Quad is false
        // the whole time, so the front fires from OCR ALONE — cures "stay still
        // after 3-2-1" (the countdown completes and fires cleanly via the
        // coordinator, no extra stillness wait, corners=0 at completion).
        final frontFire = harness.feedUntilFire(_frontFrame);
        expect(frontFire, isNotNull);
        expect(frontFire!.side, CaptureSide.front);
        _expectLatchThenCountdownThenFire(
          harness.decisionLabels,
          latchFrames: 1,
          side: CaptureSide.front,
        );
        expect(coordinator.phase, HuntPhase.extractingFront);

        final frontLabelCount = harness.decisionLabels.length;

        // PHASE 2 — HANDOFF. The device captures the front and advances to the
        // back phase: the real `_captureFront` handoff, not a state reset. The
        // coordinator clears the leftover front countdown so the back starts
        // clean (#5535).
        coordinator.advanceAfterCapture();
        expect(coordinator.phase, HuntPhase.waitingBack);

        // PHASE 3 — BACK. Flip to the textless back and hold it still. OCR is
        // empty, so this drives the empty-OCR back trigger; the sustained valid
        // quad latches then dwells to backCaptureReady, which STARTS the owned
        // countdown and fires once the dwell completes.
        final backFire = harness.feedUntilFire(_backHeldFrame);
        expect(backFire, isNotNull);
        expect(backFire!.side, CaptureSide.back);

        // PHASE 4 — DONE. The back capture completes the two-sided scan.
        coordinator.advanceAfterCapture();
        expect(coordinator.phase, HuntPhase.done);

        // The SACRED INVARIANT, end-to-end through the real path + the migrated
        // owned countdown: the front fires exactly once and the back fires
        // exactly once. The back segment is: back-latch frames → countdown →
        // single Fire(back).
        final backLabels = harness.decisionLabels.sublist(frontLabelCount);
        expect(backLabels.last, 'Fire(back)');
        expect(backLabels.where((l) => l == 'Fire(back)').length, 1);
        expect(backLabels.any((l) => l == 'CountingDown'), isTrue,
            reason: 'the back also dwells through the owned countdown');
        expect(harness.fireCount(CaptureSide.front), 1);
        expect(harness.fireCount(CaptureSide.back), 1);
      },
    );
  });

  group('GOLDEN — front-only sequences', () {
    test(
      'a single-side front (isBackSide:false), quad false the whole time, '
      'emits Scanning then Fire(front): the front is NOT blocked by quad',
      () {
        // corners=0 device truth: the quad never validates, yet the front must
        // still auto-capture from OCR stability. This is the quad-independent
        // eligibility invariant the redesign preserves.
        final coordinator = CaptureCoordinator(
          fields: DniFields.minimal(),
          isBackSide: false,
          idleFramesThreshold: _idleThreshold,
        );
        final harness = CaptureFrameSequenceHarness(coordinator);

        final fire = harness.feedUntilFire(_frontFrame);

        expect(fire, isNotNull);
        expect(fire!.side, CaptureSide.front);
        // Latch frame then the owned countdown then a single fire — the front
        // fires from OCR with the quad permanently false (quad annotates, never
        // vetoes), now through the migrated countdown.
        _expectLatchThenCountdownThenFire(
          harness.decisionLabels,
          latchFrames: 1,
          side: CaptureSide.front,
        );
      },
    );

    test(
      'CURED in PR5 (presence): a front document removed mid-sequence (front '
      'frame latched, then empty frames) surfaces the absent banner instead of '
      'staying stuck in extractingFront emitting Scanning forever',
      () {
        // DEVICE CURE (#5543), flipped from the PR3b/PR4 frozen golden as a
        // DELIBERATE approval-test update. Pre-PR5 this golden documented the
        // KNOWN BUG: once the front latched extractingFront, a genuine removal
        // (empty OCR, no quad) could not reset the machine — it stayed silently
        // stuck emitting Scanning forever and never surfaced a no-document
        // warning. PR5 migrated presence into the coordinator: front presence is
        // now OCR-document-based, so empty frames after the front latches read
        // ABSENT and the coordinator emits CaptureAbsentBanner. The widget then
        // shows the no-document banner and the user learns the card left the
        // frame. The shutter still never fires on a removed document. (Earlier
        // PRs deferred this presence symptom to the final migration; PR5 is it.)
        final coordinator = _twoSidedCoordinator();
        final harness = CaptureFrameSequenceHarness(coordinator);

        harness.feed(_frontFrame); // latches extractingFront
        for (var i = 0; i < 6; i++) {
          harness.feed(_removedFrame);
        }

        expect(
          harness.decisionLabels,
          <String>[
            'Scanning', // the front frame latches extractingFront (present)
            'AbsentBanner',
            'AbsentBanner',
            'AbsentBanner',
            'AbsentBanner',
            'AbsentBanner',
            'AbsentBanner',
          ],
          reason: 'CURED (PR5 presence): removal after the front latches now '
              'surfaces the absent banner every empty frame instead of staying '
              'silently stuck in extractingFront.',
        );
        expect(coordinator.documentPresent, isFalse);
        expect(harness.firedFor(CaptureSide.front), isFalse);
      },
    );
  });

  group('GOLDEN — back-only sequences', () {
    test(
      'a textless back with a sustained valid quad emits Scanning then '
      'Fire(back): the quad dwell fires through the real empty-OCR back trigger',
      () {
        final coordinator = CaptureCoordinator(
          fields: DniFields.minimal(),
          idleFramesThreshold: _idleThreshold,
          backQuadDwellFrames: _backQuadDwell,
          initialPhase: HuntPhase.waitingBack,
        );
        final harness = CaptureFrameSequenceHarness(coordinator);

        final fire = harness.feedUntilFire(_backHeldFrame);

        expect(fire, isNotNull);
        expect(fire!.side, CaptureSide.back);
        // Frame 0 latches extractingBack; the sustained quad then dwells for
        // backQuadDwellFrames (3) idle frames before the readiness signal STARTS
        // the owned countdown, which then counts down and fires. So the leading
        // 3 frames are Scanning (the hunt-machine quad dwell, a distinct concern
        // from the countdown), then CountingDown, then one Fire(back). The
        // hunt-machine quad dwell (3 frames) and the owned countdown are
        // SEPARATE stages — the golden pins both so a migration that collapses
        // them cannot pass silently.
        _expectLatchThenCountdownThenFire(
          harness.decisionLabels,
          latchFrames: 3,
          side: CaptureSide.back,
        );
      },
    );

    test(
      'a back without a sustained quad (textful, anchorless, no quad) does NOT '
      'fire and surfaces the manual fallback once at the idle threshold',
      () {
        // The back anchor is never confirmed and no quad frames it, so the back
        // never latches; the idle dwell accrues to the threshold and the real
        // machine emits the transient recoverManual exactly once (idle resets
        // to 0 after firing it), then resumes scanning. This is the manual
        // fallback path — never a false auto-capture.
        final coordinator = CaptureCoordinator(
          fields: DniFields.minimal(),
          idleFramesThreshold: 3,
          initialPhase: HuntPhase.waitingBack,
        );
        final harness = CaptureFrameSequenceHarness(coordinator);

        for (var i = 0; i < 5; i++) {
          harness.feed(_stuckBackFrame);
        }

        expect(
          harness.decisionLabels,
          <String>['Scanning', 'Scanning', 'Manual', 'Scanning', 'Scanning'],
          reason: 'GOLDEN: recoverManual is a transient per-cycle signal — it '
              'fires once when idle hits the threshold (frame index 2 at '
              'idleFramesThreshold:3) then idle resets.',
        );
        expect(harness.firedFor(CaptureSide.back), isFalse);
        expect(harness.firedFor(CaptureSide.front), isFalse);
      },
    );

    test(
      'a transient back quad blip does not fire: a quad that flashes valid for '
      'one frame then goes away never reaches the sustained dwell (freezes the '
      'cure for "captures when I move")',
      () {
        final coordinator = CaptureCoordinator(
          fields: DniFields.minimal(),
          idleFramesThreshold: _idleThreshold,
          backQuadDwellFrames: _backQuadDwell,
          initialPhase: HuntPhase.waitingBack,
        );
        final harness = CaptureFrameSequenceHarness(coordinator);

        // One valid quad latches extractingBack; then sustained motion keeps
        // the quad invalid, so every firing frame fails the framing floor and
        // the machine never emits backCaptureReady.
        harness.feed(_backHeldFrame);
        for (var i = 0; i < 12; i++) {
          harness.feed(_backBlipFrame);
        }

        expect(
          harness.firedFor(CaptureSide.back),
          isFalse,
          reason: 'GOLDEN: a one-frame quad blip is motion noise, not a '
              'sustained framed card; the dwell rejects it.',
        );
        // No frame in the whole blip sequence ever fired.
        expect(
          harness.decisionLabels.where((l) => l.startsWith('Fire')),
          isEmpty,
        );
      },
    );
  });

  group('GOLDEN — removed document (empty OCR, no quad)', () {
    test(
      'a removed document in the back phase never fires and surfaces the absent '
      'banner every frame (PR5 presence)',
      () {
        // PR5 (presence migration, deliberate approval update): an empty-OCR
        // frame with no quad in the back phase has NO document in view, so the
        // coordinator now surfaces CaptureAbsentBanner instead of a silent
        // Scanning. The invariant the golden protects is unchanged — the shutter
        // never fires and there is no false presence — but the absence is now
        // EXPLICIT so the widget can warn the user the document is gone (#5540).
        final coordinator = CaptureCoordinator(
          fields: DniFields.minimal(),
          idleFramesThreshold: _idleThreshold,
          backQuadDwellFrames: _backQuadDwell,
          initialPhase: HuntPhase.waitingBack,
        );
        final harness = CaptureFrameSequenceHarness(coordinator);

        for (var i = 0; i < 10; i++) {
          harness.feed(_removedFrame);
        }

        expect(
          harness.decisionLabels,
          List<String>.filled(10, 'AbsentBanner'),
          reason: 'GOLDEN (PR5): empty OCR with no quad in the back phase is '
              'absent every frame — no fire, no false presence, an explicit '
              'no-document banner.',
        );
        expect(coordinator.documentPresent, isFalse);
        expect(harness.firedFor(CaptureSide.back), isFalse);
        expect(harness.firedFor(CaptureSide.front), isFalse);
      },
    );
  });
}
