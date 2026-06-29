import 'package:dni_peru_ocr/src/domain/extraction/dni_fields.dart';
import 'package:dni_peru_ocr/src/domain/extraction/hunt_state_machine.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_coordinator.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_decision.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/frame_input.dart';
import 'package:flutter_test/flutter_test.dart';

import 'capture_frame_sequence_harness.dart';

/// A realistic Peru DNI FRONT OCR block: the title anchor plus the four minimal
/// fields. DocumentSideDetector reads the title as `front`; the extractors parse
/// the document number and three name fields. This is what ML Kit produces for a
/// front frame — the harness supplies it as the OCR OUTPUT, above the seam.
const _frontText = 'DOCUMENTO NACIONAL DE IDENTIDAD\n'
    'DNI 16793105\n'
    'PRIMER APELLIDO\nMUÑOZ\n'
    'SEGUNDO APELLIDO\nPEREZ\n'
    'PRE NOMBRES\nJUAN CARLOS';

/// A held front frame: OCR text present, IMU still, sharp. The text-dense card
/// makes the native quad find text edges, not a clean card boundary, so the
/// quad degrades to false — exactly the corners=0 device truth (#5532). The
/// front must still fire from OCR stability.
FrameInput _frontFrame() => const FrameInput(
      ocrText: _frontText,
      quadFramingValid: false,
      imuStill: true,
      isBlurry: false,
      frameWidth: 640,
      frameHeight: 480,
    );

/// A held textless BACK frame: the Peru DNI back carries almost no OCR text, so
/// OCR is empty; the only readiness proof is a sustained valid quad. This is the
/// frame the OCR path alone can never trigger — it must route through the
/// empty-OCR back trigger and fire from the real quad dwell.
FrameInput _backHeldFrame() => const FrameInput(
      ocrText: '',
      quadFramingValid: true,
      imuStill: true,
      isBlurry: false,
      frameWidth: 640,
      frameHeight: 480,
    );

/// A back frame during a motion blip: the device is moving, so the quad flickers
/// invalid this frame. A 1–2 frame blip must NOT satisfy the sustained dwell —
/// this is the "captures when I move" symptom the dwell guards against (#5543).
FrameInput _backBlipFrame() => const FrameInput(
      ocrText: '',
      quadFramingValid: false,
      imuStill: false,
      isBlurry: false,
      frameWidth: 640,
      frameHeight: 480,
    );

/// A document-removed frame: nothing in view, so OCR is empty and there is no
/// quad. The machine must not fire and must not claim presence.
FrameInput _removedFrame() => const FrameInput(
      ocrText: '',
      quadFramingValid: false,
      imuStill: true,
      isBlurry: false,
      frameWidth: 640,
      frameHeight: 480,
    );

