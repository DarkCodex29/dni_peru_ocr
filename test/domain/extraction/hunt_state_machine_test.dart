import 'package:dni_peru_ocr/dni_peru_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HuntStateMachine', () {
    const noOpAnchor = DocumentSide.unknown;
    const frontAnchor = DocumentSide.front;
    const backAnchor = DocumentSide.back;

    group('minFieldsForFastAdvance override', () {
      test('override=null uses default value of 12', () {
        final machine = HuntStateMachine();
        expect(machine.minFieldsForFastAdvance, 12);
      });

      test('override=3 uses 3 (scaled for n=4 minimal)', () {
        final machine = HuntStateMachine(minFieldsForFastAdvance: 3);
        expect(machine.minFieldsForFastAdvance, 3);
      });

      test('override=5 uses 5 (scaled for n=7 kyc)', () {
        final machine = HuntStateMachine(minFieldsForFastAdvance: 5);
        expect(machine.minFieldsForFastAdvance, 5);
      });

      test('override=14 uses 14 (same as full/default)', () {
        final machine = HuntStateMachine(minFieldsForFastAdvance: 14);
        expect(machine.minFieldsForFastAdvance, 14);
      });

      test('fast-advance triggers earlier when override is lower', () {
        final machine = HuntStateMachine(
          idleFramesThreshold: 10,
          fastAdvanceThreshold: 2,
          minFieldsForFastAdvance: 3,
        );
        machine.recordFrame(detectedSide: frontAnchor, addedNewField: false);
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 4,
        );
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 4,
        );
        final signal = machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 4,
        );
        expect(signal, HuntSignal.frontCaptureReady);
      });
    });

    test('starts in waitingFront phase', () {
      final machine = HuntStateMachine();
      expect(machine.phase, HuntPhase.waitingFront);
    });

    test('stays in waitingFront when no front anchor seen', () {
      final machine = HuntStateMachine();
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: true);
      expect(machine.phase, HuntPhase.waitingFront);
    });

    test('advances to extractingFront when front anchor detected', () {
      final machine = HuntStateMachine();
      machine.recordFrame(detectedSide: frontAnchor, addedNewField: false);
      expect(machine.phase, HuntPhase.extractingFront);
    });

    test('stays in extractingFront while frames keep revealing NEW distinct '
        'fields (filled count rises every frame)', () {
      final machine = HuntStateMachine(idleFramesThreshold: 5);
      machine.recordFrame(
        detectedSide: frontAnchor,
        addedNewField: false,
        filledFields: 0,
      );
      // Each frame reveals a brand-new distinct field, so idle keeps resetting
      // and capture never fires while the document is still revealing data.
      var signal = HuntSignal.none;
      for (var i = 1; i <= 10; i++) {
        signal = machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: true,
          filledFields: i,
        );
      }
      expect(machine.phase, HuntPhase.extractingFront);
      expect(signal, HuntSignal.none);
    });

    test('signals frontCaptureReady after N idle frames', () {
      // filledFields stays above the stable-capture floor (4) so the test
      // exercises the idle-threshold mechanism, not the floor guard.
      final machine = HuntStateMachine(idleFramesThreshold: 3);
      machine.recordFrame(
        detectedSide: frontAnchor,
        addedNewField: false,
        filledFields: 5,
      );
      machine.recordFrame(
        detectedSide: noOpAnchor,
        addedNewField: true,
        filledFields: 5,
      );
      machine.recordFrame(
        detectedSide: noOpAnchor,
        addedNewField: false,
        filledFields: 5,
      );
      machine.recordFrame(
        detectedSide: noOpAnchor,
        addedNewField: false,
        filledFields: 5,
      );
      final signal = machine.recordFrame(
        detectedSide: noOpAnchor,
        addedNewField: false,
        filledFields: 5,
      );
      expect(signal, HuntSignal.frontCaptureReady);
    });

    test('resets idle counter when a frame reveals a NEW distinct field '
        '(filled count increases)', () {
      final machine = HuntStateMachine(idleFramesThreshold: 3);
      machine.recordFrame(
        detectedSide: frontAnchor,
        addedNewField: false,
        filledFields: 5,
      );
      machine.recordFrame(
        detectedSide: noOpAnchor,
        addedNewField: false,
        filledFields: 5,
      );
      machine.recordFrame(
        detectedSide: noOpAnchor,
        addedNewField: false,
        filledFields: 5,
      );
      // A genuinely new field (5 -> 6) resets the idle counter.
      machine.recordFrame(
        detectedSide: noOpAnchor,
        addedNewField: true,
        filledFields: 6,
      );
      final signal = machine.recordFrame(
        detectedSide: noOpAnchor,
        addedNewField: false,
        filledFields: 6,
      );
      expect(machine.phase, HuntPhase.extractingFront);
      expect(signal, HuntSignal.none);
    });

    test('advanceToWaitingBack moves out of extractingFront', () {
      final machine = HuntStateMachine(idleFramesThreshold: 1);
      machine.recordFrame(detectedSide: frontAnchor, addedNewField: false);
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      machine.advanceToWaitingBack();
      expect(machine.phase, HuntPhase.waitingBack);
    });

    test('stays in waitingBack until back anchor detected', () {
      final machine = HuntStateMachine();
      _seedFrontPhaseComplete(machine);
      machine.advanceToWaitingBack();
      machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
      machine.recordFrame(detectedSide: frontAnchor, addedNewField: false);
      expect(machine.phase, HuntPhase.waitingBack);
    });

    test('advances to extractingBack when back anchor detected', () {
      final machine = HuntStateMachine();
      _seedFrontPhaseComplete(machine);
      machine.advanceToWaitingBack();
      machine.recordFrame(detectedSide: backAnchor, addedNewField: false);
      expect(machine.phase, HuntPhase.extractingBack);
    });

    test('signals backCaptureReady after N idle frames in extractingBack', () {
      // filledFields stays above the stable-capture floor (4) so the test
      // exercises the idle-threshold mechanism, not the floor guard.
      final machine = HuntStateMachine(idleFramesThreshold: 2);
      _seedFrontPhaseComplete(machine);
      machine.advanceToWaitingBack();
      machine.recordFrame(
        detectedSide: backAnchor,
        addedNewField: false,
        filledFields: 5,
      );
      machine.recordFrame(
        detectedSide: noOpAnchor,
        addedNewField: true,
        filledFields: 5,
      );
      machine.recordFrame(
        detectedSide: noOpAnchor,
        addedNewField: false,
        filledFields: 5,
      );
      final signal = machine.recordFrame(
        detectedSide: noOpAnchor,
        addedNewField: false,
        filledFields: 5,
      );
      expect(signal, HuntSignal.backCaptureReady);
    });

    group('waiting-phase stuck escape (#5457 latch fix)', () {
      test('escapes a stuck waitingBack via idle with a recovery signal, '
          'NOT a blind back-capture', () {
        final machine = HuntStateMachine(idleFramesThreshold: 3);
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        // Side detector never confirms the back anchor (unknown forever).
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        final signal =
            machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        expect(signal, HuntSignal.recoverManual);
      });

      test('SAFETY: escaping waitingBack with an unconfirmed side does NOT '
          'emit backCaptureReady', () {
        final machine = HuntStateMachine(idleFramesThreshold: 3);
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        final signals = <HuntSignal>[
          for (var i = 0; i < 6; i++)
            machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false),
        ];
        expect(signals, isNot(contains(HuntSignal.backCaptureReady)));
      });

      test('escapes a stuck waitingFront via idle with a recovery signal', () {
        final machine = HuntStateMachine(idleFramesThreshold: 3);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        final signal =
            machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        expect(signal, HuntSignal.recoverManual);
      });

      test('REGRESSION: confirmed back anchor still advances to extractingBack '
          'and reaches backCaptureReady (happy path intact)', () {
        final machine = HuntStateMachine(idleFramesThreshold: 2);
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        machine.recordFrame(
          detectedSide: backAnchor,
          addedNewField: false,
          filledFields: 5,
        );
        expect(machine.phase, HuntPhase.extractingBack);
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: true,
          filledFields: 5,
        );
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 5,
        );
        final signal = machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 5,
        );
        expect(signal, HuntSignal.backCaptureReady);
      });

      test('REGRESSION: in waitingFront an added field resets the idle counter '
          'so a productive wait is not cut short', () {
        // waitingFront still benefits from idle reset on new fields: a fresh
        // field means OCR is making progress toward the front anchor.
        final machine = HuntStateMachine(idleFramesThreshold: 3);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: true);
        final signal =
            machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        expect(signal, HuntSignal.none);
      });
    });

    group('waitingBack stale-reread escape (#5461 reverso latch)', () {
      test('stale FRONT re-reads (unknown side + addedNewField) do NOT reset '
          'idle, so the manual escape still fires', () {
        // Device repro: in waitingBack the FieldHunter keeps re-reading STALE
        // front fields, flipping addedNewField=true intermittently. The old
        // policy reset idle on every such re-read, so idle never reached the
        // threshold and recoverManual never fired. A genuine BACK field would
        // have advanced the phase to extractingBack before reaching here, so
        // any addedNewField in waitingBack is by definition a non-back read.
        final machine = HuntStateMachine(idleFramesThreshold: 4);
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        // Interleave stale re-reads (addedNewField=true) with idle frames.
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: true);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        machine.recordFrame(detectedSide: noOpAnchor, addedNewField: true);
        final signal =
            machine.recordFrame(detectedSide: noOpAnchor, addedNewField: false);
        expect(signal, HuntSignal.recoverManual);
      });

      test('SAFETY: the stale-reread escape emits recoverManual and NEVER '
          'backCaptureReady (no wrong-side auto-capture)', () {
        final machine = HuntStateMachine(idleFramesThreshold: 3);
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        final signals = <HuntSignal>[
          for (var i = 0; i < 8; i++)
            machine.recordFrame(
              detectedSide: noOpAnchor,
              addedNewField: i.isEven,
            ),
        ];
        expect(signals, contains(HuntSignal.recoverManual));
        expect(signals, isNot(contains(HuntSignal.backCaptureReady)));
      });

      test('HAPPY PATH: a confirmed back anchor still advances to '
          'extractingBack and reaches backCaptureReady', () {
        final machine = HuntStateMachine(idleFramesThreshold: 2);
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        machine.recordFrame(
          detectedSide: backAnchor,
          addedNewField: false,
          filledFields: 5,
        );
        expect(machine.phase, HuntPhase.extractingBack);
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: true,
          filledFields: 5,
        );
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 5,
        );
        final signal = machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 5,
        );
        expect(signal, HuntSignal.backCaptureReady);
      });
    });

    group('extractingFront re-vote dwell (#5461 front 92% stall)', () {
      test('re-votes of already-filled fields (addedNewField=true but the '
          'distinct filled count is flat) do NOT reset idle, so the front '
          'dwell still reaches frontCaptureReady', () {
        // Device repro (S22): the text-dense FRONT plateaus at 11/19 filled,
        // yet the FieldHunter keeps reading NEW normalized variants of fields
        // it ALREADY filled, flipping addedNewField=true intermittently. The
        // old policy reset idle on every such re-vote, so the 3-2-1 dwell
        // stalled near ~92% and only the timeout fired. A re-vote that does
        // not raise the distinct filled count is NOT new data — it must not
        // reset the dwell.
        final machine = HuntStateMachine(idleFramesThreshold: 4);
        machine.recordFrame(
          detectedSide: frontAnchor,
          addedNewField: false,
          filledFields: 11,
        );
        // filled stays clamped at 11/19; addedNewField flips true on re-votes.
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: true,
          filledFields: 11,
        );
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 11,
        );
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: true,
          filledFields: 11,
        );
        final signal = machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 11,
        );
        expect(signal, HuntSignal.frontCaptureReady);
      });

      test('REGRESSION: a genuinely new distinct field (filled count '
          'increases) DOES reset the idle dwell so a still-revealing '
          'document is not cut short', () {
        // The legitimate case: while the document keeps revealing NEW fields
        // the distinct filled count rises, which still means productive
        // progress and must reset idle.
        final machine = HuntStateMachine(idleFramesThreshold: 3);
        machine.recordFrame(
          detectedSide: frontAnchor,
          addedNewField: false,
          filledFields: 8,
        );
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 8,
        );
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 8,
        );
        // A genuinely new field appears (8 -> 9): idle must reset here.
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: true,
          filledFields: 9,
        );
        final signal = machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 9,
        );
        expect(signal, HuntSignal.none);
      });

      test('extractingBack re-votes of already-filled fields also stop '
          'resetting the dwell so backCaptureReady is reached', () {
        // filledFields stays below minFieldsForFastAdvance (12) so the slow
        // idleFramesThreshold (4) applies and the dwell is deterministic.
        final machine = HuntStateMachine(idleFramesThreshold: 4);
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        machine.recordFrame(
          detectedSide: backAnchor,
          addedNewField: false,
          filledFields: 6,
        );
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: true,
          filledFields: 6,
        );
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 6,
        );
        machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: true,
          filledFields: 6,
        );
        final signal = machine.recordFrame(
          detectedSide: noOpAnchor,
          addedNewField: false,
          filledFields: 6,
        );
        expect(signal, HuntSignal.backCaptureReady);
      });
    });

    group('capture on data stability, not all-fields completeness (#5471)', () {
      test('FRONT plateaus at 11/19 with no new fields and never reaches the '
          'complete count, yet stability still fires frontCaptureReady', () {
        // Device truth (S22): a real DNI fills 11/19 because one printed field
        // (e.g. "Fecha de inscripción") does not exist on that document, so
        // the complete count is physically unreachable. Capture must fire on
        // STABILITY (no new distinct field for N frames) regardless.
        final machine = HuntStateMachine(
          idleFramesThreshold: 6,
          fastAdvanceThreshold: 3,
          // Mirror the live widget wiring: fast-advance kicks in at the small
          // stability floor, so a plateau above it uses the fast path.
          minFieldsForFastAdvance: 4,
          // The full selection completes at 19, which this DNI can never reach.
          frontCompleteFieldsCount: 19,
        );
        machine.recordFrame(
          detectedSide: frontAnchor,
          addedNewField: false,
          filledFields: 11,
        );
        // Filled stays clamped at 11/19; no new distinct field arrives.
        var signal = HuntSignal.none;
        for (var i = 0; i < 4; i++) {
          signal = machine.recordFrame(
            detectedSide: noOpAnchor,
            addedNewField: false,
            filledFields: 11,
          );
        }
        expect(signal, HuntSignal.frontCaptureReady);
      });

      test('FRONT plateaus at 18/19 (one physically-absent field) and still '
          'reaches frontCaptureReady via stability', () {
        final machine = HuntStateMachine(
          idleFramesThreshold: 6,
          fastAdvanceThreshold: 3,
          minFieldsForFastAdvance: 4,
          frontCompleteFieldsCount: 19,
        );
        machine.recordFrame(
          detectedSide: frontAnchor,
          addedNewField: false,
          filledFields: 18,
        );
        var signal = HuntSignal.none;
        for (var i = 0; i < 4; i++) {
          signal = machine.recordFrame(
            detectedSide: noOpAnchor,
            addedNewField: false,
            filledFields: 18,
          );
        }
        expect(signal, HuntSignal.frontCaptureReady);
      });

      test('BACK plateaus below the complete count and still reaches '
          'backCaptureReady via stability', () {
        final machine = HuntStateMachine(
          idleFramesThreshold: 6,
          fastAdvanceThreshold: 3,
          minFieldsForFastAdvance: 4,
          backCompleteFieldsCount: 19,
        );
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        machine.recordFrame(
          detectedSide: backAnchor,
          addedNewField: false,
          filledFields: 13,
        );
        var signal = HuntSignal.none;
        for (var i = 0; i < 4; i++) {
          signal = machine.recordFrame(
            detectedSide: noOpAnchor,
            addedNewField: false,
            filledFields: 13,
          );
        }
        expect(signal, HuntSignal.backCaptureReady);
      });

      test('FLOOR GUARD: below the minimum-fields floor stability does NOT '
          'auto-capture (no premature garbage capture)', () {
        // With almost no real data (filled below the floor) a long plateau is
        // garbage, not a stabilized document. Capture must NOT fire.
        final machine = HuntStateMachine(
          idleFramesThreshold: 4,
          fastAdvanceThreshold: 2,
          minFieldsForStableCapture: 4,
          frontCompleteFieldsCount: 19,
        );
        machine.recordFrame(
          detectedSide: frontAnchor,
          addedNewField: false,
          filledFields: 2,
        );
        var signal = HuntSignal.none;
        for (var i = 0; i < 10; i++) {
          signal = machine.recordFrame(
            detectedSide: noOpAnchor,
            addedNewField: false,
            filledFields: 2,
          );
        }
        expect(signal, HuntSignal.none);
        expect(machine.phase, HuntPhase.extractingFront);
      });

      test('FLOOR GUARD: once filled reaches the floor, a stable plateau '
          'fires frontCaptureReady', () {
        final machine = HuntStateMachine(
          idleFramesThreshold: 4,
          fastAdvanceThreshold: 2,
          minFieldsForStableCapture: 4,
          frontCompleteFieldsCount: 19,
        );
        machine.recordFrame(
          detectedSide: frontAnchor,
          addedNewField: false,
          filledFields: 4,
        );
        var signal = HuntSignal.none;
        for (var i = 0; i < 4; i++) {
          signal = machine.recordFrame(
            detectedSide: noOpAnchor,
            addedNewField: false,
            filledFields: 4,
          );
        }
        expect(signal, HuntSignal.frontCaptureReady);
      });

      test('default minFieldsForStableCapture is 4 (DniFields.minimal size)',
          () {
        final machine = HuntStateMachine();
        expect(machine.minFieldsForStableCapture, 4);
      });
    });

    group('back auto-capture on stability when flipped (#5482)', () {
      test('flipped back (side != front) with a stable data plateau above the '
          'floor auto-captures via backCaptureReady, NOT recoverManual', () {
        // Device truth (S22): the Peru DNI back carries almost no OCR-able
        // text, so the side detector never confirms the back anchor and
        // detectedSide stays `unknown`. The user HAS flipped (the front
        // anchors left the frame, so detectedSide is no longer `front`) and
        // the carried-over front fields plateau (e.g. 11/19) stays stable.
        // This genuine flip must AUTO-CAPTURE, not fall to the manual escape.
        final machine = HuntStateMachine(
          idleFramesThreshold: 6,
          fastAdvanceThreshold: 3,
          minFieldsForFastAdvance: 4,
          minFieldsForStableCapture: 4,
          backCompleteFieldsCount: 19,
        );
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        // Flipped to the back: detectedSide is `unknown` (sparse back, the
        // front anchors are gone) and the front's fields are carried over and
        // stable at 11.
        var signal = HuntSignal.none;
        for (var i = 0; i < 5; i++) {
          signal = machine.recordFrame(
            detectedSide: DocumentSide.unknown,
            addedNewField: false,
            filledFields: 11,
          );
        }
        expect(signal, HuntSignal.backCaptureReady);
      });

      test('SAFETY: NOT flipped (side == front, user still showing the front) '
          'does NOT emit backCaptureReady even with a stable plateau', () {
        // The wrong-side risk: the user has not flipped, so the front anchors
        // keep matching and detectedSide stays `front`. Auto-capturing here
        // would photograph the front again. The machine must NOT emit
        // backCaptureReady; it falls back to the manual/idle path as before.
        final machine = HuntStateMachine(
          idleFramesThreshold: 6,
          fastAdvanceThreshold: 3,
          minFieldsForFastAdvance: 4,
          minFieldsForStableCapture: 4,
          backCompleteFieldsCount: 19,
        );
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        // Still showing the FRONT: detectedSide == front, fields stable at 11.
        final signals = <HuntSignal>[
          for (var i = 0; i < 8; i++)
            machine.recordFrame(
              detectedSide: DocumentSide.front,
              addedNewField: false,
              filledFields: 11,
            ),
        ];
        // Never auto-captures the wrong side, and still falls back to the
        // manual escape so the user is never stranded.
        expect(signals, isNot(contains(HuntSignal.backCaptureReady)));
        expect(signals, contains(HuntSignal.recoverManual));
      });

      test('SAFETY: flipped but data still below the floor (near-empty frames) '
          'does NOT auto-capture and still escapes to recoverManual', () {
        // A genuinely flipped but data-starved view (filled below the floor)
        // must not auto-capture garbage; the existing idle escape to manual
        // still fires. This is the case the older escape tests exercise
        // (filled defaults to 0).
        final machine = HuntStateMachine(idleFramesThreshold: 3);
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        machine.recordFrame(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 2,
        );
        machine.recordFrame(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 2,
        );
        final signal = machine.recordFrame(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 2,
        );
        expect(signal, HuntSignal.recoverManual);
      });
    });

    group('back latches once like front (#5494 unified trigger)', () {
      test('ONE genuine flipped frame latches into extractingBack; later '
          'ambiguous (front) frames do NOT drop it back to recoverManual and '
          'stability still fires backCaptureReady', () {
        // Device truth: a single genuine flipped frame (front anchors gone,
        // data above the floor) should COMMIT the back to the stability path,
        // exactly like the front latches into extractingFront on the first
        // front-detected frame. Subsequent ambiguous frames that momentarily
        // read `front` (stale re-reads) must NOT pull the machine back to the
        // waiting/idle escape. The old per-frame re-check fell to
        // recoverManual on the first ambiguous frame after the flip.
        final machine = HuntStateMachine(
          idleFramesThreshold: 6,
          fastAdvanceThreshold: 3,
          minFieldsForFastAdvance: 4,
          minFieldsForStableCapture: 4,
          backCompleteFieldsCount: 19,
        );
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        // ONE genuine flipped frame above the floor.
        machine.recordFrame(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 11,
        );
        expect(
          machine.phase,
          HuntPhase.extractingBack,
          reason: 'a single genuine flipped frame must latch into '
              'extractingBack like the front does',
        );
        // Now ambiguous frames arrive: some momentarily read `front` (stale
        // re-reads of carried-over front fields). These must NOT drop the
        // latch back to a waiting phase or emit recoverManual.
        final signals = <HuntSignal>[];
        for (var i = 0; i < 6; i++) {
          signals.add(
            machine.recordFrame(
              detectedSide:
                  i.isEven ? DocumentSide.front : DocumentSide.unknown,
              addedNewField: false,
              filledFields: 11,
            ),
          );
        }
        expect(
          signals,
          isNot(contains(HuntSignal.recoverManual)),
          reason: 'once latched, ambiguous frames must not surface the manual '
              'escape',
        );
        expect(
          signals,
          contains(HuntSignal.backCaptureReady),
          reason: 'the latched back fires on pure stability via the same path '
              'as the front',
        );
        expect(machine.phase, HuntPhase.extractingBack);
      });

      test('SAFETY: while every frame still reads FRONT (never flipped) the '
          'back NEVER latches and NEVER emits backCaptureReady', () {
        // The wrong-side invariant (#5457/#5484): if the user has NOT flipped,
        // the front anchors keep matching and detectedSide stays `front`. The
        // latch entry must require detectedSide != front, so the back never
        // commits and never auto-captures the front again.
        final machine = HuntStateMachine(
          idleFramesThreshold: 6,
          fastAdvanceThreshold: 3,
          minFieldsForFastAdvance: 4,
          minFieldsForStableCapture: 4,
          backCompleteFieldsCount: 19,
        );
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        final signals = <HuntSignal>[
          for (var i = 0; i < 10; i++)
            machine.recordFrame(
              detectedSide: DocumentSide.front,
              addedNewField: false,
              filledFields: 11,
            ),
        ];
        expect(signals, isNot(contains(HuntSignal.backCaptureReady)));
        expect(
          machine.phase,
          isNot(HuntPhase.extractingBack),
          reason: 'showing the front must never latch the back',
        );
        // Still surfaces the manual fallback so the user is never stranded.
        expect(signals, contains(HuntSignal.recoverManual));
      });

      test('SAFETY: a flipped frame still BELOW the floor does NOT latch '
          '(near-empty view is not a stabilized document)', () {
        // The latch entry requires floorMet as well as side-safe. A flipped
        // but data-starved view must not commit the back.
        final machine = HuntStateMachine(
          idleFramesThreshold: 3,
          minFieldsForStableCapture: 4,
        );
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        machine.recordFrame(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 2,
        );
        expect(
          machine.phase,
          HuntPhase.waitingBack,
          reason: 'below the floor the back must stay waiting, not latch',
        );
        machine.recordFrame(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 2,
        );
        final signal = machine.recordFrame(
          detectedSide: DocumentSide.unknown,
          addedNewField: false,
          filledFields: 2,
        );
        expect(signal, HuntSignal.recoverManual);
      });
    });

    test('advanceToDone moves to done phase', () {
      final machine = HuntStateMachine();
      _seedFrontPhaseComplete(machine);
      machine.advanceToWaitingBack();
      _seedBackPhaseComplete(machine);
      machine.advanceToDone();
      expect(machine.phase, HuntPhase.done);
    });

    test('reset returns machine to waitingFront', () {
      final machine = HuntStateMachine();
      _seedFrontPhaseComplete(machine);
      machine.advanceToWaitingBack();
      machine.reset();
      expect(machine.phase, HuntPhase.waitingFront);
    });

    group('completeness fast-path (per side)', () {
      test('fires frontCaptureReady when all FRONT-side selected fields are '
          'filled, even though the full selection is larger', () {
        final machine = HuntStateMachine(
          frontCompleteFieldsCount: 6,
          backCompleteFieldsCount: 7,
        );
        _seedFrontPhaseComplete(machine);
        final signal = machine.recordFrame(
          detectedSide: DocumentSide.front,
          addedNewField: true,
          filledFields: 6,
        );
        expect(signal, HuntSignal.frontCaptureReady);
      });

      test('fires backCaptureReady when the back-phase threshold is met', () {
        final machine = HuntStateMachine(
          frontCompleteFieldsCount: 6,
          backCompleteFieldsCount: 7,
        );
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();
        _seedBackPhaseComplete(machine);
        final signal = machine.recordFrame(
          detectedSide: DocumentSide.back,
          addedNewField: true,
          filledFields: 7,
        );
        expect(signal, HuntSignal.backCaptureReady);
      });

      test('still waits for idle frames while the front side is incomplete',
          () {
        final machine = HuntStateMachine(
          frontCompleteFieldsCount: 6,
          backCompleteFieldsCount: 7,
        );
        _seedFrontPhaseComplete(machine);
        final signal = machine.recordFrame(
          detectedSide: DocumentSide.front,
          addedNewField: true,
          filledFields: 5,
        );
        expect(signal, HuntSignal.none);
      });

      test('without per-side counts the fast-path is disabled', () {
        final machine = HuntStateMachine();
        _seedFrontPhaseComplete(machine);
        final signal = machine.recordFrame(
          detectedSide: DocumentSide.front,
          addedNewField: true,
          filledFields: 19,
        );
        expect(signal, HuntSignal.none);
      });
    });

    group('real detect() -> recordFrame seam (#5498 blind spot)', () {
      // The unit tests above feed detectedSide DIRECTLY, which is exactly what
      // hid the device bug: they never drive the REAL DocumentSideDetector.
      // These tests compute detectedSide through the production detector from
      // realistic OCR text, then feed THAT into the state machine — the live
      // path (dni_scanner.dart:384 -> :391) the isolated unit tests bypass.
      const detector = DocumentSideDetector();

      test('a realistic BACK frame computed through the REAL detector latches '
          'into extractingBack and emits backCaptureReady (NOT recoverManual)',
          () {
        // Device-truth back OCR: the back prints the DNI number near the MRZ,
        // plus Grupo de Votación and an address, but NO front title block and
        // NO clean CONSTANCIA/DONACIÓN anchor. Through the corrected detector
        // this resolves to NOT front, so the back latch can finally fire.
        const backText =
            'Grupo de Votación 083966\n'
            'Dirección AMPLC. TUPAC AMARU SICUANI 215\n'
            'DNI 71542895\n'
            'I<PER7154289<<<<<<<<<<<<<<<';
        final detectedSide = detector.detect(backText);
        expect(
          detectedSide,
          isNot(DocumentSide.front),
          reason: 'the realistic back must not read as front through the real '
              'detector — this is the root-cause gate (#5498)',
        );

        final machine = HuntStateMachine(
          idleFramesThreshold: 6,
          fastAdvanceThreshold: 3,
          minFieldsForFastAdvance: 4,
          minFieldsForStableCapture: 4,
          backCompleteFieldsCount: 19,
        );
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();

        // First genuine flipped frame (computed via the real detector) latches.
        machine.recordFrame(
          detectedSide: detectedSide,
          addedNewField: false,
          filledFields: 11,
        );
        expect(
          machine.phase,
          HuntPhase.extractingBack,
          reason: 'a back frame computed through the real detector must latch '
              'the back, not stay stranded in waitingBack',
        );

        // Subsequent stable frames fire on pure stability through the same
        // path as the front — reaching the counter, never the manual escape.
        final signals = <HuntSignal>[
          for (var i = 0; i < 6; i++)
            machine.recordFrame(
              detectedSide: detector.detect(backText),
              addedNewField: false,
              filledFields: 11,
            ),
        ];
        expect(signals, contains(HuntSignal.backCaptureReady));
        expect(signals, isNot(contains(HuntSignal.recoverManual)));
      });

      test('SAFETY: a genuine FRONT frame computed through the REAL detector '
          'never latches the back (wrong-side invariant #5457/#5484)', () {
        // The front title block is present, so the real detector returns front
        // every frame; the back must never latch and never auto-capture while
        // the user is still showing the front.
        const frontText =
            'REPÚBLICA DEL PERÚ\n'
            'DOCUMENTO NACIONAL DE IDENTIDAD\n'
            'GOICOCHEA PEREZ ODETTE\n'
            'DNI 71542895';
        expect(detector.detect(frontText), DocumentSide.front);

        final machine = HuntStateMachine(
          idleFramesThreshold: 6,
          fastAdvanceThreshold: 3,
          minFieldsForFastAdvance: 4,
          minFieldsForStableCapture: 4,
          backCompleteFieldsCount: 19,
        );
        _seedFrontPhaseComplete(machine);
        machine.advanceToWaitingBack();

        final signals = <HuntSignal>[
          for (var i = 0; i < 10; i++)
            machine.recordFrame(
              detectedSide: detector.detect(frontText),
              addedNewField: false,
              filledFields: 11,
            ),
        ];
        expect(signals, isNot(contains(HuntSignal.backCaptureReady)));
        expect(machine.phase, isNot(HuntPhase.extractingBack));
      });
    });
  });
}

void _seedFrontPhaseComplete(HuntStateMachine machine) {
  machine.recordFrame(
    detectedSide: DocumentSide.front,
    addedNewField: false,
  );
}

void _seedBackPhaseComplete(HuntStateMachine machine) {
  machine.recordFrame(
    detectedSide: DocumentSide.back,
    addedNewField: false,
  );
}
