import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Custom painter that renders the document-hole overlay and visual feedback.
///
/// Paints:
/// - Dark overlay with a transparent rounded rectangle cut-out (the "hole")
/// - Corner markers at the hole boundary (always visible)
/// - A sweeping scan line inside the hole (always animated during scanning)
/// - A clockwise countdown arc that grows as auto-capture approaches (0→1)
class MaskPainter extends CustomPainter {
  const MaskPainter({
    required this.holeWidth,
    required this.holeHeight,
    required this.borderColor,
    required this.overlayColor,
    required this.countdownProgress,
    this.scanProgress = 0,
  });

  final double holeWidth;
  final double holeHeight;
  final Color borderColor;
  final Color overlayColor;
  final double countdownProgress;
  final double scanProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    final fullPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    final holePath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, cy),
            width: holeWidth,
            height: holeHeight,
          ),
          const Radius.circular(8),
        ),
      );

    canvas.drawPath(
      Path.combine(PathOperation.difference, fullPath, holePath),
      Paint()..color = overlayColor,
    );

    _drawCornerMarkers(canvas, cx, cy);
    _drawScanLine(canvas, cx, cy);
    if (countdownProgress > 0) _drawRectCountdown(canvas, cx, cy);
  }

  /// Horizontal scan line sweeping vertically through the document hole.
  /// Gives real-time feedback that the system is actively reading the document.
  void _drawScanLine(Canvas canvas, double cx, double cy) {
    final l = cx - holeWidth / 2;
    final t = cy - holeHeight / 2;
    final r = cx + holeWidth / 2;
    final b = cy + holeHeight / 2;
    final scanY = t + (b - t) * scanProgress;
    final gradientRect = Rect.fromLTRB(l, scanY - 6, r, scanY + 6);

    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(l, t, r, b))
      // Glow layer
      ..drawLine(
        Offset(l, scanY),
        Offset(r, scanY),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x00FFFFFF), Color(0x1EFFFFFF), Color(0x00FFFFFF)],
          ).createShader(gradientRect)
          ..strokeWidth = 12
          ..style = PaintingStyle.stroke,
      )
      // Core line
      ..drawLine(
        Offset(l, scanY),
        Offset(r, scanY),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0x00FFFFFF), Color(0x8CFFFFFF), Color(0x00FFFFFF)],
          ).createShader(gradientRect)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      )
      ..restore();
  }

  /// Draws a clockwise-filling border around the document rect as the
  /// auto-capture countdown progresses (0 → 1). Starts from the top-left
  /// corner so the animation feels natural and directional.
  void _drawRectCountdown(Canvas canvas, double cx, double cy) {
    final l = cx - holeWidth / 2;
    final t = cy - holeHeight / 2;
    final r = cx + holeWidth / 2;
    final b = cy + holeHeight / 2;

    final perimeter = 2 * (holeWidth + holeHeight);
    var remaining = perimeter * countdownProgress;

    final path = Path()..moveTo(l, t);

    final seg1 = math.min(remaining, holeWidth);
    path.lineTo(l + seg1, t);
    remaining -= seg1;

    if (remaining > 0) {
      final seg2 = math.min(remaining, holeHeight);
      path.lineTo(r, t + seg2);
      remaining -= seg2;
    }
    if (remaining > 0) {
      final seg3 = math.min(remaining, holeWidth);
      path.lineTo(r - seg3, b);
      remaining -= seg3;
    }
    if (remaining > 0) {
      final seg4 = math.min(remaining, holeHeight);
      path.lineTo(l, b - seg4);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = borderColor
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawCornerMarkers(Canvas canvas, double cx, double cy) {
    const markerLen = 24.0;
    const strokeW = 4.0;
    const radius = 8.0;

    final paint = Paint()
      ..color = borderColor
      ..strokeWidth = strokeW
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final l = cx - holeWidth / 2;
    final t = cy - holeHeight / 2;
    final r = cx + holeWidth / 2;
    final b = cy + holeHeight / 2;

    canvas
      ..drawLine(
        Offset(l + radius, t),
        Offset(l + radius + markerLen, t),
        paint,
      )
      ..drawLine(
        Offset(l, t + radius),
        Offset(l, t + radius + markerLen),
        paint,
      )
      ..drawArc(
        Rect.fromCircle(center: Offset(l + radius, t + radius), radius: radius),
        3.14159,
        0.5 * 3.14159,
        false,
        paint,
      )
      ..drawLine(
        Offset(r - radius, t),
        Offset(r - radius - markerLen, t),
        paint,
      )
      ..drawLine(
        Offset(r, t + radius),
        Offset(r, t + radius + markerLen),
        paint,
      )
      ..drawArc(
        Rect.fromCircle(center: Offset(r - radius, t + radius), radius: radius),
        1.5 * 3.14159,
        0.5 * 3.14159,
        false,
        paint,
      )
      ..drawLine(
        Offset(l + radius, b),
        Offset(l + radius + markerLen, b),
        paint,
      )
      ..drawLine(
        Offset(l, b - radius),
        Offset(l, b - radius - markerLen),
        paint,
      )
      ..drawArc(
        Rect.fromCircle(center: Offset(l + radius, b - radius), radius: radius),
        0.5 * 3.14159,
        0.5 * 3.14159,
        false,
        paint,
      )
      ..drawLine(
        Offset(r - radius, b),
        Offset(r - radius - markerLen, b),
        paint,
      )
      ..drawLine(
        Offset(r, b - radius),
        Offset(r, b - radius - markerLen),
        paint,
      )
      ..drawArc(
        Rect.fromCircle(center: Offset(r - radius, b - radius), radius: radius),
        0,
        0.5 * 3.14159,
        false,
        paint,
      );
  }

  @override
  bool shouldRepaint(MaskPainter old) =>
      old.holeWidth != holeWidth ||
      old.holeHeight != holeHeight ||
      old.borderColor != borderColor ||
      old.overlayColor != overlayColor ||
      old.countdownProgress != countdownProgress ||
      old.scanProgress != scanProgress;
}
