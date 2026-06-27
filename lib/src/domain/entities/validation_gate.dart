enum ValidationGate {
  minBlocks,
  centering,
  fillHigh,
  fillLow,
  lineCount,
  tilt,
  sideMismatch,
  lighting,
  glare,
  quad;

  String get sentryCode => switch (this) {
        ValidationGate.minBlocks => 'min_blocks',
        ValidationGate.centering => 'centering',
        ValidationGate.fillHigh => 'fill_high',
        ValidationGate.fillLow => 'fill_low',
        ValidationGate.lineCount => 'line_count',
        ValidationGate.tilt => 'tilt',
        ValidationGate.sideMismatch => 'side_mismatch',
        ValidationGate.lighting => 'lighting',
        ValidationGate.glare => 'glare',
        ValidationGate.quad => 'quad',
      };
}
