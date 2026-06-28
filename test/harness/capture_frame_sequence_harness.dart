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
  CaptureFrameSequenceHarness(this.coordinator);

  final CaptureCoordinator coordinator;

  /// Every decision the coordinator emitted, in frame order.
  final List<CaptureDecision> decisions = <CaptureDecision>[];

  /// Feeds one frame and records the decision.
  CaptureDecision feed(FrameInput input) {
    final decision = coordinator.onFrame(input);
    decisions.add(decision);
    return decision;
  }

  /// Feeds the same frame [count] times, simulating the document being held in
  /// front of the camera at a steady cadence (a sustained plateau or hold).
  /// Stops early and returns the [CaptureFire] the moment the real machine
  /// emits one, mirroring how the live stream stops feeding once the shutter
  /// is triggered.
  CaptureFire? feedUntilFire(FrameInput input, {int maxFrames = 40}) {
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
      CaptureFire(side: final side) => 'Fire(${side.name})',
      CaptureManualAvailable() => 'Manual',
    };
