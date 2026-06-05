import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:dni_peru_ocr/src/tilt_calculator.dart';

/// Builds a [TextLine] with given corner points.
/// cornerPoints order: [TL, TR, BR, BL] (MLKit clockwise from top-left).
TextLine makeLine(
  List<math.Point<int>> cornerPoints, {
  double? angle,
}) {
  final xs = cornerPoints.map((p) => p.x);
  final ys = cornerPoints.map((p) => p.y);
  final left = xs.reduce(math.min).toDouble();
  final top = ys.reduce(math.min).toDouble();
  final right = xs.reduce(math.max).toDouble();
  final bottom = ys.reduce(math.max).toDouble();
  return TextLine(
    text: 'test',
    elements: [],
    boundingBox: Rect.fromLTRB(left, top, right, bottom),
    recognizedLanguages: [],
    cornerPoints: cornerPoints,
    confidence: null,
    angle: angle,
  );
}

/// Minimal [TextLine] for tests that only care about the MLKit-provided
/// [TextLine.angle] (and not corner geometry).
TextLine makeLineWithAngle(double? angle) {
  return makeLine(
    [
      const math.Point(0, 0),
      const math.Point(100, 0),
      const math.Point(100, 20),
      const math.Point(0, 20),
    ],
    angle: angle,
  );
}

/// Builds a [TextBlock] wrapping a list of [TextLine]s.
TextBlock makeBlockFromLines(List<TextLine> lines) {
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (final l in lines) {
    final b = l.boundingBox;
    if (b.left < left) left = b.left;
    if (b.top < top) top = b.top;
    if (b.right > right) right = b.right;
    if (b.bottom > bottom) bottom = b.bottom;
  }
  return TextBlock(
    text: lines.map((l) => l.text).join('\n'),
    lines: lines,
    boundingBox: Rect.fromLTRB(left, top, right, bottom),
    recognizedLanguages: [],
    cornerPoints: [
      math.Point(left.toInt(), top.toInt()),
      math.Point(right.toInt(), top.toInt()),
      math.Point(right.toInt(), bottom.toInt()),
      math.Point(left.toInt(), bottom.toInt()),
    ],
  );
}

/// Builds a [RecognizedText] where each entry in [lineCornerPoints] becomes
/// its own block with a single line.
RecognizedText recognizedTextWithLines(
  List<List<math.Point<int>>> lineCornerPoints,
) {
  final blocks = <TextBlock>[];
  for (final corners in lineCornerPoints) {
    final line = makeLine(corners);
    blocks.add(makeBlockFromLines([line]));
  }
  return RecognizedText(
    text: blocks.map((b) => b.text).join('\n'),
    blocks: blocks,
  );
}

/// Returns 4 corner points (TL, TR, BR, BL) for a rectangle starting at
/// (x, y), with given [width]/[height], rotated [angleDeg] degrees clockwise.
List<math.Point<int>> cornersForAngle({
  required int x,
  required int y,
  required int width,
  required int height,
  required double angleDeg,
}) {
  final rad = angleDeg * math.pi / 180;
  final cosA = math.cos(rad);
  final sinA = math.sin(rad);

  int px(double dx, double dy) => (x + dx * cosA - dy * sinA).round();
  int py(double dx, double dy) => (y + dx * sinA + dy * cosA).round();

  return [
    math.Point(px(0, 0), py(0, 0)),
    math.Point(px(width.toDouble(), 0), py(width.toDouble(), 0)),
    math.Point(
      px(width.toDouble(), height.toDouble()),
      py(width.toDouble(), height.toDouble()),
    ),
    math.Point(px(0, height.toDouble()), py(0, height.toDouble())),
  ];
}

