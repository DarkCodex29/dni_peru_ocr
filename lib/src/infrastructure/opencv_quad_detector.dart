import 'dart:typed_data';

import 'package:dartcv4/dartcv.dart' as cv;

import '../domain/capture/document_quad_detector.dart';
import 'fallback_quad_detector.dart';

/// Native [DocumentQuadDetector] backed by the trimmed opencv_dart binding.
///
/// This is the ONLY file in the package that imports `package:dartcv4/`. The
/// dependency rule keeps every other layer FFI-free.
///
/// [detectQuad] is synchronous by contract. It allocates and disposes every
/// native `cv.Mat` (and every other native handle) before returning, so it can
/// be invoked directly inside an `Isolate.run` body at the scanner layer
/// without leaking native memory. Only plain values ([QuadFrame] in,
/// [QuadDetectionResult] out) cross the isolate boundary — never a native
/// handle.
class OpenCvQuadDetector implements DocumentQuadDetector {
  const OpenCvQuadDetector();

  @override
  bool get isNativeAvailable => true;

  @override
  QuadDetectionResult detectQuad(QuadFrame frame) => detectQuadInFrame(frame);

  @override
  Uint8List? rectify({
    required Uint8List imageBytes,
    required List<QuadCorner> corners,
  }) =>
      rectifyWithCorners(imageBytes: imageBytes, corners: corners);
}

/// Minimum fraction of the frame area a candidate quad must cover to qualify
/// as the document. Rejects small/partial shapes.
const double _minAreaFraction = 0.10;

/// approxPolyDP epsilon as a fraction of the contour perimeter.
const double _approxEpsilonFactor = 0.02;

/// Detects the best qualifying document quad in [frame].
///
/// Pipeline on the Y-plane luminance: build a tight CV_8UC1 Mat (stripping any
/// row-stride padding) -> Gaussian blur -> Canny edges -> external contours ->
/// approxPolyDP per contour -> keep the largest convex 4-vertex polygon whose
/// area meets [_minAreaFraction]. Corners are ordered TL, TR, BR, BL. Returns
/// [QuadDetectionResult.invalid] when nothing qualifies. Never throws.
QuadDetectionResult detectQuadInFrame(QuadFrame frame) {
  if (frame.width <= 0 || frame.height <= 0 || frame.luminance.isEmpty) {
    return const QuadDetectionResult.invalid();
  }

  cv.Mat? gray;
  cv.Mat? blurred;
  cv.Mat? edges;
  try {
    gray = _matFromLuminance(frame);
    if (gray == null) {
      return const QuadDetectionResult.invalid();
    }

    blurred = cv.gaussianBlur(gray, (5, 5), 0);
    edges = cv.canny(blurred, 50, 150);

    final (contours, hierarchy) =
        cv.findContours(edges, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    try {
      final frameArea = (frame.width * frame.height).toDouble();
      final minArea = frameArea * _minAreaFraction;

      List<QuadCorner>? best;
      var bestArea = 0.0;

      for (var i = 0; i < contours.length; i++) {
        final contour = contours[i];
        final perimeter = cv.arcLength(contour, true);
        if (perimeter <= 0) continue;
        final approx =
            cv.approxPolyDP(contour, _approxEpsilonFactor * perimeter, true);
        try {
          if (approx.length != 4) continue;
          if (!cv.isContourConvex(approx)) continue;
          final area = cv.contourArea(approx).abs();
          if (area < minArea) continue;
          if (area <= bestArea) continue;
          bestArea = area;
          best = _orderCorners([
            for (var v = 0; v < 4; v++)
              QuadCorner(approx[v].x.toDouble(), approx[v].y.toDouble()),
          ]);
        } finally {
          approx.dispose();
        }
      }

      if (best == null) {
        return const QuadDetectionResult.invalid();
      }
      return QuadDetectionResult(framingValid: true, corners: best);
    } finally {
      contours.dispose();
      hierarchy.dispose();
    }
  } on Object {
    return const QuadDetectionResult.invalid();
  } finally {
    edges?.dispose();
    blurred?.dispose();
    gray?.dispose();
  }
}

/// Rectifies [imageBytes] using the four [corners] via perspective transform.
///
/// Decodes the image, warps it so the quad maps to an axis-aligned rectangle
/// sized to the averaged quad edges, and re-encodes as JPEG. Disposes every
/// native handle. Returns null when fewer than four corners are supplied or on
/// any native failure. Never throws.
Uint8List? rectifyWithCorners({
  required Uint8List imageBytes,
  required List<QuadCorner> corners,
}) {
  if (corners.length != 4 || imageBytes.isEmpty) return null;

  cv.Mat? src;
  cv.Mat? transform;
  cv.Mat? warped;
  cv.VecPoint? srcQuad;
  cv.VecPoint? dstQuad;
  try {
    src = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
    if (src.isEmpty) return null;

    final ordered = _orderCorners(corners);
    final widthTop = _distance(ordered[0], ordered[1]);
    final widthBottom = _distance(ordered[3], ordered[2]);
    final heightLeft = _distance(ordered[0], ordered[3]);
    final heightRight = _distance(ordered[1], ordered[2]);
    final dstWidth = widthTop > widthBottom ? widthTop : widthBottom;
    final dstHeight = heightLeft > heightRight ? heightLeft : heightRight;
    final outWidth = dstWidth.round();
    final outHeight = dstHeight.round();
    if (outWidth <= 0 || outHeight <= 0) return null;

    srcQuad = cv.VecPoint.fromList([
      for (final c in ordered) cv.Point(c.x.round(), c.y.round()),
    ]);
    dstQuad = cv.VecPoint.fromList([
      cv.Point(0, 0),
      cv.Point(outWidth - 1, 0),
      cv.Point(outWidth - 1, outHeight - 1),
      cv.Point(0, outHeight - 1),
    ]);

    transform = cv.getPerspectiveTransform(srcQuad, dstQuad);
    warped = cv.warpPerspective(src, transform, (outWidth, outHeight));

    final (ok, encoded) = cv.imencode('.jpg', warped);
    if (!ok || encoded.isEmpty) return null;
    return Uint8List.fromList(encoded);
  } on Object {
    return null;
  } finally {
    srcQuad?.dispose();
    dstQuad?.dispose();
    warped?.dispose();
    transform?.dispose();
    src?.dispose();
  }
}

/// Builds a tight single-channel CV_8UC1 Mat from the luminance plane,
/// stripping any row-stride padding so each row is exactly [width] bytes.
cv.Mat? _matFromLuminance(QuadFrame frame) {
  final width = frame.width;
  final height = frame.height;
  final stride = frame.bytesPerRow <= 0 ? width : frame.bytesPerRow;
  final plane = frame.luminance;

  if (stride == width && plane.length >= width * height) {
    return cv.Mat.fromList(
      height,
      width,
      cv.MatType.CV_8UC1,
      plane.sublist(0, width * height),
    );
  }

  final tight = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    final srcStart = y * stride;
    if (srcStart + width > plane.length) break;
    tight.setRange(y * width, y * width + width, plane, srcStart);
  }
  return cv.Mat.fromList(height, width, cv.MatType.CV_8UC1, tight);
}

