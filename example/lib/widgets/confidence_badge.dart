import 'package:flutter/material.dart';

/// Small color-graded chip that visualizes a `confidence` value in `[0.0, 1.0]`.
///
/// The badge maps confidence to one of three colors:
/// * red for confidences below 0.5,
/// * amber for 0.5–0.8,
/// * green for above 0.8.
///
/// Use it next to a value to give the reader an instant read of how much the
/// library trusts the OCR consensus for that field.
class ConfidenceBadge extends StatelessWidget {
  const ConfidenceBadge({
    super.key,
    required this.confidence,
  });

  /// Confidence value in `[0.0, 1.0]`.
  final double confidence;

  Color _backgroundFor(ColorScheme colors) {
    if (confidence < 0.5) return colors.errorContainer;
    if (confidence < 0.8) return colors.tertiaryContainer;
    return colors.primaryContainer;
  }

  Color _foregroundFor(ColorScheme colors) {
    if (confidence < 0.5) return colors.onErrorContainer;
    if (confidence < 0.8) return colors.onTertiaryContainer;
    return colors.onPrimaryContainer;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final percentage = (confidence.clamp(0.0, 1.0) * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _backgroundFor(colors),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$percentage%',
        style: TextStyle(
          color: _foregroundFor(colors),
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
