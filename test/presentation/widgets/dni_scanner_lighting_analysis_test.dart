import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/domain/entities/validation_gate.dart';
import 'package:dni_peru_ocr/src/presentation/widgets/dni_scanner.dart';

List<int> _plane(int value, {required int width, required int height}) =>
    List<int>.filled(width * height, value);

void main() {
  group('analyzeLuminancePlaneForTest — downscaled luminance gate', () {
    test('dark plane is rejected as lighting', () {
      final result = analyzeLuminancePlaneForTest(
        luminancePlane: _plane(15, width: 320, height: 240),
        bytesPerRow: 320,
        width: 320,
        height: 240,
      );

      expect(result.isValid, isFalse);
      expect(result.failing, ValidationGate.lighting);
    });

    test('well-lit plane is valid', () {
      final result = analyzeLuminancePlaneForTest(
        luminancePlane: _plane(140, width: 320, height: 240),
        bytesPerRow: 320,
        width: 320,
        height: 240,
      );

      expect(result.isValid, isTrue);
      expect(result.failing, isNull);
    });

    test('over-bright plane is rejected', () {
      final result = analyzeLuminancePlaneForTest(
        luminancePlane: _plane(250, width: 320, height: 240),
        bytesPerRow: 320,
        width: 320,
        height: 240,
      );

      expect(result.isValid, isFalse);
    });

    test('row padding (bytesPerRow > width) is respected without overflow', () {
      const width = 100;
      const height = 80;
      const bytesPerRow = 128;
      final plane = List<int>.filled(bytesPerRow * height, 140);

      final result = analyzeLuminancePlaneForTest(
        luminancePlane: plane,
        bytesPerRow: bytesPerRow,
        width: width,
        height: height,
      );

      expect(result.isValid, isTrue);
    });

    test('empty plane is rejected as lighting', () {
      final result = analyzeLuminancePlaneForTest(
        luminancePlane: const <int>[],
        bytesPerRow: 0,
        width: 0,
        height: 0,
      );

      expect(result.isValid, isFalse);
      expect(result.failing, ValidationGate.lighting);
    });
  });
}