void main() {
  group('Device-faithful two-sided capture harness (isBackSide:null)', () {
    test(
      'a front->back device sequence fires the front once then the back once, '
      'driven entirely through the real path with NO injected flag',
      () {
        // Two-sided mode: isBackSide is null, so the side is DETECTED from the
        // OCR text on every frame — the real device mode that ZERO prior tests
        // exercised (#5545). Thresholds scaled down so the dwell is reachable
        // in a bounded test sequence; the LOGIC under test is unchanged.
        final coordinator = CaptureCoordinator(
          fields: DniFields.minimal(),
          idleFramesThreshold: 4,
          backQuadDwellFrames: 3,
        );
        final harness = CaptureFrameSequenceHarness(coordinator);

        // 1) FRONT: hold the front DNI. The title anchor latches
        // extractingFront, then OCR stability emits frontCaptureReady — the
        // quad is false the whole time (text-dense card), so the front fires
        // from OCR ALONE. No debugFeedCaptureReady anywhere.
        final frontFire = harness.feedUntilFire(_frontFrame());
        expect(
          frontFire,
          isNotNull,
          reason: 'the front must fire from OCR stability through the real '
              'DocumentSideDetector + FieldHunter + HuntStateMachine chain',
        );
        expect(frontFire!.side, CaptureSide.front);
        expect(coordinator.phase, HuntPhase.extractingFront);

        // 2) HANDOFF: the device captures the front and advances to the back
        // phase — the real `_captureFront` handoff, not a state reset.
        coordinator.advanceAfterCapture();
        expect(
          coordinator.phase,
          HuntPhase.waitingBack,
          reason: 'the front handoff must advance the machine to the back phase',
        );

        // 3) BACK: flip to the textless back and hold it still. OCR is empty,
        // so this drives the empty-OCR back trigger; the sustained valid quad
        // latches and dwells through the REAL machine to backCaptureReady.
        final backFire = harness.feedUntilFire(_backHeldFrame());
        expect(
          backFire,
          isNotNull,
          reason: 'the textless back must fire from a sustained valid quad '
              'through the real empty-OCR back trigger, with no injected flag',
        );
        expect(backFire!.side, CaptureSide.back);

        // 4) DONE: the back capture completes the two-sided scan.
        coordinator.advanceAfterCapture();
        expect(coordinator.phase, HuntPhase.done);

        // The whole device sequence fired exactly one front and one back —
        // the SACRED both-sides oracle, proven through the real path.
        expect(harness.fireCount(CaptureSide.front), 1);
        expect(harness.fireCount(CaptureSide.back), 1);
      },
    );

    test(
      'a transient back quad blip does not fire: a quad that flashes valid for '
      'one frame then goes away never reaches the sustained dwell (cures '
      '"captures when I move")',
      () {
        final coordinator = CaptureCoordinator(
          fields: DniFields.minimal(),
          idleFramesThreshold: 4,
          backQuadDwellFrames: 3,
          initialPhase: HuntPhase.waitingBack,
        );
        final harness = CaptureFrameSequenceHarness(coordinator);

        // One valid quad frame latches extractingBack — the device caught a
        // momentary clean boundary while the card was moving. Then the motion
        // continues and the quad stays invalid: every subsequent frame fails
        // the framing floor on the firing frame, so the real machine never
        // emits backCaptureReady. A single blip riding motion noise must not
        // fire (#5543).
        harness.feed(_backHeldFrame());
        for (var i = 0; i < 12; i++) {
          harness.feed(_backBlipFrame());
        }

        expect(
          harness.firedFor(CaptureSide.back),
          isFalse,
          reason: 'a one-frame quad blip is motion noise, not a sustained '
              'framed card; the dwell must reject it',
        );
      },
    );

    test(
      'a removed document (empty OCR, no quad) never fires and surfaces the '
      'absent banner (PR5 presence)',
      () {
        // PR5 (presence migration): a removed document — empty OCR with no quad
        // — has nothing in view, so the coordinator now surfaces
        // CaptureAbsentBanner instead of a silent Scanning. It still never fires
        // the shutter; the absence is now explicit so the widget can warn the
        // user the document left the frame (#5540/#5543).
        final coordinator = CaptureCoordinator(
          fields: DniFields.minimal(),
          idleFramesThreshold: 4,
          backQuadDwellFrames: 3,
          initialPhase: HuntPhase.waitingBack,
        );
        final harness = CaptureFrameSequenceHarness(coordinator);

        for (var i = 0; i < 10; i++) {
          final decision = harness.feed(_removedFrame());
          expect(decision, isA<CaptureAbsentBanner>());
        }

        expect(coordinator.documentPresent, isFalse);
        expect(harness.firedFor(CaptureSide.back), isFalse);
        expect(harness.firedFor(CaptureSide.front), isFalse);
      },
    );
  });

  group('Harness purity guard (the seam stays above OCR)', () {
    test(
      'the harness exposes no debug-injection entry points and drives only '
      'FrameInput through the real coordinator',
      () {
        // This is a structural assertion that the harness fires through the
        // real path: feeding realistic FrameInput produces a real fire, which
        // is only reachable if DocumentSideDetector + FieldHunter +
        // HuntStateMachine actually ran. A flag-injected seam could not satisfy
        // this from ocrText alone.
        final coordinator = CaptureCoordinator(
          fields: DniFields.minimal(),
          idleFramesThreshold: 4,
        );
        final harness = CaptureFrameSequenceHarness(coordinator);

        final fire = harness.feedUntilFire(_frontFrame());

        expect(fire, isNotNull);
        expect(fire!.side, CaptureSide.front);
        expect(
          harness.decisions.first,
          isA<CaptureScanning>(),
          reason: 'the first frame only detects the side; the fire emerges '
              'later from accumulated OCR stability — proof the machine ran',
        );
      },
    );
  });
}
