import 'package:flutter/material.dart';

import '../domain/entities/validation_gate.dart';
import 'theme/kyc_theme.dart';

/// Maps a [ValidationGate] to its border [Color].
abstract final class ValidationGateColors {
  static Color colorFor(ValidationGate? gate, KycTheme theme) => switch (gate) {
        null => theme.success,
        ValidationGate.minBlocks => theme.white,
        ValidationGate.centering => theme.accentOrange,
        ValidationGate.fillHigh => theme.accentOrange,
        ValidationGate.fillLow => theme.accentOrange,
        ValidationGate.lineCount => theme.white,
        ValidationGate.tilt => theme.accentOrange,
        ValidationGate.sideMismatch => theme.accentOrange,
      };
}
