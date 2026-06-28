import 'package:dni_peru_ocr/src/domain/extraction/dni_fields.dart';
import 'package:dni_peru_ocr/src/domain/extraction/hunt_state_machine.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_coordinator.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_decision.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/frame_input.dart';
import 'package:flutter_test/flutter_test.dart';

import 'capture_frame_sequence_harness.dart';

/// GOLDEN CAPTURE ORACLE — capture-redesign PR3b.
///
/// This file FREEZES the exact current capture behavior as a set of golden
/// characterization tests, driven entirely through the PR3a device-faithful
/// harness (the REAL DocumentSideDetector → FieldHunter → HuntStateMachine
/// chain), with NO debug-flag injection. It is the regression gate placed
/// BEFORE the PR4/PR5 logic migration: once the god-object countdown/dwell/
/// presence logic moves into the [CaptureCoordinator], ANY deviation from the
/// decisions pinned here trips a golden immediately.
///
/// Golden granularity: each test asserts the EXACT [CaptureDecision] sequence
/// (via [CaptureFrameSequenceHarness.decisionLabels]) the real path emits for a
/// realistic frame sequence — not merely a fire count — so a migration that
/// changes timing, ordering, or the kind of any decision is caught.
///
/// Two classes of golden live here:
///  - PINNED-FOREVER goldens (the sacred both-sides oracle, front/back happy
///    paths, the motion-blip rejection) describe behavior that MUST be
///    preserved across the migration.
///  - "CURRENT BEHAVIOR — to be changed in PR4/PR5" goldens describe behavior
///    that is a KNOWN device bug today (false-absent presence, stuck-after-
///    removal). They are frozen here so PR4/PR5 must INTENTIONALLY update them
///    as approval tests rather than changing device behavior silently.
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
        // completion floor and fires. Quad is false the whole time, so the
        // front fires from OCR ALONE.
        final frontFire = harness.feedUntilFire(_frontFrame);
        expect(frontFire, isNotNull);
        expect(frontFire!.side, CaptureSide.front);
        expect(
          harness.decisionLabels,
          <String>['Scanning', 'Fire(front)'],
          reason: 'GOLDEN: the front fires on the second held frame via OCR '
              'stability; frame 0 only detects the side.',
        );
        expect(coordinator.phase, HuntPhase.extractingFront);

        // PHASE 2 — HANDOFF. The device captures the front and advances to the
        // back phase: the real `_captureFront` handoff, not a state reset.
        coordinator.advanceAfterCapture();
        expect(coordinator.phase, HuntPhase.waitingBack);

        // PHASE 3 — BACK. Flip to the textless back and hold it still. OCR is
        // empty, so this drives the empty-OCR back trigger; the sustained valid
        // quad latches (Scanning) then dwells to backCaptureReady (Fire).
        final backFire = harness.feedUntilFire(_backHeldFrame);
        expect(backFire, isNotNull);
        expect(backFire!.side, CaptureSide.back);

        // PHASE 4 — DONE. The back capture completes the two-sided scan.
        coordinator.advanceAfterCapture();
        expect(coordinator.phase, HuntPhase.done);

        // The full device sequence, frozen end-to-end: front detect → front
        // fire → back latch → back fire. This is the SACRED both-sides oracle.
        expect(
          harness.decisionLabels,
          <String>['Scanning', 'Fire(front)', 'Scanning', 'Fire(back)'],
          reason: 'GOLDEN: the sacred both-sides sequence. Any migration that '
              'reorders, retimes, or changes these decisions must update this '
              'golden deliberately.',
        );
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
        expect(
          harness.decisionLabels,
          <String>['Scanning', 'Fire(front)'],
          reason: 'GOLDEN: front-only fires from OCR with quad permanently '
              'false — quad annotates, never vetoes.',
        );
      },
    );

    test(
      'CURRENT BEHAVIOR — to be changed in PR4/PR5: a front document removed '
      'mid-sequence (front frame latched, then empty frames) stays stuck in '
      'extractingFront emitting Scanning forever — it does NOT reset and does '
      'NOT surface an absent decision',
      () {
        // The empty-OCR FRONT route is skipped today (only a quad-confirmed
        // back drives the empty-OCR trigger), so once the front has latched
        // extractingFront a genuine removal cannot reset the machine. The
        // presence-banner / reset logic still lives in DniScannerState and is
        // not yet eligibility-based — this is the false-absent / stuck-on-
        // removal symptom the spec defers to the presence migration.
        //
        // This golden FREEZES that buggy-on-device truth so PR4/PR5 must flip
        // it to a Reset/AbsentBanner decision INTENTIONALLY (as an approval
        // test update), never silently.
        final coordinator = _twoSidedCoordinator();
        final harness = CaptureFrameSequenceHarness(coordinator);

        harness.feed(_frontFrame); // latches extractingFront
        for (var i = 0; i < 6; i++) {
          harness.feed(_removedFrame);
        }

        expect(
          harness.decisionLabels,
          <String>[
            'Scanning',
            'Scanning',
            'Scanning',
            'Scanning',
            'Scanning',
            'Scanning',
            'Scanning',
          ],
          reason: 'CURRENT (to be changed in PR4/PR5): removal after the front '
              'latches never resets — the machine stays in extractingFront. '
              'PR4/PR5 must update this golden to a reset/absent decision.',
        );
        expect(coordinator.phase, HuntPhase.extractingFront);
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
        // Frame 0 latches extractingBack (Scanning); the sustained quad then
        // dwells for backQuadDwellFrames (3) idle frames before firing. This
        // fresh-waitingBack dwell is LONGER than the two-sided post-handoff
        // path, where the handoff arrives mid-dwell — a real distinction the
        // golden pins so a migration that collapses the two cannot pass silently.
        expect(
          harness.decisionLabels,
          <String>['Scanning', 'Scanning', 'Scanning', 'Fire(back)'],
          reason: 'GOLDEN: a fresh waitingBack latches on frame 0 then dwells '
              'backQuadDwellFrames before firing.',
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
      'a removed document in the back phase never fires and stays Scanning '
      'every frame',
      () {
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
          List<String>.filled(10, 'Scanning'),
          reason: 'GOLDEN: empty OCR with no quad in the back phase is skipped '
              'every frame — no fire, no false presence.',
        );
        expect(harness.firedFor(CaptureSide.back), isFalse);
        expect(harness.firedFor(CaptureSide.front), isFalse);
      },
    );
  });
}
