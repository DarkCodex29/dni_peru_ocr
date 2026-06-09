import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Injectable abstraction over image compression.
abstract class ImageCompressor {
  Future<Uint8List> compress(
    String path, {
    int quality,
    int minWidth,
    int minHeight,
  });
}

/// Delegates to [FlutterImageCompress.compressWithFile].
class FlutterImageCompressor implements ImageCompressor {
  @override
  Future<Uint8List> compress(
    String path, {
    int quality = 92,
    int minWidth = 1600,
    int minHeight = 1000,
  }) async {
    final result = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: minWidth,
      minHeight: minHeight,
      quality: quality,
      autoCorrectionAngle: true,
      keepExif: false,
      format: CompressFormat.jpeg,
    );
    if (result == null) throw Exception('Compression failed for: $path');
    return result;
  }
}

/// Utility class for KYC image processing operations.
class KycImageUtils {
  KycImageUtils({ImageCompressor? compressor})
      : _compressor = compressor ?? FlutterImageCompressor();

  final ImageCompressor _compressor;

  /// Compresses an image at [imagePath] for KYC upload.
  Future<Uint8List> compressForUpload(String imagePath) =>
      _compressor.compress(imagePath);

  /// Crops a captured DNI photo to the document area. Returns [sourcePath] on failure.
  static Future<String> cropToDocumentArea(
    String sourcePath, {
    required double holeWidth,
    required double holeHeight,
    required Size screenSize,
    double paddingRatio = 0.02,
    int maxDimension = 3000,
  }) async {
    try {
      final bytes = await File(sourcePath).readAsBytes();
      var decoded = img.decodeImage(bytes);
      if (decoded == null) return sourcePath;

      if (decoded.width > maxDimension || decoded.height > maxDimension) {
        decoded = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: maxDimension)
            : img.copyResize(decoded, height: maxDimension);
      }

      final srcW = decoded.width;
      final srcH = decoded.height;

      final coverScale = (screenSize.width / srcW) > (screenSize.height / srcH)
          ? screenSize.width / srcW
          : screenSize.height / srcH;

      var cropW = (holeWidth / coverScale).round();
      var cropH = (holeHeight / coverScale).round();

      final padW = (cropW * paddingRatio).round();
      final padH = (cropH * paddingRatio).round();
      cropW = (cropW + 2 * padW).clamp(1, srcW);
      cropH = (cropH + 2 * padH).clamp(1, srcH);

      final cropped = img.copyCrop(
        decoded,
        x: ((srcW - cropW) / 2).round(),
        y: ((srcH - cropH) / 2).round(),
        width: cropW,
        height: cropH,
      );

      final tempDir = await getTemporaryDirectory();
      final outPath =
          '${tempDir.path}/kyc_cropped_${DateTime.now().microsecondsSinceEpoch}.png';
      await File(outPath).writeAsBytes(img.encodePng(cropped));
      return outPath;
    } on Object catch (_) {
      return sourcePath;
    }
  }
}
