import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/dni_peru_ocr.dart';

void main() {
  group('resolveEmptyOcrRoute (empty-OCR frame routing #5523)', () {
    test('empty OCR on a back phase with a valid quad dispatches the back '
        'trigger instead of skipping', () {
      expect(
        resolveEmptyOcrRoute(framingValid: true, isFrontPhase: false),
        EmptyOcrRoute.dispatchBackTrigger,
      );
    });

    test('empty OCR with NO valid quad skips even on a back phase '
        '(a blank frame with no document must never trigger)', () {
      expect(
        resolveEmptyOcrRoute(framingValid: false, isFrontPhase: false),
        EmptyOcrRoute.skip,
      );
    });

    test('empty OCR on a front phase skips even with a valid quad '
        '(front stays OCR-triggered, no wrong-side back trigger)', () {
      expect(
        resolveEmptyOcrRoute(framingValid: true, isFrontPhase: true),
        EmptyOcrRoute.skip,
      );
    });

    test('empty OCR on a front phase with no quad skips', () {
      expect(
        resolveEmptyOcrRoute(framingValid: false, isFrontPhase: true),
        EmptyOcrRoute.skip,
      );
    });
  });
}
