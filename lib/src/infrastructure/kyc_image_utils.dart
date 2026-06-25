import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

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
}
