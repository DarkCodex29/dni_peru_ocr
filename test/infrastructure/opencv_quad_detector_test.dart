@Tags(['native'])

/// RED tests for the native OpenCvQuadDetector adapter (PR4 — tasks 4.1-4.7).
///
/// Verifies the detector ALGORITHM against the document-quad-detection spec
/// edge cases, on synthetic luminance frames built programmatically:
/// 1. A clear bright rectangle on a dark background detects as a valid quad
///    with four corners ordered TL, TR, BR, BL approximating the rectangle.
/// 2. A uniform / noisy frame with no quad returns invalid.
/// 3. A rectangle below the minimum area fraction returns invalid.
/// 4. With multiple rectangles, the largest qualifying one is selected.
/// 5. Corner ordering is deterministic (TL, TR, BR, BL) for rotated input.
/// 6. rectify with four corners returns non-null encoded bytes; with fewer
///    than four returns null.
/// 7. A runtime capability probe selects the native adapter when available.
/// 8. dartcv imports are confined to the adapter source file.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

const int _frameWidth = 640;
const int _frameHeight = 480;

/// Builds a [QuadFrame] whose luminance buffer is [dark] everywhere except a
/// filled bright axis-aligned rectangle in [left, top, right, bottom) pixels.
QuadFrame _frameWithRect({
  required int left,
  required int top,
  required int right,
  required int bottom,
  int width = _frameWidth,
  int height = _frameHeight,
  int dark = 10,
  int bright = 240,
  List<({int left, int top, int right, int bottom})> extraRects = const [],
}) {
  final buffer = Uint8List(width * height)..fillRange(0, width * height, dark);
  void paint(int l, int t, int r, int b) {
    for (var y = t; y < b && y < height; y++) {
      final rowStart = y * width;
      for (var x = l; x < r && x < width; x++) {
        buffer[rowStart + x] = bright;
      }
    }
  }

  paint(left, top, right, bottom);
  for (final rect in extraRects) {
    paint(rect.left, rect.top, rect.right, rect.bottom);
  }

  return QuadFrame(
    luminance: buffer,
    width: width,
    height: height,
    bytesPerRow: width,
    rotationDegrees: 0,
  );
}

/// Builds a frame with a single bright convex quad defined by four arbitrary
/// vertices, filled via scanline. Used to exercise rotated (non-axis-aligned)
/// inputs so corner ordering can be verified independently of orientation.
QuadFrame _frameWithPolygon(
  List<({double x, double y})> vertices, {
  int width = _frameWidth,
  int height = _frameHeight,
  int dark = 10,
  int bright = 240,
}) {
  final buffer = Uint8List(width * height)..fillRange(0, width * height, dark);
  for (var y = 0; y < height; y++) {
    final crossings = <double>[];
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      final ay = a.y;
      final by = b.y;
      if ((ay <= y && by > y) || (by <= y && ay > y)) {
        final t = (y - ay) / (by - ay);
        crossings.add(a.x + t * (b.x - a.x));
      }
    }
    crossings.sort();
    for (var c = 0; c + 1 < crossings.length; c += 2) {
      final xStart = crossings[c].ceil().clamp(0, width - 1);
      final xEnd = crossings[c + 1].floor().clamp(0, width - 1);
      final rowStart = y * width;
      for (var x = xStart; x <= xEnd; x++) {
        buffer[rowStart + x] = bright;
      }
    }
  }
  return QuadFrame(
    luminance: buffer,
    width: width,
    height: height,
    bytesPerRow: width,
    rotationDegrees: 0,
  );
}

/// Builds a uniform (single-value) luminance frame — no edges, no quad.
QuadFrame _uniformFrame({int value = 128}) {
  final buffer = Uint8List(_frameWidth * _frameHeight)
    ..fillRange(0, _frameWidth * _frameHeight, value);
  return QuadFrame(
    luminance: buffer,
    width: _frameWidth,
    height: _frameHeight,
    bytesPerRow: _frameWidth,
    rotationDegrees: 0,
  );
}

