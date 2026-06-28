/// One normalized per-frame input fed to [CaptureCoordinator.onFrame].
///
/// This is the device-faithful HARNESS SEAM struct. It sits ABOVE OCR: it
/// carries the already-recognized [ocrText] (so ML Kit is mocked at its OUTPUT,
/// not its input), plus the quad framing flag and the gate readings the live
/// per-frame path computes. A test constructs a sequence of these from realistic
/// strings — a real front DNI block, a textless back, a removed document — and
/// drives them through the REAL DocumentSideDetector + FieldHunter +
/// HuntStateMachine chain, with no `CameraImage` and no injected capture signal.
///
/// Pure Dart: no Flutter, no dartcv. It carries already-computed values, not the
/// computations themselves, so it stays trivially testable and layer-clean.
class FrameInput {
  const FrameInput({
    required this.ocrText,
    this.quadFramingValid = false,
    this.imuStill = true,
    this.isBlurry = false,
    this.frameWidth = 0,
    this.frameHeight = 0,
  });

  /// The recognized OCR text for this frame, exactly as the live widget joins
  /// the ML Kit recognized blocks. Empty for a textless back or a removed
  /// document. The seam is ABOVE OCR, so the harness supplies this directly.
  final String ocrText;

  /// The raw quad framing flag from the quad-detection isolate (non-blocking
  /// annotation). May be false on the text-dense front even when the DNI is
  /// present, and may be `corners=0` unsolved CV (#5532); it never vetoes.
  final bool quadFramingValid;

  /// Whether the IMU reports the device is held still this frame.
  final bool imuStill;

  /// Whether this frame was judged too blurry to capture.
  final bool isBlurry;

  /// Source frame width in pixels (carried for downstream quad/rectify use).
  final int frameWidth;

  /// Source frame height in pixels (carried for downstream quad/rectify use).
  final int frameHeight;
}
