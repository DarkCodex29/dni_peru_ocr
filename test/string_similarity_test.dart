import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StringSimilarity.distance', () {
    test('returns 0 for identical strings', () {
      expect(StringSimilarity.distance('ERMITANO', 'ERMITANO'), 0);
    });

    test('returns 0 for two empty strings', () {
      expect(StringSimilarity.distance('', ''), 0);
    });

    test('returns length when one side is empty', () {
      expect(StringSimilarity.distance('', 'HELLO'), 5);
      expect(StringSimilarity.distance('HELLO', ''), 5);
    });

    test('counts single insertion as 1', () {
      expect(StringSimilarity.distance('JOSE', 'JOSEA'), 1);
    });

    test('counts single deletion as 1', () {
      expect(StringSimilarity.distance('JOSEA', 'JOSE'), 1);
    });

    test('counts single substitution as 1', () {
      expect(StringSimilarity.distance('JOSE', 'JOSA'), 1);
    });

    test('handles the real OCR case ERMITANO vs ERMITANXXO', () {
      // OCR added "XX" before final "O" → 2 insertions.
      expect(StringSimilarity.distance('ERMITANO', 'ERMITANXXO'), 2);
    });

    test('is symmetric', () {
      expect(
        StringSimilarity.distance('ERMITANO', 'ERMITANXXO'),
        StringSimilarity.distance('ERMITANXXO', 'ERMITANO'),
      );
    });

    test('counts full mismatch as max length', () {
      expect(StringSimilarity.distance('ABC', 'XYZ'), 3);
    });
  });

  group('StringSimilarity.similarity', () {
    test('returns 1.0 for identical strings', () {
      expect(StringSimilarity.similarity('JOSE', 'JOSE'), 1.0);
    });

    test('returns 1.0 for two empty strings', () {
      expect(StringSimilarity.similarity('', ''), 1.0);
    });

    test('returns 0.0 when one side is empty', () {
      expect(StringSimilarity.similarity('', 'HELLO'), 0.0);
      expect(StringSimilarity.similarity('HELLO', ''), 0.0);
    });

    test('returns 0.8 for ERMITANO vs ERMITANXXO (2 inserts of 10)', () {
      // distance=2, maxLen=10 → 1 - 0.2 = 0.8
      expect(
        StringSimilarity.similarity('ERMITANO', 'ERMITANXXO'),
        closeTo(0.8, 0.001),
      );
    });

    test('returns 0.0 for full mismatch ABC vs XYZ', () {
      expect(StringSimilarity.similarity('ABC', 'XYZ'), 0.0);
    });

    test('reflects 1 substitution in 4-char string as 0.75', () {
      // JOSE vs JOSA: distance=1, maxLen=4 → 1 - 0.25 = 0.75
      expect(
        StringSimilarity.similarity('JOSE', 'JOSA'),
        closeTo(0.75, 0.001),
      );
    });
  });

  group('StringSimilarity.isMatch', () {
    test('identical strings match at any threshold', () {
      expect(StringSimilarity.isMatch('JOSE', 'JOSE'), isTrue);
      expect(
        StringSimilarity.isMatch('JOSE', 'JOSE', threshold: 1.0),
        isTrue,
      );
    });

    test('ERMITANO vs ERMITANXXO matches at default threshold (0.80)', () {
      // similarity = 0.8 → exactly at threshold → match
      expect(
        StringSimilarity.isMatch('ERMITANO', 'ERMITANXXO'),
        isTrue,
      );
    });

    test('ERMITANO vs ERMITANXXO does NOT match at threshold 0.85', () {
      // similarity = 0.8 < 0.85 → no match
      expect(
        StringSimilarity.isMatch(
          'ERMITANO',
          'ERMITANXXO',
          threshold: 0.85,
        ),
        isFalse,
      );
    });

    test('completely different names do not match', () {
      expect(
        StringSimilarity.isMatch('GARCIA', 'PEREZ'),
        isFalse,
      );
    });

    test('1 char off in a 4-char name is below default threshold', () {
      // JOSE vs JOSA: similarity 0.75 < 0.80 → no match.
      // This is intentional: short names need to be near-exact.
      expect(
        StringSimilarity.isMatch('JOSE', 'JOSA'),
        isFalse,
      );
    });

    test('1 char off in a long surname passes default threshold', () {
      // RODRIGUEZ vs RODRIGUEX: distance=1, maxLen=9
      // similarity = 0.888... → above 0.80 → match
      expect(
        StringSimilarity.isMatch('RODRIGUEZ', 'RODRIGUEX'),
        isTrue,
      );
    });
  });
}
