import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Computes the median tilt angle (in degrees) of recognized text lines.
///
/// Returns `0` when no lines are present or angles are inconclusive.
///
/// ### How it works
/// For each [TextLine] in every block, the angle of the top edge is derived
/// from the corner points provided by MLKit:
/// ```plaintext
/// angle = atan2(TR.y - TL.y, TR.x - TL.x) * 180 / π
/// ```
/// where `TL = cornerPoints[0]` and `TR = cornerPoints[1]`.
///
/// The **median** (not mean) is returned to make the result robust against
/// outlier angles from logo text, fingers, or partial reads.
///
/// Angles are normalized to the `[-90°, +90°]` range so that a 180°-flipped
/// document does not register as extreme tilt.
double computeMedianTiltDegrees(RecognizedText recognized) {
  final angles = <double>[];

  for (final block in recognized.blocks) {
    for (final line in block.lines) {
      final pts = line.cornerPoints;
      if (pts.length < 2) continue;

      final tl = pts[0];
      final tr = pts[1];

      final angleDeg = math.atan2(tr.y - tl.y, tr.x - tl.x) * 180 / math.pi;

      final normalized = _normalizeTo90(angleDeg);

      // Only count mostly-horizontal lines (|angle| ≤ 45°).
      // Stamps, logos and decorative text produce near-vertical angles
      // that corrupt the median on an otherwise flat document.
      if (normalized.abs() > 45.0) continue;

      angles.add(normalized);
    }
  }

  // Fewer than 3 horizontal lines → not enough signal to judge tilt;
  // return 0 so the validator skips the tilt check rather than blocking.
  if (angles.length < 3) return 0;

  return _median(angles);
}

/// Normalizes [deg] to the `[-90°, +90°]` range.
///
/// A 180°-flipped reading (e.g. 180° or -180°) maps to 0°.
/// A 100° reading maps to -80° (equivalent horizontal tilt).
double _normalizeTo90(double deg) {
  // Bring into (-180, 180].
  var d = deg % 360;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;

  // Mirror values outside [-90, 90].
  if (d > 90) return d - 180;
  if (d < -90) return d + 180;
  return d;
}

/// Returns the median value of a non-empty list of doubles.
double _median(List<double> values) {
  final sorted = List<double>.from(values)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Returns the median of `TextLine.angle` values across every line in
/// [recognized], or `null` when no line provides a non-null angle.
///
/// This is a **diagnostic-only** signal used by the G.1 telemetry overlay
/// to compare the MLKit-provided angle against the cornerPoints-derived
/// angle produced by [computeMedianTiltDegrees]. Divergence between the
/// two pinpoints which half of the tilt pipeline is producing noise.
///
/// On iOS, MLKit does not populate `TextLine.angle` — this function will
/// return `null` and the overlay should render `mlkit_angle: -` in that
/// case.
///
/// Not used for any production gate.
double? computeMlkitMedianAngleDegrees(RecognizedText recognized) {
  final angles = <double>[];
  for (final block in recognized.blocks) {
    for (final line in block.lines) {
      final a = line.angle;
      if (a != null) angles.add(a);
    }
  }
  if (angles.isEmpty) return null;
  return _median(angles);
}
