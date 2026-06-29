/// One value type that unifies the four side-aware quad reads in
/// `DniScannerState` (#5543) so every call site reads a single source.
///
/// The quad framing flag is a non-blocking ANNOTATION: it raises confidence and
/// enables rectify, but it NEVER vetoes capture. The blocking readiness signal
/// is [captureEligible], sourced from OCR/stability/side-safety via
/// `HuntStateMachine`. [isFrontPhase] selects the side-aware behavior the two
/// sides require, because the front proves a framed document through OCR while
/// the textless back proves it through the quad.
///
/// Each accessor reproduces, byte-for-byte, the fork it replaces:
/// - [fireFramingValid] — `DniScannerState._fireFramingValid`.
/// - [documentPresent] — the top-level `documentPresent` predicate.
/// - [quadFramingValid] — the raw `_framingValid` overlay read.
/// - [dispatchEmptyOcrBackTrigger] — `resolveEmptyOcrRoute`.
///
/// Pure Dart: no Flutter, no dartcv. It carries already-computed values, not the
/// computations themselves, so it stays trivially testable and layer-clean.
class FramingSignal {
  const FramingSignal({
    required this.framingValid,
    required this.captureEligible,
    required this.isFrontPhase,
  });

  /// The raw quad framing flag from the quad-detection isolate (non-blocking
  /// annotation). May be false on the text-dense front even when the DNI is
  /// present, and may be `corners=0` unsolved CV (#5532).
  final bool framingValid;

  /// The OCR-derived capture-readiness for this frame (BLOCKING): true when the
  /// latest frame yielded a capture-ready / side-detected signal, false on a
  /// `none`/dropped frame.
  final bool captureEligible;

  /// Whether the machine is in a front phase (`waitingFront`/`extractingFront`).
  final bool isFrontPhase;

  /// Side-aware framing value fed to the capture orchestrator (#5543). The front
  /// degrades framing OPEN (OCR readiness already implies a framed document), so
  /// the strict quad gate never vetoes the front shutter; the back keeps the
  /// strict live quad gate because the quad is its only readiness proof.
  bool get fireFramingValid => isFrontPhase ? true : framingValid;

  /// Whether a document is present and framed this frame (#5540/#5543). The
  /// front trusts the OCR-eligibility signal (its quad degrades to false on the
  /// text-dense card); the back trusts the strict quad-and-eligibility
  /// conjunction.
  bool get documentPresent =>
      isFrontPhase ? captureEligible : (framingValid && captureEligible);

  /// The raw quad framing flag for the overlay annotation — the same value the
  /// overlay read directly off `_framingValid` before unification.
  bool get quadFramingValid => framingValid;

  /// Whether an empty-OCR frame must drive the back trigger (#5523). True only
  /// when the quad confirms framing AND the machine has left the front phase; a
  /// blank frame with no quad, or a front phase, routes to skip.
  bool get dispatchEmptyOcrBackTrigger => framingValid && !isFrontPhase;
}
