/// RED tests for the pure-Dart FallbackQuadDetector (PR3 — tasks 3.9-3.10).
///
/// Verifies the capability-gated fallback contract from the
/// document-quad-detection spec:
/// 1. isNativeAvailable is always false (no native binary).
/// 2. detectQuad returns the honest no-quad result — framingValid false,
///    empty corners — and NEVER fabricates a quad, on any frame.
/// 3. detectQuad never throws.
/// 4. rectify is unsupported in pure Dart and returns null (never throws).
/// 5. The fallback source imports no FFI/opencv/dartcv type.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

QuadFrame _frame({
  int width = 640,
  int height = 480,
  List<int>? fill,
}) {
  final buffer = Uint8List(width * height);
  if (fill != null) {
    for (var i = 0; i < buffer.length && i < fill.length; i++) {
      buffer[i] = fill[i];
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

void main() {
  late FallbackQuadDetector detector;

  setUp(() => detector = const FallbackQuadDetector());

  group('FallbackQuadDetector — capability flag', () {
    test('isNativeAvailable is false', () {
      expect(detector.isNativeAvailable, isFalse);
    });

    test('is a DocumentQuadDetector', () {
      expect(detector, isA<DocumentQuadDetector>());
    });
  });

  group('FallbackQuadDetector — honest no-quad detection', () {
    test('detectQuad on an empty frame reports framingValid false', () {
      final result = detector.detectQuad(_frame());
      expect(result.framingValid, isFalse);
      expect(result.corners, isEmpty);
    });

    test('detectQuad on a textured frame still fabricates no quad', () {
      // A frame full of high-contrast values would tempt a real detector to
      // find edges; the fallback must STILL return no quad — it never guesses.
      final result = detector.detectQuad(
        _frame(fill: List<int>.generate(64, (i) => i.isEven ? 0 : 255)),
      );
      expect(result.framingValid, isFalse);
      expect(result.corners, isEmpty);
    });

    test('detectQuad never throws regardless of frame dimensions', () {
      expect(
        () => detector.detectQuad(_frame(width: 1, height: 1)),
        returnsNormally,
      );
    });
  });

  group('FallbackQuadDetector — rectify unsupported', () {
    test('rectify returns null even with four corners (no native warp)', () {
      final out = detector.rectify(
        imageBytes: Uint8List.fromList([1, 2, 3, 4]),
        corners: const [
          QuadCorner(0, 0),
          QuadCorner(1, 0),
          QuadCorner(1, 1),
          QuadCorner(0, 1),
        ],
      );
      expect(out, isNull);
    });

    test('rectify returns null with fewer than four corners and never throws',
        () {
      expect(
        () => detector.rectify(
          imageBytes: Uint8List.fromList([1, 2, 3]),
          corners: const [QuadCorner(0, 0)],
        ),
        returnsNormally,
      );
      final out = detector.rectify(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        corners: const [QuadCorner(0, 0)],
      );
      expect(out, isNull);
    });
  });

  group('FallbackQuadDetector — dependency rule', () {
    test('source imports no FFI, opencv_dart, or dartcv4 type', () {
      final source = File(
        'lib/src/infrastructure/fallback_quad_detector.dart',
      ).readAsStringSync();

      expect(source.contains('dart:ffi'), isFalse);
      expect(source.contains('package:opencv_dart/'), isFalse);
      expect(source.contains('package:dartcv4/'), isFalse);
    });
  });
}
