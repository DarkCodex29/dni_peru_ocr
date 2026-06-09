import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Computes the median tilt angle (in degrees) of recognized text lines.
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

      if (normalized.abs() > 45.0) continue;

      angles.add(normalized);
    }
  }

  if (angles.length < 3) return 0;

  return _median(angles);
}

double _normalizeTo90(double deg) {
  var d = deg % 360;
  if (d > 180) d -= 360;
  if (d <= -180) d += 360;

  if (d > 90) return d - 180;
  if (d < -90) return d + 180;
  return d;
}

double _median(List<double> values) {
  final sorted = List<double>.from(values)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Returns the median MLKit-reported angle, or `null` when unavailable.
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
