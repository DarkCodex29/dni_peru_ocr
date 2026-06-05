import 'package:flutter/material.dart';

import '../domain/entities/validation_gate.dart';
import 'theme/kyc_theme.dart';

/// Maps a [ValidationGate] (or `null` when capturable) to a visual [Color].
///
/// Lives in the presentation layer so the domain stays free of Flutter types.
///
/// Usage:
/// ```dart
/// final borderColor = ValidationGateColors.colorFor(result.failingGate, theme);
/// ```
///
/// The switch expression is exhaustive — adding a new [ValidationGate] value
/// without updating this file produces a compile-time error.
abstract final class ValidationGateColors {
  /// Returns the border color for [gate] using the provided [theme] tokens.
  ///
  /// - `null` (capturable) → [KycTheme.success]
  /// - Warning gates (position/fill/tilt) → [KycTheme.accentOrange]
  /// - Info gates (not enough blocks) → [KycTheme.white]
  static Color colorFor(ValidationGate? gate, KycTheme theme) => switch (gate) {
        null => theme.success,
        ValidationGate.minBlocks => theme.white,
        ValidationGate.centering => theme.accentOrange,
        ValidationGate.fillHigh => theme.accentOrange,
        ValidationGate.fillLow => theme.accentOrange,
        ValidationGate.lineCount => theme.white,
        ValidationGate.tilt => theme.accentOrange,
      };
}
