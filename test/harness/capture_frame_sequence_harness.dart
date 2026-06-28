import 'package:dni_peru_ocr/src/presentation/coordinators/capture_coordinator.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/capture_decision.dart';
import 'package:dni_peru_ocr/src/presentation/coordinators/frame_input.dart';

/// Device-faithful frame-sequence harness — the seam that closes the 6x test
/// blind spot (#5545).
///
/// It drives a sequence of [FrameInput] frames (built from realistic OCR
/// strings, a quad framing flag, IMU stillness, and blur) through the REAL
/// [CaptureCoordinator] readiness path: `DocumentSideDetector.detect` →
/// `FieldHunter.process` → `HuntStateMachine.recordFrame` → decision. The seam
/// sits ABOVE OCR, so ML Kit is mocked at its OUTPUT (the harness supplies the
/// recognized text) while the side-detect → hunt → coordinate logic is 100%
/// REAL.
///
/// HARD CONTRACT: this harness NEVER uses `debugFeedCaptureReady`,
/// `debugSetFramingValid`, `debugSetFrameCaptureable`, `debugResetToScanning`,
/// or a single-side `isBackSide:true` shortcut to manufacture a readiness
/// signal. Every [CaptureFire] it records is one the real machine emitted from
/// the supplied frame inputs. If a readiness decision could only be produced by
/// injecting a flag, the seam would have landed BELOW OCR — the failure mode —
/// and these tests would not fire.
class CaptureFrameSequenceHarness {
  CaptureFrameSequenceHarness(
    this.coordinator, {
    DateTime? startedAt,
    this.frameIntervalMs = 250,
  }) : _clock = startedAt ?? DateTime(2026, 1, 1, 12);

  final CaptureCoordinator coordinator;

  /// The per-frame wall-clock advance the harness stamps onto each fed frame.
  /// PR4 moved the countdown/dwell into the coordinator, where it is measured
  /// against [FrameInput.now]. The harness models the live camera cadence by
  /// advancing this clock every [feed], so a sustained hold accrues real dwell
  /// time across frames and the migrated countdown completes — no real `Timer`.
  final int frameIntervalMs;

  DateTime _clock;

  /// Every decision the coordinator emitted, in frame order.
  final List<CaptureDecision> decisions = <CaptureDecision>[];

  /// Feeds one frame and records the decision. The harness advances its clock
  /// and stamps it onto the frame, so the coordinator's owned countdown dwells
  /// against a deterministic, monotonically-advancing time.
  CaptureDecision feed(FrameInput input) {
    final stamped = _stamp(input);
    final decision = coordinator.onFrame(stamped);
    decisions.add(decision);
    _clock = _clock.add(Duration(milliseconds: frameIntervalMs));
    return decision;
  }

  FrameInput _stamp(FrameInput input) => FrameInput(
        ocrText: input.ocrText,
        quadFramingValid: input.quadFramingValid,
        imuStill: input.imuStill,
        isBlurry: input.isBlurry,
        frameWidth: input.frameWidth,
        frameHeight: input.frameHeight,
        now: _clock,
      );

  /// Feeds the same frame repeatedly, simulating the document being held in
  /// front of the camera at a steady cadence (a sustained plateau or hold), and
  /// advancing the clock each frame so the owned countdown dwells. Stops early
  /// and returns the [CaptureFire] the moment the real coordinator completes the
  /// dwell, mirroring how the live stream stops feeding once the shutter fires.
  CaptureFire? feedUntilFire(FrameInput input, {int maxFrames = 60}) {
    for (var i = 0; i < maxFrames; i++) {
      final decision = feed(input);
      if (decision is CaptureFire) return decision;
    }
    return null;
  }

  /// Whether any recorded decision was a fire for [side].
  bool firedFor(CaptureSide side) => decisions
      .whereType<CaptureFire>()
      .any((fire) => fire.side == side);

  /// How many fires for [side] the sequence produced.
  int fireCount(CaptureSide side) => decisions
      .whereType<CaptureFire>()
      .where((fire) => fire.side == side)
      .length;

  /// The recorded decisions mapped to stable, human-readable labels in frame
  /// order. Golden characterization tests assert this exact sequence so a later
  /// migration that changes the timing, order, or kind of any decision trips a
  /// golden immediately — not just a changed fire count.
  List<String> get decisionLabels =>
      decisions.map(captureDecisionLabel).toList();
}

/// Maps a [CaptureDecision] to the stable label the golden oracle pins.
/// A [CaptureFire] carries its side so a front/back swap is caught.
String captureDecisionLabel(CaptureDecision decision) => switch (decision) {
      CaptureScanning() => 'Scanning',
      CaptureCountingDown() => 'CountingDown',
      CaptureFire(side: final side) => 'Fire(${side.name})',
      CaptureReset() => 'Reset',
      CaptureManualAvailable() => 'Manual',
    };
