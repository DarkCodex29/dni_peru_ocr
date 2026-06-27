import 'dart:typed_data';

/// A single corner of a detected document quadrilateral, in frame-pixel
/// coordinates.
class QuadCorner {
  const QuadCorner(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuadCorner && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'QuadCorner($x, $y)';
}

/// A single grayscale camera frame submitted for quad detection.
///
/// Only plain values cross the isolate boundary: a luminance byte buffer plus
/// the geometry needed to interpret it. No native handle is ever carried here.
class QuadFrame {
  const QuadFrame({
    required this.luminance,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.rotationDegrees,
  });

  final Uint8List luminance;
  final int width;
  final int height;
  final int bytesPerRow;
  final int rotationDegrees;
}

/// The outcome of a single quad-detection pass.
///
/// [framingValid] reports whether a closed, convex, sufficiently large
/// 4-vertex quad was found. When valid, [corners] holds exactly four points
/// ordered top-left, top-right, bottom-right, bottom-left. When invalid,
/// [corners] is empty.
class QuadDetectionResult {
  const QuadDetectionResult({
    required this.framingValid,
    required this.corners,
  });

  /// The canonical no-quad result: not framed, no corners.
  const QuadDetectionResult.invalid()
      : framingValid = false,
        corners = const [];

  final bool framingValid;
  final List<QuadCorner> corners;
}

/// Domain port for detecting a document quadrilateral from a camera frame and
/// rectifying a capture via perspective transform.
///
/// This contract is FFI-, Flutter-, and opencv-free so the dependency rule
/// holds. Both the native opencv_dart adapter and the pure-Dart fallback
/// implement it; a runtime capability probe selects which is active.
abstract interface class DocumentQuadDetector {
  /// Whether the native quad-detection binary is available on this platform.
  bool get isNativeAvailable;

  /// Detects the best qualifying document quad in [frame].
  ///
  /// Returns [QuadDetectionResult.invalid] when no qualifying quad is found.
  /// Implementations MUST NOT throw.
  QuadDetectionResult detectQuad(QuadFrame frame);

  /// Rectifies [imageBytes] using the four [corners] of the detected quad,
  /// returning a deskewed image cropped to the document bounds.
  ///
  /// Returns null when fewer than four corners are supplied. Implementations
  /// MUST NOT throw an unhandled exception.
  Uint8List? rectify({
    required Uint8List imageBytes,
    required List<QuadCorner> corners,
  });
}
