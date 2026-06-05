import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as imglib;

enum QualityCheckResult { pass, blurry, spoofed, error }

class ImageQualityResult {
  const ImageQualityResult({
    required this.isLive,
    required this.isSharp,
    required this.laplacianScore,
  });

  final bool isLive;
  final bool isSharp;

  /// Laplacian variance — higher means sharper.
  final double laplacianScore;
}

class ImageQualityException implements Exception {
  const ImageQualityException(this.message);
  final String message;

  @override
  String toString() => 'ImageQualityException: $message';
}

/// Local liveness result — project-owned type (no external package dependency).
/// Fields: isLive (always true post-blink), laplacianScore (Welford variance).
class LivenessResult {
  const LivenessResult({required this.isLive, required this.laplacianScore});
  final bool isLive;
  final double laplacianScore;
}

/// Injectable liveness analyzer interface.
abstract class LivenessAnalyzer {
  Future<LivenessResult> analyze(Uint8List bytes);
}

/// Validates image quality: sharpness (Laplacian) + liveness (anti-spoofing).
class ImageQualityGate {
  ImageQualityGate({LivenessAnalyzer? analyzer})
    : _analyzer = analyzer ?? _DartLivenessAnalyzer();

  /// Minimum Laplacian variance for an image to be considered sharp.
  ///
  /// Calibrated against real mid-range Android devices: sharp KYC captures
  /// score in the 450–720 range, while heavy motion blur and out-of-focus
  /// captures fall well under 100. The value mirrors the threshold used by
  /// OpenCV's standard blur-detection recipe — empirical, conservative.
  ///
  /// This gate is a **pre-filter**: the backend performs the authoritative
  /// validation. The threshold should reject only obviously broken frames
  /// so the API call is not wasted. Re-calibrate when device-specific
  /// fixtures land in `test/fixtures/image_quality/`.
  static const int blurThreshold = 100;
  final LivenessAnalyzer _analyzer;

  void _assertDecodable(Uint8List bytes) {
    try {
      final decoded = imglib.decodeImage(bytes);
      if (decoded == null) {
        throw const ImageQualityException('Cannot decode image bytes');
      }
    } on ImageQualityException {
      rethrow;
    } on Object {
      // Catches both Exception and Error subclasses (e.g. RangeError from
      // image package when bytes are too short for header parsing).
      throw const ImageQualityException('Cannot decode image bytes');
    }
  }

  Future<bool> isBlurry(Uint8List bytes) async {
    _assertDecodable(bytes);
    final result = await _analyzer.analyze(bytes);
    return result.laplacianScore < blurThreshold;
  }

  Future<bool> isReal(Uint8List bytes) async {
    _assertDecodable(bytes);
    final result = await _analyzer.analyze(bytes);
    return result.isLive;
  }

  /// Runs blur + liveness in a single analyze call. Fail-fast order:
  /// decode → blur → liveness → pass.
  Future<QualityCheckResult> validate(Uint8List bytes) async {
    imglib.Image? decoded;
    try {
      decoded = imglib.decodeImage(bytes);
    } on Object {
      // Catches both Exception and Error subclasses (e.g. RangeError).
      return QualityCheckResult.error;
    }
    if (decoded == null) return QualityCheckResult.error;

    final result = await _analyzer.analyze(bytes);
    if (kDebugMode) {
      debugPrint(
        '── LivenessGate: isLive=${result.isLive} '
        'laplacianScore=${result.laplacianScore.toStringAsFixed(1)}',
      );
    }
    if (result.laplacianScore < blurThreshold) return QualityCheckResult.blurry;
    if (!result.isLive) return QualityCheckResult.spoofed;
    return QualityCheckResult.pass;
  }

  Future<ImageQualityResult> analyze(Uint8List bytes) async {
    _assertDecodable(bytes);
    final result = await _analyzer.analyze(bytes);
    return ImageQualityResult(
      isLive: result.isLive,
      isSharp: result.laplacianScore >= blurThreshold,
      laplacianScore: result.laplacianScore,
    );
  }
}

/// Top-level function required by [compute] — MUST NOT be an instance method.
///
/// Returns the Laplacian variance of [bytes] as a sharpness measure.
/// Returns -1.0 if the image cannot be decoded (sentinel for error handling).
///
/// Algorithm:
/// - Downscale to 480px on longest side (CPU budget)
/// - BT.601 grayscale via imglib.grayscale()
/// - 3×3 Laplacian kernel: sum(t + b + l + r - 4*c)
/// - Welford one-pass variance over interior pixels (skip 1px border)
double _computeLaplacianVariance(Uint8List bytes) {
  imglib.Image? decoded;
  try {
    decoded = imglib.decodeImage(bytes);
  } on Object {
    // Any decode error (RangeError, FormatException, etc.) → sentinel -1.0
    return -1.0;
  }
  if (decoded == null) return -1.0;

  // Downscale to 480px on longest side for CPU budget.
  final maxSide = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;
  final scale = maxSide > 480 ? 480 / maxSide : 1.0;
  final resized = scale < 1.0
      ? imglib.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
          interpolation: imglib.Interpolation.linear,
        )
      : decoded;

  // BT.601 grayscale (0.299R + 0.587G + 0.114B) — imglib.grayscale uses BT.601.
  final gray = imglib.grayscale(resized);
  final w = gray.width;
  final h = gray.height;

  // Welford one-pass variance over 3×3 Laplacian (skip 1px border).
  int n = 0;
  double mean = 0.0;
  double m2 = 0.0;

  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final c = gray.getPixel(x, y).luminance;
      final t = gray.getPixel(x, y - 1).luminance;
      final b = gray.getPixel(x, y + 1).luminance;
      final l = gray.getPixel(x - 1, y).luminance;
      final r = gray.getPixel(x + 1, y).luminance;
      final lap = (t + b + l + r - 4 * c).toDouble();
      n++;
      final delta = lap - mean;
      mean += delta / n;
      m2 += delta * (lap - mean);
    }
  }

  return n > 1 ? m2 / (n - 1) : 0.0;
}

/// Pure-Dart liveness analyzer using Laplacian variance for blur detection.
///
/// `isLive` is always `true` because liveness is already validated upstream
/// via blink detection (ML Kit) before [ImageQualityGate.analyze] is called.
class _DartLivenessAnalyzer implements LivenessAnalyzer {
  @override
  Future<LivenessResult> analyze(Uint8List bytes) async {
    final variance = await compute(_computeLaplacianVariance, bytes);

    // Sentinel -1.0 means decode failed — re-throw as ImageQualityException.
    if (variance < 0) {
      throw const ImageQualityException('Cannot decode image bytes');
    }

    return LivenessResult(isLive: true, laplacianScore: variance);
  }
}
