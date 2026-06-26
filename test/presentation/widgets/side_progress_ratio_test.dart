import 'package:dni_peru_ocr/src/presentation/widgets/dni_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sideProgressRatio (#5494 honest side indicator)', () {
    test('a side that is NOT done never reports 100% even when the raw '
        'field count fills the side total', () {
      // The misleading bug: the back dot read "100%" (backFilled/backTotal =
      // 7/7) while the capture trigger — governed by stability + side-safety,
      // not the raw field count — had NOT fired. A not-done side must never
      // display 100% because 100% implies an imminent/complete capture that
      // the field count cannot promise.
      final ratio = sideProgressRatio(filled: 7, total: 7, done: false);
      expect(
        ratio,
        lessThan(1.0),
        reason: 'a full field count must not read as 100% while the side has '
            'not actually captured',
      );
    });

    test('a captured (done) side reports exactly 100%', () {
      // Once the side is genuinely captured the indicator legitimately shows
      // 100% — that is the only honest path to a full ring.
      final ratio = sideProgressRatio(filled: 3, total: 7, done: true);
      expect(ratio, 1.0);
    });

    test('partial data on a not-done side reports the proportional ratio '
        'below the honest ceiling', () {
      // While scanning, the indicator still grows with data so the user sees
      // progress — it just never claims completion until capture fires.
      final ratio = sideProgressRatio(filled: 2, total: 7, done: false);
      expect(ratio, closeTo(2 / 7, 1e-9));
      expect(ratio, lessThan(1.0));
    });

    test('an over-filled not-done side is still capped strictly below 100%', () {
      // Carried-over fields can push filled past the side total; the ratio
      // must still never hit 100% until the side is done.
      final ratio = sideProgressRatio(filled: 20, total: 7, done: false);
      expect(ratio, lessThan(1.0));
      expect(ratio, greaterThan(0.0));
    });

    test('a zero/invalid total never divides by zero and stays in range', () {
      final ratio = sideProgressRatio(filled: 5, total: 0, done: false);
      expect(ratio, inInclusiveRange(0.0, 1.0));
      expect(ratio, lessThan(1.0));
    });
  });
}
