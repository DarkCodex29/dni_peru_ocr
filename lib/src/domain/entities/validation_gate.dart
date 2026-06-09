/// Identifies which document quality gate rejected a capture frame.
///
/// All values map to stable Sentry breadcrumb codes via [sentryCode].
/// Do NOT translate or rename these codes — Sentry filters depend on them.
///
/// When [DocumentValidationResult.failingGate] is `null`, the frame passed
/// all gates and is capturable.
enum ValidationGate {
  /// Fewer recognized OCR blocks than the required minimum.
  minBlocks,

  /// Group bounding box was not contained within the padded hole area.
  centering,

  /// Fill ratio exceeded the upper bound — document is too close.
  fillHigh,

  /// Fill ratio fell below the lower bound — document is too far.
  fillLow,

  /// Fewer than 5 OCR blocks — not enough text signal for tilt computation.
  lineCount,

  /// Median tilt angle exceeded the maximum allowed degrees.
  tilt,

  /// MRZ detected while the front side was expected — user is showing the back.
  sideMismatch;

  /// Stable Sentry breadcrumb code for this gate.
  ///
  /// These strings are intentionally ASCII-safe and match the codes used in
  /// existing Sentry dashboards and alert filters. Do NOT change them.
  String get sentryCode => switch (this) {
        ValidationGate.minBlocks => 'min_blocks',
        ValidationGate.centering => 'centering',
        ValidationGate.fillHigh => 'fill_high',
        ValidationGate.fillLow => 'fill_low',
        ValidationGate.lineCount => 'line_count',
        ValidationGate.tilt => 'tilt',
        ValidationGate.sideMismatch => 'side_mismatch',
      };
}
