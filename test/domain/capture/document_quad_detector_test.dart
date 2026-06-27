/// RED tests for the DocumentQuadDetector domain port (PR3 — tasks 3.1-3.6).
///
/// Verifies the FFI-free port contract from the document-quad-detection spec:
/// 1. QuadCorner value type holds x,y doubles with value equality.
/// 2. QuadFrame value type carries the grayscale frame the isolate passes.
/// 3. QuadDetectionResult carries framingValid + ordered corners.
/// 4. QuadDetectionResult.invalid() is the canonical no-quad result.
/// 5. The port is implementable by a fake detector (interface shape).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

QuadFrame _frame({int width = 640, int height = 480}) {
  return QuadFrame(
    luminance: Uint8List(width * height),
    width: width,
    height: height,
    bytesPerRow: width,
    rotationDegrees: 0,
  );
}

/// Fake detector that proves the port is implementable in pure Dart and lets
/// us assert the contract semantics without any infrastructure dependency.
class _FakeQuadDetector implements DocumentQuadDetector {
  _FakeQuadDetector(this._result, {bool native = false}) : _native = native;

  final QuadDetectionResult _result;
  final bool _native;

  @override
  bool get isNativeAvailable => _native;

  @override
  QuadDetectionResult detectQuad(QuadFrame frame) => _result;

  @override
  Uint8List? rectify({
    required Uint8List imageBytes,
    required List<QuadCorner> corners,
  }) {
    if (corners.length != 4) return null;
    return imageBytes;
  }
}

void main() {
  group('QuadCorner', () {
    test('holds x and y as doubles', () {
      const corner = QuadCorner(12.5, 34.0);
      expect(corner.x, 12.5);
      expect(corner.y, 34.0);
    });

    test('two corners with the same coordinates are equal', () {
      const a = QuadCorner(1.0, 2.0);
      const b = QuadCorner(1.0, 2.0);
      expect(a, equals(b));
    });

    test('corners with different coordinates are not equal', () {
      const a = QuadCorner(1.0, 2.0);
      const b = QuadCorner(2.0, 1.0);
      expect(a, isNot(equals(b)));
    });
  });

  group('QuadFrame', () {
    test('carries luminance buffer plus dimensions and rotation', () {
      final luminance = Uint8List.fromList([1, 2, 3, 4]);
      final frame = QuadFrame(
        luminance: luminance,
        width: 2,
        height: 2,
        bytesPerRow: 2,
        rotationDegrees: 90,
      );
      expect(frame.luminance, same(luminance));
      expect(frame.width, 2);
      expect(frame.height, 2);
      expect(frame.bytesPerRow, 2);
      expect(frame.rotationDegrees, 90);
    });
  });

  group('QuadDetectionResult', () {
    test('valid result carries framingValid true and four ordered corners', () {
      const corners = [
        QuadCorner(0, 0),
        QuadCorner(10, 0),
        QuadCorner(10, 10),
        QuadCorner(0, 10),
      ];
      const result = QuadDetectionResult(framingValid: true, corners: corners);
      expect(result.framingValid, isTrue);
      expect(result.corners, hasLength(4));
      expect(result.corners.first, const QuadCorner(0, 0));
      expect(result.corners.last, const QuadCorner(0, 10));
    });

    test('invalid() yields framingValid false and an empty corner list', () {
      const result = QuadDetectionResult.invalid();
      expect(result.framingValid, isFalse);
      expect(result.corners, isEmpty);
    });
  });

  group('DocumentQuadDetector port — contract semantics (via fake)', () {
    test('well-framed document yields a valid four-corner quad', () {
      const corners = [
        QuadCorner(5, 5),
        QuadCorner(95, 5),
        QuadCorner(95, 95),
        QuadCorner(5, 95),
      ];
      final detector = _FakeQuadDetector(
        const QuadDetectionResult(framingValid: true, corners: corners),
      );

      final result = detector.detectQuad(_frame());

      expect(result.framingValid, isTrue);
      expect(result.corners, hasLength(4));
    });

    test('no quad found yields framingValid false with empty corners and no throw',
        () {
      final detector = _FakeQuadDetector(const QuadDetectionResult.invalid());

      expect(() => detector.detectQuad(_frame()), returnsNormally);
      final result = detector.detectQuad(_frame());
      expect(result.framingValid, isFalse);
      expect(result.corners, isEmpty);
    });

    test('rectify returns bytes when given exactly four corners', () {
      final detector = _FakeQuadDetector(const QuadDetectionResult.invalid());
      final bytes = Uint8List.fromList([9, 8, 7]);

      final out = detector.rectify(
        imageBytes: bytes,
        corners: const [
          QuadCorner(0, 0),
          QuadCorner(1, 0),
          QuadCorner(1, 1),
          QuadCorner(0, 1),
        ],
      );

      expect(out, isNotNull);
      expect(out, same(bytes));
    });

    test('rectify returns null when fewer than four corners are supplied', () {
      final detector = _FakeQuadDetector(const QuadDetectionResult.invalid());

      final out = detector.rectify(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        corners: const [QuadCorner(0, 0), QuadCorner(1, 1)],
      );

      expect(out, isNull);
    });

    test('isNativeAvailable reflects the implementation flag', () {
      final native = _FakeQuadDetector(
        const QuadDetectionResult.invalid(),
        native: true,
      );
      final pure = _FakeQuadDetector(const QuadDetectionResult.invalid());

      expect(native.isNativeAvailable, isTrue);
      expect(pure.isNativeAvailable, isFalse);
    });
  });

  group('DocumentQuadDetector port — dependency rule', () {
    test('port source imports no FFI, Flutter, opencv_dart, or dartcv4 type',
        () {
      final source = File(
        'lib/src/domain/capture/document_quad_detector.dart',
      ).readAsStringSync();

      expect(source.contains('dart:ffi'), isFalse);
      expect(source.contains('package:flutter/'), isFalse);
      expect(source.contains('package:opencv_dart/'), isFalse);
      expect(source.contains('package:dartcv4/'), isFalse);
    });
  });
}
