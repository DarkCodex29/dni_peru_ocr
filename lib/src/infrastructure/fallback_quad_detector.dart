import 'dart:typed_data';

import '../domain/capture/document_quad_detector.dart';

/// Pure-Dart fallback adapter for [DocumentQuadDetector], selected when the
/// native opencv_dart binary cannot be loaded.
///
/// It performs no edge detection. By design it reports `isNativeAvailable ==
/// false` and returns the honest no-quad result for every frame: it never
/// fabricates corners. When this adapter is active the system degrades to the
/// OCR-block framing path (handled by document-validation), so callers can
/// detect the absence of a quad and fall back without being misled by fake
/// framing.
class FallbackQuadDetector implements DocumentQuadDetector {
  const FallbackQuadDetector();

  @override
  bool get isNativeAvailable => false;

  @override
  QuadDetectionResult detectQuad(QuadFrame frame) =>
      const QuadDetectionResult.invalid();

  @override
  Uint8List? rectify({
    required Uint8List imageBytes,
    required List<QuadCorner> corners,
  }) =>
      null;
}
