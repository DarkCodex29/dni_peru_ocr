import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:dni_peru_ocr/src/presentation/widgets/dni_scanner.dart';

void main() {
  group('DniScanner crop path (isolate JPEG q97)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('dni_crop_test');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('crops the centered document area and encodes JPEG', () {
      final source = img.Image(width: 1200, height: 800);
      img.fill(source, color: img.ColorRgb8(255, 255, 255));
      final sourcePath = '${tempDir.path}/source.jpg';
      File(sourcePath).writeAsBytesSync(img.encodeJpg(source));

      final outPath = '${tempDir.path}/cropped.jpg';
      final result = cropAndEncodeForTest(
        CropRequestForTest(
          sourcePath: sourcePath,
          outPath: outPath,
          previewWidth: 400,
          previewHeight: 800,
          holeWidth: 300,
          holeHeight: 220,
        ),
      );

      expect(result, outPath);
      final outBytes = File(outPath).readAsBytesSync();
      final decoded = img.decodeImage(outBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThan(source.width));
      expect(decoded.height, lessThan(source.height));
      expect(img.findDecoderForData(outBytes), isA<img.JpegDecoder>());
    });

    test('crop dimensions scale with a different source/preview ratio', () {
      final source = img.Image(width: 2400, height: 1600);
      img.fill(source, color: img.ColorRgb8(10, 20, 30));
      final sourcePath = '${tempDir.path}/wide.jpg';
      File(sourcePath).writeAsBytesSync(img.encodeJpg(source));

      final outPath = '${tempDir.path}/wide_cropped.jpg';
      final result = cropAndEncodeForTest(
        CropRequestForTest(
          sourcePath: sourcePath,
          outPath: outPath,
          previewWidth: 360,
          previewHeight: 640,
          holeWidth: 320,
          holeHeight: 200,
        ),
      );

      expect(result, outPath);
      final decoded = img.decodeImage(File(outPath).readAsBytesSync());
      expect(decoded, isNotNull);
      expect(decoded!.width, greaterThan(0));
      expect(decoded.width, lessThanOrEqualTo(source.width));
      expect(decoded.height, lessThanOrEqualTo(source.height));
    });
  });
}