/// Orders four arbitrary corners into TL, TR, BR, BL using coordinate sums and
/// differences: TL has the smallest x+y, BR the largest; TR has the largest
/// x-y, BL the smallest. Rotation-robust within the camera's upright range.
List<QuadCorner> _orderCorners(List<QuadCorner> corners) {
  var tl = corners[0];
  var br = corners[0];
  var tr = corners[0];
  var bl = corners[0];
  var minSum = tl.x + tl.y;
  var maxSum = minSum;
  var maxDiff = tr.x - tr.y;
  var minDiff = maxDiff;

  for (final c in corners) {
    final sum = c.x + c.y;
    final diff = c.x - c.y;
    if (sum < minSum) {
      minSum = sum;
      tl = c;
    }
    if (sum > maxSum) {
      maxSum = sum;
      br = c;
    }
    if (diff > maxDiff) {
      maxDiff = diff;
      tr = c;
    }
    if (diff < minDiff) {
      minDiff = diff;
      bl = c;
    }
  }

  return [tl, tr, br, bl];
}

double _distance(QuadCorner a, QuadCorner b) {
  final dx = a.x - b.x;
  final dy = a.y - b.y;
  return _sqrt(dx * dx + dy * dy);
}

double _sqrt(double value) {
  if (value <= 0) return 0;
  var guess = value;
  for (var i = 0; i < 24; i++) {
    guess = 0.5 * (guess + value / guess);
  }
  return guess;
}

/// Selects the active [DocumentQuadDetector] via a one-time runtime capability
/// probe: attempts a trivial native op and, if it succeeds, returns the native
/// [OpenCvQuadDetector]; otherwise falls back to the pure-Dart
/// [FallbackQuadDetector]. Never throws.
DocumentQuadDetector selectQuadDetector() {
  if (_probeNativeAvailable()) {
    return const OpenCvQuadDetector();
  }
  return const FallbackQuadDetector();
}

bool _probeNativeAvailable() {
  cv.Mat? probe;
  try {
    probe = cv.Mat.zeros(1, 1, cv.MatType.CV_8UC1);
    return probe.rows == 1 && probe.cols == 1;
  } on Object {
    return false;
  } finally {
    probe?.dispose();
  }
}

/// Encodes a [QuadFrame]'s grayscale luminance as JPEG bytes. Test-only helper
/// used to produce a source image for [rectifyWithCorners] without leaking the
/// dartcv import into the test layer.
Uint8List encodeLuminanceJpegForTest(QuadFrame frame) {
  final mat = _matFromLuminance(frame)!;
  try {
    final (ok, encoded) = cv.imencode('.jpg', mat);
    if (!ok) return Uint8List(0);
    return Uint8List.fromList(encoded);
  } finally {
    mat.dispose();
  }
}
