import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StabilityState.update', () {
    test('increments when blockDiff <= 2 and frame is not empty', () {
      final next = StabilityState.update(
        current: 3,
        blockDiff: 2,
        isEmpty: false,
      );
      expect(next, 4);
    });

    test('decrements when blockDiff exceeds 2', () {
      final next = StabilityState.update(
        current: 3,
        blockDiff: 3,
        isEmpty: false,
      );
      expect(next, 2);
    });

    test('decrements when frame is empty even if blockDiff is small', () {
      final next = StabilityState.update(
        current: 5,
        blockDiff: 0,
        isEmpty: true,
      );
      expect(next, 4);
    });

    test('floors the counter at zero when decrementing from zero', () {
      final next = StabilityState.update(
        current: 0,
        blockDiff: 9,
        isEmpty: false,
      );
      expect(next, 0);
    });
  });
}
