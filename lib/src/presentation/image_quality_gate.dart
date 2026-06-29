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

  final double laplacianScore;
}

class ImageQualityException implements Exception {
  const ImageQualityException(this.message);
  final String message;

  @override
  String toString() => 'ImageQualityException: $message';
}

class LivenessResult {
  const LivenessResult({required this.isLive, required this.laplacianScore});
  final bool isLive;
  final double laplacianScore;
}

abstract class LivenessAnalyzer {
  Future<LivenessResult> analyze(Uint8List bytes);
}

class ImageQualityGate {
  ImageQualityGate({LivenessAnalyzer? analyzer})
      : _analyzer = analyzer ?? _DartLivenessAnalyzer();

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

  Future<QualityCheckResult> validate(Uint8List bytes) async {
    imglib.Image? decoded;
    try {
      decoded = imglib.decodeImage(bytes);
    } on Object {
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

double _computeLaplacianVariance(Uint8List bytes) {
  imglib.Image? decoded;
  try {
    decoded = imglib.decodeImage(bytes);
  } on Object {
    return -1.0;
  }
  if (decoded == null) return -1.0;

  final maxSide =
      decoded.width > decoded.height ? decoded.width : decoded.height;
  final scale = maxSide > 480 ? 480 / maxSide : 1.0;
  final resized = scale < 1.0
      ? imglib.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
          interpolation: imglib.Interpolation.linear,
        )
      : decoded;

  final gray = imglib.grayscale(resized);
  final w = gray.width;
  final h = gray.height;

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

class _DartLivenessAnalyzer implements LivenessAnalyzer {
  @override
  Future<LivenessResult> analyze(Uint8List bytes) async {
    final variance = await compute(_computeLaplacianVariance, bytes);

    if (variance < 0) {
      throw const ImageQualityException('Cannot decode image bytes');
    }

    return LivenessResult(isLive: true, laplacianScore: variance);
  }
}
