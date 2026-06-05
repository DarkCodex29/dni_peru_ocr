import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

class _DenoiseCase {
  const _DenoiseCase(this.input, this.expected, {required this.reason});
  final String input;
  final String expected;
  final String reason;
}

void main() {
  group('OcrFieldNormalizer.normalizeName', () {
    test('strips diacritics and uppercases', () {
      expect(OcrFieldNormalizer.normalizeName('José'), equals('JOSE'));
    });

    test('collapses multiple whitespace into single space', () {
      expect(
        OcrFieldNormalizer.normalizeName('  Juan   Carlos  '),
        equals('JUAN CARLOS'),
      );
    });

    test('handles accented characters: á é í ó ú ñ ü', () {
      expect(
        OcrFieldNormalizer.normalizeName('Ángel Ñoño Über'),
        equals('ANGEL NONO UBER'),
      );
    });

    test('already uppercase ASCII is unchanged (minus whitespace)', () {
      expect(
        OcrFieldNormalizer.normalizeName('JUAN CARLOS'),
        equals('JUAN CARLOS'),
      );
    });

    test('empty string returns empty string', () {
      expect(OcrFieldNormalizer.normalizeName(''), equals(''));
    });

    test('mixed case with diacritics: JOSÉ CARLOS normalizes correctly', () {
      expect(
        OcrFieldNormalizer.normalizeName('JOSÉ CARLOS'),
        equals('JOSE CARLOS'),
      );
    });

    test('denoises NXX before stripping diacritics (vote-key stability)', () {
      // MUNXXOZ → denoise → MUÑOZ → strip → MUNOZ
      // This guarantees noisy and clean frames collapse to the same vote bucket.
      expect(
        OcrFieldNormalizer.normalizeName('MUNXXOZ'),
        equals('MUNOZ'),
      );
    });
  });

  group('OcrFieldNormalizer.normalizeDocument', () {
    test('trims leading and trailing whitespace', () {
      expect(
        OcrFieldNormalizer.normalizeDocument('  12345678  '),
        equals('12345678'),
      );
    });

    test('removes internal spaces from document number', () {
      expect(
        OcrFieldNormalizer.normalizeDocument('1234 5678'),
        equals('12345678'),
      );
    });

    test('empty string returns empty string', () {
      expect(OcrFieldNormalizer.normalizeDocument(''), equals(''));
    });

    test('already clean document number is unchanged', () {
      expect(
        OcrFieldNormalizer.normalizeDocument('12345678'),
        equals('12345678'),
      );
    });
  });

  group('OcrFieldNormalizer.denoiseTildeNoise', () {
    // Table-driven coverage for the tilde-noise repair pattern.
    // Pattern requires 2-3 X's flanked by vowels/boundaries — single `NX`
    // is intentionally left untouched (false-positive guard for ANXIETY).
    const cases = <_DenoiseCase>[
      _DenoiseCase(
        'MUNXXOZ',
        'MUÑOZ',
        reason: 'NXX between vowels (uppercase)',
      ),
      _DenoiseCase('MUÑOZ', 'MUÑOZ', reason: 'already clean — no-op'),
      _DenoiseCase('MUNOZ', 'MUNOZ', reason: 'no noise marker — no-op'),
      _DenoiseCase('ERMITANXXO', 'ERMITAÑO', reason: 'NXX between A and O'),
      _DenoiseCase(
        'JUAN ERMITANXXO',
        'JUAN ERMITAÑO',
        reason: 'word boundary preserved',
      ),
      _DenoiseCase(
        'Juan PEÑA',
        'Juan PEÑA',
        reason: 'mixed case clean Ñ preserved',
      ),
      _DenoiseCase(
        'ANXIETY',
        'ANXIETY',
        reason: 'single-X surrounded by consonants → no match',
      ),
      _DenoiseCase('EXTRA', 'EXTRA', reason: 'EX with no N prefix → no match'),
      _DenoiseCase('TAXI', 'TAXI', reason: 'X without N prefix → no match'),
      _DenoiseCase('', '', reason: 'empty string passes through'),
      _DenoiseCase('NXX', 'Ñ', reason: 'NXX at both boundaries'),
      _DenoiseCase('MUNXXXOZ', 'MUÑOZ', reason: '3 X variant accepted'),
      _DenoiseCase(
        'MUNXOZ',
        'MUNXOZ',
        reason: 'single X is conservative no-op',
      ),
    ];

    for (final c in cases) {
      test('${c.reason}: "${c.input}" → "${c.expected}"', () {
        expect(
          OcrFieldNormalizer.denoiseTildeNoise(c.input),
          equals(c.expected),
        );
      });
    }

    test('lowercase neighbor produces lowercase ñ', () {
      // Replacement preserves surrounding case.
      expect(
        OcrFieldNormalizer.denoiseTildeNoise('munxxoz'),
        equals('muñoz'),
      );
    });
  });

  group('OcrFieldNormalizer.normalizeForDisplay', () {
    test('denoises NXX and uppercases the result', () {
      expect(
        OcrFieldNormalizer.normalizeForDisplay('MUNXXOZ'),
        equals('MUÑOZ'),
      );
    });

    test('uppercases a lowercase tilde-bearing input (keeps Ñ)', () {
      expect(
        OcrFieldNormalizer.normalizeForDisplay('muñoz'),
        equals('MUÑOZ'),
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        OcrFieldNormalizer.normalizeForDisplay('  MUÑOZ  '),
        equals('MUÑOZ'),
      );
    });

    test('preserves clean Ñ inside a multi-word name', () {
      expect(
        OcrFieldNormalizer.normalizeForDisplay('MUÑOZ GARCIA'),
        equals('MUÑOZ GARCIA'),
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Real Peruvian surname corruptions and clean cases.
  //
  // Surnames with Ñ, surnames with other tildes, and the ML Kit `NXX`
  // corruption pattern observed in production. Goal: regression-proof the
  // denoise+display pipeline against the actual surface area, not only the
  // canonical example (MUNXXOZ → MUÑOZ).
  //
  // Known limitations explicitly encoded here:
  //   • The Ñ-noise denoiser ONLY recovers Ñ. Other diacritics (Á, É, Í,
  //     Ó, Ú) are NOT recoverable from OCR; the underlying ML Kit
  //     corruption pattern for those is not `NXX` and is out of scope.
  //   • False-positive guards must hold for English words that happen to
  //     contain `NX` (single X) — they MUST stay untouched.
  // ──────────────────────────────────────────────────────────────────────────
  group('Real Peruvian surname corruptions and clean cases', () {
    const cases = <_DenoiseCase>[
      // ── Ñ recovery on common Peruvian surnames ────────────────────────────
      _DenoiseCase('IBANXXEZ', 'IBAÑEZ', reason: 'IBÁÑEZ → recovers Ñ'),
      _DenoiseCase(
        'CASTANXXEDA',
        'CASTAÑEDA',
        reason: 'CASTAÑEDA → recovers Ñ',
      ),
      _DenoiseCase('ZUNXXIGA', 'ZUÑIGA', reason: 'ZUÑIGA → recovers Ñ'),
      _DenoiseCase('OCANXXA', 'OCAÑA', reason: 'OCAÑA → recovers Ñ'),
      _DenoiseCase('MARINXXO', 'MARIÑO', reason: 'MARIÑO → recovers Ñ'),
      _DenoiseCase('PINXXERO', 'PIÑERO', reason: 'PIÑERO → recovers Ñ'),
      _DenoiseCase('BANXXOS', 'BAÑOS', reason: 'BAÑOS → recovers Ñ'),
      _DenoiseCase('ESCANXXO', 'ESCAÑO', reason: 'ESCAÑO → recovers Ñ'),
      _DenoiseCase('BRINXXEZ', 'BRIÑEZ', reason: 'BRIÑEZ → recovers Ñ'),
      _DenoiseCase('PENXXA', 'PEÑA', reason: 'PEÑA → recovers Ñ'),
      _DenoiseCase(
        'NUNXXEZ',
        'NUÑEZ',
        reason: 'NÚÑEZ → recovers Ñ only, Ú lost',
      ),
      _DenoiseCase(
        'ORDONXXEZ',
        'ORDOÑEZ',
        reason: 'ORDÓÑEZ → recovers Ñ only, Ó tilde out of scope',
      ),

      // ── Clean surnames preserved as-is ────────────────────────────────────
      _DenoiseCase('PEÑALOZA', 'PEÑALOZA', reason: 'PEÑALOZA already clean'),
      _DenoiseCase(
        'AÑAÑOS',
        'AÑAÑOS',
        reason: 'double-Ñ in same word preserved',
      ),
      _DenoiseCase('ÑAUPA', 'ÑAUPA', reason: 'leading Ñ preserved'),
      _DenoiseCase('IBÁÑEZ', 'IBÁÑEZ', reason: 'tilde + Ñ both preserved'),

      // ── Multi-word denoising in a single pass ─────────────────────────────
      _DenoiseCase(
        'JUAN CARLOS MUNXXOZ IBANXXEZ',
        'JUAN CARLOS MUÑOZ IBAÑEZ',
        reason: 'two surnames denoised in one input',
      ),
      _DenoiseCase(
        'MUNXXOZ PENXXA',
        'MUÑOZ PEÑA',
        reason: 'both paternal+maternal denoised',
      ),

      // ── False-positive guards: must NOT be touched ────────────────────────
      _DenoiseCase(
        'EXAMEN',
        'EXAMEN',
        reason: 'no N prefix → not touched',
      ),
      _DenoiseCase(
        'MEXICO',
        'MEXICO',
        reason: 'X between vowels but no N prefix → not touched',
      ),
      _DenoiseCase(
        'EXITO',
        'EXITO',
        reason: 'X between vowels but no N prefix → not touched',
      ),
      _DenoiseCase(
        'ANXIETY',
        'ANXIETY',
        reason: 'single X (English word) → conservative no-op',
      ),
      _DenoiseCase(
        'MUNXOZ',
        'MUNXOZ',
        reason: 'single X variant → conservative no-op',
      ),
      _DenoiseCase(
        'MUNXXXXOZ',
        'MUNXXXXOZ',
        reason: '4 X variant outside 2-3 pattern → no-op',
      ),

      // ── Real Peruvian Quechua surnames with Ñ ─────────────────────────────
      // QUISPE is the #1 surname in Peru; HUAMÁN, MAMANI, CONDORI are
      // top-30. These cases pin denoise behavior on Quechua names where Ñ
      // + Ñ recovery + clean Quechua surnames must all pass through
      // unchanged or recover cleanly.
      _DenoiseCase(
        'MUNXXOZ ÑAUPARI',
        'MUÑOZ ÑAUPARI',
        reason: 'Quechua maternal ÑAUPARI preserved while paterno denoised',
      ),
      _DenoiseCase(
        'HUAMAN ÑIQUEN',
        'HUAMAN ÑIQUEN',
        reason: 'clean Quechua paterno + Ñ maternal — no-op',
      ),
      _DenoiseCase(
        'NXXAUPARI HUAMAN',
        'ÑAUPARI HUAMAN',
        reason: 'NXX recovery at word boundary on Quechua surname',
      ),
    ];

    for (final c in cases) {
      test('${c.reason}: "${c.input}" → "${c.expected}"', () {
        expect(
          OcrFieldNormalizer.denoiseTildeNoise(c.input),
          equals(c.expected),
        );
      });
    }

    test(
      'normalizeForDisplay handles full Peruvian name w/ multiple noise points',
      () {
        expect(
          OcrFieldNormalizer.normalizeForDisplay(
            'juan carlos munxxoz ibanxxez',
          ),
          equals('JUAN CARLOS MUÑOZ IBAÑEZ'),
        );
      },
    );

    test(
      'normalizeForDisplay preserves tildes that are already in the input',
      () {
        expect(
          OcrFieldNormalizer.normalizeForDisplay('garcía pérez'),
          equals('GARCÍA PÉREZ'),
        );
      },
    );

    test(
      'normalizeForDisplay handles compound first name with multiple tildes',
      () {
        expect(
          OcrFieldNormalizer.normalizeForDisplay('maría jesús'),
          equals('MARÍA JESÚS'),
        );
      },
    );
  });

  group('OcrFieldNormalizer.normalizeDate', () {
    test('trims leading and trailing whitespace', () {
      expect(
        OcrFieldNormalizer.normalizeDate('  01/01/1990  '),
        equals('01/01/1990'),
      );
    });

    test('already clean date is unchanged', () {
      expect(
        OcrFieldNormalizer.normalizeDate('01/01/1990'),
        equals('01/01/1990'),
      );
    });

    test('empty string returns empty string', () {
      expect(OcrFieldNormalizer.normalizeDate(''), equals(''));
    });

    test('ISO format date is passed through trimmed', () {
      expect(
        OcrFieldNormalizer.normalizeDate('  2030-12-31  '),
        equals('2030-12-31'),
      );
    });
  });
}
