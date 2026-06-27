// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';

import 'package:dni_peru_ocr/src/presentation/document_validator.dart';
import 'package:dni_peru_ocr/src/presentation/orchestrators/dni_capture_state.dart';
import 'package:dni_peru_ocr/src/presentation/orchestrators/dni_capture_orchestrator.dart';

// ─── Test helpers ─────────────────────────────────────────────────────────────

DniCaptureOrchestrator _orchestrator({
  int autoCaptureMs = 1500,
  int gracePeriodMs = 600,
  int manualFallbackMs = 15000,
  int minStableFrames = 2,
}) =>
    DniCaptureOrchestrator(
      autoCaptureMs: autoCaptureMs,
      gracePeriodMs: gracePeriodMs,
      manualFallbackMs: manualFallbackMs,
      minStableFrames: minStableFrames,
    );

/// Minimal fake that surfaces only [isCaptureable] without touching ML Kit.
/// Uses the `@visibleForTesting` named constructor added to
/// [DocumentValidationResult] for test isolation.
DocumentValidationResult _fakeResult({required bool isCaptureable}) =>
    DocumentValidationResult.forTest(isCaptureable: isCaptureable);

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);

  // ── Sealed state model ────────────────────────────────────────────────────

  group('Sealed state model', () {
    test('DniCaptureScanning.isCaptureable is always false', () {
      const s = DniCaptureScanning(
        guideText: 'Posiciona tu documento',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );
      expect(s.isCaptureable, isFalse);
      expect(s.manualModeActive, isFalse);
    });

    test('DniCaptureCountingDown.progress is computed from elapsed/total', () {
      const s = DniCaptureCountingDown(
        guideText: '¡Perfecto!',
        elapsedMs: 750,
        totalMs: 1500,
      );
      expect(s.progress, closeTo(0.5, 0.001));
    });

    test('DniCaptureCountingDown.progress clamps at 1.0 when elapsed > total',
        () {
      const s = DniCaptureCountingDown(
        guideText: '¡Perfecto!',
        elapsedMs: 2000,
        totalMs: 1500,
      );
      expect(s.progress, closeTo(1.0, 0.001));
    });

    test('DniCaptureInFlight carries showFlash', () {
      const s = DniCaptureInFlight(showFlash: true);
      expect(s.showFlash, isTrue);
    });

    test('DniCaptureExpired carries expirationDate', () {
      final d = DateTime(2020, 3, 15);
      final s = DniCaptureExpired(d);
      expect(s.expirationDate, equals(d));
    });

    test('DniCaptureDone is a valid sealed subtype', () {
      // Exhaustive switch over the sealed hierarchy: if DniCaptureDone ever
      // stops being a subtype of DniCaptureState, this stops compiling.
      const DniCaptureState s = DniCaptureDone();
      final tag = switch (s) {
        DniCaptureScanning() => 'scanning',
        DniCaptureCountingDown() => 'countingDown',
        DniCaptureInFlight() => 'inFlight',
        DniCaptureExpired() => 'expired',
        DniCaptureDone() => 'done',
      };
      expect(tag, equals('done'));
    });
  });

  // ── Happy countdown path ──────────────────────────────────────────────────

  group('Happy countdown path', () {
    late DniCaptureOrchestrator orc;

    setUp(() => orc = _orchestrator(autoCaptureMs: 1500, minStableFrames: 2));

    test('scanning → scanning when not captureable', () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: 'min_blocks',
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final next = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: false),
        stableFrames: 1,
        userDataMatch: null,
        now: t0,
      );

      expect(next, isA<DniCaptureScanning>());
    });

    test('scanning → countingDown when captureable + stable frames met', () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final next = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        userDataMatch: null,
        now: t0,
      );

      expect(
        next,
        isA<DniCaptureCountingDown>()
            .having((c) => c.elapsedMs, 'elapsedMs', equals(0))
            .having((c) => c.totalMs, 'totalMs', equals(1500)),
      );
    });

    test('countingDown → countingDown with growing elapsed', () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final afterFirst = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
      );
      expect(afterFirst, isA<DniCaptureCountingDown>());

      final t500 = t0.add(const Duration(milliseconds: 500));
      final afterSecond = orc.onFrame(
        current: afterFirst,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t500,
        userDataMatch: null,
      );

      expect(
        afterSecond,
        isA<DniCaptureCountingDown>().having(
          (c) => c.elapsedMs,
          'elapsedMs',
          greaterThanOrEqualTo(500),
        ),
      );
    });

    test('countingDown → inFlight at autoCaptureMs', () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final counting = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
      );

      final tCapture = t0.add(const Duration(milliseconds: 1500));
      final result = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tCapture,
        userDataMatch: null,
      );

      expect(result, isA<DniCaptureInFlight>());
    });

    test(
        'insufficient stable frames: scanning stays scanning even when captureable',
        () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final next = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 1, // < minStableFrames
        now: t0,
        userDataMatch: null,
      );

      expect(next, isA<DniCaptureScanning>());
    });
  });

  // ── Countdown reset on quality regression ────────────────────────────────

  group('Countdown reset on quality regression', () {
    late DniCaptureOrchestrator orc;

    setUp(() => orc = _orchestrator(
          autoCaptureMs: 1500,
          gracePeriodMs: 600,
          minStableFrames: 2,
        ));

    DniCaptureCountingDown startCounting(DniCaptureOrchestrator o) {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );
      return o.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
      ) as DniCaptureCountingDown;
    }

    test('regression within grace period keeps countingDown', () {
      final counting = startCounting(orc);

      final tGrace = t0.add(const Duration(milliseconds: 300)); // < 600ms
      final next = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: false),
        stableFrames: 0,
        now: tGrace,
        userDataMatch: null,
      );

      expect(next, isA<DniCaptureCountingDown>());
    });

    test('regression sustained beyond grace period resets to scanning', () {
      final counting = startCounting(orc);

      // The disturbance must be CONTINUOUS to abort (#5532): a first bad frame
      // starts it, a second bad frame past the grace window aborts.
      final tStart = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: false),
        stableFrames: 0,
        now: t0.add(const Duration(milliseconds: 50)),
        userDataMatch: null,
      );
      expect(tStart, isA<DniCaptureCountingDown>());

      final tBeyond = t0.add(const Duration(milliseconds: 700)); // > 600ms
      final next = orc.onFrame(
        current: tStart,
        validation: _fakeResult(isCaptureable: false),
        stableFrames: 0,
        now: tBeyond,
        userDataMatch: null,
      );

      expect(next, isA<DniCaptureScanning>());
    });

    test('reset countdown does NOT trigger capture on late frame', () {
      final counting = startCounting(orc);

      final disturbed = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: false),
        stableFrames: 0,
        now: t0.add(const Duration(milliseconds: 50)),
        userDataMatch: null,
      );
      final tBeyond = t0.add(const Duration(milliseconds: 700));
      final scanning = orc.onFrame(
        current: disturbed,
        validation: _fakeResult(isCaptureable: false),
        stableFrames: 0,
        now: tBeyond,
        userDataMatch: null,
      );
      expect(scanning, isA<DniCaptureScanning>());

      // Even at t0 + 1500ms (would have triggered), scanning stays scanning
      final tLate = t0.add(const Duration(milliseconds: 1500));
      final afterLate = orc.onFrame(
        current: scanning,
        validation: _fakeResult(isCaptureable: false),
        stableFrames: 0,
        now: tLate,
        userDataMatch: null,
      );
      expect(afterLate, isA<DniCaptureScanning>());
      expect(afterLate, isNot(isA<DniCaptureInFlight>()));
    });
  });

  // ── Intermittent disturbance does not stall the countdown (#5532) ─────────

  // The device-confirmed back hang: the reverso reached backCaptureReady but
  // its 3s countdown never completed (dwell climbed 125+). Root cause — the
  // grace window was measured against TOTAL elapsed progress, so once the
  // countdown passed gracePeriodMs a SINGLE non-hold frame (handheld micro-
  // jitter, which never stops on a real phone) reset the whole countdown. With
  // autoCaptureMs(3000) >> gracePeriodMs(600) the back looped 0→600→reset
  // forever and never fired. The fix measures the DISTURBANCE DURATION
  // (continuous broken-hold time): a brief jitter pauses the countdown but only
  // a disturbance that itself spans > gracePeriodMs resets it.
  group('Intermittent disturbance keeps countdown alive (#5532)', () {
    late DniCaptureOrchestrator orc;

    setUp(() => orc = _orchestrator(
          autoCaptureMs: 3000,
          gracePeriodMs: 600,
          minStableFrames: 2,
        ));

    CountingDownWithAnchor startCounting() {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );
      return orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        imuStill: true,
      ) as CountingDownWithAnchor;
    }

    test(
        'a single jitter frame past the grace mark does NOT reset — the '
        'disturbance only just started (was the back-hang reset bug)', () {
      final counting = startCounting();

      // Countdown has progressed well past gracePeriodMs (1000ms > 600ms).
      // A single not-still frame (jitter) lands here. Under the OLD elapsed-
      // based grace this reset to scanning; under the disturbance-duration
      // model the disturbance has lasted 0ms, so it must stay counting.
      final tJitter = t0.add(const Duration(milliseconds: 1000));
      final next = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tJitter,
        userDataMatch: null,
        imuStill: false,
      );

      expect(
        next,
        isA<CountingDownWithAnchor>().having(
          (c) => c.perfectSinceEpochMs,
          'perfectSinceEpochMs',
          equals(counting.perfectSinceEpochMs),
        ),
        reason: 'a brief jitter mid-countdown must pause, not nuke, the dwell',
      );
    });

    test(
        'intermittent jitter throughout the dwell still reaches inFlight at '
        'autoCaptureMs (the textless back must complete despite handheld '
        'micro-jitter)', () {
      var state = startCounting() as DniCaptureState;

      // Walk the full 3s dwell at 100ms steps, flapping imuStill exactly like a
      // handheld phone: still 3 frames, jitter 1 frame, repeated. Each
      // individual jitter is a single 100ms frame (< 600ms grace), so the hold
      // is never CONTINUOUSLY broken past the grace window.
      DniCaptureState? fired;
      for (var ms = 100; ms <= 3000; ms += 100) {
        final still = (ms ~/ 100) % 4 != 0;
        state = orc.onFrame(
          current: state,
          validation: _fakeResult(isCaptureable: true),
          stableFrames: 2,
          now: t0.add(Duration(milliseconds: ms)),
          userDataMatch: null,
          imuStill: still,
        );
        if (state is DniCaptureInFlight) {
          fired = state;
          break;
        }
        // It must never collapse back to scanning on a brief jitter.
        expect(
          state,
          isA<CountingDownWithAnchor>(),
          reason: 'intermittent jitter reset the countdown at ms=$ms — the '
              'device back-hang bug',
        );
      }

      expect(
        fired,
        isA<DniCaptureInFlight>(),
        reason: 'the dwell must fire despite intermittent handheld jitter; it '
            'hung forever before the disturbance-duration fix',
      );
    });

    test(
        'a CONTINUOUS disturbance that itself spans the grace window still '
        'resets to scanning (real loss of framing/hold must abort)', () {
      final counting = startCounting();

      // Disturbance starts at t+200 and is sustained across consecutive frames.
      final tStart = t0.add(const Duration(milliseconds: 200));
      final disturbed = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tStart,
        userDataMatch: null,
        imuStill: false,
      );
      expect(disturbed, isA<CountingDownWithAnchor>());

      // Still disturbed 700ms after the disturbance BEGAN (> 600ms grace).
      final tBeyond = t0.add(const Duration(milliseconds: 900));
      final next = orc.onFrame(
        current: disturbed,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tBeyond,
        userDataMatch: null,
        imuStill: false,
      );

      expect(
        next,
        isA<DniCaptureScanning>(),
        reason: 'a sustained disturbance past the grace window must still abort',
      );
    });

    test(
        'recovering the hold before the disturbance grace elapses clears the '
        'disturbance so a later jitter gets a fresh grace window', () {
      final counting = startCounting();

      // Brief disturbance at t+200 (just started).
      final dist1 = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0.add(const Duration(milliseconds: 200)),
        userDataMatch: null,
        imuStill: false,
      );
      expect(dist1, isA<CountingDownWithAnchor>());

      // Hold recovers at t+300 — disturbance cleared.
      final recovered = orc.onFrame(
        current: dist1,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0.add(const Duration(milliseconds: 300)),
        userDataMatch: null,
        imuStill: true,
      );
      expect(recovered, isA<CountingDownWithAnchor>());

      // A NEW single jitter much later (t+2000) must NOT instantly reset: the
      // earlier disturbance was cleared, so this one's grace window is fresh.
      final dist2 = orc.onFrame(
        current: recovered,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0.add(const Duration(milliseconds: 2000)),
        userDataMatch: null,
        imuStill: false,
      );
      expect(
        dist2,
        isA<CountingDownWithAnchor>(),
        reason: 'a fresh isolated jitter after recovery must not reset',
      );
    });
  });

  // ── Manual fallback ───────────────────────────────────────────────────────

  group('Manual fallback transition', () {
    late DniCaptureOrchestrator orc;

    setUp(() => orc = _orchestrator());

    test('onManualFallbackTimeout sets manualModeActive = true', () {
      const initial = DniCaptureScanning(
        guideText: 'Posiciona tu documento en el recuadro',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final result = orc.onManualFallbackTimeout(initial);

      expect(
        result,
        isA<DniCaptureScanning>()
            .having((s) => s.manualModeActive, 'manualModeActive', isTrue),
      );
    });

    test('onManualFallbackTimeout is no-op on non-scanning states', () {
      const inFlight = DniCaptureInFlight(showFlash: false);
      expect(orc.onManualFallbackTimeout(inFlight), same(inFlight));

      const done = DniCaptureDone();
      expect(orc.onManualFallbackTimeout(done), same(done));
    });

    test('scanning with manualModeActive stays scanning when not captureable',
        () {
      final scanning = DniCaptureScanning(
        guideText: 'Toca el botón para capturar',
        failingGate: 'tilt',
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: true,
      );

      final next = orc.onFrame(
        current: scanning,
        validation: _fakeResult(isCaptureable: false),
        stableFrames: 0,
        now: t0,
        userDataMatch: null,
      );

      expect(
        next,
        isA<DniCaptureScanning>()
            .having((s) => s.manualModeActive, 'manualModeActive', isTrue),
      );
    });
  });

  // ── Side toggle ───────────────────────────────────────────────────────────

  group('Side toggle', () {
    late DniCaptureOrchestrator orc;

    setUp(() => orc = _orchestrator());

    test('onSideToggle from countingDown resets to scanning', () {
      const counting = DniCaptureCountingDown(
        guideText: '¡Perfecto!',
        elapsedMs: 800,
        totalMs: 1500,
      );

      final result = orc.onSideToggle(counting);

      expect(
        result,
        isA<DniCaptureScanning>()
            .having((s) => s.manualModeActive, 'manualModeActive', isFalse)
            .having((s) => s.stableFrames, 'stableFrames', equals(0)),
      );
    });

    test('onSideToggle from scanning with manual mode clears manual mode', () {
      final scanning = DniCaptureScanning(
        guideText: 'Toca el botón',
        failingGate: null,
        validationProgress: 0.3,
        stableFrames: 5,
        userDataMatch: true,
        manualModeActive: true,
      );

      final result = orc.onSideToggle(scanning);

      expect(
        result,
        isA<DniCaptureScanning>()
            .having((s) => s.manualModeActive, 'manualModeActive', isFalse)
            .having((s) => s.stableFrames, 'stableFrames', equals(0))
            .having((s) => s.validationProgress, 'validationProgress', equals(0)),
      );
    });
  });

  // ── IMU stillness gate ────────────────────────────────────────────────────

  group('IMU jolt-reset (not an entry gate)', () {
    late DniCaptureOrchestrator orc;

    setUp(() => orc = _orchestrator(
          autoCaptureMs: 1500,
          gracePeriodMs: 600,
          minStableFrames: 2,
        ));

    test('imuStill false does NOT block countdown entry when captureable', () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final next = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        imuStill: false,
      );

      expect(next, isA<DniCaptureCountingDown>());
    });

    test('countdown enters regardless of imuStill when framing and frames met',
        () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final stillEntry = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        imuStill: true,
      );
      final joltEntry = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        imuStill: false,
      );

      expect(stillEntry, isA<DniCaptureCountingDown>());
      expect(joltEntry, isA<DniCaptureCountingDown>());
    });

    test('imuStill defaults to true so legacy call sites keep counting down',
        () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final next = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
      );

      expect(next, isA<DniCaptureCountingDown>());
    });

    CountingDownWithAnchor startCounting() {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );
      return orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        imuStill: true,
      ) as CountingDownWithAnchor;
    }

    test('a jolt within grace period keeps the countdown anchor', () {
      final counting = startCounting();

      final tGrace = t0.add(const Duration(milliseconds: 300));
      final next = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tGrace,
        userDataMatch: null,
        imuStill: false,
      );

      expect(
        next,
        isA<CountingDownWithAnchor>().having(
          (c) => c.perfectSinceEpochMs,
          'perfectSinceEpochMs',
          equals(counting.perfectSinceEpochMs),
        ),
      );
    });

    test('a sustained jolt beyond grace period resets to scanning', () {
      final counting = startCounting();

      // A continuous jolt (#5532): a first not-still frame begins the
      // disturbance, a second not-still frame past the grace window aborts.
      final jolted = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0.add(const Duration(milliseconds: 50)),
        userDataMatch: null,
        imuStill: false,
      );
      expect(jolted, isA<DniCaptureCountingDown>());

      final tBeyond = t0.add(const Duration(milliseconds: 700));
      final next = orc.onFrame(
        current: jolted,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tBeyond,
        userDataMatch: null,
        imuStill: false,
      );

      expect(next, isA<DniCaptureScanning>());
    });

    test('steady hand reaches inFlight even though entry never needed imuStill',
        () {
      final counting = startCounting();

      final tCapture = t0.add(const Duration(milliseconds: 1500));
      final result = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tCapture,
        userDataMatch: null,
        imuStill: true,
      );

      expect(result, isA<DniCaptureInFlight>());
    });
  });

  // ── Lighting gate ─────────────────────────────────────────────────────────

  group('Lighting gate', () {
    late DniCaptureOrchestrator orc;

    setUp(() => orc = _orchestrator(
          autoCaptureMs: 1500,
          gracePeriodMs: 600,
          minStableFrames: 2,
        ));

    test('lightingValid false blocks countdown entry even when captureable',
        () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final next = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        lightingValid: false,
      );

      expect(next, isA<DniCaptureScanning>());
    });

    test('lightingValid true allows countdown entry when captureable', () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final next = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        lightingValid: true,
      );

      expect(next, isA<DniCaptureCountingDown>());
    });

    test('lightingValid defaults to true so legacy call sites keep counting',
        () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final next = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
      );

      expect(next, isA<DniCaptureCountingDown>());
    });

    CountingDownWithAnchor startCounting() {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );
      return orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        lightingValid: true,
      ) as CountingDownWithAnchor;
    }

    test('glare within grace period keeps the countdown anchor', () {
      final counting = startCounting();

      final tGrace = t0.add(const Duration(milliseconds: 300));
      final next = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tGrace,
        userDataMatch: null,
        lightingValid: false,
      );

      expect(
        next,
        isA<CountingDownWithAnchor>().having(
          (c) => c.perfectSinceEpochMs,
          'perfectSinceEpochMs',
          equals(counting.perfectSinceEpochMs),
        ),
      );
    });

    test('sustained bad lighting beyond grace period resets to scanning', () {
      final counting = startCounting();

      // Continuous bad lighting (#5532): begins on a first bad frame, aborts on
      // a second bad frame past the grace window.
      final dim = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0.add(const Duration(milliseconds: 50)),
        userDataMatch: null,
        lightingValid: false,
      );
      expect(dim, isA<DniCaptureCountingDown>());

      final tBeyond = t0.add(const Duration(milliseconds: 700));
      final next = orc.onFrame(
        current: dim,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tBeyond,
        userDataMatch: null,
        lightingValid: false,
      );

      expect(next, isA<DniCaptureScanning>());
    });

    test('lighting gates entry but a jolt at entry does not', () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final blockedByLighting = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        imuStill: false,
        lightingValid: false,
      );
      final entersDespiteJolt = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        imuStill: false,
        lightingValid: true,
      );

      expect(blockedByLighting, isA<DniCaptureScanning>());
      expect(entersDespiteJolt, isA<DniCaptureCountingDown>());
    });
  });

  // ── Quad framing gate ─────────────────────────────────────────────────────

  group('Quad framing gate', () {
    late DniCaptureOrchestrator orc;

    setUp(() => orc = _orchestrator(
          autoCaptureMs: 1500,
          gracePeriodMs: 600,
          minStableFrames: 2,
        ));

    const initial = DniCaptureScanning(
      guideText: '',
      failingGate: null,
      validationProgress: 0,
      stableFrames: 0,
      userDataMatch: null,
      manualModeActive: false,
    );

    test('framingValid true allows countdown entry when captureable', () {
      final next = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        framingValid: true,
      );

      expect(next, isA<DniCaptureCountingDown>());
    });

    test('framingValid false blocks countdown entry even when captureable', () {
      final next = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        framingValid: false,
      );

      expect(next, isA<DniCaptureScanning>());
    });

    test('framingValid defaults to true so legacy call sites keep counting',
        () {
      final next = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
      );

      expect(next, isA<DniCaptureCountingDown>());
    });

    test(
        'wrong-side safety: framingValid true cannot override a non-captureable '
        'validation (preserves OCR-block side gate)', () {
      // The OCR-block side gate (DocumentValidator sideMismatch / the
      // HuntStateMachine wrong-side latch) surfaces here as isCaptureable=false.
      // Quad framing MUST NOT bypass it: a confident quad on the wrong side
      // still must not auto-capture (#5457/#5484/#5499).
      final next = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: false),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        framingValid: true,
      );

      expect(next, isA<DniCaptureScanning>());
    });

    CountingDownWithAnchor startCounting() {
      return orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        framingValid: true,
      ) as CountingDownWithAnchor;
    }

    test('quad flap to false within grace period keeps the countdown anchor',
        () {
      final counting = startCounting();

      final tGrace = t0.add(const Duration(milliseconds: 300)); // < 600ms
      final next = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tGrace,
        userDataMatch: null,
        framingValid: false,
      );

      expect(
        next,
        isA<CountingDownWithAnchor>().having(
          (c) => c.perfectSinceEpochMs,
          'perfectSinceEpochMs',
          equals(counting.perfectSinceEpochMs),
        ),
      );
    });

    test('quad flap true→false→true within grace does NOT reset the countdown',
        () {
      final counting = startCounting();

      // Brief drop mid-dwell, still inside the grace window.
      final tDrop = t0.add(const Duration(milliseconds: 200));
      final afterDrop = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tDrop,
        userDataMatch: null,
        framingValid: false,
      );
      expect(afterDrop, isA<CountingDownWithAnchor>());

      // Quad recovers within grace — same anchor must survive.
      final tRecover = t0.add(const Duration(milliseconds: 400));
      final afterRecover = orc.onFrame(
        current: afterDrop,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tRecover,
        userDataMatch: null,
        framingValid: true,
      );

      expect(
        afterRecover,
        isA<CountingDownWithAnchor>().having(
          (c) => c.perfectSinceEpochMs,
          'perfectSinceEpochMs',
          equals(counting.perfectSinceEpochMs),
        ),
      );
    });

    test('sustained quad loss beyond grace period resets to scanning', () {
      final counting = startCounting();

      // Continuous quad loss (#5532): begins on a first lost frame, aborts on a
      // second lost frame past the grace window. A brief blip alone never
      // resets (covered by the flap-within-grace tests above).
      final lost = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0.add(const Duration(milliseconds: 50)),
        userDataMatch: null,
        framingValid: false,
      );
      expect(lost, isA<DniCaptureCountingDown>());

      final tBeyond = t0.add(const Duration(milliseconds: 700)); // > 600ms
      final next = orc.onFrame(
        current: lost,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tBeyond,
        userDataMatch: null,
        framingValid: false,
      );

      expect(next, isA<DniCaptureScanning>());
    });

    test('steady quad framing reaches inFlight at autoCaptureMs', () {
      final counting = startCounting();

      final tCapture = t0.add(const Duration(milliseconds: 1500));
      final result = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tCapture,
        userDataMatch: null,
        framingValid: true,
      );

      expect(result, isA<DniCaptureInFlight>());
    });

    test('framing gates entry independently of lighting and imu', () {
      // Quad invalid blocks even with perfect lighting + stillness.
      final blockedByFraming = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        framingValid: false,
        lightingValid: true,
        imuStill: true,
      );
      // Quad valid enters even with a jolt at entry (imu is hold-only).
      final entersDespiteJolt = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
        framingValid: true,
        lightingValid: true,
        imuStill: false,
      );

      expect(blockedByFraming, isA<DniCaptureScanning>());
      expect(entersDespiteJolt, isA<DniCaptureCountingDown>());
    });
  });

  // ── Clock-skew edge cases ─────────────────────────────────────────────────

  group('Clock-skew edge cases', () {
    late DniCaptureOrchestrator orc;

    setUp(() => orc = _orchestrator(autoCaptureMs: 1500));

    test('backward clock keeps countingDown with non-negative elapsedMs', () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final counting = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
      );
      expect(counting, isA<DniCaptureCountingDown>());

      final tBackward = t0.subtract(const Duration(milliseconds: 200));
      final result = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tBackward,
        userDataMatch: null,
      );

      expect(
        result,
        isA<DniCaptureCountingDown>().having(
          (c) => c.elapsedMs,
          'elapsedMs',
          greaterThanOrEqualTo(0),
        ),
      );
    });

    test('same timestamp gives elapsedMs = 0, does not trigger capture', () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final counting = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
      );

      final sameTs = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
      );

      expect(
        sameTs,
        isA<DniCaptureCountingDown>()
            .having((c) => c.elapsedMs, 'elapsedMs', equals(0)),
      );
    });

    test('large clock jump beyond autoCaptureMs triggers inFlight', () {
      const initial = DniCaptureScanning(
        guideText: '',
        failingGate: null,
        validationProgress: 0,
        stableFrames: 0,
        userDataMatch: null,
        manualModeActive: false,
      );

      final counting = orc.onFrame(
        current: initial,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: t0,
        userDataMatch: null,
      );

      // Big jump: 10 seconds — well past 1500ms threshold
      final tJump = t0.add(const Duration(seconds: 10));
      final result = orc.onFrame(
        current: counting,
        validation: _fakeResult(isCaptureable: true),
        stableFrames: 2,
        now: tJump,
        userDataMatch: null,
      );

      expect(result, isA<DniCaptureInFlight>());
    });
  });
}