void main() {
  late OpenCvQuadDetector detector;

  setUp(() => detector = const OpenCvQuadDetector());

  group('OpenCvQuadDetector — capability flag', () {
    test('is a DocumentQuadDetector reporting native available', () {
      expect(detector, isA<DocumentQuadDetector>());
      expect(detector.isNativeAvailable, isTrue);
    });
  });

  group('OpenCvQuadDetector — detectQuad happy path', () {
    test('detects a clear bright rectangle as a valid four-corner quad', () {
      final frame = _frameWithRect(left: 120, top: 90, right: 520, bottom: 390);

      final result = detector.detectQuad(frame);

      expect(result.framingValid, isTrue);
      expect(result.corners, hasLength(4));
      // Corners must approximate the painted rectangle bounds within a few px.
      final tl = result.corners[0];
      final tr = result.corners[1];
      final br = result.corners[2];
      final bl = result.corners[3];
      expect(tl.x, closeTo(120, 8));
      expect(tl.y, closeTo(90, 8));
      expect(tr.x, closeTo(520, 8));
      expect(tr.y, closeTo(90, 8));
      expect(br.x, closeTo(520, 8));
      expect(br.y, closeTo(390, 8));
      expect(bl.x, closeTo(120, 8));
      expect(bl.y, closeTo(390, 8));
    });

    test('orders corners TL, TR, BR, BL by coordinate geometry', () {
      // Sum (x+y) is smallest at TL, largest at BR.
      // Diff (x-y) is smallest at BL, largest at TR.
      final frame = _frameWithRect(left: 100, top: 80, right: 500, bottom: 360);

      final corners = detector.detectQuad(frame).corners;

      expect(corners, hasLength(4));
      final sums = corners.map((c) => c.x + c.y).toList();
      final diffs = corners.map((c) => c.x - c.y).toList();
      // index 0 = TL = min sum; index 2 = BR = max sum
      expect(sums[0], lessThan(sums[2]));
      expect(sums[0], equals(sums.reduce((a, b) => a < b ? a : b)));
      expect(sums[2], equals(sums.reduce((a, b) => a > b ? a : b)));
      // index 1 = TR = max diff; index 3 = BL = min diff
      expect(diffs[1], equals(diffs.reduce((a, b) => a > b ? a : b)));
      expect(diffs[3], equals(diffs.reduce((a, b) => a < b ? a : b)));
    });

    test('orders corners TL, TR, BR, BL for a rotated (tilted) quad', () {
      // A quad rotated ~15 degrees: top edge tilts down to the right. The
      // ordering must still land each physical corner in its TL/TR/BR/BL slot
      // regardless of the orientation, exercising the sum/diff ordering.
      final frame = _frameWithPolygon(const [
        (x: 180, y: 110), // physical top-left (highest, left-most-ish)
        (x: 470, y: 160), // physical top-right (tilted lower)
        (x: 430, y: 380), // physical bottom-right
        (x: 140, y: 330), // physical bottom-left
      ]);

      final corners = detector.detectQuad(frame).corners;

      expect(corners, hasLength(4));
      final tl = corners[0];
      final tr = corners[1];
      final br = corners[2];
      final bl = corners[3];
      // TL is the upper-left cluster; BR the lower-right; orientation invariant.
      expect(tl.x, lessThan(tr.x));
      expect(bl.x, lessThan(br.x));
      expect(tl.y, lessThan(bl.y));
      expect(tr.y, lessThan(br.y));
      // Canonical sum/diff invariants hold for the tilted quad too.
      final sums = corners.map((c) => c.x + c.y).toList();
      final diffs = corners.map((c) => c.x - c.y).toList();
      expect(sums[0], equals(sums.reduce((a, b) => a < b ? a : b)));
      expect(sums[2], equals(sums.reduce((a, b) => a > b ? a : b)));
      expect(diffs[1], equals(diffs.reduce((a, b) => a > b ? a : b)));
      expect(diffs[3], equals(diffs.reduce((a, b) => a < b ? a : b)));
    });
  });

  group('OpenCvQuadDetector — detectQuad rejection cases', () {
    test('returns invalid on a uniform frame with no quad', () {
      final result = detector.detectQuad(_uniformFrame());
      expect(result.framingValid, isFalse);
      expect(result.corners, isEmpty);
    });

    test('returns invalid for a rectangle below the minimum area fraction', () {
      // A tiny 40x30 rectangle covers <1% of a 640x480 frame.
      final frame = _frameWithRect(left: 20, top: 20, right: 60, bottom: 50);

      final result = detector.detectQuad(frame);

      expect(result.framingValid, isFalse);
      expect(result.corners, isEmpty);
    });
  });

  group('OpenCvQuadDetector — multiple candidates', () {
    test('selects the largest qualifying rectangle when several are present',
        () {
      // Large rect (document) plus a smaller competing rect.
      final frame = _frameWithRect(
        left: 100,
        top: 80,
        right: 520,
        bottom: 400,
        extraRects: const [
          (left: 540, top: 20, right: 620, bottom: 90),
        ],
      );

      final corners = detector.detectQuad(frame).corners;

      expect(corners, hasLength(4));
      // The selected quad must span the LARGE rectangle, not the small one.
      final width = corners[1].x - corners[0].x;
      final height = corners[3].y - corners[0].y;
      expect(width, closeTo(420, 16));
      expect(height, closeTo(320, 16));
    });
  });

  group('OpenCvQuadDetector — rectify', () {
    test('rectify with four corners returns non-null encoded bytes', () {
      final frame = _frameWithRect(left: 120, top: 90, right: 520, bottom: 390);
      final corners = detector.detectQuad(frame).corners;
      expect(corners, hasLength(4));

      // Encode a synthetic source image (the bright-rect frame) as JPEG bytes.
      final imageBytes = encodeLuminanceJpegForTest(frame);

      final out = detector.rectify(imageBytes: imageBytes, corners: corners);

      expect(out, isNotNull);
      expect(out!, isNotEmpty);
    });

    test('rectify returns null when fewer than four corners are supplied', () {
      final out = detector.rectify(
        imageBytes: Uint8List.fromList(const [1, 2, 3, 4]),
        corners: const [QuadCorner(0, 0), QuadCorner(1, 1)],
      );
      expect(out, isNull);
    });
  });

  group('OpenCvQuadDetector — isolate seam and Mat discipline', () {
    test('detectQuadInFrame runs inside Isolate.run with only plain data '
        'crossing the boundary', () async {
      // The production seam (scanner PR5/6) invokes the synchronous detector
      // inside Isolate.run. Only a QuadFrame goes in and a QuadDetectionResult
      // comes out — no native cv.Mat ever crosses the isolate boundary. Every
      // Mat is allocated and disposed inside detectQuadInFrame.
      final frame = _frameWithRect(left: 120, top: 90, right: 520, bottom: 390);

      final result = await Isolate.run(() => detectQuadInFrame(frame));

      expect(result.framingValid, isTrue);
      expect(result.corners, hasLength(4));
    });

    test('repeated isolate detections do not leak (stable across iterations)',
        () async {
      // Triangulation: running the full native pipeline many times in fresh
      // isolates must keep returning a valid quad with disposed Mats each pass.
      final frame = _frameWithRect(left: 100, top: 80, right: 500, bottom: 360);
      for (var i = 0; i < 8; i++) {
        final result = await Isolate.run(() => detectQuadInFrame(frame));
        expect(result.framingValid, isTrue,
            reason: 'iteration $i should still detect the quad');
        expect(result.corners, hasLength(4));
      }
    });
  });

  group('quad detector selection — capability probe', () {
    test('selects the native OpenCvQuadDetector when the binding loads', () {
      final selected = selectQuadDetector();
      expect(selected, isA<OpenCvQuadDetector>());
      expect(selected.isNativeAvailable, isTrue);
    });
  });

  group('OpenCvQuadDetector — dependency rule', () {
    test('dartcv4 import is confined to the adapter source file', () {
      final libDir = Directory('lib');
      final offenders = <String>[];
      for (final entity in libDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('opencv_quad_detector.dart')) continue;
        final source = entity.readAsStringSync();
        if (source.contains('package:dartcv4/') ||
            source.contains('package:opencv_dart/')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'Only opencv_quad_detector.dart may import dartcv4');
    });
  });
}
