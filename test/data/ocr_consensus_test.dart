import 'dart:math' show Random;

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

  // ── BUG 3 regression tests — JC v0.6.0 feedback (obs #4673) ────────────────
  //
  // Two distinct bugs in OcrConsensusAccumulator that cause empty firstName /
  // lastName to leak through to the consumer:
  //
  // BUG 3A — `_buildMrzResultFromFields` is ASYMMETRIC:
  //   `secondLastName` falls back to the vote map when MRZ buffer is null,
  //   but `firstName` and `lastName` DO NOT. A back-side frame with partial
  //   MRZ (missing names) overrides the front-side seed votes.
  //
  // BUG 3B — `lockFromMrzFields` OVERWRITES the entire buffer:
  //   Each call replaces the buffer rather than merging field-by-field.
  //   If frame 1 has all fields and frame 2 has nulls, the buffer ends up
  //   with the nulls and the lock fires with empty data.
  //
  // Combined symptom: real Peruvian DNI back-side where MRZ checksum passes
  // but ML Kit OCR drops a character on a name line → snapshot returns
  // `firstName: null`, `lastName: null`, and InClub falls back to UserPreference
  // (violating the "OCR ALWAYS WINS" architectural decision).
  group('BUG 3 regression — front-side seed must survive partial back-side MRZ', () {
    test(
      'BUG 3A: snapshot falls back to vote map for firstName/lastName when buffer is null',
      () {
        // Simulate the front-side scan: text-OCR captured firstName/lastName
        // and the widget seeded the back-side accumulator with these votes.
        final builder = OcrConsensusAccumulator()
          ..recordVote({
            'firstName': 'JOSE CARLOS JOAO',
            'lastName': 'MORENO',
            'secondLastName': 'ALEMAN',
            'documentNumber': '71542895',
            'dateOfBirth': '01/09/1994',
            'expirationDate': '19/02/2028',
          })
          // Front seeds again to reach the vote threshold.
          ..recordVote({
            'firstName': 'JOSE CARLOS JOAO',
            'lastName': 'MORENO',
            'secondLastName': 'ALEMAN',
            'documentNumber': '71542895',
            'dateOfBirth': '01/09/1994',
            'expirationDate': '19/02/2028',
          });

        // Back-side MRZ frame parses documentNumber + dates but ML Kit
        // garbled the names line, so firstName/lastName come null.
        // This MUST NOT erase the front-side seed.
        builder.lockFromMrzFields(
          documentNumber: '71542895',
          firstName: null,
          lastName: null,
          secondLastName: null,
          dateOfBirth: '01/09/1994',
          expirationDate: '19/02/2028',
        );

        final snap = builder.snapshot();
        expect(
          snap.firstName.value,
          'JOSE CARLOS JOAO',
          reason: 'firstName must fall back to vote map when MRZ buffer is null',
        );
        expect(
          snap.lastName.value,
          'MORENO',
          reason: 'lastName must fall back to vote map when MRZ buffer is null',
        );
        expect(
          snap.documentNumber.value,
          '71542895',
          reason: 'documentNumber comes from MRZ buffer directly',
        );
        builder.dispose();
      },
    );

    test(
      'BUG 3B: lockFromMrzFields merges with previous buffer instead of overwriting',
      () {
        final builder = OcrConsensusAccumulator();

        // Frame 1 of back-side: MRZ parses fully.
        builder.lockFromMrzFields(
          documentNumber: '71542895',
          firstName: 'JOSE CARLOS JOAO',
          lastName: 'MORENO',
          secondLastName: 'ALEMAN',
          dateOfBirth: '01/09/1994',
          expirationDate: '19/02/2028',
        );

        // Frame 2 of back-side: MRZ checksum still valid (so the lock counter
        // advances) but ML Kit dropped a character on the names line so
        // firstName/lastName/secondLastName come null. documentNumber still ok.
        builder.lockFromMrzFields(
          documentNumber: '71542895',
          firstName: null,
          lastName: null,
          secondLastName: null,
          dateOfBirth: '01/09/1994',
          expirationDate: '19/02/2028',
        );

        // After both frames the accumulator should be locked AND retain
        // the names from frame 1.
        expect(builder.isMrzLocked, isTrue);
        final snap = builder.snapshot();
        expect(
          snap.firstName.value,
          'JOSE CARLOS JOAO',
          reason: 'frame 2 must NOT erase the names captured in frame 1',
        );
        expect(snap.lastName.value, 'MORENO');
        expect(snap.secondLastName.value, 'ALEMAN');
        expect(snap.documentNumber.value, '71542895');
        builder.dispose();
      },
    );

    test(
      'end-to-end: front seed + 2 back-side frames with partial MRZ → snapshot is complete',
      () {
        // This is the exact scenario from JC's logs (obs #4673):
        //   - Front-side scan accumulated text-OCR fields
        //   - Widget seeded back-side accumulator via recordVote (front fields)
        //   - Back-side MRZ frame 1 parses cleanly
        //   - Back-side MRZ frame 2 parses checksum-valid but with name garbled
        //   - Snapshot must return COMPLETE data (not null names)
        final builder = OcrConsensusAccumulator()
          // Front seed (simulates camera_overlay_mask.dart:266 recordVote).
          ..recordVote({
            'firstName': 'JOSE CARLOS JOAO',
            'lastName': 'MORENO',
            'secondLastName': 'ALEMAN',
            'documentNumber': '71542895',
            'dateOfBirth': '01/09/1994',
            'expirationDate': '19/02/2028',
          })
          ..recordVote({
            'firstName': 'JOSE CARLOS JOAO',
            'lastName': 'MORENO',
            'secondLastName': 'ALEMAN',
            'documentNumber': '71542895',
            'dateOfBirth': '01/09/1994',
            'expirationDate': '19/02/2028',
          })
          // Back frame 1: clean MRZ.
          ..lockFromMrzFields(
            documentNumber: '71542895',
            firstName: 'JOSE CARLOS JOAO',
            lastName: 'MORENO',
            secondLastName: 'ALEMAN',
            dateOfBirth: '01/09/1994',
            expirationDate: '19/02/2028',
          )
          // Back frame 2: MRZ checksum valid but name line garbled → nulls.
          ..lockFromMrzFields(
            documentNumber: '71542895',
            firstName: null,
            lastName: null,
            secondLastName: null,
            dateOfBirth: '01/09/1994',
            expirationDate: '19/02/2028',
          );

        final snap = builder.snapshot();
        expect(snap.success, isTrue);
        expect(snap.documentNumber.value, '71542895');
        expect(
          snap.firstName.value,
          'JOSE CARLOS JOAO',
          reason: 'firstName must be preserved across all stages',
        );
        expect(snap.lastName.value, 'MORENO');
        expect(snap.secondLastName.value, 'ALEMAN');
        expect(snap.dateOfBirth.value, '01/09/1994');
        expect(snap.expirationDate.value, '19/02/2028');
        builder.dispose();
      },
    );
  });

  // ── BUG 2 regression — configurable mrzConsecutiveRequired threshold ──────
  //
  // Real Peruvian electronic DNI back side: the fast-path MRZ trigger fires
  // after 2 consecutive valid frames (~66ms at 30fps). That's too tight a
  // window for the underlying still-camera pipeline to deliver a sharp photo:
  // takePicture() latency + handheld motion = blurry capture.
  //
  // Fix: expose `mrzConsecutiveRequired` so the host widget can raise the
  // threshold for back-side scans (recommended: 5 frames ≈ 165ms).
  group('BUG 2 regression — configurable MRZ lock threshold', () {
    test('default threshold is 2 (backwards compatible)', () {
      final builder = OcrConsensusAccumulator();
      expect(builder.mrzConsecutiveRequired, 2);
      builder.dispose();
    });

    test('default still locks after 2 consecutive lockFromMrzFields calls', () {
      final builder = OcrConsensusAccumulator()
        ..lockFromMrzFields(
          documentNumber: '71542895',
          firstName: 'JOSE',
          lastName: 'MORENO',
          secondLastName: 'ALEMAN',
          dateOfBirth: '01/09/1994',
          expirationDate: '19/02/2028',
        );
      expect(builder.isMrzLocked, isFalse);
      builder.lockFromMrzFields(
        documentNumber: '71542895',
        firstName: 'JOSE',
        lastName: 'MORENO',
        secondLastName: 'ALEMAN',
        dateOfBirth: '01/09/1994',
        expirationDate: '19/02/2028',
      );
      expect(builder.isMrzLocked, isTrue);
      builder.dispose();
    });

    test('raised threshold of 5 requires 5 frames to lock', () {
      final builder = OcrConsensusAccumulator(mrzConsecutiveRequired: 5);
      expect(builder.mrzConsecutiveRequired, 5);

      for (int i = 1; i <= 4; i++) {
        builder.lockFromMrzFields(
          documentNumber: '71542895',
          firstName: 'JOSE',
          lastName: 'MORENO',
          secondLastName: 'ALEMAN',
          dateOfBirth: '01/09/1994',
          expirationDate: '19/02/2028',
        );
        expect(builder.isMrzLocked, isFalse,
            reason: 'must not lock at frame $i (< 5)');
      }

      // 5th frame triggers the lock.
      builder.lockFromMrzFields(
        documentNumber: '71542895',
        firstName: 'JOSE',
        lastName: 'MORENO',
        secondLastName: 'ALEMAN',
        dateOfBirth: '01/09/1994',
        expirationDate: '19/02/2028',
      );
      expect(builder.isMrzLocked, isTrue);
      builder.dispose();
    });

    test('raised threshold also applies to recordMrz path', () {
      final mrz = MRZResult(
        documentType: 'TD1',
        countryCode: 'PER',
        surnames: 'MORENO',
        givenNames: 'JOSE',
        documentNumber: '71542895',
        nationalityCountryCode: 'PER',
        birthDate: DateTime(1994, 9, 1),
        sex: Sex.male,
        expiryDate: DateTime(2028, 2, 19),
        personalNumber: '',
      );

      final builder = OcrConsensusAccumulator(mrzConsecutiveRequired: 3);

      builder.recordMrz(mrz);
      expect(builder.isMrzLocked, isFalse);

      builder.recordMrz(mrz);
      expect(builder.isMrzLocked, isFalse, reason: 'must not lock at frame 2 (<3)');

      builder.recordMrz(mrz);
      expect(builder.isMrzLocked, isTrue);
      builder.dispose();
    });

    test('threshold of 1 locks on the first frame (edge case)', () {
      final builder = OcrConsensusAccumulator(mrzConsecutiveRequired: 1);
      builder.lockFromMrzFields(
        documentNumber: '71542895',
        firstName: 'JOSE',
        lastName: 'MORENO',
        secondLastName: 'ALEMAN',
        dateOfBirth: '01/09/1994',
        expirationDate: '19/02/2028',
      );
      expect(builder.isMrzLocked, isTrue);
      builder.dispose();
    });

    test('threshold of 0 is rejected by assertion', () {
      expect(
        () => OcrConsensusAccumulator(mrzConsecutiveRequired: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // ── BUG regression — RENIEC Ñ→NXX MRZ encoding recovery (JC JAMES case)
  //
  // The Peruvian MRZ (ICAO 9303 TD1) cannot encode `Ñ`. RENIEC's chosen
  // workaround is to substitute `Ñ` with `NXX`, so the surname "ERMITAÑO"
  // becomes "ERMITANXX0" on the MRZ line (the trailing `O` is often read
  // as `0` by ML Kit, compounding the corruption).
  //
  // When the front-side text-OCR voted the correct `ERMITAÑO` (with real Ñ)
  // and the back-side MRZ provides `ERMITANXX0`, the snapshot must prefer
  // the text-OCR variant — otherwise the UI shows garbage.
  group('BUG regression — Ñ recovery from text-OCR when MRZ uses NXX', () {
    test(
      'firstName: MRZ ERMITANXX0 + text vote ERMITAÑO → snapshot shows ERMITAÑO',
      () {
        final builder = OcrConsensusAccumulator()
          // Front-side text-OCR voted the real Ñ variant several times.
          ..recordVote({'firstName': 'JAMES ERMITAÑO'})
          ..recordVote({'firstName': 'JAMES ERMITAÑO'})
          // Back-side MRZ frame produces the NXX-encoded form.
          ..lockFromMrzFields(
            documentNumber: '43005787',
            firstName: 'JAMES ERMITANXX0',
            lastName: 'QUIROZ',
            secondLastName: null,
            dateOfBirth: '24/06/1985',
            expirationDate: '25/03/2036',
          )
          ..lockFromMrzFields(
            documentNumber: '43005787',
            firstName: 'JAMES ERMITANXX0',
            lastName: 'QUIROZ',
            secondLastName: null,
            dateOfBirth: '24/06/1985',
            expirationDate: '25/03/2036',
          );

        final snap = builder.snapshot();
        expect(snap.success, isTrue);
        expect(snap.firstName.value, 'JAMES ERMITAÑO',
            reason: 'Ñ recovery from text-OCR vote when MRZ uses NXX encoding');
        builder.dispose();
      },
    );

    test(
      'lastName: MRZ NUNXXEZ + text vote NÚÑEZ → snapshot shows NÚÑEZ',
      () {
        // Hypothetical: paternal surname with both Ú and Ñ → MRZ has NXX
        // for the Ñ and strips the Ú accent.
        final builder = OcrConsensusAccumulator()
          ..recordVote({'lastName': 'NÚÑEZ'})
          ..recordVote({'lastName': 'NÚÑEZ'})
          ..lockFromMrzFields(
            documentNumber: '12345678',
            firstName: 'JUAN',
            lastName: 'NUNXXEZ',
            secondLastName: null,
            dateOfBirth: '01/01/1990',
            expirationDate: '31/12/2030',
          )
          ..lockFromMrzFields(
            documentNumber: '12345678',
            firstName: 'JUAN',
            lastName: 'NUNXXEZ',
            secondLastName: null,
            dateOfBirth: '01/01/1990',
            expirationDate: '31/12/2030',
          );

        final snap = builder.snapshot();
        expect(snap.lastName.value, 'NÚÑEZ');
        builder.dispose();
      },
    );

    test(
      'no text-OCR vote → MRZ value passes through unchanged (no fabrication)',
      () {
        // Defensive: if text-OCR did not vote a variant of the surname,
        // we must NOT invent an Ñ — return the MRZ value verbatim. The user
        // can fix it in the confirmation step.
        final builder = OcrConsensusAccumulator()
          ..lockFromMrzFields(
            documentNumber: '43005787',
            firstName: 'JAMES ERMITANXX0',
            lastName: 'QUIROZ',
            secondLastName: null,
            dateOfBirth: '24/06/1985',
            expirationDate: '25/03/2036',
          )
          ..lockFromMrzFields(
            documentNumber: '43005787',
            firstName: 'JAMES ERMITANXX0',
            lastName: 'QUIROZ',
            secondLastName: null,
            dateOfBirth: '24/06/1985',
            expirationDate: '25/03/2036',
          );

        final snap = builder.snapshot();
        expect(snap.firstName.value, 'JAMES ERMITANXX0',
            reason: 'no text-OCR vote means no recovery — return MRZ as-is');
        builder.dispose();
      },
    );
  });

  // ── BUG G regression — address vote consolidation across OCR variants ───
  //
  // ML Kit emits the same DNI address in many micro-variants across frames
  // because each frame has slightly different OCR noise. Without
  // consolidation, every variant lands in its own single-vote bucket and
  // the `reduce(max)` winner is non-deterministic — often the corrupted
  // variant ends up displayed on screen.
  //
  // Real JC case against v0.6.7: log shows MILAGRO across frames, UI shows
  // MLAGRO (missing I). Root cause: ambiguous bucket tie-break.
  group('BUG G regression — address vote consolidation', () {
    test(
      'progressive completion: shorter variants merge into the longest',
      () {
        // Frames captured the address growing across captures. Earlier
        // frames have the prefix, later frames have the full address.
        final builder = OcrConsensusAccumulator()
          ..recordVote({'address': 'ASENT H15 DE ABRIL CALLE EL MILAGRO'})
          ..recordVote({'address': 'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ'})
          ..recordVote({'address': 'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ.B'})
          ..recordVote({
            'address': 'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ.B LT.19',
          });

        final snap = builder.snapshot();
        expect(
          snap.address.value,
          'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ.B LT.19',
          reason: 'longest variant in the prefix chain must win',
        );
        builder.dispose();
      },
    );

    test(
      'OCR glitch in one frame is outvoted by the well-read majority',
      () {
        // 3 frames read MILAGRO correctly, 1 frame mangled to MLAGRO.
        // The mangled frame must NOT win even though all 4 variants
        // would otherwise have 1 vote each.
        final builder = OcrConsensusAccumulator()
          ..recordVote({
            'address': 'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ.B LT.19',
          })
          ..recordVote({
            'address': 'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ.B LT.19',
          })
          ..recordVote({
            'address': 'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ.B LT.19',
          })
          ..recordVote({
            'address': 'ASENT H15 DE ABRIL CALLE EL MLAGRO MZ.B LT.19',
          });

        final snap = builder.snapshot();
        expect(
          snap.address.value,
          contains('MILAGRO'),
          reason: 'majority MILAGRO wins; single MLAGRO frame is consolidated',
        );
        expect(snap.address.value, isNot(contains('MLAGRO')));
        builder.dispose();
      },
    );

    test(
      'all variants 1-vote, longest wins (deterministic tie-break)',
      () {
        // Worst case: every frame got a different micro-variant. The
        // previous behaviour returned whichever variant Map.reduce
        // happened to encounter last (non-deterministic). The new logic
        // groups them all together and the LONGEST variant wins.
        final builder = OcrConsensusAccumulator()
          ..recordVote({'address': 'ASENT H15 DE ABRIL CALLE EL MILAGRO'})
          ..recordVote({'address': 'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ'})
          ..recordVote({'address': 'ASENT HI5 DE ABRIL CALLE EL MILAGRO MZ'})
          ..recordVote({
            'address': 'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ.B LT.19',
          })
          ..recordVote({
            'address': 'ASENT H15 DE ABRIL CALLE EL MLAGRO MZ.B LT.19',
          });

        final snap = builder.snapshot();
        // The longest variant (which is the well-read one in this case)
        // must win.
        expect(
          snap.address.value,
          'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ.B LT.19',
        );
        builder.dispose();
      },
    );

    test(
      'unrelated addresses do NOT consolidate',
      () {
        // Defensive: if two completely different addresses are voted (very
        // unlikely in practice but possible if the user moves the document
        // mid-scan), they should remain separate groups and the majority
        // wins. We do NOT want to merge unrelated content.
        final builder = OcrConsensusAccumulator()
          ..recordVote({'address': 'AV LOS PINOS 123 MAGDALENA'})
          ..recordVote({'address': 'AV LOS PINOS 123 MAGDALENA'})
          ..recordVote({'address': 'JR HUANUCO 456 LIMA'});

        final snap = builder.snapshot();
        expect(snap.address.value, contains('LOS PINOS'));
        expect(snap.address.value, isNot(contains('HUANUCO')));
        builder.dispose();
      },
    );
  });

  // ── Name field consolidation (v0.7.0): strict prefix containment ──────
  //
  // Names are short and Levenshtein-based merging risks collapsing
  // legitimately different names (`JUAN` ≈ `JOSE`). Consolidation here
  // is restricted to **whole-word prefix containment**: `MORENO` merges
  // into `MORENO ALEMAN` because the first is the literal beginning of
  // the second, but `JUAN` and `JOSE` stay independent.
  group('Name field consolidation — strict prefix only', () {
    test(
      'paternal-only vote merges into paternal+maternal vote',
      () {
        final builder = OcrConsensusAccumulator()
          ..recordVote({'lastName': 'MORENO'})
          ..recordVote({'lastName': 'MORENO ALEMAN'});

        final snap = builder.snapshot();
        // The longer variant wins and the two votes consolidate into 2/2.
        expect(snap.lastName.value, 'MORENO ALEMAN');
        expect(snap.lastName.confidence, equals(1.0));
        builder.dispose();
      },
    );

    test(
      'unrelated first names stay independent (no false merge)',
      () {
        final builder = OcrConsensusAccumulator()
          ..recordVote({'firstName': 'JUAN'})
          ..recordVote({'firstName': 'JUAN'})
          ..recordVote({'firstName': 'JOSE'});

        final snap = builder.snapshot();
        // 2 votes for JUAN, 1 for JOSE → JUAN wins on majority, no merge.
        expect(snap.firstName.value, 'JUAN');
        builder.dispose();
      },
    );

    test(
      'document number prefix consolidation does NOT fire on equal length',
      () {
        // Same-length variants must not merge — strict prefix containment
        // requires anchor.length > shorter.length.
        final builder = OcrConsensusAccumulator()
          ..recordVote({'documentNumber': '12345678'})
          ..recordVote({'documentNumber': '12345679'});

        final snap = builder.snapshot();
        // Both have 1 vote; reduce(max) returns one of them. The point of
        // this test is that they DID NOT merge into a single bucket.
        expect(snap.documentNumber.value, anyOf('12345678', '12345679'));
        expect(snap.documentNumber.confidence, equals(0.5));
        builder.dispose();
      },
    );
  });

  // ── Property: vote order does not affect winner ──────────────────────
  //
  // The snapshot must be deterministic with respect to the order in which
  // votes were recorded. ML Kit emits frames in unpredictable order, so a
  // consumer must receive the same final value regardless of which frame
  // happened to be processed first. This guards against any future
  // regression that would re-introduce HashMap iteration-order dependency.
  group('Property — snapshot order independence', () {
    test('address: shuffle 5 micro-variants 30 times, same winner each run', () {
      final votes = [
        'ASENT H15 DE ABRIL CALLE EL MILAGRO',
        'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ',
        'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ.B',
        'ASENT H15 DE ABRIL CALLE EL MILAGRO MZ.B LT.19',
        'ASENT H15 DE ABRIL CALLE EL MLAGRO MZ.B LT.19',
      ];

      String? firstWinner;
      for (var seed = 0; seed < 30; seed++) {
        final shuffled = List.of(votes)..shuffle(Random(seed));
        final acc = OcrConsensusAccumulator();
        for (final v in shuffled) {
          acc.recordVote({'address': v});
        }
        final winner = acc.snapshot().address.value;
        acc.dispose();
        firstWinner ??= winner;
        expect(
          winner,
          equals(firstWinner),
          reason: 'seed $seed produced a different winner — non-determinism',
        );
      }
    });

    test('lastName: shuffle prefix variants, same winner each run', () {
      final votes = [
        'MORENO',
        'MORENO ALEMAN',
        'MORENO ALEMAN',
        'MORENO',
      ];

      String? firstWinner;
      for (var seed = 0; seed < 30; seed++) {
        final shuffled = List.of(votes)..shuffle(Random(seed));
        final acc = OcrConsensusAccumulator();
        for (final v in shuffled) {
          acc.recordVote({'lastName': v});
        }
        final winner = acc.snapshot().lastName.value;
        acc.dispose();
        firstWinner ??= winner;
        expect(winner, equals(firstWinner));
      }
    });
  });
}
