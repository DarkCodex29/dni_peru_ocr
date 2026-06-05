import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrz_parser/mrz_parser.dart';

void main() {
  // ── helpers ────────────────────────────────────────────────────────────────

  MRZResult fakeMrz({
    String documentNumber = '12345678',
    String surnames = 'GARCIA LOPEZ',
    String givenNames = 'JUAN',
    DateTime? birthDate,
    DateTime? expiryDate,
  }) {
    return MRZResult(
      documentType: 'TD1',
      countryCode: 'PER',
      surnames: surnames,
      givenNames: givenNames,
      documentNumber: documentNumber,
      nationalityCountryCode: 'PER',
      birthDate: birthDate ?? DateTime(1990, 1, 15),
      sex: Sex.male,
      expiryDate: expiryDate ?? DateTime(2030, 12, 31),
      personalNumber: '',
    );
  }

  // ── Scenario 1: vote accumulation ─────────────────────────────────────────
  group('Scenario 1 — vote accumulation', () {
    test('records a vote for each non-null extracted field', () {
      final builder = OcrConsensusAccumulator()
        ..recordVote({'documentNumber': '12345678', 'firstName': 'JUAN'})
        ..recordVote({'documentNumber': '12345678'});

      final snap = builder.snapshot();
      expect(snap.documentNumber.value, '12345678');
      // confidence reflects 2 votes with 100% agreement
      expect(snap.documentNumber.confidence, greaterThan(0));
      builder.dispose();
    });
  });

  // ── Scenario 2: blank frame skipped ───────────────────────────────────────
  group('Scenario 2 — blank frame skipped', () {
    test('null / empty values do not change the vote map', () {
      final builder = OcrConsensusAccumulator()
        ..recordVote({'documentNumber': '12345678'})
        ..recordVote({'documentNumber': null})
        ..recordVote({'documentNumber': ''});

      final snap = builder.snapshot();
      // still only 1 effective vote for documentNumber
      expect(snap.documentNumber.value, '12345678');
      builder.dispose();
    });
  });

  // ── Scenario 3: documentNumber reaches 95% threshold ──────────────────────
  group('Scenario 3 — documentNumber 95% threshold', () {
    test('documentNumber locks when 95% of votes agree', () {
      final builder = OcrConsensusAccumulator();
      // 19 votes for correct, 1 for noise → 95%
      for (var i = 0; i < 19; i++) {
        builder.recordVote({'documentNumber': '12345678'});
      }
      builder.recordVote({'documentNumber': '99999999'});

      // Check the individual field result directly via snapshot
      final snap = builder.snapshot();
      expect(snap.documentNumber.locked, isTrue);
      expect(snap.documentNumber.value, '12345678');
      expect(snap.documentNumber.confidence, closeTo(0.95, 0.01));
      builder.dispose();
    });
  });

  // ── Scenario 4: name normalization deems variants equal ───────────────────
  group('Scenario 4 — name normalization', () {
    test('JOSE CARLOS and JOSÉ CARLOS count as the same vote', () {
      final builder = OcrConsensusAccumulator();
      for (var i = 0; i < 16; i++) {
        builder.recordVote({'firstName': 'JOSE CARLOS'});
      }
      for (var i = 0; i < 4; i++) {
        builder.recordVote({'firstName': 'JOSÉ CARLOS'});
      }

      // all 20 votes should map to the same normalized key
      final snap = builder.snapshot();
      expect(snap.firstName.locked, isTrue);
      expect(snap.firstName.confidence, closeTo(1.0, 0.01));
      builder.dispose();
    });
  });

  // ── Scenario 4b: display map preserves Ñ across noisy + clean frames ──
  // Three frames `MUÑOZ`, `MUNXXOZ`, `MUNOZ` must all collapse to the
  // same vote-key and surface `MUÑOZ` as the result.
  group('Scenario 4b — display value preserves Ñ', () {
    test('clean Ñ wins over ASCII when both share the vote-key', () {
      final builder = OcrConsensusAccumulator()
        ..recordVote({'lastName': 'MUÑOZ'})
        ..recordVote({'lastName': 'MUNXXOZ'})
        ..recordVote({'lastName': 'MUNOZ'});

      final snap = builder.snapshot();
      expect(snap.lastName.value, 'MUÑOZ');
      // 3 frames, same vote-key → confidence 1.0
      expect(snap.lastName.confidence, closeTo(1.0, 0.01));
      builder.dispose();
    });

    test('noisy-only frames still surface the repaired Ñ', () {
      final builder = OcrConsensusAccumulator();
      for (var i = 0; i < 3; i++) {
        builder.recordVote({'lastName': 'MUNXXOZ'});
      }

      final snap = builder.snapshot();
      expect(snap.lastName.value, 'MUÑOZ');
      builder.dispose();
    });
  });

  // ── Scenario 7b: MRZ-Ñ recovery from text-OCR display map ──────────────
  group('Scenario 7b — MRZ-Ñ recovery', () {
    test('text-OCR voted Ñ, MRZ says plain N → result keeps Ñ', () {
      final builder = OcrConsensusAccumulator();
      // 3 noisy text-OCR frames build a Ñ in the display map
      for (var i = 0; i < 3; i++) {
        builder.recordVote({'lastName': 'MUNXXOZ'});
      }
      // MRZ delivers the plain-ASCII variant (typical for Peruvian DNIs)
      builder
        ..lockFromMrzFields(
          documentNumber: '12345678',
          firstName: 'JUAN',
          lastName: 'MUNOZ',
          secondLastName: null,
          dateOfBirth: '01/01/1990',
          expirationDate: '31/12/2030',
        )
        ..lockFromMrzFields(
          documentNumber: '12345678',
          firstName: 'JUAN',
          lastName: 'MUNOZ',
          secondLastName: null,
          dateOfBirth: '01/01/1990',
          expirationDate: '31/12/2030',
        );

      final snap = builder.snapshot();
      expect(snap.source, OcrConsensusSource.mrzChecksum);
      // MRZ does NOT overwrite the tilde recovered by text-OCR.
      expect(snap.lastName.value, 'MUÑOZ');
      builder.dispose();
    });
  });

  // ── Scenario 5: date exact-match in 4 of last 5 frames ────────────────────
  group('Scenario 5 — date 4-of-5 lock', () {
    test('expirationDate locks when 4 of last 5 frames agree', () {
      final builder = OcrConsensusAccumulator()
        ..recordVote({'expirationDate': '2030-12-31'})
        ..recordVote({'expirationDate': '2030-12-31'})
        ..recordVote({'expirationDate': '2030-12-31'})
        ..recordVote({'expirationDate': '2030-12-31'})
        ..recordVote({'expirationDate': 'noise'});

      // last 5 = [2030-12-31 x4, noise x1] → 4 matches ≥ threshold
      final snap = builder.snapshot();
      expect(snap.expirationDate.locked, isTrue);
      expect(snap.expirationDate.value, '2030-12-31');
      builder.dispose();
    });
  });

  // ── Scenario 6: MRZ consecutive-2 fast-lock ───────────────────────────────
  group('Scenario 6 — MRZ consecutive-2 fast-lock', () {
    test('locks all MRZ fields after 2 consecutive valid MRZ parses', () {
      final builder = OcrConsensusAccumulator();
      final mrz = fakeMrz();
      builder
        ..recordMrz(mrz)
        ..recordMrz(mrz);

      expect(builder.checkAllThresholds(), isTrue);
      final snap = builder.snapshot();
      expect(snap.source, OcrConsensusSource.mrzChecksum);
      expect(snap.documentNumber.locked, isTrue);
      expect(snap.firstName.locked, isTrue);
      expect(snap.lastName.locked, isTrue);
      expect(snap.dateOfBirth.locked, isTrue);
      expect(snap.expirationDate.locked, isTrue);
      builder.dispose();
    });
  });

  // ── Scenario 7: MRZ wins over text-OCR disagreement ──────────────────────
  group('Scenario 7 — MRZ wins over text-OCR', () {
    test('MRZ documentNumber overrides text-OCR vote majority', () {
      final builder = OcrConsensusAccumulator();
      // build up text-OCR votes for wrong number
      for (var i = 0; i < 15; i++) {
        builder.recordVote({'documentNumber': '12345879'});
      }
      // MRZ fast-lock with correct number
      final mrz = fakeMrz(documentNumber: '12345678');
      builder
        ..recordMrz(mrz)
        ..recordMrz(mrz);

      final snap = builder.snapshot();
      expect(snap.source, OcrConsensusSource.mrzChecksum);
      expect(snap.documentNumber.value, '12345678');
      builder.dispose();
    });
  });

  // ── Scenario 8: noise discarded by vote ──────────────────────────────────
  group('Scenario 8 — noise discarded by vote', () {
    test('garbled noise frames are statistically outvoted', () {
      final builder = OcrConsensusAccumulator();
      // 18 correct, 2 noise — 18/20 = 90% < 95%, not yet locked
      for (var i = 0; i < 18; i++) {
        builder.recordVote({'documentNumber': '12345678'});
      }
      builder
        ..recordVote({'documentNumber': 'GARBAGE'})
        ..recordVote({'documentNumber': 'GARBAGE'});

      // 18/20 = 90% → not locked yet
      var snap = builder.snapshot();
      expect(snap.documentNumber.locked, isFalse);

      // Add enough to cross 95%: need correct/total >= 0.95
      // With 2 noise fixed, need C >= 0.95 * (C + 2) → C >= 38
      // We have 18, need 20 more
      for (var i = 0; i < 20; i++) {
        builder.recordVote({'documentNumber': '12345678'});
      }
      // 38 correct, 2 noise = 38/40 = 95% → locks
      snap = builder.snapshot();
      expect(snap.documentNumber.locked, isTrue);
      expect(snap.documentNumber.value, '12345678');
      builder.dispose();
    });
  });

  // ── OcrConsensusResult structure ──────────────────────────────────────────
  group('OcrConsensusResult structure', () {
    test(
      'success = false and source = manualFallback when not fully locked',
      () {
        final builder = OcrConsensusAccumulator()
          ..recordVote({'documentNumber': '12345678'});
        final snap = builder.snapshot();
        // only 1 vote — not locked
        expect(snap.success, isFalse);
        expect(snap.source, OcrConsensusSource.manualFallback);
        builder.dispose();
      },
    );
  });

  // ── lockFromMrzFields ─────────────────────────────────────────────────────
  group('lockFromMrzFields', () {
    test('locks all fields after 2 consecutive MRZ-field observations', () {
      // First MRZ frame — not locked yet
      final builder = OcrConsensusAccumulator()
        ..lockFromMrzFields(
          documentNumber: '71542895',
          firstName: 'JOSE CARLOS',
          lastName: 'LOPEZ',
          secondLastName: null,
          dateOfBirth: '01/09/1994',
          expirationDate: '26/12/2029',
        );
      expect(builder.isMrzLocked, isFalse, reason: 'needs 2 consecutive');

      // Second consecutive MRZ frame — should lock
      builder.lockFromMrzFields(
        documentNumber: '71542895',
        firstName: 'JOSE CARLOS',
        lastName: 'LOPEZ',
        secondLastName: null,
        dateOfBirth: '01/09/1994',
        expirationDate: '26/12/2029',
      );
      expect(builder.isMrzLocked, isTrue);

      final snap = builder.snapshot();
      expect(snap.success, isTrue);
      expect(snap.source, OcrConsensusSource.mrzChecksum);
      expect(snap.documentNumber.value, '71542895');
      expect(snap.firstName.value, 'JOSE CARLOS');
      expect(snap.lastName.value, 'LOPEZ');
      expect(snap.dateOfBirth.value, '01/09/1994');
      expect(snap.expirationDate.value, '26/12/2029');
      expect(snap.documentNumber.locked, isTrue);

      builder.dispose();
    });

    test(
      'MRZ-only frame with no text-OCR vote → stores MRZ value as-is',
      () {
        final builder = OcrConsensusAccumulator()
          ..lockFromMrzFields(
            documentNumber: '12345678',
            firstName: 'JUAN',
            lastName: 'GARCIA',
            secondLastName: null,
            dateOfBirth: '01/01/1990',
            expirationDate: '31/12/2030',
          )
          ..lockFromMrzFields(
            documentNumber: '12345678',
            firstName: 'JUAN',
            lastName: 'GARCIA',
            secondLastName: null,
            dateOfBirth: '01/01/1990',
            expirationDate: '31/12/2030',
          );

        final snap = builder.snapshot();
        expect(snap.lastName.value, 'GARCIA');
        builder.dispose();
      },
    );

    test(
      'document number MRZ override is unaffected by display map',
      () {
        final builder = OcrConsensusAccumulator();
        // text-OCR votes a wrong but tilde-free number
        for (var i = 0; i < 5; i++) {
          builder.recordVote({'documentNumber': '11111111'});
        }
        builder
          ..lockFromMrzFields(
            documentNumber: '99999999',
            firstName: 'JUAN',
            lastName: 'GARCIA',
            secondLastName: null,
            dateOfBirth: '01/01/1990',
            expirationDate: '31/12/2030',
          )
          ..lockFromMrzFields(
            documentNumber: '99999999',
            firstName: 'JUAN',
            lastName: 'GARCIA',
            secondLastName: null,
            dateOfBirth: '01/01/1990',
            expirationDate: '31/12/2030',
          );

        final snap = builder.snapshot();
        expect(snap.documentNumber.value, '99999999');
        builder.dispose();
      },
    );

    // ── Real Peruvian votes — Ñ recovery in surname/firstName ───────────────
    //
    // These scenarios exercise the full consensus pipeline with real-data
    // shapes: noisy frames that should denoise into Ñ-bearing surnames,
    // tilde-only variants that the upgrade rule does NOT cover (by design),
    // and the MRZ-paterno-only limitation documented as a test.
    // ────────────────────────────────────────────────────────────────────────
    group('Real Peruvian votes — Ñ recovery in surname/firstName', () {
      test(
        'noisy IBANXXEZ in a 3-frame vote → displayValue surfaces IBAÑEZ',
        () {
          final builder = OcrConsensusAccumulator()
            ..recordVote({'lastName': 'IBANEZ'})
            ..recordVote({'lastName': 'IBANXXEZ'})
            ..recordVote({'lastName': 'IBANEZ'});

          final snap = builder.snapshot();
          // Same vote-key (IBANEZ) but the noisy frame produced the Ñ-bearing
          // display variant — upgrade rule fires and IBAÑEZ wins.
          expect(snap.lastName.value, 'IBAÑEZ');
          builder.dispose();
        },
      );

      test(
        'single noisy MUNXXOZ IBANXXEZ frame → MUÑOZ IBAÑEZ surfaces',
        () {
          final builder = OcrConsensusAccumulator()
            ..recordVote({'lastName': 'MUNXXOZ IBANXXEZ'});

          final snap = builder.snapshot();
          expect(snap.lastName.value, 'MUÑOZ IBAÑEZ');
          builder.dispose();
        },
      );

      test(
        'tilde-only variants (no Ñ): majority wins, no upgrade rule fires',
        () {
          // The Ñ-only recovery is intentionally scoped. For other tildes
          // (Á, É, …) the consensus simply runs majority vote — whichever
          // spelling has more frames wins. Documented here as a test of
          // intentional scope.
          final builder = OcrConsensusAccumulator()
            ..recordVote({'firstName': 'MARIA'})
            ..recordVote({'firstName': 'MARÍA'})
            ..recordVote({'firstName': 'MARIA'});

          final snap = builder.snapshot();
          // ASCII variant has 2 votes vs tilde variant's 1 → ASCII wins,
          // no tilde recovery because the upgrade rule is Ñ-only by design.
          expect(snap.firstName.value, 'MARIA');
          builder.dispose();
        },
      );

      test(
        'MRZ-Ñ recovery: text-OCR builds MUÑOZ, MRZ says MUNOZ → Ñ kept',
        () {
          final builder = OcrConsensusAccumulator();
          // 3 noisy text-OCR frames build a Ñ in the display map
          for (var i = 0; i < 3; i++) {
            builder.recordVote({'lastName': 'MUÑOZ'});
          }
          // MRZ delivers plain-ASCII MUNOZ (typical for Peruvian DNIs).
          builder
            ..lockFromMrzFields(
              documentNumber: '12345678',
              firstName: 'JUAN',
              lastName: 'MUNOZ',
              secondLastName: null,
              dateOfBirth: '01/01/1990',
              expirationDate: '31/12/2030',
            )
            ..lockFromMrzFields(
              documentNumber: '12345678',
              firstName: 'JUAN',
              lastName: 'MUNOZ',
              secondLastName: null,
              dateOfBirth: '01/01/1990',
              expirationDate: '31/12/2030',
            );

          final snap = builder.snapshot();
          expect(snap.source, OcrConsensusSource.mrzChecksum);
          expect(snap.lastName.value, 'MUÑOZ');
          builder.dispose();
        },
      );

      test(
        'KNOWN LIMITATION: MRZ paterno-only does not match full text-OCR key',
        () {
          // text-OCR voted full surname "IBAÑEZ MARIÑO" (paterno + materno).
          // MRZ delivers paterno-only "IBANEZ". The normalized vote-keys are:
          //   text-OCR: IBANEZ MARINO
          //   MRZ:      IBANEZ
          // → no match in display map; MRZ value wins as-is.
          //
          // The full surname recovery for this case must be performed at
          // the application layer (e.g. against a stored profile).
          final builder = OcrConsensusAccumulator();
          for (var i = 0; i < 3; i++) {
            builder.recordVote({'lastName': 'IBAÑEZ MARIÑO'});
          }
          builder
            ..lockFromMrzFields(
              documentNumber: '12345678',
              firstName: 'JUAN',
              lastName: 'IBANEZ',
              secondLastName: null,
              dateOfBirth: '01/01/1990',
              expirationDate: '31/12/2030',
            )
            ..lockFromMrzFields(
              documentNumber: '12345678',
              firstName: 'JUAN',
              lastName: 'IBANEZ',
              secondLastName: null,
              dateOfBirth: '01/01/1990',
              expirationDate: '31/12/2030',
            );

          final snap = builder.snapshot();
          // MRZ surfaces paterno-only; materno is lost at this layer.
          expect(snap.lastName.value, 'IBANEZ');
          builder.dispose();
        },
      );

      test(
        'compound first name JOSÉ ANDRÉS with mixed votes → majority wins',
        () {
          final builder = OcrConsensusAccumulator()
            ..recordVote({'firstName': 'JOSE ANDRES'})
            ..recordVote({'firstName': 'JOSÉ ANDRÉS'})
            ..recordVote({'firstName': 'JOSE ANDRES'});

          final snap = builder.snapshot();
          // ASCII variant has the majority (2 vs 1) — wins by vote count.
          expect(snap.firstName.value, 'JOSE ANDRES');
          builder.dispose();
        },
      );

      test(
        'double-Ñ surname AÑAÑOS RIAÑO with one noisy frame still surfaces Ñ',
        () {
          final builder = OcrConsensusAccumulator()
            ..recordVote({'lastName': 'ANXXANXXOS RIANXXO'})
            ..recordVote({'lastName': 'AÑAÑOS RIAÑO'});

          final snap = builder.snapshot();
          // Both votes share the same key (AÑAÑOS RIAÑO normalizes to
          // ANANOS RIANO). Display value should keep the Ñ-bearing form.
          expect(snap.lastName.value, 'AÑAÑOS RIAÑO');
          builder.dispose();
        },
      );
    });

    test('resetMrzConsecutiveCount resets the counter on non-MRZ frames', () {
      final builder = OcrConsensusAccumulator()
        ..lockFromMrzFields(
          documentNumber: '71542895',
          firstName: 'JOSE',
          lastName: 'LOPEZ',
          secondLastName: null,
          dateOfBirth: '01/09/1994',
          expirationDate: '26/12/2029',
        )
        // Non-MRZ frame breaks the consecutive streak
        ..resetMrzConsecutiveCount()
        // Now one more MRZ frame should NOT lock (only 1 consecutive)
        ..lockFromMrzFields(
          documentNumber: '71542895',
          firstName: 'JOSE',
          lastName: 'LOPEZ',
          secondLastName: null,
          dateOfBirth: '01/09/1994',
          expirationDate: '26/12/2029',
        );
      expect(builder.isMrzLocked, isFalse);
      builder.dispose();
    });
  });
}