void main() {
  // Group 1 — Edge cases
  group('computeMedianTiltDegrees — edge cases', () {
    test('empty RecognizedText (no blocks) → returns 0', () {
      final rt = RecognizedText(text: '', blocks: []);
      final result = computeMedianTiltDegrees(rt);
      expect(result, closeTo(0.0, 0.001));
    });

    test('blocks with no lines → returns 0', () {
      final block = TextBlock(
        text: '',
        lines: [],
        boundingBox: const Rect.fromLTRB(0, 0, 100, 30),
        recognizedLanguages: [],
        cornerPoints: [
          const math.Point(0, 0),
          const math.Point(100, 0),
          const math.Point(100, 30),
          const math.Point(0, 30),
        ],
      );
      final rt = RecognizedText(text: '', blocks: [block]);
      final result = computeMedianTiltDegrees(rt);
      expect(result, closeTo(0.0, 0.001));
    });
  });

  // Group 2 — Single line angles
  // Requires ≥ 3 horizontal lines before returning a non-zero median (noise
  // guard). Fewer than 3 qualifying lines always produces 0.
  group('computeMedianTiltDegrees — single line', () {
    test(
      'perfectly horizontal line (TL=(0,0), TR=(100,0)) → 0° (< 3 lines guard)',
      () {
        final rt = recognizedTextWithLines([
          [
            const math.Point(0, 0),
            const math.Point(100, 0),
            const math.Point(100, 20),
            const math.Point(0, 20),
          ],
        ]);
        final result = computeMedianTiltDegrees(rt);
        expect(result, closeTo(0.0, 0.5));
      },
    );

    test(
      'single line tilted 10° clockwise → 0° (not enough signal, guard fires)',
      () {
        final corners = cornersForAngle(
          x: 200,
          y: 200,
          width: 200,
          height: 30,
          angleDeg: 10,
        );
        final rt = recognizedTextWithLines([corners]);
        final result = computeMedianTiltDegrees(rt);
        expect(result, closeTo(0.0, 0.001));
      },
    );

    test(
      'single line tilted 10° counter-clockwise → 0° (not enough signal, guard fires)',
      () {
        final corners = cornersForAngle(
          x: 200,
          y: 300,
          width: 200,
          height: 30,
          angleDeg: -10,
        );
        final rt = recognizedTextWithLines([corners]);
        final result = computeMedianTiltDegrees(rt);
        expect(result, closeTo(0.0, 0.001));
      },
    );
  });

  // Group 3 — Multiple lines — median, not mean
  group('computeMedianTiltDegrees — multiple lines', () {
    test('3 lines at 5°, 10°, 15° → median is 10°', () {
      final rt = recognizedTextWithLines([
        cornersForAngle(
          x: 100,
          y: 100,
          width: 200,
          height: 25,
          angleDeg: 5,
        ),
        cornersForAngle(
          x: 100,
          y: 200,
          width: 200,
          height: 25,
          angleDeg: 10,
        ),
        cornersForAngle(
          x: 100,
          y: 300,
          width: 200,
          height: 25,
          angleDeg: 15,
        ),
      ]);
      final result = computeMedianTiltDegrees(rt);
      expect(result, closeTo(10.0, 1.0));
    });

    test('outlier resistance: [5°, 5°, 5°, 45°] → median is 5° not 15°', () {
      final rt = recognizedTextWithLines([
        cornersForAngle(
          x: 100,
          y: 100,
          width: 200,
          height: 25,
          angleDeg: 5,
        ),
        cornersForAngle(
          x: 100,
          y: 200,
          width: 200,
          height: 25,
          angleDeg: 5,
        ),
        cornersForAngle(
          x: 100,
          y: 300,
          width: 200,
          height: 25,
          angleDeg: 5,
        ),
        cornersForAngle(
          x: 100,
          y: 400,
          width: 200,
          height: 25,
          angleDeg: 45,
        ),
      ]);
      final result = computeMedianTiltDegrees(rt);
      // Median of [5, 5, 5, 45] = (5+5)/2 = 5
      expect(result, closeTo(5.0, 1.0));
      // Mean would be 15° — confirm this is not mean
      expect(result, lessThan(15.0));
    });
  });

  // Group 3.5 — computeMlkitMedianAngleDegrees (diagnostic signal)
  // Returns the median of the MLKit-provided TextLine.angle field. Returns null
  // when no line carries a non-null angle (e.g. iOS). Used in the diagnostic
  // overlay to compare against computeMedianTiltDegrees and pinpoint noise.
  group('computeMlkitMedianAngleDegrees — diagnostic signal', () {
    test('empty RecognizedText → returns null', () {
      final rt = RecognizedText(text: '', blocks: []);
      expect(computeMlkitMedianAngleDegrees(rt), isNull);
    });

    test('all lines with angle=null → returns null', () {
      final block = makeBlockFromLines([
        makeLineWithAngle(null),
        makeLineWithAngle(null),
      ]);
      final rt = RecognizedText(text: 'x', blocks: [block]);
      expect(computeMlkitMedianAngleDegrees(rt), isNull);
    });

    test('single line with angle=12.5 → returns 12.5', () {
      final block = makeBlockFromLines([makeLineWithAngle(12.5)]);
      final rt = RecognizedText(text: 'x', blocks: [block]);
      expect(computeMlkitMedianAngleDegrees(rt), closeTo(12.5, 0.001));
    });

    test('three lines [5, 10, 15] → median is 10', () {
      final block = makeBlockFromLines([
        makeLineWithAngle(5),
        makeLineWithAngle(10),
        makeLineWithAngle(15),
      ]);
      final rt = RecognizedText(text: 'x', blocks: [block]);
      expect(computeMlkitMedianAngleDegrees(rt), closeTo(10.0, 0.001));
    });

    test(
      'mixed nulls and values [null, 8, null, 12] → median of [8, 12] = 10',
      () {
        final block = makeBlockFromLines([
          makeLineWithAngle(null),
          makeLineWithAngle(8),
          makeLineWithAngle(null),
          makeLineWithAngle(12),
        ]);
        final rt = RecognizedText(text: 'x', blocks: [block]);
        expect(computeMlkitMedianAngleDegrees(rt), closeTo(10.0, 0.001));
      },
    );
  });

  // Group 4 — 180° flip normalization
  group('computeMedianTiltDegrees — 180° flip normalization', () {
    test(
      '180°-flipped line (TL/TR reversed) normalizes to ~0° not 180°',
      () {
        // TL=(100,0), TR=(0,0): atan2(0-0, 0-100) = atan2(0,-100) ≈ 180°
        // After normalization to [-90°, +90°] this maps to 0°.
        final rt = recognizedTextWithLines([
          [
            const math.Point(100, 0),
            const math.Point(0, 0),
            const math.Point(0, 20),
            const math.Point(100, 20),
          ],
        ]);
        final result = computeMedianTiltDegrees(rt);
        expect(result.abs(), lessThan(1.0));
      },
    );
  });
}
