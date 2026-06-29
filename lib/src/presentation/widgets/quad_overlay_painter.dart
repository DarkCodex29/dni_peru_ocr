import 'package:flutter/widgets.dart';

import '../../domain/capture/document_quad_detector.dart';

export '../../domain/capture/document_quad_detector.dart' show QuadCorner;

/// Maps detected quad [corners] from analysis frame-pixel space into preview
/// widget space.
///
/// The transform mirrors what `CameraPreview` does on screen, in this order:
/// 1. Rotate the sensor frame upright by [rotationDegrees] (clockwise), so a
///    landscape sensor buffer becomes the portrait image the user sees.
/// 2. Scale and center the upright frame into [previewSize] with `BoxFit.cover`
///    (the same fit `CameraPreview` uses), so the long axis overflows and is
///    cropped symmetrically.
/// 3. Optionally [mirror] horizontally across the preview's vertical axis, for
///    front-facing sensors whose preview is reflected.
///
/// Returns an empty list when [corners] is empty. This is a pure function with
/// no Flutter painting side effects, so it is unit-testable in isolation.
List<Offset> mapQuadToPreview({
  required List<QuadCorner> corners,
  required int frameWidth,
  required int frameHeight,
  required int rotationDegrees,
  required Size previewSize,
  required bool mirror,
}) {
  if (corners.isEmpty) return const <Offset>[];

  final normalized = ((rotationDegrees % 360) + 360) % 360;
  final w = frameWidth.toDouble();
  final h = frameHeight.toDouble();

  // Upright dimensions after rotation.
  final uprightW = (normalized == 90 || normalized == 270) ? h : w;
  final uprightH = (normalized == 90 || normalized == 270) ? w : h;

  final coverScale = (previewSize.width / uprightW) > (previewSize.height / uprightH)
      ? previewSize.width / uprightW
      : previewSize.height / uprightH;
  final dx = (previewSize.width - uprightW * coverScale) / 2;
  final dy = (previewSize.height - uprightH * coverScale) / 2;

  Offset rotate(QuadCorner c) {
    switch (normalized) {
      case 90:
        return Offset(h - c.y, c.x);
      case 180:
        return Offset(w - c.x, h - c.y);
      case 270:
        return Offset(c.y, w - c.x);
      default:
        return Offset(c.x, c.y);
    }
  }

  return corners.map((c) {
    final upright = rotate(c);
    var px = upright.dx * coverScale + dx;
    final py = upright.dy * coverScale + dy;
    if (mirror) px = previewSize.width - px;
    return Offset(px, py);
  }).toList(growable: false);
}

/// Draws the live detected document quadrilateral over the camera preview.
///
/// Receives quad corners already mapped into preview widget space (via
/// [mapQuadToPreview]) and strokes the closed 4-point polygon. Paints nothing
/// when fewer than four corners are supplied, so the overlay vanishes the
/// instant detection drops below a valid quad.
class QuadOverlayPainter extends CustomPainter {
  const QuadOverlayPainter({
    required this.points,
    required this.color,
  });

  /// Quad corners in preview widget coordinates, ordered TL, TR, BR, BL.
  final List<Offset> points;

  /// Stroke color for the quad outline.
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 4) return;

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant QuadOverlayPainter old) {
    return old.color != color || !_pointsEqual(old.points, points);
  }

  static bool _pointsEqual(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
